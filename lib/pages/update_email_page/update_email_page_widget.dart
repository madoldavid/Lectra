import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'update_email_page_model.dart';
export 'update_email_page_model.dart';

class UpdateEmailPageWidget extends StatefulWidget {
  const UpdateEmailPageWidget({super.key});

  static String routeName = 'UpdateEmailPage';
  static String routePath = '/updateEmailPage';

  @override
  State<UpdateEmailPageWidget> createState() => _UpdateEmailPageWidgetState();
}

class _UpdateEmailPageWidgetState extends State<UpdateEmailPageWidget> {
  late UpdateEmailPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  late TextEditingController _currentPasswordController;
  bool _currentPasswordVisibility = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => UpdateEmailPageModel());

    _model.newEmailController ??= TextEditingController();
    _currentPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _model.dispose();

    super.dispose();
  }

  Future<bool> _verifyCurrentPassword(String currentPassword) async {
    final email = currentUserEmail.trim();
    if (email.isEmpty) {
      return false;
    }
    final verifier = SupabaseClient(SupaFlow.projectUrl, SupaFlow.anonKey);
    try {
      final response = await verifier.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
      await verifier.auth.signOut();
      return response.user != null;
    } on AuthException {
      return false;
    } finally {
      try {
        await verifier.auth.signOut();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          'Update Email',
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
              TextFormField(
                controller: _currentPasswordController,
                obscureText: !_currentPasswordVisibility,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  hintText: 'Enter your current password',
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: FlutterFlowTheme.of(context).alternate,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: FlutterFlowTheme.of(context).primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: FlutterFlowTheme.of(context).error,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: FlutterFlowTheme.of(context).error,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: InkWell(
                    onTap: () => setState(
                      () => _currentPasswordVisibility =
                          !_currentPasswordVisibility,
                    ),
                    focusNode: FocusNode(skipTraversal: true),
                    child: Icon(
                      _currentPasswordVisibility
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: const Color(0xFF757575),
                      size: 22,
                    ),
                  ),
                ),
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      fontFamily: 'Readex Pro',
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _model.newEmailController,
                decoration: InputDecoration(
                  labelText: 'New Email',
                  hintText: 'Enter your new email',
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: FlutterFlowTheme.of(context).alternate,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: FlutterFlowTheme.of(context).primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: FlutterFlowTheme.of(context).error,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: FlutterFlowTheme.of(context).error,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      fontFamily: 'Readex Pro',
                      letterSpacing: 0,
                    ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(0, 24, 0, 0),
                child: FFButtonWidget(
                  onPressed: () async {
                    if (_isSubmitting) {
                      return;
                    }
                    final currentPassword =
                        _currentPasswordController.text.trim();
                    final newEmail = _model.newEmailController.text.trim();
                    if (currentPassword.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Current password is required.'),
                        ),
                      );
                      return;
                    }
                    if (newEmail.isEmpty ||
                        !RegExp(r'^[a-zA-Z0-9_\.-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$')
                            .hasMatch(newEmail)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please enter a valid email address',
                          ),
                        ),
                      );
                      return;
                    }
                    if (newEmail.toLowerCase() ==
                        currentUserEmail.trim().toLowerCase()) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'New email must be different from current email.',
                          ),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _isSubmitting = true;
                    });
                    final isCurrentPasswordValid =
                        await _verifyCurrentPassword(currentPassword);
                    if (!context.mounted) {
                      return;
                    }
                    if (!isCurrentPasswordValid) {
                      setState(() {
                        _isSubmitting = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Current password is incorrect.'),
                        ),
                      );
                      return;
                    }
                    final success = await authManager.updateEmail(
                      context: context,
                      email: newEmail,
                    );
                    if (!context.mounted) {
                      return;
                    }
                    setState(() {
                      _isSubmitting = false;
                    });
                    if (success) {
                      _currentPasswordController.clear();
                      _model.newEmailController?.clear();
                      context.pop();
                    }
                  },
                  text: _isSubmitting ? 'Updating...' : 'Update Email',
                  options: FFButtonOptions(
                    width: double.infinity,
                    height: 50,
                    color: FlutterFlowTheme.of(context).primary,
                    textStyle: FlutterFlowTheme.of(context).titleSmall.override(
                          fontFamily: 'Readex Pro',
                          color: Colors.white,
                          letterSpacing: 0,
                        ),
                    elevation: 3,
                    borderSide: const BorderSide(
                      color: Colors.transparent,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
