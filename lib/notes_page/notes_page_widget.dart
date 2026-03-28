import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/backend/recordings/recording_store.dart';
import '/pages/trash_page/trash_page_widget.dart';
import '/index.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'notes_page_model.dart';
export 'notes_page_model.dart';

/// Library page for recorded lectures.
///
/// Shows locally saved recordings only.
/// Keeps the existing visual style and spacing.
class NotesPageWidget extends StatefulWidget {
  const NotesPageWidget({super.key});

  static String routeName = 'NotesPage';
  static String routePath = '/notesPage';

  @override
  State<NotesPageWidget> createState() => _NotesPageWidgetState();
}

class _NotesPageWidgetState extends State<NotesPageWidget> {
  late NotesPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<RecordingEntry> _recordings = [];
  bool _loadingRecordings = true;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => NotesPageModel());
    _loadRecordings();
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
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

  Future<void> _deleteRecording(RecordingEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move To Trash'),
        content: const Text(
          'This recording will be moved to Trash. You can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    await _moveToTrash(entry, allowUndo: false);
  }

  Future<void> _moveToTrash(
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
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
          decoration: const InputDecoration(hintText: 'Enter recording name'),
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
    await _loadRecordings();
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
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(entry.audioPath)],
        subject: entry.title,
        text: 'Lecture recording: ${entry.title}',
      ),
    );
  }

  Future<void> _onRecordingAction(RecordingEntry entry, String action) async {
    await hapticSelection();
    switch (action) {
      case 'open':
        _openRecording(entry);
        return;
      case 'rename':
        await _renameRecording(entry);
        return;
      case 'share':
        await _shareRecording(entry);
        return;
      case 'delete':
        await _deleteRecording(entry);
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
                  alignment: const AlignmentDirectional(0.0, 0.0),
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
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 4.0, 0.0, 0.0),
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
                onSelected: (value) => _onRecordingAction(entry, value),
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
                    value: 'share',
                    child: Text('Share'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Move to Trash'),
                  ),
                ],
              ),
            ].divide(const SizedBox(width: 12.0)),
          ),
        ),
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
                'Library',
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
                'Your recorded lectures',
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
          actions: [
            FlutterFlowIconButton(
              borderColor: Colors.transparent,
              borderRadius: 20.0,
              borderWidth: 1.0,
              buttonSize: 40.0,
              icon: Icon(
                Icons.delete_sweep_rounded,
                color: FlutterFlowTheme.of(context).primaryText,
                size: 22.0,
              ),
              onPressed: () async {
                unawaited(hapticSelection());
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TrashPageWidget(),
                  ),
                );
                await _loadRecordings();
              },
            ),
          ],
          centerTitle: false,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20.0, 0.0, 20.0, 0.0),
            child: RefreshIndicator(
              onRefresh: _loadRecordings,
              child: _loadingRecordings
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120.0),
                        Center(
                          child: Text(
                            'Loading recordings...',
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
                                ),
                          ),
                        ),
                      ],
                    )
                  : (_recordings.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 120.0),
                            Center(
                              child: Text(
                                'No recordings yet.',
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
                                    ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding:
                              const EdgeInsets.only(top: 12.0, bottom: 24.0),
                          itemCount: _recordings.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12.0),
                          itemBuilder: (context, index) {
                            final entry = _recordings[index];
                            return Dismissible(
                              key: ValueKey('library_recording_${entry.id}'),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                await hapticLight();
                                await _moveToTrash(entry);
                                return false;
                              },
                              background: Container(
                                alignment: AlignmentDirectional.centerEnd,
                                padding:
                                    const EdgeInsetsDirectional.only(end: 20.0),
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context)
                                      .error
                                      .withValues(alpha: 0.12),
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
                        )),
            ),
          ),
        ),
      ),
    );
  }
}
