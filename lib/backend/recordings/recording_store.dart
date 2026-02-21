import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class RecordingEntry {
  RecordingEntry({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.duration,
    required this.audioPath,
    required this.notesPath,
    required this.transcriptPreview,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final Duration duration;
  final String audioPath;
  final String notesPath;
  final String transcriptPreview;

  factory RecordingEntry.fromJson(Map<String, dynamic> json) {
    return RecordingEntry(
      id: (json['id'] ?? '') as String,
      title: (json['title'] ?? 'Lecture') as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      duration: Duration(seconds: (json['durationSeconds'] ?? 0) as int),
      audioPath: (json['audioPath'] ?? '') as String,
      notesPath: (json['notesPath'] ?? '') as String,
      transcriptPreview: (json['transcriptPreview'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'durationSeconds': duration.inSeconds,
        'audioPath': audioPath,
        'notesPath': notesPath,
        'transcriptPreview': transcriptPreview,
      };
}

class RecordingStore {
  static Future<Directory> ensureRecordingsDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/recordings');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static Future<List<RecordingEntry>> loadRecordings() async {
    final dir = await ensureRecordingsDir();
    if (!dir.existsSync()) {
      return [];
    }
    final metaFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    final entriesById = <String, RecordingEntry>{};

    for (final file in metaFiles) {
      try {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) {
          final raw = RecordingEntry.fromJson(data);
          final repaired = await _repairEntry(raw);
          entriesById[repaired.id] = repaired;
        }
      } catch (_) {
        // Skip malformed entries.
      }
    }

    // Recover recordings that have audio files but no metadata.
    final audioFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.m4a'))
        .toList();
    for (final audio in audioFiles) {
      final basePath = _stripExtension(audio.path);
      final id = _fileName(basePath);
      if (entriesById.containsKey(id)) {
        continue;
      }
      final recovered = await _recoverEntryFromAudio(audio);
      entriesById[recovered.id] = recovered;
    }

    final entries = entriesById.values.toList();
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  static Future<RecordingEntry> saveRecording({
    required String audioPath,
    required String transcript,
    required Duration duration,
    String? notesOverride,
    String? titleOverride,
  }) async {
    final createdAt = DateTime.now();
    final basePath = _stripExtension(audioPath);
    final notesPath = '$basePath.txt';
    final metaPath = '$basePath.json';
    final customTitle = titleOverride?.trim() ?? '';
    final title =
        customTitle.isNotEmpty ? customTitle : _titleFromDate(createdAt);

    var notes = (notesOverride ?? '').trim();
    if (_looksLikeApiError(notes)) {
      notes = '';
    }
    if (notes.isEmpty) {
      notes = _buildLocalNotes(transcript);
    }
    await File(notesPath).writeAsString(notes, flush: true);

    final entry = RecordingEntry(
      id: _fileName(basePath),
      title: title,
      createdAt: createdAt,
      duration: duration,
      audioPath: audioPath,
      notesPath: notesPath,
      transcriptPreview: (transcript.length > 160)
          ? '${transcript.substring(0, 160)}...'
          : transcript,
    );
    await File(metaPath).writeAsString(jsonEncode(entry.toJson()), flush: true);
    return entry;
  }

  static Future<void> deleteRecording(RecordingEntry entry) async {
    try {
      final audioFile = File(entry.audioPath);
      if (audioFile.existsSync()) {
        await audioFile.delete();
      }

      final notesFile = File(entry.notesPath);
      if (notesFile.existsSync()) {
        await notesFile.delete();
      }

      final metaPath = '${_stripExtension(entry.audioPath)}.json';
      final metaFile = File(metaPath);
      if (metaFile.existsSync()) {
        await metaFile.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) {
          print('Error deleting recording files for ${entry.id}: $e');
        }
      }
    }
  }

  static String _stripExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot <= 0) {
      return path;
    }
    return path.substring(0, dot);
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  static String _titleFromDate(DateTime dateTime) {
    final month = _monthName(dateTime.month);
    return 'Lecture $month ${dateTime.day}, ${dateTime.year}';
  }

  static String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month < 1 || month > 12) {
      return 'Unknown';
    }
    return months[month - 1];
  }

  static Future<RecordingEntry> _repairEntry(RecordingEntry entry) async {
    final audioFile = File(entry.audioPath);
    final fallbackBasePath =
        entry.audioPath.trim().isEmpty ? '' : _stripExtension(entry.audioPath);
    final resolvedNotesPath = entry.notesPath.trim().isNotEmpty
        ? entry.notesPath
        : (fallbackBasePath.isNotEmpty ? '$fallbackBasePath.txt' : '');
    final notesFile =
        resolvedNotesPath.isNotEmpty ? File(resolvedNotesPath) : null;

    final audioExists = audioFile.existsSync();
    final notesExists = notesFile?.existsSync() ?? false;

    if (!audioExists && !notesExists) {
      // Keep metadata visible; never auto-delete user recordings.
      return entry;
    }

    if (!notesExists && notesFile != null) {
      await notesFile.writeAsString(
        _buildLocalNotes(entry.transcriptPreview),
        flush: true,
      );
    }

    // Keep entry id/title/dates stable to avoid disappearing rows.
    if (resolvedNotesPath == entry.notesPath) {
      return entry;
    }
    final repaired = RecordingEntry(
      id: entry.id,
      title: entry.title,
      createdAt: entry.createdAt,
      duration: entry.duration,
      audioPath: entry.audioPath,
      notesPath: resolvedNotesPath,
      transcriptPreview: entry.transcriptPreview,
    );
    if (entry.audioPath.trim().isNotEmpty) {
      final metaPath = '${_stripExtension(entry.audioPath)}.json';
      await File(metaPath)
          .writeAsString(jsonEncode(repaired.toJson()), flush: true);
    }
    return repaired;
  }

  static Future<RecordingEntry> _recoverEntryFromAudio(File audioFile) async {
    final stat = await audioFile.stat();
    final createdAt = stat.modified.toLocal();
    final basePath = _stripExtension(audioFile.path);
    final notesPath = '$basePath.txt';
    final metaPath = '$basePath.json';
    final title = _titleFromDate(createdAt);

    final notesFile = File(notesPath);
    if (!notesFile.existsSync()) {
      await notesFile.writeAsString(_buildLocalNotes(''), flush: true);
    }

    final entry = RecordingEntry(
      id: _fileName(basePath),
      title: title,
      createdAt: createdAt,
      duration: Duration.zero,
      audioPath: audioFile.path,
      notesPath: notesPath,
      transcriptPreview: '',
    );
    await File(metaPath).writeAsString(jsonEncode(entry.toJson()), flush: true);
    return entry;
  }

  static String _buildLocalNotes(String transcript) {
    final cleaned = transcript.trim();
    if (cleaned.isEmpty) {
      return [
        '# Main Topics',
        '- No transcript captured.',
        '',
        '# Key Definitions',
        '- Not available.',
        '',
        '# Action Items',
        '- Review recording and retry transcription.',
      ].join('\n');
    }

    final preview =
        cleaned.length > 1000 ? '${cleaned.substring(0, 1000)}...' : cleaned;
    return [
      '# Main Topics',
      '- Generated from the captured transcript.',
      '',
      '# Key Definitions',
      '- Extract key terms while reviewing the transcript.',
      '',
      '# Action Items',
      '- Review and refine these notes as needed.',
      '',
      '# Transcript Excerpt',
      preview,
    ].join('\n');
  }

  static bool _looksLikeApiError(String text) {
    if (text.isEmpty) {
      return false;
    }
    final normalized = text.toLowerCase();
    return normalized.contains('api key') ||
        normalized.contains('api not valid') ||
        normalized
            .contains('exception occurred while trying to generate notes');
  }
}
