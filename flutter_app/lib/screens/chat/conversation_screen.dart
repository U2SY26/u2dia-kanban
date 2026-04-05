import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/api_service.dart';

/// 유디 대화모드 — 파티클 신시사이저 + STT/TTS
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> with TickerProviderStateMixin {
  final _inputCtrl = TextEditingController();
  String _sessionId = 'conv-${DateTime.now().millisecondsSinceEpoch}';
  String _responseText = '';
  String _userText = '';
  List<String> _toolsUsed = [];
  _CharState _charState = _CharState.idle;
  bool _loading = false;

  // STT
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _sttAvailable = false;
  bool _isListening = false;
  String _sttText = '';

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _ttsEnabled = true;

  // Animation
  late AnimationController _particleCtrl;
  late AnimationController _pulseCtrl;

  // 도구 빠른 호출
  static const _tools = [
    ('팀 목록', Icons.groups, '현재 활성 팀 목록 보여줘'),
    ('전체 현황', Icons.dashboard, '전체 현황 요약해줘'),
    ('검수', Icons.verified, '리뷰 상태 티켓 검수해줘'),
    ('스프린트', Icons.speed, '활성 스프린트 현황'),
    ('CLI', Icons.terminal, 'CLI 작업 현황'),
    ('활동', Icons.history, '최근 활동 로그'),
  ];

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _responseText = '안녕하세요 대표님, 유디입니다.\n마이크 버튼을 누르고 말씀하세요.';
    _initStt();
    _initTts();
  }

  Future<void> _initStt() async {
    _sttAvailable = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted && _isListening) {
            setState(() => _isListening = false);
            if (_sttText.isNotEmpty) _send(_sttText);
          }
        }
      },
      onError: (_) { if (mounted) setState(() => _isListening = false); },
    );
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() { _isSpeaking = false; _charState = _CharState.idle; });
    });
    _tts.setStartHandler(() {
      if (mounted) setState(() { _isSpeaking = true; _charState = _CharState.speaking; });
    });
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    _pulseCtrl.dispose();
    _inputCtrl.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  void _toggleListening() async {
    HapticFeedback.mediumImpact();
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      if (_sttText.isNotEmpty) _send(_sttText);
      return;
    }

    if (!_sttAvailable) {
      setState(() => _responseText = 'STT를 사용할 수 없습니다.\n마이크 권한을 확인해주세요.');
      return;
    }

    // TTS 중이면 멈추기
    if (_isSpeaking) { await _tts.stop(); setState(() { _isSpeaking = false; _charState = _CharState.idle; }); }

    setState(() { _isListening = true; _sttText = ''; _charState = _CharState.listening; });
    await _speech.listen(
      onResult: (result) {
        if (mounted) setState(() => _sttText = result.recognizedWords);
      },
      localeId: 'ko_KR',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> _send([String? override]) async {
    final text = override ?? _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;
    _inputCtrl.clear();

    // TTS 중이면 멈추기
    if (_isSpeaking) await _tts.stop();

    setState(() {
      _userText = text;
      _responseText = '';
      _toolsUsed = [];
      _sttText = '';
      _charState = _CharState.thinking;
      _loading = true;
    });

    final api = context.read<ApiService>();

    try {
      final url = '${api.baseUrl}/api/agent/chat/stream';
      final request = http.Request('POST', Uri.parse(url));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'message': text, 'session_id': _sessionId});

      final client = http.Client();
      final response = await client.send(request);
      String buffer = '';

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);
          if (!line.startsWith('data:')) continue;
          final jsonStr = line.substring(5).trim();
          if (jsonStr.isEmpty) continue;
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = data['type']?.toString() ?? '';
            if (type == 'text' && mounted) {
              setState(() { _responseText += data['text']?.toString() ?? ''; _charState = _CharState.speaking; });
            } else if (type == 'tool' && mounted) {
              setState(() { _toolsUsed.add(data['name']?.toString() ?? ''); _charState = _CharState.tooling; });
            } else if (type == 'done' && mounted) {
              setState(() => _charState = _CharState.idle);
            } else if (type == 'error' && mounted) {
              setState(() { _responseText = data['text']?.toString() ?? '오류'; _charState = _CharState.error; });
            }
          } catch (_) {}
        }
      }
      client.close();

      if (mounted && _responseText.isEmpty) {
        final res = await api.agentChat(text, _sessionId);
        setState(() {
          _responseText = res['response']?.toString() ?? '응답 없음';
          _toolsUsed = (res['tools_used'] as List?)?.cast<String>() ?? [];
        });
      }
    } catch (e) {
      try {
        final res = await api.agentChat(text, _sessionId);
        if (mounted) setState(() {
          _responseText = res['response']?.toString() ?? '응답 없음';
          _toolsUsed = (res['tools_used'] as List?)?.cast<String>() ?? [];
        });
      } catch (e2) {
        if (mounted) setState(() { _responseText = '연결 오류'; _charState = _CharState.error; });
      }
    } finally {
      if (mounted) {
        setState(() { _loading = false; if (_charState != _CharState.error) _charState = _CharState.idle; });
        // TTS로 응답 읽기
        if (_ttsEnabled && _responseText.isNotEmpty) {
          // HTML 태그 제거 + 최대 500자
          final clean = _responseText.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\*+'), '');
          final speak = clean.length > 500 ? '${clean.substring(0, 500)}... 이하 생략' : clean;
          await _tts.speak(speak);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080c14),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, size: 20), onPressed: () => Navigator.pop(context)),
        title: const Row(children: [
          Icon(Icons.auto_awesome, size: 18, color: Color(0xFF58a6ff)),
          SizedBox(width: 8),
          Text('유디 대화', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          // TTS 토글
          IconButton(
            icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off, size: 20,
                color: _ttsEnabled ? const Color(0xFF4AC99B) : const Color(0xFF8b949e)),
            onPressed: () {
              setState(() => _ttsEnabled = !_ttsEnabled);
              if (!_ttsEnabled && _isSpeaking) _tts.stop();
            },
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20, color: Color(0xFF8b949e)),
            onPressed: () => setState(() {
              _sessionId = 'conv-${DateTime.now().millisecondsSinceEpoch}';
              _responseText = '새 대화를 시작합니다.';
              _userText = ''; _toolsUsed = [];
            })),
        ],
      ),
      body: Column(children: [
        // 파티클 캐릭터
        Expanded(
          flex: 5,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedBuilder(
              animation: _particleCtrl,
              builder: (_, __) => CustomPaint(
                size: Size.infinite,
                painter: _ParticleSynthPainter(
                  time: _particleCtrl.value, pulse: _pulseCtrl.value, state: _charState,
                ),
              ),
            ),
            // STT 인식 중 텍스트
            if (_isListening && _sttText.isNotEmpty)
              Positioned(
                bottom: 20,
                left: 30, right: 30,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFf85149).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFf85149).withOpacity(0.3)),
                  ),
                  child: Text(_sttText, textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 14)),
                ),
              ),
            // 상태 뱃지
            if (_charState == _CharState.thinking)
              Positioned(top: 20, child: _stateBadge('생각 중...', const Color(0xFF58a6ff), Icons.auto_awesome)),
            if (_charState == _CharState.tooling && _toolsUsed.isNotEmpty)
              Positioned(top: 20, child: _stateBadge(_toolsUsed.last, const Color(0xFFa371f7), Icons.build_circle)),
            if (_charState == _CharState.listening)
              Positioned(top: 20, child: _stateBadge('듣고 있어요...', const Color(0xFFf85149), Icons.mic)),
            if (_isSpeaking)
              Positioned(top: 20, child: _stateBadge('말하는 중...', const Color(0xFF4AC99B), Icons.record_voice_over)),
            // 도구 뱃지
            if (_toolsUsed.isNotEmpty)
              Positioned(top: 52, child: Wrap(spacing: 4, children: _toolsUsed.map((t) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF4AC99B).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(t, style: const TextStyle(color: Color(0xFF4AC99B), fontSize: 8)),
              )).toList())),
          ]),
        ),
        // 응답 텍스트
        Expanded(
          flex: 3,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: SingleChildScrollView(reverse: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_userText.isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('나  ', style: TextStyle(color: Color(0xFF1B96FF), fontSize: 11, fontWeight: FontWeight.w700)),
                  Expanded(child: Text(_userText, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12, height: 1.4))),
                ])),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('유디  ', style: TextStyle(color: Color(0xFF4AC99B), fontSize: 11, fontWeight: FontWeight.w700)),
                Expanded(child: SelectableText(_responseText,
                    style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13, height: 1.5))),
              ]),
            ])),
          ),
        ),
        // 도구 바
        SizedBox(height: 36, child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _tools.length,
          itemBuilder: (_, i) {
            final tool = _tools[i];
            return Padding(padding: const EdgeInsets.only(right: 6), child: Material(
              color: const Color(0xFF21262d), borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _loading ? null : () => _send(tool.$3),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(tool.$2, size: 13, color: const Color(0xFF8b949e)),
                    const SizedBox(width: 4),
                    Text(tool.$1, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
                  ])),
              ),
            ));
          },
        )),
        const SizedBox(height: 6),
        // 마이크 + 입력
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
          decoration: const BoxDecoration(
            color: Color(0xFF0d1117),
            border: Border(top: BorderSide(color: Color(0xFF21262d), width: 0.5)),
          ),
          child: SafeArea(child: Row(children: [
            // 마이크 버튼
            GestureDetector(
              onTap: _loading ? null : _toggleListening,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _isListening ? const Color(0xFFf85149) : const Color(0xFF21262d),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isListening ? const Color(0xFFf85149) : const Color(0xFF30363d),
                    width: _isListening ? 2 : 1,
                  ),
                  boxShadow: _isListening ? [BoxShadow(color: const Color(0xFFf85149).withOpacity(0.3), blurRadius: 12)] : null,
                ),
                child: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  size: 22,
                  color: _isListening ? Colors.white : const Color(0xFF8b949e),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              controller: _inputCtrl,
              style: const TextStyle(fontSize: 14, color: Color(0xFFe6edf3)),
              maxLines: 2, minLines: 1,
              decoration: InputDecoration(
                hintText: '또는 텍스트로 입력...',
                hintStyle: const TextStyle(color: Color(0xFF484f58), fontSize: 13),
                filled: true, fillColor: const Color(0xFF161b22),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
            )),
            const SizedBox(width: 8),
            Material(
              color: _loading ? const Color(0xFF30363d) : const Color(0xFF1B96FF),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _loading ? null : () => _send(),
                child: SizedBox(width: 44, height: 44, child: _loading
                    ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                    : const Icon(Icons.send_rounded, size: 20, color: Colors.white)),
              ),
            ),
          ])),
        ),
      ]),
    );
  }

  Widget _stateBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color), const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontSize: 11)),
      ]),
    );
  }
}

enum _CharState { idle, thinking, speaking, tooling, listening, error }

// ── 파티클 신시사이저 페인터 ──
class _ParticleSynthPainter extends CustomPainter {
  final double time;
  final double pulse;
  final _CharState state;
  _ParticleSynthPainter({required this.time, required this.pulse, required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rng = Random(42);
    final color = _stateColor();

    // 글로우
    canvas.drawCircle(Offset(cx, cy), 140, Paint()
      ..shader = RadialGradient(colors: [color.withOpacity(0.08 + pulse * 0.06), Colors.transparent])
          .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 140)));

    // 코어
    final coreR = 20.0 + pulse * 6
        + (state == _CharState.speaking ? 10 : 0)
        + (state == _CharState.listening ? sin(time * pi * 8) * 8 : 0);
    canvas.drawCircle(Offset(cx, cy), coreR, Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.9), color.withOpacity(0.3), Colors.transparent],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: coreR)));

    // 오비탈 링
    for (int r = 0; r < 3; r++) {
      canvas.drawCircle(Offset(cx, cy), 42.0 + r * 28 + pulse * 5, Paint()
        ..color = color.withOpacity(0.05 + r * 0.02)..style = PaintingStyle.stroke..strokeWidth = 0.5);
    }

    // 파티클
    final count = state == _CharState.idle ? 60 : state == _CharState.listening ? 100 : 90;
    final spd = state == _CharState.idle ? 1.0 : state == _CharState.listening ? 3.0 : 2.0;
    for (int i = 0; i < count; i++) {
      final s = rng.nextDouble();
      final a = s * pi * 2 + time * pi * 2 * spd * (i.isEven ? 1 : -1);
      final orb = 30 + s * 100 + sin(time * pi * 2 + i) * 15;
      final x = cx + cos(a) * orb;
      final y = cy + sin(a) * orb * 0.7;
      final sz = 1.0 + s * 2.5 + (state == _CharState.speaking ? pulse * 2 : 0);
      final al = (0.3 + s * 0.5 + pulse * 0.2).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(x, y), sz, Paint()..color = _pColor(i, s).withOpacity(al));
    }

    // 웨이브 (speaking/listening)
    if (state == _CharState.speaking || state == _CharState.listening) {
      for (int w = 0; w < 3; w++) {
        canvas.drawCircle(Offset(cx, cy), coreR + 20 + w * 18 + pulse * 30, Paint()
          ..color = color.withOpacity(0.1 - w * 0.03)..style = PaintingStyle.stroke..strokeWidth = 1.5 - w * 0.4);
      }
    }

    // 에너지 라인 (thinking/tooling)
    if (state == _CharState.thinking || state == _CharState.tooling) {
      for (int l = 0; l < 8; l++) {
        final la = (l / 8) * pi * 2 + time * pi * 4;
        final endR = coreR + 30 + sin(time * pi * 6 + l) * 20;
        canvas.drawLine(
          Offset(cx + cos(la) * (coreR + 5), cy + sin(la) * (coreR + 5)),
          Offset(cx + cos(la) * endR, cy + sin(la) * endR),
          Paint()..color = color.withOpacity(0.3)..strokeWidth = 1,
        );
      }
    }
  }

  Color _stateColor() => const {
    _CharState.idle: Color(0xFF1B96FF),
    _CharState.thinking: Color(0xFF58a6ff),
    _CharState.speaking: Color(0xFF4AC99B),
    _CharState.tooling: Color(0xFFa371f7),
    _CharState.listening: Color(0xFFf85149),
    _CharState.error: Color(0xFFf85149),
  }[state] ?? const Color(0xFF1B96FF);

  Color _pColor(int i, double s) {
    if (state == _CharState.error) return const Color(0xFFf85149);
    if (state == _CharState.listening) return const Color(0xFFf85149);
    const c = [Color(0xFF1B96FF), Color(0xFF58a6ff), Color(0xFF4AC99B), Color(0xFFa371f7), Color(0xFF1FC9E8)];
    return c[(i + (s * 5).toInt()) % c.length];
  }

  @override
  bool shouldRepaint(covariant _ParticleSynthPainter old) => true;
}
