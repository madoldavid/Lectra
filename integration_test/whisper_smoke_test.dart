import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'package:lectra/services/whisper_transcription_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('whisper local transcription smoke test', (tester) async {
    final service =
        WhisperTranscriptionService(model: WhisperModel.tinyEn, language: 'en');

    await service.ensureModelReady().timeout(const Duration(minutes: 4));

    final tempDir = await getTemporaryDirectory();
    final inputPath = '${tempDir.path}/whisper_smoke_input.wav';
    await File(inputPath).writeAsBytes(_buildSilentWavBytes(seconds: 2));

    final text = await service
        .transcribeFile(inputPath)
        .timeout(const Duration(minutes: 4));

    // The goal is to ensure local whisper pipeline executes without crash.
    // Silence may return empty string depending on model thresholds.
    expect(text, isA<String>());
  });
}

Uint8List _buildSilentWavBytes({required int seconds}) {
  const sampleRate = 16000;
  const channels = 1;
  const bitsPerSample = 16;
  final numSamples = sampleRate * seconds;
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final dataSize = numSamples * blockAlign;
  final fileSize = 44 + dataSize - 8;

  final bytes = BytesBuilder();
  void writeString(String value) => bytes.add(value.codeUnits);
  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void writeUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  writeString('RIFF');
  writeUint32(fileSize);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16); // PCM fmt chunk size
  writeUint16(1); // PCM
  writeUint16(channels);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bitsPerSample);
  writeString('data');
  writeUint32(dataSize);
  bytes.add(Uint8List(dataSize)); // silence

  return bytes.toBytes();
}
