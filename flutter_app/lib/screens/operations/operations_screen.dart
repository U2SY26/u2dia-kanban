import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import 'competition_detail_screen.dart';
import '../cli/cli_mirror_screen.dart';

// ── Colors ──
const _kBg = Color(0xFF0d1117);
const _kCard = Color(0xFF161b22);
const _kPanel = Color(0xFF21262d);
const _kBorder = Color(0xFF30363d);
const _kText = Color(0xFFe6edf3);
const _kTextSec = Color(0xFF8b949e);
const _kTextMuted = Color(0xFF5e6c84);
const _kAccent = Color(0xFF1B96FF);
const _kGreen = Color(0xFF4AC99B);
const _kRed = Color(0xFFf85149);
const _kOrange = Color(0xFFd29922);
const _kWarning = Color(0xFFFE9339);
const _kPurple = Color(0xFF8B5CF6);
const _kCyan = Color(0xFF1FC9E8);

class OperationsScreen extends StatefulWidget {
  final int initialTabIndex;
  const OperationsScreen({super.key, this.initialTabIndex = 0});
  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // ── Tab 1: Competitions ──
  List<Map<String, dynamic>> _competitions = [];
  List<Map<String, dynamic>> _lambdaRunning = [];
  double _lambdaTotalLiveSpend = 0;
  double _lambdaMonthTotal = 0;
  bool _loadingCompetitions = true;
  Timer? _competitionsTimer;

  // ── Tab 2: CLI / Fleet ──
  List<Map<String, dynamic>> _fleet = [];
  List<Map<String, dynamic>> _jobs = [];
  Map<String, int> _cliStats = {};
  bool _loadingCli = true;
  Timer? _cliTimer;

  // ── CLI Exec (명령 실행) ──
  final _cliCmdCtrl = TextEditingController();
  final _cliScrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _cliHistory = [];
  final Set<int> _cliHistoryServerIds = {};
  bool _cliExecRunning = false;
  bool _cliHistoryLoaded = false;

  // ── Tab 3: Resources ──
  Map<String, dynamic> _metrics = {};
  Map<String, dynamic> _gpu = {};
  bool _loadingResources = true;
  Timer? _resourcesTimer;

  // ── Tab 4: Hooks & Sessions ──
  Map<String, dynamic> _hookStats = {};
  List<Map<String, dynamic>> _hookEvents = [];
  Map<String, dynamic> _sessionStats = {};
  List<Map<String, dynamic>> _activeSessions = [];
  bool _loadingHooks = true;
  Timer? _hooksTimer;
  int _hooksRangeHours = 24; // 24 또는 168 (7d)

  // ── Tab 5: Settings ──
  String _supervisorModel = '';
  List<Map<String, dynamic>> _supervisorModels = [];
  bool _savingModel = false;
  Map<String, dynamic>? _healthResult;
  bool _checkingHealth = false;
  Map<String, bool> _notifPrefs = {};
  List<Map<String, dynamic>> _notifCategories = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 4),
    );
    _tabCtrl.addListener(_onTabChanged);
    _loadCompetitions();
    _loadCli();
    _loadResources();
    _loadHooks();
    _loadSettings();
    _competitionsTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadCompetitions());
    _cliTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _loadCli());
    _resourcesTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadResources());
    _hooksTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadHooks());
  }

  @override
  void dispose() {
    _competitionsTimer?.cancel();
    _cliTimer?.cancel();
    _resourcesTimer?.cancel();
    _hooksTimer?.cancel();
    _cliCmdCtrl.dispose();
    _cliScrollCtrl.dispose();
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabCtrl.indexIsChanging) setState(() {});
  }

  // ════════════════════════════════════════════════════════════
  // Data loading
  // ════════════════════════════════════════════════════════════

  Future<void> _loadCompetitions() async {
    final api = context.read<ApiService>();
    // 개별 호출 — 하나 실패해도 나머지 데이터 유지
    Map<String, dynamic> comps = {};
    Map<String, dynamic> running = {};
    Map<String, dynamic> costs = {};
    try { comps = await api.get('/api/competitions'); } catch (_) {}
    try { running = await api.get('/api/competitions/lambda-running'); } catch (_) {}
    try { costs = await api.get('/api/competitions/lambda-costs?month=${_currentMonth()}'); } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (comps['ok'] == true) {
        _competitions = ((comps['competitions'] as List?) ?? []).cast<Map<String, dynamic>>();
      }
      if (running['ok'] == true) {
        _lambdaRunning = ((running['running_instances'] as List?) ?? []).cast<Map<String, dynamic>>();
        _lambdaTotalLiveSpend = (running['total_live_spend'] as num?)?.toDouble() ?? 0;
      }
      if (costs['ok'] == true) {
        _lambdaMonthTotal = (costs['total'] as num?)?.toDouble() ?? 0;
      }
      _loadingCompetitions = false;
    });
  }

  String _currentMonth() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _loadCli() async {
    final api = context.read<ApiService>();
    try {
      final results = await Future.wait([
        api.fleetStatus(),
        api.cliJobs(),
        api.cliStats(),
        api.cliExecHistory(limit: 50),
      ]);
      if (!mounted) return;
      final fleetData = results[0] as Map<String, dynamic>;
      final jobsData = results[1] as List<Map<String, dynamic>>;
      final statsData = results[2] as Map<String, dynamic>;
      final execHistory = results[3] as List<Map<String, dynamic>>;

      final statsMap = <String, int>{};
      final raw = statsData['stats'] as Map<String, dynamic>? ?? {};
      for (final e in raw.entries) {
        statsMap[e.key] = (e.value as num?)?.toInt() ?? 0;
      }

      // 서버 히스토리 머지 — id 기준 중복 방지
      final List<Map<String, dynamic>> newServerEntries = [];
      // 서버는 DESC로 주므로 오래된 것이 먼저 표시되도록 역순 추가
      for (final h in execHistory.reversed) {
        final id = (h['id'] as num?)?.toInt();
        if (id == null || _cliHistoryServerIds.contains(id)) continue;
        _cliHistoryServerIds.add(id);
        final command = (h['command'] ?? '').toString();
        final resultText = (h['result'] ?? '').toString();
        final ok = h['ok'] == true;
        final createdAt = (h['created_at'] ?? '').toString();
        newServerEntries.add({
          'type': 'input',
          'text': command,
          'time': createdAt,
          'server_id': id,
        });
        if (resultText.isNotEmpty) {
          newServerEntries.add({
            'type': ok ? 'output' : 'error',
            'text': resultText,
            'time': createdAt,
            'server_id': id,
          });
        }
      }

      setState(() {
        _fleet = ((fleetData['fleet'] as List?) ?? [])
            .cast<Map<String, dynamic>>();
        _jobs = jobsData;
        _cliStats = statsMap;
        _loadingCli = false;
        if (newServerEntries.isNotEmpty) {
          if (!_cliHistoryLoaded) {
            // 최초 로드 시 서버 히스토리를 앞에 삽입
            _cliHistory.insertAll(0, newServerEntries);
          } else {
            // 이후 폴링 시 새 항목만 뒤에 추가
            _cliHistory.addAll(newServerEntries);
          }
          _cliHistoryLoaded = true;
        } else {
          _cliHistoryLoaded = true;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCli = false);
    }
  }

  Future<void> _loadResources() async {
    final api = context.read<ApiService>();
    // 개별 호출 — 하나 실패해도 나머지 데이터 유지
    Map<String, dynamic> metricsRes = {};
    Map<String, dynamic> gpuRes = {};
    try { metricsRes = await api.getMetrics(); } catch (_) {}
    try { gpuRes = await api.get('/api/system/gpu'); } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (metricsRes['ok'] == true) {
        _metrics = (metricsRes['metrics'] as Map<String, dynamic>?) ?? {};
      }
      if (gpuRes['ok'] == true) {
        _gpu = gpuRes;
      }
      _loadingResources = false;
    });
  }

  Future<void> _loadSettings() async {
    final api = context.read<ApiService>();
    try {
      final results = await Future.wait([
        api.getSupervisorModel(),
        api.getNotifPrefs(),
      ]);
      if (!mounted) return;
      final notifRes = results[1];
      final prefs = (notifRes['prefs'] as Map<String, dynamic>?) ?? {};
      final cats = ((notifRes['categories'] as List?) ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _supervisorModel = results[0]['current'] as String? ?? '';
        _supervisorModels = ((results[0]['models'] as List?) ?? [])
            .cast<Map<String, dynamic>>();
        _notifPrefs = prefs.map((k, v) => MapEntry(k, v == true));
        _notifCategories = cats;
      });
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════
  // Build
  // ════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        title: const Text(
          '운영',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _kText),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: _kTextSec),
            tooltip: '새로고침',
            onPressed: _refreshCurrentTab,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _kAccent,
          indicatorWeight: 2.5,
          labelColor: _kAccent,
          unselectedLabelColor: _kTextSec,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: '대회'),
            Tab(text: 'tmux'),
            Tab(text: '자원'),
            Tab(text: 'Hooks'),
            Tab(text: '설정'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildCompetitionsTab(),
          _buildCliTab(),
          _buildResourcesTab(),
          _buildHooksTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

  void _refreshCurrentTab() {
    switch (_tabCtrl.index) {
      case 0:
        setState(() => _loadingCompetitions = true);
        _loadCompetitions();
        break;
      case 1:
        setState(() => _loadingCli = true);
        _loadCli();
        break;
      case 2:
        setState(() => _loadingResources = true);
        _loadResources();
        break;
      case 3:
        setState(() => _loadingHooks = true);
        _loadHooks();
        break;
      case 4:
        _loadSettings();
        break;
    }
  }

  // ════════════════════════════════════════════════════════════
  // TAB 1 : Competitions
  // ════════════════════════════════════════════════════════════

  String? _expandedComp;
  bool _shutdownRunning = false;

  String _fmtCost(double cost) {
    if (cost >= 1000) return '\$${(cost / 1000).toStringAsFixed(1)}K';
    if (cost >= 1) return '\$${cost.toStringAsFixed(0)}';
    if (cost > 0) return '\$${cost.toStringAsFixed(2)}';
    return '\$0';
  }

  Future<void> _confirmShutdown(String target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('GPU Shutdown', style: TextStyle(color: _kRed, fontWeight: FontWeight.w700)),
        content: Text(
          target == 'all'
              ? '모든 대회의 Lambda GPU를 종료합니다.\n비용 청구가 중단됩니다.'
              : '$target의 GPU를 종료합니다.',
          style: const TextStyle(color: _kText, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('종료', style: TextStyle(color: _kRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _shutdownRunning = true);
    try {
      final api = context.read<ApiService>();
      final res = await api.competitionShutdown(target: target, reason: 'app shutdown');
      if (!mounted) return;
      final results = (res['results'] as List?) ?? [];
      final msg = results.map((r) => '${r['name']}: ${r['ok'] == true ? 'OK' : r['error']}').join('\n');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 11)),
        backgroundColor: _kPanel,
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Shutdown failed: $e', style: const TextStyle(fontSize: 11)),
          backgroundColor: _kRed,
        ));
      }
    }
    if (mounted) setState(() => _shutdownRunning = false);
  }

  Widget _buildCompetitionsTab() {
    if (_loadingCompetitions && _competitions.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent));
    }

    if (_competitions.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCompetitions,
        color: _kAccent,
        backgroundColor: _kCard,
        child: ListView(children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.emoji_events_outlined, size: 48, color: _kTextMuted),
                SizedBox(height: 12),
                Text('등록된 대회 없음', style: TextStyle(color: _kTextSec, fontSize: 14)),
              ]),
            ),
          ),
        ]),
      );
    }

    // 전체 비용 합산 — lambda_cost 기준 (이전 total_cost는 항상 0이었음)
    // 월별 총합은 서버의 _lambdaMonthTotal을 사용 (정확한 집계)
    final totalCostAll = _lambdaMonthTotal > 0 ? _lambdaMonthTotal : () {
      double sum = 0;
      for (final c in _competitions) {
        sum += (c['lambda_cost'] as num?)?.toDouble() ?? 0;
      }
      return sum;
    }();
    final totalGpus = _lambdaRunning.length;
    final totalLiveSpend = _lambdaTotalLiveSpend;
    int totalLiveTickets = 0;
    for (final c in _competitions) {
      totalLiveTickets += ((c['live_tickets'] as List?) ?? []).length;
    }

    return RefreshIndicator(
      onRefresh: _loadCompetitions,
      color: _kAccent,
      backgroundColor: _kCard,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ── 비용 요약 헤더 ──
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  totalCostAll > 1000 ? _kRed.withValues(alpha: 0.15) : _kAccent.withValues(alpha: 0.1),
                  _kCard,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: totalCostAll > 1000 ? _kRed.withValues(alpha: 0.4) : _kBorder),
            ),
            child: Column(children: [
              Row(children: [
                Icon(Icons.attach_money, size: 18, color: totalCostAll > 1000 ? _kRed : _kGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Lambda GPU Cost',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: totalCostAll > 1000 ? _kRed : _kTextSec,
                    ),
                  ),
                ),
                if (_shutdownRunning)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _kRed))
                else
                  GestureDetector(
                    onTap: () => _confirmShutdown('all'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _kRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kRed.withValues(alpha: 0.5)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.power_settings_new, size: 13, color: _kRed),
                        SizedBox(width: 4),
                        Text('ALL STOP', style: TextStyle(fontSize: 10, color: _kRed, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _fmtCost(totalCostAll),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: totalCostAll > 1000 ? _kRed : _kGreen,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text('${_currentMonth()} 총액', style: const TextStyle(fontSize: 10, color: _kTextMuted)),
                  ]),
                ),
                _costMetric(Icons.memory, '$totalGpus', 'Running', totalGpus > 0 ? _kGreen : _kTextMuted),
                const SizedBox(width: 12),
                _costMetric(Icons.bolt, '\$${totalLiveSpend.toStringAsFixed(0)}', 'Live', _kWarning),
              ]),
              // ── Running 인스턴스 인라인 리스트 ──
              if (_lambdaRunning.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(color: _kBorder, height: 1),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.circle, size: 8, color: _kGreen),
                  const SizedBox(width: 6),
                  Text('${_lambdaRunning.length}개 인스턴스 실행 중',
                      style: const TextStyle(fontSize: 11, color: _kGreen, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                ..._lambdaRunning.map((inst) {
                  final liveSpend = (inst['live_spend'] as num?)?.toDouble() ?? 0;
                  final liveDur = (inst['live_duration_hours'] as num?)?.toDouble() ?? 0;
                  final rate = (inst['rate_per_hour'] as num?)?.toDouble() ?? 0;
                  final name = inst['instance_name']?.toString() ?? '';
                  final gpu = inst['gpu_type']?.toString() ?? '';
                  final region = inst['region']?.toString() ?? '';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kBg.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Expanded(flex: 2, child: Text(name,
                          style: const TextStyle(color: _kText, fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 2, child: Text(gpu,
                          style: const TextStyle(color: _kCyan, fontSize: 10, fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis)),
                      Expanded(child: Text('${liveDur.toStringAsFixed(1)}h',
                          style: const TextStyle(color: _kTextSec, fontSize: 11, fontFamily: 'monospace'),
                          textAlign: TextAlign.right)),
                      Expanded(child: Text('\$${liveSpend.toStringAsFixed(2)}',
                          style: TextStyle(color: liveSpend > 50 ? _kRed : _kWarning, fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                          textAlign: TextAlign.right)),
                    ]),
                  );
                }),
              ],
            ]),
          ),

          // ── 대회별 카드 ──
          ..._competitions.map((c) => _competitionCard(c)),
        ],
      ),
    );
  }

  Widget _costMetric(IconData icon, String value, String label, Color color) {
    return Column(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color, fontFamily: 'monospace')),
      Text(label, style: const TextStyle(fontSize: 9, color: _kTextMuted)),
    ]);
  }

  Widget _competitionCard(Map<String, dynamic> c) {
    final name = c['name']?.toString() ?? 'Untitled';
    final title = c['title']?.toString().trim().isNotEmpty == true ? c['title'].toString() : name;
    final writeupUrl = c['writeup_url']?.toString() ?? '';
    final submissionStatus = c['submission_status']?.toString() ?? 'in_progress';
    final track = c['track']?.toString() ?? '';
    final status = c['status']?.toString() ?? 'idle';
    final progress = (c['progress'] as num?)?.toDouble() ?? 0;
    final stats = (c['ticket_stats'] as Map<String, dynamic>?) ?? {};
    final totalTickets = (stats['total'] as num?)?.toInt() ?? 0;
    final doneTickets = (stats['done'] as num?)?.toInt() ?? 0;
    final inProgress = (stats['in_progress'] as num?)?.toInt() ?? 0;
    final blocked = (stats['blocked'] as num?)?.toInt() ?? 0;
    final lastActivity = c['last_activity']?.toString() ?? '';
    final deadline = c['deadline']?.toString() ?? '';
    final totalCost = (c['total_cost'] as num?)?.toDouble() ?? 0;
    final lambdaCost = (c['lambda_cost'] as num?)?.toDouble() ?? 0;
    final lambdaInstances = (c['lambda_instances'] as num?)?.toInt() ?? 0;
    final activeGpus = (c['active_gpus'] as num?)?.toInt() ?? 0;
    final teams = ((c['teams'] as List?) ?? []).cast<Map<String, dynamic>>();
    final liveTickets = ((c['live_tickets'] as List?) ?? []).cast<Map<String, dynamic>>();
    final activeTeamCount = (c['active_team_count'] as num?)?.toInt() ?? teams.where((t) => t['archived'] != true).length;
    final archivedTeamCount = (c['archived_team_count'] as num?)?.toInt() ?? teams.where((t) => t['archived'] == true).length;

    final isActive = status == 'active';
    final isExpanded = _expandedComp == name;
    final hasCost = totalCost > 0;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CompetitionDetailScreen(competition: c, summary: c),
      )),
      onLongPress: () => setState(() => _expandedComp = isExpanded ? null : name),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasCost ? _kWarning.withValues(alpha: 0.4) : isActive ? _kGreen.withValues(alpha: 0.3) : _kBorder,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _kText),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (title != name)
                  Text(name,
                      style: const TextStyle(fontSize: 10, color: _kTextMuted, fontFamily: 'monospace')),
              ]),
            ),
            if (hasCost) ...[
              Text(_fmtCost(totalCost),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: totalCost > 1000 ? _kRed : _kOrange,
                    fontFamily: 'monospace',
                  )),
              const SizedBox(width: 6),
            ],
            if (submissionStatus == 'writeup_posted') ...[
              _badge('WRITEUP', _kPurple),
              const SizedBox(width: 4),
            ],
            _badge(status.toUpperCase(), isActive ? _kGreen : _kTextMuted),
          ]),
          const SizedBox(height: 8),

          // GPU + Teams + Deadline row
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (lambdaCost > 0)
              _statChip(Icons.cloud, '\$${lambdaCost.toStringAsFixed(2)}', lambdaCost > 100 ? _kRed : _kOrange),
            if (lambdaInstances > 0)
              _statChip(Icons.dns, '$lambdaInstances runs', _kCyan),
            if (activeGpus > 0)
              _statChip(Icons.memory, '$activeGpus GPU', _kCyan),
            _statChip(Icons.groups_outlined, '$activeTeamCount${archivedTeamCount > 0 ? "+$archivedTeamCount" : ""}', _kPurple),
            _statChip(Icons.check_circle_outline, '$doneTickets/$totalTickets', _kGreen),
            if (inProgress > 0) _statChip(Icons.play_circle_outline, '$inProgress', _kAccent),
            if (blocked > 0) _statChip(Icons.block, '$blocked', _kRed),
            if (deadline.isNotEmpty) _statChip(Icons.event, deadline, _kOrange),
            if (track.isNotEmpty) _statChip(Icons.label_outline, track, _kCyan),
            if (writeupUrl.isNotEmpty)
              GestureDetector(
                onTap: () => _openUrl(writeupUrl),
                child: _statChip(Icons.description_outlined, 'Writeup', _kPurple),
              ),
          ]),

          // Progress bar
          if (totalTickets > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (progress / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: _kPanel,
                    valueColor: AlwaysStoppedAnimation(progress >= 100 ? _kGreen : _kAccent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${progress.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kAccent)),
            ]),
          ],

          // ── 라이브 티켓 (비용/GPU 보고) ──
          if (liveTickets.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: _kWarning, letterSpacing: 1)),
            const SizedBox(height: 4),
            ...liveTickets.map((t) => _liveTicketRow(t)),
          ],

          // ── 확장: 팀별 상세 ──
          if (isExpanded && teams.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: _kBorder, height: 1),
            const SizedBox(height: 8),
            // 활성 팀 먼저
            ...teams.where((t) => t['archived'] != true).map((team) => _teamSection(team)),
            // 아카이브 팀 요약
            if (archivedTeamCount > 0) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: _kPanel, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  const Icon(Icons.archive_outlined, size: 12, color: _kTextMuted),
                  const SizedBox(width: 6),
                  Text('아카이브 $archivedTeamCount팀',
                      style: const TextStyle(fontSize: 10, color: _kTextMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  ...teams.where((t) => t['archived'] == true).take(3).map((t) {
                    final ts = (t['ticket_stats'] as Map<String, dynamic>?) ?? {};
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('${(ts['total'] ?? 0)}tix', style: const TextStyle(fontSize: 9, color: _kTextMuted, fontFamily: 'monospace')),
                    );
                  }),
                ]),
              ),
            ],

            // 개별 셧다운
            if (hasCost) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _confirmShutdown(name),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _kRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kRed.withValues(alpha: 0.3)),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.power_settings_new, size: 14, color: _kRed),
                    SizedBox(width: 6),
                    Text('STOP THIS GPU', style: TextStyle(fontSize: 11, color: _kRed, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ],
          ],

          // Footer
          if (lastActivity.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.access_time, size: 10, color: _kTextMuted),
              const SizedBox(width: 3),
              Expanded(
                child: Text(_formatTimestamp(lastActivity),
                    style: const TextStyle(fontSize: 9, color: _kTextMuted), overflow: TextOverflow.ellipsis),
              ),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 16, color: _kTextSec),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _liveTicketRow(Map<String, dynamic> t) {
    final title = t['title']?.toString() ?? '';
    final note = t['progress_note']?.toString() ?? '';
    final status = t['status']?.toString() ?? '';
    final cost = (t['cost'] as num?)?.toDouble();
    final gpuInfo = t['gpu_info'] as Map<String, dynamic>?;
    final isBlocked = status == 'Blocked';

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isBlocked ? _kRed.withValues(alpha: 0.3) : _kAccent.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isBlocked ? Icons.block : Icons.play_circle_filled, size: 12, color: isBlocked ? _kRed : _kAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kText),
                overflow: TextOverflow.ellipsis),
          ),
          if (cost != null && cost > 0)
            Text(_fmtCost(cost),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cost > 1000 ? _kRed : _kOrange,
                  fontFamily: 'monospace',
                )),
        ]),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(note, style: const TextStyle(fontSize: 10, color: _kCyan, fontFamily: 'monospace'), maxLines: 2),
        ],
        if (gpuInfo != null) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 8, children: [
            if (gpuInfo['memory_mib'] != null)
              _statChip(Icons.memory, '${(gpuInfo['memory_mib'] / 1024).toStringAsFixed(0)}GB', _kCyan),
            if (gpuInfo['util_pct'] != null)
              _statChip(Icons.speed, '${gpuInfo['util_pct']}%', _kGreen),
            if (gpuInfo['procs'] != null)
              _statChip(Icons.dns, '${gpuInfo['procs']} proc', _kPurple),
            if (gpuInfo['hours'] != null)
              _statChip(Icons.timer, '${gpuInfo['hours']}h', _kWarning),
          ]),
        ],
      ]),
    );
  }

  Widget _teamSection(Map<String, dynamic> team) {
    final name = team['name']?.toString() ?? '';
    final members = ((team['members'] as List?) ?? []).cast<Map<String, dynamic>>();
    final teamCost = (team['cost'] as num?)?.toDouble() ?? 0;
    final ts = (team['ticket_stats'] as Map<String, dynamic>?) ?? {};

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.view_kanban, size: 12, color: _kAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kText),
                overflow: TextOverflow.ellipsis),
          ),
          if (teamCost > 0) Text(_fmtCost(teamCost),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _kOrange, fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: [
          _statChip(Icons.person, '${members.length}', _kPurple),
          _statChip(Icons.assignment, '${ts['total'] ?? 0}', _kTextSec),
          if ((ts['in_progress'] as num?)?.toInt() != null && (ts['in_progress'] as num).toInt() > 0)
            _statChip(Icons.play_circle, '${ts['in_progress']}', _kAccent),
          if ((ts['blocked'] as num?)?.toInt() != null && (ts['blocked'] as num).toInt() > 0)
            _statChip(Icons.block, '${ts['blocked']}', _kRed),
        ]),
        // 멤버 목록
        if (members.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 2, children: members.map((m) {
            final isWorking = m['status'] == 'Working';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isWorking ? _kGreen.withValues(alpha: 0.1) : _kPanel,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${m['display_name'] ?? m['role']}',
                style: TextStyle(fontSize: 9, color: isWorking ? _kGreen : _kTextMuted),
              ),
            );
          }).toList()),
        ],
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════
  // TAB 2 : CLI / Fleet
  // ════════════════════════════════════════════════════════════

  // ── CLI Exec: 명령 실행 ──
  Future<void> _execCliCommand() async {
    final cmd = _cliCmdCtrl.text.trim();
    if (cmd.isEmpty || _cliExecRunning) return;

    setState(() {
      _cliExecRunning = true;
      _cliHistory.add({'type': 'input', 'text': cmd, 'time': DateTime.now().toString()});
    });
    _cliCmdCtrl.clear();

    try {
      final api = context.read<ApiService>();
      final res = await api.cliExec(cmd);
      if (!mounted) return;
      final isShell = res['type'] == 'shell';
      final exitCode = res['exit_code'];
      final durationMs = res['duration_ms'];
      var text = res['result'] ?? res['error'] ?? '응답 없음';
      if (isShell && (exitCode != null || durationMs != null)) {
        final suffix = [
          if (exitCode != null && exitCode != 0) 'exit=$exitCode',
          if (durationMs != null) '${durationMs}ms',
        ].join(' ');
        if (suffix.isNotEmpty) text = '$text\n--- $suffix';
      }
      setState(() {
        _cliHistory.add({
          'type': res['ok'] == true ? 'output' : 'error',
          'text': text,
          'command': res['command'] ?? '',
          'data': res['data'],
          'time': DateTime.now().toString(),
        });
        _cliExecRunning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cliHistory.add({'type': 'error', 'text': '연결 실패: $e', 'time': DateTime.now().toString()});
        _cliExecRunning = false;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cliScrollCtrl.hasClients) {
        _cliScrollCtrl.animateTo(
          _cliScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _cliTerminal() {
    // 일반 CLI(cliExec) 는 작동 신뢰도 문제로 비활성화 — tmux mirror 로 통일.
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0a1628), Color(0xFF0e2435)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kCyan.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kCyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.terminal, color: _kCyan, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('tmux Mirror', style: TextStyle(color: _kText, fontSize: 15, fontWeight: FontWeight.w800)),
            SizedBox(height: 2),
            Text('실시간 PC 세션 미러 — Ctrl+B 프리픽스 단축키 지원',
              style: TextStyle(color: _kTextSec, fontSize: 11)),
          ])),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CliMirrorScreen())),
            icon: const Icon(Icons.open_in_full, size: 18),
            label: const Text('tmux 세션 열기', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kCyan,
              foregroundColor: const Color(0xFF062032),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _tmuxHint('^B n', '다음 윈도우'),
          _tmuxHint('^B p', '이전 윈도우'),
          _tmuxHint('^B c', '새 윈도우'),
          _tmuxHint('^B d', 'detach'),
          _tmuxHint('^B %', 'split |'),
          _tmuxHint('^B "', 'split —'),
        ]),
      ]),
    );
  }

  Widget _tmuxHint(String key, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kBg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(key, style: const TextStyle(color: _kCyan, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _kTextSec, fontSize: 10)),
      ]),
    );
  }

  Widget _buildCliTab() {
    if (_loadingCli && _fleet.isEmpty && _jobs.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent));
    }

    final runningJobs = _jobs
        .where(
            (j) => j['status'] == 'running' || j['status'] == 'approved')
        .toList();
    final recentJobs = _jobs
        .where(
            (j) => j['status'] != 'running' && j['status'] != 'approved')
        .take(15)
        .toList();

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadCli,
          color: _kAccent,
          backgroundColor: _kCard,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              // ── CLI 터미널 ──
              _cliTerminal(),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fleet Status section
                    _sectionTitle(
                        'Fleet',
                        '${_fleet.length} instances',
                        _fleet.isNotEmpty ? _kGreen : _kTextMuted),
                    const SizedBox(height: 8),
                    if (_fleet.isEmpty)
                      _emptyPlaceholder(
                          Icons.smart_toy_outlined, '실행 중인 Claude 없음')
                    else
                      ..._fleet.map((f) => _fleetCard(f)),

                    const SizedBox(height: 16),

                    // CLI Stats summary
                    if (_cliStats.isNotEmpty) ...[
                      _cliStatsRow(),
                      const SizedBox(height: 12),
                    ],

                    // Running jobs
                    if (runningJobs.isNotEmpty) ...[
                      _sectionTitle(
                          '실행 중', '${runningJobs.length}', _kWarning),
                      const SizedBox(height: 8),
                      ...runningJobs.map((j) => _jobCard(j)),
                      const SizedBox(height: 12),
                    ],

                    // Recent jobs
                    _sectionTitle(
                        '최근 작업', '${recentJobs.length}', _kTextSec),
                    const SizedBox(height: 8),
                    if (recentJobs.isEmpty)
                      _emptyPlaceholder(Icons.work_off_outlined, '작업 없음')
                    else
                      ...recentJobs.map((j) => _jobCard(j)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // FAB: New Job
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: 'ops_new_job',
            backgroundColor: _kAccent,
            onPressed: () => _showNewJobSheet(context),
            child: const Icon(Icons.add, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _cliStatsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _cliStatItem(
              'Running',
              _cliStats['running']?.toString() ?? '0',
              _kWarning),
          _cliStatItem(
              'Completed',
              _cliStats['completed']?.toString() ?? '0',
              _kGreen),
          _cliStatItem(
              'Failed',
              _cliStats['failed']?.toString() ?? '0',
              _kRed),
          _cliStatItem(
              'Pending',
              _cliStats['pending']?.toString() ?? '0',
              _kTextSec),
        ],
      ),
    );
  }

  Widget _cliStatItem(String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(fontSize: 9, color: _kTextMuted)),
    ]);
  }

  Widget _fleetCard(Map<String, dynamic> f) {
    final pid = f['pid'] as int? ?? 0;
    final project = f['project']?.toString() ?? '?';
    final mem = (f['mem_mb'] as num?)?.toInt() ?? 0;
    final uptime = (f['uptime_sec'] as num?)?.toInt() ?? 0;
    final job = f['active_job'] as Map<String, dynamic>?;
    final hasJob = job != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: hasJob
                ? _kWarning.withValues(alpha: 0.3)
                : _kGreen.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasJob ? _kWarning : _kGreen,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(project,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kText)),
          ),
          _badge(hasJob ? 'WORKING' : 'IDLE',
              hasJob ? _kWarning : _kGreen),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _statChip(Icons.memory, '${mem}MB', _kCyan),
          const SizedBox(width: 8),
          _statChip(Icons.timer_outlined, _fmtDuration(uptime), _kPurple),
          const SizedBox(width: 8),
          _statChip(Icons.tag, 'PID $pid', _kTextSec),
          const Spacer(),
          GestureDetector(
            onTap: () => _showFleetMessageSheet(context, pid, project),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.message, size: 12, color: _kAccent),
                SizedBox(width: 4),
                Text('전송',
                    style: TextStyle(
                        fontSize: 10,
                        color: _kAccent,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        if (hasJob) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kPanel,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(job['prompt']?.toString() ?? '',
                style: const TextStyle(fontSize: 11, color: _kTextSec),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ]),
    );
  }

  Widget _jobCard(Map<String, dynamic> j) {
    final status = j['status']?.toString() ?? '';
    final prompt = j['prompt']?.toString() ?? '';
    final projectName = j['project_name']?.toString();
    final projectPath = j['project_path']?.toString() ?? '';
    final displayProject = (projectName != null && projectName.isNotEmpty)
        ? projectName
        : (projectPath.isNotEmpty
            ? projectPath.split('/').last
            : '?');
    final model = j['model']?.toString() ?? '';
    final jobId = j['job_id']?.toString() ?? '';

    Color sc;
    IconData si;
    switch (status) {
      case 'running':
        sc = _kWarning;
        si = Icons.play_circle;
        break;
      case 'approved':
        sc = _kCyan;
        si = Icons.hourglass_top;
        break;
      case 'completed':
        sc = _kGreen;
        si = Icons.check_circle;
        break;
      case 'failed':
        sc = _kRed;
        si = Icons.error;
        break;
      case 'cancelled':
        sc = _kTextMuted;
        si = Icons.cancel;
        break;
      default:
        sc = _kTextSec;
        si = Icons.help_outline;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(si, size: 16, color: sc),
          const SizedBox(width: 6),
          Expanded(
            child: Text(prompt,
                style: const TextStyle(
                    fontSize: 12,
                    color: _kText,
                    fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Text(displayProject,
              style: const TextStyle(
                  fontSize: 10,
                  color: _kAccent,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$jobId | $model',
              style: const TextStyle(
                  fontSize: 9,
                  color: _kTextMuted,
                  fontFamily: 'monospace')),
        ]),
        if (status == 'running' || status == 'approved')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              if (status == 'approved')
                _actionButton(Icons.play_arrow, '시작', _kGreen, () async {
                  await context.read<ApiService>().approveCliJob(jobId);
                  _loadCli();
                }),
              if (status == 'approved') const SizedBox(width: 8),
              _actionButton(Icons.stop, '중지', _kRed, () async {
                await context.read<ApiService>().killCliJob(jobId);
                _loadCli();
              }),
            ]),
          ),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════
  // TAB 3 : Resources
  // ════════════════════════════════════════════════════════════

  Widget _buildResourcesTab() {
    if (_loadingResources && _metrics.isEmpty && _gpu.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent));
    }

    if (!_loadingResources && _metrics.isEmpty && (_gpu.isEmpty || _gpu['ok'] != true)) {
      return RefreshIndicator(
        onRefresh: _loadResources,
        color: _kAccent,
        backgroundColor: _kCard,
        child: ListView(children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off, size: 48, color: _kTextMuted),
              SizedBox(height: 12),
              Text('서버 연결 실패', style: TextStyle(color: _kTextSec, fontSize: 14)),
              SizedBox(height: 4),
              Text('당겨서 새로고침', style: TextStyle(color: _kTextMuted, fontSize: 11)),
            ])),
          ),
        ]),
      );
    }

    // GPU data from /api/system/gpu endpoint (gpus array)
    final gpusList = ((_gpu['gpus'] as List?) ?? []).cast<Map<String, dynamic>>();
    final gpuData = gpusList.isNotEmpty ? gpusList.first : <String, dynamic>{};
    final gpuName = gpuData['name']?.toString() ?? _metrics['gpu_name']?.toString() ?? '';
    final gpuUtil = (gpuData['utilization'] as num?)?.toDouble() ?? 0;
    final gpuTemp = (gpuData['temperature'] as num?)?.toDouble() ?? 0;
    final vramUsed = (gpuData['memory_used_mb'] as num?)?.toDouble() ?? 0;
    final vramTotal = (gpuData['memory_total_mb'] as num?)?.toDouble() ?? 0;
    final vramPct = (gpuData['memory_percent'] as num?)?.toDouble() ?? 0;
    final powerW = (gpuData['power_draw_w'] as num?)?.toDouble() ?? 0;
    final powerMax = 575.0; // RTX 5090 TDP

    // Lambda Cloud instances — GPU API 우선, 없으면 competitions 데이터 fallback
    List<Map<String, dynamic>> lambdaInstances = ((_gpu['lambda_instances'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (lambdaInstances.isEmpty && _lambdaRunning.isNotEmpty) {
      lambdaInstances = _lambdaRunning;
    }

    // System metrics from /api/system/gpu (more reliable than /api/system/metrics)
    final cpuGpu = (_gpu['cpu_percent'] as num?)?.toDouble();
    final cpu = cpuGpu ?? ((_metrics['cpu_percent'] as num?)?.toDouble() ?? 0);
    final memGpu = (_gpu['memory'] as Map<String, dynamic>?) ?? {};
    final memTotalMb = (memGpu['total_mb'] as num?)?.toDouble() ?? (_metrics['memory_total_mb'] as num?)?.toDouble() ?? 0;
    final memUsedMb = (memGpu['used_mb'] as num?)?.toDouble() ?? (_metrics['memory_used_mb'] as num?)?.toDouble() ?? 0;
    final memTotal = memTotalMb / 1024;
    final memUsed = memUsedMb / 1024;
    final memPct = (memGpu['percent'] as num?)?.toDouble() ?? (memTotal > 0 ? memUsed / memTotal * 100 : 0.0);
    final diskGpu = (_gpu['disk'] as Map<String, dynamic>?) ?? {};
    final diskTotal = (diskGpu['total_gb'] as num?)?.toDouble() ?? (_metrics['disk_total_gb'] as num?)?.toDouble() ?? 0;
    final diskUsed = (diskGpu['used_gb'] as num?)?.toDouble() ?? (_metrics['disk_used_gb'] as num?)?.toDouble() ?? 0;
    final diskPct = (diskGpu['percent'] as num?)?.toDouble() ?? (diskTotal > 0 ? diskUsed / diskTotal * 100 : 0.0);
    final uptime = (_metrics['uptime_seconds'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      onRefresh: _loadResources,
      color: _kAccent,
      backgroundColor: _kCard,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // GPU section
          if (gpuName.isNotEmpty) ...[
            _sectionTitle('GPU', gpuName, _kPurple),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // GPU utilization
                    _resourceBar(
                      'Utilization',
                      gpuUtil,
                      '${gpuUtil.toStringAsFixed(0)}%',
                      gpuUtil > 80
                          ? _kRed
                          : gpuUtil > 50
                              ? _kOrange
                              : _kAccent,
                    ),
                    const SizedBox(height: 12),
                    // VRAM
                    _resourceBar(
                      'VRAM',
                      vramPct,
                      '${(vramUsed / 1024).toStringAsFixed(1)} / ${(vramTotal / 1024).toStringAsFixed(1)} GB',
                      vramPct > 80
                          ? _kRed
                          : vramPct > 50
                              ? _kOrange
                              : _kGreen,
                    ),
                    const SizedBox(height: 12),
                    // GPU info chips
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      _infoChip(Icons.thermostat, '${gpuTemp.toStringAsFixed(0)}C',
                          gpuTemp > 80
                              ? _kRed
                              : gpuTemp > 60
                                  ? _kOrange
                                  : _kTextSec),
                      if (powerW > 0)
                        _infoChip(
                            Icons.bolt,
                            '${powerW.toStringAsFixed(0)}/${powerMax.toStringAsFixed(0)}W',
                            _kTextSec),
                    ]),
                  ]),
            ),
            const SizedBox(height: 16),
          ],

          // Lambda Cloud section
          _sectionTitle('Lambda Cloud', lambdaInstances.isEmpty ? 'no instances' : '${lambdaInstances.length} running', _kOrange),
          const SizedBox(height: 8),
          if (lambdaInstances.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: _kBorder)),
              child: const Row(children: [
                Icon(Icons.cloud_off, size: 16, color: _kTextSec),
                SizedBox(width: 8),
                Text('No active Lambda instances', style: TextStyle(color: _kTextSec, fontSize: 12)),
              ]),
            )
          else
            ...lambdaInstances.map((li) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: _kBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.cloud, size: 16, color: _kOrange),
                  const SizedBox(width: 8),
                  Expanded(child: Text(li['gpu']?.toString() ?? 'GPU', style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w600))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: _kGreen.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(li['status']?.toString() ?? '', style: const TextStyle(color: _kGreen, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _infoChip(Icons.memory, '${li['vcpus'] ?? 0} vCPU', _kTextSec),
                  _infoChip(Icons.storage, '${li['ram_gb'] ?? 0} GB RAM', _kTextSec),
                  _infoChip(Icons.disc_full, '${li['storage_gb'] ?? 0} GB SSD', _kTextSec),
                  _infoChip(Icons.attach_money, '\$${li['price_per_hour'] ?? 0}/hr', _kOrange),
                  if (li['region'] != null && li['region'].toString().isNotEmpty)
                    _infoChip(Icons.location_on, li['region'].toString(), _kTextSec),
                  if (li['ip'] != null && li['ip'].toString().isNotEmpty)
                    _infoChip(Icons.language, li['ip'].toString(), _kAccent),
                ]),
              ]),
            )),
          const SizedBox(height: 16),

          // System metrics section
          _sectionTitle('System', uptime > 0 ? _fmtDuration(uptime) : '', _kCyan),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Column(children: [
              _resourceBar(
                'CPU',
                cpu,
                '${cpu.toStringAsFixed(1)}%',
                cpu > 80
                    ? _kRed
                    : cpu > 60
                        ? _kOrange
                        : _kGreen,
              ),
              const SizedBox(height: 14),
              _resourceBar(
                'Memory',
                memPct,
                '${memUsed.toStringAsFixed(1)} / ${memTotal.toStringAsFixed(1)} GB',
                memPct > 85
                    ? _kRed
                    : memPct > 70
                        ? _kOrange
                        : _kAccent,
              ),
              const SizedBox(height: 14),
              _resourceBar(
                'Disk',
                diskPct,
                '${diskUsed.toStringAsFixed(1)} / ${diskTotal.toStringAsFixed(1)} GB',
                diskPct > 90
                    ? _kRed
                    : diskPct > 75
                        ? _kOrange
                        : _kPurple,
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // Additional server info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Server Info',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kTextSec)),
                  const SizedBox(height: 8),
                  _serverInfoRow('Platform',
                      _metrics['platform']?.toString() ?? '-'),
                  _serverInfoRow(
                      'Host', _metrics['hostname']?.toString() ?? '-'),
                  _serverInfoRow('Python',
                      _metrics['python_version']?.toString() ?? '-'),
                  _serverInfoRow('SSE Clients',
                      '${_metrics['sse_clients'] ?? 0}'),
                  _serverInfoRow('Active Teams',
                      '${_metrics['active_teams'] ?? 0}'),
                  _serverInfoRow('DB Size',
                      '${(_metrics['db_size_mb'] as num?)?.toStringAsFixed(2) ?? '0'} MB'),
                ]),
          ),
        ],
      ),
    );
  }

  Widget _resourceBar(
      String label, double pct, String detail, Color color) {
    final clamped = pct.clamp(0.0, 100.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: _kTextSec,
                    fontWeight: FontWeight.w600)),
            Text(detail,
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w700)),
          ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: clamped / 100,
          minHeight: 7,
          backgroundColor: _kPanel,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ]);
  }

  static const _groupLabels = {
    'gpu': 'GPU / 비용',
    'supervisor': 'Supervisor',
    'team': '팀',
    'ticket': '티켓',
    'system': '시스템',
  };
  static const _groupIcons = {
    'gpu': Icons.memory,
    'supervisor': Icons.admin_panel_settings,
    'team': Icons.groups,
    'ticket': Icons.assignment,
    'system': Icons.settings,
  };
  static const _groupColors = {
    'gpu': _kRed,
    'supervisor': _kPurple,
    'team': _kGreen,
    'ticket': _kAccent,
    'system': _kTextSec,
  };

  List<Widget> _buildNotifCategoryGroups() {
    if (_notifCategories.isEmpty) {
      return [const Text('서버에서 카테고리 로딩 중...', style: TextStyle(fontSize: 11, color: _kTextMuted))];
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final c in _notifCategories) {
      final g = c['group']?.toString() ?? 'system';
      groups.putIfAbsent(g, () => []).add(c);
    }
    final widgets = <Widget>[];
    for (final g in ['gpu', 'supervisor', 'team', 'ticket', 'system']) {
      final items = groups[g];
      if (items == null) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Row(children: [
          Icon(_groupIcons[g] ?? Icons.label, size: 12, color: _groupColors[g] ?? _kTextSec),
          const SizedBox(width: 6),
          Text(_groupLabels[g] ?? g, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _groupColors[g] ?? _kTextSec)),
        ]),
      ));
      for (final cat in items) {
        final key = cat['key']?.toString() ?? '';
        final label = cat['label']?.toString() ?? key;
        final enabled = _notifPrefs[key] ?? true;
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: _kText))),
            SizedBox(
              height: 28,
              child: Switch(
                value: enabled,
                activeThumbColor: _groupColors[g] ?? _kAccent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) async {
                  setState(() => _notifPrefs[key] = v);
                  await context.read<ApiService>().setNotifPrefs({'prefs': _notifPrefs});
                },
              ),
            ),
          ]),
        ));
      }
    }
    return widgets;
  }

  Widget _serverInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 11, color: _kTextMuted)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 11, color: _kText),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════
  // TAB 4 : Hooks & Sessions
  // ════════════════════════════════════════════════════════════

  Future<void> _loadHooks() async {
    final api = context.read<ApiService>();
    try {
      final stats = await api.get('/api/hooks/stats?hours=$_hooksRangeHours');
      final events = await api.get('/api/hooks/events?limit=20');
      final sessStats = await api.get('/api/sessions/stats');
      final sessions = await api.get('/api/sessions?status=active');
      if (!mounted) return;
      setState(() {
        _hookStats = stats is Map<String, dynamic> ? stats : {};
        _hookEvents = (events is Map && events['events'] is List)
            ? List<Map<String, dynamic>>.from(events['events'])
            : [];
        _sessionStats = sessStats is Map<String, dynamic> ? sessStats : {};
        _activeSessions = (sessions is Map && sessions['sessions'] is List)
            ? List<Map<String, dynamic>>.from(sessions['sessions'])
            : [];
        _loadingHooks = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHooks = false);
    }
  }

  Widget _buildHooksTab() {
    if (_loadingHooks) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    // 응답 필드명 변형 대응: total | by_event_type | by_kind 모두 처리
    final totalRaw = _hookStats['total'];
    final total = (totalRaw is num) ? totalRaw.toInt() : 0;
    final activeSes = (_sessionStats['active_sessions'] as num?)?.toInt() ?? 0;
    final todaySes = (_sessionStats['sessions_today'] as num?)?.toInt() ?? 0;
    final timedOut = (_sessionStats['timed_out'] as num?)?.toInt() ?? 0;
    final dynamic byType = _hookStats['by_event_type'] ?? _hookStats['by_kind'];
    final dynamic byTool = _hookStats['by_tool'];
    final hasData = total > 0 || (byType is Map && byType.isNotEmpty) ||
        _hookEvents.isNotEmpty || _activeSessions.isNotEmpty;

    String fmt(int v) => v > 0 ? '$v' : '-';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 기간 필터 토글
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _rangeChip('24h', 24),
            const SizedBox(width: 6),
            _rangeChip('7d', 168),
          ],
        ),
        const SizedBox(height: 8),
        // KPI Cards
        Row(children: [
          _hookKpi('Hook Events', fmt(total), total > 0 ? _kAccent : _kTextMuted, Icons.webhook),
          const SizedBox(width: 8),
          _hookKpi('Active Sessions', fmt(activeSes), activeSes > 0 ? _kGreen : _kTextMuted, Icons.play_circle),
          const SizedBox(width: 8),
          _hookKpi('Today', fmt(todaySes), todaySes > 0 ? _kCyan : _kTextMuted, Icons.today),
          const SizedBox(width: 8),
          _hookKpi('Timed Out', fmt(timedOut), timedOut > 0 ? _kRed : _kTextMuted, Icons.timer_off),
        ]),
        const SizedBox(height: 16),

        if (!hasData) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              children: [
                Icon(Icons.webhook, size: 32, color: _kTextMuted.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                Text(
                  '최근 ${_hooksRangeHours == 168 ? '7일' : '${_hooksRangeHours}시간'} 기록된 Hook 이벤트가 없습니다',
                  style: const TextStyle(color: _kTextMuted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Claude Code 훅이 설치되면 자동 수집됩니다',
                  style: TextStyle(color: _kTextMuted.withValues(alpha: 0.7), fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Active Sessions
        if (_activeSessions.isNotEmpty) ...[
          const Text('Active Sessions', style: TextStyle(color: _kText, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          ..._activeSessions.map((s) {
            final ctxMax = (s['context_max'] ?? 200000) as num;
            final ctxUsed = (s['context_used'] ?? 0) as num;
            final pct = ctxMax > 0 ? ctxUsed / ctxMax : 0.0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: _kBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(s['session_id'] ?? '', style: const TextStyle(color: _kText, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: _kGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                    child: Text(s['status'] ?? '', style: const TextStyle(color: _kGreen, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('${s['model'] ?? ''} · Turns: ${s['turns'] ?? 0}', style: const TextStyle(color: _kTextSec, fontSize: 11)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0).toDouble(),
                    backgroundColor: _kBorder,
                    color: pct > 0.8 ? _kRed : pct > 0.5 ? _kOrange : _kGreen,
                    minHeight: 4,
                  ),
                ),
                Text('Context: ${(pct * 100).toStringAsFixed(0)}%', style: const TextStyle(color: _kTextMuted, fontSize: 10)),
              ]),
            );
          }),
          const SizedBox(height: 16),
        ],

        // Hook Stats by Type
        if (byType is Map && byType.isNotEmpty) ...[
          Text(
            'Events by Type (${_hooksRangeHours == 168 ? '7d' : '${_hooksRangeHours}h'})',
            style: const TextStyle(color: _kText, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...byType.entries.map((e) => _hookStatRow(e.key.toString(), e.value)),
          const SizedBox(height: 16),
        ],

        // Hook Stats by Tool
        if (byTool is Map && byTool.isNotEmpty) ...[
          const Text('Events by Tool', style: TextStyle(color: _kText, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          ...byTool.entries.map((e) => _hookStatRow(e.key.toString(), e.value)),
          const SizedBox(height: 16),
        ],

        // Recent Events
        const Text('Recent Hook Events', style: TextStyle(color: _kText, fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        if (_hookEvents.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('아직 이벤트 없음', style: TextStyle(color: _kTextMuted, fontSize: 12))))
        else
          ..._hookEvents.map((e) {
            final evType = e['event_type'] ?? '';
            final tool = e['tool_name'] ?? '';
            final time = (e['created_at'] ?? '').toString();
            final timeShort = time.length >= 19 ? time.substring(11, 19) : time;
            final color = evType == 'SessionStart' ? _kGreen
                : evType == 'SessionEnd' ? _kRed
                : evType == 'PostToolUse' ? _kAccent
                : evType == 'Stop' ? _kOrange
                : _kCyan;
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _kBorder.withValues(alpha: 0.5)))),
              child: Row(children: [
                Text(timeShort, style: const TextStyle(color: _kTextMuted, fontSize: 10, fontFamily: 'monospace')),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                  child: Text(evType, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
                ),
                if (tool.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(tool, style: const TextStyle(color: _kTextSec, fontSize: 11)),
                ],
              ]),
            );
          }),
      ],
    );
  }

  Widget _hookKpi(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: _kBorder)),
        child: Column(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: _kTextMuted, fontSize: 9), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _hookStatRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: _kTextSec, fontSize: 12)),
        Text('$value', style: const TextStyle(color: _kText, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _rangeChip(String label, int hours) {
    final selected = _hooksRangeHours == hours;
    return GestureDetector(
      onTap: () {
        if (selected) return;
        setState(() {
          _hooksRangeHours = hours;
          _loadingHooks = true;
        });
        _loadHooks();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? _kAccent.withValues(alpha: 0.2) : _kCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? _kAccent : _kBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _kAccent : _kTextSec,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // TAB 5 : Settings
  // ════════════════════════════════════════════════════════════

  Widget _buildSettingsTab() {
    final api = context.watch<ApiService>();
    final auth = context.read<AuthService>();
    final connected = api.connected;
    final serverUrl = auth.serverUrl;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Connection status
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: connected
                    ? _kGreen.withValues(alpha: 0.3)
                    : _kRed.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? _kGreen : _kRed,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connected ? '서버 연결됨' : '서버 연결 안됨',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: connected ? _kGreen : _kRed)),
                    const SizedBox(height: 2),
                    Text(serverUrl,
                        style: const TextStyle(
                            fontSize: 11,
                            color: _kTextMuted,
                            fontFamily: 'monospace')),
                  ]),
            ),
            _badge(connected ? 'ONLINE' : 'OFFLINE',
                connected ? _kGreen : _kRed),
          ]),
        ),

        const SizedBox(height: 16),

        // Supervisor model selector
        _sectionTitle('Supervisor AI Model', '', _kAccent),
        const SizedBox(height: 8),
        if (_supervisorModels.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: const Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _kAccent)),
          )
        else
          ..._supervisorModels.map((m) {
            final id = m['id'] as String? ?? '';
            final name = m['name'] as String? ?? '';
            final provider = m['provider'] as String? ?? '';
            final desc = m['description'] as String? ?? '';
            final selected = _supervisorModel == id;
            final providerColor =
                provider == 'anthropic' ? _kOrange : _kGreen;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1c2f47)
                    : _kCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? _kAccent : _kBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _savingModel
                    ? null
                    : () => _saveModel(id),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? _kAccent : _kTextMuted,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(name,
                                    style: const TextStyle(
                                        color: _kText,
                                        fontSize: 13,
                                        fontWeight:
                                            FontWeight.w600)),
                              ),
                              _badge(
                                  provider.toUpperCase(),
                                  providerColor),
                            ]),
                            const SizedBox(height: 2),
                            Text(id,
                                style: const TextStyle(
                                    color: _kTextMuted,
                                    fontSize: 10,
                                    fontFamily: 'monospace')),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(desc,
                                  style: const TextStyle(
                                      color: _kTextSec,
                                      fontSize: 10)),
                            ],
                          ]),
                    ),
                  ]),
                ),
              ),
            );
          }),

        // Health check result
        if (_checkingHealth || _healthResult != null) ...[
          const SizedBox(height: 8),
          _healthCard(),
        ],

        // Health check button
        if (_supervisorModel.isNotEmpty &&
            !_checkingHealth &&
            _healthResult == null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _runHealth(_supervisorModel),
              icon:
                  const Icon(Icons.health_and_safety, size: 16),
              label: const Text('Health Check'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kAccent,
                side: const BorderSide(color: _kAccent),
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Notification preferences — 카테고리별 토글
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.notifications_outlined, size: 18, color: _kAccent),
              const SizedBox(width: 8),
              const Text('알림 설정', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kText)),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final allOn = _notifPrefs.values.every((v) => v);
                  final newPrefs = _notifPrefs.map((k, _) => MapEntry(k, !allOn));
                  setState(() => _notifPrefs = newPrefs);
                  await context.read<ApiService>().setNotifPrefs({'prefs': newPrefs});
                },
                child: Text(
                  _notifPrefs.values.every((v) => v) ? '전체 끄기' : '전체 켜기',
                  style: const TextStyle(fontSize: 10, color: _kAccent, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            ..._buildNotifCategoryGroups(),
          ]),
        ),

        const SizedBox(height: 16),

        // App info
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('App Info',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kTextSec)),
                const SizedBox(height: 8),
                _serverInfoRow('App', 'U2DIA Kanban Board'),
                _serverInfoRow('Version', '5.11.1'),
                _serverInfoRow('Platform', 'Flutter'),
                _serverInfoRow(
                    'Server', connected ? serverUrl : 'Disconnected'),
              ]),
        ),
      ],
    );
  }

  Widget _healthCard() {
    final isHealthy = _healthResult?['healthy'] == true;
    final borderColor = _checkingHealth
        ? _kAccent
        : (isHealthy ? _kGreen : _kRed);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (_checkingHealth) ...[
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kAccent)),
                const SizedBox(width: 8),
                const Text('Health Check...',
                    style: TextStyle(
                        color: _kAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ] else ...[
                Icon(isHealthy ? Icons.check_circle : Icons.error,
                    color: isHealthy ? _kGreen : _kRed, size: 16),
                const SizedBox(width: 8),
                Text(isHealthy ? 'PASSED' : 'FAILED',
                    style: TextStyle(
                        color: isHealthy ? _kGreen : _kRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
              const Spacer(),
              if (!_checkingHealth && _supervisorModel.isNotEmpty)
                GestureDetector(
                  onTap: () => _runHealth(_supervisorModel),
                  child: const Icon(Icons.refresh,
                      size: 16, color: _kTextSec),
                ),
            ]),
            if (_healthResult != null && !_checkingHealth) ...[
              const SizedBox(height: 8),
              _serverInfoRow('Model',
                  _healthResult!['model']?.toString() ?? '-'),
              _serverInfoRow('Provider',
                  (_healthResult!['provider']?.toString() ?? '-')
                      .toUpperCase()),
              _serverInfoRow('Latency',
                  '${_healthResult!['latency_ms'] ?? 0}ms'),
              if (_healthResult!['error'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      'Error: ${_healthResult!['error']}',
                      style: const TextStyle(
                          color: _kRed, fontSize: 10)),
                ),
            ],
          ]),
    );
  }

  Future<void> _saveModel(String modelId) async {
    setState(() {
      _savingModel = true;
      _healthResult = null;
    });
    try {
      final res = await context
          .read<ApiService>()
          .setSupervisorModel(modelId);
      if (!mounted) return;
      if (res['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: ${res['error'] ?? ''}'),
          backgroundColor: _kRed,
        ));
        return;
      }
      setState(() => _supervisorModel = modelId);
      await _runHealth(modelId);
    } finally {
      if (mounted) setState(() => _savingModel = false);
    }
  }

  Future<void> _runHealth(String modelId) async {
    setState(() => _checkingHealth = true);
    try {
      final res = await context
          .read<ApiService>()
          .supervisorModelHealth(modelId);
      if (!mounted) return;
      setState(() => _healthResult = res);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _healthResult = {'healthy': false, 'error': e.toString()});
      }
    } finally {
      if (mounted) setState(() => _checkingHealth = false);
    }
  }

  // ════════════════════════════════════════════════════════════
  // Bottom sheets
  // ════════════════════════════════════════════════════════════

  void _showNewJobSheet(BuildContext context) {
    final promptCtrl = TextEditingController();
    final projects = _fleet
        .map((f) => f['project']?.toString() ?? '')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();
    String? selectedProject =
        projects.isNotEmpty ? projects.first : null;
    String selectedModel = 'claude-sonnet-4-20250514';
    int maxTurns = 30;
    int timeout = 300;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('New CLI Job',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _kText)),
                  const Spacer(),
                  IconButton(
                      icon:
                          const Icon(Icons.close, size: 20, color: _kTextSec),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 12),
                if (projects.isNotEmpty) ...[
                  const Text('Project',
                      style: TextStyle(
                          fontSize: 11,
                          color: _kTextSec,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                      spacing: 6,
                      children: projects
                          .map((p) => ChoiceChip(
                                label: Text(p,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: selectedProject == p
                                            ? _kText
                                            : _kTextSec)),
                                selected: selectedProject == p,
                                onSelected: (v) => setSheetState(
                                    () => selectedProject = p),
                                backgroundColor: _kPanel,
                                selectedColor: _kAccent,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(6)),
                              ))
                          .toList()),
                  const SizedBox(height: 12),
                ],
                const Text('Model',
                    style: TextStyle(
                        fontSize: 11,
                        color: _kTextSec,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                    spacing: 6,
                    children: [
                      ('claude-sonnet-4-20250514', 'Sonnet 4'),
                      ('claude-opus-4-6', 'Opus 4.6'),
                      ('claude-haiku-4-5-20251001', 'Haiku 4.5'),
                    ]
                        .map((e) => ChoiceChip(
                              label: Text(e.$2,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: selectedModel == e.$1
                                          ? _kText
                                          : _kTextSec)),
                              selected: selectedModel == e.$1,
                              onSelected: (v) => setSheetState(
                                  () => selectedModel = e.$1),
                              backgroundColor: _kPanel,
                              selectedColor: _kAccent,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(6)),
                            ))
                        .toList()),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text('Max Turns',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: _kTextSec)),
                          const SizedBox(height: 4),
                          Wrap(
                              spacing: 4,
                              children: [10, 30, 50, 100]
                                  .map((v) => ChoiceChip(
                                        label: Text('$v',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color:
                                                    maxTurns == v
                                                        ? _kText
                                                        : _kTextSec)),
                                        selected: maxTurns == v,
                                        onSelected: (_) =>
                                            setSheetState(() =>
                                                maxTurns = v),
                                        backgroundColor: _kPanel,
                                        selectedColor: _kAccent,
                                        shape:
                                            RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius
                                                        .circular(
                                                            4)),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize
                                                .shrinkWrap,
                                        visualDensity:
                                            VisualDensity.compact,
                                      ))
                                  .toList()),
                        ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text('Timeout',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: _kTextSec)),
                          const SizedBox(height: 4),
                          Wrap(
                              spacing: 4,
                              children: [120, 300, 600, 1800]
                                  .map((v) => ChoiceChip(
                                        label: Text(
                                            '${v ~/ 60}m',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color:
                                                    timeout == v
                                                        ? _kText
                                                        : _kTextSec)),
                                        selected: timeout == v,
                                        onSelected: (_) =>
                                            setSheetState(() =>
                                                timeout = v),
                                        backgroundColor: _kPanel,
                                        selectedColor: _kAccent,
                                        shape:
                                            RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius
                                                        .circular(
                                                            4)),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize
                                                .shrinkWrap,
                                        visualDensity:
                                            VisualDensity.compact,
                                      ))
                                  .toList()),
                        ]),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: promptCtrl,
                  maxLines: 4,
                  autofocus: true,
                  style:
                      const TextStyle(fontSize: 13, color: _kText),
                  decoration: InputDecoration(
                    hintText: '작업 지시 내용...',
                    hintStyle:
                        const TextStyle(color: _kTextMuted),
                    filled: true,
                    fillColor: _kPanel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.rocket_launch,
                        size: 18),
                    label: const Text('Dispatch'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      if (promptCtrl.text.trim().isEmpty) return;
                      final api = context.read<ApiService>();
                      String projectPath = '';
                      if (selectedProject != null) {
                        final match = _fleet.firstWhere(
                          (f) =>
                              f['project'] ==
                              selectedProject,
                          orElse: () => <String, dynamic>{},
                        );
                        projectPath = match['project_path']
                                ?.toString() ??
                            '~/github/$selectedProject';
                      }
                      await api.createCliJob({
                        'prompt': promptCtrl.text.trim(),
                        'project_path': projectPath,
                        'model': selectedModel,
                        'max_turns': maxTurns,
                        'timeout_sec': timeout,
                        'auto_approve': true,
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _loadCli();
                    },
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  void _showFleetMessageSheet(
      BuildContext context, int pid, String project) {
    final msgCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.message,
                    size: 20, color: _kAccent),
                const SizedBox(width: 8),
                Text('Message -> $project',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _kText)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close,
                        size: 20, color: _kTextSec),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              Text('PID $pid',
                  style: const TextStyle(
                      fontSize: 11,
                      color: _kTextMuted,
                      fontFamily: 'monospace')),
              const SizedBox(height: 12),
              TextField(
                controller: msgCtrl,
                maxLines: 4,
                autofocus: true,
                style:
                    const TextStyle(fontSize: 13, color: _kText),
                decoration: InputDecoration(
                  hintText: '메시지 내용...',
                  hintStyle:
                      const TextStyle(color: _kTextMuted),
                  filled: true,
                  fillColor: _kPanel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('전송'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    if (msgCtrl.text.trim().isEmpty) return;
                    final api = context.read<ApiService>();
                    await api.fleetSendMessage(
                      pid: pid,
                      message: msgCtrl.text.trim(),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(
                        content:
                            Text('전송 완료 -> $project'),
                        backgroundColor: _kGreen,
                        duration:
                            const Duration(seconds: 2),
                      ));
                    }
                  },
                ),
              ),
            ]),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // Shared widgets
  // ════════════════════════════════════════════════════════════

  Widget _sectionTitle(String title, String sub, Color color) {
    return Row(children: [
      Text(title,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color)),
      if (sub.isNotEmpty) ...[
        const SizedBox(width: 8),
        Expanded(
          child: Text(sub,
              style: const TextStyle(
                  fontSize: 10, color: _kTextMuted),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    ]);
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w700)),
    );
  }

  Widget _statChip(IconData icon, String text, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text(text,
          style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace')),
    ]);
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL을 열 수 없습니다: $url'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL 오류: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _actionButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _emptyPlaceholder(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 36, color: _kTextMuted),
        const SizedBox(height: 8),
        Text(text,
            style:
                const TextStyle(fontSize: 12, color: _kTextSec)),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════
  // Formatting helpers
  // ════════════════════════════════════════════════════════════

  String _fmtDuration(int sec) {
    if (sec < 60) return '${sec}s';
    if (sec < 3600) return '${sec ~/ 60}m';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    return '${h}h${m}m';
  }

  String _formatTimestamp(String ts) {
    if (ts.isEmpty) return '';
    try {
      final dt = DateTime.parse(ts.contains('Z') ? ts : '${ts}Z')
          .add(const Duration(hours: 9));
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts.length > 16 ? ts.substring(0, 16) : ts;
    }
  }
}
