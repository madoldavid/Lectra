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
        authOptions:
            const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
      );
}
