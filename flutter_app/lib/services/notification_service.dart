import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  Timer? _pollTimer;
  ApiService? _api;
  int _lastNotifCount = 0;
  int _notifId = 0;

  Future<void> init(ApiService api) async {
    _api = api;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    // 30초마다 새 알림 체크
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkNew());
  }

  Future<void> _checkNew() async {
    if (_api == null) return;
    try {
      final res = await _api!.get('/api/notifications?unread_only=true');
      if (res['ok'] != true) return;
      final unread = (res['unread_count'] ?? 0) as int;
      final notifs = (res['notifications'] as List?) ?? [];

      if (unread > _lastNotifCount && notifs.isNotEmpty) {
        // 새 알림 표시
        for (final n in notifs.take(unread - _lastNotifCount)) {
          await _show(
            n['title']?.toString() ?? '알림',
            n['body']?.toString() ?? '',
            n['type']?.toString() ?? 'info',
          );
        }
      }
      _lastNotifCount = unread;
    } catch (_) {}
  }

  Future<void> _show(String title, String body, String type) async {
    final color = type == 'error' ? const Color(0xFFf85149) : const Color(0xFF3fb950);
    final details = AndroidNotificationDetails(
      'u2dia_agent', 'U2DIA Agent',
      channelDescription: '상주 에이전트 알림',
      importance: Importance.high,
      priority: Priority.high,
      color: color,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(_notifId++, title, body, NotificationDetails(android: details));
  }

  void dispose() {
    _pollTimer?.cancel();
  }
}
