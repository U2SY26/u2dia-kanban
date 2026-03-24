import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

class BoardScreen extends StatefulWidget {
  final String teamId;
  const BoardScreen({super.key, required this.teamId});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  Map<String, dynamic> _board = {};
  bool _loading = true;
  Timer? _pollTimer;

  static const _cols = ['Backlog', 'InProgress', 'Blocked', 'Done'];
  static const _colColors = {
    'Backlog': Color(0xFF8b949e),
    'InProgress': Color(0xFF1B96FF),
    'Blocked': Color(0xFFFF4C4C),
    'Done': Color(0xFF4AC99B),
  };

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final res = await api.getBoard(widget.teamId);
    if (mounted && res['ok'] == true) {
      setState(() { _board = res; _loading = false; });
    } else if (mounted) {
      setState(() { _loading = false; });
    }
  }

  List<Map<String, dynamic>> _ticketsForCol(String col) {
    final tickets = (_board['tickets'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    return tickets.where((t) => t['status'] == col).toList();
  }

  @override
  Widget build(BuildContext context) {
    final team = _board['team'] as Map<String, dynamic>? ?? {};
    return Scaffold(
      appBar: AppBar(
        title: Text(team['name'] ?? '보드', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF161b22),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF30363d)),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              children: _cols.map((col) => _buildColumn(col)).toList(),
            ),
    );
  }

  Widget _buildColumn(String col) {
    final tickets = _ticketsForCol(col);
    final color = _colColors[col] ?? const Color(0xFF8b949e);
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0d1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF21262d)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 컬럼 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 8),
                Text(col, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${tickets.length}', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Container(height: 1, color: color.withOpacity(0.3)),
          // 티켓 목록
          Expanded(
            child: tickets.isEmpty
                ? const Center(child: Text('티켓 없음', style: TextStyle(color: Color(0xFF8b949e), fontSize: 12)))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: tickets.length,
                    itemBuilder: (_, i) => _TicketCard(ticket: tickets[i], statusColor: color),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final Color statusColor;
  const _TicketCard({required this.ticket, required this.statusColor});

  @override
  Widget build(BuildContext context) {
    final hasProgress = (ticket['progress_note'] as String? ?? '').isNotEmpty;
    final isLive = hasProgress && ticket['process_alive'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isLive ? const Color(0xFF1B96FF) : const Color(0xFF30363d),
          width: isLive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(ticket['ticket_id'] ?? '', style: const TextStyle(
                  color: Color(0xFF8b949e), fontSize: 9, fontFamily: 'monospace',
                )),
                if (isLive) ...[
                  const Spacer(),
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4AC99B),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(ticket['title'] ?? '', style: const TextStyle(
              color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w600,
            ), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (hasProgress) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B96FF).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border(left: BorderSide(color: statusColor, width: 2)),
                ),
                child: Text(ticket['progress_note'] ?? '', style: const TextStyle(
                  color: Color(0xFF8b949e), fontSize: 10,
                ), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
            if (ticket['claimed_by'] != null) ...[
              const SizedBox(height: 4),
              Text('👤 ${ticket['claimed_by']}', style: const TextStyle(
                color: Color(0xFF8b949e), fontSize: 9,
              )),
            ],
          ],
        ),
      ),
    );
  }
}
