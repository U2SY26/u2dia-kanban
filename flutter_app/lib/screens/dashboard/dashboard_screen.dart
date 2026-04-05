import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../history/history_screen.dart';
import '../archives/archive_detail_screen.dart';
import '../team/team_detail_screen.dart';
import '../kanban/agent_office_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Function(String, String)? onTeamTap;
  const DashboardScreen({super.key, this.onTeamTap});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _stats = {};
  Map<String, dynamic> _usage = {};
  Map<String, dynamic> _metrics = {};
  Map<String, dynamic> _heatmapData = {};
  Map<String, dynamic> _pipeline = {};
  List<Map<String, dynamic>> _teams = [];
  List<Map<String, dynamic>> _activity = [];
  List<Map<String, dynamic>> _projectGoals = [];
  double _usdKrw = 1380;
  Timer? _kpiTimer;
  Timer? _chartTimer;
  bool _loading = true;

  static const _kst = Duration(hours: 9);

  @override
  void initState() {
    super.initState();
    _loadAll();
    _kpiTimer = Timer.periodic(const Duration(seconds: 19), (_) => _loadKpi());
    _chartTimer = Timer.periodic(const Duration(minutes: 5), (_) => _loadCharts());
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadKpi(), _loadCharts()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadKpi() async {
    final api = context.read<ApiService>();
    try {
      final r0 = await api.globalStats();
      final r1 = await api.usageGlobal();
      final r2 = await api.systemMetrics();
      final r3 = await api.getTeamsWithStats();
      final r4 = await api.supervisorPipeline();
      final r5 = await api.projectGoals();
      final r6 = await api.exchangeRate();
      if (mounted) {
        setState(() {
          _stats = r0['ok'] == true ? (r0['stats'] as Map<String, dynamic>? ?? r0) : {};
          _usage = r1['ok'] == true ? r1 : {};
          _metrics = r2['ok'] == true ? (r2['metrics'] as Map<String, dynamic>? ?? r2) : {};
          _teams = (r3 is List) ? r3.cast<Map<String, dynamic>>() : [];
          _pipeline = r4['ok'] == true ? r4 : {};
          _projectGoals = ((r5['projects'] as List?) ?? []).cast<Map<String, dynamic>>();
          _usdKrw = (r6['rate'] as num?)?.toDouble() ?? 1380;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCharts() async {
    final api = context.read<ApiService>();
    try {
      final h = await api.heatmap();
      final a = await api.globalActivity(limit: 40);
      if (mounted) {
        setState(() {
          _heatmapData = h['ok'] == true ? h : {};
          _activity = ((a['logs'] ?? a['activities'] ?? []) as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  String _kstTime(String? utc) {
    if (utc == null || utc.isEmpty) return '';
    try {
      final dt = DateTime.parse(utc.contains('Z') ? utc : '${utc}Z').add(_kst);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return utc.length > 16 ? utc.substring(11, 16) : utc;
    }
  }

  @override
  void dispose() {
    _kpiTimer?.cancel();
    _chartTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<ApiService>().connected;
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22), elevation: 0,
        title: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(
            shape: BoxShape.circle, color: connected ? const Color(0xFF3fb950) : const Color(0xFFf85149),
          )),
          const SizedBox(width: 8),
          const Text('U2DIA Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.history, size: 20), tooltip: '히스토리',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()))),
          IconButton(icon: const Icon(Icons.archive_outlined, size: 20), tooltip: '아카이브',
              onPressed: () => _showArchives()),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () { setState(() => _loading = true); _loadAll(); }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                _buildServerHealth(),
                const SizedBox(height: 16),
                _buildKpiGrid(),
                const SizedBox(height: 16),
                _buildPipelineInsight(),
                const SizedBox(height: 16),
                _buildProjectProgress(),
                const SizedBox(height: 16),
                _buildHeatmap(),
                const SizedBox(height: 16),
                _buildTeamSection(),
                const SizedBox(height: 16),
                _buildActivitySection(),
              ]),
            ),
    );
  }

  Widget _buildServerHealth() {
    final m = _metrics;
    final cpu = (m['cpu_percent'] as num?)?.toDouble() ?? 0;
    final ram = (m['memory_percent'] as num?)?.toDouble() ?? 0;
    final disk = (m['disk_percent'] as num?)?.toDouble() ?? 0;
    final db = (m['db_size_mb'] as num?)?.toDouble() ?? 0;
    final sse = (m['sse_clients'] as num?)?.toInt() ?? 0;
    final connected = context.read<ApiService>().connected;

    final pHealth = _pipeline['health']?.toString() ?? '';
    final pRate = (_pipeline['completion_rate'] as num?)?.toDouble() ?? 0;
    final qaTotal = ((_pipeline['last_24h'] as Map?)?.cast<String, dynamic>() ?? {})['reviews'] ?? 0;
    final rework = _pipeline['rework_distribution'] as Map<String, dynamic>? ?? {};
    final blocked = (_pipeline['blocked_tickets'] as List?)?.length ?? 0;

    Color sColor;
    String sLabel;
    if (!connected) { sColor = const Color(0xFFf85149); sLabel = 'OFFLINE'; }
    else if (cpu > 90 || ram > 90) { sColor = const Color(0xFFf85149); sLabel = 'CRITICAL'; }
    else if (cpu > 70 || ram > 70) { sColor = const Color(0xFFd29922); sLabel = 'WARNING'; }
    else { sColor = const Color(0xFF3fb950); sLabel = 'ONLINE'; }

    Color pColor;
    switch (pHealth) {
      case 'healthy': pColor = const Color(0xFF3fb950); break;
      case 'warning': case 'stalled': pColor = const Color(0xFFd29922); break;
      case 'critical': pColor = const Color(0xFFf85149); break;
      default: pColor = const Color(0xFF8b949e);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        border: Border.all(color: sColor.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: sColor)),
          const SizedBox(width: 6),
          Text('Server $sLabel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: sColor)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: pColor.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
            child: Text('QA ${pHealth.toUpperCase()}', style: TextStyle(color: pColor, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          Text('₩${_usdKrw.toStringAsFixed(0)}/\$', style: const TextStyle(fontSize: 9, color: Color(0xFF8b949e), fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 10),
        // Resource bars
        Row(children: [
          Expanded(child: _resourceBar('CPU', cpu, cpu > 80 ? const Color(0xFFf85149) : const Color(0xFF58a6ff))),
          const SizedBox(width: 8),
          Expanded(child: _resourceBar('RAM', ram, ram > 80 ? const Color(0xFFf85149) : const Color(0xFF3fb950))),
          const SizedBox(width: 8),
          Expanded(child: _resourceBar('Disk', disk, disk > 80 ? const Color(0xFFf85149) : const Color(0xFFbc8cff))),
        ]),
        const SizedBox(height: 8),
        // Bottom row: DB size, SSE clients, QA stats, blocked, completion
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF0d1117), borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            _miniStat('DB', '${db.toStringAsFixed(1)}MB', const Color(0xFF8b949e)),
            _miniStat('SSE', '$sse', const Color(0xFF58a6ff)),
            _miniStat('QA', '$qaTotal', const Color(0xFFa371f7)),
            if (blocked > 0) _miniStat('Block', '$blocked', const Color(0xFFf85149)),
            const Spacer(),
            Text('${pRate.toStringAsFixed(1)}%', style: TextStyle(color: pColor, fontSize: 13, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
          ]),
        ),
      ]),
    );
  }

  Widget _resourceBar(String label, double pct, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF8b949e), fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
      ]),
      const SizedBox(height: 3),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(value: (pct / 100).clamp(0, 1), minHeight: 4,
          backgroundColor: const Color(0xFF30363d), valueColor: AlwaysStoppedAnimation(color)),
      ),
    ]);
  }

  Widget _miniStat(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
        Text(label, style: const TextStyle(fontSize: 8, color: Color(0xFF8b949e))),
      ]),
    );
  }

  Widget _buildKpiGrid() {
    final s = _stats;
    final ut = _usage['total'] ?? {};
    final utd = _usage['today'] ?? {};
    final m = _metrics;

    final cards = [
      _KpiData('Teams', '${s['active_teams'] ?? 0}', Icons.groups, const Color(0xFF58a6ff), sub: '${s['archived_teams'] ?? 0} archived'),
      _KpiData('Agents', '${s['total_agents'] ?? 0}', Icons.smart_toy, const Color(0xFF39d2c0), sub: '${s['working_agents'] ?? 0} working'),
      _KpiData('Tickets', '${s['total_tickets'] ?? 0}', Icons.confirmation_number, const Color(0xFFbc8cff), sub: '${s['done_tickets'] ?? 0} done'),
      _KpiData('Progress', '${s['global_progress'] ?? 0}%', Icons.pie_chart, const Color(0xFF3fb950)),
      _KpiData('Blocked', '${s['blocked_tickets'] ?? 0}', Icons.block, (s['blocked_tickets'] ?? 0) > 0 ? const Color(0xFFf85149) : const Color(0xFF8b949e)),
      _KpiData('Tokens', _fmtNum(((ut['input_tokens'] ?? 0) + (ut['output_tokens'] ?? 0)) as num), Icons.token, const Color(0xFF39d2c0)),
      _KpiData('Total Cost', _fmtKrw((ut['total_cost'] ?? 0) as num), Icons.payments, const Color(0xFFe3b341), sub: '\$${((ut['total_cost'] ?? 0) as num).toStringAsFixed(2)}'),
      _KpiData('Today', _fmtKrw((utd['total_cost'] ?? 0) as num), Icons.today, const Color(0xFF7ee787), sub: '\$${((utd['total_cost'] ?? 0) as num).toStringAsFixed(2)}'),
      _KpiData('System', '${m['cpu_percent'] ?? '-'}%', Icons.monitor_heart, const Color(0xFF8b949e), sub: '${m['memory_percent'] ?? '-'}% RAM'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 1.3, crossAxisSpacing: 8, mainAxisSpacing: 8,
      ),
      itemCount: cards.length,
      itemBuilder: (ctx, i) => _kpiCard(cards[i]),
    );
  }

  Widget _kpiCard(_KpiData d) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(context: context, backgroundColor: const Color(0xFF161b22),
          builder: (_) => Padding(padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(d.icon, size: 32, color: d.color),
              const SizedBox(height: 8),
              Text(d.label, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(color: d.color, fontSize: 28, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
              if (d.sub != null) Padding(padding: const EdgeInsets.only(top: 4),
                child: Text(d.sub!, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12))),
              const SizedBox(height: 20),
            ])));
      },
      child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        border: Border.all(color: const Color(0xFF30363d)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(d.icon, size: 14, color: d.color),
          const SizedBox(width: 4),
          Expanded(child: Text(d.label, style: const TextStyle(fontSize: 9, color: Color(0xFF8b949e), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        ]),
        const Spacer(),
        Text(d.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: d.color, fontFamily: 'monospace')),
        if (d.sub != null) Text(d.sub!, style: const TextStyle(fontSize: 9, color: Color(0xFF8b949e))),
      ]),
    ));
  }

  Widget _buildPipelineInsight() {
    final sc = (_pipeline['status_counts'] as Map<String, dynamic>?) ?? {};
    final health = _pipeline['health']?.toString() ?? '';
    final issues = (_pipeline['issues'] as List?)?.cast<String>() ?? [];
    final last24 = (_pipeline['last_24h'] as Map<String, dynamic>?) ?? {};
    final total = (_pipeline['total_tickets'] as num?)?.toInt() ?? 0;
    final rate = (_pipeline['completion_rate'] as num?)?.toDouble() ?? 0;

    Color hc;
    String hl;
    switch (health) {
      case 'healthy': hc = const Color(0xFF3fb950); hl = 'HEALTHY'; break;
      case 'warning': hc = const Color(0xFFd29922); hl = 'WARNING'; break;
      case 'stalled': hc = const Color(0xFFd29922); hl = 'STALLED'; break;
      case 'critical': hc = const Color(0xFFf85149); hl = 'CRITICAL'; break;
      default: hc = const Color(0xFF8b949e); hl = 'UNKNOWN';
    }

    final stages = [
      ('Done', sc['Done'] ?? 0, const Color(0xFF3fb950)),
      ('Review', sc['Review'] ?? 0, const Color(0xFFa371f7)),
      ('WIP', sc['InProgress'] ?? 0, const Color(0xFFd29922)),
      ('Blocked', sc['Blocked'] ?? 0, const Color(0xFFf85149)),
      ('Backlog', (sc['Backlog'] ?? 0) + (sc['Todo'] ?? 0), const Color(0xFF8b949e)),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        border: Border.all(color: const Color(0xFF30363d)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.timeline, size: 14, color: Color(0xFFe6edf3)),
          const SizedBox(width: 6),
          const Text('Supervisor Pipeline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFe6edf3))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: hc.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
            child: Text(hl, style: TextStyle(color: hc, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        // 파이프라인 바
        if (total > 0) ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(height: 8, child: Row(
            children: stages.map((s) {
              final w = (s.$2 as int) / total;
              if (w <= 0) return const SizedBox.shrink();
              return Flexible(flex: (w * 1000).round().clamp(1, 1000), child: Container(color: s.$3));
            }).toList(),
          )),
        ),
        const SizedBox(height: 8),
        Row(children: stages.map((s) => Expanded(child: Column(children: [
          Text('${s.$2}', style: TextStyle(color: s.$3, fontSize: 13, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
          Text(s.$1, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 8)),
        ]))).toList()),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...issues.map((i) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              const Icon(Icons.warning_amber, size: 12, color: Color(0xFFd29922)),
              const SizedBox(width: 4),
              Expanded(child: Text(i, style: const TextStyle(color: Color(0xFFd29922), fontSize: 10))),
            ]),
          )),
        ],
        // 24시간 QA
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF0d1117), borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            const Text('24h QA: ', style: TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
            Text('${last24['reviews'] ?? 0}건 검수', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 10, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('통과 ${last24['passed'] ?? 0}', style: const TextStyle(color: Color(0xFF3fb950), fontSize: 10)),
            const SizedBox(width: 8),
            Text('재작업 ${last24['reworked'] ?? 0}', style: const TextStyle(color: Color(0xFFf85149), fontSize: 10)),
            const Spacer(),
            Text('${rate.toStringAsFixed(1)}%', style: TextStyle(color: hc, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildProjectProgress() {
    // 미완료 프로젝트만 (진행 중인 것)
    final active = _projectGoals.where((p) {
      final t = (p['total'] as num?)?.toInt() ?? 0;
      final d = (p['done'] as num?)?.toInt() ?? 0;
      return t > 0 && d < t;
    }).toList()
      ..sort((a, b) => ((b['progress'] as num?) ?? 0).compareTo((a['progress'] as num?) ?? 0));

    if (active.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Project Progress (${active.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFe6edf3))),
      const SizedBox(height: 8),
      ...active.take(6).map((p) {
        final name = p['project']?.toString() ?? '';
        final total = (p['total'] as num?)?.toInt() ?? 0;
        final done = (p['done'] as num?)?.toInt() ?? 0;
        final pct = total > 0 ? done / total : 0.0;
        final wip = (p['in_progress'] as num?)?.toInt() ?? 0;
        final rev = (p['review'] as num?)?.toInt() ?? 0;
        final goal = p['goal_title']?.toString() ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF161b22),
            border: Border.all(color: const Color(0xFF30363d)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w600))),
              Text('${(pct * 100).toInt()}%', style: TextStyle(
                color: pct >= 0.8 ? const Color(0xFF3fb950) : const Color(0xFF1B96FF),
                fontSize: 14, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
            ]),
            if (goal.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2),
                child: Text(goal, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: const Color(0xFF30363d),
                valueColor: AlwaysStoppedAnimation(pct >= 0.8 ? const Color(0xFF3fb950) : const Color(0xFF1B96FF)),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Text('$done/$total', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
              if (wip > 0) ...[const SizedBox(width: 8), Text('WIP:$wip', style: const TextStyle(color: Color(0xFFd29922), fontSize: 9))],
              if (rev > 0) ...[const SizedBox(width: 8), Text('Rev:$rev', style: const TextStyle(color: Color(0xFFa371f7), fontSize: 9))],
            ]),
          ]),
        );
      }),
    ]);
  }

  Widget _buildHeatmap() {
    final data = (_heatmapData['data'] as Map<String, dynamic>?) ?? {};
    if (data.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Activity Heatmap (48h, KST)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFe6edf3))),
      const SizedBox(height: 8),
      SizedBox(
        height: 80,
        child: CustomPaint(painter: _HeatmapPainter(data), size: const Size(double.infinity, 80)),
      ),
    ]);
  }

  Widget _buildTeamSection() {
    if (_teams.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Active Teams (${_teams.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFe6edf3))),
      const SizedBox(height: 8),
      ..._teams.take(10).map(_teamTile),
    ]);
  }

  Widget _teamTile(Map<String, dynamic> t) {
    final stats = t['stats'] as Map<String, dynamic>? ?? {};
    final done = (stats['done_tickets'] ?? 0) as int;
    final total = (stats['total_tickets'] ?? 0) as int;
    final pct = total > 0 ? done / total : 0.0;
    return GestureDetector(
      onTap: () => widget.onTeamTap?.call(t['team_id'] ?? '', t['name'] ?? ''),
      onLongPress: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => TeamDetailScreen(teamId: t['team_id'] ?? '', teamName: t['name'] ?? ''),
      )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161b22), border: Border.all(color: const Color(0xFF30363d)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(t['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AgentOfficeScreen(teamId: t['team_id'] ?? '', teamName: t['name'] ?? ''))),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF1B96FF).withOpacity(0.1), borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF1B96FF).withOpacity(0.3))),
                child: const Text('Office', style: TextStyle(fontSize: 10, color: Color(0xFF58a6ff), fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            Text('$done/$total', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF8b949e))),
          ]),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: pct, minHeight: 3,
              backgroundColor: const Color(0xFF30363d), valueColor: const AlwaysStoppedAnimation(Color(0xFF3fb950)))),
          const SizedBox(height: 4),
          Row(children: [
            Text('👥 ${t['in_progress'] ?? 0} WIP', style: const TextStyle(fontSize: 9, color: Color(0xFF8b949e))),
            const Spacer(),
            if ((t['completion_rate'] as num? ?? 0) > 0)
              Text('${(t['completion_rate'] as num).toStringAsFixed(0)}%', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: (t['completion_rate'] as num) >= 80 ? const Color(0xFF3fb950) : const Color(0xFF8b949e))),
          ]),
        ]),
      ),
    );
  }

  Widget _buildActivitySection() {
    if (_activity.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Recent Activity (${_activity.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFe6edf3))),
      const SizedBox(height: 8),
      ..._activity.take(20).map(_actTile),
    ]);
  }

  Widget _actTile(Map<String, dynamic> a) {
    final action = (a['action'] ?? '').toString();
    final msg = (a['message'] ?? '').toString();
    final team = (a['team_name'] ?? '').toString();
    return Padding(padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_actEmoji(action), style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (team.isNotEmpty) Text(team, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF58a6ff))),
          Text(msg, style: const TextStyle(fontSize: 11, color: Color(0xFFc9d1d9)), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        Text(_kstTime(a['created_at']?.toString()), style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: Color(0xFF8b949e))),
      ]),
    );
  }

  String _actEmoji(String a) {
    if (a.contains('ticket_created')) return '🎫';
    if (a.contains('status')) return '🔄';
    if (a.contains('spawn')) return '👾';
    if (a.contains('artifact')) return '📎';
    if (a.contains('feedback')) return '⭐';
    if (a.contains('team')) return '🏗️';
    if (a.contains('error')) return '❌';
    if (a.contains('progress')) return '▸';
    return '•';
  }

  String _fmtNum(num n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}억';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}만';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}천';
    return n.toString();
  }

  String _fmtKrw(num usd) {
    final krw = usd * _usdKrw;
    if (krw >= 10000) return '${(krw / 10000).toStringAsFixed(1)}만원';
    return '${krw.toStringAsFixed(0)}원';
  }

  Future<void> _showArchives() async {
    final api = context.read<ApiService>();
    final archives = await api.getArchives();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _ArchiveListPage(archives: archives)));
  }
}

class _ArchiveListPage extends StatelessWidget {
  final List<Map<String, dynamic>> archives;
  const _ArchiveListPage({required this.archives});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22), elevation: 0,
        title: Text('아카이브 (${archives.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
      body: archives.isEmpty
          ? const Center(child: Text('아카이브 없음', style: TextStyle(color: Color(0xFF8b949e))))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: archives.length,
              itemBuilder: (_, i) {
                final a = archives[i];
                final name = (a['name'] ?? a['team']?['name'] ?? '').toString();
                final total = (a['total_tickets'] ?? a['stats']?['total_tickets'] ?? 0) as num;
                final done = (a['done_tickets'] ?? a['stats']?['done_tickets'] ?? 0) as num;
                final pct = total > 0 ? (done / total * 100).round() : 0;
                final archivedAt = (a['archived_at'] ?? '').toString();
                final timeStr = archivedAt.length >= 10 ? archivedAt.substring(0, 10) : archivedAt;
                return ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: const Color(0xFF21262d), borderRadius: BorderRadius.circular(8)),
                    child: const Center(child: Text('📦', style: TextStyle(fontSize: 16))),
                  ),
                  title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFe6edf3))),
                  subtitle: Text('$done/$total 완료 ($pct%) · $timeStr',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8b949e))),
                  trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF484f58)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ArchiveDetailScreen(archive: a),
                  )),
                );
              },
            ),
    );
  }
}

class _KpiData {
  final String label, value;
  final IconData icon;
  final Color color;
  final String? sub;
  _KpiData(this.label, this.value, this.icon, this.color, {this.sub});
}

class _HeatmapPainter extends CustomPainter {
  final Map<String, dynamic> data;
  _HeatmapPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxVal = data.values.fold<int>(0, (m, v) => max(m, (v as num).toInt()));
    if (maxVal == 0) return;
    const cols = 48;
    const rows = 6;
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));

    for (final entry in data.entries) {
      try {
        final val = (entry.value as num).toInt();
        if (val == 0) continue;
        final dt = DateTime.parse('${entry.key}:00Z').add(const Duration(hours: 9));
        final diffMin = now.difference(dt).inMinutes;
        if (diffMin < 0 || diffMin > 48 * 60) continue;
        final col = cols - 1 - (diffMin ~/ 60);
        final row = (dt.minute ~/ 10);
        if (col < 0 || col >= cols || row < 0 || row >= rows) continue;
        final ratio = val / maxVal;
        Color c;
        if (ratio < 0.25) c = Color.lerp(const Color(0xFF0d1117), const Color(0xFF1B96FF), ratio * 4)!;
        else if (ratio < 0.6) c = Color.lerp(const Color(0xFF1B96FF), const Color(0xFFe3b341), (ratio - 0.25) / 0.35)!;
        else c = Color.lerp(const Color(0xFFe3b341), const Color(0xFFf85149), (ratio - 0.6) / 0.4)!;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(col * cellW + 0.5, row * cellH + 0.5, cellW - 1, cellH - 1), const Radius.circular(1)),
          Paint()..color = c,
        );
      } catch (_) {}
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
