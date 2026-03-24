import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  final Function(String teamId) onTeamTap;
  const DashboardScreen({super.key, required this.onTeamTap});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> _teams = [];
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('ko', timeago.KoMessages());
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.read<ApiService>();
      final teams = await api.getTeams();
      final overview = await api.get('/api/overview');
      setState(() {
        _teams = teams.where((t) => t['status'] != 'Archived').toList();
        _stats = overview['stats'] ?? {};
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: const Color(0xFF1B96FF), borderRadius: BorderRadius.circular(7)),
              child: const Center(child: Text('U', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
            ),
            const SizedBox(width: 10),
            const Text('U2DIA AI', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
        backgroundColor: const Color(0xFF161b22),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF30363d)),
        ),
        actions: [
          Consumer<ApiService>(
            builder: (_, api, __) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.circle, size: 10,
                color: api.connected ? const Color(0xFF4AC99B) : const Color(0xFF8b949e)),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: Color(0xFFFF4C4C), size: 40),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
                  TextButton(onPressed: _load, child: const Text('다시 시도')),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildStats()),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            '활성 팀 (${_teams.length})',
                            style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _TeamCard(team: _teams[i], onTap: () => widget.onTeamTap(_teams[i]['team_id'])),
                          childCount: _teams.length,
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStats() {
    final kpis = [
      {'label': '활성 팀', 'val': '${_teams.length}', 'color': const Color(0xFF1B96FF)},
      {'label': '총 티켓', 'val': '${_stats['total_tickets'] ?? 0}', 'color': const Color(0xFF4AC99B)},
      {'label': '진행 중', 'val': '${_stats['in_progress_tickets'] ?? 0}', 'color': const Color(0xFFFF9F43)},
      {'label': '완료율', 'val': '${_stats['global_progress'] ?? 0}%', 'color': const Color(0xFF9B59B6)},
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: kpis.map((k) => Expanded(
          child: Container(
            margin: EdgeInsets.only(right: kpis.indexOf(k) < kpis.length - 1 ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF161b22),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF30363d)),
            ),
            child: Column(
              children: [
                Text(k['val'] as String, style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: k['color'] as Color,
                )),
                const SizedBox(height: 2),
                Text(k['label'] as String, style: const TextStyle(
                  fontSize: 9, color: Color(0xFF8b949e),
                )),
              ],
            ),
          ),
        )).toList(),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final Map<String, dynamic> team;
  final VoidCallback onTap;
  const _TeamCard({required this.team, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final progress = (team['progress'] ?? 0) as num;
    final done = team['done_tickets'] ?? 0;
    final total = team['total_tickets'] ?? 0;
    final status = team['status'] ?? 'Active';

    Color statusColor;
    switch (status) {
      case 'Active': statusColor = const Color(0xFF4AC99B); break;
      case 'Blocked': statusColor = const Color(0xFFFF4C4C); break;
      default: statusColor = const Color(0xFF8b949e);
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161b22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF30363d)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(child: Text(team['name'] ?? '', style: const TextStyle(
                  color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w600,
                ), overflow: TextOverflow.ellipsis)),
                Text('$done/$total', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
              ],
            ),
            if (team['description']?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(team['description'], style: const TextStyle(
                color: Color(0xFF8b949e), fontSize: 11,
              ), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: const Color(0xFF30363d),
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 80 ? const Color(0xFF4AC99B) : const Color(0xFF1B96FF),
                ),
                minHeight: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
