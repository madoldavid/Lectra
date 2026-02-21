import 'dart:async';
import 'dart:convert';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
    required this.raw,
    required this.readField,
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic> raw;
  final String? readField;

  AppNotification copyWith({
    bool? isRead,
  }) {
    return AppNotification(
      id: id,
      title: title,
      message: message,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      raw: raw,
      readField: readField,
    );
  }
}

class NotificationSyncService {
  NotificationSyncService._();
  static final NotificationSyncService instance = NotificationSyncService._();

  static const _cacheKey = 'lectra_notifications_cache_v1';

  final ValueNotifier<List<AppNotification>> notifications =
      ValueNotifier<List<AppNotification>>(<AppNotification>[]);
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);
  final ValueNotifier<DateTime?> lastUpdated = ValueNotifier<DateTime?>(null);

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  bool _started = false;
  String _activeUid = '';

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _activeUid = currentUserUid;
    await _loadFromCache();
    await refreshFromServer();
    _startRealtime();
    _startPolling();
  }

  Future<void> handleAuthChanged() async {
    final uid = currentUserUid;
    if (_activeUid == uid && _started) {
      return;
    }
    await stop();
    if (uid.isEmpty) {
      notifications.value = <AppNotification>[];
      return;
    }
    await start();
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    connected.value = false;
    _started = false;
    _activeUid = '';
    if (_channel != null) {
      await SupaFlow.client.removeChannel(_channel!);
      _channel = null;
    }
  }

  Future<void> refreshFromServer() async {
    if (currentUserUid.isEmpty) {
      return;
    }

    try {
      List<dynamic> rows;
      try {
        rows = await SupaFlow.client
            .from('notifications')
            .select()
            .order('created_at', ascending: false)
            .limit(200);
      } catch (_) {
        rows = await SupaFlow.client
            .from('notifications')
            .select()
            .order('createdAt', ascending: false)
            .limit(200);
      }

      final parsed = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where(_isForCurrentUser)
          .map(_parseRow)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      notifications.value = parsed;
      lastUpdated.value = DateTime.now();
      await _saveToCache(parsed);
      connected.value = true;
    } catch (_) {
      connected.value = false;
    }
  }

  Future<void> markAsRead(AppNotification item) async {
    if (item.isRead) {
      return;
    }
    notifications.value = notifications.value
        .map((n) => n.id == item.id ? n.copyWith(isRead: true) : n)
        .toList();
    await _saveToCache(notifications.value);

    if (item.id.isEmpty) {
      return;
    }
    final readField = item.readField ?? 'is_read';
    try {
      await SupaFlow.client
          .from('notifications')
          .update({readField: true}).eq('id', item.id);
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    final pending = notifications.value.where((n) => !n.isRead).toList();
    if (pending.isEmpty) {
      return;
    }
    notifications.value =
        notifications.value.map((n) => n.copyWith(isRead: true)).toList();
    await _saveToCache(notifications.value);

    for (final item in pending) {
      await markAsRead(item);
    }
  }

  int get unreadCount => notifications.value.where((n) => !n.isRead).length;

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await refreshFromServer();
    });
  }

  void _startRealtime() {
    if (_channel != null) {
      return;
    }
    _channel = SupaFlow.client.channel(
      'public:notifications:${currentUserUid.isEmpty ? 'anon' : currentUserUid}',
    );

    _channel!
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notifications',
      callback: (_) async {
        await refreshFromServer();
      },
    )
        .subscribe((status, [error]) {
      connected.value = status == RealtimeSubscribeStatus.subscribed;
      if (error != null) {
        connected.value = false;
      }
    });
  }

  bool _isForCurrentUser(Map<String, dynamic> row) {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) {
      return true;
    }
    const userKeys = ['user_id', 'recipient_id', 'target_user_id', 'uid'];

    bool foundUserField = false;
    for (final key in userKeys) {
      final value = row[key];
      if (value == null) {
        continue;
      }
      final normalized = value.toString().trim();
      if (normalized.isEmpty) {
        continue;
      }
      foundUserField = true;
      if (normalized == uid) {
        return true;
      }
    }

    // If a user field exists but doesn't match, skip.
    if (foundUserField) {
      return false;
    }
    // If row has no user scoping field, treat it as global notification.
    return true;
  }

  AppNotification _parseRow(Map<String, dynamic> row) {
    String readString(List<String> keys) {
      for (final key in keys) {
        final value = row[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
      return '';
    }

    DateTime readDate(List<String> keys) {
      for (final key in keys) {
        final value = row[key];
        if (value is String) {
          final parsed = DateTime.tryParse(value);
          if (parsed != null) {
            return parsed.toLocal();
          }
        }
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    String? readField;
    bool isRead = false;
    for (final key in const ['is_read', 'read', 'seen']) {
      final value = row[key];
      if (value is bool) {
        readField = key;
        isRead = value;
        break;
      }
    }

    final title = readString(const ['title', 'subject', 'event', 'name']);
    final message = readString(
      const ['message', 'body', 'content', 'description', 'text'],
    );

    return AppNotification(
      id: (row['id'] ?? '').toString(),
      title: title.isNotEmpty ? title : 'Notification',
      message: message,
      createdAt: readDate(
        const ['created_at', 'createdAt', 'timestamp', 'inserted_at'],
      ),
      isRead: isRead,
      raw: row,
      readField: readField,
    );
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      final parsed = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map((row) => AppNotification(
                id: (row['id'] ?? '').toString(),
                title: (row['title'] ?? 'Notification').toString(),
                message: (row['message'] ?? '').toString(),
                createdAt:
                    DateTime.tryParse((row['createdAt'] ?? '').toString())
                            ?.toLocal() ??
                        DateTime.fromMillisecondsSinceEpoch(0),
                isRead: row['isRead'] == true,
                raw: const {},
                readField: (row['readField'] ?? '').toString().isEmpty
                    ? null
                    : row['readField'].toString(),
              ))
          .toList();
      notifications.value = parsed;
    } catch (_) {}
  }

  Future<void> _saveToCache(List<AppNotification> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializable = value
          .map((n) => {
                'id': n.id,
                'title': n.title,
                'message': n.message,
                'createdAt': n.createdAt.toIso8601String(),
                'isRead': n.isRead,
                'readField': n.readField,
              })
          .toList();
      await prefs.setString(_cacheKey, jsonEncode(serializable));
    } catch (_) {}
  }
}
