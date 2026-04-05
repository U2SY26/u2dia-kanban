import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../kanban/agent_office_screen.dart';

/// 프로젝트 고도화 진행률 인터랙티브 오버뷰
class ProjectOverviewScreen extends StatefulWidget {
  final Function(String teamId, String teamName)? onTeamTap;
  const ProjectOverviewScreen({super.key, this.onTeamTap});
  @override
  State<ProjectOverviewScreen> createState() => _ProjectOverviewScreenState();
}

class _ProjectOverviewScreenState extends State<ProjectOverviewScreen>
    with TickerProviderStateMixin {
  List<_ProjectData> _projects = [];
  Map<String, dynamic> _globalStats = {};
  Map<String, dynamic> _sprintStats = {};
  Map<String, Map<String, dynamic>> _inventory = {};
  bool _loading = true;
  String? _expandedProject;
  String _drillTab = 'goals'; // 'goals' | 'tickets' | 'agents'
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  List<String> _visibleProjects = [];

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final results = await Future.wait([
      api.projectGoals(),
      api.globalStats(),
      api.sprintGlobalStats(),
      api.projectInventory(),
      api.getVisibleProjects(),
    ]);
    final goalsRes = results[0] as Map<String, dynamic>;
    final stats = results[1] as Map<String, dynamic>;
    final sprints = results[2] as Map<String, dynamic>;
    final invRes = results[3] as Map<String, dynamic>;
    final visRes = results[4] as Map<String, dynamic>;
    // 인벤토리 맵 구축
    final invMap = <String, Map<String, dynamic>>{};
    for (final p in ((invRes['projects'] as List?) ?? []).cast<Map<String, dynamic>>()) {
      invMap[(p['name'] ?? '').toString().toUpperCase()] = p;
      invMap[(p['name'] ?? '').toString()] = p;
    }
    // 표시 프로젝트 필터
    final visList = ((visRes['projects'] as List?) ?? []).cast<String>();

    // projectGoals 기반 프로젝트 매핑
    final goalsList = ((goalsRes['projects'] as List?) ?? []).cast<Map<String, dynamic>>();
    final mapped = <_ProjectData>[];
    for (final g in goalsList) {
      final name = (g['project'] ?? '').toString();
      if (name.isEmpty) continue;
      final p = _ProjectData(name: name);
      p.description = (g['description'] ?? '').toString();
      p.progress = ((g['progress'] as num?) ?? 0).toDouble();
      p.totalTickets = (g['total'] as int?) ?? 0;
      p.doneTickets = (g['done'] as int?) ?? 0;
      p.blockedTickets = (g['blocked'] as int?) ?? 0;
      p.inProgressTickets = (g['in_progress'] as int?) ?? 0;
      p.reviewTickets = (g['review'] as int?) ?? 0;
      p.activeTeams = (g['teams'] as int?) ?? 0;
      p.memberCount = (g['agents'] as int?) ?? 0;
      p.checklist = ((g['checklist'] as List?) ?? []).cast<Map<String, dynamic>>();
      p.goalTitle = (g['goal_title'] ?? '').toString();
      p.milestones = ((g['milestones'] as List?) ?? []).cast<Map<String, dynamic>>();
      p.remaining = (g['remaining'] as int?) ?? 0;
      p.archivedTeams = (g['archived_teams'] as int?) ?? 0;
      p.backlog = (g['backlog'] as int?) ?? 0;
      mapped.add(p);
    }

    var sortedProjects = mapped
      ..sort((a, b) {
        if (a.activeTeams != b.activeTeams) return b.activeTeams.compareTo(a.activeTeams);
        return b.progress.compareTo(a.progress);
      });
    // visible 필터 적용 (빈 목록 = 전체 표시)
    if (visList.isNotEmpty) {
      final visSet = visList.map((v) => v.toUpperCase()).toSet();
      sortedProjects = sortedProjects.where((p) => visSet.contains(p.name.toUpperCase())).toList();
    }

    if (mounted) {
      setState(() {
        _projects = sortedProjects;
        _globalStats = (stats['stats'] as Map<String, dynamic>?) ?? {};
        _sprintStats = sprints;
        _inventory = invMap;
        _visibleProjects = visList;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF1B96FF),
              child: CustomScrollView(
                slivers: [
                  _buildSliverHeader(),
                  _buildGlobalKpi(),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _buildProjectCard(_projects[i]),
                        childCount: _projects.length,
                      ),
                    ),
                  ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
                ],
              ),
            ),
    );
  }

  Widget _buildSliverHeader() {
    return SliverAppBar(
      backgroundColor: const Color(0xFF161b22),
      pinned: true,
      expandedHeight: 60,
      title: const Text('프로젝트 고도화 현황',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFe6edf3))),
      actions: [
        IconButton(
          icon: const Icon(Icons.tune, size: 20, color: Color(0xFF8b949e)),
          onPressed: _showProjectFilter,
          tooltip: '프로젝트 필터',
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20, color: Color(0xFF8b949e)),
          onPressed: _load,
        ),
      ],
    );
  }

  Widget _buildGlobalKpi() {
    final totalProjects = _projects.length;
    final activeTeams = _globalStats['active_teams'] ?? 0;
    final totalTickets = _globalStats['total_tickets'] ?? 0;
    final doneTickets = _globalStats['done_tickets'] ?? 0;
    final globalProgress = _globalStats['global_progress'] ?? 0;
    final activeSprints = _sprintStats['active_sprints'] ?? 0;
    final blocked = _globalStats['blocked_tickets'] ?? 0;

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161b22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF30363d)),
        ),
        child: Column(
          children: [
            // 전체 진행률 원형
            Row(
              children: [
                SizedBox(
                  width: 60, height: 60,
                  child: CustomPaint(
                    painter: _CircleProgressPainter(
                      progress: (globalProgress as num).toDouble() / 100,
                      color: const Color(0xFF4AC99B),
                      bgColor: const Color(0xFF30363d),
                    ),
                    child: Center(
                      child: Text('${(globalProgress as num).toInt()}%',
                          style: const TextStyle(color: Color(0xFF4AC99B), fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('전체 고도화 진행률',
                        style: TextStyle(color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('$totalProjects 프로젝트 · $activeTeams 팀 · $totalTickets 티켓 ($doneTickets 완료)',
                        style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Mini KPI row
            Row(children: [
              _miniKpi('Sprint', '$activeSprints', const Color(0xFF1B96FF)),
              _miniKpi('Blocked', '$blocked', blocked > 0 ? const Color(0xFFf85149) : const Color(0xFF4AC99B)),
              _miniKpi('Done', '$doneTickets', const Color(0xFF4AC99B)),
              _miniKpi('Total', '$totalTickets', const Color(0xFF8b949e)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _miniKpi(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
          Text(label, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
        ]),
      ),
    );
  }

  Widget _buildProjectCard(_ProjectData proj) {
    final isExpanded = _expandedProject == proj.name;
    final progressPct = proj.progress.round();
    final progress = proj.progress / 100;

    // 고도화 수준 결정
    final level = _sophisticationLevel(proj);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isExpanded ? const Color(0xFF1B96FF) : const Color(0xFF30363d)),
      ),
      child: Column(children: [
        // Header
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showProjectPopup(proj),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                // 고도화 레벨 뱃지
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: level.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Text(level.icon, style: const TextStyle(fontSize: 18))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(proj.name,
                        style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 14, fontWeight: FontWeight.w700)),
                    if (proj.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(proj.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
                    ],
                    if (proj.goalTitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('\u{1F3AF} ${proj.goalTitle}', style: const TextStyle(color: Color(0xFF4AC99B), fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 3),
                    Wrap(spacing: 3, runSpacing: 2, children: [
                      _tagBadge('${proj.activeTeams} 팀', const Color(0xFF1B96FF)),
                      _tagBadge('${proj.memberCount} agents', const Color(0xFF7c3aed)),
                      Builder(builder: (_) {
                        final inv = _findInventory(proj.name);
                        final skillCnt = (inv['skill_count'] as int?) ?? 0;
                        final mcpList = ((inv['mcp_servers'] as List?) ?? []).cast<String>();
                        return Row(mainAxisSize: MainAxisSize.min, children: [
                          if (skillCnt > 0) _tagBadge('$skillCnt skills', const Color(0xFFf0883e)),
                          if (mcpList.isNotEmpty) _tagBadge('MCP:${mcpList.length}', const Color(0xFF4AC99B)),
                        ]);
                      }),
                    ]),
                  ]),
                ),
                // 진행률
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${proj.progress.toInt()}%',
                      style: TextStyle(
                        color: proj.progress >= 80 ? const Color(0xFF4AC99B) : const Color(0xFF1B96FF),
                        fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('${proj.doneTickets}/${proj.totalTickets} done',
                      style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
                  if (proj.remaining > 0)
                    Text('${proj.remaining} remaining', style: const TextStyle(color: Color(0xFFf0883e), fontSize: 8)),
                ]),
                const SizedBox(width: 4),
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF8b949e), size: 20),
              ]),
              const SizedBox(height: 8),
              // Progress bar (colored by actual status)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: Row(children: [
                    _barSegment(proj.doneTickets, proj.totalTickets, const Color(0xFF4AC99B)),
                    _barSegment(proj.inProgressTickets, proj.totalTickets, const Color(0xFF1B96FF)),
                    _barSegment(proj.reviewTickets, proj.totalTickets, const Color(0xFFf0883e)),
                    _barSegment(proj.blockedTickets, proj.totalTickets, const Color(0xFFf85149)),
                    Expanded(child: Container(color: const Color(0xFF30363d))),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              // Legend
              Row(children: [
                _legendDot('Done ${proj.doneTickets}', const Color(0xFF4AC99B)),
                _legendDot('WIP ${proj.inProgressTickets}', const Color(0xFF1B96FF)),
                _legendDot('Review ${proj.reviewTickets}', const Color(0xFFf0883e)),
                if (proj.blockedTickets > 0) _legendDot('Block ${proj.blockedTickets}', const Color(0xFFf85149)),
              ]),
              if (proj.archivedTeams > 0) ...[
                const SizedBox(height: 2),
                Text('\u{1F4E6} ${proj.archivedTeams} archived teams \u{00B7} ${proj.activeTeams} active',
                    style: const TextStyle(color: Color(0xFF484f58), fontSize: 8)),
              ],
            ]),
          ),
        ),
        // Expanded: checklist drill-down
        if (isExpanded) ...[
          // 올라마 요청 버튼 바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF30363d)))),
            child: Row(children: [
              Expanded(child: InkWell(
                onTap: () => _askOllama(proj.name, '팀 구성하고 티켓 발행해줘. 프로젝트 스캔 후 필요한 작업 분해해서'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFF1B96FF).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('🤖', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 4),
                    Text('팀+티켓 구성 요청', style: TextStyle(color: Color(0xFF1B96FF), fontSize: 10, fontWeight: FontWeight.w600)),
                  ]),
                ),
              )),
              const SizedBox(width: 6),
              Expanded(child: InkWell(
                onTap: () => _askOllama(proj.name, '현재 상태 분석하고 다음 우선순위 알려줘'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFF22c55e).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('📊', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 4),
                    Text('상태 분석 요청', style: TextStyle(color: Color(0xFF22c55e), fontSize: 10, fontWeight: FontWeight.w600)),
                  ]),
                ),
              )),
            ]),
          ),
          // Navigation buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              Expanded(child: _navButton('Office', () {
                if (proj.checklist.isNotEmpty) {
                  final teamId = proj.checklist.first['team_id'] as String? ?? '';
                  if (teamId.isNotEmpty) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AgentOfficeScreen(teamId: teamId, teamName: proj.name),
                    ));
                  }
                }
              })),
              const SizedBox(width: 4),
              Expanded(child: _navButton('히스토리', () {
                if (proj.checklist.isNotEmpty) {
                  final teamId = proj.checklist.first['team_id'] as String? ?? '';
                  if (teamId.isNotEmpty) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _TeamHistoryPage(teamId: teamId, teamName: proj.name),
                    ));
                  }
                }
              })),
              const SizedBox(width: 4),
              Expanded(child: _navButton('스프린트', () {
                if (proj.checklist.isNotEmpty) {
                  final teamId = proj.checklist.first['team_id'] as String? ?? '';
                  if (teamId.isNotEmpty) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _SprintListPage(teamId: teamId, teamName: proj.name),
                    ));
                  }
                }
              })),
            ]),
          ),
          // Tab bar
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF21262d)))),
            child: Row(children: [
              _drillTabBtn('goals', '목표/로드맵', Icons.flag_outlined),
              _drillTabBtn('tickets', '체크리스트', Icons.check_box_outlined),
              _drillTabBtn('agents', '에이전트/스킬', Icons.smart_toy_outlined),
            ]),
          ),
          if (_drillTab == 'goals') _buildGoalsView(proj),
          if (_drillTab == 'tickets') _buildChecklistView(proj),
          if (_drillTab == 'agents') _buildInventoryView(proj),
        ],
      ]),
    );
  }

  Widget _buildGoalsView(_ProjectData proj) {
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF30363d)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 비전/목표
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          color: const Color(0xFF0d1117),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.flag, size: 14, color: Color(0xFF4AC99B)),
              SizedBox(width: 6),
              Text('프로젝트 목표', style: TextStyle(color: Color(0xFF4AC99B), fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            if (proj.goalTitle.isNotEmpty)
              Text(proj.goalTitle,
                  style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w600, height: 1.4))
            else
              InkWell(
                onTap: () => _showGoalRegisterDialog(proj),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B96FF).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1B96FF).withOpacity(0.3), style: BorderStyle.solid),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF1B96FF)),
                    SizedBox(width: 6),
                    Text('목표 설정하기', style: TextStyle(color: Color(0xFF1B96FF), fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ]),
        ),
        // 마일스톤 로드맵
        if (proj.milestones.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(children: [
              const Icon(Icons.timeline, size: 14, color: Color(0xFF1B96FF)),
              const SizedBox(width: 6),
              const Text('로드맵', style: TextStyle(color: Color(0xFF1B96FF), fontSize: 11, fontWeight: FontWeight.w700)),
              const Spacer(),
              Builder(builder: (_) {
                final done = proj.milestones.where((m) => m['done'] == true).length;
                return Text('$done/${proj.milestones.length} 완료',
                    style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10));
              }),
            ]),
          ),
          ...List.generate(proj.milestones.length, (i) {
            final m = proj.milestones[i];
            final isDone = m['done'] == true;
            final isLast = i == proj.milestones.length - 1;
            return GestureDetector(
              onTap: () async {
                final api = context.read<ApiService>();
                final newMilestones = List<Map<String, dynamic>>.from(proj.milestones);
                newMilestones[i] = {...newMilestones[i], 'done': !(m['done'] == true)};
                await api.registerProjectGoal(proj.name, proj.goalTitle, newMilestones);
                _load();
              },
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // 타임라인 도트 + 라인
                SizedBox(width: 24, child: Column(children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(
                    color: isDone ? const Color(0xFF4AC99B) : const Color(0xFF30363d),
                    shape: BoxShape.circle,
                    border: Border.all(color: isDone ? const Color(0xFF4AC99B) : const Color(0xFF484f58), width: 2),
                  ), child: isDone ? const Icon(Icons.check, size: 8, color: Colors.white) : null),
                  if (!isLast) Container(width: 2, height: 28, color: isDone ? const Color(0xFF4AC99B).withOpacity(0.3) : const Color(0xFF30363d)),
                ])),
                const SizedBox(width: 8),
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(m['title']?.toString() ?? '',
                    style: TextStyle(
                      color: isDone ? const Color(0xFF8b949e) : const Color(0xFFe6edf3),
                      fontSize: 12, height: 1.3,
                      decoration: isDone ? TextDecoration.lineThrough : null)),
                )),
              ]),
            ));
          }),
        ] else ...[
          // 마일스톤 없을 때
          Container(
            padding: const EdgeInsets.all(14),
            child: InkWell(
              onTap: () => _showGoalRegisterDialog(proj),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF21262d),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add, size: 14, color: Color(0xFF8b949e)),
                  SizedBox(width: 4),
                  Text('마일스톤 추가', style: TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
                ]),
              ),
            ),
          ),
        ],
        // 현재 진행 요약
        Container(
          margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF161b22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363d)),
          ),
          child: Row(children: [
            Expanded(child: _goalKpi('진행률', '${proj.progress.toInt()}%', const Color(0xFF1B96FF))),
            Container(width: 1, height: 24, color: const Color(0xFF30363d)),
            Expanded(child: _goalKpi('잔여', '${proj.remaining}', const Color(0xFFf0883e))),
            Container(width: 1, height: 24, color: const Color(0xFF30363d)),
            Expanded(child: _goalKpi('팀', '${proj.activeTeams}', const Color(0xFF7c3aed))),
            Container(width: 1, height: 24, color: const Color(0xFF30363d)),
            Expanded(child: _goalKpi('완료', '${proj.doneTickets}', const Color(0xFF4AC99B))),
          ]),
        ),
      ]),
    );
  }

  Widget _goalKpi(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
    ]);
  }

  void _showGoalRegisterDialog(_ProjectData proj) {
    final goalCtrl = TextEditingController(text: proj.goalTitle);
    final msCtrl = TextEditingController(
      text: proj.milestones.map((m) => m['title']?.toString() ?? '').join('\n'),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161b22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF30363d))),
        title: Text('${proj.name} 목표 설정', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 14)),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: goalCtrl,
              style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13),
              decoration: InputDecoration(
                labelText: '프로젝트 목표',
                labelStyle: const TextStyle(color: Color(0xFF8b949e), fontSize: 12),
                hintText: '예: AI 커머스 플랫폼 상용화',
                hintStyle: const TextStyle(color: Color(0xFF484f58), fontSize: 11),
                filled: true, fillColor: const Color(0xFF0d1117),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363d))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363d))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: msCtrl, maxLines: 5,
              style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12),
              decoration: InputDecoration(
                labelText: '마일스톤 (한 줄에 하나)',
                labelStyle: const TextStyle(color: Color(0xFF8b949e), fontSize: 12),
                hintText: 'Phase 1: 설계\nPhase 2: 개발\nPhase 3: 출시',
                hintStyle: const TextStyle(color: Color(0xFF484f58), fontSize: 11),
                filled: true, fillColor: const Color(0xFF0d1117),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363d))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363d))),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Color(0xFF8b949e)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B96FF)),
            onPressed: () async {
              final goal = goalCtrl.text.trim();
              if (goal.isEmpty) return;
              final lines = msCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
              final milestones = lines.map((l) => {'title': l.trim(), 'done': false}).toList();
              final api = context.read<ApiService>();
              await api.registerProjectGoal(proj.name, goal, milestones.cast<Map<String, dynamic>>());
              if (mounted) { Navigator.pop(ctx); _load(); }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistView(_ProjectData proj) {
    final checklist = proj.checklist;
    if (checklist.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF30363d)))),
        child: const Center(child: Text('체크리스트 없음', style: TextStyle(color: Color(0xFF8b949e), fontSize: 12))),
      );
    }

    // 우선순위별 그룹핑
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final tk in checklist) {
      final priority = (tk['priority'] ?? 'Medium') as String;
      grouped.putIfAbsent(priority, () => []).add(tk);
    }
    final priorityOrder = ['Critical', 'High', 'Medium', 'Low'];
    final priColors = {
      'Critical': const Color(0xFFf85149), 'High': const Color(0xFFf0883e),
      'Medium': const Color(0xFF1B96FF), 'Low': const Color(0xFF8b949e),
    };

    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF30363d)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 요약 바
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF0d1117),
          child: Row(children: [
            Text('${checklist.length} 항목', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 11, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${proj.activeTeams} 팀', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
            const SizedBox(width: 8),
            Text('${proj.memberCount} 에이전트', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
          ]),
        ),
        // 체크리스트 by priority
        ...priorityOrder.where((p) => grouped.containsKey(p)).map((priority) {
          final tks = grouped[priority]!;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(
                  color: priColors[priority], shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('$priority (${tks.length})', style: TextStyle(
                  color: priColors[priority], fontSize: 10, fontWeight: FontWeight.w700)),
              ]),
            ),
            ...tks.map((tk) => _ticketCheckbox(tk)),
          ]);
        }),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _ticketCheckbox(Map<String, dynamic> tk) {
    final isDone = tk['done'] == true || tk['status'] == 'Done';
    final status = (tk['status'] ?? '').toString();
    final isBlocked = status == 'Blocked';
    final isReview = status == 'Review';
    final isWip = status == 'InProgress';
    final team = (tk['team'] ?? '').toString();

    Color statusColor = const Color(0xFF8b949e);
    IconData statusIcon = Icons.check_box_outline_blank;
    if (isDone) { statusColor = const Color(0xFF4AC99B); statusIcon = Icons.check_box; }
    else if (isBlocked) { statusColor = const Color(0xFFf85149); statusIcon = Icons.disabled_by_default; }
    else if (isReview) { statusColor = const Color(0xFFf0883e); statusIcon = Icons.rate_review; }
    else if (isWip) { statusColor = const Color(0xFF1B96FF); statusIcon = Icons.indeterminate_check_box; }

    return InkWell(
      onTap: () {
        if (tk['team_id'] != null) {
          _showTeamPopup(tk['team_id'] as String, tk['team_name']?.toString() ?? tk['team']?.toString() ?? '');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tk['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: isDone ? const Color(0xFF8b949e) : const Color(0xFFe6edf3),
                    fontSize: 11, decoration: isDone ? TextDecoration.lineThrough : null)),
            Row(children: [
              Text(tk['id'] ?? tk['ticket_id'] ?? '', style: const TextStyle(color: Color(0xFF484f58), fontSize: 9, fontFamily: 'monospace')),
              if (team.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(team, style: const TextStyle(color: Color(0xFF7c3aed), fontSize: 8)),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }

  void _showProjectFilter() async {
    final api = context.read<ApiService>();
    // 전체 프로젝트 그룹 수집
    final allGroups = _projects.map((p) => p.name).toList();
    // 인벤토리에서도 추가
    for (final inv in _inventory.values) {
      final name = (inv['name'] ?? '').toString();
      if (name.isNotEmpty && !allGroups.contains(name.toUpperCase())) {
        allGroups.add(name.toUpperCase());
      }
    }
    final uniqueGroups = allGroups.toSet().toList()..sort();
    final selected = Set<String>.from(_visibleProjects.map((v) => v.toUpperCase()));
    final allMode = selected.isEmpty;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDlg) {
          return AlertDialog(
            backgroundColor: const Color(0xFF161b22),
            title: const Text('프로젝트 표시 설정', style: TextStyle(color: Color(0xFFe6edf3), fontSize: 14)),
            content: SizedBox(
              width: 300,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CheckboxListTile(
                  value: selected.isEmpty,
                  onChanged: (v) => setDlg(() { if (v == true) selected.clear(); }),
                  title: const Text('전체 표시', style: TextStyle(color: Color(0xFFe6edf3), fontSize: 12)),
                  activeColor: const Color(0xFF1B96FF),
                  dense: true,
                ),
                const Divider(color: Color(0xFF30363d), height: 1),
                SizedBox(
                  height: 300,
                  child: ListView(children: uniqueGroups.map((g) =>
                    CheckboxListTile(
                      value: selected.contains(g),
                      onChanged: (v) => setDlg(() {
                        if (v == true) selected.add(g); else selected.remove(g);
                      }),
                      title: Text(g, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 11)),
                      dense: true,
                      activeColor: const Color(0xFF1B96FF),
                    ),
                  ).toList()),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소', style: TextStyle(color: Color(0xFF8b949e))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B96FF)),
                onPressed: () async {
                  final list = selected.toList();
                  await api.setVisibleProjects(list);
                  if (mounted) { Navigator.pop(ctx); _load(); }
                },
                child: const Text('저장'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _drillTabBtn(String tab, String label, IconData icon) {
    final active = _drillTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _drillTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: active ? const Color(0xFF1B96FF) : Colors.transparent, width: 2)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14, color: active ? const Color(0xFF1B96FF) : const Color(0xFF8b949e)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              color: active ? const Color(0xFF1B96FF) : const Color(0xFF8b949e),
              fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }

  Map<String, dynamic> _findInventory(String projName) {
    // 프로젝트 별칭 매핑 (goals 이름 → 인벤토리 폴더명)
    const aliases = {
      'U2DIA AI': 'PMI-LINK-GLOBAL',
      'U2DIA Commerce AI': 'e-commerceAI',
      'PMI LINK GLOBAL': 'PMI-LINK-GLOBAL',
      'U2DIA-SIMULATOR': 'u2dia_simulator',
      'E-COMMERCE-AI': 'e-commerceAI',
      'PARTICLE-MODEL': 'u2dia_particlemodel',
      'Gemma4 Particle Edu': 'gemma4-particle-edu',
      'U2DIA-CS': 'U2DIA-KANBAN-BOARD',
    };
    // 별칭으로 먼저 시도
    final aliased = aliases[projName];
    if (aliased != null && _inventory.containsKey(aliased)) return _inventory[aliased]!;
    // 정확 매칭
    if (_inventory.containsKey(projName)) return _inventory[projName]!;
    if (_inventory.containsKey(projName.toUpperCase())) return _inventory[projName.toUpperCase()]!;
    // fuzzy 매칭 (하이픈/공백/대소문자/언더스코어 무시)
    final norm = projName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final entry in _inventory.entries) {
      final k = entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (k == norm || k.contains(norm) || norm.contains(k)) return entry.value;
    }
    return {};
  }

  void _showProjectPopup(_ProjectData proj) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF161b22),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 8),
              decoration: BoxDecoration(color: const Color(0xFF30363d), borderRadius: BorderRadius.circular(2))),
            // 프로젝트 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(proj.name, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 16, fontWeight: FontWeight.w700)),
                  if (proj.goalTitle.isNotEmpty)
                    Text(proj.goalTitle, style: const TextStyle(color: Color(0xFF4AC99B), fontSize: 11)),
                ])),
                Text('${proj.progress.toInt()}%', style: TextStyle(
                  color: proj.progress >= 80 ? const Color(0xFF4AC99B) : const Color(0xFF1B96FF),
                  fontSize: 22, fontWeight: FontWeight.w800)),
              ]),
            ),
            // 탭 바
            _ProjectPopupTabs(proj: proj, scrollController: scroll,
              inventory: _findInventory(proj.name),
              onTeamTap: widget.onTeamTap,
              onGoalRegister: () => _showGoalRegisterDialog(proj)),
          ]),
        ),
      ),
    );
  }

  void _askOllama(String projName, String request) {
    final api = context.read<ApiService>();
    // Navigate back to home and show snackbar directing to chat tab
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🤖 유디 탭에서 응답을 확인하세요'), duration: Duration(seconds: 2)),
    );
    // Fire the message to chat API so it appears in chat history
    api.post('/api/agent/chat', {
      'message': '$projName 프로젝트에 $request',
      'session_id': 'app-main',
    });
  }

  void _showTeamPopup(String teamId, String teamName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF161b22),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(children: [
            // Handle
            Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 8),
              decoration: BoxDecoration(color: const Color(0xFF30363d), borderRadius: BorderRadius.circular(2))),
            // Team header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                const Icon(Icons.view_kanban, size: 18, color: Color(0xFF1B96FF)),
                const SizedBox(width: 8),
                Expanded(child: Text(teamName, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 14, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis)),
                // Open full kanban button
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (widget.onTeamTap != null) widget.onTeamTap!(teamId, teamName);
                  },
                  icon: const Icon(Icons.open_in_full, size: 14, color: Color(0xFF8b949e)),
                  label: const Text('전체 보기', style: TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ]),
            ),
            // Office 버튼 + Agent 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AgentOfficeScreen(teamId: teamId, teamName: teamName))); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF1B96FF).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.meeting_room, size: 14, color: Color(0xFF58a6ff)),
                      SizedBox(width: 4),
                      Text('Office', style: TextStyle(color: Color(0xFF58a6ff), fontSize: 10, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                )),
              ]),
            ),
            const Divider(height: 1, color: Color(0xFF30363d)),
            // 탭: 티켓 + 에이전트
            Expanded(child: _TeamPopupTabs(teamId: teamId, scrollController: scroll)),
          ]),
        ),
      ),
    );
  }

  Widget _buildInventoryView(_ProjectData proj) {
    final inv = _findInventory(proj.name);
    final agents = ((inv['agents'] as List?) ?? []).cast<Map<String, dynamic>>();
    final skills = ((inv['skills'] as List?) ?? []).cast<Map<String, dynamic>>();
    final mcpServers = ((inv['mcp_servers'] as List?) ?? []).cast<String>();

    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF30363d)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 요약 바
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF0d1117),
          child: Row(children: [
            const Icon(Icons.smart_toy, size: 12, color: Color(0xFF7c3aed)),
            const SizedBox(width: 4),
            Text('전문가 ${agents.length}명', style: const TextStyle(color: Color(0xFF7c3aed), fontSize: 10, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            const Icon(Icons.auto_awesome, size: 12, color: Color(0xFFf0883e)),
            const SizedBox(width: 4),
            Text('스킬 ${skills.length}개', style: const TextStyle(color: Color(0xFFf0883e), fontSize: 10, fontWeight: FontWeight.w700)),
            if (mcpServers.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text('MCP ${mcpServers.length}', style: const TextStyle(color: Color(0xFF4AC99B), fontSize: 10)),
            ],
            const Spacer(),
            Text('칸반: ${proj.memberCount}명 활성', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
          ]),
        ),
        // 에이전트 목록
        if (agents.isNotEmpty) ...[
          ...agents.map((a) {
            final name = a['name']?.toString() ?? '';
            final desc = a['description']?.toString() ?? '';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Row(children: [
                Container(width: 24, height: 24,
                  decoration: BoxDecoration(color: const Color(0xFF7c3aed).withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                  child: const Center(child: Icon(Icons.smart_toy, size: 12, color: Color(0xFF7c3aed)))),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 11, fontWeight: FontWeight.w600)),
                  if (desc.isNotEmpty)
                    Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
                ])),
              ]),
            );
          }),
        ] else
          const Padding(padding: EdgeInsets.all(16),
            child: Center(child: Text('에이전트 미등록', style: TextStyle(color: Color(0xFF8b949e), fontSize: 11)))),
        // 스킬 목록
        if (skills.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text('스킬 (${skills.length})', style: const TextStyle(color: Color(0xFFf0883e), fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(spacing: 4, runSpacing: 4, children: skills.map((s) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFf0883e).withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
              child: Text(s['name']?.toString() ?? '', style: const TextStyle(color: Color(0xFFf0883e), fontSize: 9)),
            )).toList()),
          ),
        ],
        // MCP
        if (mcpServers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(spacing: 4, children: mcpServers.map((s) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF4AC99B).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text('MCP: $s', style: const TextStyle(color: Color(0xFF4AC99B), fontSize: 9)),
            )).toList()),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _barSegment(int count, int total, Color color) {
    if (total == 0 || count == 0) return const SizedBox.shrink();
    return Flexible(
      flex: count,
      child: Container(color: color),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
      ]),
    );
  }

  Widget _tagBadge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10)),
    );
  }

  Widget _navButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF21262d),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Center(child: Text(label, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9))),
      ),
    );
  }

  _SophisticationLevel _sophisticationLevel(_ProjectData proj) {
    final p = proj.progress;
    if (p >= 90) return _SophisticationLevel('🏆', 'Production', const Color(0xFF4AC99B));
    if (p >= 70) return _SophisticationLevel('🚀', 'Advanced', const Color(0xFF1B96FF));
    if (p >= 40) return _SophisticationLevel('🔨', 'Building', const Color(0xFFf0883e));
    if (p >= 10) return _SophisticationLevel('📋', 'Planning', const Color(0xFF7c3aed));
    return _SophisticationLevel('💡', 'Init', const Color(0xFF8b949e));
  }
}

class _ProjectData {
  final String name;
  String description = '';
  double progress = 0.0;
  int activeTeams = 0;
  int totalTickets = 0;
  int doneTickets = 0;
  int memberCount = 0;
  int blockedTickets = 0;
  int reviewTickets = 0;
  int inProgressTickets = 0;
  List<Map<String, dynamic>> checklist = [];
  String goalTitle = '';
  List<Map<String, dynamic>> milestones = [];
  int remaining = 0;
  int archivedTeams = 0;
  int backlog = 0;
  _ProjectData({required this.name});
}

class _SophisticationLevel {
  final String icon;
  final String label;
  final Color color;
  _SophisticationLevel(this.icon, this.label, this.color);
}

class _CircleProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color bgColor;
  _CircleProgressPainter({required this.progress, required this.color, required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 3;
    final bgPaint = Paint()..color = bgColor..style = PaintingStyle.stroke..strokeWidth = 4;
    final fgPaint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -pi / 2, 2 * pi * progress, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _TeamHistoryPage extends StatefulWidget {
  final String teamId, teamName;
  const _TeamHistoryPage({required this.teamId, required this.teamName});
  @override State<_TeamHistoryPage> createState() => _TeamHistoryPageState();
}

class _TeamHistoryPageState extends State<_TeamHistoryPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final res = await api.teamHistory(widget.teamId);
    if (mounted) setState(() { _items = ((res['history'] as List?) ?? []).cast<Map<String, dynamic>>(); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(title: Text('${widget.teamName} 히스토리', style: const TextStyle(fontSize: 14)), backgroundColor: const Color(0xFF161b22)),
      body: _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)))
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final h = _items[i];
              final type = h['type'] ?? '';
              final icon = type == 'artifact' ? '📎' : type == 'message' ? '💬' : '📝';
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF161b22), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF30363d))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(icon, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    Text(h['action'] ?? '', style: const TextStyle(color: Color(0xFF1B96FF), fontSize: 10, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text((h['created_at'] ?? '').toString().substring(0, min(16, (h['created_at'] ?? '').toString().length)), style: const TextStyle(color: Color(0xFF484f58), fontSize: 9)),
                  ]),
                  if ((h['message'] ?? '').toString().isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text(h['message'].toString(), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10))),
                ]),
              );
            },
          ),
    );
  }
}

class _ArchiveListPage extends StatefulWidget {
  const _ArchiveListPage();
  @override State<_ArchiveListPage> createState() => _ArchiveListPageState();
}

class _ArchiveListPageState extends State<_ArchiveListPage> {
  List<Map<String, dynamic>> _archives = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final res = await api.getArchives();
    if (mounted) setState(() { _archives = res; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(title: Text('아카이브 (${_archives.length})', style: const TextStyle(fontSize: 14)), backgroundColor: const Color(0xFF161b22)),
      body: _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)))
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _archives.length,
            itemBuilder: (_, i) {
              final a = _archives[i];
              final team = (a['team'] as Map<String, dynamic>?) ?? a;
              final name = team['name'] ?? '';
              final pg = team['project_group'] ?? '';
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF161b22), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF30363d))),
                child: Row(children: [
                  const Icon(Icons.archive_outlined, size: 16, color: Color(0xFF8b949e)),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.toString(), style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w600)),
                    if (pg.toString().isNotEmpty) Text(pg.toString(), style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
                  ])),
                ]),
              );
            },
          ),
    );
  }
}

class _SprintListPage extends StatefulWidget {
  final String teamId, teamName;
  const _SprintListPage({required this.teamId, required this.teamName});
  @override State<_SprintListPage> createState() => _SprintListPageState();
}

class _SprintListPageState extends State<_SprintListPage> {
  List<Map<String, dynamic>> _sprints = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final res = await api.sprintList(widget.teamId);
    if (mounted) setState(() { _sprints = res; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final phases = ['Think','Plan','Build','Review','Test','Ship','Reflect'];
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(title: Text('${widget.teamName} 스프린트', style: const TextStyle(fontSize: 14)), backgroundColor: const Color(0xFF161b22)),
      body: _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)))
        : _sprints.isEmpty
          ? const Center(child: Text('스프린트 없음', style: TextStyle(color: Color(0xFF8b949e))))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _sprints.length,
              itemBuilder: (_, i) {
                final s = _sprints[i];
                final phase = s['phase'] ?? 'Think';
                final phaseIdx = phases.indexOf(phase);
                final pct = ((phaseIdx + 1) / phases.length * 100).toInt();
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF161b22), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF30363d))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(s['name'] ?? '', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(s['status'] ?? '', style: TextStyle(color: s['status'] == 'Active' ? const Color(0xFF4AC99B) : const Color(0xFF8b949e), fontSize: 10)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
                      value: pct / 100, minHeight: 4,
                      backgroundColor: const Color(0xFF30363d),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF1B96FF)),
                    )),
                    const SizedBox(height: 4),
                    Text('Phase: $phase ($pct%)', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
                  ]),
                );
              },
            ),
    );
  }
}

class _TeamPopupTabs extends StatefulWidget {
  final String teamId;
  final ScrollController scrollController;
  const _TeamPopupTabs({required this.teamId, required this.scrollController});
  @override State<_TeamPopupTabs> createState() => _TeamPopupTabsState();
}

class _TeamPopupTabsState extends State<_TeamPopupTabs> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF21262d)))),
        child: Row(children: [
          _tb('티켓', Icons.confirmation_number_outlined, 0),
          _tb('에이전트', Icons.smart_toy_outlined, 1),
        ]),
      ),
      Expanded(child: _tab == 0
          ? _TeamPopupBody(teamId: widget.teamId, scrollController: widget.scrollController)
          : _AgentListBody(teamId: widget.teamId, scrollController: widget.scrollController)),
    ]);
  }
  Widget _tb(String l, IconData ic, int idx) {
    final a = _tab == idx;
    return Expanded(child: InkWell(
      onTap: () => setState(() => _tab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: a ? const Color(0xFF1B96FF) : Colors.transparent, width: 2))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(ic, size: 14, color: a ? const Color(0xFF1B96FF) : const Color(0xFF8b949e)),
          const SizedBox(width: 4),
          Text(l, style: TextStyle(color: a ? const Color(0xFF1B96FF) : const Color(0xFF8b949e), fontSize: 11, fontWeight: a ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    ));
  }
}

class _AgentListBody extends StatefulWidget {
  final String teamId;
  final ScrollController scrollController;
  const _AgentListBody({required this.teamId, required this.scrollController});
  @override State<_AgentListBody> createState() => _AgentListBodyState();
}

class _AgentListBodyState extends State<_AgentListBody> {
  List<Map<String, dynamic>> _agents = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final res = await api.teamSpecialists(widget.teamId);
    if (mounted) setState(() {
      _agents = ((res['agents'] as List?) ?? []).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)));
    if (_agents.isEmpty) return const Center(child: Text('에이전트 없음', style: TextStyle(color: Color(0xFF8b949e))));
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _agents.length,
      itemBuilder: (_, i) => _agentCard(_agents[i]),
    );
  }

  Widget _agentCard(Map<String, dynamic> a) {
    final name = a['display_name']?.toString() ?? '';
    final role = a['role']?.toString() ?? 'general';
    final status = a['status']?.toString() ?? 'Idle';
    final kpi = (a['kpi'] as Map<String, dynamic>?) ?? {};
    final done = kpi['done'] ?? 0;
    final total = kpi['total_claimed'] ?? 0;
    final rate = kpi['completion_rate'] ?? 0;
    final avg = kpi['avg_score'] ?? 0;
    final isWorking = status == 'Working';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0d1117), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isWorking ? const Color(0xFF1B96FF).withOpacity(0.4) : const Color(0xFF30363d)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(
              color: isWorking ? const Color(0xFF1B96FF).withOpacity(0.15) : const Color(0xFF21262d),
              borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(isWorking ? '💻' : '😎', style: const TextStyle(fontSize: 16)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w600)),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFF7c3aed).withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
                child: Text(role, style: const TextStyle(color: Color(0xFFa371f7), fontSize: 9)),
              ),
              const SizedBox(width: 6),
              Container(width: 6, height: 6, decoration: BoxDecoration(
                color: isWorking ? const Color(0xFF1B96FF) : const Color(0xFF8b949e), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(isWorking ? '작업 중' : '대기', style: TextStyle(
                color: isWorking ? const Color(0xFF1B96FF) : const Color(0xFF8b949e), fontSize: 9)),
            ]),
          ])),
          // KPI 미니
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$done/$total', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
            Text('$rate%', style: TextStyle(
              color: rate >= 80 ? const Color(0xFF4AC99B) : const Color(0xFF8b949e), fontSize: 10)),
          ]),
        ]),
        if (avg > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('QA 평균: ', style: TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
            ...List.generate(5, (i) => Icon(
              i < avg.round() ? Icons.star : Icons.star_border,
              size: 12, color: i < avg.round() ? const Color(0xFFe4a201) : const Color(0xFF30363d))),
            Text(' $avg', style: const TextStyle(color: Color(0xFFe4a201), fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        ],
      ]),
    );
  }
}

class _ProjectPopupTabs extends StatefulWidget {
  final _ProjectData proj;
  final ScrollController scrollController;
  final Map<String, dynamic> inventory;
  final Function(String, String)? onTeamTap;
  final VoidCallback onGoalRegister;
  const _ProjectPopupTabs({required this.proj, required this.scrollController, required this.inventory, this.onTeamTap, required this.onGoalRegister});
  @override State<_ProjectPopupTabs> createState() => _ProjectPopupTabsState();
}

class _ProjectPopupTabsState extends State<_ProjectPopupTabs> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final inv = widget.inventory;
    final agents = ((inv['agents'] as List?) ?? []).cast<Map<String, dynamic>>();
    final skills = ((inv['skills'] as List?) ?? []).cast<Map<String, dynamic>>();

    return Expanded(child: Column(children: [
      Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF30363d)), bottom: BorderSide(color: Color(0xFF30363d)))),
        child: Row(children: [
          _tb('에이전트 (${agents.length})', Icons.smart_toy_outlined, 0),
          _tb('스킬 (${skills.length})', Icons.auto_awesome, 1),
          _tb('목표', Icons.flag_outlined, 2),
        ]),
      ),
      Expanded(child: ListView(controller: widget.scrollController, children: [
        if (_tab == 0) _agentsTab(agents),
        if (_tab == 1) _skillsTab(skills),
        if (_tab == 2) _goalsTab(),
      ])),
    ]));
  }

  Widget _tb(String l, IconData ic, int idx) {
    final a = _tab == idx;
    return Expanded(child: InkWell(
      onTap: () => setState(() => _tab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: a ? const Color(0xFF1B96FF) : Colors.transparent, width: 2))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(ic, size: 13, color: a ? const Color(0xFF1B96FF) : const Color(0xFF8b949e)),
          const SizedBox(width: 4),
          Flexible(child: Text(l, style: TextStyle(color: a ? const Color(0xFF1B96FF) : const Color(0xFF8b949e), fontSize: 10, fontWeight: a ? FontWeight.w700 : FontWeight.w400), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    ));
  }

  Widget _agentsTab(List<Map<String, dynamic>> agents) {
    if (agents.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('에이전트 미등록', style: TextStyle(color: Color(0xFF8b949e)))));
    return Column(children: agents.map((a) {
      final name = a['name']?.toString() ?? '';
      final desc = a['description']?.toString() ?? '';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Container(width: 28, height: 28,
            decoration: BoxDecoration(color: const Color(0xFF7c3aed).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: const Center(child: Icon(Icons.smart_toy, size: 14, color: Color(0xFF7c3aed)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w600)),
            if (desc.isNotEmpty) Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9, height: 1.3)),
          ])),
        ]),
      );
    }).toList());
  }

  Widget _skillsTab(List<Map<String, dynamic>> skills) {
    if (skills.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('스킬 미등록', style: TextStyle(color: Color(0xFF8b949e)))));
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(spacing: 6, runSpacing: 6, children: skills.map((s) {
        final name = s['name']?.toString() ?? '';
        final desc = s['description']?.toString() ?? '';
        return Tooltip(
          message: desc,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFf0883e).withOpacity(0.08), borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFf0883e).withOpacity(0.2))),
            child: Text(name, style: const TextStyle(color: Color(0xFFf0883e), fontSize: 10)),
          ),
        );
      }).toList()),
    );
  }

  Widget _goalsTab() {
    final proj = widget.proj;
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (proj.goalTitle.isNotEmpty) ...[
        const Row(children: [Icon(Icons.flag, size: 14, color: Color(0xFF4AC99B)), SizedBox(width: 6),
          Text('목표', style: TextStyle(color: Color(0xFF4AC99B), fontSize: 11, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 8),
        Text(proj.goalTitle, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w600)),
      ] else
        TextButton.icon(onPressed: () { Navigator.pop(context); widget.onGoalRegister(); },
          icon: const Icon(Icons.add, size: 14), label: const Text('목표 설정'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF1B96FF))),
      if (proj.milestones.isNotEmpty) ...[
        const SizedBox(height: 16),
        ...proj.milestones.map((m) {
          final isDone = m['done'] == true;
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
            Icon(isDone ? Icons.check_circle : Icons.circle_outlined, size: 16,
              color: isDone ? const Color(0xFF4AC99B) : const Color(0xFF484f58)),
            const SizedBox(width: 8),
            Expanded(child: Text(m['title']?.toString() ?? '', style: TextStyle(
              color: isDone ? const Color(0xFF8b949e) : const Color(0xFFe6edf3), fontSize: 12,
              decoration: isDone ? TextDecoration.lineThrough : null))),
          ]));
        }),
      ],
      const SizedBox(height: 16),
      Row(children: [
        _kpi('진행률', '${proj.progress.toInt()}%', const Color(0xFF1B96FF)),
        _kpi('잔여', '${proj.remaining}', const Color(0xFFf0883e)),
        _kpi('팀', '${proj.activeTeams}', const Color(0xFF7c3aed)),
        _kpi('완료', '${proj.doneTickets}', const Color(0xFF4AC99B)),
      ]),
    ]));
  }

  Widget _kpi(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w800)),
    Text(l, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
  ]));
}

class _LiveAgentList extends StatefulWidget {
  final String projectName;
  final List<String> teamIds;
  final Map<String, dynamic> inventory;
  const _LiveAgentList({required this.projectName, required this.teamIds, required this.inventory});
  @override State<_LiveAgentList> createState() => _LiveAgentListState();
}

class _LiveAgentListState extends State<_LiveAgentList> {
  List<Map<String, dynamic>> _liveAgents = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final all = <Map<String, dynamic>>[];
    for (final tid in widget.teamIds) {
      final res = await api.teamSpecialists(tid);
      for (final a in ((res['agents'] as List?) ?? [])) {
        if (a is Map<String, dynamic>) {
          a['_team_id'] = tid;
          all.add(a);
        }
      }
    }
    if (mounted) setState(() { _liveAgents = all; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.inventory;
    final skills = ((inv['skills'] as List?) ?? []).cast<Map<String, dynamic>>();
    final mcpServers = ((inv['mcp_servers'] as List?) ?? []).cast<String>();

    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF30363d)))),
      child: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF))))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 실제 스폰 에이전트
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                color: const Color(0xFF0d1117),
                child: Row(children: [
                  const Icon(Icons.smart_toy, size: 12, color: Color(0xFF7c3aed)),
                  const SizedBox(width: 4),
                  Text('활성 에이전트 (${_liveAgents.length})', style: const TextStyle(color: Color(0xFF7c3aed), fontSize: 10, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (skills.isNotEmpty) Text('스킬 ${skills.length}', style: const TextStyle(color: Color(0xFFf0883e), fontSize: 9)),
                  if (mcpServers.isNotEmpty) ...[const SizedBox(width: 6), Text('MCP ${mcpServers.length}', style: const TextStyle(color: Color(0xFF4AC99B), fontSize: 9))],
                ]),
              ),
              if (_liveAgents.isEmpty) ...[
                // 칸반 스폰 없으면 파일 인벤토리의 에이전트 표시
                if (((widget.inventory['agents'] as List?) ?? []).isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                    child: Text('등록 전문가 (미스폰)', style: TextStyle(color: const Color(0xFF8b949e).withOpacity(0.7), fontSize: 9))),
                  ...((widget.inventory['agents'] as List?) ?? []).cast<Map<String, dynamic>>().take(10).map((a) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Row(children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: const Color(0xFF484f58), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a['name']?.toString() ?? '', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10))),
                      const Text('미스폰', style: TextStyle(color: Color(0xFF484f58), fontSize: 8)),
                    ]),
                  )),
                ] else
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('에이전트 없음', style: TextStyle(color: Color(0xFF8b949e), fontSize: 11)))),
              ]
              else
                ..._liveAgents.map((a) {
                  final name = a['display_name']?.toString() ?? '';
                  final role = a['role']?.toString() ?? '';
                  final status = a['status']?.toString() ?? 'Idle';
                  final kpi = (a['kpi'] as Map<String, dynamic>?) ?? {};
                  final done = kpi['done'] ?? 0;
                  final total = kpi['total_claimed'] ?? 0;
                  final isWorking = status == 'Working';
                  return InkWell(
                    onTap: () => _showTeamPopupFromAgent(a),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(
                          color: isWorking ? const Color(0xFF1B96FF) : const Color(0xFF8b949e), shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 11, fontWeight: FontWeight.w500)),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: const Color(0xFF7c3aed).withOpacity(0.1), borderRadius: BorderRadius.circular(3)),
                              child: Text(role, style: const TextStyle(color: Color(0xFFa371f7), fontSize: 8)),
                            ),
                            const SizedBox(width: 6),
                            Text(isWorking ? '작업 중' : '대기', style: TextStyle(color: isWorking ? const Color(0xFF1B96FF) : const Color(0xFF484f58), fontSize: 8)),
                          ]),
                        ])),
                        Text('$done/$total', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10, fontFamily: 'monospace')),
                      ]),
                    ),
                  );
                }),
              // 스킬 요약
              if (skills.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Wrap(spacing: 4, runSpacing: 4, children: skills.take(15).map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFFf0883e).withOpacity(0.08), borderRadius: BorderRadius.circular(3)),
                    child: Text(s['name']?.toString() ?? '', style: const TextStyle(color: Color(0xFFf0883e), fontSize: 8)),
                  )).toList()),
                ),
            ]),
    );
  }

  void _showTeamPopupFromAgent(Map<String, dynamic> agent) {
    final teamId = agent['_team_id']?.toString() ?? '';
    if (teamId.isEmpty) return;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.3, expand: false,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(color: Color(0xFF161b22), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
          child: Column(children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 8),
              decoration: BoxDecoration(color: const Color(0xFF30363d), borderRadius: BorderRadius.circular(2))),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Row(children: [
              const Icon(Icons.smart_toy, size: 16, color: Color(0xFF7c3aed)),
              const SizedBox(width: 8),
              Expanded(child: Text(agent['display_name']?.toString() ?? '', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 14, fontWeight: FontWeight.w700))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF7c3aed).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(agent['role']?.toString() ?? '', style: const TextStyle(color: Color(0xFFa371f7), fontSize: 10))),
            ])),
            const Divider(height: 1, color: Color(0xFF30363d)),
            Expanded(child: _AgentListBody(teamId: teamId, scrollController: scroll)),
          ]),
        ),
      ),
    );
  }
}

class _TeamPopupBody extends StatefulWidget {
  final String teamId;
  final ScrollController scrollController;
  const _TeamPopupBody({required this.teamId, required this.scrollController});
  @override State<_TeamPopupBody> createState() => _TeamPopupBodyState();
}

class _TeamPopupBodyState extends State<_TeamPopupBody> {
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final res = await api.getBoard(widget.teamId);
    if (mounted && res['ok'] == true) {
      final board = res['board'] as Map<String, dynamic>? ?? {};
      setState(() {
        _tickets = ((board['tickets'] as List?) ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } else if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)));
    if (_tickets.isEmpty) return const Center(child: Text('티켓 없음', style: TextStyle(color: Color(0xFF8b949e))));

    // Group by status
    final statusOrder = ['InProgress', 'Review', 'Blocked', 'Todo', 'Backlog', 'Done'];
    final statusColors = {
      'Backlog': const Color(0xFF8b949e), 'Todo': const Color(0xFF58a6ff),
      'InProgress': const Color(0xFFd29922), 'Review': const Color(0xFFa371f7),
      'Blocked': const Color(0xFFf85149), 'Done': const Color(0xFF3fb950),
    };

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final t in _tickets) {
      final s = t['status']?.toString() ?? 'Backlog';
      groups.putIfAbsent(s, () => []).add(t);
    }

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(12),
      children: statusOrder.where((s) => groups.containsKey(s)).expand((status) {
        final tks = groups[status]!;
        final color = statusColors[status] ?? const Color(0xFF8b949e);
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('$status (${tks.length})', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
          ...tks.map((tk) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0d1117), borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF30363d))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tk['title']?.toString() ?? '', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Row(children: [
                Text(tk['ticket_id']?.toString() ?? '', style: const TextStyle(color: Color(0xFF484f58), fontSize: 9, fontFamily: 'monospace')),
                const Spacer(),
                if (tk['claimed_by'] != null)
                  Text('${tk['claimed_by']}', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
              ]),
            ]),
          )),
        ];
      }).toList(),
    );
  }
}
