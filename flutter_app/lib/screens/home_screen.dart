import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme/colors.dart';
import 'dashboard/dashboard_screen.dart';
import 'dashboard/dashboard_webview_screen.dart';
import 'kanban/kanban_screen.dart';
import 'chat/chat_screen.dart';
import 'projects/project_overview_screen.dart';
import 'cli/cli_mirror_screen.dart';
import 'vscode/vscode_workspace_screen.dart';
import 'kanban/agent_office_screen.dart';
import 'operations/operations_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final List<int> _tabHistory = [0];
  String? _kanbanTeamId;
  String? _kanbanTeamName;
  int _operationsSubTab = 0;
  int _opsNavKey = 0; // OperationsScreen 재빌드 강제용 (key 변경)

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    api.configure(auth.serverUrl);
    api.ping();
    NotificationService().init(api);
  }

  void navigateToBoard(String teamId, String teamName) {
    setState(() {
      _kanbanTeamId = teamId;
      _kanbanTeamName = teamName;
      _tab = 2; // 칸반 탭
      _tabHistory.add(2);
    });
  }

  void navigateToTab(int tabIndex) {
    setState(() {
      _tab = tabIndex;
      _tabHistory.add(tabIndex);
    });
  }

  void navigateToOperations(int subTab) {
    setState(() {
      _operationsSubTab = subTab;
      _opsNavKey++;
      _tab = 4;
      _tabHistory.add(4);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardWebViewScreen(
        onTeamTap: navigateToBoard,
        onNavigateToTab: navigateToTab,
        onNavigateToOperations: navigateToOperations,
      ),
      ProjectOverviewScreen(onTeamTap: navigateToBoard),
      _KanbanTab(
        selectedTeamId: _kanbanTeamId,
        selectedTeamName: _kanbanTeamName,
        onTeamTap: (id, name) => setState(() {
          _kanbanTeamId = id;
          _kanbanTeamName = name;
        }),
        onBack: () => setState(() {
          _kanbanTeamId = null;
          _kanbanTeamName = null;
        }),
      ),
      const ChatScreen(),
      OperationsScreen(
        key: ValueKey('ops-$_opsNavKey'),
        initialTabIndex: _operationsSubTab,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 칸반 보드 열려있으면 팀 목록으로 복귀
        if (_tab == 2 && _kanbanTeamId != null) {
          setState(() { _kanbanTeamId = null; _kanbanTeamName = null; });
          return;
        }
        if (_tabHistory.length > 1) {
          _tabHistory.removeLast();
          setState(() => _tab = _tabHistory.last);
        }
      },
      child: Scaffold(
      body: IndexedStack(index: _tab, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.border, 
              width: 0.5,
            ),
          ),
        ),
        child: NavigationBar(
          backgroundColor: AppColors.backgroundElevated,
          indicatorColor: AppColors.brandBg,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() { _tabHistory.add(i); _tab = i; }),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined, size: 20),
              selectedIcon: Icon(Icons.dashboard, size: 20),
              label: '대시보드',
            ),
            NavigationDestination(
              icon: Icon(Icons.rocket_launch_outlined, size: 20),
              selectedIcon: Icon(Icons.rocket_launch, size: 20),
              label: '프로젝트',
            ),
            NavigationDestination(
              icon: Icon(Icons.view_kanban_outlined, size: 20),
              selectedIcon: Icon(Icons.view_kanban, size: 20),
              label: '칸반',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_outlined, size: 20),
              selectedIcon: Icon(Icons.chat, size: 20),
              label: '유디',
            ),
            NavigationDestination(
              icon: Icon(Icons.terminal_outlined, size: 20),
              selectedIcon: Icon(Icons.terminal, size: 20),
              label: '운영',
            ),
          ],
        ),
      ),
    ),
    );
  }

}

class _KanbanTab extends StatefulWidget {
  final String? selectedTeamId;
  final String? selectedTeamName;
  final void Function(String id, String name) onTeamTap;
  final VoidCallback onBack;

  const _KanbanTab({
    required this.selectedTeamId,
    required this.selectedTeamName,
    required this.onTeamTap,
    required this.onBack,
  });

  @override
  State<_KanbanTab> createState() => _KanbanTabState();
}

class _KanbanTabState extends State<_KanbanTab> {
  List<Map<String, dynamic>> _teams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final api = context.read<ApiService>();
    try {
      final res = await api.get('/api/teams');
      if (res['ok'] == true) {
        final teams = (res['teams'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (mounted) {
          setState(() {
            _teams = teams.where((t) => t['status'] == 'Active').toList();
            _loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 팀 선택됨 → 칸반 보드 표시
    if (widget.selectedTeamId != null) {
      return Column(children: [
        Container(
          color: AppColors.backgroundElevated,
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: widget.onBack,
            ),
            Expanded(
              child: Text(
                widget.selectedTeamName ?? '',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
          ]),
        ),
        Expanded(
          child: KanbanScreen(
            teamId: widget.selectedTeamId!,
            teamName: widget.selectedTeamName ?? '',
          ),
        ),
      ]);
    }

    // 팀 미선택 → 전체 팀 목록
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final t in _teams) {
      final g = t['project_group']?.toString() ?? '기타';
      groups.putIfAbsent(g, () => []).add(t);
    }

    final isDemoMode = context.watch<ApiService>().demoMode;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('칸반보드'),
        backgroundColor: AppColors.backgroundElevated,
        elevation: 0,
        bottom: isDemoMode
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  width: double.infinity,
                  height: 28,
                  color: const Color(0xFFf59e0b),
                  alignment: Alignment.center,
                  child: const Text(
                    '🎭 DEMO MODE — 샘플 데이터 (서버 미연결)',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.code, size: 20),
            tooltip: 'VSCode Workspaces',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VsCodeWorkspaceScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.terminal, size: 20),
            tooltip: 'Remote CLI Mirror',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CliMirrorScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () {
              setState(() => _loading = true);
              _loadTeams();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTeams,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: groups.length,
                itemBuilder: (ctx, i) {
                  final group = groups.keys.elementAt(i);
                  final teamList = groups[group]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          group,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      ...teamList.map((t) => _teamCard(t)),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _teamCard(Map<String, dynamic> team) {
    final name = team['name']?.toString() ?? '';
    final desc = team['description']?.toString() ?? '';
    final leader = team['leader_agent']?.toString() ?? '';

    return Card(
      color: AppColors.backgroundElevated,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onTeamTap(team['team_id'], name),
        onLongPress: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AgentOfficeScreen(
              teamId: team['team_id']?.toString() ?? '',
              teamName: name,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.view_kanban, size: 16, color: AppColors.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.groups, size: 18, color: Color(0xFF8fb4ff)),
                  tooltip: 'Agent Office',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AgentOfficeScreen(
                        teamId: team['team_id']?.toString() ?? '',
                        teamName: name,
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    leader,
                    style: TextStyle(fontSize: 11, color: AppColors.brand),
                  ),
                ),
              ]),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  desc,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}