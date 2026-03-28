import '/backend/recordings/recording_store.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TrashPageWidget extends StatefulWidget {
  const TrashPageWidget({super.key});

  @override
  State<TrashPageWidget> createState() => _TrashPageWidgetState();
}

class _TrashPageWidgetState extends State<TrashPageWidget> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<RecordingEntry> _trashRecordings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTrashRecordings();
  }

  Future<void> _loadTrashRecordings() async {
    final entries = await RecordingStore.loadTrashRecordings();
    if (!mounted) {
      return;
    }
    setState(() {
      _trashRecordings = entries;
      _loading = false;
    });
  }

  Future<bool> _restoreRecording(RecordingEntry entry) async {
    await hapticLight();
    await RecordingStore.restoreFromTrash(entry);
    await _loadTrashRecordings();
    if (!mounted) {
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recording restored to Library.')),
    );
    return true;
  }

  Future<bool> _deletePermanently(RecordingEntry entry) async {
    await hapticSelection();
    if (!mounted) {
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Permanently'),
        content: const Text(
          'This will permanently delete the recording and notes from your device. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return false;
    }

    await RecordingStore.deleteRecordingPermanently(entry);
    await _loadTrashRecordings();
    return true;
  }

  Future<void> _showTrashActionsSheet(RecordingEntry entry) async {
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
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Restore'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _restoreRecording(entry);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever_rounded,
                color: FlutterFlowTheme.of(context).error,
              ),
              title: Text(
                'Delete permanently',
                style: TextStyle(color: FlutterFlowTheme.of(context).error),
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _deletePermanently(entry);
              },
            ),
            const SizedBox(height: 8.0),
          ],
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

  Widget _buildTrashCard(RecordingEntry entry) {
    final deletedDate = entry.deletedAt ?? entry.createdAt;
    return InkWell(
      onTap: () => _openRecording(entry),
      onLongPress: () => _showTrashActionsSheet(entry),
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(12.0),
        ),
        padding: const EdgeInsets.all(12.0),
        child: Row(
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
                  Icons.delete_outline_rounded,
                  color: FlutterFlowTheme.of(context).primary,
                  size: 24.0,
                ),
              ),
            ),
            Expanded(
              child: Column(
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
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.0,
                        ),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'Deleted ${dateTimeFormat('relative', deletedDate)} • ${_formatDuration(entry.duration)}',
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
                ],
              ),
            ),
            FlutterFlowIconButton(
              borderColor: Colors.transparent,
              borderRadius: 20.0,
              borderWidth: 1.0,
              buttonSize: 40.0,
              icon: Icon(
                Icons.restore_rounded,
                color: FlutterFlowTheme.of(context).primary,
                size: 22.0,
              ),
              onPressed: () => _restoreRecording(entry),
            ),
            FlutterFlowIconButton(
              borderColor: Colors.transparent,
              borderRadius: 20.0,
              borderWidth: 1.0,
              buttonSize: 40.0,
              icon: Icon(
                Icons.delete_forever_rounded,
                color: FlutterFlowTheme.of(context).error,
                size: 22.0,
              ),
              onPressed: () => _deletePermanently(entry),
            ),
          ].divide(const SizedBox(width: 8.0)),
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
          leading: FlutterFlowIconButton(
            borderRadius: 20.0,
            buttonSize: 40.0,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: FlutterFlowTheme.of(context).primaryText,
              size: 24.0,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trash',
                style: FlutterFlowTheme.of(context).headlineMedium.override(
                      font: GoogleFonts.interTight(
                        fontWeight: FontWeight.bold,
                        fontStyle: FlutterFlowTheme.of(context)
                            .headlineMedium
                            .fontStyle,
                      ),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.0,
                    ),
              ),
              Text(
                'Restore or delete permanently',
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
          elevation: 0.0,
          centerTitle: false,
        ),
        body: SafeArea(
          top: true,
          child: Padding(
            padding:
                const EdgeInsetsDirectional.fromSTEB(20.0, 12.0, 20.0, 20.0),
            child: _loading
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120.0),
                      Center(
                        child: Text(
                          'Loading trash...',
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
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                        ),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: _loadTrashRecordings,
                    child: (_trashRecordings.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 120.0),
                              Center(
                                child: Text(
                                  'Trash is empty.',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
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
                            itemCount: _trashRecordings.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12.0),
                            itemBuilder: (context, index) {
                              final entry = _trashRecordings[index];
                              return Dismissible(
                                key: ValueKey('trash_recording_${entry.id}'),
                                direction: DismissDirection.horizontal,
                                confirmDismiss: (direction) async {
                                  if (direction ==
                                      DismissDirection.startToEnd) {
                                    await _restoreRecording(entry);
                                    return false;
                                  }
                                  await _deletePermanently(entry);
                                  return false;
                                },
                                background: Container(
                                  alignment: AlignmentDirectional.centerStart,
                                  padding: const EdgeInsetsDirectional.only(
                                      start: 20.0),
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .success
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Icon(
                                    Icons.restore_rounded,
                                    color: FlutterFlowTheme.of(context).success,
                                  ),
                                ),
                                secondaryBackground: Container(
                                  alignment: AlignmentDirectional.centerEnd,
                                  padding: const EdgeInsetsDirectional.only(
                                      end: 20.0),
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .error
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Icon(
                                    Icons.delete_forever_rounded,
                                    color: FlutterFlowTheme.of(context).error,
                                  ),
                                ),
                                child: _buildTrashCard(entry),
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
