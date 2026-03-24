import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import 'ticket_thread_sheet.dart';

class KanbanScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  const KanbanScreen({super.key, required this.teamId, required this.teamName});
  @override State<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends State<KanbanScreen> {
  Map<String, dynamic> _board = {};
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  Timer? _timer;

  static const _cols = ['Backlog', 'Todo', 'InProgress', 'Review', 'Blocked', 'Done'];
  static const _colColors = {
    'Backlog': Color(0xFF8b949e),
    'Todo': Color(0xFF58a6ff),
    'InProgress': Color(0xFFd29922),
    'Review': Color(0xFFa371f7),
    'Blocked': Color(0xFFf85149),
    'Done': Color(0xFF3fb950),
  };

  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() { _timer?.cancel(); _hScroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final res = await api.getBoard(widget.teamId);
    if (mounted && res['ok'] == true) {
      final board = res['board'] as Map<String, dynamic>? ?? {};
      setState(() {
        _board = board;
        _tickets = ((board['tickets'] as List?) ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } else if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> _ticketsFor(String col) =>
      _tickets.where((t) => t['status'] == col).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        title: Text(widget.teamName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF161b22), elevation: 0,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: const Color(0xFF30363d))),
        actions: [
          IconButton(icon: const Icon(Icons.add_circle_outline, size: 22), onPressed: _showCreateTicketDialog),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)))
          : Column(children: [
              // ── 틀고정 컬럼 헤더 (가로 스크롤 동기화) ──
              _StickyColumnHeader(scrollController: _hScroll, cols: _cols, colColors: _colColors, tickets: _tickets),
              // ── 칸반 보드 본문 (가로+세로 스크롤) ──
              Expanded(
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _cols.length * 200.0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _cols.map((col) => _buildColumn(col)).toList(),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }

  Widget _buildColumn(String col) {
    final tickets = _ticketsFor(col);
    final color = _colColors[col]!;
    return SizedBox(
      width: 200,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
        itemCount: tickets.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) return _addTicketBtn(col);
          return _TicketCard(ticket: tickets[i - 1], statusColor: color,
            onStatusChange: (s) => _changeStatus(tickets[i - 1]['ticket_id'], s));
        },
      ),
    );
  }

  Widget _addTicketBtn(String col) => col == 'Backlog'
      ? Padding(padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: _showCreateTicketDialog,
            icon: const Icon(Icons.add, size: 14, color: Color(0xFF8b949e)),
            label: const Text('티켓 추가', style: TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF30363d)),
              padding: const EdgeInsets.symmetric(vertical: 6),
              minimumSize: const Size(double.infinity, 32),
            ),
          ))
      : const SizedBox.shrink();

  Future<void> _changeStatus(String ticketId, String status) async {
    final api = context.read<ApiService>();
    await api.updateTicketStatus(ticketId, status);
    _load();
  }

  void _showCreateTicketDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'medium';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
      backgroundColor: const Color(0xFF161b22),
      title: const Text('새 티켓', style: TextStyle(color: Color(0xFFe6edf3), fontSize: 15)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _field('제목', titleCtrl),
        const SizedBox(height: 10),
        _field('설명', descCtrl, maxLines: 3),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: priority,
          dropdownColor: const Color(0xFF161b22),
          style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12),
          decoration: InputDecoration(labelText: '우선순위',
            labelStyle: const TextStyle(color: Color(0xFF8b949e), fontSize: 11),
            filled: true, fillColor: const Color(0xFF0d1117),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363d))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363d))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
          items: ['low', 'medium', 'high', 'critical'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: (v) => setSt(() => priority = v ?? 'medium'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Color(0xFF8b949e)))),
        ElevatedButton(
          onPressed: () async {
            if (titleCtrl.text.isEmpty) return;
            final api = context.read<ApiService>();
            await api.createTicket(widget.teamId, {'title': titleCtrl.text, 'description': descCtrl.text, 'priority': priority});
            if (mounted) { Navigator.pop(ctx); _load(); }
          },
          child: const Text('생성'),
        ),
      ],
    )));
  }

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) => TextField(
    controller: ctrl, maxLines: maxLines,
    style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13),
    decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Color(0xFF8b949e), fontSize: 12),
      filled: true, fillColor: const Color(0xFF0d1117),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363d))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363d))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
  );
}

// 틀고정 헤더 위젯 (가로 스크롤과 동기화)
class _StickyColumnHeader extends StatefulWidget {
  final ScrollController scrollController;
  final List<String> cols;
  final Map<String, Color> colColors;
  final List<Map<String, dynamic>> tickets;
  const _StickyColumnHeader({required this.scrollController, required this.cols, required this.colColors, required this.tickets});
  @override State<_StickyColumnHeader> createState() => _StickyColumnHeaderState();
}

class _StickyColumnHeaderState extends State<_StickyColumnHeader> {
  double _offset = 0;
  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }
  void _onScroll() => setState(() => _offset = widget.scrollController.offset);
  @override
  void dispose() { widget.scrollController.removeListener(_onScroll); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161b22),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Transform.translate(
          offset: Offset(-_offset, 0),
          child: Row(children: widget.cols.map((col) {
            final count = widget.tickets.where((t) => t['status'] == col).length;
            final color = widget.colColors[col]!;
            return SizedBox(width: 200, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color.withOpacity(0.4), width: 1.5))),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 8),
                Text(col, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                  child: Text('$count', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600))),
              ]),
            ));
          }).toList()),
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final Color statusColor;
  final Function(String) onStatusChange;
  const _TicketCard({required this.ticket, required this.statusColor, required this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final hasProgress = (ticket['progress_note'] as String? ?? '').isNotEmpty;
    final isLive = hasProgress;
    final priority = ticket['priority'] ?? 'medium';
    final priorityColor = {'critical': const Color(0xFFFF4C4C), 'high': const Color(0xFFFF9F43), 'medium': const Color(0xFF1B96FF), 'low': const Color(0xFF8b949e)}[priority] ?? const Color(0xFF8b949e);

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => TicketThreadSheet(ticket: ticket),
      ),
      onLongPress: () => _showStatusMenu(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF161b22), borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isLive ? const Color(0xFF1B96FF) : const Color(0xFF30363d), width: isLive ? 1.5 : 1)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 4, height: 4, decoration: BoxDecoration(color: priorityColor, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Expanded(child: Text(ticket['ticket_id'] ?? '', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9, fontFamily: 'monospace'))),
              if (isLive) Container(width: 6, height: 6, decoration: BoxDecoration(color: const Color(0xFF4AC99B), borderRadius: BorderRadius.circular(3))),
            ]),
            const SizedBox(height: 5),
            Text(ticket['title'] ?? '', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w600), maxLines: 3, overflow: TextOverflow.ellipsis),
            if ((ticket['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(ticket['description'], style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (hasProgress) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF1B96FF).withOpacity(0.08), borderRadius: BorderRadius.circular(4),
                  border: Border(left: BorderSide(color: statusColor, width: 2))),
                child: Text(ticket['progress_note'], style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
            const SizedBox(height: 6),
            Row(children: [
              if (ticket['claimed_by'] != null) Expanded(child: Text('👤 ${ticket['claimed_by']}', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9))),
              const Spacer(),
              GestureDetector(onTap: () => _showStatusMenu(context),
                child: const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF8b949e))),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showStatusMenu(BuildContext context) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF161b22),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('상태 변경', style: TextStyle(color: Color(0xFFe6edf3), fontWeight: FontWeight.w600))),
        ...['Backlog', 'Todo', 'InProgress', 'Review', 'Blocked', 'Done'].map((s) {
          final colors = {'Backlog': const Color(0xFF8b949e), 'Todo': const Color(0xFF58a6ff), 'InProgress': const Color(0xFFd29922), 'Review': const Color(0xFFa371f7), 'Blocked': const Color(0xFFf85149), 'Done': const Color(0xFF3fb950)};
          return ListTile(
            leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[s], borderRadius: BorderRadius.circular(5))),
            title: Text(s, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13)),
            trailing: ticket['status'] == s ? const Icon(Icons.check, color: Color(0xFF4AC99B), size: 16) : null,
            onTap: () { Navigator.pop(context); onStatusChange(s); },
          );
        }),
        const SizedBox(height: 20),
      ]),
    );
  }
}
