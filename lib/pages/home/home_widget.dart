import '/services/local_pcm_recording_service.dart';
import '/services/gemini_service.dart';
import '/env.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:async';
import 'dart:io';
import '/backend/recordings/recording_store.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'home_model.dart';
export 'home_model.dart';

class HomeWidget extends StatefulWidget {
  const HomeWidget({super.key});

  static const routeName = 'Home';
  static const routePath = '/home';

  @override
  State<HomeWidget> createState() => _HomeWidgetState();
}

class _HomeWidgetState extends State<HomeWidget> {
  late HomeModel _model;
  late LocalPcmRecordingService _recordingService;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final stt.SpeechToText _speech = stt.SpeechToText();
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _speechAvailable = false;
  bool _speechListening = false;
  String _finalTranscript = '';
  String _liveTranscript = '';
  List<RecordingEntry> _recordings = [];
  bool _loadingRecordings = true;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomeModel());
    _recordingService = LocalPcmRecordingService();
    _loadRecordings();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _speech.stop();
    _recordingService.dispose();
    _model.dispose();

    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_isRecording) {
      return;
    }

    final recordingsDir = await _ensureRecordingsDir();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final audioPath = '${recordingsDir.path}/lecture_$timestamp.m4a';

    setState(() {
      _finalTranscript = '';
      _liveTranscript = '';
      _recordingDuration = Duration.zero;
    });

    try {
      await _recordingService.startRecording(wavOutputPath: audioPath);
      await _startSpeechToText();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to start recording: $e')),
      );
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isRecording = true;
    });
    _startRecordingTimer();
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) {
      return;
    }

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });
    _recordingTimer?.cancel();
    if (_speechListening) {
      await _speech.stop();
      _speechListening = false;
    }

    String audioPath;
    double maxAmplitudeDb;
    try {
      audioPath = await _recordingService.stopRecording();
      maxAmplitudeDb = _recordingService.maxAmplitudeDb;
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to stop recording: $e')),
      );
      setState(() {
        _isProcessing = false;
      });
      return;
    }

    final geminiService = GeminiService(geminiApiKey);
    var aiResult = const LectureNotesResult(notes: '', transcript: '');
    try {
      aiResult = await geminiService.generateNotesFromAudio(audioPath);
    } catch (_) {
      // If AI processing fails, save recording locally with fallback notes.
    }

    var transcript = aiResult.transcript.trim();
    if (transcript.isEmpty) {
      transcript = _combinedTranscript;
    }
    var notes = aiResult.notes.trim();
    if (notes.isEmpty && transcript.isNotEmpty) {
      notes = await geminiService.generateNotes(transcript);
    }
    _finalTranscript = transcript;
    final titleOverride = await _promptForRecordingTitle();

    try {
      if (!mounted) {
        return;
      }
      await RecordingStore.saveRecording(
        audioPath: audioPath,
        transcript: transcript,
        duration: _recordingDuration,
        notesOverride: notes,
        titleOverride: titleOverride,
      );

      if (!mounted) {
        return;
      }
      await _loadRecordings();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (notes.isNotEmpty || transcript.isNotEmpty)
                ? 'Recording saved and notes generated.'
                : (maxAmplitudeDb < -45.0
                    ? 'Recording saved, but microphone signal was too low. Check emulator mic input.'
                    : 'Recording saved locally. AI returned no transcript.'),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Recording saved, but note generation failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<Directory> _ensureRecordingsDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/recordings');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRecording) {
        return;
      }
      setState(() {
        _recordingDuration += const Duration(seconds: 1);
      });
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }

  String _defaultRecordingTitle() {
    final now = DateTime.now();
    return 'Lecture ${dateTimeFormat('MMMEd', now)} ${dateTimeFormat('jm', now)}';
  }

  Future<String?> _promptForRecordingTitle() async {
    if (!mounted) {
      return null;
    }
    final controller = TextEditingController(text: _defaultRecordingTitle());
    final title = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this recording'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Physics Lecture 4',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('Use default'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return title;
  }

  String get _transcriptPreview {
    final text = _combinedTranscript;
    if (text.length <= 180) {
      return text;
    }
    return '${text.substring(0, 180)}...';
  }

  String get _combinedTranscript => [_finalTranscript, _liveTranscript]
      .where((e) => e.trim().isNotEmpty)
      .join(' ')
      .trim();

  Future<void> _startSpeechToText() async {
    _speechAvailable = await _speech.initialize(
      onStatus: _handleSpeechStatus,
      onError: (_) {},
    );
    if (!_speechAvailable || _speechListening) {
      return;
    }
    _speechListening = true;
    await _speech.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(hours: 2),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
      ),
    );
  }

  void _handleSpeechStatus(String status) {
    if (status == 'done') {
      _speechListening = false;
      if (_isRecording) {
        _startSpeechToText();
      }
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) {
      return;
    }
    if (result.finalResult) {
      final text = result.recognizedWords.trim();
      if (text.isNotEmpty) {
        _finalTranscript =
            [_finalTranscript, text].where((e) => e.isNotEmpty).join(' ');
      }
      _liveTranscript = '';
    } else {
      _liveTranscript = result.recognizedWords;
    }
    setState(() {});
  }

  Future<void> _loadRecordings() async {
    final entries = await RecordingStore.loadRecordings();
    if (!mounted) {
      return;
    }
    setState(() {
      _recordings = entries;
      _loadingRecordings = false;
    });
  }

  void _openRecording(RecordingEntry entry) {
    context.pushNamed(
      NotesDetailPageWidget.routeName,
      queryParameters: {
        'audioPath': serializeParam(entry.audioPath, ParamType.string),
        'notesPath': serializeParam(entry.notesPath, ParamType.string),
        'title': serializeParam(entry.title, ParamType.string),
        'createdAt': serializeParam(entry.createdAt, ParamType.dateTime),
        'durationSeconds':
            serializeParam(entry.duration.inSeconds, ParamType.int),
      }.withoutNulls,
    );
  }

  Widget _buildLectureCard(RecordingEntry entry) {
    return InkWell(
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () => _openRecording(entry),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                width: 48.0,
                height: 48.0,
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).accent1,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Align(
                  alignment: const AlignmentDirectional(0, 0),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: FlutterFlowTheme.of(context).primary,
                    size: 24.0,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: FlutterFlowTheme.of(context).titleMedium.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w600,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .titleMedium
                                  .fontStyle,
                            ),
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w600,
                            fontStyle: FlutterFlowTheme.of(context)
                                .titleMedium
                                .fontStyle,
                          ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(0, 4, 0, 0),
                      child: Text(
                        '${dateTimeFormat('relative', entry.createdAt)} • ${_formatDuration(entry.duration)}',
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              font: GoogleFonts.inter(
                                fontWeight: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .fontWeight,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .fontStyle,
                              ),
                              color: FlutterFlowTheme.of(context).secondaryText,
                              letterSpacing: 0.0,
                              fontWeight: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .fontWeight,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .fontStyle,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.more_vert_rounded,
                color: FlutterFlowTheme.of(context).secondaryText,
                size: 20.0,
              ),
            ].divide(const SizedBox(width: 12)),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentLecturesList() {
    if (_loadingRecordings) {
      return Center(
        child: Text(
          'Loading recordings...',
          style: FlutterFlowTheme.of(context).bodySmall.override(
                font: GoogleFonts.inter(
                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                ),
                color: FlutterFlowTheme.of(context).secondaryText,
                letterSpacing: 0.0,
              ),
        ),
      );
    }

    if (_recordings.isEmpty) {
      return Center(
        child: Text(
          'No recordings yet.',
          style: FlutterFlowTheme.of(context).bodySmall.override(
                font: GoogleFonts.inter(
                  fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                  fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                ),
                color: FlutterFlowTheme.of(context).secondaryText,
                letterSpacing: 0.0,
              ),
        ),
      );
    }

    final recentLectures = _recordings.take(3).toList();

    return ListView(
      padding: EdgeInsets.zero,
      primary: false,
      scrollDirection: Axis.vertical,
      children: recentLectures
          .map(_buildLectureCard)
          .toList()
          .divide(const SizedBox(height: 12)),
    );
  }

  Widget _buildRecordingPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: const AlignmentDirectional(0, 0),
          child: InkWell(
            splashColor: Colors.transparent,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: _toggleRecording,
            child: Material(
              color: Colors.transparent,
              elevation: 8.0,
              shape: const CircleBorder(),
              child: Container(
                width: 120.0,
                height: 120.0,
                decoration: BoxDecoration(
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 20.0,
                      color: Colors.white,
                      offset: Offset(0, 8),
                    )
                  ],
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6366F1),
                      FlutterFlowTheme.of(context).primary
                    ],
                    stops: const [0.8, 1.0],
                    begin: const AlignmentDirectional(0, -1),
                    end: const AlignmentDirectional(0, 1),
                  ),
                  shape: BoxShape.circle,
                ),
                child: Align(
                  alignment: const AlignmentDirectional(0, 0),
                  child: Icon(
                    Icons.mic_rounded,
                    color: FlutterFlowTheme.of(context).info,
                    size: 48.0,
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(
          _isRecording
              ? 'Recording...'
              : (_isProcessing ? 'Processing...' : 'Record Lecture'),
          textAlign: TextAlign.center,
          style: FlutterFlowTheme.of(context).headlineSmall.override(
                font: GoogleFonts.interTight(
                  fontWeight: FontWeight.bold,
                  fontStyle:
                      FlutterFlowTheme.of(context).headlineSmall.fontStyle,
                ),
                letterSpacing: 0.0,
                fontWeight: FontWeight.bold,
                fontStyle: FlutterFlowTheme.of(context).headlineSmall.fontStyle,
              ),
        ),
        Text(
          _isRecording
              ? 'Tap to stop • ${_formatDuration(_recordingDuration)}'
              : (_isProcessing
                  ? 'Generating transcript and notes...'
                  : 'Tap to start recording your lecture'),
          textAlign: TextAlign.center,
          style: FlutterFlowTheme.of(context).bodyMedium.override(
                font: GoogleFonts.inter(
                  fontWeight:
                      FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                  fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                ),
                color: FlutterFlowTheme.of(context).secondaryText,
                letterSpacing: 0.0,
                fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
              ),
        ),
        if (!_isRecording && !_isProcessing && _transcriptPreview.isNotEmpty)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 88.0),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).secondaryBackground,
              borderRadius: BorderRadius.circular(12.0),
            ),
            padding: const EdgeInsets.all(12.0),
            child: Text(
              _transcriptPreview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: FlutterFlowTheme.of(context).bodySmall.override(
                    font: GoogleFonts.inter(
                      fontWeight:
                          FlutterFlowTheme.of(context).bodySmall.fontWeight,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodySmall.fontStyle,
                    ),
                    color: FlutterFlowTheme.of(context).secondaryText,
                    letterSpacing: 0.0,
                    fontWeight:
                        FlutterFlowTheme.of(context).bodySmall.fontWeight,
                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                  ),
            ),
          ),
      ].divide(const SizedBox(height: 16)),
    );
  }

  Future<void> _toggleRecording() async {
    if (_isProcessing) {
      return;
    }
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _openSearch() async {
    if (_loadingRecordings) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loading recordings...')),
        );
      }
      return;
    }
    await showSearch<RecordingEntry?>(
      context: context,
      delegate: _RecordingSearchDelegate(
        recordings: _recordings,
        openRecording: _openRecording,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: false,
          title: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                width: 40.0,
                height: 40.0,
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).primary,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Align(
                  alignment: const AlignmentDirectional(0, 0),
                  child: Icon(
                    Icons.school_rounded,
                    color: FlutterFlowTheme.of(context).info,
                    size: 24.0,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lectra',
                    style: FlutterFlowTheme.of(context).titleLarge.override(
                          font: GoogleFonts.interTight(
                            fontWeight: FontWeight.bold,
                            fontStyle: FlutterFlowTheme.of(context)
                                .titleLarge
                                .fontStyle,
                          ),
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.bold,
                          fontStyle:
                              FlutterFlowTheme.of(context).titleLarge.fontStyle,
                        ),
                  ),
                  Text(
                    'Ready to record',
                    style: FlutterFlowTheme.of(context).bodySmall.override(
                          font: GoogleFonts.inter(
                            fontWeight: FlutterFlowTheme.of(context)
                                .bodySmall
                                .fontWeight,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodySmall
                                .fontStyle,
                          ),
                          color: FlutterFlowTheme.of(context).secondaryText,
                          letterSpacing: 0.0,
                          fontWeight:
                              FlutterFlowTheme.of(context).bodySmall.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodySmall.fontStyle,
                        ),
                  ),
                ],
              ),
            ].divide(const SizedBox(width: 12)),
          ),
          actions: [
            Align(
              alignment: const AlignmentDirectional(0, 0),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
                child: FlutterFlowIconButton(
                  borderRadius: 12.0,
                  buttonSize: 40.0,
                  fillColor: FlutterFlowTheme.of(context).secondaryBackground,
                  icon: Icon(
                    Icons.notifications_none_rounded,
                    color: FlutterFlowTheme.of(context).primaryText,
                    size: 24.0,
                  ),
                  onPressed: () async {
                    context.pushNamed(NotificationPageWidget.routeName);
                  },
                ),
              ),
            ),
          ],
          centerTitle: false,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Lectures',
                      style:
                          FlutterFlowTheme.of(context).headlineMedium.override(
                                font: GoogleFonts.interTight(
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .headlineMedium
                                      .fontStyle,
                                ),
                                letterSpacing: 0.0,
                                fontWeight: FontWeight.w600,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .headlineMedium
                                    .fontStyle,
                              ),
                    ),
                    InkWell(
                      splashColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () async {
                        context.pushNamed(NotesPageWidget.routeName);
                      },
                      child: Text(
                        'View all',
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontStyle,
                              ),
                              color: FlutterFlowTheme.of(context).primary,
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w500,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                Expanded(child: _buildRecentLecturesList()),
                _buildRecordingPanel(),
                Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        InkWell(
                          splashColor: Colors.transparent,
                          focusColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          onTap: () async {
                            context.pushNamed(NotesPageWidget.routeName);
                          },
                          child: Container(
                            width: 56.0,
                            height: 56.0,
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context)
                                  .secondaryBackground,
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            child: Align(
                              alignment: const AlignmentDirectional(0, 0),
                              child: Icon(
                                Icons.folder_outlined,
                                color: FlutterFlowTheme.of(context).primaryText,
                                size: 28.0,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 0),
                          child: Text(
                            'Library',
                            textAlign: TextAlign.center,
                            style:
                                FlutterFlowTheme.of(context).bodySmall.override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.w500,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                      letterSpacing: 0.0,
                                      fontWeight: FontWeight.w500,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        InkWell(
                          splashColor: Colors.transparent,
                          focusColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          onTap: _openSearch,
                          child: Container(
                            width: 56.0,
                            height: 56.0,
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context)
                                  .secondaryBackground,
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            child: Align(
                              alignment: const AlignmentDirectional(0, 0),
                              child: Icon(
                                Icons.search_rounded,
                                color: FlutterFlowTheme.of(context).primaryText,
                                size: 28.0,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 0),
                          child: Text(
                            'Search',
                            textAlign: TextAlign.center,
                            style:
                                FlutterFlowTheme.of(context).bodySmall.override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.w500,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                      letterSpacing: 0.0,
                                      fontWeight: FontWeight.w500,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        InkWell(
                          splashColor: Colors.transparent,
                          focusColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          onTap: () async {
                            context.pushNamed(SettingPageWidget.routeName);
                          },
                          child: Container(
                            width: 56.0,
                            height: 56.0,
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context)
                                  .secondaryBackground,
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            child: Align(
                              alignment: const AlignmentDirectional(0, 0),
                              child: Icon(
                                Icons.settings_outlined,
                                color: FlutterFlowTheme.of(context).primaryText,
                                size: 28.0,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 0),
                          child: Text(
                            'Settings',
                            textAlign: TextAlign.center,
                            style:
                                FlutterFlowTheme.of(context).bodySmall.override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.w500,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .fontStyle,
                                      ),
                                      letterSpacing: 0.0,
                                      fontWeight: FontWeight.w500,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ].divide(const SizedBox(height: 32)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingSearchDelegate extends SearchDelegate<RecordingEntry?> {
  _RecordingSearchDelegate({
    required List<RecordingEntry> recordings,
    required this.openRecording,
  }) : _recordings = recordings;

  final List<RecordingEntry> _recordings;
  final void Function(RecordingEntry entry) openRecording;

  List<RecordingEntry> _filterRecordings(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return _recordings;
    }
    return _recordings.where((entry) {
      return entry.title.toLowerCase().contains(normalized) ||
          entry.transcriptPreview.toLowerCase().contains(normalized);
    }).toList();
  }

  @override
  String get searchFieldLabel => 'Search recordings';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
          icon: const Icon(Icons.clear_rounded),
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildResultsList(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildResultsList(context);
  }

  Widget _buildResultsList(BuildContext context) {
    final items = _filterRecordings(query);
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No recordings found.',
          style: FlutterFlowTheme.of(context).bodyMedium.override(
                font: GoogleFonts.inter(
                  fontWeight:
                      FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                  fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                ),
                color: FlutterFlowTheme.of(context).secondaryText,
                letterSpacing: 0.0,
              ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10.0),
      itemBuilder: (context, index) {
        final entry = items[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12.0),
          onTap: () {
            close(context, entry);
            openRecording(entry);
          },
          child: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).secondaryBackground,
              borderRadius: BorderRadius.circular(12.0),
            ),
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  color: FlutterFlowTheme.of(context).primary,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlutterFlowTheme.of(context).titleSmall.override(
                              font: GoogleFonts.interTight(
                                fontWeight: FontWeight.w600,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .titleSmall
                                    .fontStyle,
                              ),
                              letterSpacing: 0.0,
                            ),
                      ),
                      Text(
                        dateTimeFormat('relative', entry.createdAt),
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              font: GoogleFonts.inter(
                                fontWeight: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .fontWeight,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .fontStyle,
                              ),
                              color: FlutterFlowTheme.of(context).secondaryText,
                              letterSpacing: 0.0,
                            ),
                      ),
                    ].divide(const SizedBox(height: 4.0)),
                  ),
                ),
              ].divide(const SizedBox(width: 10.0)),
            ),
          ),
        );
      },
    );
  }
}
