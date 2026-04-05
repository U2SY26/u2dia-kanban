import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import '../kanban/ticket_thread_sheet.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final List<Map<String, dynamic>> _events = [];
  StreamSubscription? _sseSub;
  http.Client? _sseClient;
  Timer? _pollTimer;
  String _filter = '전체';
  bool _connected = false;
  static const _maxItems = 200;

  static const _filters = ['전체', '티켓', '스폰', '산출물', '검수', '에러'];

  // action -> filter category mapping
  static const _actionCategory = {
    'ticket_created': '티켓',
    'ticket_status_changed': '티켓',
    'status_changed': '티켓',
    'ticket_claimed': '티켓',
    'member_spawned': '스폰',
    'artifact_created': '산출물',
    'error': '에러',
    'supervisor_review': '검수',
    'feedback_created': '검수',
  };

  // action -> icon + color
  static const _actionMeta = {
    'team_created': (Icons.group_add, Color(0xFF1B96FF)),
    'ticket_created': (Icons.add_task, Color(0xFF4AC99B)),
    'ticket_status_changed': (Icons.sync_alt, Color(0xFFFF9F43)),
    'status_changed': (Icons.sync_alt, Color(0xFFFF9F43)),
    'ticket_claimed': (Icons.flash_on, Color(0xFFFFD700)),
    'member_spawned': (Icons.smart_toy, Color(0xFF9B59B6)),
    'artifact_created': (Icons.inventory_2, Color(0xFF1ABC9C)),
    'message_sent': (Icons.chat_bubble_outline, Color(0xFF8b949e)),
    'feedback_created': (Icons.star_outline, Color(0xFFFF9F43)),
    'progress': (Icons.trending_up, Color(0xFF1B96FF)),
    'error': (Icons.error_outline, Color(0xFFf85149)),
  };

  @override
  void initState() {
    super.initState();
    _loadInitialActivity();
    _connectSSE();
    // SSE 끊김 대비 — 10초 폴링 폴백
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_connected) _loadInitialActivity();
    });
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _sseClient?.close();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialActivity() async {
    final api = context.read<ApiService>();
    final res = await api.globalActivity(limit: 50);
    final activities = (res['activities'] as List?) ?? (res['logs'] as List?) ?? [];
    if (!mounted) return;
    setState(() {
      for (final a in activities) {
        if (a is Map<String, dynamic>) {
          _events.add(a);
        }
      }
    });
  }

  void _connectSSE() {
    final api = context.read<ApiService>();
    final url = '${api.baseUrl}/api/supervisor/events';
    _sseClient = http.Client();

    final request = http.Request('GET', Uri.parse(url));
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';

    _sseClient!.send(request).then((response) {
      if (!mounted) return;
      setState(() => _connected = true);

      final stream = response.stream.transform(utf8.decoder);
      String buffer = '';

      _sseSub = stream.listen(
        (chunk) {
          buffer += chunk;
          final lines = buffer.split('\n');
          buffer = lines.last; // keep incomplete line

          for (int i = 0; i < lines.length - 1; i++) {
            final line = lines[i].trim();
            if (line.startsWith('data:')) {
              final jsonStr = line.substring(5).trim();
              if (jsonStr.isEmpty || jsonStr == 'ping' || jsonStr == '{}') continue;
              try {
                final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
                // SSE 형식 → API 형식으로 정규화
                final event = _normalizeSSE(raw);
                if (event == null || !mounted) return;
                setState(() {
                  _events.insert(0, event);
                  if (_events.length > _maxItems) {
                    _events.removeRange(_maxItems, _events.length);
                  }
                });
              } catch (_) {}
            }
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() => _connected = false);
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) _connectSSE();
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() => _connected = false);
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) _connectSSE();
            });
          }
        },
      );
    }).catchError((_) {
      if (mounted) {
        setState(() => _connected = false);
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) _connectSSE();
        });
      }
    });
  }

  /// SSE 이벤트를 API activity 형식으로 정규화
  Map<String, dynamic>? _normalizeSSE(Map<String, dynamic> raw) {
    final type = raw['type'] as String? ?? raw['event_type'] as String? ?? '';
    // heartbeat 무시
    if (type == 'ticket_heartbeat') return null;

    final data = raw['data'] as Map<String, dynamic>? ?? {};
    // 메시지 추출 우선순위
    String msg = '';
    if (data['message'] != null) {
      msg = data['message'].toString();
    } else if (data['title'] != null) {
      msg = data['title'].toString();
    } else if (data['ticket_title'] != null) {
      msg = data['ticket_title'].toString();
      if (data['status'] != null) msg += ' → ${data['status']}';
    } else if (data['content'] != null) {
      msg = data['content'].toString();
      if (msg.length > 120) msg = msg.substring(0, 120);
    } else if (data['name'] != null) {
      msg = data['name'].toString();
    } else if (data['status'] != null) {
      msg = '${data['ticket_id'] ?? ''} → ${data['status']}';
    } else if (data['role'] != null) {
      msg = '${data['member_id'] ?? ''} (${data['role']})';
    } else {
      msg = type;
    }

    return {
      'action': type,
      'message': msg,
      'team_id': raw['team_id'] ?? '',
      'team_name': raw['team_name'] ?? '',
      'ticket_id': data['ticket_id'] ?? '',
      'created_at': raw['ts'] ?? DateTime.now().toUtc().toIso8601String(),
    };
  }

  List<Map<String, dynamic>> get _filteredEvents {
    if (_filter == '전체') return _events;
    return _events.where((e) {
      final action = e['action'] as String? ?? '';
      return _actionCategory[action] == _filter;
    }).toList();
  }

  String _toKst(String? utcStr) {
    if (utcStr == null || utcStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(utcStr).add(const Duration(hours: 9));
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      if (utcStr.length >= 16) return utcStr.substring(5, 16).replaceFirst('T', ' ');
      return utcStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEvents;

    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        elevation: 0,
        title: Row(children: [
          Icon(Icons.rss_feed, size: 20, color: _connected ? const Color(0xFF4AC99B) : const Color(0xFF8b949e)),
          const SizedBox(width: 8),
          const Text('실시간 피드', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _connected ? const Color(0xFF4AC99B).withOpacity(0.15) : const Color(0xFFf85149).withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _connected ? 'LIVE' : 'OFFLINE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _connected ? const Color(0xFF4AC99B) : const Color(0xFFf85149),
              ),
            ),
          ),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(41),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF30363d), width: 0.5)),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _filters.map((f) => _filterChip(f)).toList(),
            ),
          ),
        ),
      ),
      body: filtered.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_connected ? Icons.rss_feed : Icons.cloud_off, size: 48, color: const Color(0xFF30363d)),
                const SizedBox(height: 12),
                Text(
                  _connected ? '이벤트 대기 중...' : '서버 연결 중...',
                  style: const TextStyle(color: Color(0xFF8b949e), fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  _connected ? '에이전트가 작업을 시작하면 실시간으로 표시됩니다' : '칸반 서버(localhost:5555)에 연결할 수 없습니다',
                  style: const TextStyle(color: Color(0xFF484f58), fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) => _eventTile(filtered[i]),
            ),
    );
  }

  Widget _filterChip(String label) {
    final selected = _filter == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: Material(
        color: selected ? const Color(0xFF1B96FF).withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => setState(() => _filter = label),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? const Color(0xFF58a6ff) : const Color(0xFF30363d)),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(label, style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? const Color(0xFF58a6ff) : const Color(0xFF8b949e),
            )),
          ),
        ),
      ),
    );
  }

  void _openTicket(String ticketId, Map<String, dynamic> event) async {
    // 티켓 정보 조회
    final api = context.read<ApiService>();
    final teamId = event['team_id']?.toString() ?? '';
    if (teamId.isEmpty) return;

    try {
      final res = await api.getBoard(teamId);
      if (!mounted) return;
      final board = res['board'] as Map<String, dynamic>? ?? {};
      final tickets = ((board['tickets'] as List?) ?? []).cast<Map<String, dynamic>>();
      final ticket = tickets.where((t) => t['ticket_id'] == ticketId).firstOrNull;

      if (ticket != null) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => TicketThreadSheet(ticket: ticket),
        );
      }
    } catch (_) {}
  }

  Widget _eventTile(Map<String, dynamic> event) {
    final action = event['action'] as String? ?? '';
    final meta = _actionMeta[action] ?? (Icons.arrow_right, const Color(0xFF8b949e));
    final msg = event['message'] as String? ?? event['description'] as String? ?? action;
    final teamName = event['team_name'] as String? ?? '';
    final ticketId = event['ticket_id'] as String? ?? '';
    final timeStr = _toKst(event['created_at'] as String? ?? event['timestamp'] as String?);

    return InkWell(
      onTap: ticketId.isNotEmpty ? () => _openTicket(ticketId, event) : null,
      child: Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF21262d), width: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: meta.$2.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Icon(meta.$1, size: 16, color: meta.$2)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (teamName.isNotEmpty)
            Text(teamName, style: const TextStyle(
              color: Color(0xFF58a6ff), fontSize: 10, fontWeight: FontWeight.w600,
            )),
          const SizedBox(height: 2),
          Text(msg, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, height: 1.4),
            maxLines: 3, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(timeStr, style: const TextStyle(color: Color(0xFF484f58), fontSize: 9)),
          if (ticketId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF1B96FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(ticketId, style: const TextStyle(color: Color(0xFF58a6ff), fontSize: 8, fontFamily: 'monospace')),
            ),
          ],
        ]),
      ]),
    ));
  }
}
