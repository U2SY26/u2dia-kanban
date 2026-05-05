import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../theme/colors.dart';
import '../history/history_screen.dart';

class TeamDetailScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  const TeamDetailScreen({super.key, required this.teamId, required this.teamName});
  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map<String, dynamic>? _board;
  List<Map<String, dynamic>> _activity = [];
  List<Map<String, dynamic>> _artifacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final results = await Future.wait([
      api.getBoard(widget.teamId),
      api.get('/api/teams/${widget.teamId}/activity?limit=50'),
      api.getArtifacts(widget.teamId),
    ]);
    if (!mounted) return;
    setState(() {
      _board = results[0] as Map<String, dynamic>;
      _activity = ((results[1] as Map)['logs'] as List? ?? []).cast<Map<String, dynamic>>();
      _artifacts = (results[2] as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  String _time(String? s) {
    if (s == null) return '';
    try {
      final dt = DateTime.parse(s).add(const Duration(hours: 9));
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return s.length >= 16 ? s.substring(5, 16) : s; }
  }

  @override
  Widget build(BuildContext context) {
    final board = _board?['board'] as Map? ?? {};
    final members = ((board['members'] as List?) ?? []).cast<Map<String, dynamic>>();
    final tickets = ((board['tickets'] as List?) ?? []).cast<Map<String, dynamic>>();
    final stats = board['stats'] as Map? ?? {};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundElevated, elevation: 0,
        title: Text(widget.teamName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => HistoryScreen(teamId: widget.teamId, teamName: widget.teamName),
            )),
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: '멤버 (${members.length})'),
            Tab(text: '티켓 (${tickets.length})'),
            Tab(text: '산출물 (${_artifacts.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // 통계 헤더
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: AppColors.backgroundElevated,
                child: Row(children: [
                  _kpi('총 티켓', '${stats['total_tickets'] ?? tickets.length}'),
                  _kpi('완료율', '${stats['completion_rate'] ?? 0}%'),
                  _kpi('평균 시간', '${stats['avg_minutes_per_ticket'] != null ? (stats['avg_minutes_per_ticket'] as num).round() : '-'}m'),
                  _kpi('활동', '${_activity.length}'),
                ]),
              ),
              Expanded(child: TabBarView(controller: _tabCtrl, children: [
                _membersTab(members),
                _ticketsTab(tickets),
                _artifactsTab(),
              ])),
            ]),
    );
  }

  Widget _kpi(String label, String value) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFe6edf3))),
          Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF8b949e))),
        ]),
      );

  Widget _membersTab(List<Map<String, dynamic>> members) {
    if (members.isEmpty) return const Center(child: Text('멤버 없음', style: TextStyle(color: Color(0xFF8b949e))));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: members.length,
      itemBuilder: (_, i) {
        final m = members[i];
        final status = (m['status'] ?? '').toString();
        final isWorking = status == 'Working' || status == 'Active';
        return ListTile(
          dense: true,
          leading: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isWorking ? AppColors.brand.withOpacity(0.15) : const Color(0xFF21262d),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Text(isWorking ? '🤖' : '💤', style: const TextStyle(fontSize: 16))),
          ),
          title: Text((m['member_id'] ?? '').toString(),
              style: const TextStyle(fontSize: 12, color: Color(0xFFe6edf3), fontFamily: 'monospace')),
          subtitle: Text('${m['role'] ?? '-'} · $status · 티켓: ${m['current_ticket_id'] ?? '없음'}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF8b949e))),
        );
      },
    );
  }

  Widget _ticketsTab(List<Map<String, dynamic>> tickets) {
    final statusColor = {
      'Backlog': const Color(0xFF8b949e), 'Todo': const Color(0xFF9B59B6),
      'InProgress': const Color(0xFF1B96FF), 'Review': const Color(0xFFFF9F43),
      'Done': const Color(0xFF4AC99B), 'Blocked': const Color(0xFFf85149),
    };
    if (tickets.isEmpty) return const Center(child: Text('티켓 없음', style: TextStyle(color: Color(0xFF8b949e))));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: tickets.length,
      itemBuilder: (_, i) {
        final t = tickets[i];
        final status = (t['status'] ?? '').toString();
        return ListTile(
          dense: true,
          leading: Container(width: 8, height: 8, decoration: BoxDecoration(
            color: statusColor[status] ?? const Color(0xFF8b949e), shape: BoxShape.circle)),
          title: Text(t['title'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFFe6edf3))),
          subtitle: Text('$status · ${t['priority'] ?? ''} · ${t['assigned_member_id'] ?? '미할당'}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF8b949e))),
          trailing: Text(_time(t['created_at']?.toString()), style: const TextStyle(fontSize: 9, color: Color(0xFF484f58))),
        );
      },
    );
  }

  Widget _artifactsTab() {
    if (_artifacts.isEmpty) return const Center(child: Text('산출물 없음', style: TextStyle(color: Color(0xFF8b949e))));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _artifacts.length,
      itemBuilder: (_, i) {
        final a = _artifacts[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF21262d), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363d), width: 0.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('📎', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(child: Text((a['name'] ?? a['artifact_id'] ?? '').toString(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFe6edf3)))),
              Text(_time(a['created_at']?.toString()), style: const TextStyle(fontSize: 9, color: Color(0xFF484f58))),
            ]),
            if (a['content'] != null) ...[
              const SizedBox(height: 6),
              Text(a['content'].toString(), style: const TextStyle(fontSize: 11, color: Color(0xFF8b949e), height: 1.4),
                  maxLines: 5, overflow: TextOverflow.ellipsis),
            ],
          ]),
        );
      },
    );
  }
}
