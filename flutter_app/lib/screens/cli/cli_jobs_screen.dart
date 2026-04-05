import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../services/api_service.dart';
import '../../theme/colors.dart';

class CliJobsScreen extends StatefulWidget {
  const CliJobsScreen({super.key});
  @override
  State<CliJobsScreen> createState() => _CliJobsScreenState();
}

class _CliJobsScreenState extends State<CliJobsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _jobs = [];
  Map<String, int> _stats = {};
  bool _loading = true;
  Timer? _pollTimer;

  // 새 잡 생성
  final _promptCtrl = TextEditingController();
  String? _selectedProject;
  String _selectedModel = '';
  List<String> _projects = [];
  List<Map<String, dynamic>> _models = [];
  int _maxTurns = 30;
  int _timeoutSec = 300;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadAll();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadAll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final api = context.read<ApiService>();
    final results = await Future.wait([
      api.cliJobs(),
      api.cliStats(),
      api.getTeams(status: 'active'),
      api.cliModels(),
    ]);

    if (!mounted) return;

    final jobs = results[0] as List<Map<String, dynamic>>;
    final statsRes = results[1] as Map<String, dynamic>;
    final teams = results[2] as List<Map<String, dynamic>>;
    final models = results[3] as List<Map<String, dynamic>>;

    final statsMap = <String, int>{};
    final rawStats = statsRes['stats'] as Map<String, dynamic>? ?? {};
    for (final e in rawStats.entries) {
      statsMap[e.key] = (e.value as num?)?.toInt() ?? 0;
    }

    final projectSet = <String>{};
    for (final t in teams) {
      final pg = t['project_group']?.toString() ?? '';
      if (pg.isNotEmpty) projectSet.add(pg);
    }

    setState(() {
      _jobs = jobs;
      _stats = statsMap;
      _projects = projectSet.toList()..sort();
      _models = models;
      if (_selectedModel.isEmpty && models.isNotEmpty) {
        final def = models.where((m) => m['default'] == true);
        _selectedModel = def.isNotEmpty ? def.first['id'] as String : models.first['id'] as String;
      }
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _filtered(List<String> statuses) {
    if (statuses.isEmpty) return _jobs;
    return _jobs.where((j) => statuses.contains(j['status'])).toList();
  }

  Future<void> _createJob() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) return;

    final api = context.read<ApiService>();
    final res = await api.createCliJob({
      'prompt': prompt,
      'project_name': _selectedProject ?? '',
      'model': _selectedModel,
      'max_turns': _maxTurns,
      'timeout_sec': _timeoutSec,
      'auto_approve': false,
    });

    if (!mounted) return;

    if (res['ok'] == true) {
      _promptCtrl.clear();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('CLI 잡 생성: ${res['job_id']}'),
        backgroundColor: AppColors.success,
      ));
      _loadAll();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('실패: ${res['error'] ?? '알 수 없는 오류'}'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _approveJob(String jobId) async {
    final api = context.read<ApiService>();
    final res = await api.approveCliJob(jobId);
    if (!mounted) return;
    if (res['ok'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$jobId 승인 완료'),
        backgroundColor: AppColors.success,
      ));
      _loadAll();
    }
  }

  Future<void> _cancelJob(String jobId) async {
    final confirmed = await _confirmDialog('작업 취소', '$jobId 작업을 취소하시겠습니까?');
    if (confirmed != true) return;
    final api = context.read<ApiService>();
    await api.cancelCliJob(jobId);
    if (mounted) _loadAll();
  }

  Future<void> _killJob(String jobId) async {
    final confirmed = await _confirmDialog('실행 중단', '$jobId 실행을 강제 중단하시겠습니까?\n진행 중인 코드 변경이 불완전할 수 있습니다.');
    if (confirmed != true) return;
    final api = context.read<ApiService>();
    final res = await api.killCliJob(jobId);
    if (!mounted) return;
    if (res['ok'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('작업 중단 요청됨'),
        backgroundColor: AppColors.warning,
      ));
      _loadAll();
    }
  }

  Future<bool?> _confirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text(content, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('아니오', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
  }

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Row(children: [
                Icon(Icons.rocket_launch, size: 20, color: AppColors.brandLight),
                SizedBox(width: 8),
                Text('코딩 작업 지시', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ]),
              const SizedBox(height: 16),
              // 프로젝트 선택
              _dropdownField(
                icon: Icons.folder_outlined,
                hint: '프로젝트 선택',
                value: _selectedProject,
                items: _projects.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) { setSheetState(() => _selectedProject = v); setState(() => _selectedProject = v); },
              ),
              const SizedBox(height: 10),
              // 모델 선택
              _dropdownField(
                icon: Icons.memory,
                hint: '모델 선택',
                value: _selectedModel.isNotEmpty ? _selectedModel : null,
                items: _models.map((m) {
                  final id = m['id'] as String;
                  final name = m['name'] as String;
                  final isDefault = m['default'] == true;
                  return DropdownMenuItem(value: id,
                    child: Row(children: [
                      Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                      if (isDefault) Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(4)),
                        child: const Text('기본', style: TextStyle(fontSize: 9, color: AppColors.success)),
                      ),
                    ]),
                  );
                }).toList(),
                onChanged: (v) { setSheetState(() => _selectedModel = v ?? ''); setState(() => _selectedModel = v ?? ''); },
              ),
              const SizedBox(height: 10),
              // 설정 행: max_turns + timeout
              Row(children: [
                Expanded(child: _numberField(
                  label: 'Max Turns',
                  value: _maxTurns,
                  onChanged: (v) { setSheetState(() => _maxTurns = v); setState(() => _maxTurns = v); },
                  presets: [10, 30, 50, 100],
                )),
                const SizedBox(width: 10),
                Expanded(child: _numberField(
                  label: 'Timeout (초)',
                  value: _timeoutSec,
                  onChanged: (v) { setSheetState(() => _timeoutSec = v); setState(() => _timeoutSec = v); },
                  presets: [120, 300, 600, 1800],
                )),
              ]),
              const SizedBox(height: 12),
              // 프롬프트 입력
              TextField(
                controller: _promptCtrl,
                maxLines: 5,
                minLines: 3,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '코딩 작업을 자유롭게 지시하세요...\n\n예: "로그인 페이지에 소셜 로그인 버튼 추가해줘"',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.panel,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.brandLight)),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _createJob,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('작업 생성', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _dropdownField<T>({required IconData icon, required String hint, T? value, required List<DropdownMenuItem<T>> items, required void Function(T?) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            hint: Text(hint, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            dropdownColor: AppColors.panel,
            isExpanded: true,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            items: items,
            onChanged: onChanged,
          ),
        )),
      ]),
    );
  }

  Widget _numberField({required String label, required int value, required void Function(int) onChanged, required List<int> presets}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Wrap(spacing: 4, children: presets.map((p) => GestureDetector(
        onTap: () => onChanged(p),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: value == p ? AppColors.brandLight.withOpacity(0.2) : AppColors.panel,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: value == p ? AppColors.brandLight : AppColors.border),
          ),
          child: Text('$p', style: TextStyle(
            fontSize: 11, color: value == p ? AppColors.brandLight : AppColors.textSecondary,
            fontWeight: value == p ? FontWeight.w600 : FontWeight.normal,
          )),
        ),
      )).toList()),
    ]);
  }

  void _showJobDetail(Map<String, dynamic> job) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _JobDetailScreen(job: job),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pending = _filtered(['pending']);
    final running = _filtered(['approved', 'running']);
    final done = _filtered(['completed']);
    final failed = _filtered(['failed', 'cancelled']);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundElevated,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Row(children: [
          Icon(Icons.terminal, size: 20, color: AppColors.brandLight),
          SizedBox(width: 8),
          Text('CLI 작업', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20),
            onPressed: () { setState(() => _loading = true); _loadAll(); }),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.brandLight,
          labelColor: AppColors.brandLight,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: '대기 (${pending.length})'),
            Tab(text: '실행 (${running.length})'),
            Tab(text: '완료 (${done.length})'),
            Tab(text: '실패 (${failed.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(children: [
              _statsBar(),
              Expanded(
                child: TabBarView(controller: _tabCtrl, children: [
                  _jobList(pending, emptyMsg: '대기 중인 작업이 없습니다'),
                  _jobList(running, emptyMsg: '실행 중인 작업이 없습니다'),
                  _jobList(done, emptyMsg: '완료된 작업이 없습니다'),
                  _jobList(failed, emptyMsg: '실패한 작업이 없습니다'),
                ]),
              ),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        backgroundColor: AppColors.brandLight,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('코딩 작업', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _statsBar() {
    final total = _stats.values.fold(0, (a, b) => a + b);
    final completed = _stats['completed'] ?? 0;
    final running = (_stats['approved'] ?? 0) + (_stats['running'] ?? 0);
    final pending = _stats['pending'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.backgroundElevated,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(children: [
        _statChip('전체', total, AppColors.textSecondary),
        _statChip('대기', pending, AppColors.warning),
        _statChip('실행', running, AppColors.brandLight),
        _statChip('완료', completed, AppColors.success),
      ]),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Expanded(
      child: Column(children: [
        Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _jobList(List<Map<String, dynamic>> jobs, {required String emptyMsg}) {
    if (jobs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_outlined, size: 48, color: AppColors.textMuted.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text(emptyMsg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: jobs.length,
        itemBuilder: (ctx, i) => _jobCard(jobs[i]),
      ),
    );
  }

  Widget _jobCard(Map<String, dynamic> job) {
    final status = job['status']?.toString() ?? '';
    final prompt = job['prompt']?.toString() ?? '';
    final jobId = job['job_id']?.toString() ?? '';
    final project = job['project_name']?.toString() ?? '';
    final model = job['model']?.toString() ?? '';
    final ticketId = job['ticket_id']?.toString() ?? '';
    final createdAt = job['created_at']?.toString() ?? '';

    return Card(
      color: AppColors.backgroundElevated,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: status == 'running' ? AppColors.brandLight.withOpacity(0.4) : AppColors.border,
          width: status == 'running' ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showJobDetail(job),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _statusIcon(status),
              const SizedBox(width: 8),
              Text(jobId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontFamily: 'monospace')),
              const Spacer(),
              if (createdAt.isNotEmpty) Text(_formatTime(createdAt), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ]),
            const SizedBox(height: 8),
            Text(prompt, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(children: [
              if (project.isNotEmpty) ...[
                const Icon(Icons.folder_outlined, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(project, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                const SizedBox(width: 10),
              ],
              if (model.isNotEmpty) ...[
                const Icon(Icons.memory, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Flexible(child: Text(_shortModel(model), style: const TextStyle(fontSize: 11, color: AppColors.textMuted), overflow: TextOverflow.ellipsis)),
              ],
              const Spacer(),
              if (status == 'pending')
                _actionButton('승인', AppColors.success, () => _approveJob(jobId)),
              if (status == 'pending' || status == 'approved')
                Padding(padding: const EdgeInsets.only(left: 6), child: _actionButton('취소', AppColors.error, () => _cancelJob(jobId))),
              if (status == 'running')
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _actionButton('중단', AppColors.error, () => _killJob(jobId)),
                  const SizedBox(width: 8),
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.brandLight)),
                  const SizedBox(width: 6),
                  const Text('실행 중', style: TextStyle(fontSize: 11, color: AppColors.brandLight)),
                ]),
            ]),
          ]),
        ),
      ),
    );
  }

  String _shortModel(String model) {
    if (model.contains('sonnet')) return 'Sonnet 4';
    if (model.contains('opus')) return 'Opus 4.6';
    if (model.contains('haiku')) return 'Haiku 4.5';
    if (model.startsWith('ollama:')) return model.substring(7);
    return model;
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      return timeago.format(DateTime.parse(iso), locale: 'ko');
    } catch (_) {
      return iso;
    }
  }

  Widget _statusIcon(String status, {double size = 16}) {
    IconData icon;
    Color color;
    switch (status) {
      case 'pending': icon = Icons.hourglass_empty; color = AppColors.warning; break;
      case 'approved': icon = Icons.check_circle_outline; color = AppColors.info; break;
      case 'running': icon = Icons.play_circle_outline; color = AppColors.brandLight; break;
      case 'completed': icon = Icons.check_circle; color = AppColors.success; break;
      case 'failed': icon = Icons.error_outline; color = AppColors.error; break;
      case 'cancelled': icon = Icons.cancel_outlined; color = AppColors.textMuted; break;
      default: icon = Icons.circle_outlined; color = AppColors.textSecondary;
    }
    return Icon(icon, size: size, color: color);
  }
}

// ── 잡 상세 화면 (실시간 로그 포함) ──
class _JobDetailScreen extends StatefulWidget {
  final Map<String, dynamic> job;
  const _JobDetailScreen({required this.job});
  @override
  State<_JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<_JobDetailScreen> {
  late Map<String, dynamic> _job;
  String _liveLog = '';
  Timer? _logTimer;
  final _logScroll = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _job = Map.from(widget.job);
    _liveLog = _job['live_log']?.toString() ?? '';
    // running 상태면 로그 폴링 시작
    if (_job['status'] == 'running' || _job['status'] == 'approved') {
      _startLogPolling();
    }
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  void _startLogPolling() {
    _logTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLog());
  }

  Future<void> _fetchLog() async {
    final api = context.read<ApiService>();
    final res = await api.cliJobLog(_job['job_id'] as String);
    if (!mounted) return;
    setState(() {
      _liveLog = res['log']?.toString() ?? _liveLog;
      final newStatus = res['status']?.toString() ?? _job['status'];
      if (newStatus != _job['status']) {
        _job['status'] = newStatus;
        if (newStatus != 'running' && newStatus != 'approved') {
          _logTimer?.cancel();
          _refreshJob();
        }
      }
    });
    if (_autoScroll && _logScroll.hasClients) {
      _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    }
  }

  Future<void> _refreshJob() async {
    final api = context.read<ApiService>();
    final jobs = await api.cliJobs();
    if (!mounted) return;
    final updated = jobs.where((j) => j['job_id'] == _job['job_id']);
    if (updated.isNotEmpty) {
      setState(() => _job = Map.from(updated.first));
    }
  }

  Future<void> _killJob() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
        title: const Text('실행 중단', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: const Text('실행을 강제 중단하시겠습니까?', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니오', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('중단', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    final api = context.read<ApiService>();
    await api.killCliJob(_job['job_id'] as String);
    if (mounted) _refreshJob();
  }

  Future<void> _approveJob() async {
    final api = context.read<ApiService>();
    final res = await api.approveCliJob(_job['job_id'] as String);
    if (!mounted) return;
    if (res['ok'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('승인 완료'), backgroundColor: AppColors.success));
      _refreshJob();
      _startLogPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _job['status']?.toString() ?? '';
    final prompt = _job['prompt']?.toString() ?? '';
    final jobId = _job['job_id']?.toString() ?? '';
    final result = _job['result_summary']?.toString() ?? '';
    final error = _job['error']?.toString() ?? '';
    final project = _job['project_name']?.toString() ?? _job['project_path']?.toString() ?? '';
    final model = _job['model']?.toString() ?? '';
    final ticketId = _job['ticket_id']?.toString() ?? '';
    final createdAt = _job['created_at']?.toString() ?? '';
    final completedAt = _job['completed_at']?.toString() ?? '';
    final workerId = _job['worker_id']?.toString() ?? '';
    final isRunning = status == 'running' || status == 'approved';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundElevated,
        elevation: 0,
        title: Row(children: [
          _statusIconWidget(status, size: 20),
          const SizedBox(width: 8),
          Text(jobId, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
        ]),
        actions: [
          if (status == 'pending')
            TextButton.icon(
              onPressed: _approveJob,
              icon: const Icon(Icons.check, size: 18, color: AppColors.success),
              label: const Text('승인', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
            ),
          if (isRunning)
            TextButton.icon(
              onPressed: _killJob,
              icon: const Icon(Icons.stop, size: 18, color: AppColors.error),
              label: const Text('중단', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // 메타 정보
        _infoCard([
          _infoRow('상태', _statusLabel(status), _statusColor(status)),
          if (project.isNotEmpty) _infoRow('프로젝트', project, null),
          if (model.isNotEmpty) _infoRow('모델', model, null),
          if (ticketId.isNotEmpty) _infoRow('티켓', ticketId, null),
          if (workerId.isNotEmpty) _infoRow('워커', workerId, null),
          if (createdAt.isNotEmpty) _infoRow('생성', _formatTime(createdAt), null),
          if (completedAt.isNotEmpty) _infoRow('완료', _formatTime(completedAt), null),
        ]),
        const SizedBox(height: 12),
        // 프롬프트
        _section('작업 내용', Icons.code, prompt),
        const SizedBox(height: 12),
        // 실시간 로그 (running 시)
        if (isRunning || _liveLog.isNotEmpty) ...[
          _logSection(isRunning),
          const SizedBox(height: 12),
        ],
        // 결과
        if (result.isNotEmpty)
          _section('실행 결과', Icons.terminal, result, mono: true),
        if (error.isNotEmpty) ...[
          const SizedBox(height: 12),
          _section('오류', Icons.error_outline, error, mono: true, color: AppColors.error),
        ],
      ]),
    );
  }

  Widget _infoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }

  Widget _infoRow(String label, String value, Color? valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: valueColor ?? AppColors.textPrimary))),
      ]),
    );
  }

  Widget _section(String title, IconData icon, String content, {bool mono = false, Color? color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color ?? AppColors.textSecondary)),
        ]),
        const SizedBox(height: 8),
        SelectableText(content, style: TextStyle(
          fontSize: 13, height: 1.6, color: color ?? AppColors.textPrimary,
          fontFamily: mono ? 'monospace' : null,
        )),
      ]),
    );
  }

  Widget _logSection(bool isLive) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0d1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isLive ? AppColors.brandLight.withOpacity(0.3) : AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.backgroundElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
          ),
          child: Row(children: [
            if (isLive) ...[
              const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.brandLight)),
              const SizedBox(width: 8),
            ],
            Icon(Icons.terminal, size: 14, color: isLive ? AppColors.brandLight : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(isLive ? '실시간 로그' : '실행 로그',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isLive ? AppColors.brandLight : AppColors.textSecondary)),
            const Spacer(),
            if (isLive) GestureDetector(
              onTap: () => setState(() => _autoScroll = !_autoScroll),
              child: Row(children: [
                Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.pause, size: 14,
                    color: _autoScroll ? AppColors.success : AppColors.textMuted),
                const SizedBox(width: 4),
                Text(_autoScroll ? '자동 스크롤' : '일시정지',
                    style: TextStyle(fontSize: 10, color: _autoScroll ? AppColors.success : AppColors.textMuted)),
              ]),
            ),
          ]),
        ),
        SizedBox(
          height: 250,
          child: _liveLog.isEmpty
              ? const Center(child: Text('로그 대기 중...', style: TextStyle(color: AppColors.textMuted, fontSize: 12)))
              : SingleChildScrollView(
                  controller: _logScroll,
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _liveLog,
                    style: const TextStyle(fontSize: 11, height: 1.5, color: AppColors.textPrimary, fontFamily: 'monospace'),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _statusIconWidget(String status, {double size = 16}) {
    IconData icon;
    Color color;
    switch (status) {
      case 'pending': icon = Icons.hourglass_empty; color = AppColors.warning; break;
      case 'approved': icon = Icons.check_circle_outline; color = AppColors.info; break;
      case 'running': icon = Icons.play_circle_outline; color = AppColors.brandLight; break;
      case 'completed': icon = Icons.check_circle; color = AppColors.success; break;
      case 'failed': icon = Icons.error_outline; color = AppColors.error; break;
      case 'cancelled': icon = Icons.cancel_outlined; color = AppColors.textMuted; break;
      default: icon = Icons.circle_outlined; color = AppColors.textSecondary;
    }
    return Icon(icon, size: size, color: color);
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending': return '승인 대기';
      case 'approved': return '워커 대기';
      case 'running': return '실행 중';
      case 'completed': return '완료';
      case 'failed': return '실패';
      case 'cancelled': return '취소됨';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return AppColors.warning;
      case 'approved': return AppColors.info;
      case 'running': return AppColors.brandLight;
      case 'completed': return AppColors.success;
      case 'failed': return AppColors.error;
      case 'cancelled': return AppColors.textMuted;
      default: return AppColors.textSecondary;
    }
  }

  String _formatTime(String iso) {
    try {
      return timeago.format(DateTime.parse(iso), locale: 'ko');
    } catch (_) {
      return iso;
    }
  }
}
