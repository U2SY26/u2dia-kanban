import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';

class TicketThreadSheet extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const TicketThreadSheet({super.key, required this.ticket});
  @override State<TicketThreadSheet> createState() => _TicketThreadSheetState();
}

class _TicketThreadSheetState extends State<TicketThreadSheet> {
  List<Map<String, dynamic>> _thread = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final tid = widget.ticket['ticket_id'] as String? ?? '';
    final items = await api.ticketThread(tid);
    if (mounted) setState(() { _thread = items; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final status = ticket['status'] as String? ?? '';
    final statusColors = {
      'Backlog': const Color(0xFF8b949e), 'Todo': const Color(0xFF58a6ff),
      'InProgress': const Color(0xFFd29922), 'Review': const Color(0xFFa371f7),
      'Blocked': const Color(0xFFf85149), 'Done': const Color(0xFF3fb950),
    };
    final statusColor = statusColors[status] ?? const Color(0xFF8b949e);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF161b22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(children: [
          // 핸들
          Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 12),
            decoration: BoxDecoration(color: const Color(0xFF30363d), borderRadius: BorderRadius.circular(2))),
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 8),
                Text(ticket['ticket_id'] ?? '', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10, fontFamily: 'monospace')),
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(status, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 6),
              Text(ticket['title'] ?? '', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 14, fontWeight: FontWeight.w600)),
              if ((ticket['progress_note'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF1B96FF).withOpacity(0.08), borderRadius: BorderRadius.circular(6),
                    border: Border(left: BorderSide(color: statusColor, width: 2))),
                  child: Text(ticket['progress_note'], style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11), maxLines: 3, overflow: TextOverflow.ellipsis)),
              ],
            ]),
          ),
          const Divider(height: 1, color: Color(0xFF30363d)),
          // 스레드 제목
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              const Text('대화 스레드', style: TextStyle(color: Color(0xFF8b949e), fontSize: 11, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (!_loading) Text('${_thread.length}건', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
              const SizedBox(width: 8),
              GestureDetector(onTap: () { setState(() => _loading = true); _load(); },
                child: const Icon(Icons.refresh, size: 14, color: Color(0xFF8b949e))),
            ]),
          ),
          // 스레드 목록
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)))
                : _thread.isEmpty
                    ? const Center(child: Text('기록 없음', style: TextStyle(color: Color(0xFF8b949e), fontSize: 12)))
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _thread.length,
                        itemBuilder: (c, i) => _ThreadItem(item: _thread[i]),
                      ),
          ),
        ]),
      ),
    );
  }
}

class _ThreadItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ThreadItem({required this.item});

  static const _kindMeta = {
    'conversation': (Icons.chat_bubble_outline, Color(0xFF58a6ff)),
    'qa':           (Icons.verified_outlined,   Color(0xFF3fb950)),
    'activity':     (Icons.bar_chart,            Color(0xFF1B96FF)),
    'artifact':     (Icons.inventory_2_outlined, Color(0xFFa371f7)),
  };
  static const _typeMeta = {
    'meeting':  ('🏛', Color(0xFFFF9F43), '회의'),
    'rework':   ('🔄', Color(0xFFFF9F43), '재작업'),
    'response': ('↩', Color(0xFFe6edf3), '답변'),
    'fail':     ('❌', Color(0xFFf85149), 'QA실패'),
    'pass':     ('✅', Color(0xFF3fb950), 'QA통과'),
    'question': ('❓', Color(0xFF58a6ff), '질문'),
    'progress': ('▶', Color(0xFF1B96FF), '진행'),
  };

  @override
  Widget build(BuildContext context) {
    final kind = item['kind'] as String? ?? 'conversation';
    final msgType = item['msg_type'] as String? ?? '';
    final speaker = item['speaker'] as String? ?? '-';
    final toAgent = item['to_agent'] as String? ?? '';
    final message = item['message'] as String? ?? '';
    final createdAt = (item['created_at'] as String? ?? '');
    final timeStr = createdAt.length >= 16 ? createdAt.substring(11, 16) : '';
    final score = item['score'];

    final meta = _kindMeta[kind] ?? (Icons.circle, const Color(0xFF8b949e));
    final tmeta = _typeMeta[msgType];
    final iconData = meta.$1;
    final iconColor = meta.$2;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 28, height: 28,
          decoration: BoxDecoration(color: iconColor.withOpacity(0.12), shape: BoxShape.circle,
            border: Border.all(color: iconColor.withOpacity(0.3))),
          child: Icon(iconData, size: 14, color: iconColor)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(speaker, style: TextStyle(color: iconColor, fontSize: 11, fontWeight: FontWeight.w700)),
            if (toAgent.isNotEmpty && toAgent != '팀' && toAgent != '전체') ...[
              const Text(' → ', style: TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
              Text(toAgent, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
            ],
            if (tmeta != null) ...[
              const SizedBox(width: 4),
              Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: tmeta.$2.withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
                child: Text('${tmeta.$1} ${tmeta.$3}', style: TextStyle(color: tmeta.$2, fontSize: 9))),
            ],
            if (score != null) ...[
              const SizedBox(width: 4),
              Text('$score/5', style: const TextStyle(color: Color(0xFF3fb950), fontSize: 10, fontWeight: FontWeight.w700)),
            ],
            const Spacer(),
            Text(timeStr, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
          ]),
          const SizedBox(height: 3),
          Text(message, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11, height: 1.4),
            maxLines: 5, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}
