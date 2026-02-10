import 'dart:convert';
import 'dart:io';

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
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    final entries = <RecordingEntry>[];
    for (final file in files) {
      try {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) {
          entries.add(RecordingEntry.fromJson(data));
        }
      } catch (_) {
        // Skip malformed entries.
      }
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  static Future<RecordingEntry> saveRecording({
    required String audioPath,
    required String transcript,
    required Duration duration,
  }) async {
    final createdAt = DateTime.now();
    final basePath = _stripExtension(audioPath);
    final notesPath = '$basePath.txt';
    final metaPath = '$basePath.json';
    final title = _titleFromDate(createdAt);
    final highlights = _extractHighlights(transcript);
    final transcriptPreview = _previewTranscript(transcript);

    final buffer = StringBuffer();
    buffer.writeln('Lecture Notes');
    buffer.writeln('Title: $title');
    buffer.writeln('Recorded: ${createdAt.toIso8601String()}');
    buffer.writeln('Duration: ${_formatDuration(duration)}');
    buffer.writeln();
    buffer.writeln('Highlights (auto-extracted)');
    if (highlights.isEmpty) {
      buffer.writeln('- (No transcript available)');
    } else {
      for (final line in highlights) {
        buffer.writeln('- $line');
      }
    }
    buffer.writeln();
    buffer.writeln('Transcript');
    buffer.writeln(transcript.isEmpty ? '(No transcript available)' : transcript);

    await File(notesPath).writeAsString(buffer.toString());

    final entry = RecordingEntry(
      id: _fileName(basePath),
      title: title,
      createdAt: createdAt,
      duration: duration,
      audioPath: audioPath,
      notesPath: notesPath,
      transcriptPreview: transcriptPreview,
    );
    await File(metaPath).writeAsString(jsonEncode(entry.toJson()));
    return entry;
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

  static List<String> _extractHighlights(String transcript) {
    if (transcript.trim().isEmpty) {
      return [];
    }
    final sentences = transcript
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.isEmpty) {
      return [];
    }
    return sentences.take(5).toList();
  }

  static String _previewTranscript(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final limit = 160;
    if (trimmed.length <= limit) {
      return trimmed;
    }
    return '${trimmed.substring(0, limit)}...';
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
}
