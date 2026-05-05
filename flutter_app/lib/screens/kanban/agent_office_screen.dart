import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';

class AgentOfficeScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  const AgentOfficeScreen({super.key, required this.teamId, required this.teamName});
  @override
  State<AgentOfficeScreen> createState() => _AgentOfficeScreenState();
}

/// 역할 → 스프라이트/구역 매핑.
/// outfitIdx 1-6 (실제 assets/sprites/outfit1~6.png),
/// hairRow 0-7 (hairs.png 8줄),
/// zone: 'dev-left' | 'dev-right' | 'qa' | 'center' | 'corner'.
class _RoleStyle {
  final int outfitIdx;
  final int hairRow;
  final String zone;
  final String deskType; // 'dual-monitor' | 'laptop' | 'sofa' | 'round-table'
  final String emoji;
  const _RoleStyle(this.outfitIdx, this.hairRow, this.zone, this.deskType, this.emoji);
}

const Map<String, _RoleStyle> _kRoleStyleMap = {
  // Frontend 계열
  'frontend': _RoleStyle(1, 0, 'dev-left', 'dual-monitor', '🎨'),
  'ui': _RoleStyle(1, 0, 'dev-left', 'dual-monitor', '🎨'),
  'design': _RoleStyle(1, 1, 'dev-left', 'dual-monitor', '🖌️'),
  'electron': _RoleStyle(1, 2, 'dev-left', 'dual-monitor', '🖥️'),
  // Backend 계열
  'backend': _RoleStyle(2, 1, 'dev-right', 'dual-monitor', '⚙️'),
  'server': _RoleStyle(2, 1, 'dev-right', 'dual-monitor', '🖧'),
  'go-backend': _RoleStyle(2, 2, 'dev-right', 'dual-monitor', '🐹'),
  'py-backend': _RoleStyle(2, 3, 'dev-right', 'dual-monitor', '🐍'),
  'mes-core': _RoleStyle(2, 4, 'dev-right', 'dual-monitor', '🏭'),
  'auth': _RoleStyle(2, 5, 'dev-right', 'laptop', '🔐'),
  'security': _RoleStyle(2, 6, 'dev-right', 'laptop', '🛡️'),
  // DB 계열
  'sqlite': _RoleStyle(3, 2, 'dev-left', 'laptop', '🗄️'),
  'db': _RoleStyle(3, 2, 'dev-left', 'laptop', '🗃️'),
  'oracle-db': _RoleStyle(3, 3, 'dev-left', 'laptop', '🛢️'),
  'postgres-db': _RoleStyle(3, 4, 'dev-left', 'laptop', '🐘'),
  'db-postgres': _RoleStyle(3, 4, 'dev-left', 'laptop', '🐘'),
  'equip-db': _RoleStyle(3, 5, 'dev-left', 'laptop', '📊'),
  'tool-db': _RoleStyle(3, 6, 'dev-left', 'laptop', '📊'),
  // QA 계열
  'qa': _RoleStyle(4, 3, 'qa', 'sofa', '🔍'),
  'test': _RoleStyle(4, 3, 'qa', 'sofa', '🧪'),
  'build': _RoleStyle(4, 4, 'qa', 'sofa', '🔨'),
  // Orchestrator / Supervisor / Management
  'orchestrator': _RoleStyle(5, 0, 'center', 'round-table', '🎯'),
  'supervisor': _RoleStyle(5, 4, 'center', 'round-table', '👑'),
  'architect': _RoleStyle(5, 2, 'center', 'round-table', '🏗️'),
  'devops': _RoleStyle(5, 5, 'corner', 'laptop', '🚀'),
  'cs': _RoleStyle(5, 6, 'corner', 'laptop', '💬'),
  'docs': _RoleStyle(5, 7, 'corner', 'laptop', '📚'),
  'legal': _RoleStyle(5, 1, 'corner', 'laptop', '⚖️'),
  'tax': _RoleStyle(5, 2, 'corner', 'laptop', '💰'),
  // Mobile / Flutter
  'flutter': _RoleStyle(6, 5, 'dev-left', 'dual-monitor', '📱'),
  'mobile': _RoleStyle(6, 5, 'dev-left', 'dual-monitor', '📱'),
  'ollama': _RoleStyle(6, 6, 'corner', 'dual-monitor', '🤖'),
  // U2DIA 전문 도메인 (CNC/가공)
  'machining': _RoleStyle(2, 0, 'dev-right', 'dual-monitor', '🔧'),
  'equipment': _RoleStyle(2, 1, 'dev-right', 'dual-monitor', '🛠️'),
  'tooling': _RoleStyle(2, 2, 'dev-right', 'dual-monitor', '⚒️'),
  'cutting': _RoleStyle(2, 3, 'dev-right', 'dual-monitor', '✂️'),
  'nc-code': _RoleStyle(1, 4, 'dev-left', 'dual-monitor', '📟'),
  'post-proc': _RoleStyle(1, 5, 'dev-left', 'dual-monitor', '📄'),
  'controller': _RoleStyle(2, 6, 'dev-right', 'laptop', '🎛️'),
  'fea': _RoleStyle(3, 0, 'dev-left', 'laptop', '🧮'),
  'mesh': _RoleStyle(3, 1, 'dev-left', 'laptop', '🔷'),
  // Commerce / Payment
  'payment': _RoleStyle(5, 3, 'corner', 'laptop', '💳'),
  'product': _RoleStyle(1, 2, 'dev-left', 'laptop', '📦'),
  'order': _RoleStyle(2, 4, 'dev-right', 'laptop', '📋'),
  'ai-recommend': _RoleStyle(6, 7, 'corner', 'laptop', '🤖'),
  'i18n': _RoleStyle(1, 3, 'corner', 'laptop', '🌐'),
  // Simulator
  'nc-interp': _RoleStyle(2, 5, 'dev-right', 'dual-monitor', '🎯'),
  '3d-viz': _RoleStyle(1, 6, 'dev-left', 'dual-monitor', '🧊'),
  'backplot': _RoleStyle(1, 7, 'dev-left', 'dual-monitor', '📈'),
  'physics': _RoleStyle(3, 6, 'dev-left', 'laptop', '⚛️'),
};

_RoleStyle _styleForRole(String role, int seed) {
  final r = role.toLowerCase().trim();
  if (_kRoleStyleMap.containsKey(r)) return _kRoleStyleMap[r]!;
  // 키워드 부분 매칭
  for (final e in _kRoleStyleMap.entries) {
    if (r.contains(e.key) || e.key.contains(r)) return e.value;
  }
  // fallback: seed 기반 (호환성 유지)
  final zones = ['dev-left', 'dev-right', 'qa', 'corner'];
  final desks = ['dual-monitor', 'laptop', 'sofa'];
  return _RoleStyle(
    (seed.abs() % 6) + 1,
    (seed.abs() ~/ 6) % 8,
    zones[seed.abs() % zones.length],
    desks[seed.abs() % desks.length],
    '💼',
  );
}

class _AgentOfficeScreenState extends State<AgentOfficeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  List<_Agent> _agents = [];
  List<_Desk> _desks = [];
  List<_Furniture> _furniture = [];
  List<_Particle> _particles = [];
  Map<String, dynamic> _boardData = {};
  bool _loading = true;
  final _rand = Random();
  int _frame = 0;
  double _parallax = 0;
  // 동적 월드 크기 (가로 확장 지원)
  double _worldW = 480;
  double _worldH = 220;

  final idleChats = [
    '오늘 날씨 좋다~', '주말 뭐 해?', '커피 한잔 할까?', '점심 뭐 먹지?',
    '어제 드라마 봤어?', '새 키보드 샀어', '운동 가야하는데...', '책 추천해줘',
    '🎮 게임 한판?', '🎵 이 노래 좋다', '📚 독서 중', '✏️ 낙서 중',
    '🎸 기타 연습', '🧩 퍼즐 푸는중', '🎨 그림 그리는중', '📱 유튜브 보는중',
    '☁️ 구름 예쁘다', '🌅 노을 보여', '🌧️ 비 온다~', '🍂 가을이네',
    '리뷰 좀 봐줘', '이 API 어때?', 'PR 올렸어', '코드 깔끔하네',
    '디자인 바꿔야해', '스프린트 언제?', '테스트 통과!', '배포 준비 됐어?',
  ];

  // 스프라이트 이미지
  ui.Image? _bodyImg;
  ui.Image? _hairsImg;
  ui.Image? _shadowImg;
  final Map<int, ui.Image> _outfitImgs = {};

  @override
  void initState() {
    super.initState();
    // 가로 모드 강제 전환 (이슈 5)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _animCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 999))..repeat();
    _animCtrl.addListener(_tick);
    _loadAll();
  }

  @override
  void dispose() {
    _animCtrl.removeListener(_tick);
    _animCtrl.dispose();
    // 모든 방향 복원 (세로 우선이지만 나머지 화면도 정상 동작하게)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    _frame++;
    if (_frame % 2 == 0) _update();
    // 미묘한 패럴랙스 (20초 주기)
    _parallax = sin(_frame * 0.004) * 4;
    setState(() {});
  }

  Future<ui.Image> _loadImage(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _loadAll() async {
    try {
      _bodyImg = await _loadImage('assets/sprites/character.png');
      _hairsImg = await _loadImage('assets/sprites/hairs.png');
      _shadowImg = await _loadImage('assets/sprites/shadow.png');
      for (var i = 1; i <= 6; i++) {
        _outfitImgs[i] = await _loadImage('assets/sprites/outfit$i.png');
      }
    } catch (e) {
      debugPrint('Sprite load error: $e');
    }

    final api = context.read<ApiService>();
    final res = await api.getBoard(widget.teamId);
    if (mounted) {
      _boardData = (res['ok'] == true ? (res['board'] as Map<String, dynamic>?) : null) ?? {};
      if ((_boardData['project_group']?.toString() ?? '').isEmpty) {
        _boardData['project_group'] = widget.teamName;
      }
      _initOffice();
      setState(() => _loading = false);
    }
  }

  void _initOffice() {
    final members = (_boardData['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tickets = (_boardData['tickets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final isIdle = tickets.where((t) => t['status'] == 'InProgress' || t['status'] == 'Review').isEmpty;

    // 프로젝트 전문가 역할 목록 (CLAUDE.md 기반 — 최소 인원 보장)
    const projectRoles = {
      'U2DIA AI': ['machining', 'equipment', 'tooling', 'cutting', 'nc-code', 'post-proc', 'controller', 'ui', 'oracle-db', 'postgres-db', 'go-backend', 'py-backend', 'frontend', 'fea', 'mesh', 'security', 'legal', 'qa', 'devops', 'cs'],
      'LINKO': ['mes-core', 'frontend', 'db-postgres', 'backend', 'auth', 'i18n', 'payment', 'cs', 'legal', 'tax', 'security', 'build', 'qa', 'docs'],
      'U2DIA Commerce AI': ['frontend', 'backend', 'auth', 'payment', 'product', 'order', 'ai-recommend', 'cs', 'legal', 'tax', 'security', 'qa'],
      'u2dia_simulator': ['nc-interp', '3d-viz', 'backplot', 'physics', 'controller', 'frontend', 'backend', 'db', 'equip-db', 'tool-db', 'i18n', 'security', 'qa'],
      'U2DIA-KANBAN-BOARD': ['server', 'sqlite', 'flutter', 'electron', 'ollama', 'supervisor', 'devops', 'security', 'qa'],
    };

    final pg = _boardData['project_group']?.toString() ?? widget.teamName;
    var roles = projectRoles[pg] ?? <String>[];
    if (roles.isEmpty) {
      final pgLower = pg.toLowerCase();
      for (final e in projectRoles.entries) {
        if (pgLower.contains(e.key.toLowerCase()) || e.key.toLowerCase().contains(pgLower)) {
          roles = e.value; break;
        }
      }
    }
    if (roles.isEmpty) roles = ['frontend', 'backend', 'qa', 'devops', 'architect'];

    // 이슈 3: clamp 제거. 실제 멤버 수 사용 (부족하면 역할 placeholder 로 채움).
    // members 가 roles 보다 많으면 그대로 다 보여줌.
    final agentCount = members.isEmpty
        ? roles.length
        : (members.length >= roles.length ? members.length : roles.length);

    // 월드 크기: 에이전트가 많아지면 가로로 확장 (스크롤/축소로 대응)
    _worldW = (agentCount <= 10) ? 480.0
        : (agentCount <= 20) ? 620.0
        : (agentCount <= 30) ? 780.0
        : 780.0 + (agentCount - 30) * 24.0;
    _worldH = 260.0;

    // 이슈 6: 구역 기반 책상 배치 (네오 SaaS 오피스)
    // 좌측 개발 존 (dev-left, dev-right), 중앙 미팅 존 (center), 우측 QA 존 (qa), 모서리 (corner)
    _desks = [];
    _furniture = _buildFurniture();

    // 효과적 멤버 리스트 준비
    final effectiveMembers = List<Map<String, dynamic>>.from(members);
    if (effectiveMembers.length < agentCount) {
      for (var i = effectiveMembers.length; i < agentCount; i++) {
        final roleName = i < roles.length ? roles[i] : 'agent-${i + 1}';
        effectiveMembers.add(<String, dynamic>{
          'display_name': roleName,
          'member_id': 'role-$roleName-$i',
          'role': roleName,
          'status': 'Idle',
        });
      }
    }

    // 1단계: 역할별로 멤버 분류
    final byZone = <String, List<int>>{
      'dev-left': [], 'dev-right': [], 'qa': [], 'center': [], 'corner': [],
    };
    final memberStyles = <_RoleStyle>[];
    for (var i = 0; i < effectiveMembers.length; i++) {
      final m = effectiveMembers[i];
      final role = (m['role'] ?? 'agent') as String;
      final mid = (m['member_id'] ?? '') as String;
      var seed = 0;
      for (var c = 0; c < mid.length; c++) seed = seed * 31 + mid.codeUnitAt(c);
      final style = _styleForRole(role, seed);
      memberStyles.add(style);
      byZone[style.zone]!.add(i);
    }

    // 2단계: 각 구역마다 책상 배치 (구역 중심을 기준으로 그리드)
    // 구역 좌표 (월드 기준, _worldW / _worldH 에 비례)
    final zoneRects = <String, Rect>{
      'dev-left': Rect.fromLTWH(30, 70, _worldW * 0.32, _worldH * 0.55),
      'dev-right': Rect.fromLTWH(_worldW * 0.35, 70, _worldW * 0.30, _worldH * 0.55),
      'qa': Rect.fromLTWH(_worldW * 0.70, 70, _worldW * 0.25, _worldH * 0.40),
      'center': Rect.fromLTWH(_worldW * 0.38, _worldH * 0.58, _worldW * 0.25, _worldH * 0.28),
      'corner': Rect.fromLTWH(_worldW * 0.70, _worldH * 0.55, _worldW * 0.25, _worldH * 0.35),
    };

    // 역할 -> 책상 매핑
    final deskMap = <int, int>{}; // memberIdx -> deskIdx
    for (final zone in byZone.keys) {
      final ids = byZone[zone]!;
      if (ids.isEmpty) continue;
      final r = zoneRects[zone]!;
      final cols = zone == 'center' ? 2 : (zone == 'corner' ? 2 : 3);
      final rows = ((ids.length / cols).ceil()).clamp(1, 10);
      final cellW = r.width / cols;
      final cellH = r.height / rows;
      for (var k = 0; k < ids.length; k++) {
        final col = k % cols;
        final row = k ~/ cols;
        final dx = r.left + col * cellW + cellW * 0.25;
        final dy = r.top + row * cellH + cellH * 0.30;
        final deskType = memberStyles[ids[k]].deskType;
        final deskIdx = _desks.length;
        _desks.add(_Desk(
          x: dx, y: dy, screenOn: false,
          type: deskType, zone: zone,
        ));
        deskMap[ids[k]] = deskIdx;
      }
    }

    _agents = [];
    for (var j = 0; j < effectiveMembers.length; j++) {
      final m = effectiveMembers[j];
      final mid = (m['member_id'] ?? '') as String;
      var seed = 0;
      for (var c = 0; c < mid.length; c++) seed = seed * 31 + mid.codeUnitAt(c);

      Map<String, dynamic>? ticket;
      if (members.isNotEmpty) {
        for (final t in tickets) {
          if (t['assigned_member_id'] == mid && t['status'] == 'InProgress') { ticket = t; break; }
        }
      }

      final deskIdx = deskMap[j] ?? (j % _desks.length);
      final desk = _desks[deskIdx];
      desk.screenOn = ticket != null;

      final style = memberStyles[j];

      // 멤버 display_name 우선, 없으면 역할 기반 이름
      const sampleNames = [
        'Alex', 'Blake', 'Casey', 'Dana', 'Ellis', 'Finn', 'Gray', 'Harper',
        'Ivy', 'Jules', 'Kit', 'Logan', 'Max', 'Noel', 'Owen', 'Parker',
        'Quinn', 'Riley', 'Sam', 'Tay', 'Uma', 'Val', 'Wren', 'Xia',
        'Yuri', 'Zane', 'Ash', 'Brook', 'Clay', 'Drew',
      ];
      final rawName = (m['display_name'] ?? '') as String;
      final displayName = rawName.isNotEmpty
          ? rawName
          : sampleNames[seed.abs() % sampleNames.length];

      // 역할에서 티켓 상태 파생
      String agentState = 'idle';
      if (!isIdle && ticket != null) agentState = 'working';
      // 멤버 status 필드로 override 가능
      final memberStatus = (m['status'] ?? '').toString().toLowerCase();
      if (memberStatus.contains('review')) agentState = 'review';
      if (memberStatus.contains('blocked')) agentState = 'blocked';

      _agents.add(_Agent(
        name: displayName.substring(0, min(12, displayName.length)),
        role: (m['role'] ?? 'agent') as String,
        roleEmoji: style.emoji,
        x: desk.x + 6, y: desk.y + 16,
        targetX: desk.x + 6, targetY: desk.y + 16,
        skinRow: seed.abs() % 6,
        hairRow: style.hairRow % 8,
        outfitIdx: style.outfitIdx.clamp(1, 6),
        animFrame: _rand.nextInt(4), direction: 0,
        state: (members.isEmpty || isIdle) ? 'idle' : agentState,
        ticketTitle: ticket != null ? (ticket['title'] ?? '').toString() : '',
        deskIdx: deskIdx,
        stateTimer: 50 + _rand.nextInt(150),
        chatMsg: (members.isEmpty || isIdle)
            ? idleChats[j % idleChats.length]
            : (ticket != null
                ? '💻 ${(ticket['title'] ?? '').toString().substring(0, min(14, (ticket['title'] ?? '').toString().length))}'
                : ''),
        chatTimer: 80 + _rand.nextInt(100),
        bobPhase: _rand.nextDouble() * pi * 2,
        vx: 0, vy: 0,
      ));
    }
    _particles = [];
  }

  /// 사무실 가구 배치 (이슈 6).
  /// LED 스트립, 화분, 화이트보드, 포스터, 시계, 커피머신, 카펫, 회의 테이블 등.
  List<_Furniture> _buildFurniture() {
    final w = _worldW, h = _worldH;
    return [
      // 카펫 (중앙 미팅 존)
      _Furniture(type: 'carpet', x: w * 0.37, y: h * 0.57, w: w * 0.27, h: h * 0.30,
          color: const Color(0xFF2f3b52)),
      // 카펫 (QA 존)
      _Furniture(type: 'carpet', x: w * 0.70, y: h * 0.25, w: w * 0.25, h: h * 0.30,
          color: const Color(0xFF352a3e)),
      // 중앙 원형 미팅 테이블
      _Furniture(type: 'round-table', x: w * 0.48, y: h * 0.72, w: 46, h: 18,
          color: const Color(0xFF6d5436)),
      // QA 소파 (우측)
      _Furniture(type: 'sofa', x: w * 0.72, y: h * 0.32, w: 52, h: 14,
          color: const Color(0xFF4c3a5e)),
      _Furniture(type: 'sofa', x: w * 0.82, y: h * 0.32, w: 38, h: 14,
          color: const Color(0xFF4c3a5e)),
      // 화이트보드 (좌측 벽)
      _Furniture(type: 'whiteboard', x: w * 0.04, y: 24, w: 52, h: 20,
          color: const Color(0xFFe6edf3)),
      // 포스터 U2DIA (중앙 벽)
      _Furniture(type: 'poster', x: w * 0.44, y: 22, w: 28, h: 20,
          color: const Color(0xFF3b82f6)),
      // 시계 (우측 벽)
      _Furniture(type: 'clock', x: w * 0.88, y: 28, w: 10, h: 10,
          color: const Color(0xFFe6edf3)),
      // 화분 (창가)
      _Furniture(type: 'plant', x: w * 0.10, y: h * 0.48, w: 8, h: 12, color: const Color(0xFF22c55e)),
      _Furniture(type: 'plant', x: w * 0.30, y: h * 0.48, w: 8, h: 12, color: const Color(0xFF22c55e)),
      _Furniture(type: 'plant', x: w * 0.55, y: h * 0.48, w: 8, h: 12, color: const Color(0xFF22c55e)),
      _Furniture(type: 'plant', x: w * 0.92, y: h * 0.78, w: 8, h: 12, color: const Color(0xFF22c55e)),
      // 커피머신 (좌측 구석)
      _Furniture(type: 'coffee', x: w * 0.02, y: h * 0.80, w: 10, h: 16,
          color: const Color(0xFF5a3d2a)),
      // 정수기 (우측 구석)
      _Furniture(type: 'water', x: w * 0.95, y: h * 0.90, w: 8, h: 18,
          color: const Color(0xFF38bdf8)),
      // LED 스트립 (천장 전체)
      _Furniture(type: 'led-strip', x: 0, y: 18, w: w, h: 1.2,
          color: const Color(0xFF38bdf8)),
    ];
  }

  void _update() {
    final w = _worldW, h = _worldH;
    for (final a in _agents) {
      a.stateTimer--;
      if (_frame % 8 == 0) a.animFrame = (a.animFrame + 1) % 4;
      a.bobPhase += 0.08; // idle bob
      if (a.stateTimer <= 0) {
        if (a.state == 'working') {
          if (_rand.nextDouble() < 0.1) {
            a.state = 'walking'; a.targetX = 10 + _rand.nextDouble() * 40; a.targetY = h - 24;
            a.chatMsg = '☕'; a.chatTimer = 80; a.stateTimer = 80;
          } else {
            a.stateTimer = 60 + _rand.nextInt(120);
            _particles.add(_Particle(x: a.x + 5, y: a.y - 5, life: 25,
                text: ['{}', '()', '=>', 'fn', '++'][_rand.nextInt(5)]));
          }
        } else if (a.state == 'idle') {
          final r = _rand.nextDouble();
          if (r < 0.35) {
            a.state = 'walking';
            if (_agents.length > 1) {
              final target = _agents[_rand.nextInt(_agents.length)];
              a.targetX = target.x + (_rand.nextDouble() - 0.5) * 12;
              a.targetY = target.y + (_rand.nextDouble() - 0.5) * 12;
            } else {
              a.targetX = 10 + _rand.nextDouble() * (w - 20);
              a.targetY = 10 + _rand.nextDouble() * (h - 20);
            }
            a.stateTimer = 60 + _rand.nextInt(80);
            a.chatMsg = idleChats[_rand.nextInt(idleChats.length)]; a.chatTimer = 120;
          } else if (r < 0.5) {
            a.state = 'walking';
            a.targetX = 30 + _rand.nextDouble() * (w - 60);
            a.targetY = 22;
            a.stateTimer = 80 + _rand.nextInt(60);
            a.chatMsg = ['☁️ ...', '🌅 예쁘다', '🌧️ 비온다', '🍃 바람~'][_rand.nextInt(4)];
            a.chatTimer = 100;
          } else {
            a.stateTimer = 50 + _rand.nextInt(80);
            a.chatMsg = idleChats[_rand.nextInt(idleChats.length)];
            a.chatTimer = 100;
          }
        } else if (a.state == 'review' || a.state == 'blocked') {
          // 유지
          a.stateTimer = 80 + _rand.nextInt(60);
        } else {
          final desk = _desks[a.deskIdx.clamp(0, _desks.length - 1)];
          a.targetX = desk.x + 6; a.targetY = desk.y + 16;
          a.state = a.ticketTitle.isNotEmpty ? 'working' : 'idle';
          a.stateTimer = 60 + _rand.nextInt(120);
        }
      }
      final dx = a.targetX - a.x, dy = a.targetY - a.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 1) {
        a.vx = dx / dist * 0.55; a.vy = dy / dist * 0.55;
        a.x += a.vx; a.y += a.vy;
        a.direction = dx.abs() > dy.abs() ? (dx > 0 ? 2 : 1) : (dy > 0 ? 0 : 3);
      } else { a.vx = 0; a.vy = 0; }
      if (a.chatTimer > 0) a.chatTimer--;
    }
    _particles.removeWhere((p) { p.y -= 0.2; p.life--; return p.life <= 0; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f1424),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151a2e),
        title: Row(children: [
          const Text('🏢 ', style: TextStyle(fontSize: 18)),
          Expanded(child: Text(widget.teamName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFe6edf3)),
              overflow: TextOverflow.ellipsis)),
          // 에이전트 수 뱃지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF22305a),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('👥 ${_agents.length}',
                style: const TextStyle(color: Color(0xFF8fb4ff), fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3b82f6)))
          : Column(children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // FittedBox + InteractiveViewer 로 작으면 확대, 크면 축소
                    return InteractiveViewer(
                      minScale: 0.4,
                      maxScale: 4.0,
                      boundaryMargin: const EdgeInsets.all(80),
                      child: ClipRect(
                        child: CustomPaint(
                          painter: _OfficePainter(
                            agents: _agents, desks: _desks, furniture: _furniture,
                            particles: _particles, frame: _frame, parallax: _parallax,
                            worldW: _worldW, worldH: _worldH,
                            bodyImg: _bodyImg, hairsImg: _hairsImg,
                            shadowImg: _shadowImg, outfitImgs: _outfitImgs,
                          ),
                          size: Size(constraints.maxWidth, constraints.maxHeight),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _buildStatusBar(),
            ]),
    );
  }

  Widget _buildStatusBar() {
    final tickets = (_boardData['tickets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final done = tickets.where((t) => t['status'] == 'Done').length;
    final total = tickets.length;
    final pct = total > 0 ? (done / total * 100).toInt() : 0;
    final ip = tickets.where((t) => t['status'] == 'InProgress').length;
    final rv = tickets.where((t) => t['status'] == 'Review').length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF151a2e),
        border: Border(top: BorderSide(color: Color(0xFF2a3356))),
      ),
      child: Row(children: [
        Text('👥 ${_agents.length}명', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
        const SizedBox(width: 12),
        Text('🔄 $ip', style: const TextStyle(color: Color(0xFF3b82f6), fontSize: 11)),
        const SizedBox(width: 8),
        Text('🔍 $rv', style: const TextStyle(color: Color(0xFFf59e0b), fontSize: 11)),
        const SizedBox(width: 8),
        Text('✅ $done/$total', style: const TextStyle(color: Color(0xFF22c55e), fontSize: 11)),
        const Spacer(),
        SizedBox(width: 80, height: 4, child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
                value: pct / 100, minHeight: 4,
                backgroundColor: const Color(0xFF1e2740),
                valueColor: AlwaysStoppedAnimation(
                    pct >= 80 ? const Color(0xFF22c55e) : const Color(0xFF3b82f6))))),
        const SizedBox(width: 6),
        Text('$pct%',
            style: TextStyle(
                color: pct >= 80 ? const Color(0xFF22c55e) : const Color(0xFF3b82f6),
                fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _OfficePainter extends CustomPainter {
  final List<_Agent> agents;
  final List<_Desk> desks;
  final List<_Furniture> furniture;
  final List<_Particle> particles;
  final int frame;
  final double parallax;
  final double worldW, worldH;
  final ui.Image? bodyImg, hairsImg, shadowImg;
  final Map<int, ui.Image> outfitImgs;

  _OfficePainter({
    required this.agents, required this.desks, required this.furniture,
    required this.particles, required this.frame, required this.parallax,
    required this.worldW, required this.worldH,
    this.bodyImg, this.hairsImg, this.shadowImg, required this.outfitImgs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = worldW, h = worldH;
    // 캔버스에 맞도록 fit (가로 비율 고정, 여백은 캔버스 배경)
    final s = min(size.width / w, size.height / h);
    final offsetX = (size.width - w * s) / 2;
    final offsetY = (size.height - h * s) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(s, s);

    // ─── 배경: 다크 네이비 그라데이션 벽 ───
    final wallRect = Rect.fromLTWH(0, 0, w, h * 0.42);
    canvas.drawRect(wallRect, Paint()..shader = ui.Gradient.linear(
      Offset(0, 0), Offset(0, h * 0.42),
      [const Color(0xFF1a2140), const Color(0xFF2a3565), const Color(0xFF1e2750)],
      [0, 0.5, 1],
    ));
    // 벽 세로 라인 (고급감)
    final wallLine = Paint()..color = const Color(0xFF2d3a68)..strokeWidth = 0.4;
    for (var x = 20.0; x < w; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, h * 0.42), wallLine);
    }

    // 베이스보드
    canvas.drawRect(Rect.fromLTWH(0, h * 0.42 - 3, w, 3),
        Paint()..color = const Color(0xFF141930));

    // ─── 바닥: 오피스 타일 (회색 + 우드 섹션) ───
    for (var tx = 0.0; tx < w; tx += 18) {
      for (var ty = h * 0.42; ty < h; ty += 18) {
        final isCarpetArea = _isInCarpet(tx, ty);
        if (isCarpetArea) continue;
        // 타일 체크 패턴
        final even = ((tx ~/ 18 + ty ~/ 18) % 2 == 0);
        canvas.drawRect(Rect.fromLTWH(tx, ty, 18, 18),
            Paint()..color = even ? const Color(0xFF2a2f3d) : const Color(0xFF252a38));
        // 타일 라인
        canvas.drawLine(Offset(tx, ty), Offset(tx + 18, ty),
            Paint()..color = const Color(0xFF1f2430)..strokeWidth = 0.15);
      }
    }

    // ─── 창문 (벽 위에 햇빛 ray) ───
    final windowCount = (w / 90).floor().clamp(3, 10);
    for (var wi = 0; wi < windowCount; wi++) {
      final wx = 20.0 + wi * (w - 40) / windowCount + parallax * 0.3;
      final wy = 6.0;
      // 창틀
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(wx, wy, 48, 22), const Radius.circular(1.5)),
          Paint()..color = const Color(0xFF0b1630));
      // 유리 (그라데이션: 하늘 → 연한 파랑)
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(wx + 1, wy + 1, 46, 20), const Radius.circular(1)),
          Paint()..shader = ui.Gradient.linear(
              Offset(wx, wy), Offset(wx, wy + 22),
              [const Color(0xFF67a8e8), const Color(0xFFa8d4f5)]));
      // 창틀 크로스
      canvas.drawLine(Offset(wx + 24, wy), Offset(wx + 24, wy + 22),
          Paint()..color = const Color(0xFF0b1630)..strokeWidth = 0.8);
      canvas.drawLine(Offset(wx, wy + 11), Offset(wx + 48, wy + 11),
          Paint()..color = const Color(0xFF0b1630)..strokeWidth = 0.8);
      // 햇빛 ray (아래쪽으로 퍼지는 삼각형)
      final rayPaint = Paint()..shader = ui.Gradient.linear(
          Offset(wx + 24, wy + 22), Offset(wx + 24, wy + 80),
          [const Color(0xFFfff6c8).withOpacity(0.18), const Color(0xFFfff6c8).withOpacity(0.0)]);
      final rayPath = Path()
        ..moveTo(wx + 6, wy + 22)
        ..lineTo(wx + 42, wy + 22)
        ..lineTo(wx + 58, wy + 80)
        ..lineTo(wx - 10, wy + 80)
        ..close();
      canvas.drawPath(rayPath, rayPaint);
    }

    // ─── 가구 ───
    _drawFurniture(canvas);

    // ─── 데스크 ───
    for (final d in desks) {
      _drawDesk(canvas, d);
    }

    // ─── 에이전트 ───
    final sorted = List<_Agent>.from(agents)..sort((a, b) => a.y.compareTo(b.y));
    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (final a in sorted) {
      final x = a.x;
      // idle bob (미세 흔들림)
      final bob = (a.state == 'idle' || a.state == 'working') ? sin(a.bobPhase) * 0.35 : 0.0;
      final y = a.y + bob;

      // 그림자
      if (shadowImg != null) {
        canvas.drawImageRect(shadowImg!,
            const Rect.fromLTWH(0, 0, 32, 32),
            Rect.fromLTWH(x - 1, a.y + 6, 10, 3),
            Paint()..color = Colors.black.withOpacity(0.5));
      }

      // 스프라이트 프레임
      final isMoving = a.vx.abs() > 0.1 || a.vy.abs() > 0.1;
      final col = isMoving
          ? (a.direction * 4 + a.animFrame % 4)
          : (a.direction * 4 + ((frame % 40 < 20) ? 0 : 1));
      final row = a.skinRow % 6;
      final srcRect = Rect.fromLTWH(col * 32.0, row * 32.0, 32, 32);
      final dstRect = Rect.fromLTWH(x - 4, y - 8, 20, 20);

      if (bodyImg != null) canvas.drawImageRect(bodyImg!, srcRect, dstRect, Paint());
      final oi = outfitImgs[a.outfitIdx];
      if (oi != null) canvas.drawImageRect(oi, Rect.fromLTWH(col * 32.0, 0, 32, 32), dstRect, Paint());
      if (hairsImg != null) {
        final hsrc = Rect.fromLTWH(col * 32.0, (a.hairRow % 8) * 32.0, 32, 32);
        canvas.drawImageRect(hairsImg!, hsrc, dstRect, Paint());
      }

      // 상태 버블 (머리 위) — 상태별 아이콘
      _drawStatusBubble(canvas, tp, a, x, y);

      // 이름 (역할 이모지 포함)
      tp.text = TextSpan(
        text: '${a.roleEmoji} ${a.name}',
        style: const TextStyle(fontSize: 2.6, color: Color(0xFFcccccc),
            fontWeight: FontWeight.w600),
      );
      tp.layout();
      tp.paint(canvas, Offset(x + 4 - tp.width / 2, y + 9));

      // 말풍선
      if (a.chatTimer > 0 && a.chatMsg.isNotEmpty) {
        final bw = min(a.chatMsg.length * 2.0 + 4, 42.0);
        final br = RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 4, y - 12, bw, 5.5), const Radius.circular(1.5));
        canvas.drawRRect(br, Paint()..color = Colors.white.withOpacity(0.94));
        canvas.drawRRect(br, Paint()
          ..color = const Color(0xFF3b82f6).withOpacity(0.4)
          ..style = PaintingStyle.stroke..strokeWidth = 0.2);
        final path = Path()..moveTo(x + 1, y - 6.5)..lineTo(x + 2, y - 4.8)..lineTo(x + 4, y - 6.5)..close();
        canvas.drawPath(path, Paint()..color = Colors.white.withOpacity(0.94));
        tp.text = TextSpan(text: a.chatMsg,
            style: const TextStyle(fontSize: 2.3, color: Color(0xFF0f1424)));
        tp.layout();
        tp.paint(canvas, Offset(x - 2, y - 11.2));
      }
    }

    // ─── 파티클 ───
    for (final p in particles) {
      tp.text = TextSpan(text: p.text,
          style: TextStyle(fontSize: 2.5, color: const Color(0xFF38bdf8).withOpacity(p.life / 25)));
      tp.layout();
      tp.paint(canvas, Offset(p.x, p.y));
    }

    canvas.restore();
  }

  bool _isInCarpet(double x, double y) {
    for (final f in furniture) {
      if (f.type == 'carpet' && x >= f.x && x < f.x + f.w && y >= f.y && y < f.y + f.h) return true;
    }
    return false;
  }

  void _drawFurniture(Canvas canvas) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final f in furniture) {
      switch (f.type) {
        case 'carpet':
          // 카펫 (둥근 모서리)
          canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(f.x, f.y, f.w, f.h), const Radius.circular(2)),
              Paint()..color = f.color);
          // 카펫 텍스처 (줄무늬)
          for (var ty = f.y + 3; ty < f.y + f.h; ty += 4) {
            canvas.drawLine(Offset(f.x + 2, ty), Offset(f.x + f.w - 2, ty),
                Paint()..color = f.color.withOpacity(0.5)..strokeWidth = 0.3);
          }
          break;
        case 'round-table':
          // 원형 테이블
          final cx = f.x + f.w / 2, cy = f.y + f.h / 2;
          canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: f.w, height: f.h),
              Paint()..color = const Color(0xFF3a2d1e));
          canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: f.w - 3, height: f.h - 3),
              Paint()..color = f.color);
          // 중앙 노트북/커피
          canvas.drawRect(Rect.fromLTWH(cx - 4, cy - 2, 8, 4), Paint()..color = const Color(0xFF222233));
          break;
        case 'sofa':
          // 소파
          canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(f.x, f.y, f.w, f.h), const Radius.circular(2.5)),
              Paint()..color = f.color);
          // 쿠션 (작게 3개)
          final cushionW = (f.w - 6) / 3;
          for (var ci = 0; ci < 3; ci++) {
            canvas.drawRRect(
                RRect.fromRectAndRadius(
                    Rect.fromLTWH(f.x + 2 + ci * cushionW, f.y + 3, cushionW - 1, f.h - 6),
                    const Radius.circular(1.5)),
                Paint()..color = f.color.withOpacity(0.7));
          }
          // 등받이
          canvas.drawRect(Rect.fromLTWH(f.x, f.y, f.w, 2),
              Paint()..color = const Color(0xFF2b1f3a));
          break;
        case 'whiteboard':
          canvas.drawRect(Rect.fromLTWH(f.x, f.y, f.w, f.h), Paint()..color = f.color);
          canvas.drawRect(Rect.fromLTWH(f.x, f.y, f.w, f.h),
              Paint()..color = const Color(0xFF1a2140)..style = PaintingStyle.stroke..strokeWidth = 0.5);
          // 텍스트 (미션)
          tp.text = const TextSpan(
              text: 'SPRINT v5.x\nSHIP IT!',
              style: TextStyle(fontSize: 2.6, color: Color(0xFF1a2140), fontWeight: FontWeight.w700));
          tp.layout();
          tp.paint(canvas, Offset(f.x + 2, f.y + 3));
          // 작은 원형 (마커 점)
          canvas.drawCircle(Offset(f.x + f.w - 4, f.y + f.h - 4), 1.5,
              Paint()..color = const Color(0xFFf59e0b));
          break;
        case 'poster':
          canvas.drawRect(Rect.fromLTWH(f.x, f.y, f.w, f.h),
              Paint()..shader = ui.Gradient.linear(
                  Offset(f.x, f.y), Offset(f.x + f.w, f.y + f.h),
                  [f.color, const Color(0xFF8b5cf6)]));
          canvas.drawRect(Rect.fromLTWH(f.x, f.y, f.w, f.h),
              Paint()..color = const Color(0xFF0f1424)..style = PaintingStyle.stroke..strokeWidth = 0.5);
          tp.text = const TextSpan(
              text: 'U2DIA',
              style: TextStyle(fontSize: 4.5, color: Colors.white, fontWeight: FontWeight.w900));
          tp.layout();
          tp.paint(canvas, Offset(f.x + f.w / 2 - tp.width / 2, f.y + f.h / 2 - tp.height / 2));
          break;
        case 'clock':
          final cx = f.x + f.w / 2, cy = f.y + f.h / 2;
          canvas.drawCircle(Offset(cx, cy), f.w / 2, Paint()..color = f.color);
          canvas.drawCircle(Offset(cx, cy), f.w / 2,
              Paint()..color = const Color(0xFF0f1424)..style = PaintingStyle.stroke..strokeWidth = 0.4);
          // 시계 침 (현재 시간 기반)
          final now = DateTime.now();
          final hour = (now.hour % 12 + now.minute / 60) * pi / 6 - pi / 2;
          final min = now.minute * pi / 30 - pi / 2;
          canvas.drawLine(Offset(cx, cy),
              Offset(cx + cos(hour) * 2.5, cy + sin(hour) * 2.5),
              Paint()..color = const Color(0xFF0f1424)..strokeWidth = 0.7);
          canvas.drawLine(Offset(cx, cy),
              Offset(cx + cos(min) * 3.8, cy + sin(min) * 3.8),
              Paint()..color = const Color(0xFF0f1424)..strokeWidth = 0.5);
          break;
        case 'plant':
          // 화분 (갈색 바닥)
          canvas.drawRect(Rect.fromLTWH(f.x, f.y + f.h - 3, f.w, 3),
              Paint()..color = const Color(0xFF5a3d2a));
          // 잎 (초록 원)
          canvas.drawCircle(Offset(f.x + f.w / 2, f.y + 2), f.w / 2 + 0.5,
              Paint()..color = f.color);
          canvas.drawCircle(Offset(f.x + f.w / 2 - 1.5, f.y + 4), 2,
              Paint()..color = const Color(0xFF16a34a));
          canvas.drawCircle(Offset(f.x + f.w / 2 + 1.5, f.y + 4), 2,
              Paint()..color = const Color(0xFF16a34a));
          break;
        case 'coffee':
          // 커피머신 (사각형 + 상단 LED)
          canvas.drawRect(Rect.fromLTWH(f.x, f.y, f.w, f.h), Paint()..color = f.color);
          canvas.drawRect(Rect.fromLTWH(f.x + 1, f.y + 2, f.w - 2, 2),
              Paint()..color = const Color(0xFFf59e0b));
          // 컵 슬롯
          canvas.drawRect(Rect.fromLTWH(f.x + 2, f.y + f.h - 5, f.w - 4, 2),
              Paint()..color = const Color(0xFF0f1424));
          break;
        case 'water':
          // 정수기
          canvas.drawRect(Rect.fromLTWH(f.x, f.y, f.w, f.h),
              Paint()..color = const Color(0xFF8b949e));
          // 물탱크 (파란색)
          canvas.drawRect(Rect.fromLTWH(f.x + 1, f.y + 1, f.w - 2, 6),
              Paint()..color = f.color);
          break;
        case 'led-strip':
          // 천장 LED (은은한 빛, 주기적 깜빡임)
          final glow = 0.5 + 0.3 * sin(frame * 0.03);
          canvas.drawRect(Rect.fromLTWH(f.x, f.y, f.w, f.h),
              Paint()..color = f.color.withOpacity(glow));
          // LED 아래쪽 반사 (그라데이션)
          canvas.drawRect(Rect.fromLTWH(f.x, f.y + f.h, f.w, 8),
              Paint()..shader = ui.Gradient.linear(
                  Offset(0, f.y + f.h), Offset(0, f.y + f.h + 8),
                  [f.color.withOpacity(0.25 * glow), f.color.withOpacity(0.0)]));
          break;
      }
    }
  }

  void _drawDesk(Canvas canvas, _Desk d) {
    // 데스크 본체 (둥근 모서리)
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(d.x, d.y, 36, 18), const Radius.circular(1.5)),
        Paint()..color = const Color(0xFF3a2d1e));
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(d.x + 1, d.y + 1, 34, 16), const Radius.circular(1.2)),
        Paint()..color = const Color(0xFF7b5d2c));

    switch (d.type) {
      case 'dual-monitor':
        // 듀얼 모니터
        for (var mi = 0; mi < 2; mi++) {
          final mx = d.x + 4 + mi * 15;
          canvas.drawRect(Rect.fromLTWH(mx, d.y - 10, 13, 10),
              Paint()..color = const Color(0xFF1a1a24));
          canvas.drawRect(Rect.fromLTWH(mx + 1, d.y - 9, 11, 8),
              Paint()..color = d.screenOn ? const Color(0xFF2563eb) : const Color(0xFF0a0a14));
          if (d.screenOn) {
            // 코드 줄
            for (var sl = 0; sl < 3; sl++) {
              canvas.drawRect(Rect.fromLTWH(mx + 2, d.y - 8 + sl * 2.2, 8, 0.7),
                  Paint()..color = Colors.white.withOpacity(0.3));
            }
          }
        }
        // 키보드
        canvas.drawRect(Rect.fromLTWH(d.x + 10, d.y + 2, 16, 2),
            Paint()..color = const Color(0xFF1a1a24));
        // 데스크 스탠드 (빛)
        if (d.screenOn) {
          final glow = Paint()..shader = ui.Gradient.radial(
              Offset(d.x + 18, d.y - 4), 14,
              [const Color(0xFFffd98e).withOpacity(0.25), Colors.transparent]);
          canvas.drawCircle(Offset(d.x + 18, d.y - 4), 14, glow);
        }
        break;
      case 'laptop':
        // 노트북
        canvas.drawRect(Rect.fromLTWH(d.x + 10, d.y - 7, 16, 8),
            Paint()..color = const Color(0xFF1a1a24));
        canvas.drawRect(Rect.fromLTWH(d.x + 11, d.y - 6, 14, 6),
            Paint()..color = d.screenOn ? const Color(0xFF2563eb) : const Color(0xFF0a0a14));
        canvas.drawRect(Rect.fromLTWH(d.x + 10, d.y + 1, 16, 2),
            Paint()..color = const Color(0xFF2a2a34));
        break;
      case 'sofa':
        // 소파 스타일 책상 (낮은 사이드 테이블 + 노트북)
        canvas.drawRect(Rect.fromLTWH(d.x + 12, d.y - 4, 12, 5),
            Paint()..color = const Color(0xFF1a1a24));
        canvas.drawRect(Rect.fromLTWH(d.x + 13, d.y - 3, 10, 3),
            Paint()..color = d.screenOn ? const Color(0xFFf59e0b) : const Color(0xFF0a0a14));
        break;
      case 'round-table':
        // 미팅 테이블: 이미 furniture 로 그려짐, 여기선 태블릿만
        canvas.drawRect(Rect.fromLTWH(d.x + 14, d.y + 3, 8, 5),
            Paint()..color = const Color(0xFF1a1a24));
        canvas.drawRect(Rect.fromLTWH(d.x + 15, d.y + 4, 6, 3),
            Paint()..color = d.screenOn ? const Color(0xFF22c55e) : const Color(0xFF0a0a14));
        break;
    }
  }

  void _drawStatusBubble(Canvas canvas, TextPainter tp, _Agent a, double x, double y) {
    // 상태 버블 (캐릭터 머리 위 — 말풍선 영역 밖에 세로로 작은 아이콘)
    String icon = '';
    Color bg = Colors.transparent;
    switch (a.state) {
      case 'working':
        icon = '✏️'; bg = const Color(0xFF3b82f6);
        break;
      case 'review':
        icon = '🔍'; bg = const Color(0xFFf59e0b);
        break;
      case 'blocked':
        icon = '⛔'; bg = const Color(0xFFef4444);
        break;
      case 'idle':
        // idle 은 간헐적으로만 표시 (50 프레임 중 25 프레임)
        if (frame % 50 < 25) { icon = '💤'; bg = const Color(0xFF6b7280); }
        break;
    }
    if (icon.isEmpty) return;
    // 작은 원형 배경
    final cx = x + 12.0, cy = y - 6.0;
    canvas.drawCircle(Offset(cx, cy), 2.8, Paint()..color = bg.withOpacity(0.85));
    canvas.drawCircle(Offset(cx, cy), 2.8,
        Paint()..color = Colors.white.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 0.3);
    tp.text = TextSpan(text: icon, style: const TextStyle(fontSize: 3));
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Agent {
  String name, role, roleEmoji, state, ticketTitle, chatMsg;
  double x, y, targetX, targetY, vx, vy;
  int skinRow, hairRow, outfitIdx, animFrame, direction, deskIdx, stateTimer, chatTimer;
  double bobPhase;
  _Agent({
    required this.name, required this.role, required this.roleEmoji,
    required this.x, required this.y, required this.targetX, required this.targetY,
    required this.vx, required this.vy, required this.skinRow, required this.hairRow,
    required this.outfitIdx, required this.animFrame, required this.direction,
    required this.state, required this.ticketTitle, required this.deskIdx,
    required this.stateTimer, required this.chatMsg, required this.chatTimer,
    required this.bobPhase,
  });
}

class _Desk {
  double x, y;
  bool screenOn;
  String type, zone;
  _Desk({required this.x, required this.y, required this.screenOn,
    required this.type, required this.zone});
}

class _Furniture {
  String type;
  double x, y, w, h;
  Color color;
  _Furniture({required this.type, required this.x, required this.y,
    required this.w, required this.h, required this.color});
}

class _Particle {
  double x, y;
  int life;
  String text;
  _Particle({required this.x, required this.y, required this.life, required this.text});
}
