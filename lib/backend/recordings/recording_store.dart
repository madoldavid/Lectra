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
    this.deletedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final Duration duration;
  final String audioPath;
  final String notesPath;
  final String transcriptPreview;
  final DateTime? deletedAt;

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
      deletedAt: DateTime.tryParse((json['deletedAt'] ?? '') as String),
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
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
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

  static Future<Directory> ensureTrashDir() async {
    final recordingsDir = await ensureRecordingsDir();
    final trashDir = Directory('${recordingsDir.path}/trash');
    if (!trashDir.existsSync()) {
      trashDir.createSync(recursive: true);
    }
    return trashDir;
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
          if (raw.deletedAt != null) {
            continue;
          }
          final repaired = await _repairEntry(raw);
          entriesById[repaired.id] = repaired;
        }
      } catch (_) {
        // Skip malformed entries.
      }
    }

    final entries = entriesById.values.toList();
    // Drop and clean up orphaned zero-duration entries (previous recovery stubs).
    entries.removeWhere((entry) {
      final isOrphan =
          entry.duration.inSeconds == 0 || !File(entry.audioPath).existsSync();
      if (isOrphan) {
        try {
          File(entry.audioPath).deleteSync();
          File(entry.notesPath).deleteSync();
          File(_metaPathFromAudioPath(entry.audioPath)).deleteSync();
        } catch (_) {}
      }
      return isOrphan;
    });

    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  static Future<List<RecordingEntry>> loadTrashRecordings() async {
    final dir = await ensureTrashDir();
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

    final audioFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => _isAudioFilePath(f.path))
        .toList();
    for (final audio in audioFiles) {
      final basePath = _stripExtension(audio.path);
      final id = _fileName(basePath);
      if (entriesById.containsKey(id)) {
        continue;
      }
      final recovered = await _recoverEntryFromAudio(
        audio,
        deletedAt: DateTime.now(),
      );
      entriesById[recovered.id] = recovered;
    }

    final entries = entriesById.values.toList();
    // Drop and clean up orphaned zero-duration entries (often recovered stubs).
    entries.removeWhere((entry) {
      if (entry.duration.inSeconds > 0) return false;
      // Clean up files for the orphan.
      try {
        File(entry.audioPath).deleteSync();
        File(entry.notesPath).deleteSync();
        File(_metaPathFromAudioPath(entry.audioPath)).deleteSync();
      } catch (_) {}
      return true;
    });

    entries.sort((a, b) {
      final aKey = a.deletedAt ?? a.createdAt;
      final bKey = b.deletedAt ?? b.createdAt;
      return bKey.compareTo(aKey);
    });
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
      deletedAt: null,
    );
    await File(metaPath).writeAsString(jsonEncode(entry.toJson()), flush: true);
    return entry;
  }

  static Future<RecordingEntry> moveToTrash(RecordingEntry entry) async {
    final trashDir = await ensureTrashDir();
    final sourceAudio = File(entry.audioPath);
    final sourceMeta = File(_metaPathFromAudioPath(entry.audioPath));
    final sourceNotes = File(entry.notesPath);

    final targetBase = _nextAvailableBasePath(
      directoryPath: trashDir.path,
      preferredBaseName: _fileName(_stripExtension(entry.audioPath)),
      audioExtension: _extensionOfPath(entry.audioPath, fallback: '.m4a'),
    );

    final targetAudioPath =
        '$targetBase${_extensionOfPath(entry.audioPath, fallback: '.m4a')}';
    final targetNotesPath = '$targetBase.txt';
    final targetMetaPath = '$targetBase.json';

    if (sourceAudio.existsSync()) {
      await sourceAudio.rename(targetAudioPath);
    }
    if (sourceNotes.existsSync()) {
      await sourceNotes.rename(targetNotesPath);
    }
    if (sourceMeta.existsSync()) {
      await sourceMeta.rename(targetMetaPath);
    }

    final trashedEntry = RecordingEntry(
      id: _fileName(targetBase),
      title: entry.title,
      createdAt: entry.createdAt,
      duration: entry.duration,
      audioPath: targetAudioPath,
      notesPath: targetNotesPath,
      transcriptPreview: entry.transcriptPreview,
      deletedAt: DateTime.now(),
    );
    await File(targetMetaPath)
        .writeAsString(jsonEncode(trashedEntry.toJson()), flush: true);
    return trashedEntry;
  }

  static Future<RecordingEntry> restoreFromTrash(RecordingEntry entry) async {
    final recordingsDir = await ensureRecordingsDir();
    final sourceAudio = File(entry.audioPath);
    final sourceMeta = File(_metaPathFromAudioPath(entry.audioPath));
    final sourceNotes = File(entry.notesPath);

    final targetBase = _nextAvailableBasePath(
      directoryPath: recordingsDir.path,
      preferredBaseName: _fileName(_stripExtension(entry.audioPath)),
      audioExtension: _extensionOfPath(entry.audioPath, fallback: '.m4a'),
    );

    final targetAudioPath =
        '$targetBase${_extensionOfPath(entry.audioPath, fallback: '.m4a')}';
    final targetNotesPath = '$targetBase.txt';
    final targetMetaPath = '$targetBase.json';

    if (sourceAudio.existsSync()) {
      await sourceAudio.rename(targetAudioPath);
    }
    if (sourceNotes.existsSync()) {
      await sourceNotes.rename(targetNotesPath);
    }
    if (sourceMeta.existsSync()) {
      await sourceMeta.rename(targetMetaPath);
    }

    final restoredEntry = RecordingEntry(
      id: _fileName(targetBase),
      title: entry.title,
      createdAt: entry.createdAt,
      duration: entry.duration,
      audioPath: targetAudioPath,
      notesPath: targetNotesPath,
      transcriptPreview: entry.transcriptPreview,
      deletedAt: null,
    );
    await File(targetMetaPath)
        .writeAsString(jsonEncode(restoredEntry.toJson()), flush: true);
    return restoredEntry;
  }

  static Future<void> deleteRecordingPermanently(RecordingEntry entry) async {
    try {
      final audioFile = File(entry.audioPath);
      if (audioFile.existsSync()) {
        await audioFile.delete();
      }

      final notesFile = File(entry.notesPath);
      if (notesFile.existsSync()) {
        await notesFile.delete();
      }

      final metaPath = _metaPathFromAudioPath(entry.audioPath);
      final metaFile = File(metaPath);
      if (metaFile.existsSync()) {
        await metaFile.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting recording files for ${entry.id}: $e');
      }
    }
  }

  static Future<void> deleteRecording(RecordingEntry entry) async {
    await moveToTrash(entry);
  }

  static Future<RecordingEntry> updateRecordingTitle({
    required RecordingEntry entry,
    required String newTitle,
  }) async {
    final trimmedTitle = newTitle.trim();
    if (trimmedTitle.isEmpty) {
      return entry;
    }

    final updated = RecordingEntry(
      id: entry.id,
      title: trimmedTitle,
      createdAt: entry.createdAt,
      duration: entry.duration,
      audioPath: entry.audioPath,
      notesPath: entry.notesPath,
      transcriptPreview: entry.transcriptPreview,
      deletedAt: entry.deletedAt,
    );

    try {
      final metaPath = '${_stripExtension(entry.audioPath)}.json';
      await File(metaPath)
          .writeAsString(jsonEncode(updated.toJson()), flush: true);
      return updated;
    } catch (_) {
      return entry;
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
    } else if (notesExists && notesFile != null) {
      try {
        final existingNotes = await notesFile.readAsString();
        if (_looksLikeApiError(existingNotes.trim())) {
          await notesFile.writeAsString(
            _buildLocalNotes(entry.transcriptPreview),
            flush: true,
          );
        }
      } catch (_) {
        // Keep existing notes if repair read/write fails.
      }
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
      deletedAt: entry.deletedAt,
    );
    if (entry.audioPath.trim().isNotEmpty) {
      final metaPath = '${_stripExtension(entry.audioPath)}.json';
      await File(metaPath)
          .writeAsString(jsonEncode(repaired.toJson()), flush: true);
    }
    return repaired;
  }

  static Future<RecordingEntry> _recoverEntryFromAudio(
    File audioFile, {
    DateTime? deletedAt,
  }) async {
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
      deletedAt: deletedAt,
    );
    await File(metaPath).writeAsString(jsonEncode(entry.toJson()), flush: true);
    return entry;
  }

  static String _metaPathFromAudioPath(String audioPath) =>
      '${_stripExtension(audioPath)}.json';

  static String _extensionOfPath(String path, {required String fallback}) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot >= path.length - 1) {
      return fallback;
    }
    return path.substring(dot);
  }

  static bool _isAudioFilePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.m4a') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.mp3');
  }

  static String _nextAvailableBasePath({
    required String directoryPath,
    required String preferredBaseName,
    required String audioExtension,
  }) {
    var index = 0;
    while (true) {
      final suffix = index == 0 ? '' : '_$index';
      final candidateBase = '$directoryPath/$preferredBaseName$suffix';
      final candidateAudio = File('$candidateBase$audioExtension');
      final candidateNotes = File('$candidateBase.txt');
      final candidateMeta = File('$candidateBase.json');
      if (!candidateAudio.existsSync() &&
          !candidateNotes.existsSync() &&
          !candidateMeta.existsSync()) {
        return candidateBase;
      }
      index += 1;
    }
  }

  static String _buildLocalNotes(String transcript) {
    final cleaned = transcript.trim();
    if (cleaned.isEmpty) {
      return [
        '# Lecture Summary',
        '- No transcript captured.',
        '',
        '# Main Topics',
        '- No transcript captured.',
        '',
        '# Key Definitions',
        '- Not available.',
        '',
        '# Action Items',
        '- Review recording and retry transcription.',
        '',
        '# Additional Context (Beyond Recording)',
        '- Additional context is unavailable without transcript content.',
      ].join('\n');
    }

    final preview =
        cleaned.length > 1000 ? '${cleaned.substring(0, 1000)}...' : cleaned;
    return [
      '# Lecture Summary',
      '- Generated from the captured transcript.',
      '',
      '# Main Topics',
      '- Generated from the captured transcript.',
      '',
      '# Key Definitions',
      '- Extract key terms while reviewing the transcript.',
      '',
      '# Action Items',
      '- Review and refine these notes as needed.',
      '',
      '# Additional Context (Beyond Recording)',
      '- Add your own extra references/examples while reviewing the lecture.',
      '',
      '# Transcript Excerpt (Raw)',
      preview,
    ].join('\n');
  }

  static bool _looksLikeApiError(String text) {
    if (text.isEmpty) {
      return false;
    }
    final normalized = text.toLowerCase();
    final asksForTranscript =
        normalized.contains('please provide the transcript') ||
            normalized.contains('provide the transcript') ||
            normalized.contains('share the transcript') ||
            normalized.contains('send the transcript') ||
            normalized.contains('waiting for the transcript') ||
            normalized.contains("i'm ready") ||
            normalized.contains('i am ready');
    if (asksForTranscript) {
      return true;
    }

    final hasExpectedHeadings = normalized.contains('main topics') ||
        normalized.contains('key definitions') ||
        normalized.contains('action items');
    if (!hasExpectedHeadings && normalized.length < 180) {
      return true;
    }

    return normalized.contains('api key') ||
        normalized.contains('api not valid') ||
        normalized
            .contains('exception occurred while trying to generate notes');
  }
}
