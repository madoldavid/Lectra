import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'package:lectra/services/local_pcm_recording_service.dart';
import 'package:lectra/services/whisper_transcription_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('start/stop recording and transcription smoke test',
      (tester) async {
    final recorder = LocalPcmRecordingService();
    final whisper =
        WhisperTranscriptionService(model: WhisperModel.tinyEn, language: 'en');

    final docsDir = await getApplicationDocumentsDirectory();
    final outputPath =
        '${docsDir.path}/recordings/smoke_${DateTime.now().millisecondsSinceEpoch}.wav';
    await Directory('${docsDir.path}/recordings').create(recursive: true);

    try {
      await recorder.startRecording(wavOutputPath: outputPath);
      await Future<void>.delayed(const Duration(seconds: 2));
      final stoppedPath = await recorder.stopRecording();

      final file = File(stoppedPath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(44));

      await whisper.ensureModelReady().timeout(const Duration(minutes: 4));
      final transcript = await whisper
          .transcribeFile(stoppedPath)
          .timeout(const Duration(minutes: 4));

      expect(transcript, isA<String>());
    } finally {
      await recorder.dispose();
    }
  });
}
