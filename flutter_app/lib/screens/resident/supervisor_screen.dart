import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../theme/colors.dart';

class SupervisorScreen extends StatefulWidget {
  const SupervisorScreen({super.key});
  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  Map<String, dynamic> _pipeline = {};
  Map<String, dynamic> _reviewStats = {};
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final results = await Future.wait([
      api.supervisorPipeline(),
      api.supervisorReviewStats(),
    ]);
    if (!mounted) return;
    setState(() {
      _pipeline = results[0];
      _reviewStats = results[1];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundElevated, elevation: 0,
        title: const Row(children: [
          Icon(Icons.verified_user, size: 20, color: AppColors.brandLight),
          SizedBox(width: 8),
          Text('Supervisor QA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () { setState(() => _loading = true); _load(); }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
              _healthBanner(),
              const SizedBox(height: 12),
              _pipelineStatus(),
              const SizedBox(height: 12),
              _qaStats(),
              const SizedBox(height: 12),
              _reworkDistribution(),
              if ((_pipeline['blocked_tickets'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _blockedList(),
              ],
              if ((_pipeline['no_artifact_reviews'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _noArtifactList(),
              ],
              const SizedBox(height: 40),
            ])),
    );
  }

  Widget _healthBanner() {
    final health = _pipeline['health']?.toString() ?? 'unknown';
    final issues = (_pipeline['issues'] as List?)?.cast<String>() ?? [];
    Color color;
    IconData icon;
    String label;
    switch (health) {
      case 'healthy': color = AppColors.success; icon = Icons.check_circle; label = '정상'; break;
      case 'warning': color = AppColors.warning; icon = Icons.warning_amber; label = '주의'; break;
      case 'stalled': color = AppColors.warning; icon = Icons.pause_circle; label = '정체'; break;
      case 'critical': color = AppColors.error; icon = Icons.error; label = '심각'; break;
      default: color = AppColors.textSecondary; icon = Icons.help; label = '알 수 없음';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 10),
          Text('파이프라인: $label', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('${_pipeline['completion_rate'] ?? 0}%', style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...issues.map((issue) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              Icon(Icons.arrow_right, size: 14, color: color),
              Expanded(child: Text(issue, style: TextStyle(color: color, fontSize: 11))),
            ]),
          )),
        ],
      ]),
    );
  }

  Widget _pipelineStatus() {
    final sc = (_pipeline['status_counts'] as Map<String, dynamic>?) ?? {};
    final total = (_pipeline['total_tickets'] as num?)?.toInt() ?? 0;
    final stages = [
      ('Backlog', sc['Backlog'] ?? 0, AppColors.statusBacklog),
      ('Todo', sc['Todo'] ?? 0, AppColors.statusTodo),
      ('InProgress', sc['InProgress'] ?? 0, AppColors.statusInProgress),
      ('Review', sc['Review'] ?? 0, AppColors.statusReview),
      ('Blocked', sc['Blocked'] ?? 0, AppColors.statusBlocked),
      ('Done', sc['Done'] ?? 0, AppColors.statusDone),
    ];

    return _card('파이프라인 현황', Icons.timeline, Column(children: [
      // 파이프라인 바
      if (total > 0)
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(height: 10, child: Row(
            children: stages.map((s) {
              final w = (s.$2 as int) / total;
              if (w <= 0) return const SizedBox.shrink();
              return Flexible(flex: (w * 1000).round().clamp(1, 1000), child: Container(color: s.$3));
            }).toList(),
          )),
        ),
      const SizedBox(height: 12),
      // 숫자
      Row(children: stages.map((s) => Expanded(child: Column(children: [
        Text('${s.$2}', style: TextStyle(color: s.$3, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(s.$1, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
      ]))).toList()),
    ]));
  }

  Widget _qaStats() {
    final s = (_reviewStats['stats'] as Map<String, dynamic>?) ?? _reviewStats;
    final last24 = (_pipeline['last_24h'] as Map<String, dynamic>?) ?? {};

    return _card('QA 검수 통계', Icons.verified, Column(children: [
      Row(children: [
        _kpi('총 검수', '${s['total_reviews'] ?? 0}', AppColors.brandLight),
        _kpi('통과', '${s['passed'] ?? 0}', AppColors.success),
        _kpi('재작업', '${s['rework'] ?? 0}', AppColors.warning),
        _kpi('평균', '${s['avg_score'] ?? 0}', AppColors.info),
      ]),
      const Divider(color: AppColors.border, height: 20),
      Row(children: [
        const Icon(Icons.schedule, size: 12, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        const Text('최근 24시간', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        const Spacer(),
        Text('검수 ${last24['reviews'] ?? 0} | 통과 ${last24['passed'] ?? 0} | 재작업 ${last24['reworked'] ?? 0}',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 11)),
      ]),
    ]));
  }

  Widget _reworkDistribution() {
    final dist = (_pipeline['rework_distribution'] as Map<String, dynamic>?) ?? {};
    if (dist.isEmpty) {
      return _card('재작업 분포', Icons.replay, const Center(
        child: Text('재작업 이력 없음', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ));
    }
    return _card('재작업 분포 (3회 제한)', Icons.replay, Column(
      children: dist.entries.map((e) {
        final count = int.tryParse(e.key.toString()) ?? 0;
        final tickets = (e.value as num).toInt();
        final color = count >= 3 ? AppColors.error : count >= 2 ? AppColors.warning : AppColors.info;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
              child: Center(child: Text('$count', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))),
            ),
            const SizedBox(width: 8),
            Text('$count회 재작업', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
            const Spacer(),
            Text('$tickets개 티켓', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            if (count >= 3) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(4)),
                child: const Text('Blocked', style: TextStyle(color: AppColors.error, fontSize: 9)),
              ),
            ],
          ]),
        );
      }).toList(),
    ));
  }

  Widget _blockedList() {
    final items = (_pipeline['blocked_tickets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return _card('Blocked 티켓 (에스컬레이션)', Icons.block, Column(
      children: items.take(10).map((t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 14, color: AppColors.error),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t['title']?.toString() ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${t['ticket_id']} | 재작업 ${t['rework_count'] ?? '?'}회 | ${t['team_name'] ?? ''}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          ])),
        ]),
      )).toList(),
    ));
  }

  Widget _noArtifactList() {
    final items = (_pipeline['no_artifact_reviews'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return _card('산출물 없는 Review 티켓', Icons.warning_amber, Column(
      children: items.take(10).map((t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const Icon(Icons.inventory_2_outlined, size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t['title']?.toString() ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${t['ticket_id']} | ${t['team_name'] ?? ''}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          ])),
        ]),
      )).toList(),
    ));
  }

  Widget _card(String title, IconData icon, Widget child) {
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
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Expanded(child: Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
    ]));
  }
}
