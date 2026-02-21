import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class LocalPcmRecordingService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  bool _isRecording = false;
  double _maxAmplitudeDb = -160.0;

  bool get isRecording => _isRecording;
  double get maxAmplitudeDb => _maxAmplitudeDb;

  Future<void> startRecording({required String wavOutputPath}) async {
    if (_isRecording) {
      throw StateError('A recording session is already in progress.');
    }

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission was denied.');
    }

    if (kDebugMode) {
      try {
        final inputs = await _audioRecorder.listInputDevices();
        print('Recorder input devices: $inputs');
      } catch (_) {}
    }
    _maxAmplitudeDb = -160.0;

    // Use legacy MediaRecorder path for stability on emulators/devices.
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 128000,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: AndroidRecordConfig(
          useLegacy: true,
          audioSource: AndroidAudioSource.mic,
          manageBluetooth: false,
        ),
      ),
      path: wavOutputPath,
    );
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 250))
        .listen((amp) {
      if (amp.current > _maxAmplitudeDb) {
        _maxAmplitudeDb = amp.current;
      }
    });

    _isRecording = true;
  }

  Future<String> stopRecording() async {
    if (!_isRecording) {
      throw StateError('No active recording session.');
    }

    final path = await _audioRecorder.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _isRecording = false;

    if (path == null || path.trim().isEmpty) {
      throw StateError('Recorder did not return an output path.');
    }
    return path;
  }

  Future<void> dispose() async {
    if (_isRecording) {
      try {
        await _audioRecorder.stop();
      } catch (_) {
        // Ignore dispose-time stop failures.
      }
      _isRecording = false;
    }
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    await _audioRecorder.dispose();
  }
}
