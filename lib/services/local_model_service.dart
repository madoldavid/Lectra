import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages on‑demand download and local processing of transcripts using an
/// on-device model (SmolLM-135M or similar).
///
/// NOTE: The current implementation keeps the app lightweight by downloading
/// the model only when first needed. The summarization logic is heuristic and
/// runs in an Isolate to avoid janking the UI. Swap `_summarizeLocally` with
/// actual model inference once the TFLite file is available.
class LocalModelService {
  LocalModelService._();
  static final LocalModelService instance = LocalModelService._();

  /// Replace with your hosted model URL (TFLite/gguf).
  /// Host your quantized TFLite model here. Replace this URL with your CDN/Firebase Storage link.
  static const String _modelUrl =
      String.fromEnvironment(
        'SMOLLM_MODEL_URL',
        defaultValue:
            'https://example.com/models/smollm-135m-instruct.tflite',
      );
  static const String _modelFileName = 'smollm-135m-instruct.tflite';

  Future<String> _modelPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, _modelFileName);
  }

  Future<bool> isModelDownloaded() async {
    final path = await _modelPath();
    return File(path).existsSync();
  }

  /// Downloads the model on-demand. Provides progress 0.0–1.0 via callback.
  Future<void> ensureModelAvailable({void Function(double progress)? onProgress}) async {
    if (await isModelDownloaded()) return;
    final path = await _modelPath();
    await Directory(p.dirname(path)).create(recursive: true);
    final tmpPath = '$path.part';

    final req = http.Request('GET', Uri.parse(_modelUrl));
    final res = await req.send();
    if (res.statusCode != 200) {
      throw Exception('Model download failed (${res.statusCode})');
    }

    final total = res.contentLength ?? 0;
    var received = 0;
    final sink = File(tmpPath).openWrite();
    await for (final chunk in res.stream) {
      received += chunk.length;
      sink.add(chunk);
      if (onProgress != null && total > 0) {
        onProgress(received / total);
      }
    }
    await sink.flush();
    await sink.close();
    await File(tmpPath).rename(path);
  }

  /// Attempts to structure notes locally. Returns null if the model is missing
  /// or processing fails; caller should fall back to cloud.
  Future<String?> structureLocally(String transcript) async {
    if (!await isModelDownloaded()) return null;
    if (transcript.trim().isEmpty) return null;
    try {
      final modelPath = await _modelPath();
      return compute(_runLocalJob, _LocalJob(transcript: transcript, modelPath: modelPath));
    } catch (_) {
      return null;
    }
  }
}

class _LocalJob {
  const _LocalJob({required this.transcript, required this.modelPath});
  final String transcript;
  final String modelPath;
}

/// Lightweight summarization that can be replaced with real model inference.
String _runLocalJob(_LocalJob job) {
  final transcript = job.transcript;
  // TODO: Plug in real TFLite inference using [job.modelPath] + tokenizer.
  // For now, keep the heuristic summary to ensure functionality.
  String clean(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').replaceAll('\n', ' ').trim();

  final sentences = transcript
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map(clean)
      .where((s) => s.length >= 20 && s.length <= 240)
      .toList();

  List<String> topN(List<String> list, int n) =>
      list.where((e) => e.isNotEmpty).take(n).toList();

  final summary = topN(sentences, 2);

  final topics = sentences
      .where((s) => RegExp(r'(topic|concept|model|theory|process)', caseSensitive: false).hasMatch(s))
      .toList();

  final definitions = RegExp(
          r'\b([A-Za-z][A-Za-z0-9\-/ ]{2,32})\s+(?:is|are|means|refers to)\s+([^.!?]{10,140})',
          caseSensitive: false)
      .allMatches(transcript)
      .map((m) => '${m.group(1)}: ${m.group(2)}')
      .toList();

  final actions = sentences
      .where((s) => RegExp(r'(should|must|need to|remember|review|practice)', caseSensitive: false)
          .hasMatch(s))
      .toList();

  String section(String title, List<String> lines, int max) {
    if (lines.isEmpty) return '# $title\n- Not available.';
    return '# $title\n${topN(lines, max).map((l) => '- $l').join('\n')}';
  }

  return [
    section('Lecture Summary', summary, 2),
    '',
    section('Main Topics', topics, 6),
    '',
    section('Key Definitions', definitions, 6),
    '',
    section('Action Items', actions, 5),
    '',
    '# Additional Context (Beyond Recording)\n- Review textbook references or slides to reinforce these points.',
  ].join('\n');
}
