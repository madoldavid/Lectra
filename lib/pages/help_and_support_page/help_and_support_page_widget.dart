import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'help_and_support_page_model.dart';
export 'help_and_support_page_model.dart';

const String _supportEmail = 'goydave45@gmail.com';
const String _privacyPolicyUrl = 'https://madoldavid.github.io/Lectra/privacy';
const String _termsUrl = 'https://madoldavid.github.io/Lectra/terms';

class HelpAndSupportPageWidget extends StatefulWidget {
  const HelpAndSupportPageWidget({super.key});

  static String routeName = 'HelpAndSupportPage';
  static String routePath = '/helpAndSupportPage';

  @override
  State<HelpAndSupportPageWidget> createState() =>
      _HelpAndSupportPageWidgetState();
}

class _HelpAndSupportPageWidgetState extends State<HelpAndSupportPageWidget> {
  late HelpAndSupportPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HelpAndSupportPageModel());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _safeLaunch(String url) async {
    try {
      await launchURL(url);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open link: $e')),
      );
    }
  }

  Future<void> _showFaqs() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'FAQs',
                  style: FlutterFlowTheme.of(context).titleMedium,
                ),
                const SizedBox(height: 10.0),
                Text(
                  '1. Where are my recordings stored?\n'
                  'All recordings and notes are stored locally on your device.\n\n'
                  '2. Why is transcription empty?\n'
                  'This is usually caused by API quota, network issues, or low audio quality.\n\n'
                  '3. Can I rename recordings?\n'
                  'Yes. After recording/transcription, you can set a custom name.\n\n'
                  '4. Can I delete recordings?\n'
                  'Yes. Open Library and delete any recording.',
                  style: FlutterFlowTheme.of(context).bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTerms() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Terms of Service'),
        content: const Text(
          'By using Lectra, you agree to use the app responsibly, comply with local laws, and respect lecture recording permissions in your institution.\n\n'
          'You are responsible for the data you record and store on your device.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _safeLaunch(_termsUrl);
            },
            child: const Text('View Full Terms'),
          ),
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
      onTap: onTap,
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
            'Help and Support',
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
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                _buildRow(
                  icon: Icons.help_outline,
                  label: 'FAQs',
                  onTap: _showFaqs,
                ),
                const Divider(thickness: 1),
                _buildRow(
                  icon: Icons.contact_support_outlined,
                  label: 'Contact Support',
                  onTap: () => _safeLaunch(
                    'mailto:$_supportEmail?subject=${Uri.encodeComponent('Lectra Support Request')}',
                  ),
                ),
                const Divider(thickness: 1),
                _buildRow(
                  icon: Icons.article_outlined,
                  label: 'Terms of Service',
                  onTap: _showTerms,
                ),
                const Divider(thickness: 1),
                _buildRow(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  onTap: () => _safeLaunch(_privacyPolicyUrl),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
