import '/services/local_pcm_recording_service.dart';
import '/services/gemini_service.dart';
import '/services/whisper_transcription_service.dart';
import '/services/battery_optimization_service.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import '/backend/recordings/recording_store.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:in_app_review/in_app_review.dart';
import 'home_model.dart';
export 'home_model.dart';

class HomeWidget extends StatefulWidget {
  const HomeWidget({super.key});

  static const routeName = 'Home';
  static const routePath = '/home';

  @override
  State<HomeWidget> createState() => _HomeWidgetState();
}

class _HomeWidgetState extends State<HomeWidget>
    with SingleTickerProviderStateMixin {
  late HomeModel _model;
  late LocalPcmRecordingService _recordingService;
  late WhisperTranscriptionService _transcriptionService;
  late final AnimationController _recordingPulseController;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  bool _isRecording = false;
  bool _isProcessing = false;
  List<RecordingEntry> _recordings = [];
  bool _loadingRecordings = true;
  bool _batteryPromptHandled = false;
  bool _playUpdateChecked = false;
  bool _reviewPromptShown = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomeModel());
    _recordingService = LocalPcmRecordingService();
    _transcriptionService = WhisperTranscriptionService();
    _recordingPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    unawaited(
      _transcriptionService.ensureModelReady().catchError((_) {
        // Model setup will retry on first transcription attempt.
      }),
    );
    _loadRecordings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeCheckPlayUpdate();
      _scheduleReviewPrompt();
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingPulseController.dispose();
    _recordingService.dispose();
    _model.dispose();

    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_isRecording) {
      return;
    }
    await _maybeHandleBatteryOptimization();

    final recordingsDir = await _ensureRecordingsDir();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final audioPath = '${recordingsDir.path}/lecture_$timestamp.wav';

    setState(() {
      _recordingDuration = Duration.zero;
    });

    try {
      await _recordingService.startRecording(wavOutputPath: audioPath);
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
    _recordingPulseController.repeat();
    _startRecordingTimer();
  }

  Future<void> _maybeHandleBatteryOptimization() async {
    if (!isAndroid || _batteryPromptHandled) {
      return;
    }
    _batteryPromptHandled = true;

    final isIgnoring =
        await BatteryOptimizationService.isIgnoringBatteryOptimizations();
    if (isIgnoring || !mounted) {
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Allow background recording'),
        content: const Text(
          'To keep recording when the screen locks or when you switch apps, allow Lectra to ignore battery optimization.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('later'),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('settings'),
            child: const Text('Open settings'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('allow'),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == 'later') {
      return;
    }

    if (action == 'settings') {
      await BatteryOptimizationService.openBatteryOptimizationSettings();
      return;
    }

    await BatteryOptimizationService.requestIgnoreBatteryOptimizations();
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) {
      return;
    }

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });
    _recordingPulseController.stop();
    _recordingPulseController.reset();
    _recordingTimer?.cancel();

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

    try {
      await _waitForAudioFileToStabilize(audioPath);

      final geminiService = GeminiService();
      String transcript = '';
      String notes = '';
      Object? transcriptionError;
      Object? notesError;

      try {
        transcript = await _transcriptionService
            .transcribeFile(audioPath)
            .timeout(_transcriptionTimeoutFor(_recordingDuration));
      } catch (e) {
        transcriptionError = e;
      }

      if (transcript.isNotEmpty) {
        try {
          notes = await geminiService
              .generateNotes(transcript)
              .timeout(_notesTimeoutForTranscript(transcript));
        } catch (e) {
          notesError = e;
        }
      }

      String? titleOverride;
      try {
        titleOverride = await _promptForRecordingTitle();
      } catch (_) {
        titleOverride = null;
      }

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

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadRecordings();
          }
        });
      }
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
                    : (transcriptionError != null
                        ? 'Recording saved locally. No transcript captured. ${transcriptionError is TimeoutException ? 'Transcription timed out.' : 'Please try again.'}'
                        : (notesError != null
                            ? 'Recording saved, transcript captured, but note structuring failed. Local fallback notes were saved.'
                            : 'Recording saved locally. No transcript captured.'))),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stop recording failed: $e')),
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

  Future<void> _maybeCheckPlayUpdate() async {
    if (_playUpdateChecked || !mounted) return;
    _playUpdateChecked = true;
    if (!Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability ==
          UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (_) {
      // Silent fail; don't block UX if Play Core check fails.
    }
  }

  void _scheduleReviewPrompt() {
    if (_reviewPromptShown) return;
    _reviewPromptShown = true;
    Future.delayed(const Duration(seconds: 5), () async {
      if (!mounted || !Platform.isAndroid) return;
      try {
        final review = InAppReview.instance;
        final available = await review.isAvailable();
        if (available) {
          await review.requestReview();
        } else {
          await review.openStoreListing(
            appStoreId: null,
            microsoftStoreId: null,
          );
        }
      } catch (_) {
        // Ignore failures; we don't block UX.
      }
    });
  }

  // (In-app update handles the flow; no manual store launch needed now.)

  Future<Directory> _ensureRecordingsDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/recordings');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<void> _waitForAudioFileToStabilize(String audioPath) async {
    final file = File(audioPath);
    var lastSize = -1;
    for (var i = 0; i < 6; i++) {
      if (!file.existsSync()) {
        await Future.delayed(const Duration(milliseconds: 120));
        continue;
      }
      final currentSize = file.lengthSync();
      if (currentSize > 4096 && currentSize == lastSize) {
        return;
      }
      lastSize = currentSize;
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  Duration _transcriptionTimeoutFor(Duration recordingDuration) {
    final minutes = recordingDuration.inMinutes;
    // Base 6 minutes + ~45 seconds per recorded minute, capped at 70 minutes.
    final seconds = 360 + (minutes * 45);
    final boundedSeconds = seconds.clamp(360, 4200).toInt();
    return Duration(seconds: boundedSeconds);
  }

  Duration _notesTimeoutForTranscript(String transcript) {
    final cleanedLength = transcript.trim().length;
    if (cleanedLength <= 0) {
      return const Duration(seconds: 90);
    }
    // Roughly align with chunked prompts (about 4.5k chars each).
    final estimatedChunks = (cleanedLength / 4500).ceil().clamp(1, 60).toInt();
    final seconds = 90 + (estimatedChunks * 45);
    final boundedSeconds = seconds.clamp(90, 1500).toInt();
    return Duration(seconds: boundedSeconds);
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
    final defaultTitle = _defaultRecordingTitle();
    final title = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (_) => _RecordingNameDialog(defaultTitle: defaultTitle),
    );
    return title;
  }

  Future<void> _loadRecordings() async {
    final entries = await RecordingStore.loadRecordings();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _recordings = entries;
        _loadingRecordings = false;
      });
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

  Future<void> _renameRecording(RecordingEntry entry) async {
    final controller = TextEditingController(text: entry.title);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename recording'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter recording name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    final newTitle = result?.trim() ?? '';
    if (newTitle.isEmpty || newTitle == entry.title) {
      return;
    }

    await RecordingStore.updateRecordingTitle(entry: entry, newTitle: newTitle);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadRecordings();
      }
    });
  }

  Future<void> _deleteRecording(RecordingEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move To Trash'),
        content: const Text(
          'This recording will be moved to Trash. You can restore it from Library > Trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await _moveRecordingToTrash(entry, allowUndo: false);
  }

  Future<void> _moveRecordingToTrash(
    RecordingEntry entry, {
    bool allowUndo = true,
  }) async {
    final trashedEntry = await RecordingStore.moveToTrash(entry);
    await _loadRecordings();
    if (!mounted || !allowUndo) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${entry.title}" moved to Trash'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await RecordingStore.restoreFromTrash(trashedEntry);
            await _loadRecordings();
          },
        ),
      ),
    );
  }

  Future<void> _shareRecording(RecordingEntry entry) async {
    final file = File(entry.audioPath);
    if (!file.existsSync()) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording file not found.')),
      );
      return;
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(entry.audioPath)],
          subject: entry.title,
          text: 'Lecture recording: ${entry.title}',
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to share recording: $e')),
      );
    }
  }

  Future<void> _onRecordingMenuSelected(
    RecordingEntry entry,
    String action,
  ) async {
    await hapticSelection();
    // Ensure menu route is fully dismissed before potentially triggering rebuilds.
    await Future<void>.delayed(Duration.zero);
    switch (action) {
      case 'open':
        _openRecording(entry);
        return;
      case 'rename':
        await _renameRecording(entry);
        return;
      case 'delete':
        await _deleteRecording(entry);
        return;
      case 'share':
        await _shareRecording(entry);
        return;
    }
  }

  Future<void> _showRecordingActionsSheet(RecordingEntry entry) async {
    await hapticSelection();
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openRecording(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Future<void>.delayed(Duration.zero);
                await _renameRecording(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _shareRecording(entry);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: FlutterFlowTheme.of(context).error,
              ),
              title: Text(
                'Move to Trash',
                style: TextStyle(color: FlutterFlowTheme.of(context).error),
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _deleteRecording(entry);
              },
            ),
            const SizedBox(height: 8.0),
          ],
        ),
      ),
    );
  }

  Widget _buildLectureCard(RecordingEntry entry) {
    return InkWell(
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () => _openRecording(entry),
      onLongPress: () => _showRecordingActionsSheet(entry),
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
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: FlutterFlowTheme.of(context).secondaryText,
                  size: 20.0,
                ),
                onSelected: (value) => _onRecordingMenuSelected(entry, value),
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'open',
                    child: Text('Open'),
                  ),
                  PopupMenuItem<String>(
                    value: 'rename',
                    child: Text('Rename'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Move to Trash'),
                  ),
                  PopupMenuItem<String>(
                    value: 'share',
                    child: Text('Share'),
                  ),
                ],
              ),
            ].divide(const SizedBox(width: 12)),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentLecturesList({double bottomPadding = 0.0}) {
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

    return ListView.separated(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemCount: _recordings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12.0),
      itemBuilder: (context, index) {
        final entry = _recordings[index];
        return Dismissible(
          key: ValueKey('home_recording_${entry.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            await hapticLight();
            await _moveRecordingToTrash(entry);
            return false;
          },
          background: Container(
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsetsDirectional.only(end: 20.0),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              color: FlutterFlowTheme.of(context).error,
            ),
          ),
          child: _buildLectureCard(entry),
        );
      },
    );
  }

  Widget _buildRecordingPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: const AlignmentDirectional(0, 0),
          child: _buildRecordingButton(),
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
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _isRecording
              ? Text(
                  'Tap to stop • ${_formatDuration(_recordingDuration)}',
                  key: const ValueKey('recording-status'),
                  textAlign: TextAlign.center,
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight:
                              FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                        ),
                        color: FlutterFlowTheme.of(context).secondaryText,
                        letterSpacing: 0.0,
                        fontWeight:
                            FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                )
              : _isProcessing
                  ? Column(
                      key: const ValueKey('processing-status'),
                      children: [
                        Text(
                          'Generating transcript and notes...',
                          textAlign: TextAlign.center,
                          style: FlutterFlowTheme.of(context)
                              .bodyMedium
                              .override(
                                font: GoogleFonts.inter(
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontStyle,
                                ),
                                color: FlutterFlowTheme.of(context)
                                    .secondaryText,
                                letterSpacing: 0.0,
                              ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 4,
                          width: 140,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 4,
                              backgroundColor: FlutterFlowTheme.of(context)
                                  .secondaryText
                                  .withValues(alpha: 0.12),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                FlutterFlowTheme.of(context).primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Tap to start recording your lecture',
                      key: const ValueKey('idle-status'),
                      textAlign: TextAlign.center,
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontWeight,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                            color: FlutterFlowTheme.of(context).secondaryText,
                            letterSpacing: 0.0,
                            fontWeight: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontWeight,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontStyle,
                          ),
                    ),
        ),
      ].divide(const SizedBox(height: 16)),
    );
  }

  Widget _buildQuickActionsRow() {
    return Row(
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
                unawaited(hapticSelection());
                context.pushNamed(NotesPageWidget.routeName);
              },
              child: Container(
                width: 56.0,
                height: 56.0,
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).secondaryBackground,
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
              padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 0),
              child: Text(
                'Library',
                textAlign: TextAlign.center,
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      font: GoogleFonts.inter(
                        fontWeight: FontWeight.w500,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodySmall.fontStyle,
                      ),
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w500,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodySmall.fontStyle,
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
                await hapticSelection();
                await _openSearch();
              },
              child: Container(
                width: 56.0,
                height: 56.0,
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).secondaryBackground,
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
              padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 0),
              child: Text(
                'Search',
                textAlign: TextAlign.center,
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      font: GoogleFonts.inter(
                        fontWeight: FontWeight.w500,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodySmall.fontStyle,
                      ),
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w500,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodySmall.fontStyle,
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
                unawaited(hapticSelection());
                context.pushNamed(SettingPageWidget.routeName);
              },
              child: Container(
                width: 56.0,
                height: 56.0,
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).secondaryBackground,
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
              padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 0),
              child: Text(
                'Settings',
                textAlign: TextAlign.center,
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      font: GoogleFonts.inter(
                        fontWeight: FontWeight.w500,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodySmall.fontStyle,
                      ),
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w500,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodySmall.fontStyle,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecordingButton() {
    return SizedBox(
      width: 168.0,
      height: 168.0,
      child: AnimatedBuilder(
        animation: _recordingPulseController,
        builder: (context, child) {
          final pulseValue = _recordingPulseController.value;
          final iconScale = _isRecording
              ? (1.0 + (math.sin(pulseValue * math.pi * 2) * 0.05))
              : 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (_isRecording) ...[
                _buildWaveRing(
                  progress: (pulseValue + 0.0) % 1.0,
                  color: FlutterFlowTheme.of(context).primary,
                ),
                _buildWaveRing(
                  progress: (pulseValue + 0.33) % 1.0,
                  color: FlutterFlowTheme.of(context).secondary,
                ),
                _buildWaveRing(
                  progress: (pulseValue + 0.66) % 1.0,
                  color: FlutterFlowTheme.of(context).tertiary,
                ),
              ],
              Transform.scale(
                scale: iconScale,
                child: child,
              ),
            ],
          );
        },
        child: InkWell(
          splashColor: Colors.transparent,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: _toggleRecording,
          child: Material(
            color: Colors.transparent,
            elevation: _isRecording ? 12.0 : 8.0,
            shape: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              width: 120.0,
              height: 120.0,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    blurRadius: _isRecording ? 28.0 : 20.0,
                    color: _isRecording
                        ? FlutterFlowTheme.of(context)
                            .primary
                            .withValues(alpha: 0.35)
                        : Colors.white,
                    offset: const Offset(0, 8),
                  ),
                ],
                gradient: LinearGradient(
                  colors: _isRecording
                      ? [
                          FlutterFlowTheme.of(context).tertiary,
                          FlutterFlowTheme.of(context).primary,
                        ]
                      : [
                          const Color(0xFF6366F1),
                          FlutterFlowTheme.of(context).primary,
                        ],
                  stops: const [0.2, 1.0],
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
    );
  }

  Widget _buildWaveRing({
    required double progress,
    required Color color,
  }) {
    final ringSize = 120.0 + (progress * 42.0);
    final opacity = ((1.0 - progress) * 0.45).clamp(0.0, 0.45).toDouble();
    return IgnorePointer(
      child: Container(
        width: ringSize,
        height: ringSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: opacity),
            width: 2.0,
          ),
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity * 0.18),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleRecording() async {
    if (_isProcessing) {
      return;
    }
    await hapticLight();
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
                    unawaited(hapticSelection());
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
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Align(
                      alignment: const AlignmentDirectional(-1.0, 0),
                      child: Text(
                        'Recent Lectures',
                        style: FlutterFlowTheme.of(context)
                            .headlineMedium
                            .override(
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
                    ),
                    const SizedBox(height: 16.0),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadRecordings,
                        child: _buildRecentLecturesList(bottomPadding: 360.0),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.only(top: 24.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          FlutterFlowTheme.of(context)
                              .primaryBackground
                              .withValues(alpha: 0.0),
                          FlutterFlowTheme.of(context)
                              .primaryBackground
                              .withValues(alpha: 0.9),
                          FlutterFlowTheme.of(context).primaryBackground,
                        ],
                        stops: const [0.0, 0.25, 1.0],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildRecordingPanel(),
                        const SizedBox(height: 20.0),
                        _buildQuickActionsRow(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingNameDialog extends StatefulWidget {
  const _RecordingNameDialog({
    required this.defaultTitle,
  });

  final String defaultTitle;

  @override
  State<_RecordingNameDialog> createState() => _RecordingNameDialogState();
}

class _RecordingNameDialogState extends State<_RecordingNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this recording'),
      content: TextField(
        controller: _controller,
        maxLength: 80,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'e.g. Physics Lecture 4',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(''),
          child: const Text('Use default'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true)
              .pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
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
