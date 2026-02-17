import 'dart:async';

import 'package:flutter/material.dart';
import '/auth/auth_manager.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'email_auth.dart';
import 'supabase_user_provider.dart';

export '/auth/base_auth_user_provider.dart';

class SupabaseAuthManager extends AuthManager
    with EmailSignInManager, GoogleSignInManager, AppleSignInManager {
  static const Duration _oauthTimeout = Duration(minutes: 2);
  static const String _mobileRedirectUrl = 'lectra://lectra.com';

  @override
  Future signOut() {
    currentUser = null;
    return SupaFlow.client.auth.signOut();
  }

  @override
  Future deleteUser(BuildContext context) async {
    try {
      if (!loggedIn) {
        // Error: delete user attempted with no logged in user!
        return;
      }
      await currentUser?.delete();
    } on AuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
    }
  }

  @override
  Future<bool> updateEmail({
    required String email,
    required BuildContext context,
  }) async {
    try {
      if (!loggedIn) {
        // Error: update email attempted with no logged in user!
        return false;
      }
      await currentUser?.updateEmail(email);
    } on AuthException catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
      return false;
    }
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Email change confirmation email sent')),
    );
    return true;
  }

  @override
  Future<bool> updatePassword({
    required String newPassword,
    required BuildContext context,
  }) async {
    try {
      if (!loggedIn) {
        // Error: update password attempted with no logged in user!
        return false;
      }
      await currentUser?.updatePassword(newPassword);
    } on AuthException catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
      return false;
    }
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password updated successfully')),
    );
    return true;
  }

  Future<void> updateCurrentUser(Map<String, dynamic> data) async {
    try {
      final response =
          await SupaFlow.client.auth.updateUser(UserAttributes(data: data));
      final user = response.user;
      if (user != null) {
        final authUser = LectraSupabaseUser(user);
        currentUser = authUser;
        AppStateNotifier.instance.update(authUser);
      }
    } on AuthException {
      rethrow;
    }
  }

  @override
  Future resetPassword({
    required String email,
    required BuildContext context,
    String? redirectTo,
  }) async {
    try {
      await SupaFlow.client.auth
          .resetPasswordForEmail(email, redirectTo: redirectTo);
    } on AuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
      return null;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password reset email sent')),
    );
  }

  @override
  Future<BaseAuthUser?> signInWithEmail(
    BuildContext context,
    String email,
    String password,
  ) =>
      _signInOrCreateAccount(
        context,
        () => emailSignInFunc(email, password),
      );

  @override
  Future<BaseAuthUser?> createAccountWithEmail(
    BuildContext context,
    String email,
    String password,
  ) =>
      _createAccountWithEmail(
        context,
        email,
        password,
      );

  @override
  Future<BaseAuthUser?> signInWithGoogle(BuildContext context) =>
      _signInWithOAuth(context, OAuthProvider.google);

  @override
  Future<BaseAuthUser?> signInWithApple(BuildContext context) =>
      _signInWithOAuth(context, OAuthProvider.apple);

  /// Tries to sign in or create an account using Supabase Auth.
  /// Returns the User object if sign in was successful.
  Future<BaseAuthUser?> _signInOrCreateAccount(
    BuildContext context,
    Future<User?> Function() signInFunc,
  ) async {
    try {
      final user = await signInFunc();
      final authUser = user == null ? null : LectraSupabaseUser(user);
      if (authUser != null) {
        currentUser = authUser;
        AppStateNotifier.instance.update(authUser);
      }
      return authUser;
    } on AuthException catch (e) {
      final errorMsg = e.message.contains('User already registered')
          ? 'Error: The email is already in use by a different account'
          : 'Error: ${e.message}';
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
      return null;
    }
  }

  Future<BaseAuthUser?> _createAccountWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      final user = await emailCreateAccountFunc(email, password);
      if (user == null) {
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Check your email to confirm your account before signing in.',
            ),
          ),
        );
        return null;
      }
      final username = email.split('@')[0];
      final response = await SupaFlow.client.auth
          .updateUser(UserAttributes(data: {'full_name': username}));
      final updatedUser = response.user;
      final authUser = updatedUser != null
          ? LectraSupabaseUser(updatedUser)
          : LectraSupabaseUser(user);
      currentUser = authUser;
      AppStateNotifier.instance.update(authUser);
      return authUser;
    } on AuthException catch (e) {
      final errorMsg = e.message.contains('User already registered')
          ? 'Error: The email is already in use by a different account'
          : 'Error: ${e.message}';
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
      return null;
    }
  }

  Future<BaseAuthUser?> _signInWithOAuth(
    BuildContext context,
    OAuthProvider provider,
  ) async {
    try {
      await SupaFlow.client.auth.signInWithOAuth(
        provider,
        redirectTo: isWeb ? null : _mobileRedirectUrl,
      );

      if (isWeb) {
        return null;
      }

      final authState = await SupaFlow.client.auth.onAuthStateChange
          .firstWhere((state) => state.session?.user != null)
          .timeout(_oauthTimeout);
      final user = authState.session?.user;
      final authUser = user == null ? null : LectraSupabaseUser(user);
      if (authUser != null) {
        currentUser = authUser;
        AppStateNotifier.instance.update(authUser);
      }
      return authUser;
    } on TimeoutException {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign-in timed out. Please try again.')),
      );
      return null;
    } on AuthException catch (e) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
      return null;
    }
  }
}
