import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';

class ProjectsScreen extends StatefulWidget {
  final Function(String teamId, String teamName) onTeamTap;
  const ProjectsScreen({super.key, required this.onTeamTap});
  @override State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _teams = [];
  List<Map<String, dynamic>> _archives = [];
  bool _loading = true;
  String? _selectedProject;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = context.read<ApiService>();
    final projs = await api.getProjects();
    final teams = await api.getTeamsWithStats();
    final archives = await api.getArchives();
    if (mounted) setState(() {
      _projects = projs;
      _teams = teams;
      _archives = archives;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _teamsForProject(String projName) {
    final low = projName.toLowerCase();
    return _teams.where((t) {
      final g = (t['project_group'] ?? '').toString().toLowerCase();
      return g == low || g.contains(low) || low.contains(g);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        title: const Text('프로젝트 & 팀', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF161b22), elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load)],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF1B96FF),
          labelColor: const Color(0xFF1B96FF),
          unselectedLabelColor: const Color(0xFF8b949e),
          tabs: [
            Tab(text: '프로젝트 (${_projects.length})'),
            Tab(text: '팀 (${_teams.length})'),
            Tab(text: '아카이브 (${_archives.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B96FF)))
          : TabBarView(controller: _tabCtrl, children: [
              _buildProjectsTab(),
              _buildTeamsTab(_teams),
              _buildTeamsTab(_archives, archived: true),
            ]),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: const Color(0xFF1B96FF),
        onPressed: _showCreateTeamDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildProjectsTab() {
    if (_projects.isEmpty) return const Center(child: Text('프로젝트 없음', style: TextStyle(color: Color(0xFF8b949e))));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _projects.length,
      itemBuilder: (ctx, i) {
        final proj = _projects[i];
        final projTeams = _teamsForProject(proj['name'] ?? '');
        final isSelected = _selectedProject == proj['name'];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => setState(() => _selectedProject = isSelected ? null : proj['name']),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1B96FF).withOpacity(0.1) : const Color(0xFF161b22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isSelected ? const Color(0xFF1B96FF) : const Color(0xFF30363d))),
              child: Row(children: [
                Icon(proj['is_git'] == true ? Icons.code : Icons.folder_outlined,
                  color: const Color(0xFF1B96FF), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(proj['name'] ?? '', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w600)),
                  if ((proj['alias'] ?? '').isNotEmpty)
                    Text('별명: ${proj['alias']}', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('팀 ${projTeams.length}', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
                  Text(proj['last_activity'] != null ? proj['last_activity'].toString().substring(0, 10) : '',
                    style: const TextStyle(color: Color(0xFF8b949e), fontSize: 9)),
                ]),
                const SizedBox(width: 6),
                Icon(isSelected ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF8b949e), size: 18),
              ]),
            ),
          ),
          if (isSelected && projTeams.isNotEmpty)
            ...projTeams.map((t) => Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 6),
              child: _teamCard(t),
            )),
        ]);
      },
    );
  }

  Widget _buildTeamsTab(List<Map<String, dynamic>> teams, {bool archived = false}) {
    if (teams.isEmpty) return Center(child: Text(archived ? '아카이브 없음' : '팀 없음', style: const TextStyle(color: Color(0xFF8b949e))));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: teams.length,
      itemBuilder: (ctx, i) => _teamCard(teams[i], archived: archived),
    );
  }

  Widget _teamCard(Map<String, dynamic> team, {bool archived = false}) {
    final done = team['done_tickets'] ?? 0;
    final total = team['total_tickets'] ?? 0;
    final progress = total > 0 ? (done / total * 100) : 0.0;
    return InkWell(
      onTap: archived ? null : () => widget.onTeamTap(team['team_id'], team['name'] ?? ''),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161b22), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF30363d))),
        child: Row(children: [
          Icon(archived ? Icons.archive_outlined : Icons.view_kanban_outlined,
            color: archived ? const Color(0xFF8b949e) : const Color(0xFF1B96FF), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(team['name'] ?? '', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w600)),
            if ((team['project_group'] ?? '').isNotEmpty)
              Text(team['project_group'], style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
            if (!archived) ...[
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(
                value: progress / 100, minHeight: 3,
                backgroundColor: const Color(0xFF30363d),
                valueColor: AlwaysStoppedAnimation(progress >= 80 ? const Color(0xFF4AC99B) : const Color(0xFF1B96FF)),
              )),
            ],
          ])),
          const SizedBox(width: 8),
          Text('$done/$total', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
          if (!archived) const Icon(Icons.chevron_right, color: Color(0xFF8b949e), size: 18),
        ]),
      ),
    );
  }

  void _showCreateTeamDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final projCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF161b22),
      title: const Text('새 팀 생성', style: TextStyle(color: Color(0xFFe6edf3), fontSize: 15)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogField('팀 이름', nameCtrl),
        const SizedBox(height: 10),
        _dialogField('설명', descCtrl),
        const SizedBox(height: 10),
        _dialogField('프로젝트', projCtrl),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Color(0xFF8b949e)))),
        ElevatedButton(
          onPressed: () async {
            if (nameCtrl.text.isEmpty) return;
            final api = context.read<ApiService>();
            await api.createTeam({'name': nameCtrl.text, 'description': descCtrl.text, 'project_group': projCtrl.text});
            if (mounted) { Navigator.pop(ctx); _load(); }
          },
          child: const Text('생성'),
        ),
      ],
    ));
  }

  Widget _dialogField(String label, TextEditingController ctrl) => TextField(
    controller: ctrl,
    style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13),
    decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Color(0xFF8b949e), fontSize: 12),
      filled: true, fillColor: const Color(0xFF0d1117),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363d))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363d))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
  );
}
