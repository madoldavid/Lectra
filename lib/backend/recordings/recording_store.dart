import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:lectra/services/gemini_service.dart';

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
          final entry = RecordingEntry.fromJson(data);
          final audioExists = File(entry.audioPath).existsSync();
          final notesExists = File(entry.notesPath).existsSync();
          if (!audioExists && !notesExists) {
            await deleteRecording(entry);
            continue;
          }
          entries.add(entry);
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
    required GeminiService geminiService,
  }) async {
    final createdAt = DateTime.now();
    final basePath = _stripExtension(audioPath);
    final notesPath = '$basePath.txt';
    final metaPath = '$basePath.json';
    final title = _titleFromDate(createdAt);

    final notes = await geminiService.generateNotes(transcript);
    await File(notesPath).writeAsString(notes);

    final entry = RecordingEntry(
      id: _fileName(basePath),
      title: title,
      createdAt: createdAt,
      duration: duration,
      audioPath: audioPath,
      notesPath: notesPath,
      transcriptPreview: (transcript.length > 160) ? '${transcript.substring(0, 160)}...' : transcript,
    );
    await File(metaPath).writeAsString(jsonEncode(entry.toJson()));
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
}
