import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

class LectureNotesResult {
  const LectureNotesResult({
    required this.notes,
    required this.transcript,
  });

  final String notes;
  final String transcript;
}

class GeminiService {
  final String apiKey;

  GeminiService(this.apiKey);

  Future<LectureNotesResult> generateNotesFromAudio(String filePath) async {
    final audioBytes = await File(filePath).readAsBytes();
    final model = GenerativeModel(model: 'gemini-2.0-flash', apiKey: apiKey);
    final mimeType = _mimeTypeForPath(filePath);

    const prompt = '''
You are an expert academic note-taker.
Listen to this lecture audio and return strict JSON with this schema:
{
  "transcript": "verbatim transcript text",
  "notes": "well-structured markdown notes with headings: Main Topics, Key Definitions, Action Items"
}
Do not include markdown fences or extra text outside JSON.
''';

    final response = await model.generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart(mimeType, audioBytes),
      ]),
    ]);

    final raw = (response.text ?? '').trim();
    if (raw.isEmpty) {
      return const LectureNotesResult(notes: '', transcript: '');
    }

    final parsed = _tryParseJson(raw);
    if (parsed != null) {
      return LectureNotesResult(
        transcript: (parsed['transcript'] ?? '').toString().trim(),
        notes: (parsed['notes'] ?? '').toString().trim(),
      );
    }

    return LectureNotesResult(notes: raw, transcript: '');
  }

  Future<String> generateNotes(String transcript) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.0-flash', apiKey: apiKey);
      final content = [
        Content.text(
          'You are a professional note-taker. '
          'Use the transcript below to create structured notes with headings for '
          'Main Topics, Key Definitions, and Action Items.\n\n'
          'Transcript:\n$transcript',
        )
      ];
      final response = await model.generateContent(content);
      return response.text ?? 'No response from Gemini.';
    } catch (e) {
      return 'An exception occurred while trying to generate notes: $e';
    }
  }

  Map<String, dynamic>? _tryParseJson(String input) {
    final direct = _decodeObject(input);
    if (direct != null) {
      return direct;
    }

    final cleaned =
        input.replaceAll('```json', '').replaceAll('```', '').trim();
    final cleanedDecoded = _decodeObject(cleaned);
    if (cleanedDecoded != null) {
      return cleanedDecoded;
    }

    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return _decodeObject(cleaned.substring(start, end + 1));
    }
    return null;
  }

  Map<String, dynamic>? _decodeObject(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) {
      return 'audio/mp4';
    }
    if (lower.endsWith('.wav')) {
      return 'audio/wav';
    }
    if (lower.endsWith('.aac')) {
      return 'audio/aac';
    }
    return 'audio/mp4';
  }
}
