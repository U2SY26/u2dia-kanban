import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../theme/colors.dart';

class HistoryScreen extends StatefulWidget {
  final String? teamId;
  final String? teamName;
  const HistoryScreen({super.key, this.teamId, this.teamName});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String _filter = '전체';

  static const _actionIcon = {
    'ticket_created': ('🎫', Color(0xFF4AC99B)),
    'ticket_status_changed': ('🔄', Color(0xFFFF9F43)),
    'ticket_claimed': ('⚡', Color(0xFFFFD700)),
    'member_spawned': ('🤖', Color(0xFF9B59B6)),
    'team_created': ('🏗️', Color(0xFF1B96FF)),
    'team_archived': ('📦', Color(0xFF8b949e)),
    'artifact_created': ('📎', Color(0xFF1ABC9C)),
    'feedback_created': ('⭐', Color(0xFFFF9F43)),
    'message_sent': ('💬', Color(0xFF8b949e)),
    'progress': ('▶', Color(0xFF1B96FF)),
    'activity_logged': ('⚡', Color(0xFF58a6ff)),
  };

  static const _filters = ['전체', '티켓', '에이전트', '산출물'];
  static const _filterActions = {
    '티켓': ['ticket_created', 'ticket_status_changed', 'ticket_claimed'],
    '에이전트': ['member_spawned', 'team_created', 'team_archived'],
    '산출물': ['artifact_created', 'feedback_created'],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = context.read<ApiService>();
    final path = widget.teamId != null
        ? '/api/teams/${widget.teamId}/activity?limit=200'
        : '/api/supervisor/activity?limit=200';
    final res = await api.get(path);
    if (mounted) {
      setState(() {
        _logs = ((res['logs'] as List?) ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == '전체') return _logs;
    final actions = _filterActions[_filter] ?? [];
    return _logs.where((l) => actions.contains(l['action'])).toList();
  }

  String _time(String? s) {
    if (s == null || s.isEmpty) return '';
    try {
      final dt = DateTime.parse(s).add(const Duration(hours: 9));
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s.length >= 16 ? s.substring(5, 16).replaceFirst('T', ' ') : s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundElevated,
        elevation: 0,
        title: Text(widget.teamName != null ? '${widget.teamName} 히스토리' : '전체 히스토리',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(41),
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _filters.map((f) {
                final sel = _filter == f;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.brandBg : Colors.transparent,
                        border: Border.all(color: sel ? AppColors.brand : AppColors.border),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(f, style: TextStyle(
                        fontSize: 11, fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        color: sel ? AppColors.brand : AppColors.textSecondary,
                      )),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('활동 로그가 없습니다', style: TextStyle(color: Color(0xFF8b949e))))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _tile(items[i]),
                  ),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> log) {
    final action = (log['action'] ?? '').toString();
    final meta = _actionIcon[action];
    final icon = meta?.$1 ?? '•';
    final color = meta?.$2 ?? const Color(0xFF8b949e);
    final msg = (log['message'] ?? log['action'] ?? '').toString();
    final team = (log['team_name'] ?? '').toString();
    final time = _time(log['created_at']?.toString());

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF21262d), width: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 14))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (team.isNotEmpty)
            Text(team, style: const TextStyle(color: Color(0xFF58a6ff), fontSize: 10, fontWeight: FontWeight.w600)),
          Text(msg, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, height: 1.4),
              maxLines: 3, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 8),
        Text(time, style: const TextStyle(color: Color(0xFF484f58), fontSize: 9, fontFamily: 'monospace')),
      ]),
    );
  }
}
