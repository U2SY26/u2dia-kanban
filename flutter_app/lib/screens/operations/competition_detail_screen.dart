import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';

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
const _kGold = Color(0xFFFFD700);

class CompetitionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> competition;
  final Map<String, dynamic>? summary;

  const CompetitionDetailScreen({
    super.key,
    required this.competition,
    this.summary,
  });

  @override
  State<CompetitionDetailScreen> createState() => _CompetitionDetailScreenState();
}

class _CompetitionDetailScreenState extends State<CompetitionDetailScreen> {
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic> _fullData = {};
  List<Map<String, dynamic>> _lambdaRunning = [];
  bool _loading = true;
  bool _descExpanded = false;
  String? _eventFilter;
  Timer? _refreshTimer;

  String get _compName =>
      _fullData['name']?.toString() ??
      widget.competition['name']?.toString() ??
      widget.competition['competition']?.toString() ?? '';
  String get _projectGroup =>
      _fullData['project_group']?.toString() ??
      widget.competition['project_group']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _fullData = Map<String, dynamic>.from(widget.competition);
    if (widget.summary != null) {
      _fullData.addAll(widget.summary!);
    }
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final api = context.read<ApiService>();
    final pg = _projectGroup;
    final name = _compName;

    try {
      final compsData = await api.getCompetitions();
      Map<String, dynamic> matched = {};
      for (final c in compsData) {
        if (c['project_group'] == pg || c['name'] == name ||
            c['competition_display'] == name || c['title'] == name) {
          matched = c;
          break;
        }
      }

      final histKey = matched['competition_display']?.toString() ?? name;
      final histData = await api.competitionHistory(histKey, limit: 500);

      Map<String, dynamic> lambdaData = {};
      try {
        lambdaData = await api.lambdaRunning();
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        if (matched.isNotEmpty) _fullData = matched;
        _events = ((histData['events'] as List?) ?? []).cast<Map<String, dynamic>>();
        final allRunning = ((lambdaData['running_instances'] as List?) ?? []).cast<Map<String, dynamic>>();
        final comp = _fullData['project_group']?.toString() ?? '';
        _lambdaRunning = allRunning.where((i) {
          final ic = i['competition']?.toString() ?? '';
          return ic == comp || ic.contains(comp) || comp.contains(ic);
        }).toList();
        if (_lambdaRunning.isEmpty && allRunning.isNotEmpty) {
          final runningFromEntry = ((_fullData['running_instances'] as List?) ?? []).cast<Map<String, dynamic>>();
          if (runningFromEntry.isNotEmpty) _lambdaRunning = runningFromEntry;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = _fullData;
    final title = c['title']?.toString().trim().isNotEmpty == true
        ? c['title'].toString() : _compName;
    final kaggleUrl = c['kaggle_url']?.toString() ?? '';
    final writeupUrl = c['writeup_url']?.toString() ?? '';
    final deadline = c['deadline']?.toString() ?? '';
    final entryDeadline = c['entry_deadline']?.toString() ?? '';
    final track = c['track']?.toString() ?? '';
    final prizeUsd = (c['prize_usd'] as num?)?.toInt() ?? 0;
    final submissionStatus = c['submission_status']?.toString() ?? 'in_progress';
    final description = c['description']?.toString() ?? '';
    final progress = (c['progress'] as num?)?.toDouble() ?? 0;
    final stats = (c['ticket_stats'] as Map<String, dynamic>?) ?? {};
    final totalTickets = (stats['total'] as num?)?.toInt() ?? 0;
    final doneTickets = (stats['done'] as num?)?.toInt() ?? 0;
    final inProgressTickets = (stats['in_progress'] as num?)?.toInt() ?? 0;
    final reviewTickets = (stats['review'] as num?)?.toInt() ?? 0;
    final blockedTickets = (stats['blocked'] as num?)?.toInt() ?? 0;
    final lambdaCost = (c['lambda_cost'] as num?)?.toDouble() ?? 0;
    final lambdaInstances = (c['lambda_instances'] as num?)?.toInt() ?? 0;
    final activeGpus = (c['active_gpus'] as num?)?.toInt() ?? 0;
    final runningCount = (c['running_count'] as num?)?.toInt() ?? _lambdaRunning.length;
    final teams = ((c['teams'] as List?) ?? []).cast<Map<String, dynamic>>();
    final activeTeams = teams.where((t) => t['archived'] != true).toList();
    final archivedTeams = teams.where((t) => t['archived'] == true).toList();

    final totalEvents = (c['total_events'] as num?)?.toInt() ?? _events.length;
    final reviewCount = (c['review_count'] as num?)?.toInt() ?? 0;
    final avgScore = (c['avg_score'] as num?)?.toDouble();
    final maxScore = (c['max_score'] as num?)?.toDouble();
    final eventDist = (c['event_distribution'] as Map?) ?? {};
    final commitCount = (eventDist['git_commit'] as num?)?.toInt() ?? 0;
    final artifactCount = (eventDist['artifact_created'] as num?)?.toInt() ?? 0;

    String dday = '';
    int ddayNum = 0;
    if (deadline.isNotEmpty) {
      try {
        final dl = DateTime.parse(deadline);
        ddayNum = dl.difference(DateTime.now()).inDays;
        dday = ddayNum > 0 ? 'D-$ddayNum' : ddayNum == 0 ? 'D-DAY' : 'D+${-ddayNum}';
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: _kAccent,
        backgroundColor: _kCard,
        child: CustomScrollView(
          slivers: [
            _heroAppBar(title, kaggleUrl, submissionStatus, dday, ddayNum, prizeUsd),
            SliverPadding(
              padding: const EdgeInsets.all(14),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _quickLinks(kaggleUrl, writeupUrl),
                  if (kaggleUrl.isNotEmpty || writeupUrl.isNotEmpty) const SizedBox(height: 14),

                  _statusOverview(track, deadline, dday, ddayNum, entryDeadline,
                      submissionStatus, prizeUsd, lambdaCost, lambdaInstances,
                      runningCount, activeGpus),
                  const SizedBox(height: 14),

                  if (description.isNotEmpty) ...[
                    _descriptionSection(description),
                    const SizedBox(height: 14),
                  ],

                  _agentMetadataSection(c),
                  if (c['winning_conditions'] != null || c['evaluation_metric'] != null ||
                      c['current_rank'] != null || c['approach'] != null ||
                      c['status_notes'] != null) const SizedBox(height: 14),

                  if (_lambdaRunning.isNotEmpty || lambdaCost > 0) ...[
                    _lambdaSection(lambdaCost, lambdaInstances, runningCount),
                    const SizedBox(height: 14),
                  ],

                  if (totalTickets > 0) ...[
                    _progressSection(progress, totalTickets, doneTickets,
                        inProgressTickets, reviewTickets, blockedTickets),
                    const SizedBox(height: 14),
                  ],

                  _kpiGrid(totalEvents, reviewCount, avgScore, maxScore,
                      commitCount, artifactCount, totalTickets),
                  const SizedBox(height: 14),

                  if (activeTeams.isNotEmpty || archivedTeams.isNotEmpty) ...[
                    _teamsSection(activeTeams, archivedTeams),
                    const SizedBox(height: 14),
                  ],

                  _eventTimeline(),
                  const SizedBox(height: 60),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  // Hero AppBar
  // ══════════════════════════════════════

  Widget _heroAppBar(String title, String kaggleUrl, String status, String dday, int ddayNum, int prize) {
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      backgroundColor: _kCard,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (kaggleUrl.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 20, color: _kCyan),
            tooltip: 'Kaggle',
            onPressed: () => _openUrl(kaggleUrl),
          ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: () { setState(() => _loading = true); _loadData(); },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kPurple.withValues(alpha: 0.15), _kAccent.withValues(alpha: 0.08), _kBg],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 80, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(children: [
                _statusBadge(status),
                const SizedBox(width: 6),
                if (dday.isNotEmpty) _ddayBadge(dday, ddayNum),
                const Spacer(),
                if (prize > 0) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kGold.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.emoji_events, size: 14, color: _kGold),
                    const SizedBox(width: 4),
                    Text('\$${_fmtNumber(prize)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _kGold)),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              Text(title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _kText, height: 1.2),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              if (title != _compName)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_compName,
                      style: const TextStyle(fontSize: 11, color: _kTextMuted, fontFamily: 'monospace')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  // Quick Links
  // ══════════════════════════════════════

  Widget _quickLinks(String kaggleUrl, String writeupUrl) {
    if (kaggleUrl.isEmpty && writeupUrl.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      if (kaggleUrl.isNotEmpty)
        Expanded(child: _linkButton(Icons.public, 'Kaggle Competition', _kCyan, kaggleUrl)),
      if (kaggleUrl.isNotEmpty && writeupUrl.isNotEmpty) const SizedBox(width: 8),
      if (writeupUrl.isNotEmpty)
        Expanded(child: _linkButton(Icons.description, 'Writeup / Solution', _kPurple, writeupUrl)),
    ]);
  }

  Widget _linkButton(IconData icon, String label, Color color, String url) {
    return GestureDetector(
      onTap: () => _openUrl(url),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                overflow: TextOverflow.ellipsis),
          ),
          Icon(Icons.open_in_new, size: 14, color: color.withValues(alpha: 0.6)),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════
  // Status Overview (상금/우승조건/제출상태/현재상태)
  // ══════════════════════════════════════

  Widget _statusOverview(String track, String deadline, String dday, int ddayNum,
      String entryDeadline, String submissionStatus, int prizeUsd,
      double lambdaCost, int lambdaInstances, int runningCount, int activeGpus) {

    final (statusLabel, statusColor, statusIcon) = switch (submissionStatus) {
      'writeup_posted' => ('Writeup 게시 완료', _kPurple, Icons.check_circle),
      'submitted' => ('제출 완료', _kGreen, Icons.check_circle),
      _ => ('진행 중', _kAccent, Icons.play_circle_filled),
    };

    final ddayColor = ddayNum <= 0 ? _kRed
        : ddayNum <= 7 ? _kRed
        : ddayNum <= 30 ? _kOrange : _kGreen;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('COMPETITION STATUS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kTextMuted, letterSpacing: 1.5)),
        const SizedBox(height: 12),

        // 현재 제출 상태 — 강조 카드
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(statusIcon, size: 24, color: statusColor),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('제출 상태', style: TextStyle(fontSize: 10, color: _kTextMuted)),
              Text(statusLabel,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: statusColor)),
            ])),
            if (dday.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: ddayColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(children: [
                  Text(dday,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: ddayColor, fontFamily: 'monospace')),
                  Text('마감', style: TextStyle(fontSize: 9, color: ddayColor.withValues(alpha: 0.8))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),

        _overviewRow(Icons.category, 'Track', track.isNotEmpty ? track : '-'),
        _overviewRow(Icons.event, 'Deadline', deadline.isNotEmpty ? '$deadline${dday.isNotEmpty ? "  ($dday)" : ""}' : '-'),
        if (entryDeadline.isNotEmpty)
          _overviewRow(Icons.event_available, 'Entry Deadline', entryDeadline),

        if (prizeUsd > 0) ...[
          const Divider(color: _kBorder, height: 16),
          _prizeSection(prizeUsd),
        ],

        if (lambdaCost > 0 || runningCount > 0) ...[
          const Divider(color: _kBorder, height: 16),
          _overviewRow(Icons.cloud, 'Lambda 누적 비용', '\$${lambdaCost.toStringAsFixed(2)}'),
          _overviewRow(Icons.dns, 'Lambda 총 실행', '$lambdaInstances회'),
          if (runningCount > 0)
            _overviewRow(Icons.play_arrow, 'Lambda 현재 가동', '$runningCount대 ($activeGpus GPU)'),
        ],
      ]),
    );
  }

  Widget _prizeSection(int prizeUsd) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kGold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.emoji_events, size: 16, color: _kGold),
          const SizedBox(width: 8),
          const Text('상금', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kGold)),
          const Spacer(),
          Text('\$${_fmtNumber(prizeUsd)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _kGold, fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 6),
        Text(prizeUsd >= 100000 ? '대규모 상금 대회 — Top 솔루션 요구'
            : prizeUsd >= 10000 ? '중규모 상금 대회'
            : '소규모 대회 / Knowledge 대회',
            style: const TextStyle(fontSize: 10, color: _kTextMuted)),
      ]),
    );
  }

  Widget _overviewRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 14, color: _kTextSec),
        const SizedBox(width: 10),
        SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12, color: _kTextSec))),
        Expanded(child: Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kText))),
      ]),
    );
  }

  // ══════════════════════════════════════
  // Description (README.md)
  // ══════════════════════════════════════

  Widget _descriptionSection(String description) {
    final showExpand = description.length > 600;
    final displayText = showExpand && !_descExpanded
        ? '${description.substring(0, 600).trimRight()}…'
        : description;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.article_outlined, size: 14, color: _kTextMuted),
          SizedBox(width: 6),
          Text('DESCRIPTION',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kTextMuted, letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 10),
        SelectableText(displayText,
            style: const TextStyle(fontSize: 12, color: _kTextSec, height: 1.6)),
        if (showExpand)
          GestureDetector(
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_descExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: _kAccent),
                const SizedBox(width: 4),
                Text(_descExpanded ? '접기' : '더 보기',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kAccent)),
              ]),
            ),
          ),
      ]),
    );
  }

  // ══════════════════════════════════════
  // Agent Metadata (에이전트가 등록한 동적 메타데이터)
  // ══════════════════════════════════════

  Widget _agentMetadataSection(Map<String, dynamic> c) {
    final wc = c['winning_conditions']?.toString();
    final em = c['evaluation_metric']?.toString();
    final sf = c['submission_format']?.toString();
    final rank = c['current_rank'];
    final score = c['current_score'];
    final bestScore = c['best_score'];
    final baseline = c['baseline_score'];
    final approach = c['approach']?.toString();
    final statusNotes = c['status_notes']?.toString();
    final notes = c['notes']?.toString();
    final updatedAt = c['metadata_updated_at']?.toString() ?? '';
    final updatedBy = c['metadata_updated_by']?.toString() ?? '';

    final hasAny = wc != null || em != null || sf != null || rank != null ||
        score != null || approach != null || statusNotes != null || notes != null;
    if (!hasAny) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPurple.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.smart_toy, size: 14, color: _kPurple),
          const SizedBox(width: 6),
          const Text('AGENT INTEL',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kTextMuted, letterSpacing: 1.5)),
          const Spacer(),
          if (updatedAt.isNotEmpty)
            Text(updatedAt.length >= 16 ? updatedAt.substring(0, 16) : updatedAt,
                style: const TextStyle(fontSize: 9, color: _kTextMuted, fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 10),

        // 현재 상태 (강조)
        if (statusNotes != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 16, color: _kAccent),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('현재 상태', style: TextStyle(fontSize: 10, color: _kTextMuted)),
                const SizedBox(height: 2),
                Text(statusNotes,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kText, height: 1.4)),
              ])),
            ]),
          ),
          const SizedBox(height: 10),
        ],

        // 점수/순위 카드
        if (rank != null || score != null || bestScore != null || baseline != null) ...[
          Row(children: [
            if (rank != null) _scoreStat('현재 순위', '#$rank', _kGold),
            if (rank != null && (score != null || bestScore != null)) const SizedBox(width: 8),
            if (score != null) _scoreStat('현재 점수', '$score', _kGreen),
            if (score != null && bestScore != null) const SizedBox(width: 8),
            if (bestScore != null) _scoreStat('최고 점수', '$bestScore', _kCyan),
            if (baseline != null) ...[
              const SizedBox(width: 8),
              _scoreStat('베이스라인', '$baseline', _kTextSec),
            ],
          ]),
          const SizedBox(height: 10),
        ],

        // 상세 정보
        if (wc != null) _metaRow(Icons.emoji_events, '우승 조건', wc, _kGold),
        if (em != null) _metaRow(Icons.analytics, '평가 지표', em, _kCyan),
        if (sf != null) _metaRow(Icons.upload_file, '제출 형식', sf, _kPurple),
        if (approach != null) _metaRow(Icons.science, '접근 방식', approach, _kAccent),
        if (notes != null) _metaRow(Icons.note, '노트', notes, _kTextSec),

        if (updatedBy.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Updated by $updatedBy',
                style: const TextStyle(fontSize: 9, color: _kTextMuted, fontStyle: FontStyle.italic)),
          ),
      ]),
    );
  }

  Widget _scoreStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color, fontFamily: 'monospace'),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(label, style: const TextStyle(fontSize: 9, color: _kTextMuted)),
        ]),
      ),
    );
  }

  Widget _metaRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 10),
        SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 11, color: _kTextMuted))),
        Expanded(child: Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kText, height: 1.4))),
      ]),
    );
  }

  // ══════════════════════════════════════
  // Lambda GPU Section (Live)
  // ══════════════════════════════════════

  Widget _lambdaSection(double totalCost, int totalInstances, int runningCount) {
    final totalLiveSpend = _lambdaRunning.fold<double>(0, (s, i) => s + ((i['live_spend'] as num?)?.toDouble() ?? 0));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _lambdaRunning.isNotEmpty ? _kWarning.withValues(alpha: 0.4) : _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.cloud, size: 14, color: _kWarning),
          const SizedBox(width: 6),
          const Text('LAMBDA GPU',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kTextMuted, letterSpacing: 1.5)),
          const Spacer(),
          if (_lambdaRunning.isNotEmpty) Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: _kGreen, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('${_lambdaRunning.length} LIVE',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kGreen)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),

        // 비용 요약 바
        Row(children: [
          _costStat('누적 비용', '\$${totalCost.toStringAsFixed(2)}', _kOrange),
          const SizedBox(width: 12),
          _costStat('현재 세션', '\$${totalLiveSpend.toStringAsFixed(2)}',
              totalLiveSpend > 10 ? _kRed : _kWarning),
          const SizedBox(width: 12),
          _costStat('총 실행', '$totalInstances회', _kCyan),
        ]),

        // 라이브 인스턴스
        if (_lambdaRunning.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._lambdaRunning.map((i) => _lambdaInstanceCard(i)),
        ],
      ]),
    );
  }

  Widget _costStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color, fontFamily: 'monospace')),
          Text(label, style: const TextStyle(fontSize: 9, color: _kTextMuted)),
        ]),
      ),
    );
  }

  Widget _lambdaInstanceCard(Map<String, dynamic> i) {
    final name = i['instance_name']?.toString() ?? i['name']?.toString() ?? '';
    final gpu = i['gpu_type']?.toString() ?? i['gpu']?.toString() ?? '';
    final ip = i['ip']?.toString() ?? '';
    final region = i['region']?.toString() ?? '';
    final rate = (i['rate_per_hour'] as num?)?.toDouble() ?? (i['price_per_hour'] as num?)?.toDouble() ?? 0;
    final liveHours = (i['live_duration_hours'] as num?)?.toDouble() ?? 0;
    final liveSpend = (i['live_spend'] as num?)?.toDouble() ?? 0;
    final status = i['status']?.toString() ?? 'active';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(
                color: status == 'active' || status == 'running' ? _kGreen : _kOrange,
                shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kText, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis),
          ),
          Text('\$${rate.toStringAsFixed(2)}/hr',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kOrange, fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          _infoChip(Icons.memory, gpu, _kCyan),
          if (ip.isNotEmpty) _infoChip(Icons.lan, ip, _kTextSec),
          if (region.isNotEmpty) _infoChip(Icons.location_on, region, _kTextSec),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.timer, size: 12, color: _kTextMuted),
          const SizedBox(width: 4),
          Text('${liveHours.toStringAsFixed(1)}h',
              style: const TextStyle(fontSize: 11, color: _kText, fontFamily: 'monospace')),
          const Spacer(),
          const Icon(Icons.attach_money, size: 12, color: _kWarning),
          Text('\$${liveSpend.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                  color: liveSpend > 50 ? _kRed : _kWarning, fontFamily: 'monospace')),
        ]),
      ]),
    );
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: color),
      const SizedBox(width: 3),
      Text(text, style: TextStyle(fontSize: 10, color: color)),
    ]);
  }

  // ══════════════════════════════════════
  // Progress Section
  // ══════════════════════════════════════

  Widget _progressSection(double progress, int total, int done, int inProg, int review, int blocked) {
    final backlog = total - done - review - inProg - blocked;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('PROGRESS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kTextMuted, letterSpacing: 1.5)),
          const Spacer(),
          Text('${progress.toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                  color: progress >= 100 ? _kGreen : _kAccent)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              if (done > 0) Expanded(flex: done, child: Container(color: _kGreen)),
              if (review > 0) Expanded(flex: review, child: Container(color: _kPurple)),
              if (inProg > 0) Expanded(flex: inProg, child: Container(color: _kAccent)),
              if (blocked > 0) Expanded(flex: blocked, child: Container(color: _kRed)),
              if (backlog > 0) Expanded(flex: backlog, child: Container(color: _kPanel)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 6, children: [
          _legendItem(_kGreen, 'Done $done'),
          if (review > 0) _legendItem(_kPurple, 'Review $review'),
          if (inProg > 0) _legendItem(_kAccent, 'InProgress $inProg'),
          if (blocked > 0) _legendItem(_kRed, 'Blocked $blocked'),
          _legendItem(_kPanel, 'Backlog $backlog'),
        ]),
      ]),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 10, color: _kTextSec)),
    ]);
  }

  // ══════════════════════════════════════
  // KPI Grid
  // ══════════════════════════════════════

  Widget _kpiGrid(int totalEvents, int reviews, double? avgScore, double? maxScore,
      int commits, int artifacts, int tickets) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('KPI',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kTextMuted, letterSpacing: 1.5)),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          _kpiCard(Icons.event_note, '$totalEvents', 'Events', _kAccent),
          _kpiCard(Icons.fact_check, '$reviews', 'Reviews', _kPurple),
          _kpiCard(Icons.star,
              avgScore != null ? avgScore.toStringAsFixed(1) : '-',
              maxScore != null ? 'Avg (max ${maxScore.toStringAsFixed(1)})' : 'Avg Score',
              avgScore != null ? (avgScore >= 4 ? _kGreen : avgScore >= 3 ? _kOrange : _kRed) : _kTextMuted),
          _kpiCard(Icons.commit, '$commits', 'Commits', _kCyan),
          _kpiCard(Icons.inventory_2, '$artifacts', 'Artifacts', _kWarning),
          _kpiCard(Icons.assignment, '$tickets', 'Tickets', _kGreen),
        ],
      ),
    ]);
  }

  Widget _kpiCard(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color, fontFamily: 'monospace')),
        Text(label,
            style: const TextStyle(fontSize: 9, color: _kTextMuted),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  // ══════════════════════════════════════
  // Teams Section
  // ══════════════════════════════════════

  Widget _teamsSection(List<Map<String, dynamic>> active, List<Map<String, dynamic>> archived) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('TEAMS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kTextMuted, letterSpacing: 1.5)),
          const Spacer(),
          Text('${active.length} active', style: const TextStyle(fontSize: 10, color: _kGreen, fontWeight: FontWeight.w600)),
          if (archived.isNotEmpty) ...[
            const Text(' / ', style: TextStyle(fontSize: 10, color: _kTextMuted)),
            Text('${archived.length} archived', style: const TextStyle(fontSize: 10, color: _kTextMuted)),
          ],
        ]),
        const SizedBox(height: 8),
        ...active.map((t) => _teamRow(t, false)),
        if (archived.isNotEmpty) ...[
          const Divider(color: _kBorder, height: 16),
          ...archived.take(5).map((t) => _teamRow(t, true)),
          if (archived.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+${archived.length - 5}개 아카이브',
                  style: const TextStyle(fontSize: 10, color: _kTextMuted)),
            ),
        ],
      ]),
    );
  }

  Widget _teamRow(Map<String, dynamic> t, bool archived) {
    final name = t['name']?.toString() ?? '';
    final members = ((t['members'] as List?) ?? []).cast<Map<String, dynamic>>();
    final ts = (t['ticket_stats'] as Map<String, dynamic>?) ?? {};
    final total = (ts['total'] as num?)?.toInt() ?? 0;
    final done = (ts['done'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: archived ? _kBorder : _kGreen.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(archived ? Icons.archive_outlined : Icons.groups, size: 14,
            color: archived ? _kTextMuted : _kGreen),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: archived ? _kTextMuted : _kText), overflow: TextOverflow.ellipsis),
            Text('${members.length} members / $done/$total tickets',
                style: const TextStyle(fontSize: 10, color: _kTextSec)),
          ]),
        ),
        if (total > 0)
          SizedBox(width: 50, child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total > 0 ? done / total : 0,
              minHeight: 4,
              backgroundColor: _kPanel,
              valueColor: AlwaysStoppedAnimation(archived ? _kTextMuted : _kGreen),
            ),
          )),
      ]),
    );
  }

  // ══════════════════════════════════════
  // Event Timeline (full + filters)
  // ══════════════════════════════════════

  Widget _eventTimeline() {
    final allTypes = <String>{};
    for (final e in _events) {
      final t = e['event_type']?.toString() ?? '';
      if (t.isNotEmpty) allTypes.add(t);
    }

    final filtered = _eventFilter == null
        ? _events
        : _events.where((e) => e['event_type'] == _eventFilter).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('TIMELINE',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kTextMuted, letterSpacing: 1.5)),
        const Spacer(),
        Text('${filtered.length}/${_events.length} events',
            style: const TextStyle(fontSize: 10, color: _kTextSec)),
      ]),
      const SizedBox(height: 8),

      // Filter chips
      if (allTypes.isNotEmpty) ...[
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _filterChip('전체', null, Icons.list),
              ...allTypes.map((t) {
                final (icon, color) = _eventStyle(t);
                return _filterChip(t.replaceAll('_', ' '), t, icon);
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],

      if (_loading && _events.isEmpty)
        const Center(child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
        ))
      else if (filtered.isEmpty)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder)),
          child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.history_outlined, size: 32, color: _kTextMuted),
            SizedBox(height: 8),
            Text('이벤트 없음', style: TextStyle(color: _kTextSec, fontSize: 12)),
          ])),
        )
      else ..._buildGroupedEvents(filtered),
    ]);
  }

  Widget _filterChip(String label, String? type, IconData icon) {
    final selected = _eventFilter == type;
    final (_, color) = type != null ? _eventStyle(type) : (Icons.list, _kAccent);
    return GestureDetector(
      onTap: () => setState(() => _eventFilter = type),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : _kPanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? color : _kBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: selected ? color : _kTextMuted),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: selected ? color : _kTextSec)),
        ]),
      ),
    );
  }

  List<Widget> _buildGroupedEvents(List<Map<String, dynamic>> events) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final e in events) {
      final ts = e['created_at']?.toString() ?? '';
      final date = ts.length >= 10 ? ts.substring(0, 10) : 'unknown';
      grouped.putIfAbsent(date, () => []).add(e);
    }

    final widgets = <Widget>[];
    final dates = grouped.keys.toList();
    for (int i = 0; i < dates.length; i++) {
      final date = dates[i];
      final dayEvents = grouped[date]!;
      widgets.add(Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kPanel,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today, size: 12, color: _kTextSec),
              const SizedBox(width: 6),
              Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kText)),
              const Spacer(),
              Text('${dayEvents.length}', style: const TextStyle(fontSize: 11, color: _kTextMuted)),
            ]),
          ),
          ...dayEvents.map((e) => _eventRow(e)),
        ]),
      ));
    }
    return widgets;
  }

  Widget _eventRow(Map<String, dynamic> e) {
    final type = e['event_type']?.toString() ?? '';
    final title = e['title']?.toString() ?? '';
    final detail = e['detail']?.toString() ?? '';
    final ts = e['created_at']?.toString() ?? '';
    final score = (e['score'] as num?)?.toDouble();
    final time = ts.length >= 16 ? ts.substring(11, 16) : '';
    final (icon, color) = _eventStyle(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorder, width: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 24, height: 24,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 14, color: color)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.isNotEmpty ? title : type.replaceAll('_', ' '),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kText),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          if (detail.isNotEmpty)
            Text(detail, style: const TextStyle(fontSize: 10, color: _kTextSec),
                maxLines: 3, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(time, style: const TextStyle(fontSize: 10, color: _kTextMuted, fontFamily: 'monospace')),
          if (score != null) Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: (score >= 4 ? _kGreen : score >= 3 ? _kOrange : _kRed).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(score.toStringAsFixed(1),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: score >= 4 ? _kGreen : score >= 3 ? _kOrange : _kRed)),
          ),
        ]),
      ]),
    );
  }

  (IconData, Color) _eventStyle(String type) {
    return switch (type) {
      'status_changed' => (Icons.swap_horiz, _kAccent),
      'ticket_created' => (Icons.note_add, _kGreen),
      'ticket_claimed' => (Icons.person_add, _kCyan),
      'artifact_created' => (Icons.inventory_2, _kWarning),
      'supervisor_review' => (Icons.fact_check, _kPurple),
      'git_commit' => (Icons.commit, _kCyan),
      'progress_updated' => (Icons.trending_up, _kAccent),
      'sprint_phase_changed' => (Icons.speed, _kOrange),
      'sprint_gate_evaluated' => (Icons.security, _kGold),
      _ => (Icons.circle, _kTextSec),
    };
  }

  // ══════════════════════════════════════
  // Helper Widgets
  // ══════════════════════════════════════

  Widget _statusBadge(String status) {
    final (label, color) = switch (status) {
      'writeup_posted' => ('WRITEUP POSTED', _kPurple),
      'submitted' => ('SUBMITTED', _kGreen),
      _ => ('IN PROGRESS', _kAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _ddayBadge(String dday, int ddayNum) {
    final color = dday == 'D-DAY' || ddayNum <= 0 ? _kRed
        : ddayNum <= 7 ? _kRed
        : ddayNum <= 30 ? _kOrange : _kTextSec;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(dday,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color, fontFamily: 'monospace')),
    );
  }

  String _fmtNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }
}
