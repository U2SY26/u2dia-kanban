import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';

class ResidentScreen extends StatefulWidget {
  const ResidentScreen({super.key});
  @override
  State<ResidentScreen> createState() => _ResidentScreenState();
}

class _ResidentScreenState extends State<ResidentScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map<String, dynamic>? _kpi;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _agentKpis = [];
  String _filter = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final results = await Future.wait([
      api.residentKpi(),
      api.residentHistory(limit: 200, type: _filter),
      api.agentsKpi(),
    ]);
    if (!mounted) return;
    setState(() {
      _kpi = results[0]['ok'] == true ? results[0]['kpi'] as Map<String, dynamic>? : null;
      if (results[1]['ok'] == true) {
        _history = ((results[1]['history'] as List?) ?? []).cast<Map<String, dynamic>>();
      }
      if (results[2]['ok'] == true) {
        _agentKpis = ((results[2]['agents'] as List?) ?? []).cast<Map<String, dynamic>>();
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        title: const Text('🤖 유디 대시보드'),
        backgroundColor: const Color(0xFF161b22),
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF1B96FF),
          tabs: const [
            Tab(text: 'KPI'),
            Tab(text: '히스토리'),
            Tab(text: '에이전트 KPI'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabCtrl, children: [
              _buildKpiTab(),
              _buildHistoryTab(),
              _buildAgentKpiTab(),
            ]),
    );
  }

  Widget _buildKpiTab() {
    if (_kpi == null) return const Center(child: Text('데이터 없음', style: TextStyle(color: Color(0xFF8b949e))));
    final k = _kpi!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        _kpiRow([
          _kpiCard('QA 리뷰', '${k['qa_total'] ?? 0}', Colors.green, '오늘 ${k['today_qa'] ?? 0}'),
          _kpiCard('QA 점수', '${k['qa_avg_score'] ?? 0}/5', Colors.amber, 'Pass ${k['qa_pass_rate'] ?? 0}%'),
        ]),
        const SizedBox(height: 8),
        _kpiRow([
          _kpiCard('Pass/Fail', '${k['qa_pass'] ?? 0}/${k['qa_fail'] ?? 0}',
              (k['qa_fail'] ?? 0) > 0 ? Colors.red : Colors.green, '합격률'),
          _kpiCard('재작업', '${k['reworks'] ?? 0}', Colors.red, '품질 개선'),
        ]),
        const SizedBox(height: 8),
        _kpiRow([
          _kpiCard('라우팅', '${k['routes'] ?? 0}', Colors.cyan, '에이전트→유디'),
          _kpiCard('회의', '${k['meetings'] ?? 0}', Colors.purple, '팀 조율'),
        ]),
        const SizedBox(height: 8),
        _kpiRow([
          _kpiCard('메시지', '${k['messages'] ?? 0}', Colors.orange, '팀 소통'),
        ]),
      ]),
    );
  }

  Widget _kpiRow(List<Widget> cards) => Row(
    children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c))).toList(),
  );

  Widget _kpiCard(String label, String value, Color color, String sub) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF161b22),
      border: Border.all(color: const Color(0xFF30363d)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(height: 3, width: 24, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8b949e))),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 2),
      Text(sub, style: const TextStyle(fontSize: 10, color: Color(0xFF8b949e))),
    ]),
  );

  Widget _buildHistoryTab() {
    final filters = ['all', 'review', 'rework', 'meeting', 'route', 'message'];
    final labels = ['전체', 'QA', '재작업', '회의', '라우팅', '메시지'];
    return Column(children: [
      SizedBox(height: 40, child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: filters.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(labels[i], style: const TextStyle(fontSize: 11)),
            selected: _filter == filters[i],
            selectedColor: const Color(0xFF1B96FF).withOpacity(0.3),
            onSelected: (_) { setState(() { _filter = filters[i]; }); _load(); },
          ),
        ),
      )),
      Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: _history.isEmpty
            ? const Center(child: Text('히스토리 없음', style: TextStyle(color: Color(0xFF8b949e))))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _history.length,
                itemBuilder: (_, i) => _historyItem(_history[i]),
              ),
      )),
    ]);
  }

  Widget _historyItem(Map<String, dynamic> item) {
    final kind = item['kind'] ?? '';
    final icons = {'conversation': '💬', 'review': '🔍', 'activity': '📊', 'message': '📨'};
    final colors = {'conversation': Colors.cyan, 'review': Colors.green, 'activity': const Color(0xFF1B96FF), 'message': Colors.orange};
    final kindLabels = {'conversation': '대화', 'review': 'QA', 'activity': '활동', 'message': '메시지'};
    final icon = icons[kind] ?? '📌';
    final color = colors[kind] ?? Colors.grey;
    final label = kindLabels[kind] ?? kind;
    final result = item['result'] ?? '';
    final score = item['score'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        border: Border.all(color: const Color(0xFF30363d)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            if (result == 'pass') ...[const SizedBox(width: 6), _badge('PASS', const Color(0xFF4ade80), const Color(0xFF1a472a))],
            if (result == 'fail') ...[const SizedBox(width: 6), _badge('FAIL', const Color(0xFFf87171), const Color(0xFF4a1a1a))],
            if (score.toString().isNotEmpty && score != '') ...[const SizedBox(width: 4), Text('★$score', style: const TextStyle(fontSize: 10, color: Colors.amber))],
          ]),
          Text(item['created_at'] ?? '', style: const TextStyle(fontSize: 9, color: Color(0xFF8b949e))),
        ]),
        const SizedBox(height: 4),
        Text(
          (item['content'] ?? '').toString().length > 200
              ? '${(item['content'] ?? '').toString().substring(0, 200)}...'
              : (item['content'] ?? '').toString(),
          style: const TextStyle(fontSize: 11, color: Color(0xFFc9d1d9), height: 1.4),
        ),
        if (item['ticket_id'] != null && item['ticket_id'].toString().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 2),
            child: Text('${item['from_agent'] ?? ''} ${item['ticket_id']}',
              style: const TextStyle(fontSize: 9, color: Color(0xFF58a6ff)))),
      ]),
    );
  }

  Widget _badge(String text, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
    child: Text(text, style: TextStyle(fontSize: 9, color: fg, fontWeight: FontWeight.bold)),
  );

  Widget _buildAgentKpiTab() {
    if (_agentKpis.isEmpty) return const Center(child: Text('에이전트 없음', style: TextStyle(color: Color(0xFF8b949e))));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _agentKpis.length,
        itemBuilder: (_, i) => _agentKpiItem(_agentKpis[i]),
      ),
    );
  }

  Widget _agentKpiItem(Map<String, dynamic> a) {
    final rate = (a['completion_rate'] as num?)?.toDouble() ?? 0;
    final qaScore = (a['qa_avg_score'] as num?)?.toDouble() ?? 0;
    final scoreColor = qaScore >= 4 ? Colors.green : qaScore >= 3 ? Colors.amber : Colors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        border: Border.all(color: const Color(0xFF30363d)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['display_name'] ?? a['member_id'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFc9d1d9))),
            Text('${a['team_name'] ?? ''} · ${a['role'] ?? ''}', style: const TextStyle(fontSize: 10, color: Color(0xFF8b949e))),
          ])),
          Text(a['status'] ?? 'Idle', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600,
            color: a['status'] == 'Working' ? Colors.green : a['status'] == 'Blocked' ? Colors.red : Colors.grey,
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Column(children: [
            Text('${a['tickets_done']}/${a['tickets_total']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFc9d1d9))),
            const Text('티켓', style: TextStyle(fontSize: 9, color: Color(0xFF8b949e))),
          ])),
          Expanded(child: Column(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 30, height: 4, child: ClipRRect(borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: rate / 100, backgroundColor: const Color(0xFF30363d), color: Colors.green))),
              const SizedBox(width: 4),
              Text('${rate.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, color: Color(0xFFc9d1d9))),
            ]),
            const Text('완료율', style: TextStyle(fontSize: 9, color: Color(0xFF8b949e))),
          ])),
          Expanded(child: Column(children: [
            Text(qaScore > 0 ? '${qaScore}★' : '-', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: scoreColor)),
            const Text('QA', style: TextStyle(fontSize: 9, color: Color(0xFF8b949e))),
          ])),
          Expanded(child: Column(children: [
            Text('\$${((a['cost'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFFc9d1d9))),
            const Text('비용', style: TextStyle(fontSize: 9, color: Color(0xFF8b949e))),
          ])),
        ]),
      ]),
    );
  }
}
