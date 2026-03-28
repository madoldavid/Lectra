import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Android-first local speech-to-text using whisper.cpp via whisper_ggml.
///
/// - Downloads model once to app support directory.
/// - Runs fully on-device after model is present.
/// - Optimized for long recordings by splitting large WAV files in Dart
///   (no ffmpeg runtime dependency needed).
class WhisperTranscriptionService {
  WhisperTranscriptionService({
    WhisperModel model = WhisperModel.tinyEn,
    String language = 'en',
  })  : _model = model,
        _language = language;

  final WhisperController _controller = WhisperController();
  final WhisperModel _model;
  final String _language;
  static const int _segmentThresholdSeconds = 20 * 60;
  static const int _segmentLengthSeconds = 15 * 60;
  static const int _minModelBytes = 1024 * 1024; // 1MB sanity threshold

  bool _modelReady = false;
  Future<void>? _ensureModelFuture;

  Future<void> ensureModelReady() async {
    if (_modelReady) {
      return;
    }
    _ensureModelFuture ??= _prepareModel();
    await _ensureModelFuture;
  }

  Future<String> transcribeFile(String audioPath) async {
    final file = File(audioPath);
    if (!file.existsSync()) {
      throw StateError('Audio file not found for transcription.');
    }

    await ensureModelReady();

    final wavInfo = await _readWavInfo(audioPath);
    if (wavInfo != null &&
        wavInfo.durationSeconds >= _segmentThresholdSeconds) {
      final segmented = await _transcribeWavInSegments(audioPath, wavInfo);
      if (segmented.trim().isNotEmpty) {
        return _normalize(segmented);
      }
    }

    var text = await _transcribeSingle(audioPath);
    text = _normalize(text);
    if (text.isNotEmpty) {
      return text;
    }

    // Recovery path: model file may be partially downloaded/corrupt.
    await _forceModelRefresh();
    text = _normalize(await _transcribeSingle(audioPath));
    return text;
  }

  Future<String> _transcribeSingle(String audioPath) async {
    final candidateModels = _candidateModelsFor(_model);

    for (final candidate in candidateModels) {
      try {
        final result = await _controller.transcribe(
          model: candidate,
          audioPath: audioPath,
          lang: _language,
        );
        final text = (result?.transcription.text ?? '').toString().trim();
        if (text.isNotEmpty) {
          return text;
        }
      } catch (_) {
        // Try next model fallback.
      }
    }
    return '';
  }

  List<WhisperModel> _candidateModelsFor(WhisperModel preferred) {
    switch (preferred) {
      case WhisperModel.smallEn:
        return const [
          WhisperModel.smallEn,
          WhisperModel.baseEn,
          WhisperModel.tinyEn,
        ];
      case WhisperModel.baseEn:
        return const [
          WhisperModel.baseEn,
          WhisperModel.tinyEn,
        ];
      case WhisperModel.tinyEn:
        return const [WhisperModel.tinyEn];
      default:
        return [preferred, WhisperModel.tinyEn];
    }
  }

  Future<void> _prepareModel() async {
    final path = await _controller.getPath(_model);
    final file = File(path);
    final needsDownload =
        !file.existsSync() || file.lengthSync() < _minModelBytes;
    if (needsDownload) {
      await _controller.downloadModel(_model);
    }
    _modelReady = true;
  }

  Future<void> _forceModelRefresh() async {
    _modelReady = false;
    _ensureModelFuture = null;
    final path = await _controller.getPath(_model);
    final file = File(path);
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {}
    await ensureModelReady();
  }

  Future<_WavInfo?> _readWavInfo(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final length = await raf.length();
      if (length < 44) {
        return null;
      }

      final riffHeader = await raf.read(12);
      if (riffHeader.length < 12) {
        return null;
      }
      if (_ascii(riffHeader.sublist(0, 4)) != 'RIFF' ||
          _ascii(riffHeader.sublist(8, 12)) != 'WAVE') {
        return null;
      }

      int? sampleRate;
      int? channels;
      int? bitsPerSample;
      int? dataSize;
      int? dataOffset;

      while (await raf.position() + 8 <= length) {
        final chunkHeader = await raf.read(8);
        if (chunkHeader.length < 8) {
          break;
        }
        final chunkId = _ascii(chunkHeader.sublist(0, 4));
        final chunkSize =
            ByteData.sublistView(Uint8List.fromList(chunkHeader), 4)
                .getUint32(0, Endian.little);

        final chunkDataStart = await raf.position();
        if (chunkId == 'fmt ') {
          final fmtBytes = await raf.read(chunkSize);
          if (fmtBytes.length >= 16) {
            final bd = ByteData.sublistView(Uint8List.fromList(fmtBytes));
            final audioFormat = bd.getUint16(0, Endian.little);
            if (audioFormat != 1) {
              return null; // Non-PCM WAV is unsupported for splitting.
            }
            channels = bd.getUint16(2, Endian.little);
            sampleRate = bd.getUint32(4, Endian.little);
            bitsPerSample = bd.getUint16(14, Endian.little);
          }
        } else if (chunkId == 'data') {
          dataOffset = chunkDataStart;
          dataSize = chunkSize;
          await raf.setPosition(chunkDataStart + chunkSize);
        } else {
          await raf.setPosition(chunkDataStart + chunkSize);
        }

        // RIFF chunks are word-aligned.
        final afterChunk = await raf.position();
        if (afterChunk.isOdd && afterChunk < length) {
          await raf.setPosition(afterChunk + 1);
        }

        if (sampleRate != null &&
            channels != null &&
            bitsPerSample != null &&
            dataSize != null &&
            dataOffset != null) {
          final bytesPerSecond = sampleRate * channels * (bitsPerSample ~/ 8);
          if (bytesPerSecond <= 0) {
            return null;
          }
          final durationSeconds = dataSize / bytesPerSecond;
          return _WavInfo(
            sampleRate: sampleRate,
            channels: channels,
            bitsPerSample: bitsPerSample,
            dataOffset: dataOffset,
            dataSize: dataSize,
            durationSeconds: durationSeconds,
          );
        }
      }
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }

    return null;
  }

  Future<String> _transcribeWavInSegments(
      String audioPath, _WavInfo wavInfo) async {
    final tempRoot = await getTemporaryDirectory();
    final segmentDir = Directory(
      '${tempRoot.path}/whisper_segments_${DateTime.now().millisecondsSinceEpoch}',
    );
    await segmentDir.create(recursive: true);

    final segmentFiles = <File>[];
    RandomAccessFile? source;
    try {
      source = await File(audioPath).open(mode: FileMode.read);
      final bytesPerSecond =
          wavInfo.sampleRate * wavInfo.channels * (wavInfo.bitsPerSample ~/ 8);
      final segmentBytesTarget = _segmentLengthSeconds * bytesPerSecond;
      var offset = 0;
      var index = 0;
      while (offset < wavInfo.dataSize) {
        final segmentDataBytes =
            (wavInfo.dataSize - offset) < segmentBytesTarget
                ? (wavInfo.dataSize - offset)
                : segmentBytesTarget;

        final segmentFile = File(
          '${segmentDir.path}/chunk_${index.toString().padLeft(3, '0')}.wav',
        );
        segmentFiles.add(segmentFile);

        final sink = segmentFile.openWrite(mode: FileMode.writeOnly);
        sink.add(
          _buildWavHeader(
            dataSize: segmentDataBytes,
            sampleRate: wavInfo.sampleRate,
            channels: wavInfo.channels,
            bitsPerSample: wavInfo.bitsPerSample,
          ),
        );

        await source.setPosition(wavInfo.dataOffset + offset);
        var remaining = segmentDataBytes;
        while (remaining > 0) {
          final readSize = remaining > 65536 ? 65536 : remaining;
          final data = await source.read(readSize);
          if (data.isEmpty) {
            break;
          }
          sink.add(data);
          remaining -= data.length;
        }

        await sink.flush();
        await sink.close();

        offset += segmentDataBytes;
        index += 1;
      }

      if (segmentFiles.isEmpty) {
        return '';
      }

      final buffer = StringBuffer();
      for (final segment in segmentFiles) {
        String partial = '';
        try {
          partial = (await _transcribeSingle(segment.path)
                  .timeout(const Duration(minutes: 5)))
              .trim();
        } catch (_) {
          partial = '';
        }
        if (partial.isEmpty) {
          continue;
        }
        if (buffer.isNotEmpty) {
          buffer.write('\n');
        }
        buffer.write(partial);
      }

      return buffer.toString();
    } catch (_) {
      return '';
    } finally {
      await source?.close();
      try {
        if (segmentDir.existsSync()) {
          await segmentDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Uint8List _buildWavHeader({
    required int dataSize,
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final totalSize = 44 + dataSize - 8;

    final bytes = ByteData(44);
    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    bytes.setUint32(4, totalSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little); // PCM fmt chunk size
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, byteRate, Endian.little);
    bytes.setUint16(32, blockAlign, Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);

    return bytes.buffer.asUint8List();
  }

  String _ascii(List<int> bytes) => String.fromCharCodes(bytes);

  String _normalize(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _WavInfo {
  const _WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
    required this.durationSeconds,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataSize;
  final double durationSeconds;
}
