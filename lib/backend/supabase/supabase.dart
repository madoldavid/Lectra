import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'database/database.dart';

const _kSupabaseUrl = 'https://kjakcnlchljralfsqagx.supabase.co';
const _kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtqYWtjbmxjaGxqcmFsZnNxYWd4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0NjMwMzIsImV4cCI6MjA4NjAzOTAzMn0.NdBgwPoQcUiPYPJICoFsAXYfo7xWMDjXg0KtjaOosPY';

class SupaFlow {
  SupaFlow._();

  static SupaFlow? _instance;
  static SupaFlow get instance => _instance ??= SupaFlow._();

  final _supabase = Supabase.instance.client;
  static SupabaseClient get client => instance._supabase;
  static String get projectUrl => _kSupabaseUrl;
  static String get anonKey => _kSupabaseAnonKey;

  static Future initialize() => Supabase.initialize(
        url: _kSupabaseUrl,
        headers: {
          'X-Client-Info': 'flutterflow',
        },
        anonKey: _kSupabaseAnonKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          localStorage: _ResilientLocalStorage(
            persistSessionKey:
                'sb-${Uri.parse(_kSupabaseUrl).host.split('.').first}-auth-token',
          ),
          pkceAsyncStorage: _ResilientPkceStorage(),
        ),
      );
}

/// SharedPreferences can fail to bind its platform channel during app cold
/// start on some release installs. We fallback to in-memory storage so app
/// startup is not blocked.
class _ResilientLocalStorage extends LocalStorage {
  _ResilientLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;
  SharedPreferences? _prefs;
  Future<void>? _prefsInit;
  String? _memorySession;

  Future<void> _ensurePrefs() {
    _prefsInit ??= () async {
      try {
        _prefs = await SharedPreferences.getInstance();
      } catch (_) {
        _prefs = null;
      }
    }();
    return _prefsInit!;
  }

  @override
  Future<void> initialize() async {
    await _ensurePrefs();
  }

  @override
  Future<bool> hasAccessToken() async {
    await _ensurePrefs();
    return _prefs?.containsKey(persistSessionKey) == true ||
        (_memorySession?.isNotEmpty ?? false);
  }

  @override
  Future<String?> accessToken() async {
    await _ensurePrefs();
    return _prefs?.getString(persistSessionKey) ?? _memorySession;
  }

  @override
  Future<void> removePersistedSession() async {
    await _ensurePrefs();
    _memorySession = null;
    try {
      await _prefs?.remove(persistSessionKey);
    } catch (_) {}
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _ensurePrefs();
    _memorySession = persistSessionString;
    try {
      await _prefs?.setString(persistSessionKey, persistSessionString);
    } catch (_) {}
  }
}

class _ResilientPkceStorage extends GotrueAsyncStorage {
  final Map<String, String> _memory = <String, String>{};
  SharedPreferences? _prefs;
  Future<void>? _prefsInit;

  Future<void> _ensurePrefs() {
    _prefsInit ??= () async {
      try {
        _prefs = await SharedPreferences.getInstance();
      } catch (_) {
        _prefs = null;
      }
    }();
    return _prefsInit!;
  }

  @override
  Future<String?> getItem({required String key}) async {
    await _ensurePrefs();
    return _prefs?.getString(key) ?? _memory[key];
  }

  @override
  Future<void> removeItem({required String key}) async {
    await _ensurePrefs();
    _memory.remove(key);
    try {
      await _prefs?.remove(key);
    } catch (_) {}
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    await _ensurePrefs();
    _memory[key] = value;
    try {
      await _prefs?.setString(key, value);
    } catch (_) {}
  }
}
