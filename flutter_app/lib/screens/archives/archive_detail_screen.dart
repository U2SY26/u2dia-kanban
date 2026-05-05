import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../theme/colors.dart';

class ArchiveDetailScreen extends StatefulWidget {
  final Map<String, dynamic> archive;
  const ArchiveDetailScreen({super.key, required this.archive});
  @override
  State<ArchiveDetailScreen> createState() => _ArchiveDetailScreenState();
}

class _ArchiveDetailScreenState extends State<ArchiveDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map<String, dynamic>? _board;
  List<Map<String, dynamic>> _activity = [];
  List<Map<String, dynamic>> _artifacts = [];
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  String get _teamId => (widget.archive['team_id'] ?? widget.archive['team']?['team_id'] ?? '').toString();
  String get _teamName => (widget.archive['name'] ?? widget.archive['team']?['name'] ?? _teamId).toString();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final results = await Future.wait([
      api.getBoard(_teamId),
      api.get('/api/teams/$_teamId/activity?limit=100'),
      api.getArtifacts(_teamId),
      api.getMessages(_teamId),
    ]);
    if (!mounted) return;
    setState(() {
      _board = results[0] as Map<String, dynamic>;
      final actRes = results[1] as Map<String, dynamic>;
      _activity = ((actRes['logs'] as List?) ?? []).cast<Map<String, dynamic>>();
      _artifacts = (results[2] as List).cast<Map<String, dynamic>>();
      _messages = (results[3] as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  String _time(String? s) {
    if (s == null) return '';
    try {
      final dt = DateTime.parse(s).add(const Duration(hours: 9));
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s.length >= 16 ? s.substring(5, 16).replaceFirst('T', ' ') : s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final archive = widget.archive;
    final stats = (archive['stats'] as Map?) ?? {};
    final total = (stats['total_tickets'] as num?)?.toInt() ?? (archive['total_tickets'] as num?)?.toInt() ?? 0;
    final done = (stats['done_tickets'] as num?)?.toInt() ?? (archive['done_tickets'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundElevated,
        elevation: 0,
        title: Text(_teamName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: [
            Tab(text: '티켓 ($total)'),
            Tab(text: '활동 (${_activity.length})'),
            Tab(text: '산출물 (${_artifacts.length})'),
            Tab(text: '대화 (${_messages.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // 요약 헤더
              Container(
                padding: const EdgeInsets.all(14),
                color: AppColors.backgroundElevated,
                child: Row(children: [
                  _statChip('📋', '$done/$total', '완료'),
                  const SizedBox(width: 12),
                  _statChip('🤖', '${(archive['member_count'] ?? stats['total_agents'] ?? 0)}', '에이전트'),
                  const SizedBox(width: 12),
                  _statChip('📎', '${_artifacts.length}', '산출물'),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(total > 0 ? '${(done / total * 100).round()}%' : '0%',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                  ),
                ]),
              ),
              // 탭 본문
              Expanded(
                child: TabBarView(controller: _tabCtrl, children: [
                  _ticketsTab(),
                  _activityTab(),
                  _artifactsTab(),
                  _messagesTab(),
                ]),
              ),
            ]),
    );
  }

  Widget _statChip(String icon, String value, String label) => Row(children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFe6edf3))),
        const SizedBox(width: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF8b949e))),
      ]);

  Widget _ticketsTab() {
    final board = _board?['board'] as Map? ?? {};
    final tickets = ((board['tickets'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (tickets.isEmpty) return const Center(child: Text('티켓 없음', style: TextStyle(color: Color(0xFF8b949e))));

    final statusColor = {
      'Backlog': const Color(0xFF8b949e), 'Todo': const Color(0xFF9B59B6),
      'InProgress': const Color(0xFF1B96FF), 'Review': const Color(0xFFFF9F43),
      'Done': const Color(0xFF4AC99B), 'Blocked': const Color(0xFFf85149),
    };

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: tickets.length,
      itemBuilder: (_, i) {
        final t = tickets[i];
        final status = (t['status'] ?? '').toString();
        final color = statusColor[status] ?? const Color(0xFF8b949e);
        return ListTile(
          dense: true,
          leading: Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          title: Text(t['title'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFFe6edf3))),
          subtitle: Text('$status · ${t['priority'] ?? 'Medium'} · ${t['assigned_member_id'] ?? '미할당'}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF8b949e))),
          trailing: Text(_time(t['created_at']?.toString()), style: const TextStyle(fontSize: 9, color: Color(0xFF484f58))),
          onTap: () => _showTicketDetail(t),
        );
      },
    );
  }

  void _showTicketDetail(Map<String, dynamic> ticket) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.3,
        expand: false,
        builder: (ctx, scroll) => _TicketDetailSheet(ticket: ticket, scrollCtrl: scroll),
      ),
    );
  }

  Widget _activityTab() {
    if (_activity.isEmpty) return const Center(child: Text('활동 없음', style: TextStyle(color: Color(0xFF8b949e))));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _activity.length,
      itemBuilder: (_, i) {
        final a = _activity[i];
        return ListTile(
          dense: true,
          leading: Text(_actIcon(a['action']?.toString() ?? ''), style: const TextStyle(fontSize: 13)),
          title: Text((a['message'] ?? a['action'] ?? '').toString(),
              style: const TextStyle(fontSize: 12, color: Color(0xFFe6edf3)), maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text(_time(a['created_at']?.toString()), style: const TextStyle(fontSize: 9, color: Color(0xFF484f58))),
        );
      },
    );
  }

  String _actIcon(String action) => const {
        'ticket_created': '🎫', 'ticket_status_changed': '🔄', 'ticket_claimed': '⚡',
        'member_spawned': '🤖', 'artifact_created': '📎', 'feedback_created': '⭐',
        'progress': '▶', 'activity_logged': '⚡',
      }[action] ?? '•';

  Widget _artifactsTab() {
    if (_artifacts.isEmpty) return const Center(child: Text('산출물 없음', style: TextStyle(color: Color(0xFF8b949e))));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _artifacts.length,
      itemBuilder: (_, i) {
        final a = _artifacts[i];
        return ListTile(
          dense: true,
          leading: const Text('📎', style: TextStyle(fontSize: 14)),
          title: Text((a['name'] ?? a['artifact_id'] ?? '').toString(),
              style: const TextStyle(fontSize: 12, color: Color(0xFFe6edf3))),
          subtitle: Text((a['content'] ?? '').toString(),
              style: const TextStyle(fontSize: 10, color: Color(0xFF8b949e)),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text(_time(a['created_at']?.toString()), style: const TextStyle(fontSize: 9, color: Color(0xFF484f58))),
        );
      },
    );
  }

  Widget _messagesTab() {
    if (_messages.isEmpty) return const Center(child: Text('대화 없음', style: TextStyle(color: Color(0xFF8b949e))));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final sender = (m['sender'] ?? m['member_id'] ?? '').toString();
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF21262d),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363d), width: 0.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(sender, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF58a6ff))),
              const Spacer(),
              Text(_time(m['created_at']?.toString()), style: const TextStyle(fontSize: 9, color: Color(0xFF484f58))),
            ]),
            const SizedBox(height: 4),
            Text((m['content'] ?? '').toString(),
                style: const TextStyle(fontSize: 12, color: Color(0xFFe6edf3), height: 1.5)),
          ]),
        );
      },
    );
  }
}

class _TicketDetailSheet extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final ScrollController scrollCtrl;
  const _TicketDetailSheet({required this.ticket, required this.scrollCtrl});
  @override
  State<_TicketDetailSheet> createState() => _TicketDetailSheetState();
}

class _TicketDetailSheetState extends State<_TicketDetailSheet> {
  List<Map<String, dynamic>> _thread = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final tid = widget.ticket['ticket_id']?.toString() ?? '';
    if (tid.isEmpty) { setState(() => _loading = false); return; }
    final thread = await api.ticketThread(tid);
    if (mounted) setState(() { _thread = thread; _loading = false; });
  }

  String _time(String? s) {
    if (s == null) return '';
    try {
      final dt = DateTime.parse(s).add(const Duration(hours: 9));
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF30363d)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFF484f58), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Text(t['title'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFe6edf3))),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            _chip(t['status'] ?? '', AppColors.brand),
            _chip(t['priority'] ?? 'Medium', AppColors.warning),
            if (t['assigned_member_id'] != null) _chip('🤖 ${t['assigned_member_id']}', const Color(0xFF8b949e)),
          ]),
          if (t['description'] != null && t['description'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(t['description'].toString(), style: const TextStyle(fontSize: 12, color: Color(0xFF8b949e), height: 1.5)),
          ],
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _thread.isEmpty
                ? const Center(child: Text('히스토리 없음', style: TextStyle(color: Color(0xFF8b949e))))
                : ListView.builder(
                    controller: widget.scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _thread.length,
                    itemBuilder: (_, i) {
                      final h = _thread[i];
                      final typeIcons = {'conversation': '💬', 'review': '📋', 'artifact': '📦', 'activity': '⚡', 'feedback': '⭐'};
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161b22), borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(typeIcons[h['type']] ?? 'ℹ️', style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 6),
                            Text((h['actor'] ?? h['sender'] ?? h['type'] ?? '').toString(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF58a6ff))),
                            const Spacer(),
                            Text(_time(h['created_at']?.toString()), style: const TextStyle(fontSize: 9, color: Color(0xFF484f58))),
                          ]),
                          const SizedBox(height: 4),
                          Text((h['content'] ?? h['message'] ?? '').toString(),
                              style: const TextStyle(fontSize: 12, color: Color(0xFFe6edf3), height: 1.4),
                              maxLines: 10, overflow: TextOverflow.ellipsis),
                        ]),
                      );
                    },
                  ),
      ),
    ]);
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      );
}
