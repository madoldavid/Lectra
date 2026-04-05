import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import '../env.dart';
import '../backend/supabase/supabase.dart';
import 'local_model_service.dart';

class LectureNotesResult {
  const LectureNotesResult({
    required this.notes,
    required this.transcript,
  });

  final String notes;
  final String transcript;
}

class GeminiService {
  GeminiService();

  static const int _chunkChars = 3200;
  static const int _maxChunks = 40;
  String? _lastDebug;
  String? get lastDebug => _lastDebug;
  void _log(String msg) {
    _lastDebug = msg;
  }

  Future<LectureNotesResult> generateNotesFromAudio(String filePath) async {
    // In production we no longer send audio to Gemini from the client.
    // Transcription is local; notes structuring happens via the Supabase edge proxy.
    final transcript = await File(filePath).readAsString(); // placeholder if needed
    final notes = await generateNotes(transcript);
    return LectureNotesResult(notes: notes, transcript: transcript);
  }

  Future<String> generateNotes(String transcript) async {
    final cleanedTranscript = _prepareTranscript(transcript);
    if (cleanedTranscript.isEmpty) {
      _log('empty transcript');
      return '';
    }

    // Prefer on-device structuring if model is available.
    final localNotes =
        await LocalModelService.instance.structureLocally(cleanedTranscript);
    if (localNotes != null && localNotes.trim().isNotEmpty) {
      _log('local model produced notes');
      return _validateAndRepairNotes(
        raw: localNotes,
        transcript: cleanedTranscript,
      );
    }
    // Use anon key explicitly to avoid session-related 401s from edge function.
    final bearer = SupaFlow.anonKey;
    _log('using bearer len=${bearer.length}');

    // Chunked pipeline for long lectures to keep requests fast and avoid single huge calls.
    final chunks = _splitTranscript(cleanedTranscript);
    if (chunks.length > 1) {
      _log('chunking ${chunks.length} parts');
      if (chunks.length > _maxChunks) {
        // Too long to process safely; return raw to avoid blowing quotas/timeouts.
        _log('too many chunks (${chunks.length})');
        return _localStructuredFallback(cleanedTranscript);
      }
      final chunkNotes = <String>[];
      for (var i = 0; i < chunks.length; i++) {
        final note = await _structureChunkViaProxy(
          transcript: chunks[i],
          title: 'Lecture Part ${i + 1}/${chunks.length}',
          bearer: bearer,
        );
        if (note != null && note.trim().isNotEmpty) {
          chunkNotes.add(note.trim());
        } else {
          _log('chunk ${i + 1}/${chunks.length} returned empty');
        }
      }
      if (chunkNotes.isNotEmpty) {
        final merged = _mergeSectionNotes(chunkNotes, cleanedTranscript);
        if (merged.trim().isNotEmpty) {
          return merged;
        }
      }
      // If chunked calls failed, fall back to local raw transcript only to avoid a massive single request.
      _log('chunk merge empty -> fallback raw');
      return _localStructuredFallback(cleanedTranscript);
    }

    try {
      final res = await http.post(
        Uri.parse(notesProxyUrl),
        headers: {
          'Authorization': 'Bearer $bearer',
          'apikey': SupaFlow.anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'transcript': cleanedTranscript,
          'title': 'Lecture',
        }),
      );

      if (res.statusCode != 200) {
        _log('proxy status ${res.statusCode}: ${res.body}');
        return _localStructuredFallback(cleanedTranscript,
            reason: 'proxy status ${res.statusCode}');
      }
      final data = jsonDecode(res.body);
      final notes = (data['notes'] ?? '').toString().trim();
      if (notes.isEmpty) {
        _log('proxy empty body');
        return _localStructuredFallback(cleanedTranscript,
            reason: 'proxy empty');
      }
      return _validateAndRepairNotes(
        raw: notes,
        transcript: cleanedTranscript,
      );
    } catch (e) {
      _log('proxy exception $e');
      return _localStructuredFallback(cleanedTranscript,
          reason: 'proxy exception');
    }
  }

  String _prepareTranscript(String transcript) {
    final normalized = transcript
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return normalized;
  }

  Future<String> _validateAndRepairNotes({
    required String raw,
    required String transcript,
  }) async {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) {
      _log('validate: cleaned empty');
      return _localStructuredFallback(transcript,
          reason: 'validate cleaned empty');
    }
    if (_looksLikePromptReply(cleaned)) {
      _log('validate: looks like prompt reply');
      return _localStructuredFallback(transcript,
          reason: 'validate prompt reply');
    }

    final initialFinal = _finalizeNotes(
      _ensureSupplementalSection(cleaned),
      transcript,
    );
    if (_hasMinimumQuality(initialFinal)) {
      _log('validate: initial final accepted');
      return initialFinal;
    }

    try {
      final repaired = (await _repairViaProxy(
        transcript: transcript,
        draftNotes: cleaned,
      ))
          ?.trim();
      if (repaired != null &&
          repaired.isNotEmpty &&
          !_looksLikePromptReply(repaired) &&
          _hasCoreHeadings(repaired)) {
        final finalized = _finalizeNotes(
          _ensureSupplementalSection(repaired),
          transcript,
        );
        if (_hasMinimumQuality(finalized)) {
          _log('validate: repaired accepted');
          return finalized;
        } else {
          _log('validate: repaired low quality');
          return finalized;
        }
      }
    } catch (e) {
      _log('validate: repair exception $e');
      // Fallback below when repair is not possible.
    }

    // Return best-effort structured notes instead of dropping to raw transcript.
    _log('validate: returning initialFinal low quality');
    return initialFinal;
  }

  bool _looksLikePromptReply(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('please provide the transcript') ||
        normalized.contains('provide the transcript') ||
        normalized.contains('share the transcript') ||
        normalized.contains('send the transcript') ||
        normalized.contains('waiting for the transcript') ||
        normalized.contains("i'm ready") ||
        normalized.contains('i am ready');
  }

  bool _hasCoreHeadings(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('lecture summary') &&
        normalized.contains('main topics') &&
        normalized.contains('key definitions') &&
        normalized.contains('action items');
  }

  String _ensureSupplementalSection(String notes) {
    final normalized = notes.toLowerCase();
    if (normalized.contains('additional context (beyond recording)') ||
        normalized.contains('additional context') ||
        normalized.contains('supplemental context') ||
        normalized.contains('deep dive')) {
      return notes;
    }
    return [
      notes.trim(),
      '',
      '# Additional Context (Beyond Recording)',
      '- Evidence-based follow-ups and deeper reading:',
      '- Summarize how this topic links to prior lectures.',
      '- Suggested practice: create 3 questions testing the core ideas.',
      '- Note any assumptions, risks, or limitations mentioned.',
    ].join('\n');
  }

  // Proxy repair (fallback to local if proxy cannot be used)
  Future<String?> _repairViaProxy({
    required String transcript,
    required String draftNotes,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final token = supabase.auth.currentSession?.accessToken;
      final bearer = token ?? SupaFlow.anonKey;

      final res = await http.post(
        Uri.parse(notesProxyUrl),
        headers: {
          'Authorization': 'Bearer $bearer',
          'apikey': SupaFlow.anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'transcript': transcript,
          'title': 'Lecture',
          'draft': draftNotes,
        }),
      );
      if (res.statusCode != 200) {
        _log('repair proxy status ${res.statusCode}: ${res.body}');
        return null;
      }
      final data = jsonDecode(res.body);
      final notes = (data['notes'] ?? '').toString();
      if (notes.isEmpty) {
        _log('repair proxy empty body');
        return null;
      }
      return notes;
    } catch (e) {
      _log('repair proxy exception $e');
      return null;
    }
  }

  static const String _sectionSummary = 'lecture_summary';
  static const String _sectionTopics = 'main_topics';
  static const String _sectionDefinitions = 'key_definitions';
  static const String _sectionActions = 'action_items';
  static const String _sectionAdditional = 'additional_context';
  static const String _sectionQA = 'exam_questions';

  String _finalizeNotes(String notes, String transcript) {
    final sections = _parseSections(notes);
    final summary = sections[_sectionSummary] ?? <String>[];
    final topics = sections[_sectionTopics] ?? <String>[];
    final definitions = sections[_sectionDefinitions] ?? <String>[];
    final actions = sections[_sectionActions] ?? <String>[];
    final additional = sections[_sectionAdditional] ?? <String>[];

    final normalizedSummary = _normalizeSectionLines(summary);
    final normalizedTopics = _normalizeSectionLines(topics);
    final normalizedDefinitions = _normalizeDefinitionLines(definitions);
    final normalizedActions = _normalizeSectionLines(actions);
    final normalizedAdditional = _normalizeSectionLines(additional);
    final normalizedQA =
        _normalizeSectionLines(sections[_sectionQA] ?? const []);

    if (normalizedSummary.isEmpty) {
      normalizedSummary.add(_summaryFromTranscript(transcript));
    }

    final extractedTopics = _extractTopicBullets(transcript);
    while (normalizedTopics.length < 3 && extractedTopics.isNotEmpty) {
      final candidate = extractedTopics.removeAt(0);
      if (!normalizedTopics.contains(candidate)) {
        normalizedTopics.add(candidate);
      }
    }
    if (normalizedTopics.isEmpty) {
      normalizedTopics
          .add('Core lecture topics were captured from transcript.');
    }

    final extractedDefinitions = _extractDefinitionBullets(transcript);
    while (
        normalizedDefinitions.length < 2 && extractedDefinitions.isNotEmpty) {
      final candidate = extractedDefinitions.removeAt(0);
      if (!normalizedDefinitions.contains(candidate)) {
        normalizedDefinitions.add(candidate);
      }
    }
    if (normalizedDefinitions.isEmpty) {
      normalizedDefinitions.add(
        'Key term definitions were not confidently detected in transcript.',
      );
    }

    if (normalizedActions.isEmpty) {
      normalizedActions.addAll(_extractActionBullets(transcript));
    }
    if (normalizedActions.length < 3) {
      normalizedActions.addAll(
        _synthesizedActions(
          primaryTopic: normalizedTopics.isNotEmpty
              ? normalizedTopics.first
              : 'this lecture',
        ),
      );
    }
    // Deduplicate while preserving order.
    final seenAction = <String>{};
    final dedupedActions = <String>[];
    for (final a in normalizedActions) {
      final key = a.toLowerCase().trim();
      if (key.isEmpty || seenAction.contains(key)) continue;
      seenAction.add(key);
      dedupedActions.add(a);
    }
    normalizedActions
      ..clear()
      ..addAll(dedupedActions);

    if (normalizedAdditional.isEmpty) {
      normalizedAdditional.addAll(
        _additionalContextFromTopics(normalizedTopics),
      );
    }
    if (normalizedAdditional.length < 3) {
      normalizedAdditional.addAll(
        _enrichAdditionalContext(
          primaryTopic: normalizedTopics.isNotEmpty
              ? normalizedTopics.first
              : 'this lecture',
        ),
      );
    }
    final seenAddl = <String>{};
    final dedupedAddl = <String>[];
    for (final a in normalizedAdditional) {
      final key = a.toLowerCase().trim();
      if (key.isEmpty || seenAddl.contains(key)) continue;
      seenAddl.add(key);
      dedupedAddl.add(a);
    }
    normalizedAdditional
      ..clear()
      ..addAll(dedupedAddl);

    if (normalizedQA.length < 3) {
      normalizedQA.addAll(
        _generateQAFromContext(
          primaryTopic: normalizedTopics.isNotEmpty
              ? normalizedTopics.first
              : 'this lecture',
        ),
      );
    }
    final seenQA = <String>{};
    final dedupedQA = <String>[];
    for (final q in normalizedQA) {
      final key = q.toLowerCase().trim();
      if (key.isEmpty || seenQA.contains(key)) continue;
      seenQA.add(key);
      dedupedQA.add(q);
    }
    normalizedQA
      ..clear()
      ..addAll(dedupedQA.take(6));

    String sectionMarkdown(String heading, List<String> lines) {
      final nonEmpty = lines
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (nonEmpty.isEmpty) {
        return '# $heading\n- Not available.';
      }
      final bullets = nonEmpty.map((line) => '- $line').join('\n');
      return '# $heading\n$bullets';
    }

    return [
      sectionMarkdown('Lecture Summary', normalizedSummary.take(2).toList()),
      '',
      sectionMarkdown('Main Topics', normalizedTopics.take(6).toList()),
      '',
      sectionMarkdown(
          'Key Definitions', normalizedDefinitions.take(6).toList()),
      '',
      sectionMarkdown('Action Items', normalizedActions.take(5).toList()),
      '',
      sectionMarkdown(
        'Additional Context (Beyond Recording)',
        normalizedAdditional.take(5).toList(),
      ),
      '',
      sectionMarkdown(
        'Exam / Interview Questions',
        normalizedQA.take(6).toList(),
      ),
    ].join('\n');
  }

  Map<String, List<String>> _parseSections(String notes) {
    final map = <String, List<String>>{};
    String? currentSection;
    for (final rawLine in notes.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final headingMatch = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        currentSection = _canonicalSection(headingMatch.group(1) ?? '');
        if (currentSection != null) {
          map.putIfAbsent(currentSection, () => <String>[]);
        }
        continue;
      }
      if (currentSection == null) {
        continue;
      }
      map.putIfAbsent(currentSection, () => <String>[]).add(line);
    }
    return map;
  }

  String? _canonicalSection(String heading) {
    final normalized = heading.toLowerCase().trim();
    if (normalized.contains('lecture summary') || normalized == 'summary') {
      return _sectionSummary;
    }
    if (normalized.contains('main topic') ||
        (normalized.contains('topic') && !normalized.contains('additional'))) {
      return _sectionTopics;
    }
    if (normalized.contains('key definition') ||
        normalized.contains('definition')) {
      return _sectionDefinitions;
    }
    if (normalized.contains('action item') ||
        normalized.contains('next step') ||
        normalized.contains('action')) {
      return _sectionActions;
    }
    if (normalized.contains('additional context') ||
        normalized.contains('beyond recording') ||
        normalized.contains('supplemental') ||
        normalized.contains('deep dive') ||
        normalized.contains('potential additional context')) {
      return _sectionAdditional;
    }
    return null;
  }

  List<String> _normalizeSectionLines(List<String> lines) {
    final out = <String>[];
    for (final raw in lines) {
      var line = raw.trim();
      line = line
          .replaceFirst(RegExp(r'^[-*]\s+'), '')
          .replaceFirst(RegExp(r'^\d+[\.\)]\s+'), '')
          .replaceAll(RegExp(r'[*_`]+'), '')
          .trim();
      if (line.isEmpty) {
        continue;
      }
      if (!out.contains(line)) {
        out.add(line);
      }
    }
    return out;
  }

  List<String> _normalizeDefinitionLines(List<String> lines) {
    final normalized = _normalizeSectionLines(lines);
    final out = <String>[];
    for (final line in normalized) {
      if (!out.contains(line)) {
        out.add(line);
      }
    }
    return out;
  }

  bool _hasMinimumQuality(String notes) {
    final sections = _parseSections(notes);
    final summary =
        _normalizeSectionLines(sections[_sectionSummary] ?? const []);
    final topics = _normalizeSectionLines(sections[_sectionTopics] ?? const []);
    final defs =
        _normalizeDefinitionLines(sections[_sectionDefinitions] ?? const []);
    final actions =
        _normalizeSectionLines(sections[_sectionActions] ?? const []);
    final summaryWords = summary.join(' ').split(RegExp(r'\s+')).length;
    return summaryWords >= 4 &&
        topics.isNotEmpty &&
        defs.isNotEmpty &&
        actions.isNotEmpty;
  }

  String _summaryFromTranscript(String transcript) {
    final sentences = _extractSentences(transcript);
    if (sentences.isEmpty) {
      return 'Lecture summary was generated from available transcript context.';
    }
    final picked = sentences.take(2).join(' ');
    if (picked.length < 30) {
      return 'Lecture discusses core concepts and practical understanding steps.';
    }
    return picked;
  }

  List<String> _extractSentences(String transcript) {
    final normalized =
        transcript.replaceAll(RegExp(r'\s+'), ' ').replaceAll('\n', ' ').trim();
    if (normalized.isEmpty) {
      return const [];
    }
    final parts = normalized.split(RegExp(r'(?<=[.!?])\s+'));
    return parts
        .map((s) => s.trim())
        .where((s) => s.length >= 20 && s.length <= 220)
        .toList();
  }

  List<String> _extractTopicBullets(String transcript) {
    final keywords = [
      'topic',
      'concept',
      'principle',
      'process',
      'method',
      'model',
      'framework',
      'theory',
      'application',
      'analysis',
      'system',
      'chapter',
      'module',
    ];
    final sentences = _extractSentences(transcript);
    final scored = <MapEntry<String, int>>[];
    for (final sentence in sentences) {
      final lower = sentence.toLowerCase();
      var score = 0;
      for (final k in keywords) {
        if (lower.contains(k)) {
          score += 2;
        }
      }
      if (sentence.length >= 40 && sentence.length <= 140) {
        score += 1;
      }
      if (score > 0) {
        scored.add(MapEntry(sentence, score));
      }
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    final out = <String>[];
    for (final item in scored) {
      if (!out.contains(item.key)) {
        out.add(item.key);
      }
      if (out.length >= 6) {
        break;
      }
    }
    if (out.length < 3) {
      for (final sentence in sentences) {
        if (!out.contains(sentence)) {
          out.add(sentence);
        }
        if (out.length >= 3) {
          break;
        }
      }
    }
    return out;
  }

  List<String> _extractDefinitionBullets(String transcript) {
    final out = <String>[];
    final seenTerms = <String>{};
    final normalized = transcript.replaceAll('\n', ' ');

    final patterns = [
      RegExp(
        r'\b([A-Za-z][A-Za-z0-9\-/ ]{2,32})\s+(?:is|are|means|refers to)\s+([^.!?]{10,140})',
      ),
      RegExp(r'\b([A-Za-z][A-Za-z0-9\-/ ]{2,32})\s*:\s*([^.!?]{10,140})'),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(normalized)) {
        final term = (match.group(1) ?? '').trim();
        final definition = (match.group(2) ?? '').trim();
        final termKey = term.toLowerCase();
        if (term.isEmpty || definition.isEmpty || seenTerms.contains(termKey)) {
          continue;
        }
        seenTerms.add(termKey);
        out.add('$term: $definition');
        if (out.length >= 6) {
          return out;
        }
      }
    }
    return out;
  }

  List<String> _extractActionBullets(String transcript) {
    final cues = [
      'should',
      'must',
      'need to',
      'remember',
      'review',
      'practice',
      'apply',
      'prepare',
      'quiz',
      'exercise'
    ];
    final sentences = _extractSentences(transcript);
    final out = <String>[];
    for (final sentence in sentences) {
      final lower = sentence.toLowerCase();
      if (cues.any(lower.contains)) {
        out.add(sentence);
      }
      if (out.length >= 4) {
        break;
      }
    }
    return out;
  }

  List<String> _synthesizedActions({required String primaryTopic}) {
    return [
      'Create 3 flashcards summarizing the core ideas of $primaryTopic.',
      'Write a 5-bullet explanation of $primaryTopic as if teaching a friend.',
      'Find one real-world example that illustrates $primaryTopic and note why it matters.',
      'Draft one exam-style question and answer for $primaryTopic.',
    ];
  }

  List<String> _additionalContextFromTopics(List<String> topics) {
    final topic = topics.isNotEmpty ? topics.first : 'this lecture topic';
    return [
      'Compare "$topic" with related methods to understand when each is best applied.',
      'Review practical examples and common misconceptions connected to these concepts.',
      'Link today\'s ideas to prior lessons to build a deeper mental model.',
    ];
  }

  List<String> _enrichAdditionalContext({required String primaryTopic}) {
    return [
      'Cross-check "$primaryTopic" against authoritative sources (textbook or journal) for nuances.',
      'Identify open questions or debates related to "$primaryTopic" and note opposing viewpoints.',
      'List tools or frameworks that commonly pair with "$primaryTopic" and when to use them.',
      'Note typical pitfalls or misconceptions students have about "$primaryTopic".',
    ];
  }

  List<String> _generateQAFromContext({required String primaryTopic}) {
    return [
      'Define $primaryTopic and explain its real-world significance.',
      'Walk through a worked example/problem involving $primaryTopic.',
      'Contrast $primaryTopic with a closely related concept—when is each preferable?',
      'What common pitfalls or misconceptions occur with $primaryTopic?',
      'Give an interview-style question that tests practical understanding of $primaryTopic.',
    ];
  }

  String _formatRawTranscript(String text) {
    final sentences = _extractSentences(text);
    if (sentences.isEmpty) return text;
    final buffer = StringBuffer();
    var count = 0;
    for (final s in sentences) {
      buffer.write(s);
      buffer.write(' ');
      count++;
      if (count % 3 == 0) {
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  String _localStructuredFallback(String transcript, {String? reason}) {
    _log('fallback raw transcript${reason != null ? " ($reason)" : ""}');
    final cleaned = transcript.trim();
    if (cleaned.isEmpty) {
      return '# Raw Transcript\nNo transcript captured.';
    }
    return [
      '# Raw Transcript',
      _formatRawTranscript(cleaned),
    ].join('\n\n');
  }

  Future<String?> _structureChunkViaProxy({
    required String transcript,
    required String title,
    required String bearer,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(notesProxyUrl),
        headers: {
          'Authorization': 'Bearer $bearer',
          'apikey': SupaFlow.anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'transcript': transcript,
          'title': title,
        }),
      );
      if (res.statusCode != 200) {
        _log('chunk proxy status ${res.statusCode}: ${res.body}');
        return null;
      }
      final data = jsonDecode(res.body);
      final notes = (data['notes'] ?? '').toString();
      if (notes.isEmpty) {
        _log('chunk proxy empty body');
        return null;
      }
      return notes;
    } catch (e) {
      _log('chunk proxy exception $e');
      return null;
    }
  }

  String _mergeSectionNotes(List<String> noteDocs, String fullTranscript) {
    final collected = <String, List<String>>{};

    for (final doc in noteDocs) {
      final parsed = _parseSections(doc);
      parsed.forEach((key, value) {
        collected.putIfAbsent(key, () => <String>[]).addAll(value);
      });
    }

    String sectionBlock(String heading, String key) {
      final lines = collected[key] ?? const [];
      final normalized = _normalizeSectionLines(lines);
      if (normalized.isEmpty) return '# $heading\n';
      final bullets = normalized.map((l) => '- $l').join('\n');
      return '# $heading\n$bullets';
    }

    final draft = [
      sectionBlock('Lecture Summary', _sectionSummary),
      '',
      sectionBlock('Main Topics', _sectionTopics),
      '',
      sectionBlock('Key Definitions', _sectionDefinitions),
      '',
      sectionBlock('Action Items', _sectionActions),
      '',
      sectionBlock('Additional Context (Beyond Recording)', _sectionAdditional),
    ].join('\n');

    return _finalizeNotes(draft, fullTranscript);
  }

  List<String> _splitTranscript(String transcript) {
    final normalized = transcript.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= _chunkChars) {
      return [normalized];
    }

    final chunks = <String>[];
    var start = 0;
    while (start < normalized.length) {
      var end = start + _chunkChars;
      if (end >= normalized.length) {
        chunks.add(normalized.substring(start).trim());
        break;
      }

      final splitAt = normalized.lastIndexOf('.', end);
      if (splitAt > start + 1000) {
        end = splitAt + 1;
      }

      chunks.add(normalized.substring(start, end).trim());
      start = end;
    }
    return chunks.where((c) => c.isNotEmpty).toList();
  }

}
