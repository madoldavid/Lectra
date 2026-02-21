import 'dart:io';

import '/backend/recordings/recording_store.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'storage_and_data_page_model.dart';
export 'storage_and_data_page_model.dart';

class StorageAndDataPageWidget extends StatefulWidget {
  const StorageAndDataPageWidget({super.key});

  static String routeName = 'StorageAndDataPage';
  static String routePath = '/storageAndDataPage';

  @override
  State<StorageAndDataPageWidget> createState() =>
      _StorageAndDataPageWidgetState();
}

class _StorageMetrics {
  const _StorageMetrics({
    required this.totalBytes,
    required this.recordingsBytes,
    required this.audioBytes,
    required this.notesBytes,
    required this.metaBytes,
    required this.cacheBytes,
    required this.recordingsCount,
  });

  final int totalBytes;
  final int recordingsBytes;
  final int audioBytes;
  final int notesBytes;
  final int metaBytes;
  final int cacheBytes;
  final int recordingsCount;
}

class _StorageAndDataPageWidgetState extends State<StorageAndDataPageWidget> {
  late StorageAndDataPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _loading = true;
  bool _busy = false;
  _StorageMetrics _metrics = const _StorageMetrics(
    totalBytes: 0,
    recordingsBytes: 0,
    audioBytes: 0,
    notesBytes: 0,
    metaBytes: 0,
    cacheBytes: 0,
    recordingsCount: 0,
  );

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => StorageAndDataPageModel());
    _refreshMetrics();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _refreshMetrics() async {
    final metrics = await _collectMetrics();
    if (!mounted) {
      return;
    }
    setState(() {
      _metrics = metrics;
      _loading = false;
    });
  }

  Future<_StorageMetrics> _collectMetrics() async {
    final recordingsDir = await RecordingStore.ensureRecordingsDir();
    final cacheDir = await getTemporaryDirectory();

    int audioBytes = 0;
    int notesBytes = 0;
    int metaBytes = 0;
    int recordingsCount = 0;

    if (recordingsDir.existsSync()) {
      final files = recordingsDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>();
      for (final file in files) {
        int length = 0;
        try {
          length = file.lengthSync();
        } catch (_) {
          length = 0;
        }
        final path = file.path.toLowerCase();
        if (path.endsWith('.m4a') ||
            path.endsWith('.wav') ||
            path.endsWith('.mp4') ||
            path.endsWith('.aac')) {
          audioBytes += length;
          recordingsCount++;
        } else if (path.endsWith('.txt')) {
          notesBytes += length;
        } else if (path.endsWith('.json')) {
          metaBytes += length;
        }
      }
    }

    final recordingsBytes = audioBytes + notesBytes + metaBytes;
    final cacheBytes = await _directorySize(cacheDir);
    final totalBytes = recordingsBytes + cacheBytes;

    return _StorageMetrics(
      totalBytes: totalBytes,
      recordingsBytes: recordingsBytes,
      audioBytes: audioBytes,
      notesBytes: notesBytes,
      metaBytes: metaBytes,
      cacheBytes: cacheBytes,
      recordingsCount: recordingsCount,
    );
  }

  Future<int> _directorySize(Directory dir) async {
    if (!dir.existsSync()) {
      return 0;
    }
    int total = 0;
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  Future<void> _clearCache() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });

    final cacheDir = await getTemporaryDirectory();
    final before = await _directorySize(cacheDir);
    int clearedFiles = 0;

    try {
      if (cacheDir.existsSync()) {
        final entities = cacheDir.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          try {
            if (entity is File) {
              await entity.delete();
              clearedFiles++;
            }
          } catch (_) {}
        }
      }
      await DefaultCacheManager().emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await _refreshMetrics();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cache cleared (${_formatBytes(before)} removed, $clearedFiles files).',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear cache: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _repairOfflineData() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final repairedEntries = await RecordingStore.loadRecordings();
      await _refreshMetrics();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Offline data index repaired. ${repairedEntries.length} recordings verified.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Offline data repair failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openOfflineDataManager() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage Offline Data',
                  style: FlutterFlowTheme.of(context).titleMedium,
                ),
                const SizedBox(height: 8.0),
                Text(
                  'Recordings: ${_metrics.recordingsCount}\nStored data: ${_formatBytes(_metrics.recordingsBytes)}',
                  style: FlutterFlowTheme.of(context).bodyMedium,
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          context.pushNamed(NotesPageWidget.routeName);
                        },
                        child: const Text('Open Library'),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await _repairOfflineData();
                        },
                        child: const Text('Repair Data'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDataUsageStats() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Data Usage Statistics'),
        content: Text(
          [
            'Total app data: ${_formatBytes(_metrics.totalBytes)}',
            'Recordings total: ${_formatBytes(_metrics.recordingsBytes)}',
            'Audio files: ${_formatBytes(_metrics.audioBytes)}',
            'Notes files: ${_formatBytes(_metrics.notesBytes)}',
            'Metadata files: ${_formatBytes(_metrics.metaBytes)}',
            'Cache/temporary: ${_formatBytes(_metrics.cacheBytes)}',
            'Saved recordings: ${_metrics.recordingsCount}',
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: _busy ? null : onTap,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(
            icon,
            color: FlutterFlowTheme.of(context).secondaryText,
            size: 24,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 0, 0),
              child: Text(
                label,
                style: FlutterFlowTheme.of(context).bodyLarge.override(
                      fontFamily: 'Readex Pro',
                      letterSpacing: 0,
                    ),
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: FlutterFlowTheme.of(context).secondaryText,
            size: 20.0,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _model.unfocusNode.canRequestFocus
          ? FocusScope.of(context).requestFocus(_model.unfocusNode)
          : FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primary,
          automaticallyImplyLeading: false,
          leading: FlutterFlowIconButton(
            borderColor: Colors.transparent,
            borderRadius: 30,
            borderWidth: 1,
            buttonSize: 60,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 30,
            ),
            onPressed: () async {
              context.pop();
            },
          ),
          title: Text(
            'Storage and Data',
            style: FlutterFlowTheme.of(context).headlineMedium.override(
                  fontFamily: 'Outfit',
                  color: Colors.white,
                  fontSize: 22,
                  letterSpacing: 0,
                ),
          ),
          actions: const [],
          centerTitle: false,
          elevation: 2,
        ),
        body: SafeArea(
          top: true,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Storage Used',
                            style: FlutterFlowTheme.of(context).bodyLarge,
                          ),
                          Text(
                            _formatBytes(_metrics.totalBytes),
                            style: FlutterFlowTheme.of(context).bodyLarge,
                          ),
                        ],
                      ),
                      const Divider(thickness: 1),
                      _buildRow(
                        icon: Icons.delete_sweep_outlined,
                        label: 'Clear Cache',
                        onTap: _clearCache,
                      ),
                      const Divider(thickness: 1),
                      _buildRow(
                        icon: Icons.offline_pin_outlined,
                        label: 'Manage Offline Data',
                        onTap: _openOfflineDataManager,
                      ),
                      const Divider(thickness: 1),
                      _buildRow(
                        icon: Icons.data_usage_outlined,
                        label: 'Data Usage Statistics',
                        onTap: _showDataUsageStats,
                      ),
                      const SizedBox(height: 12.0),
                      if (_busy) const LinearProgressIndicator(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
