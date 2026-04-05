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

class _AgentOfficeScreenState extends State<AgentOfficeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  List<_Agent> _agents = [];
  List<_Desk> _desks = [];
  List<_Particle> _particles = [];
  Map<String, dynamic> _boardData = {};
  bool _loading = true;
  final _rand = Random();
  int _frame = 0;

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
  Map<int, ui.Image> _outfitImgs = {};

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 999))..repeat();
    _animCtrl.addListener(_tick);
    _loadAll();
  }

  @override
  void dispose() {
    _animCtrl.removeListener(_tick);
    _animCtrl.dispose();
    // 세로 모드 복원
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    _frame++;
    if (_frame % 2 == 0) _update();
    setState(() {});
  }

  Future<ui.Image> _loadImage(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _loadAll() async {
    // 스프라이트 로드
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

    // 보드 데이터
    final api = context.read<ApiService>();
    final res = await api.getBoard(widget.teamId);
    if (mounted) {
      _boardData = (res['ok'] == true ? (res['board'] as Map<String, dynamic>?) : null) ?? {};
      // 프로젝트 그룹이 없으면 teamName에서 추론
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
    const _projectRoles = {
      'U2DIA AI': ['machining', 'equipment', 'tooling', 'cutting', 'nc-code', 'post-proc', 'controller', 'ui', 'oracle-db', 'postgres-db', 'go-backend', 'py-backend', 'frontend', 'fea', 'mesh', 'security', 'legal', 'qa', 'devops', 'cs'],
      'LINKO': ['mes-core', 'frontend', 'db-postgres', 'backend', 'auth', 'i18n', 'payment', 'cs', 'legal', 'tax', 'security', 'build', 'qa', 'docs'],
      'U2DIA Commerce AI': ['frontend', 'backend', 'auth', 'payment', 'product', 'order', 'ai-recommend', 'cs', 'legal', 'tax', 'security', 'qa'],
      'u2dia_simulator': ['nc-interp', '3d-viz', 'backplot', 'physics', 'controller', 'frontend', 'backend', 'db', 'equip-db', 'tool-db', 'i18n', 'security', 'qa'],
      'U2DIA-KANBAN-BOARD': ['server', 'sqlite', 'flutter', 'electron', 'ollama', 'supervisor', 'devops', 'security', 'qa'],
    };

    // 팀이 속한 프로젝트의 역할 수 또는 실제 멤버 수 중 큰 값
    final pg = _boardData['project_group']?.toString() ?? widget.teamName;
    // 정확 매칭 → 키워드 매칭
    var roles = _projectRoles[pg] ?? [];
    if (roles.isEmpty) {
      final pgLower = pg.toLowerCase();
      for (final e in _projectRoles.entries) {
        if (pgLower.contains(e.key.toLowerCase()) || e.key.toLowerCase().contains(pgLower)) {
          roles = e.value; break;
        }
      }
    }
    // 그래도 없으면 기본 5명
    if (roles.isEmpty) roles = ['frontend', 'backend', 'qa', 'devops', 'architect'];
    final minAgents = roles.length > members.length ? roles.length : members.length;
    final agentCount = minAgents.clamp(4, 30);

    _desks = [];
    // 사무실 확장: 4열 넓은 배치
    for (var i = 0; i < agentCount; i++) {
      final row = i ~/ 4, col = i % 4;
      _desks.add(_Desk(x: 20.0 + col * 70, y: 28.0 + row * 50, screenOn: false));
    }

    _agents = [];
    // idleChats는 클래스 필드로 이동됨

    // 실제 멤버 + 부족분은 전문가 역할로 placeholder 생성
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

    for (var j = 0; j < effectiveMembers.length; j++) {
      final m = effectiveMembers[j];
      final mid = (m['member_id'] ?? '') as String;
      // 해시 분산: 각 요소가 독립적으로 분포하도록
      var seed = 0;
      for (var c = 0; c < mid.length; c++) seed = seed * 31 + mid.codeUnitAt(c);

      Map<String, dynamic>? ticket;
      if (members.isNotEmpty) {
        for (final t in tickets) {
          if (t['assigned_member_id'] == mid && t['status'] == 'InProgress') { ticket = t; break; }
        }
      }

      final deskIdx = j % _desks.length;
      final desk = _desks[deskIdx];
      desk.screenOn = ticket != null;

      final role = (m['role'] ?? 'agent') as String;
      // 영어 사람 이름 (seed 기반 고정 배정)
      const _names = [
        'Alex', 'Blake', 'Casey', 'Dana', 'Ellis', 'Finn', 'Gray', 'Harper',
        'Ivy', 'Jules', 'Kit', 'Logan', 'Max', 'Noel', 'Owen', 'Parker',
        'Quinn', 'Riley', 'Sam', 'Tay', 'Uma', 'Val', 'Wren', 'Xia',
        'Yuri', 'Zane', 'Ash', 'Brook', 'Clay', 'Drew',
      ];
      final displayName = _names[seed.abs() % _names.length];
      _agents.add(_Agent(
        name: displayName.substring(0, min(12, displayName.length)),
        x: desk.x + 6, y: desk.y + 16,
        targetX: desk.x + 6, targetY: desk.y + 16,
        skinRow: seed.abs() % 6, hairRow: (seed.abs() ~/ 6) % 8, outfitIdx: (seed.abs() ~/ 48) % 6 + 1,
        animFrame: _rand.nextInt(4), direction: 0,
        state: (members.isEmpty || isIdle) ? 'idle' : (ticket != null ? 'working' : 'idle'),
        ticketTitle: ticket != null ? (ticket['title'] ?? '').toString() : '',
        deskIdx: deskIdx,
        stateTimer: 50 + _rand.nextInt(150),
        chatMsg: (members.isEmpty || isIdle)
            ? idleChats[j % idleChats.length]
            : (ticket != null ? '💻 ${(ticket['title'] ?? '').toString().substring(0, min(14, (ticket['title'] ?? '').toString().length))}' : ''),
        chatTimer: 80 + _rand.nextInt(100),
        vx: 0, vy: 0,
      ));
    }
    _particles = [];
  }

  void _update() {
    final w = 216.0, h = 120.0;
    for (final a in _agents) {
      a.stateTimer--;
      if (_frame % 8 == 0) a.animFrame = (a.animFrame + 1) % 4;
      if (a.stateTimer <= 0) {
        if (a.state == 'working') {
          if (_rand.nextDouble() < 0.1) {
            a.state = 'walking'; a.targetX = 10 + _rand.nextDouble() * 40; a.targetY = h - 20;
            a.chatMsg = '☕'; a.chatTimer = 80; a.stateTimer = 80;
          } else {
            a.stateTimer = 60 + _rand.nextInt(120);
            _particles.add(_Particle(x: a.x + 5, y: a.y - 5, life: 25, text: ['{}', '()', '=>', 'fn', '++'][_rand.nextInt(5)]));
          }
        } else if (a.state == 'idle') {
          final r = _rand.nextDouble();
          if (r < 0.35) {
            // 돌아다니며 다른 에이전트와 스몰토크
            a.state = 'walking';
            // 다른 에이전트 근처로 이동
            if (_agents.length > 1) {
              final target = _agents[_rand.nextInt(_agents.length)];
              a.targetX = target.x + (_rand.nextDouble() - 0.5) * 10;
              a.targetY = target.y + (_rand.nextDouble() - 0.5) * 10;
            } else {
              a.targetX = 10 + _rand.nextDouble() * (w - 20); a.targetY = 10 + _rand.nextDouble() * (h - 20);
            }
            a.stateTimer = 60 + _rand.nextInt(80);
            a.chatMsg = idleChats[_rand.nextInt(idleChats.length)]; a.chatTimer = 120;
          } else if (r < 0.5) {
            // 창밖 보기 (벽 근처로 이동)
            a.state = 'walking'; a.targetX = 30 + _rand.nextDouble() * 160; a.targetY = 16;
            a.stateTimer = 80 + _rand.nextInt(60);
            a.chatMsg = ['☁️ ...', '🌅 예쁘다', '🌧️ 비온다', '🍃 바람~'][_rand.nextInt(4)]; a.chatTimer = 100;
          } else {
            // 자리에서 취미/잡담
            a.stateTimer = 50 + _rand.nextInt(80);
            a.chatMsg = idleChats[_rand.nextInt(idleChats.length)]; a.chatTimer = 100;
          }
        } else {
          final desk = _desks[a.deskIdx];
          a.targetX = desk.x + 6; a.targetY = desk.y + 16;
          a.state = a.ticketTitle.isNotEmpty ? 'working' : 'idle';
          a.stateTimer = 60 + _rand.nextInt(120);
        }
      }
      final dx = a.targetX - a.x, dy = a.targetY - a.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 1) {
        a.vx = dx / dist * 0.5; a.vy = dy / dist * 0.5;
        a.x += a.vx; a.y += a.vy;
        a.direction = dx.abs() > dy.abs() ? (dx > 0 ? 2 : 1) : (dy > 0 ? 0 : 3);
      } else { a.vx = 0; a.vy = 0; }
      if (a.chatTimer > 0) a.chatTimer--;
    }
    _particles.removeWhere((p) { p.y -= 0.2; p.life--; return p.life <= 0; });
  }

  @override
  Widget build(BuildContext context) {
    // 가로 모드 허용
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    return Scaffold(
      backgroundColor: const Color(0xFF1c2333),
      appBar: AppBar(
        backgroundColor: const Color(0xFF252d41),
        title: Row(children: [
          const Text('🏢 ', style: TextStyle(fontSize: 18)),
          Expanded(child: Text(widget.teamName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFe6edf3)), overflow: TextOverflow.ellipsis)),
        ]),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3b82f6)))
          : Column(children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 3.0,
                      child: ClipRect(
                        child: CustomPaint(
                          painter: _OfficePainter(
                            agents: _agents, desks: _desks, particles: _particles, frame: _frame,
                            bodyImg: _bodyImg, hairsImg: _hairsImg, shadowImg: _shadowImg, outfitImgs: _outfitImgs,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(color: Color(0xFF252d41), border: Border(top: BorderSide(color: Color(0xFF3d4663)))),
      child: Row(children: [
        Text('👥 ${_agents.length}', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
        const SizedBox(width: 12),
        Text('🔄 $ip', style: const TextStyle(color: Color(0xFF3b82f6), fontSize: 11)),
        const SizedBox(width: 8),
        Text('✅ $done/$total', style: const TextStyle(color: Color(0xFF22c55e), fontSize: 11)),
        const Spacer(),
        SizedBox(width: 80, height: 4, child: ClipRRect(borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: pct / 100, minHeight: 4,
            backgroundColor: const Color(0xFF1e2740),
            valueColor: AlwaysStoppedAnimation(pct >= 80 ? const Color(0xFF22c55e) : const Color(0xFF3b82f6))))),
        const SizedBox(width: 6),
        Text('$pct%', style: TextStyle(color: pct >= 80 ? const Color(0xFF22c55e) : const Color(0xFF3b82f6), fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _OfficePainter extends CustomPainter {
  final List<_Agent> agents;
  final List<_Desk> desks;
  final List<_Particle> particles;
  final int frame;
  final ui.Image? bodyImg, hairsImg, shadowImg;
  final Map<int, ui.Image> outfitImgs;

  _OfficePainter({required this.agents, required this.desks, required this.particles, required this.frame,
    this.bodyImg, this.hairsImg, this.shadowImg, required this.outfitImgs});

  @override
  void paint(Canvas canvas, Size size) {
    // 에이전트 수에 따라 사무실 크기 동적 확장
    final rows = (agents.length / 5).ceil().clamp(2, 8);
    final w = 300.0, h = max(160.0, rows * 50.0 + 40);
    final s = min(size.width / w, size.height / h);
    canvas.save(); canvas.scale(s, s);

    // 바닥 (나무 타일)
    for (var tx = 0.0; tx < w; tx += 16) {
      for (var ty = 0.0; ty < h; ty += 16) {
        canvas.drawRect(Rect.fromLTWH(tx, ty, 16, 16),
          Paint()..color = ((tx ~/ 16 + ty ~/ 16) % 2 == 0) ? const Color(0xFF433d2e) : const Color(0xFF3b3526));
      }
    }
    // 벽
    canvas.drawRect(Rect.fromLTWH(0, 0, w, 18), Paint()..color = const Color(0xFF5c6b4f));
    canvas.drawRect(Rect.fromLTWH(0, 17, w, 2), Paint()..color = const Color(0xFF6d7a5e));
    // 창문
    for (var wi = 0; wi < 4; wi++) {
      final wx = 25.0 + wi * 70;
      canvas.drawRect(Rect.fromLTWH(wx, 3, 30, 12), Paint()..color = const Color(0xFF87CEEB));
      canvas.drawRect(Rect.fromLTWH(wx, 3, 30, 12), Paint()..color = const Color(0xFF4a5a3e)..style = PaintingStyle.stroke..strokeWidth = 0.8);
    }

    // 데스크
    for (final d in desks) {
      canvas.drawRect(Rect.fromLTWH(d.x, d.y, 36, 18), Paint()..color = const Color(0xFF8B6914));
      canvas.drawRect(Rect.fromLTWH(d.x + 1, d.y + 1, 34, 16), Paint()..color = const Color(0xFFA07818));
      // 모니터
      canvas.drawRect(Rect.fromLTWH(d.x + 8, d.y - 10, 18, 12), Paint()..color = const Color(0xFF222222));
      canvas.drawRect(Rect.fromLTWH(d.x + 9, d.y - 9, 16, 10),
        Paint()..color = d.screenOn ? const Color(0xFF2563eb) : const Color(0xFF111111));
      if (d.screenOn) {
        for (var sl = 0; sl < 4; sl++) {
          canvas.drawRect(Rect.fromLTWH(d.x + 11, d.y - 8 + sl * 2.5, 10, 0.8),
            Paint()..color = Colors.white.withOpacity(0.2));
        }
      }
      canvas.drawRect(Rect.fromLTWH(d.x + 16, d.y - 0.5, 3, 1.5), Paint()..color = const Color(0xFF333333));
    }

    // 에이전트 (y순)
    final sorted = List<_Agent>.from(agents)..sort((a, b) => a.y.compareTo(b.y));
    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (final a in sorted) {
      final x = a.x, y = a.y;

      // 그림자
      if (shadowImg != null) {
        canvas.drawImageRect(shadowImg!, const Rect.fromLTWH(0, 0, 32, 32),
          Rect.fromLTWH(x - 1, y + 6, 10, 3), Paint()..color = Colors.black.withOpacity(0.4));
      }

      // 스프라이트 프레임
      final isMoving = a.vx.abs() > 0.1 || a.vy.abs() > 0.1;
      final col = isMoving ? (a.direction * 4 + a.animFrame % 4) : (a.direction * 4 + ((frame % 40 < 20) ? 0 : 1));
      final row = a.skinRow % 6;
      final srcRect = Rect.fromLTWH(col * 32.0, row * 32.0, 32, 32);
      final dstRect = Rect.fromLTWH(x - 4, y - 8, 20, 20);

      // 몸체
      if (bodyImg != null) canvas.drawImageRect(bodyImg!, srcRect, dstRect, Paint());
      // 의상
      final oi = outfitImgs[a.outfitIdx];
      if (oi != null) canvas.drawImageRect(oi, Rect.fromLTWH(col * 32.0, 0, 32, 32), dstRect, Paint());
      // 머리카락
      if (hairsImg != null) {
        final hsrc = Rect.fromLTWH(col * 32.0, (a.hairRow % 8) * 32.0, 32, 32);
        canvas.drawImageRect(hairsImg!, hsrc, dstRect, Paint());
      }

      // 상태 아이콘
      if (a.state == 'working' && frame % 25 < 18) {
        tp.text = const TextSpan(text: '⚡', style: TextStyle(fontSize: 4)); tp.layout(); tp.paint(canvas, Offset(x + 8, y - 5));
      } else if (a.state == 'idle' && frame % 50 < 25) {
        tp.text = const TextSpan(text: '💤', style: TextStyle(fontSize: 3)); tp.layout(); tp.paint(canvas, Offset(x + 8, y - 5));
      }

      // 이름
      tp.text = TextSpan(text: a.name, style: const TextStyle(fontSize: 2.5, color: Color(0xFFcccccc)));
      tp.layout(); tp.paint(canvas, Offset(x + 4 - tp.width / 2, y + 9));

      // 말풍선
      if (a.chatTimer > 0 && a.chatMsg.isNotEmpty) {
        final bw = min(a.chatMsg.length * 2.0 + 4, 36.0);
        final br = RRect.fromRectAndRadius(Rect.fromLTWH(x - 4, y - 11, bw, 5), const Radius.circular(1.5));
        canvas.drawRRect(br, Paint()..color = Colors.white.withOpacity(0.92));
        canvas.drawRRect(br, Paint()..color = const Color(0xFFaaaaaa)..style = PaintingStyle.stroke..strokeWidth = 0.2);
        // 꼬리
        final path = Path()..moveTo(x + 1, y - 6)..lineTo(x + 2, y - 4)..lineTo(x + 4, y - 6)..close();
        canvas.drawPath(path, Paint()..color = Colors.white.withOpacity(0.92));
        tp.text = TextSpan(text: a.chatMsg, style: const TextStyle(fontSize: 2.2, color: Color(0xFF333333)));
        tp.layout(); tp.paint(canvas, Offset(x - 2, y - 10.5));
      }
    }

    // 파티클
    for (final p in particles) {
      tp.text = TextSpan(text: p.text, style: TextStyle(fontSize: 2.5, color: Color(0xFF38bdf8).withOpacity(p.life / 25)));
      tp.layout(); tp.paint(canvas, Offset(p.x, p.y));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Agent {
  String name, state, ticketTitle, chatMsg;
  double x, y, targetX, targetY, vx, vy;
  int skinRow, hairRow, outfitIdx, animFrame, direction, deskIdx, stateTimer, chatTimer;
  _Agent({required this.name, required this.x, required this.y, required this.targetX, required this.targetY,
    required this.vx, required this.vy, required this.skinRow, required this.hairRow, required this.outfitIdx,
    required this.animFrame, required this.direction, required this.state, required this.ticketTitle,
    required this.deskIdx, required this.stateTimer, required this.chatMsg, required this.chatTimer});
}

class _Desk { double x, y; bool screenOn; _Desk({required this.x, required this.y, required this.screenOn}); }
class _Particle { double x, y; int life; String text; _Particle({required this.x, required this.y, required this.life, required this.text}); }
