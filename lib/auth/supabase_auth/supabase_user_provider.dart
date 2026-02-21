import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rxdart/rxdart.dart';

import '/backend/supabase/supabase.dart';
import '../base_auth_user_provider.dart';

export '../base_auth_user_provider.dart';

class LectraSupabaseUser extends BaseAuthUser {
  LectraSupabaseUser(this.user);
  User? user;
  @override
  bool get loggedIn => user != null;

  @override
  AuthUserInfo get authUserInfo => AuthUserInfo(
        uid: user?.id,
        email: user?.email,
        displayName: _metadataString(user, const [
          'display_name',
          'full_name',
          'name',
        ]),
        photoUrl: _metadataString(user, const [
          'avatar_url',
          'picture',
          'photo_url',
        ]),
        phoneNumber: user?.phone,
      );

  @override
  Future? delete() async {
    if (user == null) {
      return;
    }

    // Preferred: project-level edge function using service role on backend.
    try {
      await SupaFlow.client.functions.invoke(
        'delete-user',
        body: {'user_id': user!.id},
      );
      return;
    } catch (_) {
      // Continue with fallback strategies.
    }

    try {
      await _deleteSelfViaAuthApi();
      return;
    } catch (_) {
      // Fallback to admin API (will require elevated backend credentials).
    }

    await SupaFlow.client.auth.admin.deleteUser(user!.id);
  }

  Future<void> _deleteSelfViaAuthApi() async {
    final accessToken = SupaFlow.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const AuthException('No active session.');
    }

    final client = HttpClient();
    try {
      Future<void> sendDeleteRequest(Map<String, dynamic>? body) async {
        final request = await client
            .deleteUrl(Uri.parse('${SupaFlow.projectUrl}/auth/v1/user'));
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
        request.headers.set('apikey', SupaFlow.anonKey);
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        if (body != null) {
          request.add(utf8.encode(jsonEncode(body)));
        }
        final response = await request.close();
        final responseBody = await utf8.decoder.bind(response).join();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw AuthException(
            'Delete failed (${response.statusCode}): $responseBody',
          );
        }
      }

      // Try multiple compatible payload variants for different GoTrue versions.
      try {
        await sendDeleteRequest({'should_soft_delete': false});
        return;
      } catch (_) {}

      try {
        await sendDeleteRequest({'should_soft_delete': true});
        return;
      } catch (_) {}

      await sendDeleteRequest(null);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future? updateEmail(String email) async {
    final response =
        await SupaFlow.client.auth.updateUser(UserAttributes(email: email));
    if (response.user != null) {
      user = response.user;
    }
  }

  @override
  Future? updatePassword(String newPassword) async {
    final response = await SupaFlow.client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
    if (response.user != null) {
      user = response.user;
    }
  }

  @override
  Future? sendEmailVerification() =>
      SupaFlow.client.auth.resend(type: OtpType.signup, email: user!.email!);

  @override
  bool get emailVerified {
    // Reloads the user when checking in order to get the most up to date
    // email verified status.
    if (loggedIn && user!.emailConfirmedAt == null) {
      refreshUser();
    }
    return user?.emailConfirmedAt != null;
  }

  @override
  Future refreshUser() async {
    await SupaFlow.client.auth
        .refreshSession()
        .then((_) => user = SupaFlow.client.auth.currentUser);
  }

  static String? _metadataString(User? user, List<String> keys) {
    final metadata = user?.userMetadata;
    if (metadata == null) {
      return null;
    }
    for (final key in keys) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }
}

/// Generates a stream of the authenticated user.
Stream<BaseAuthUser> lectraSupabaseUserStream() {
  final supabaseAuthStream = SupaFlow.client.auth.onAuthStateChange.map(
    (authState) {
      currentUser = LectraSupabaseUser(authState.session?.user);
      return currentUser!;
    },
  );
  return MergeStream([
    Stream.value(LectraSupabaseUser(SupaFlow.client.auth.currentUser)),
    supabaseAuthStream,
  ]);
}
