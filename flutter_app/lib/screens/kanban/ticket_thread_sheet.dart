import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../cli/cli_jobs_screen.dart';

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

  void _showCliJobDialog(BuildContext ctx, Map<String, dynamic> ticket) {
    final promptCtrl = TextEditingController(
      text: '${ticket['title'] ?? ''}\n${ticket['description'] ?? ''}',
    );
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF161b22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF30363d))),
        title: Row(children: [
          const Icon(Icons.terminal, size: 18, color: Color(0xFF1B96FF)),
          const SizedBox(width: 8),
          Expanded(child: Text('CLI 작업: ${ticket['ticket_id'] ?? ''}',
            style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 14), overflow: TextOverflow.ellipsis)),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: promptCtrl, maxLines: 5, minLines: 3,
              style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13),
              decoration: InputDecoration(
                hintText: '코딩 작업 지시...',
                hintStyle: const TextStyle(color: Color(0xFF484f58), fontSize: 12),
                filled: true, fillColor: const Color(0xFF0d1117),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF30363d))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF30363d))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1B96FF))),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx),
            child: const Text('취소', style: TextStyle(color: Color(0xFF8b949e)))),
          ElevatedButton.icon(
            onPressed: () async {
              final prompt = promptCtrl.text.trim();
              if (prompt.isEmpty) return;
              Navigator.pop(dCtx);
              final api = ctx.read<ApiService>();
              final res = await api.createCliJob({
                'ticket_id': ticket['ticket_id'],
                'team_id': ticket['team_id'],
                'prompt': prompt,
              });
              if (!ctx.mounted) return;
              if (res['ok'] == true) {
                // 시트 닫고 CLI Jobs 화면으로
                Navigator.pop(ctx);
                Navigator.push(ctx, MaterialPageRoute(builder: (_) => const CliJobsScreen()));
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text('CLI 잡 생성: ${res['job_id']}'),
                  backgroundColor: const Color(0xFF3fb950)));
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text('실패: ${res['error'] ?? ''}'),
                  backgroundColor: const Color(0xFFf85149)));
              }
            },
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('작업 생성', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B96FF), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ],
      ),
    );
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
          Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 8),
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
                const Spacer(),
                // CLI 실행 버튼
                GestureDetector(
                  onTap: () => _showCliJobDialog(context, ticket),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B96FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF1B96FF).withOpacity(0.3)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.terminal, size: 12, color: Color(0xFF1B96FF)),
                      SizedBox(width: 4),
                      Text('CLI', style: TextStyle(color: Color(0xFF1B96FF), fontSize: 10, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
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
          // 탭 바
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF30363d)), bottom: BorderSide(color: Color(0xFF30363d)))),
            child: Row(children: [
              _tabBtn('대화', Icons.chat_bubble_outline, _tab == 0, () => setState(() => _tab = 0)),
              _tabBtn('산출물', Icons.inventory_2_outlined, _tab == 1, () => setState(() => _tab = 1)),
              _tabBtn('피드백', Icons.star_outline, _tab == 2, () => setState(() => _tab = 2)),
              _tabBtn('CLI', Icons.terminal, _tab == 3, () => setState(() => _tab = 3)),
            ]),
          ),
          // 탭 내용
          Expanded(
            child: _tab == 0
                ? _threadView(scroll)
                : _tab == 1
                    ? _artifactView(scroll)
                    : _tab == 2
                        ? _feedbackView(scroll)
                        : _cliJobsView(scroll),
          ),
        ]),
      ),
    );
  }

  int _tab = 0;

  Widget _tabBtn(String label, IconData icon, bool active, VoidCallback onTap) {
    return Expanded(child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(
          color: active ? const Color(0xFF1B96FF) : Colors.transparent, width: 2))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14, color: active ? const Color(0xFF1B96FF) : const Color(0xFF8b949e)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: active ? const Color(0xFF1B96FF) : const Color(0xFF8b949e),
            fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    ));
  }

  Widget _threadView(ScrollController scroll) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)));
    if (_thread.isEmpty) return const Center(child: Text('기록 없음', style: TextStyle(color: Color(0xFF8b949e), fontSize: 12)));
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _thread.length,
      itemBuilder: (c, i) => _ThreadItem(item: _thread[i]),
    );
  }

  Widget _artifactView(ScrollController scroll) {
    return _AsyncList(
      scroll: scroll,
      loader: () async {
        final api = context.read<ApiService>();
        final tid = widget.ticket['ticket_id'] as String? ?? '';
        final teamId = widget.ticket['team_id'] as String? ?? '';
        if (teamId.isEmpty) return [];
        final arts = await api.getArtifacts(teamId);
        return arts.where((a) => a['ticket_id'] == tid).toList();
      },
      emptyText: '산출물 없음',
      itemBuilder: (art) {
        final type = art['artifact_type'] ?? 'code';
        final title = art['title']?.toString() ?? '';
        final content = art['content']?.toString() ?? '';
        final created = (art['created_at'] ?? '').toString();
        final timeStr = created.length >= 16 ? created.substring(11, 16) : '';
        final icons = {'code': Icons.code, 'document': Icons.description, 'config': Icons.settings};
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0d1117), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363d))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icons[type] ?? Icons.attachment, size: 14, color: const Color(0xFF1ABC9C)),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w600))),
              Text(timeStr, style: const TextStyle(color: Color(0xFF484f58), fontSize: 9)),
            ]),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF161b22), borderRadius: BorderRadius.circular(4)),
                child: SelectableText(content.length > 500 ? '${content.substring(0, 500)}...' : content,
                  style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10, fontFamily: 'monospace', height: 1.4)),
              ),
            ],
          ]),
        );
      },
    );
  }

  Widget _feedbackView(ScrollController scroll) {
    return _AsyncList(
      scroll: scroll,
      loader: () async {
        final api = context.read<ApiService>();
        final tid = widget.ticket['ticket_id'] as String? ?? '';
        // thread에서 qa kind만 추출
        return _thread.where((t) => t['kind'] == 'qa' || (t['msg_type'] ?? '').toString().contains('pass') || (t['msg_type'] ?? '').toString().contains('fail')).toList();
      },
      emptyText: 'QA 피드백 없음',
      itemBuilder: (fb) {
        final score = fb['score'];
        final msg = fb['message']?.toString() ?? '';
        final speaker = fb['speaker']?.toString() ?? '';
        final created = (fb['created_at'] ?? '').toString();
        final timeStr = created.length >= 16 ? created.substring(11, 16) : '';
        final isPassed = score != null && (score as num) >= 3;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0d1117), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isPassed ? const Color(0xFF4AC99B).withOpacity(0.3) : const Color(0xFFf85149).withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(isPassed ? Icons.check_circle : Icons.cancel, size: 14,
                color: isPassed ? const Color(0xFF4AC99B) : const Color(0xFFf85149)),
              const SizedBox(width: 6),
              Text(speaker, style: const TextStyle(color: Color(0xFF58a6ff), fontSize: 11, fontWeight: FontWeight.w600)),
              if (score != null) ...[
                const Spacer(),
                Text('$score/5', style: TextStyle(
                  color: isPassed ? const Color(0xFF4AC99B) : const Color(0xFFf85149),
                  fontSize: 13, fontWeight: FontWeight.w800)),
              ],
              const Spacer(),
              Text(timeStr, style: const TextStyle(color: Color(0xFF484f58), fontSize: 9)),
            ]),
            if (msg.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(msg, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11, height: 1.4),
                maxLines: 5, overflow: TextOverflow.ellipsis),
            ],
          ]),
        );
      },
    );
  }

  Widget _cliJobsView(ScrollController scroll) {
    return _CliJobsForTicket(
      ticketId: widget.ticket['ticket_id'] as String? ?? '',
      scroll: scroll,
    );
  }
}

class _CliJobsForTicket extends StatefulWidget {
  final String ticketId;
  final ScrollController scroll;
  const _CliJobsForTicket({required this.ticketId, required this.scroll});
  @override
  State<_CliJobsForTicket> createState() => _CliJobsForTicketState();
}

class _CliJobsForTicketState extends State<_CliJobsForTicket> {
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  String? _expandedJobId;
  String _liveLog = '';
  Timer? _logTimer;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _logTimer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final all = await api.cliJobs();
    if (!mounted) return;
    setState(() {
      _jobs = all.where((j) => j['ticket_id'] == widget.ticketId).toList();
      _loading = false;
    });
  }

  void _toggleExpand(String jobId) {
    _logTimer?.cancel();
    if (_expandedJobId == jobId) {
      setState(() { _expandedJobId = null; _liveLog = ''; });
      return;
    }
    setState(() { _expandedJobId = jobId; _liveLog = ''; });
    _fetchLog(jobId);
    // running이면 폴링
    final job = _jobs.firstWhere((j) => j['job_id'] == jobId, orElse: () => {});
    if (job['status'] == 'running' || job['status'] == 'approved') {
      _logTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLog(jobId));
    }
  }

  Future<void> _fetchLog(String jobId) async {
    final api = context.read<ApiService>();
    final res = await api.cliJobLog(jobId);
    if (!mounted || _expandedJobId != jobId) return;
    setState(() => _liveLog = res['log']?.toString() ?? _liveLog);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)));
    if (_jobs.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.terminal, size: 36, color: Color(0xFF30363d)),
        const SizedBox(height: 8),
        const Text('CLI 작업 없음', style: TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () {
            // CLI 잡 생성 (부모의 _showCliJobDialog 호출 불가하므로 직접 표시)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('상단 CLI 버튼으로 작업을 생성하세요'), backgroundColor: Color(0xFF1B96FF)),
            );
          },
          icon: const Icon(Icons.add, size: 16, color: Color(0xFF1B96FF)),
          label: const Text('CLI 작업 생성', style: TextStyle(color: Color(0xFF1B96FF), fontSize: 12)),
        ),
      ]));
    }
    return ListView.builder(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _jobs.length,
      itemBuilder: (_, i) => _jobCard(_jobs[i]),
    );
  }

  Widget _jobCard(Map<String, dynamic> job) {
    final jobId = job['job_id']?.toString() ?? '';
    final status = job['status']?.toString() ?? '';
    final prompt = job['prompt']?.toString() ?? '';
    final model = job['model']?.toString() ?? '';
    final result = job['result_summary']?.toString() ?? '';
    final error = job['error']?.toString() ?? '';
    final isExpanded = _expandedJobId == jobId;
    final isRunning = status == 'running' || status == 'approved';

    Color sc;
    IconData si;
    switch (status) {
      case 'pending': sc = const Color(0xFFd29922); si = Icons.hourglass_empty; break;
      case 'approved': sc = const Color(0xFF1FC9E8); si = Icons.check_circle_outline; break;
      case 'running': sc = const Color(0xFF1B96FF); si = Icons.play_circle_outline; break;
      case 'completed': sc = const Color(0xFF4AC99B); si = Icons.check_circle; break;
      case 'failed': sc = const Color(0xFFf85149); si = Icons.error_outline; break;
      default: sc = const Color(0xFF8b949e); si = Icons.cancel_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0d1117), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isRunning ? sc.withOpacity(0.4) : const Color(0xFF30363d)),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _toggleExpand(jobId),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(si, size: 14, color: sc),
                const SizedBox(width: 6),
                Text(jobId, style: TextStyle(color: sc, fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                if (isRunning) ...[
                  const SizedBox(width: 8),
                  const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF1B96FF))),
                ],
                const Spacer(),
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 16, color: const Color(0xFF8b949e)),
              ]),
              const SizedBox(height: 4),
              Text(prompt, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 11, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (model.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(model, style: const TextStyle(color: Color(0xFF484f58), fontSize: 9)),
              ),
            ]),
          ),
        ),
        // 확장 영역: 로그
        if (isExpanded) Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 250),
          decoration: BoxDecoration(
            color: const Color(0xFF161b22),
            border: Border(top: BorderSide(color: const Color(0xFF30363d).withOpacity(0.5))),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 로그 헤더
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(children: [
                if (isRunning) ...[
                  const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1, color: Color(0xFF1B96FF))),
                  const SizedBox(width: 6),
                ],
                Text(isRunning ? '실시간 로그' : '실행 로그', style: TextStyle(
                  color: isRunning ? const Color(0xFF1B96FF) : const Color(0xFF8b949e), fontSize: 10, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${_liveLog.length}자', style: const TextStyle(color: Color(0xFF484f58), fontSize: 9)),
              ]),
            ),
            // 로그 본문
            Expanded(
              child: _liveLog.isEmpty && result.isEmpty && error.isEmpty
                  ? const Center(child: Text('로그 대기 중...', style: TextStyle(color: Color(0xFF484f58), fontSize: 10)))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: SelectableText(
                        _liveLog.isNotEmpty ? _liveLog : (result.isNotEmpty ? result : error),
                        style: TextStyle(
                          color: error.isNotEmpty && _liveLog.isEmpty && result.isEmpty ? const Color(0xFFf85149) : const Color(0xFF8b949e),
                          fontSize: 10, fontFamily: 'monospace', height: 1.4),
                      ),
                    ),
            ),
          ]),
        ),
      ]),
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

class _AsyncList extends StatefulWidget {
  final ScrollController scroll;
  final Future<List<dynamic>> Function() loader;
  final String emptyText;
  final Widget Function(Map<String, dynamic>) itemBuilder;
  const _AsyncList({required this.scroll, required this.loader, required this.emptyText, required this.itemBuilder});
  @override State<_AsyncList> createState() => _AsyncListState();
}

class _AsyncListState extends State<_AsyncList> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final items = await widget.loader();
    if (mounted) setState(() { _items = items.cast<Map<String, dynamic>>(); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)));
    if (_items.isEmpty) return Center(child: Text(widget.emptyText, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)));
    return ListView.builder(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _items.length,
      itemBuilder: (_, i) => widget.itemBuilder(_items[i]),
    );
  }
}
