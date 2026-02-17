import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'notes_detail_page_model.dart';
export 'notes_detail_page_model.dart';

class NotesDetailPageWidget extends StatefulWidget {
  const NotesDetailPageWidget({super.key, this.audioPath, this.notesPath, this.title, this.createdAt, this.durationSeconds});

  static String routeName = 'NotesDetailPage';
  static String routePath = '/notesDetailPage';

  final String? audioPath;
  final String? notesPath;
  final String? title;
  final DateTime? createdAt;
  final int? durationSeconds;

  @override
  State<NotesDetailPageWidget> createState() => _NotesDetailPageWidgetState();
}

class _NotesDetailPageWidgetState extends State<NotesDetailPageWidget> {
  late NotesDetailPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final AudioPlayer _player = AudioPlayer();
  String _notesText = '';
  bool _loadingNotes = true;
  bool _loadingAudio = true;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => NotesDetailPageModel());
    _loadNotes();
    _prepareAudio();
  }

  @override
  void dispose() {
    _player.dispose();
    _model.dispose();

    super.dispose();
  }

  Future<void> _loadNotes() async {
    final path = widget.notesPath;
    if (path == null || path.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notesText = 'Notes file not found.';
        _loadingNotes = false;
      });
      return;
    }

    try {
      final file = File(path);
      final text = await file.readAsString();
      if (!mounted) {
        return;
      }
      setState(() {
        _notesText = text;
        _loadingNotes = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notesText = 'Unable to load notes.';
        _loadingNotes = false;
      });
    }
  }

  Future<void> _prepareAudio() async {
    final path = widget.audioPath;
    if (path == null || path.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingAudio = false;
      });
      return;
    }
    try {
      await _player.setFilePath(path);
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingAudio = false;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }

  String _metaLine() {
    final created = widget.createdAt;
    final durationSeconds = widget.durationSeconds ?? 0;
    final duration = Duration(seconds: durationSeconds);
    if (created == null) {
      return _formatDuration(duration);
    }
    return '${dateTimeFormat('relative', created)} • ${_formatDuration(duration)}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: false,
          leading: FlutterFlowIconButton(
            borderRadius: 20.0,
            buttonSize: 40.0,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: FlutterFlowTheme.of(context).primaryText,
              size: 24.0,
            ),
            onPressed: () async {
              context.safePop();
            },
          ),
          title: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title ?? 'Lecture Notes',
                style: FlutterFlowTheme.of(context).headlineMedium.override(
                      font: GoogleFonts.interTight(
                        fontWeight: FontWeight.bold,
                        fontStyle: FlutterFlowTheme.of(context)
                            .headlineMedium
                            .fontStyle,
                      ),
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.bold,
                      fontStyle:
                          FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                    ),
              ),
              Text(
                _metaLine(),
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      font: GoogleFonts.inter(
                        fontWeight:
                            FlutterFlowTheme.of(context).bodySmall.fontWeight,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodySmall.fontStyle,
                      ),
                      color: FlutterFlowTheme.of(context).secondaryText,
                      letterSpacing: 0.0,
                    ),
              ),
            ],
          ),
          centerTitle: false,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20.0, 16.0, 20.0, 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: FlutterFlowTheme.of(context).secondaryBackground,
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Text(
                            'Playback',
                            style: FlutterFlowTheme.of(context)
                                .labelMedium
                                .override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                                  letterSpacing: 0.5,
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .fontStyle,
                                ),
                          ),
                          const SizedBox(height: 12.0),
                          if (_loadingAudio)
                            Text(
                              'Preparing audio...',
                              style: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryText,
                                  ),
                            )
                          else
                            StreamBuilder<PlayerState>(
                              stream: _player.playerStateStream,
                              builder: (context, snapshot) {
                                final isPlaying = snapshot.data?.playing ?? false;
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FlutterFlowIconButton(
                                      borderRadius: 30.0,
                                      buttonSize: 52.0,
                                      fillColor:
                                          FlutterFlowTheme.of(context).primary,
                                      icon: Icon(
                                        isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color:
                                            FlutterFlowTheme.of(context).info,
                                        size: 28.0,
                                      ),
                                      onPressed: () async {
                                        if (isPlaying) {
                                          await _player.pause();
                                        } else {
                                          await _player.play();
                                        }
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                          const SizedBox(height: 12.0),
                          StreamBuilder<Duration?>(
                            stream: _player.durationStream,
                            builder: (context, snapshot) {
                              final duration = snapshot.data ?? Duration.zero;
                              return StreamBuilder<Duration>(
                                stream: _player.positionStream,
                                builder: (context, positionSnapshot) {
                                  final position =
                                      positionSnapshot.data ?? Duration.zero;
                                  final maxSeconds = duration.inSeconds == 0
                                      ? 1
                                      : duration.inSeconds;
                                  final currentSeconds = position.inSeconds;
                                  return Column(
                                    children: [
                                      Slider(
                                        value: currentSeconds
                                            .clamp(0, maxSeconds)
                                            .toDouble(),
                                        min: 0,
                                        max: maxSeconds.toDouble(),
                                        activeColor:
                                            FlutterFlowTheme.of(context).primary,
                                        onChanged: (value) async {
                                          await _player.seek(
                                            Duration(seconds: value.toInt()),
                                          );
                                        },
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatDuration(position),
                                            style: FlutterFlowTheme.of(context)
                                                .bodySmall
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodySmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodySmall
                                                            .fontStyle,
                                                  ),
                                                  color:
                                                      FlutterFlowTheme.of(context)
                                                          .secondaryText,
                                                ),
                                          ),
                                          Text(
                                            _formatDuration(duration),
                                            style: FlutterFlowTheme.of(context)
                                                .bodySmall
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodySmall
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodySmall
                                                            .fontStyle,
                                                  ),
                                                  color:
                                                      FlutterFlowTheme.of(context)
                                                          .secondaryText,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20.0),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: FlutterFlowTheme.of(context).secondaryBackground,
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notes',
                            style: FlutterFlowTheme.of(context)
                                .labelMedium
                                .override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                                  letterSpacing: 0.5,
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .fontStyle,
                                ),
                          ),
                          const SizedBox(height: 12.0),
                          if (_loadingNotes)
                            Text(
                              'Loading notes...',
                              style: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryText,
                                  ),
                            )
                          else
                            Text(
                              _notesText,
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
                                    letterSpacing: 0.0,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ].divide(const SizedBox(height: 12.0)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
