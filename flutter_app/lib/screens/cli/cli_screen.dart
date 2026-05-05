import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';

class CliScreen extends StatefulWidget {
  const CliScreen({super.key});
  @override
  State<CliScreen> createState() => _CliScreenState();
}

class _CliScreenState extends State<CliScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // 팀 목록
  List<Map<String, dynamic>> _teams = [];
  String? _selectedTeamId;
  String _selectedTeamName = '';

  // 티켓 목록
  List<Map<String, dynamic>> _tickets = [];
  bool _loadingTickets = false;

  // 텔레그램
  final TextEditingController _teleCtrl = TextEditingController();
  bool _sendingTele = false;

  // 로그
  List<String> _logs = ['[시스템] U2DIA CLI 패널 준비됨'];

  // 티켓 생성
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  String _priority = 'medium';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadTeams();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _teleCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    final api = context.read<ApiService>();
    final teams = await api.getTeams(status: 'active');
    if (!mounted) return;
    setState(() => _teams = teams);
    if (teams.isNotEmpty && _selectedTeamId == null) {
      _selectedTeamId = teams.first['team_id'] as String;
      _selectedTeamName = teams.first['name'] as String? ?? '';
      _loadTickets();
    }
  }

  Future<void> _loadTickets() async {
    if (_selectedTeamId == null) return;
    setState(() => _loadingTickets = true);
    final api = context.read<ApiService>();
    final board = await api.getBoard(_selectedTeamId!);
    if (!mounted) return;
    final boardData = board['board'] as Map<String, dynamic>? ?? {};
    final tickets = (boardData['tickets'] as List? ?? []).cast<Map<String, dynamic>>();
    setState(() {
      _tickets = tickets;
      _loadingTickets = false;
    });
  }

  void _addLog(String msg) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() => _logs.add('[$ts] $msg'));
  }

  Future<void> _createTicket() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _selectedTeamId == null) return;
    final api = context.read<ApiService>();
    final res = await api.createTicket(_selectedTeamId!, {
      'title': title,
      'description': _descCtrl.text.trim(),
      'priority': _priority,
    });
    if (!mounted) return;
    if (res['ok'] == true) {
      _addLog('✅ 티켓 생성: $title (${res['ticket']?['ticket_id'] ?? ''})');
      _titleCtrl.clear();
      _descCtrl.clear();
      _loadTickets();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('티켓 생성됨'), backgroundColor: Color(0xFF3fb950), duration: Duration(seconds: 2)));
    } else {
      _addLog('❌ 티켓 생성 실패: ${res['error'] ?? ''}');
    }
  }

  Future<void> _updateStatus(String ticketId, String status) async {
    final api = context.read<ApiService>();
    final res = await api.updateTicketStatus(ticketId, status);
    if (!mounted) return;
    if (res['ok'] == true) {
      _addLog('📊 상태 변경: $ticketId → $status');
      _loadTickets();
    } else {
      _addLog('❌ 상태 변경 실패: ${res['error'] ?? ''}');
    }
  }

  Future<void> _sendTelegram() async {
    final msg = _teleCtrl.text.trim();
    if (msg.isEmpty || _sendingTele) return;
    setState(() => _sendingTele = true);
    _addLog('📤 텔레그램 전송: $msg');
    final api = context.read<ApiService>();
    final res = await api.sendTelegram(msg);
    if (!mounted) return;
    setState(() => _sendingTele = false);
    if (res['ok'] == true) {
      _addLog('✅ 텔레그램 전송 완료');
      _teleCtrl.clear();
    } else {
      _addLog('❌ 텔레그램 실패: ${res['error'] ?? ''}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        elevation: 0,
        title: const Row(children: [
          Icon(Icons.terminal, color: Color(0xFF1B96FF), size: 20),
          SizedBox(width: 8),
          Text('CLI 운영', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF1B96FF),
          labelColor: const Color(0xFF1B96FF),
          unselectedLabelColor: const Color(0xFF8b949e),
          tabs: const [
            Tab(icon: Icon(Icons.confirmation_number_outlined, size: 18), text: '티켓 관리'),
            Tab(icon: Icon(Icons.send_to_mobile, size: 18), text: '텔레그램'),
            Tab(icon: Icon(Icons.receipt_long, size: 18), text: '로그'),
          ],
        ),
      ),
      body: Column(children: [
        // 팀 선택
        _teamBar(),
        Expanded(
          child: TabBarView(controller: _tabCtrl, children: [
            _ticketTab(),
            _telegramTab(),
            _logTab(),
          ]),
        ),
      ]),
    );
  }

  Widget _teamBar() {
    return Container(
      color: const Color(0xFF1c2128),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        const Icon(Icons.folder_open, size: 14, color: Color(0xFF8b949e)),
        const SizedBox(width: 8),
        Expanded(
          child: _teams.isEmpty
              ? const Text('팀 로딩 중...', style: TextStyle(color: Color(0xFF8b949e), fontSize: 12))
              : DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedTeamId,
                    dropdownColor: const Color(0xFF21262d),
                    style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13),
                    isDense: true,
                    items: _teams.map((t) => DropdownMenuItem(
                      value: t['team_id'] as String,
                      child: Text(t['name'] as String? ?? ''),
                    )).toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      final team = _teams.firstWhere((t) => t['team_id'] == id);
                      setState(() {
                        _selectedTeamId = id;
                        _selectedTeamName = team['name'] as String? ?? '';
                      });
                      _loadTickets();
                    },
                  ),
                ),
        ),
        IconButton(icon: const Icon(Icons.refresh, size: 16), onPressed: _loadTickets, padding: EdgeInsets.zero),
      ]),
    );
  }

  Widget _ticketTab() {
    return Column(children: [
      // 티켓 생성 폼
      Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: Color(0xFF161b22),
          border: Border(bottom: BorderSide(color: Color(0xFF30363d))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('새 티켓', style: TextStyle(color: Color(0xFF8b949e), fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _titleCtrl,
                style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '티켓 제목',
                  hintStyle: TextStyle(color: Color(0xFF484f58), fontSize: 12),
                  filled: true,
                  fillColor: Color(0xFF21262d),
                  border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF30363d))),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF30363d))),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF1B96FF))),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF21262d),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF30363d)),
                ),
                child: DropdownButton<String>(
                  value: _priority,
                  dropdownColor: const Color(0xFF21262d),
                  style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12),
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('낮음')),
                    DropdownMenuItem(value: 'medium', child: Text('중간')),
                    DropdownMenuItem(value: 'high', child: Text('높음')),
                    DropdownMenuItem(value: 'critical', child: Text('긴급')),
                  ],
                  onChanged: (v) => setState(() => _priority = v ?? 'medium'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _selectedTeamId != null ? _createTicket : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B96FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
              ),
              child: const Text('생성', style: TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12),
            decoration: const InputDecoration(
              hintText: '설명 (선택)',
              hintStyle: TextStyle(color: Color(0xFF484f58), fontSize: 11),
              filled: true,
              fillColor: Color(0xFF21262d),
              border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF30363d))),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF30363d))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF1B96FF))),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
          ),
        ]),
      ),
      // 티켓 목록
      Expanded(
        child: _loadingTickets
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _tickets.isEmpty
                ? const Center(child: Text('티켓 없음', style: TextStyle(color: Color(0xFF8b949e))))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _tickets.length,
                    itemBuilder: (ctx, i) => _TicketCard(
                      ticket: _tickets[i],
                      onStatusChange: _updateStatus,
                    ),
                  ),
      ),
    ]);
  }

  Widget _telegramTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('텔레그램 메시지 전송', style: TextStyle(color: Color(0xFF8b949e), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1c2128),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363d)),
          ),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.telegram, color: Color(0xFF58a6ff), size: 20),
              const SizedBox(width: 8),
              const Text('U2DIA Telegram Bot', style: TextStyle(color: Color(0xFF58a6ff), fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _teleCtrl,
              maxLines: 4,
              style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 14),
              decoration: const InputDecoration(
                hintText: '전송할 메시지를 입력하세요...',
                hintStyle: TextStyle(color: Color(0xFF484f58)),
                filled: true,
                fillColor: Color(0xFF21262d),
                border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF30363d))),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF30363d))),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF1B96FF))),
                contentPadding: EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sendingTele ? null : _sendTelegram,
                icon: _sendingTele
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 18),
                label: Text(_sendingTele ? '전송 중...' : '텔레그램 전송'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF58a6ff),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // 빠른 메시지
        const Text('빠른 메시지', style: TextStyle(color: Color(0xFF8b949e), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _quickMsg('🔴 긴급 알림'),
          _quickMsg('✅ 작업 완료'),
          _quickMsg('⚠️ 오류 발생'),
          _quickMsg('📊 현황 보고'),
          _quickMsg('🚀 배포 시작'),
          _quickMsg('🔧 점검 중'),
        ]),
      ]),
    );
  }

  Widget _quickMsg(String text) => GestureDetector(
    onTap: () => _teleCtrl.text = text,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF21262d),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363d)),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12)),
    ),
  );

  Widget _logTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: const Color(0xFF161b22),
        child: Row(children: [
          const Icon(Icons.receipt_long, size: 14, color: Color(0xFF8b949e)),
          const SizedBox(width: 6),
          const Text('실행 로그', style: TextStyle(color: Color(0xFF8b949e), fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _logs = ['[시스템] 로그 초기화됨']),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF8b949e), padding: EdgeInsets.zero, minimumSize: Size.zero),
            child: const Text('초기화', style: TextStyle(fontSize: 11)),
          ),
        ]),
      ),
      Expanded(
        child: Container(
          color: const Color(0xFF0d1117),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _logs.length,
            reverse: true,
            itemBuilder: (ctx, i) {
              final log = _logs[_logs.length - 1 - i];
              Color color = const Color(0xFF8b949e);
              if (log.contains('✅')) color = const Color(0xFF3fb950);
              if (log.contains('❌')) color = const Color(0xFFf85149);
              if (log.contains('⚠️') || log.contains('📤')) color = const Color(0xFFd29922);
              if (log.contains('[시스템]')) color = const Color(0xFF58a6ff);
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(log, style: TextStyle(color: color, fontSize: 12, fontFamily: 'monospace')),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

// ── 티켓 카드 ──────────────────────────────────
class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final void Function(String, String) onStatusChange;

  const _TicketCard({required this.ticket, required this.onStatusChange});

  Color _statusColor(String? s) {
    switch (s) {
      case 'Backlog': return const Color(0xFF8b949e);
      case 'Todo': return const Color(0xFF58a6ff);
      case 'InProgress': return const Color(0xFFd29922);
      case 'Review': return const Color(0xFFa371f7);
      case 'Blocked': return const Color(0xFFf85149);
      case 'Done': return const Color(0xFF3fb950);
      default: return const Color(0xFF8b949e);
    }
  }

  Color _priorityColor(String? p) {
    switch (p) {
      case 'critical': return const Color(0xFFf85149);
      case 'high': return const Color(0xFFd29922);
      case 'medium': return const Color(0xFF1B96FF);
      default: return const Color(0xFF8b949e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = ticket['ticket_id'] as String? ?? '';
    final title = ticket['title'] as String? ?? '';
    final status = ticket['status'] as String? ?? '';
    final priority = ticket['priority'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363d)),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 4,
          decoration: BoxDecoration(
            color: _priorityColor(priority),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(title, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w500)),
        subtitle: Row(children: [
          Text(id, style: const TextStyle(color: Color(0xFF484f58), fontSize: 11)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _statusColor(status).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _statusColor(status).withOpacity(0.4)),
            ),
            child: Text(status, style: TextStyle(color: _statusColor(status), fontSize: 10)),
          ),
        ]),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 16, color: Color(0xFF8b949e)),
          color: const Color(0xFF21262d),
          itemBuilder: (_) => [
            'Backlog', 'Todo', 'InProgress', 'Review', 'Blocked', 'Done'
          ].map((s) => PopupMenuItem(
            value: s,
            child: Row(children: [
              Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: _statusColor(s), shape: BoxShape.circle)),
              Text(s, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13)),
            ]),
          )).toList(),
          onSelected: (s) => onStatusChange(id, s),
        ),
      ),
    );
  }
}


