import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

/// 알림 카테고리별 채널 정의
class _NotifChannel {
  final String id;
  final String name;
  final String description;
  final Importance importance;
  final Color color;

  const _NotifChannel(this.id, this.name, this.description, this.importance, this.color);
}

const _channels = [
  _NotifChannel('gpu_alert', 'GPU 비용 경보', 'Lambda GPU 비용 임계치 돌파', Importance.max, Color(0xFFf85149)),
  _NotifChannel('gpu_anomaly', 'GPU 이상 감지', 'GPU 프로세스 드롭 등 이상 상황', Importance.max, Color(0xFFd29922)),
  _NotifChannel('gpu_periodic', 'GPU 비용 주기보고', '1시간마다 비용 현황', Importance.defaultImportance, Color(0xFF1FC9E8)),
  _NotifChannel('supervisor', 'Supervisor', '승인 요청 및 검수 결과', Importance.high, Color(0xFF8B5CF6)),
  _NotifChannel('team_ticket', '팀/티켓', '팀 완료, 티켓 상태 변경', Importance.defaultImportance, Color(0xFF3fb950)),
  _NotifChannel('agent_msg', '에이전트 알림', '에이전트가 supervisor 경유로 보내는 알림', Importance.high, Color(0xFF58a6ff)),
  _NotifChannel('agent_critical', '에이전트 긴급', '에이전트 긴급 보고 (critical)', Importance.max, Color(0xFFf85149)),
  _NotifChannel('cli_approval', 'CLI 승인 대기', 'Claude Code가 분기점에서 승인 대기 중', Importance.max, Color(0xFFFFAB00)),
  _NotifChannel('cli_phase_done', 'CLI Phase 완료', 'Claude Code가 phase/세션을 완료함', Importance.high, Color(0xFF00C853)),
  _NotifChannel('system', '시스템', '에러, Fleet, CLI 알림', Importance.low, Color(0xFF8b949e)),
];

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  Timer? _pollTimer;
  ApiService? _api;
  int _lastNotifCount = 0;
  int _notifId = 0;
  bool _initialized = false;

  Future<void> init(ApiService api) async {
    _api = api;
    if (_initialized) return;
    _initialized = true;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    // Android 알림 채널 등록
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      for (final ch in _channels) {
        await androidPlugin.createNotificationChannel(AndroidNotificationChannel(
          ch.id, ch.name,
          description: ch.description,
          importance: ch.importance,
        ));
      }
      // Android 13+ 알림 권한 요청
      await androidPlugin.requestNotificationsPermission();
    }

    // 15초마다 새 알림 체크 (기존 30초 → 15초)
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkNew());
  }

  String _channelForType(String type) {
    switch (type) {
      case 'gpu_cost_alert':
        return 'gpu_alert';
      case 'gpu_anomaly':
        return 'gpu_anomaly';
      case 'gpu_cost_periodic':
        return 'gpu_periodic';
      case 'supervisor_approval':
      case 'supervisor_review':
        return 'supervisor';
      case 'team_created':
      case 'team_completed':
      case 'ticket_created':
      case 'ticket_done':
      case 'ticket_status':
      case 'artifact_created':
        return 'team_ticket';
      case 'agent_critical':
        return 'agent_critical';
      case 'agent_notification':
      case 'agent_warning':
        return 'agent_msg';
      case 'cli_approval':
      case 'cli_waiting':
        return 'cli_approval';
      case 'cli_phase_done':
      case 'cli_session_end':
        return 'cli_phase_done';
      default:
        return 'system';
    }
  }

  Importance _importanceForType(String type) {
    switch (type) {
      case 'gpu_cost_alert':
      case 'gpu_anomaly':
      case 'agent_critical':
      case 'cli_approval':
      case 'cli_waiting':
        return Importance.max;
      case 'supervisor_approval':
      case 'agent_notification':
      case 'agent_warning':
      case 'cli_phase_done':
      case 'cli_session_end':
        return Importance.high;
      default:
        return Importance.defaultImportance;
    }
  }

  Priority _priorityForType(String type) {
    switch (type) {
      case 'gpu_cost_alert':
      case 'gpu_anomaly':
      case 'agent_critical':
      case 'cli_approval':
      case 'cli_waiting':
        return Priority.max;
      case 'supervisor_approval':
      case 'team_completed':
      case 'agent_notification':
      case 'agent_warning':
      case 'cli_phase_done':
      case 'cli_session_end':
        return Priority.high;
      default:
        return Priority.defaultPriority;
    }
  }

  Color _colorForType(String type) {
    for (final ch in _channels) {
      if (ch.id == _channelForType(type)) return ch.color;
    }
    return const Color(0xFF3fb950);
  }

  Future<void> _checkNew() async {
    if (_api == null) return;
    try {
      final res = await _api!.get('/api/notifications?unread_only=true');
      if (res['ok'] != true) return;
      final unread = (res['unread_count'] ?? 0) as int;
      final notifs = (res['notifications'] as List?) ?? [];

      if (unread > _lastNotifCount && notifs.isNotEmpty) {
        final newCount = unread - _lastNotifCount;
        for (final n in notifs.take(newCount > 5 ? 5 : newCount)) {
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
    final channelId = _channelForType(type);
    final color = _colorForType(type);
    final details = AndroidNotificationDetails(
      channelId,
      _channels.firstWhere((c) => c.id == channelId, orElse: () => _channels.last).name,
      channelDescription: _channels.firstWhere((c) => c.id == channelId, orElse: () => _channels.last).description,
      importance: _importanceForType(type),
      priority: _priorityForType(type),
      color: color,
      icon: '@mipmap/ic_launcher',
      styleInformation: body.length > 60
          ? BigTextStyleInformation(body, contentTitle: title)
          : null,
    );
    await _plugin.show(_notifId++, title, body, NotificationDetails(android: details));
  }

  void dispose() {
    _pollTimer?.cancel();
  }
}
