import 'dart:async';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notes_detail_page_model.dart';
export 'notes_detail_page_model.dart';
import '../backend/recordings/recording_store.dart';
import '../services/export_service.dart';
import '../services/gemini_service.dart';

class NotesDetailPageWidget extends StatefulWidget {
  const NotesDetailPageWidget(
      {super.key,
      this.audioPath,
      this.notesPath,
      this.title,
      this.createdAt,
      this.durationSeconds});

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

class _NoteSection {
  const _NoteSection({
    required this.title,
    required this.bodyLines,
  });

  final String title;
  final List<String> bodyLines;
}

class _SectionVisualTheme {
  const _SectionVisualTheme({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;
}

class _NotesDetailPageWidgetState extends State<NotesDetailPageWidget> {
  late NotesDetailPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSubscription;
  String _notesText = '';
  bool _loadingNotes = true;
  bool _loadingAudio = true;
  bool _isPlaying = false;
  bool _isPlayPauseBusy = false;
  bool _isExporting = false;
  bool _isRetryingNotes = false;
  bool _autoRetriedOnce = false;
  bool _reviewPrompted = false;

  String _ensureMarkdownHeadings(String text) {
    // If already has markdown headings, return as-is.
    if (RegExp(r'^#', multiLine: true).hasMatch(text)) return text;

    final known = <String>[
      'lecture summary',
      'main topics',
      'key definitions',
      'action items',
      'additional context',
      'sample questions',
      'algorithms',
      'steps',
      'pitfalls',
      'frameworks',
      'models',
      'risks',
      'constraints',
      'key findings',
      'differential',
      'diagnostics',
      'treatment',
      'protocols',
      'risks/warnings',
    ];

    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].trimLeft().toLowerCase();
      for (final h in known) {
        if (lower.startsWith(h)) {
          final canonical = h
              .split(RegExp(r'[/ ]'))
              .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
              .join(' ')
              .replaceAll('Risks Warnings', 'Risks/Warnings');
          lines[i] = '# $canonical';
          break;
        }
      }
    }
    return lines.join('\n');
  }

  Future<void> _maybePromptReview() async {
    if (_reviewPrompted) return;
    _reviewPrompted = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('review_prompt_shown') == true) return;
      final review = InAppReview.instance;
      final available = await review.isAvailable();
      if (available) {
        await review.requestReview();
      } else {
        await review.openStoreListing(appStoreId: null, microsoftStoreId: null);
      }
      await prefs.setBool('review_prompt_shown', true);
    } catch (_) {
      // Ignore failures; don't block UX.
    }
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => NotesDetailPageModel());
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = state.playing;
      });
    });
    _loadNotes();
    _prepareAudio();
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
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
      // Auto retry AI structuring if we only have raw transcript.
      final trimmed = text.trimLeft().toLowerCase();
      if (!_autoRetriedOnce && trimmed.startsWith('# raw transcript')) {
        _autoRetriedOnce = true;
        // Fire and forget; user sees the same screen while we try.
        unawaited(_retryStructuring());
      }
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
      _isPlaying = _player.playing;
    });
  }

  Future<void> _exportNotes(String format) async {
    if (_isExporting || _loadingNotes || _notesText.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final entry = RecordingEntry(
        id: widget.title?.isNotEmpty == true
            ? widget.title!
            : 'export-${DateTime.now().millisecondsSinceEpoch}',
        title: widget.title ?? 'Lecture',
        createdAt: widget.createdAt ?? DateTime.now(),
        duration: Duration(seconds: widget.durationSeconds ?? 0),
        audioPath: widget.audioPath ?? '',
        notesPath: widget.notesPath ?? '',
        transcriptPreview:
            _notesText.isNotEmpty ? _notesText.substring(0, _notesText.length.clamp(0, 120)) : '',
        deletedAt: null,
      );

      switch (format) {
        case 'pdf':
          final file =
              await ExportService.exportNotesToPdf(entry: entry, notesText: _notesText);
          await Share.shareXFiles([XFile(file.path)],
              subject: '${entry.title} — Notes');
          break;
        case 'docx':
          final file = await ExportService.exportNotesToDocx(
              entry: entry, notesText: _notesText);
          await Share.shareXFiles([XFile(file.path)],
              subject: '${entry.title} — Notes');
          break;
        default:
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Format not supported yet.')),
          );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      } else {
        _isExporting = false;
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (_loadingAudio || _isPlayPauseBusy) {
      return;
    }
    setState(() {
      _isPlayPauseBusy = true;
    });
    try {
      final state = _player.playerState;
      final isPlayingNow = state.playing;

      if (isPlayingNow) {
        // Pause without rewinding so the user can resume from the same spot.
        await _player.pause();
      } else {
        // If ended, rewind before replaying.
        final duration = _player.duration;
        if (state.processingState == ProcessingState.completed ||
            (duration != null && _player.position >= duration)) {
          await _player.seek(Duration.zero);
        }
        // Do NOT await play(); it completes when playback ends, which would block toggling.
        _player.play();
      }
    } catch (e) {
      debugPrint('Playback toggle failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isPlayPauseBusy = false;
          _isPlaying = _player.playing;
        });
      } else {
        _isPlayPauseBusy = false;
        _isPlaying = _player.playing;
      }
    }
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

  List<_NoteSection> _parseSections(String notes) {
    final lines = notes.split('\n');
    final sections = <_NoteSection>[];

    String currentTitle = 'Lecture Summary';
    final currentBody = <String>[];

    void flushSection() {
      if (currentBody.isEmpty && sections.isNotEmpty) {
        return;
      }
      sections.add(
        _NoteSection(
          title: currentTitle,
          bodyLines: List<String>.from(currentBody),
        ),
      );
      currentBody.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final headingMatch = RegExp(r'^\s*#{1,6}\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        flushSection();
        currentTitle = headingMatch.group(1)?.trim() ?? 'Section';
        continue;
      }
      currentBody.add(line);
    }
    flushSection();

    final filtered = sections.where((section) {
      return section.title.trim().isNotEmpty ||
          section.bodyLines.any((line) => line.trim().isNotEmpty);
    }).toList();

    // Merge duplicate titles (e.g., double "Lecture Summary") into a single
    // section to avoid repeated headings.
    final merged = <String, _NoteSection>{};
    for (final section in filtered) {
      final key = section.title.trim().toLowerCase();
      if (merged.containsKey(key)) {
        final existing = merged[key]!;
        merged[key] = _NoteSection(
          title: existing.title,
          bodyLines: [
            ...existing.bodyLines,
            if (existing.bodyLines.isNotEmpty) '',
            ...section.bodyLines
          ],
        );
      } else {
        merged[key] = section;
      }
    }
    return merged.values.toList();
  }

  _SectionVisualTheme _sectionTheme(String title, int index) {
    // Premium, restrained palette: single accent derived from primary.
    final accent =
        FlutterFlowTheme.of(context).primary.withValues(alpha: 0.85);
    final normalized = title.toLowerCase();
    if (normalized.contains('topic')) {
      return _SectionVisualTheme(
        icon: Icons.account_tree_outlined,
        color: accent,
        label: 'Main Topics',
      );
    }
    if (normalized.contains('definition')) {
      return _SectionVisualTheme(
        icon: Icons.menu_book_outlined,
        color: accent,
        label: 'Definitions',
      );
    }
    if (normalized.contains('action')) {
      return _SectionVisualTheme(
        icon: Icons.task_alt_outlined,
        color: accent,
        label: 'Action Items',
      );
    }
    if (normalized.contains('additional context') ||
        normalized.contains('beyond recording') ||
        normalized.contains('supplemental') ||
        normalized.contains('deep dive')) {
      return _SectionVisualTheme(
        icon: Icons.explore_outlined,
        color: accent,
        label: 'Deep Dive',
      );
    }
    if (normalized.contains('summary')) {
      return _SectionVisualTheme(
        icon: Icons.lightbulb_outline_rounded,
        color: accent,
        label: 'Summary',
      );
    }
    if (normalized.contains('transcript')) {
      return _SectionVisualTheme(
        icon: Icons.subtitles_outlined,
        color: accent,
        label: 'Transcript',
      );
    }
    return _SectionVisualTheme(
      icon: Icons.notes_rounded,
      color: accent,
      label: 'Section',
    );
  }

  String _cleanInlineMarkdown(String value) {
    return value
        .replaceAll(RegExp(r'[*_`~]'), '')
        .replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _looksLikeDefinition(String line) {
    final match = RegExp(r'^([A-Za-z0-9][A-Za-z0-9\s\-/]{1,40}):\s+(.+)$')
        .firstMatch(line);
    return match != null;
  }

  Widget _buildEmptySectionBody() {
    return Text(
      'No details available.',
      style: FlutterFlowTheme.of(context).bodyMedium.override(
            font: GoogleFonts.inter(
              fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
            ),
            color: FlutterFlowTheme.of(context).secondaryText,
            letterSpacing: 0.0,
          ),
    );
  }

  Widget _buildDefinitionTile({
    required String term,
    required String definition,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: accent.withValues(alpha: 0.22),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999.0),
            ),
            child: Text(
              term,
              style: FlutterFlowTheme.of(context).labelSmall.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontStyle:
                          FlutterFlowTheme.of(context).labelSmall.fontStyle,
                    ),
                    letterSpacing: 0.0,
                    color: accent,
                  ),
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            definition,
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  font: GoogleFonts.inter(
                    fontWeight:
                        FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                  ),
                  letterSpacing: 0.0,
                  lineHeight: 1.45,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletRow({
    required IconData icon,
    required Color accent,
    required String text,
    String? leadingLabel,
  }) {
    final neutral =
        FlutterFlowTheme.of(context).primary.withValues(alpha: 0.85);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leadingLabel != null)
            Container(
              width: 22.0,
              height: 22.0,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: neutral.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999.0),
              ),
              child: Text(
                leadingLabel,
                style: FlutterFlowTheme.of(context).labelSmall.override(
                      font: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontStyle:
                            FlutterFlowTheme.of(context).labelSmall.fontStyle,
                      ),
                      color: neutral,
                      letterSpacing: 0.0,
                    ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Icon(
                icon,
                size: 14.0,
                color: neutral,
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10.0),
              child: Text(
                text,
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      font: GoogleFonts.inter(
                        fontWeight:
                            FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                      letterSpacing: 0.0,
                      lineHeight: 1.5,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBody(_NoteSection section, _SectionVisualTheme theme) {
    final nonEmpty = section.bodyLines.where((line) => line.trim().isNotEmpty);
    if (nonEmpty.isEmpty) {
      return _buildEmptySectionBody();
    }

    final widgets = <Widget>[];
    for (final rawLine in section.bodyLines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6.0));
        continue;
      }

      final cleaned = _cleanInlineMarkdown(trimmed);
      if (cleaned.isEmpty) {
        continue;
      }

      final checklistMatch =
          RegExp(r'^[-*]\s+\[( |x|X)\]\s+(.+)$').firstMatch(trimmed);
      if (checklistMatch != null) {
        final isDone = checklistMatch.group(1)?.toLowerCase() == 'x';
        final taskText = _cleanInlineMarkdown(checklistMatch.group(2) ?? '');
        widgets.add(
          _buildBulletRow(
            icon: isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            accent: theme.color,
            text: taskText,
          ),
        );
        continue;
      }

      final numberedMatch = RegExp(r'^(\d+)[\.\)]\s+(.+)$').firstMatch(trimmed);
      if (numberedMatch != null) {
        widgets.add(
          _buildBulletRow(
            icon: Icons.adjust,
            accent: theme.color,
            text: _cleanInlineMarkdown(numberedMatch.group(2) ?? ''),
            leadingLabel: numberedMatch.group(1),
          ),
        );
        continue;
      }

      final isBullet = trimmed.startsWith('- ') || trimmed.startsWith('* ');
      if (isBullet) {
        widgets.add(
          _buildBulletRow(
            icon: Icons.circle,
            accent: theme.color,
            text: _cleanInlineMarkdown(trimmed.substring(2).trim()),
          ),
        );
        continue;
      }

      if (_looksLikeDefinition(cleaned) ||
          section.title.toLowerCase().contains('definition')) {
        final definitionMatch =
            RegExp(r'^([^:]{2,40}):\s+(.+)$').firstMatch(cleaned);
        if (definitionMatch != null) {
          widgets.add(
            _buildDefinitionTile(
              term: definitionMatch.group(1)!.trim(),
              definition: definitionMatch.group(2)!.trim(),
              accent: theme.color,
            ),
          );
          continue;
        }
      }

      if (cleaned.startsWith('> ')) {
        widgets.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context)
                  .secondaryBackground
                  .withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12.0),
              border: Border(
                left: BorderSide(
                  color: theme.color,
                  width: 3.0,
                ),
              ),
            ),
            child: Text(
              cleaned.substring(2).trim(),
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.w500,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                    ),
                    letterSpacing: 0.0,
                    lineHeight: 1.45,
                  ),
            ),
          ),
        );
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            cleaned,
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  font: GoogleFonts.inter(
                    fontWeight:
                        FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                  ),
                  letterSpacing: 0.0,
                  lineHeight: 1.5,
                ),
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      return _buildEmptySectionBody();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildNotesSummary(List<_NoteSection> sections) {
    final words = _cleanInlineMarkdown(_notesText)
        .split(' ')
        .where((w) => w.trim().isNotEmpty)
        .length;
    final estimate = words == 0 ? 1 : ((words / 180).ceil().clamp(1, 99));
    final sectionLabels = sections.take(4).map((s) => s.title).toList();

    final subtleBorder =
        FlutterFlowTheme.of(context).secondaryText.withValues(alpha: 0.12);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.0),
        color: FlutterFlowTheme.of(context).secondaryBackground,
        border: Border.all(color: subtleBorder, width: 1.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34.0,
                  height: 34.0,
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context)
                        .secondaryBackground
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: subtleBorder, width: 1.0),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: FlutterFlowTheme.of(context).primary,
                    size: 18.0,
                  ),
                ),
                const SizedBox(width: 10.0),
                Text(
                  'AI Structured Notes',
                  style: FlutterFlowTheme.of(context).titleMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w700,
                          fontStyle: FlutterFlowTheme.of(context)
                              .titleMedium
                              .fontStyle,
                        ),
                        letterSpacing: 0.0,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                _buildInfoChip(
                    Icons.view_agenda_outlined, '${sections.length} sections'),
                _buildInfoChip(Icons.schedule_rounded, '$estimate min read'),
                _buildInfoChip(Icons.text_fields_rounded, '$words words'),
              ],
            ),
            if (sectionLabels.isNotEmpty) ...[
              const SizedBox(height: 12.0),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: sectionLabels
                    .map(
                      (label) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10.0, vertical: 6.0),
                        decoration: BoxDecoration(
                          color: FlutterFlowTheme.of(context)
                              .secondaryBackground
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999.0),
                          border: Border.all(color: subtleBorder, width: 1.0),
                        ),
                        child: Text(
                          label,
                          style:
                              FlutterFlowTheme.of(context).labelSmall.override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .labelSmall
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                  ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 7.0),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context)
            .secondaryBackground
            .withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(
          color:
              FlutterFlowTheme.of(context).secondaryText.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: FlutterFlowTheme.of(context).secondaryText,
            size: 14.0,
          ),
          const SizedBox(width: 6.0),
          Text(
            text,
            style: FlutterFlowTheme.of(context).labelSmall.override(
                  font: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontStyle:
                        FlutterFlowTheme.of(context).labelSmall.fontStyle,
                  ),
                  letterSpacing: 0.0,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection(_NoteSection section, int index) {
    final theme = _sectionTheme(section.title, index);
    final subtleBorder =
        FlutterFlowTheme.of(context).secondaryText.withValues(alpha: 0.12);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: subtleBorder,
          width: 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36.0,
                  height: 36.0,
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context)
                        .secondaryBackground
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: subtleBorder, width: 1.0),
                  ),
                  child: Icon(
                    theme.icon,
                    color: theme.color,
                    size: 18.0,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10.0),
                    child: Text(
                      section.title,
                      style: FlutterFlowTheme.of(context).titleMedium.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w700,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .titleMedium
                                  .fontStyle,
                            ),
                            letterSpacing: 0.0,
                          ),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context)
                        .secondaryBackground
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999.0),
                    border: Border.all(color: subtleBorder, width: 1.0),
                  ),
                  child: Text(
                    theme.label,
                    style: FlutterFlowTheme.of(context).labelSmall.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontStyle:
                                FlutterFlowTheme.of(context).labelSmall.fontStyle,
                          ),
                          letterSpacing: 0.0,
                          color: FlutterFlowTheme.of(context).primaryText,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            _buildSectionBody(section, theme),
          ],
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
          actions: [
            IconButton(
              tooltip: _isExporting ? 'Exporting…' : 'Export',
              onPressed: _isExporting
                  ? null
                  : () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (sheetCtx) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.picture_as_pdf_outlined),
                                title: const Text('Export as PDF'),
                                onTap: () async {
                                  Navigator.of(sheetCtx).pop();
                                  await _exportNotes('pdf');
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.insert_drive_file_outlined),
                                title: const Text('Export as DOCX'),
                                onTap: () async {
                                  Navigator.of(sheetCtx).pop();
                                  await _exportNotes('docx');
                                },
                              ),
                              const SizedBox(height: 8.0),
                            ],
                          ),
                        ),
                      );
                    },
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: true,
          child: SingleChildScrollView(
            child: Padding(
              padding:
                  const EdgeInsetsDirectional.fromSTEB(20.0, 16.0, 20.0, 24.0),
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FlutterFlowIconButton(
                                  borderRadius: 30.0,
                                  buttonSize: 52.0,
                                  fillColor:
                                      FlutterFlowTheme.of(context).primary,
                                  icon: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: FlutterFlowTheme.of(context).info,
                                    size: 28.0,
                                  ),
                                  onPressed: () async {
                                    await _togglePlayPause();
                                  },
                                ),
                              ],
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
                                            FlutterFlowTheme.of(context)
                                                .primary,
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
                                                  color: FlutterFlowTheme.of(
                                                          context)
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
                                                  color: FlutterFlowTheme.of(
                                                          context)
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
                          else ...[
                            Builder(
                              builder: (context) {
                                final trimmed = _notesText.trimLeft();
                                final isRawOnly =
                                    trimmed.toLowerCase().startsWith('# raw transcript') &&
                                    !_hasStructured(_notesText);

                                if (isRawOnly) {
                                  final body = (() {
                                    final idx = trimmed.indexOf('\n');
                                    if (idx == -1) return '';
                                    return trimmed.substring(idx + 1).trim();
                                  })();

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryBackground,
                                          borderRadius: BorderRadius.circular(16.0),
                                          border: Border.all(
                                            color: FlutterFlowTheme.of(context)
                                                .secondaryText
                                                .withValues(alpha: 0.12),
                                            width: 1.0,
                                          ),
                                        ),
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 36.0,
                                                  height: 36.0,
                                                  decoration: BoxDecoration(
                                                    color: FlutterFlowTheme.of(context)
                                                        .secondaryBackground
                                                        .withValues(alpha: 0.9),
                                                    borderRadius:
                                                        BorderRadius.circular(10.0),
                                                    border: Border.all(
                                                      color: FlutterFlowTheme.of(context)
                                                          .secondaryText
                                                          .withValues(alpha: 0.12),
                                                      width: 1.0,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    Icons.subtitles_outlined,
                                                    color: FlutterFlowTheme.of(context)
                                                        .primary,
                                                    size: 18.0,
                                                  ),
                                                ),
                                                const SizedBox(width: 10.0),
                                                Text(
                                                  'Raw Transcript',
                                                  style: FlutterFlowTheme.of(context)
                                                      .titleMedium
                                                      .override(
                                                        font: GoogleFonts.interTight(
                                                          fontWeight: FontWeight.w700,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(context)
                                                                  .titleMedium
                                                                  .fontStyle,
                                                        ),
                                                        letterSpacing: 0.0,
                                                      ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12.0),
                                            Text(
                                              body.isEmpty
                                                  ? 'No transcript captured.'
                                                  : body,
                                              style: FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .override(
                                                    font: GoogleFonts.inter(
                                                      fontWeight:
                                                          FlutterFlowTheme.of(context)
                                                              .bodyMedium
                                                              .fontWeight,
                                                      fontStyle:
                                                          FlutterFlowTheme.of(context)
                                                              .bodyMedium
                                                              .fontStyle,
                                                    ),
                                                    letterSpacing: 0.0,
                                                    lineHeight: 1.5,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12.0),
                                      SizedBox(
                                        width: double.infinity,
                                       child: ElevatedButton.icon(
                                          onPressed: _isRetryingNotes ? null : _retryStructuring,
                                          icon: _isRetryingNotes
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Icon(Icons.auto_fix_high_rounded, size: 18),
                                          label: Text(
                                            _isRetryingNotes
                                                ? 'Generating…'
                                                : 'Generate AI Notes',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                FlutterFlowTheme.of(context).primary,
                                            foregroundColor:
                                                FlutterFlowTheme.of(context).info,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12.0),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14.0,
                                              vertical: 12.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                final sections = _parseSections(_notesText);
                                if (sections.isEmpty) {
                                  return Text(
                                    'No notes were generated for this recording.',
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
                                  );
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildNotesSummary(sections),
                                    const SizedBox(height: 12.0),
                                    ...sections
                                        .asMap()
                                        .entries
                                        .map(
                                          (entry) => _buildNotesSection(
                                            entry.value,
                                            entry.key,
                                          ),
                                        )
                                        .toList()
                                        .divide(const SizedBox(height: 12.0)),
                                  ],
                                );
                              },
                            ),
                          ],
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
  String _extractRawTranscript(String notesText) {
    final trimmed = notesText.trimLeft();
    if (!trimmed.toLowerCase().startsWith('# raw transcript')) {
      return trimmed;
    }
    final idx = trimmed.indexOf('\n');
    if (idx == -1) return '';
    return trimmed.substring(idx + 1).trim();
  }

  bool _hasStructured(String notesText) {
    final t = notesText.toLowerCase();
    return t.contains('lecture summary') && t.contains('main topics');
  }

  Future<void> _retryStructuring() async {
    if (_isRetryingNotes || _loadingNotes) return;
    setState(() => _isRetryingNotes = true);
    try {
      final transcript = _extractRawTranscript(_notesText);
      if (transcript.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No transcript available to process.')),
          );
        }
        return;
      }
      final service = GeminiService();
      final notes = await service.generateNotes(transcript);
      final trimmed = notes.trim();
      final isRawFallback =
          trimmed.toLowerCase().startsWith('# raw transcript');
      final looksStructured = !isRawFallback && _hasStructured(trimmed);

      if (trimmed.isEmpty || !looksStructured) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Could not generate structured notes yet. Try again with better connection.'),
            ),
          );
        }
        return;
      }
      final normalized = _ensureMarkdownHeadings(trimmed);
      if (widget.notesPath != null && widget.notesPath!.isNotEmpty) {
        await File(widget.notesPath!).writeAsString(normalized, flush: true);
      }
      if (mounted) {
        setState(() {
          _notesText = normalized;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI notes generated.')),
        );
        unawaited(_maybePromptReview());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Retry failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRetryingNotes = false);
      } else {
        _isRetryingNotes = false;
      }
    }
  }
}
