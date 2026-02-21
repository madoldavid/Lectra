import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'account_settings_page_model.dart';
export 'account_settings_page_model.dart';
import '/pages/change_password_page/change_password_page_widget.dart';
import '/pages/update_email_page/update_email_page_widget.dart';
import '/pages/sign_up_page/sign_up_page_widget.dart';
import '/pages/edit_profile_page/edit_profile_page_widget.dart';

class AccountSettingsPageWidget extends StatefulWidget {
  const AccountSettingsPageWidget({super.key});

  static String routeName = 'AccountSettingsPage';
  static String routePath = '/accountSettingsPage';

  @override
  State<AccountSettingsPageWidget> createState() =>
      _AccountSettingsPageWidgetState();
}

class _AccountSettingsPageWidgetState extends State<AccountSettingsPageWidget> {
  late AccountSettingsPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => AccountSettingsPageModel());
    _refreshUser();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _refreshUser() async {
    await authManager.refreshUser();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) {
      return;
    }
    final passwordController = TextEditingController();
    final currentPassword = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete Account'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This action cannot be undone. Enter your current password to confirm.',
                ),
                const SizedBox(height: 12.0),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                  ),
                  onSubmitted: (value) =>
                      Navigator.pop(dialogContext, value.trim()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, ''),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                    dialogContext, passwordController.text.trim()),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        '';
    passwordController.dispose();

    if (currentPassword.isEmpty) {
      return;
    }

    final isCurrentPasswordValid =
        await _verifyCurrentPassword(currentPassword);
    if (!mounted) {
      return;
    }
    if (!isCurrentPasswordValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current password is incorrect.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Final Confirmation'),
            content: const Text(
              'Are you absolutely sure you want to permanently delete this account?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  'Delete',
                  style: TextStyle(color: FlutterFlowTheme.of(context).error),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _deletingAccount = true;
    });

    final deleted = await authManager.deleteUser(context);
    if (!mounted) {
      return;
    }

    setState(() {
      _deletingAccount = false;
    });

    if (deleted || !loggedIn) {
      context.goNamed(SignUpPageWidget.routeName);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Unable to delete account right now. Please contact support.',
        ),
      ),
    );
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
    final firstLetter =
        currentUserEmail.isNotEmpty ? currentUserEmail[0].toUpperCase() : '';
    final displayName = currentUserDisplayName.isNotEmpty
        ? currentUserDisplayName
        : (currentUserEmail.isNotEmpty ? currentUserEmail : 'Lectra User');

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
              context.safePop();
            },
          ),
          title: Text(
            'Account Settings',
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
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    if (currentUserPhoto.isEmpty)
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: FlutterFlowTheme.of(context).primary,
                        child: Text(
                          firstLetter,
                          style: FlutterFlowTheme.of(context)
                              .headlineLarge
                              .override(
                                fontFamily: 'Outfit',
                                color: Colors.white,
                              ),
                        ),
                      )
                    else
                      Container(
                        width: 80,
                        height: 80,
                        clipBehavior: Clip.antiAlias,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                        ),
                        child: Image.network(
                          currentUserPhoto,
                          fit: BoxFit.cover,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: FlutterFlowTheme.of(context).headlineSmall,
                          ),
                          Text(
                            currentUserEmail,
                            style: FlutterFlowTheme.of(context).bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    InkWell(
                      splashColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () async {
                        context.pushNamed(EditProfilePageWidget.routeName);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            color: FlutterFlowTheme.of(context).secondaryText,
                            size: 24,
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                12, 0, 0, 0),
                            child: Text(
                              'Edit Profile',
                              style: FlutterFlowTheme.of(context)
                                  .bodyLarge
                                  .override(
                                    fontFamily: 'Readex Pro',
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                      thickness: 1,
                    ),
                    InkWell(
                      splashColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () async {
                        context.pushNamed(ChangePasswordPageWidget.routeName);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: FlutterFlowTheme.of(context).secondaryText,
                            size: 24,
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                12, 0, 0, 0),
                            child: Text(
                              'Change Password',
                              style: FlutterFlowTheme.of(context)
                                  .bodyLarge
                                  .override(
                                    fontFamily: 'Readex Pro',
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                      thickness: 1,
                    ),
                    InkWell(
                      splashColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () async {
                        context.pushNamed(UpdateEmailPageWidget.routeName);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Icon(
                            Icons.email_outlined,
                            color: FlutterFlowTheme.of(context).secondaryText,
                            size: 24,
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                12, 0, 0, 0),
                            child: Text(
                              'Update Email',
                              style: FlutterFlowTheme.of(context)
                                  .bodyLarge
                                  .override(
                                    fontFamily: 'Readex Pro',
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                      thickness: 1,
                    ),
                    InkWell(
                      splashColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: _deleteAccount,
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: FlutterFlowTheme.of(context).error,
                            size: 24,
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                12, 0, 0, 0),
                            child: Text(
                              'Delete Account',
                              style: FlutterFlowTheme.of(context)
                                  .bodyLarge
                                  .override(
                                    fontFamily: 'Readex Pro',
                                    color: FlutterFlowTheme.of(context).error,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                          if (_deletingAccount)
                            SizedBox(
                              width: 16.0,
                              height: 16.0,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                color: FlutterFlowTheme.of(context).error,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
