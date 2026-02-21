import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

class LiveTranscriptionState {
  const LiveTranscriptionState({
    required this.finalText,
    required this.interimText,
  });

  final String finalText;
  final String interimText;

  String get fullText => [finalText, interimText]
      .where((e) => e.trim().isNotEmpty)
      .join(' ')
      .trim();
}

class LiveRecordingResult {
  const LiveRecordingResult({
    required this.audioPath,
    required this.transcript,
    required this.structuredNotes,
  });

  final String audioPath;
  final String transcript;
  final String structuredNotes;
}

class GeminiLiveRecordingService {
  GeminiLiveRecordingService({
    required this.apiKey,
    this.model = 'models/gemini-2.5-flash-native-audio-latest',
    this.voiceName = 'Aoede',
    this.systemInstruction = _defaultSystemInstruction,
    this.chunkDuration = const Duration(milliseconds: 160),
  });

  static const String _defaultSystemInstruction =
      'You are a professional note-taker. Transcribe this lecture accurately and, at the end, provide a well-structured summary with headings for Main Topics, Key Definitions, and Action Items.';

  final String apiKey;
  final String model;
  final String voiceName;
  final String systemInstruction;
  // Recorder is intentionally locked to Linear PCM, 16kHz, mono, 16-bit.
  final String audioMimeType = 'audio/pcm;rate=16000';
  final int sampleRate = 16000;
  final int channelCount = 1;
  final int bitsPerSample = 16;
  final Duration chunkDuration;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final BytesBuilder _pendingAudio = BytesBuilder(copy: false);

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  IOSink? _pcmSink;
  File? _pcmFile;
  String? _targetWavPath;

  Completer<void>? _setupCompleter;
  Completer<String>? _finalNotesCompleter;

  LiveTranscriptionState _transcriptionState =
      const LiveTranscriptionState(finalText: '', interimText: '');
  String _lastFinalSegment = '';
  String _latestModelText = '';
  bool _isDisposed = false;
  bool _isRecording = false;
  bool _awaitingFinalNotes = false;
  String? _setupErrorMessage;

  void Function(LiveTranscriptionState state)? _onTranscriptionUpdate;

  bool get _isNativeAudioModel => model.toLowerCase().contains('native-audio');

  int get _targetChunkBytes {
    final bytesPerSecond = sampleRate * channelCount * (bitsPerSample ~/ 8);
    final value = (bytesPerSecond * chunkDuration.inMilliseconds) ~/ 1000;
    return value.clamp(1024, 8192);
  }

  Future<void> startRecording({
    required String wavOutputPath,
    required void Function(LiveTranscriptionState state) onTranscriptionUpdate,
  }) async {
    if (_isDisposed) {
      throw StateError('GeminiLiveRecordingService has been disposed.');
    }
    if (_isRecording) {
      throw StateError('A recording session is already in progress.');
    }
    if (apiKey.trim().isEmpty || apiKey == 'YOUR_API_KEY') {
      throw StateError('Gemini API key is missing.');
    }

    _onTranscriptionUpdate = onTranscriptionUpdate;
    _transcriptionState =
        const LiveTranscriptionState(finalText: '', interimText: '');
    _lastFinalSegment = '';
    _latestModelText = '';
    _awaitingFinalNotes = false;
    _setupErrorMessage = null;
    _targetWavPath = wavOutputPath;
    _setupCompleter = Completer<void>();
    _finalNotesCompleter = Completer<String>();
    _pendingAudio.clear();

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission was denied.');
    }

    final pcmPath = _wavPathToPcmPath(wavOutputPath);
    _pcmFile = File(pcmPath);
    await _pcmFile!.parent.create(recursive: true);
    _pcmSink = _pcmFile!.openWrite(mode: FileMode.writeOnly);

    try {
      await _connectAndSetup();
      await _startAudioStream();
    } catch (e) {
      await _closeSession();
      rethrow;
    }

    _isRecording = true;
    _notifyTranscription();
  }

  Future<LiveRecordingResult> stopRecording() async {
    if (!_isRecording) {
      throw StateError('No active recording session.');
    }

    _isRecording = false;

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _audioRecorder.stop();

    await _flushPendingAudio(force: true);

    _awaitingFinalNotes = true;
    _sendJson({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {
                'text':
                    'The lecture has ended. Provide final structured notes with headings for Main Topics, Key Definitions, and Action Items.'
              }
            ]
          }
        ],
        'turnComplete': true,
      }
    });

    String structuredNotes = '';
    try {
      final completer = _finalNotesCompleter;
      if (completer != null) {
        structuredNotes = await completer.future.timeout(
          const Duration(seconds: 40),
          onTimeout: () => _latestModelText.trim(),
        );
      }
    } catch (_) {
      structuredNotes = _latestModelText.trim();
    }

    await _closeSession();
    final wavPath = await _finalizeWavFile();

    return LiveRecordingResult(
      audioPath: wavPath,
      transcript: _transcriptionState.fullText,
      structuredNotes: structuredNotes.trim(),
    );
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _closeSession();
    await _audioRecorder.dispose();
  }

  Future<void> _connectAndSetup() async {
    final uri = Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$apiKey',
    );
    _socket = await WebSocket.connect(uri.toString());
    _socketSubscription = _socket!.listen(
      _onSocketMessage,
      onError: _onSocketError,
      onDone: _onSocketDone,
      cancelOnError: false,
    );

    final generationConfig = <String, dynamic>{
      'responseModalities': _isNativeAudioModel ? ['AUDIO'] : ['TEXT'],
    };
    if (_isNativeAudioModel) {
      generationConfig['speechConfig'] = {
        'voiceConfig': {
          'prebuiltVoiceConfig': {'voiceName': voiceName}
        }
      };
    }

    _sendJson({
      'setup': {
        'model': model,
        'generationConfig': generationConfig,
        'inputAudioTranscription': {},
        'outputAudioTranscription': {},
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction}
          ]
        },
      }
    });

    final setup = _setupCompleter;
    if (setup != null) {
      await setup.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw StateError('Timed out waiting for Gemini Live setup.'),
      );
    }
  }

  Future<void> _startAudioStream() async {
    final stream = await _audioRecorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channelCount,
      ),
    );

    _audioSubscription = stream.listen(
      (chunk) async {
        _pcmSink?.add(chunk);
        _pendingAudio.add(chunk);
        await _flushPendingAudio();
      },
      onError: _onSocketError,
      cancelOnError: false,
    );
  }

  Future<void> _flushPendingAudio({bool force = false}) async {
    if (_socket == null) {
      return;
    }
    final bytes = _pendingAudio.takeBytes();
    if (bytes.isEmpty) {
      return;
    }

    final chunkBytes = _targetChunkBytes;
    var offset = 0;
    final maxSendLength =
        force ? bytes.length : (bytes.length - (bytes.length % chunkBytes));
    while (offset < maxSendLength) {
      final end = force
          ? (offset + chunkBytes <= maxSendLength
              ? offset + chunkBytes
              : maxSendLength)
          : offset + chunkBytes;
      final chunk = bytes.sublist(offset, end);
      _sendAudioChunk(chunk);
      offset = end;
    }

    if (offset < bytes.length) {
      _pendingAudio.add(bytes.sublist(offset));
    }
  }

  void _sendAudioChunk(Uint8List chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _sendJson({
      'realtimeInput': {
        'mediaChunks': [
          {
            'data': base64Encode(chunk),
            'mimeType': audioMimeType,
          }
        ]
      }
    });
  }

  void _onSocketMessage(dynamic message) {
    final String payload;
    if (message is String) {
      payload = message;
    } else if (message is List<int>) {
      payload = utf8.decode(message, allowMalformed: true);
    } else {
      return;
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final setupComplete = decoded['setupComplete'];
    if (setupComplete != null && !(_setupCompleter?.isCompleted ?? true)) {
      _setupCompleter?.complete();
    }

    final error = decoded['error'];
    if (error != null) {
      _setupErrorMessage = _extractErrorMessage(error);
      if (!(_setupCompleter?.isCompleted ?? true)) {
        _setupCompleter?.completeError(
          StateError('Gemini Live setup failed: $_setupErrorMessage'),
        );
      }
      if (!(_finalNotesCompleter?.isCompleted ?? true)) {
        _finalNotesCompleter?.complete(_latestModelText.trim());
      }
      _awaitingFinalNotes = false;
      return;
    }

    final serverContent = decoded['serverContent'];
    if (serverContent is Map<String, dynamic>) {
      final inputTranscription = serverContent['inputTranscription'];
      if (inputTranscription is Map<String, dynamic>) {
        _handleInputTranscription(inputTranscription);
      }

      final outputTranscription = serverContent['outputTranscription'];
      if (outputTranscription is Map<String, dynamic>) {
        final text = (outputTranscription['text'] ?? '').toString().trim();
        if (text.isNotEmpty) {
          _latestModelText = _mergeModelText(_latestModelText, text);
        }
      }

      final modelTurn = serverContent['modelTurn'];
      final modelText = _extractModelTurnText(modelTurn);
      if (modelText.isNotEmpty) {
        _latestModelText = _mergeModelText(_latestModelText, modelText);
      }

      final turnComplete = serverContent['turnComplete'] == true;
      if (turnComplete &&
          _awaitingFinalNotes &&
          !(_finalNotesCompleter?.isCompleted ?? true)) {
        _finalNotesCompleter?.complete(_latestModelText.trim());
        _awaitingFinalNotes = false;
      }
    }
  }

  void _handleInputTranscription(Map<String, dynamic> inputTranscription) {
    final text = (inputTranscription['text'] ?? '').toString().trim();
    if (text.isEmpty) {
      return;
    }

    final isFinal = _isFinalTranscriptionChunk(inputTranscription);
    if (isFinal) {
      if (text != _lastFinalSegment) {
        _transcriptionState = LiveTranscriptionState(
          finalText: _appendDistinct(_transcriptionState.finalText, text),
          interimText: '',
        );
        _lastFinalSegment = text;
      } else {
        _transcriptionState = LiveTranscriptionState(
          finalText: _transcriptionState.finalText,
          interimText: '',
        );
      }
    } else {
      _transcriptionState = LiveTranscriptionState(
        finalText: _transcriptionState.finalText,
        interimText: text,
      );
    }
    _notifyTranscription();
  }

  bool _isFinalTranscriptionChunk(Map<String, dynamic> chunk) {
    final dynamic direct =
        chunk['final'] ?? chunk['isFinal'] ?? chunk['finished'];
    if (direct is bool) {
      return direct;
    }
    if (direct is String) {
      return direct.toLowerCase() == 'true';
    }
    return false;
  }

  String _extractModelTurnText(dynamic modelTurn) {
    if (modelTurn is! Map<String, dynamic>) {
      return '';
    }
    final parts = modelTurn['parts'];
    if (parts is! List) {
      return '';
    }
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map<String, dynamic>) {
        final text = (part['text'] ?? '').toString();
        if (text.trim().isNotEmpty) {
          if (buffer.isNotEmpty) {
            buffer.writeln();
          }
          buffer.write(text.trim());
        }
      }
    }
    return buffer.toString().trim();
  }

  String _mergeModelText(String previous, String next) {
    if (previous.isEmpty) {
      return next;
    }
    if (next.isEmpty || next == previous) {
      return previous;
    }
    if (next.startsWith(previous)) {
      return next;
    }
    if (previous.startsWith(next)) {
      return previous;
    }
    return '$previous\n$next';
  }

  String _appendDistinct(String existing, String chunk) {
    if (existing.isEmpty) {
      return chunk;
    }
    if (chunk.isEmpty) {
      return existing;
    }
    if (chunk == existing || existing.endsWith(chunk)) {
      return existing;
    }
    if (chunk.startsWith(existing)) {
      return chunk;
    }
    return '$existing $chunk'.trim();
  }

  void _notifyTranscription() {
    _onTranscriptionUpdate?.call(_transcriptionState);
  }

  void _sendJson(Map<String, dynamic> data) {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    socket.add(jsonEncode(data));
  }

  void _onSocketError(Object error, [StackTrace? stackTrace]) {
    if (!(_setupCompleter?.isCompleted ?? true)) {
      _setupCompleter?.completeError(error, stackTrace);
    }
    if (_awaitingFinalNotes && !(_finalNotesCompleter?.isCompleted ?? true)) {
      _finalNotesCompleter?.complete(_latestModelText.trim());
      _awaitingFinalNotes = false;
    }
  }

  void _onSocketDone() {
    if (!(_setupCompleter?.isCompleted ?? true)) {
      final detail = (_setupErrorMessage?.trim().isNotEmpty ?? false)
          ? ' $_setupErrorMessage'
          : '';
      _setupCompleter?.completeError(
        StateError('Gemini Live socket closed before setup completed.$detail'),
      );
    }
    if (_awaitingFinalNotes && !(_finalNotesCompleter?.isCompleted ?? true)) {
      _finalNotesCompleter?.complete(_latestModelText.trim());
      _awaitingFinalNotes = false;
    }
  }

  String _extractErrorMessage(dynamic error) {
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString().trim();
      }
      final status = error['status'];
      final code = error['code'];
      if (status != null || code != null) {
        return 'status=${status ?? 'unknown'}, code=${code ?? 'unknown'}';
      }
      return error.toString();
    }
    if (error == null) {
      return 'Unknown setup error';
    }
    return error.toString();
  }

  Future<void> _closeSession() async {
    try {
      await _audioRecorder.stop();
    } catch (_) {
      // Ignore. Recorder may already be stopped.
    }

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;

    await _pcmSink?.flush();
    await _pcmSink?.close();
    _pcmSink = null;
  }

  Future<String> _finalizeWavFile() async {
    final wavPath = _targetWavPath;
    final pcm = _pcmFile;
    if (wavPath == null || pcm == null) {
      throw StateError('Recording output paths are unavailable.');
    }

    final wavFile = File(wavPath);
    await wavFile.parent.create(recursive: true);

    final pcmLength = await pcm.length();
    final header = _wavHeader(
      dataLength: pcmLength,
      sampleRate: sampleRate,
      channelCount: channelCount,
      bitsPerSample: bitsPerSample,
    );

    final sink = wavFile.openWrite(mode: FileMode.writeOnly);
    sink.add(header);
    await sink.addStream(pcm.openRead());
    await sink.flush();
    await sink.close();

    if (pcm.existsSync()) {
      await pcm.delete();
    }

    _pcmFile = null;
    _targetWavPath = null;
    return wavPath;
  }

  String _wavPathToPcmPath(String wavPath) {
    if (wavPath.toLowerCase().endsWith('.wav')) {
      return '${wavPath.substring(0, wavPath.length - 4)}.pcm';
    }
    return '$wavPath.pcm';
  }

  Uint8List _wavHeader({
    required int dataLength,
    required int sampleRate,
    required int channelCount,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * channelCount * (bitsPerSample ~/ 8);
    final blockAlign = channelCount * (bitsPerSample ~/ 8);
    final totalLength = 36 + dataLength;

    final buffer = ByteData(44);
    var offset = 0;

    void writeAscii(String value) {
      for (final codeUnit in value.codeUnits) {
        buffer.setUint8(offset++, codeUnit);
      }
    }

    writeAscii('RIFF');
    buffer.setUint32(offset, totalLength, Endian.little);
    offset += 4;
    writeAscii('WAVE');
    writeAscii('fmt ');
    buffer.setUint32(offset, 16, Endian.little);
    offset += 4;
    buffer.setUint16(offset, 1, Endian.little);
    offset += 2;
    buffer.setUint16(offset, channelCount, Endian.little);
    offset += 2;
    buffer.setUint32(offset, sampleRate, Endian.little);
    offset += 4;
    buffer.setUint32(offset, byteRate, Endian.little);
    offset += 4;
    buffer.setUint16(offset, blockAlign, Endian.little);
    offset += 2;
    buffer.setUint16(offset, bitsPerSample, Endian.little);
    offset += 2;
    writeAscii('data');
    buffer.setUint32(offset, dataLength, Endian.little);

    return buffer.buffer.asUint8List();
  }
}
