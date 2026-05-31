import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';
import '../../services/api_service.dart';

class CliMirrorScreen extends StatefulWidget {
  const CliMirrorScreen({super.key});
  @override
  State<CliMirrorScreen> createState() => _CliMirrorScreenState();
}

class _CliMirrorScreenState extends State<CliMirrorScreen> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;
  // 단축키 패널이 PTY로 정상 송신되도록 native(xterm) 모드를 기본값으로.
  // WebView 모드는 ttyd 페이지의 WebSocket을 외부에서 가로채야 해서 단축키 미동작 케이스 다수.
  bool _native = true;
  Terminal? _term;
  WebSocketChannel? _ws;
  bool _showTmuxRow = true;
  int _shortcutCategory = 0;

  List<Map<String, dynamic>> _sessions = [];
  String? _currentSession;
  List<Map<String, dynamic>> _windows = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
    // native 기본 — initState 직후 setupNative 호출 (context.read는 첫 frame 이후 안전)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_native && _term == null) {
        _setupNative();
      }
      setState(() => _loading = false);
    });
  }

  void _ensureWebViewController() {
    if (_controller != null) return;
    final api = context.read<ApiService>();
    final url = '${api.baseUrl}/cli/?writable=1';
    final headers = <String, String>{};
    final token = api.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (e) => setState(() {
          _error = '${e.errorCode}: ${e.description}';
          _loading = false;
        }),
      ))
      ..loadRequest(Uri.parse(url), headers: headers);
  }

  Future<void> _loadSessions() async {
    final api = context.read<ApiService>();
    try {
      final r = await api.tmuxSessions();
      if (!mounted) return;
      final sessions = ((r['sessions'] as List?) ?? []).cast<Map<String, dynamic>>();
      final current = r['current'] as String?;
      setState(() {
        _sessions = sessions;
        _currentSession = current;
      });
      if (current != null) _loadWindows(current);
    } catch (_) {}
  }

  Future<void> _loadWindows(String session) async {
    final api = context.read<ApiService>();
    try {
      final r = await api.tmuxWindows(session);
      if (!mounted) return;
      setState(() {
        _windows = ((r['windows'] as List?) ?? []).cast<Map<String, dynamic>>();
      });
    } catch (_) {
      if (mounted) setState(() => _windows = []);
    }
  }

  Future<void> _switchSession(String session) async {
    if (session == _currentSession) return;
    final api = context.read<ApiService>();
    try {
      final r = await api.tmuxSwitch(session);
      if (r['ok'] == true) {
        if (mounted) {
          setState(() => _currentSession = session);
          await _loadWindows(session);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('세션 전환: $session'), duration: const Duration(seconds: 1)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('전환 실패: ${r['error'] ?? "unknown"}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    }
  }

  // 단일 byte/byte 시퀀스를 PTY 로 전송 — WebView/Native 양쪽 동일 인터페이스.
  // 프로토콜: ttyd 호환 — 첫 byte '0' (0x30) = input, 이후 payload bytes.
  Future<void> _sendBytes(List<int> bytes) async {
    if (_native) {
      final ws = _ws;
      if (ws == null) return;
      final buf = Uint8List(1 + bytes.length);
      buf[0] = 0x30;
      for (var i = 0; i < bytes.length; i++) {
        buf[1 + i] = bytes[i] & 0xFF;
      }
      ws.sink.add(buf);
      return;
    }
    if (_controller == null) return;
    final hex = bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join();
    await _controller!.runJavaScript("(function(){"
        "var t=window.term;"
        "var ws=t&&t.__ws;"
        "if(!ws||ws.readyState!==1)return;"
        "var h='$hex';var n=h.length/2;"
        "var buf=new Uint8Array(1+n);"
        "buf[0]=48;"
        "for(var i=0;i<n;i++){buf[1+i]=parseInt(h.substr(i*2,2),16);}"
        "ws.send(buf);"
        "})();");
  }

  // tmux 프리픽스(Ctrl+B) + 후속 키 — 한 번의 송신으로 합쳐서 전송 (race-free).
  Future<void> _tmuxPrefix(int followKey) async {
    await _sendBytes([0x02, followKey]);
    // 이동/생성 후 windows 갱신
    if (_currentSession != null) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _loadWindows(_currentSession!);
      });
    }
  }

  // tmux prefix + 멀티 byte (예: 화살표는 prefix + ESC[A)
  Future<void> _tmuxPrefixSeq(List<int> seq) async {
    await _sendBytes([0x02, ...seq]);
  }

  Widget _keyBtn(String label, Future<void> Function() onTap, {double width = 56, Color? bg, Color? fg}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: width,
        height: 32,
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: bg ?? const Color(0xFF1e293b),
            foregroundColor: fg ?? const Color(0xFFe2e8f0),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 32),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: () => onTap(),
          child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  void _setupNative() {
    final api = context.read<ApiService>();
    final base = api.baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    final token = api.token ?? '';
    final term = Terminal(maxLines: 10000);
    final ch = WebSocketChannel.connect(Uri.parse('$base/cli/ws'), protocols: ['tty']);
    final enc = utf8;
    ch.sink.add(jsonEncode({'AuthToken': token}));
    ch.sink.add('1${jsonEncode({'columns': term.viewWidth, 'rows': term.viewHeight})}');
    ch.stream.listen((msg) {
      if (msg is List<int> || msg is Uint8List) {
        final bytes = msg is Uint8List ? msg : Uint8List.fromList(msg as List<int>);
        if (bytes.isNotEmpty && bytes[0] == 0x30) {
          term.write(enc.decode(bytes.sublist(1)));
        }
      } else if (msg is String && msg.isNotEmpty && msg.codeUnitAt(0) == 0x30) {
        term.write(msg.substring(1));
      }
    }, onError: (e) => term.write('\r\n[WS error: $e]'),
       onDone: () => term.write('\r\n[연결 종료]'));
    term.onOutput = (data) {
      final out = Uint8List.fromList([0x30, ...enc.encode(data)]);
      ch.sink.add(out);
    };
    term.onResize = (w, h, _, __) {
      ch.sink.add('1${jsonEncode({'columns': w, 'rows': h})}');
    };
    setState(() { _term = term; _ws = ch; });
  }

  @override
  void dispose() {
    _ws?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b0f17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0f172a),
        title: Row(children: [
          const Text('tmux', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          // 세션 dropdown
          if (_sessions.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0e2435),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF1FC9E8).withValues(alpha: 0.3)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _currentSession,
                  isDense: true,
                  iconEnabledColor: const Color(0xFF1FC9E8),
                  dropdownColor: const Color(0xFF0e2435),
                  style: const TextStyle(color: Color(0xFF1FC9E8), fontSize: 12, fontWeight: FontWeight.w600),
                  items: _sessions.map((s) {
                    final name = s['name']?.toString() ?? '';
                    final wins = s['windows'] ?? 0;
                    final att = s['attached'] == true ? '●' : '○';
                    return DropdownMenuItem<String>(
                      value: name,
                      child: Text('$att $name ($wins)'),
                    );
                  }).toList(),
                  onChanged: (v) { if (v != null) _switchSession(v); },
                ),
              ),
            ),
          const SizedBox(width: 8),
          Text(_native ? 'native' : 'web',
              style: const TextStyle(fontSize: 10, color: Color(0xFF8b949e))),
        ]),
        actions: [
          IconButton(
            icon: Icon(_showTmuxRow ? Icons.keyboard_hide : Icons.keyboard, size: 20),
            tooltip: _showTmuxRow ? '단축키 숨김' : '단축키 표시',
            onPressed: () => setState(() => _showTmuxRow = !_showTmuxRow),
          ),
          IconButton(
            icon: Icon(_native ? Icons.web : Icons.terminal, size: 20),
            tooltip: _native ? 'WebView 모드 (단축키 미동작)' : 'Native xterm 모드 (단축키 OK)',
            onPressed: () {
              setState(() {
                _native = !_native;
                if (_native && _term == null) _setupNative();
                if (!_native) {
                  _ws?.sink.close();
                  _ws = null;
                  _term = null;
                  _ensureWebViewController();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () {
              _loadSessions();
              if (_native) { _ws?.sink.close(); _setupNative(); }
              else { _controller?.reload(); }
            },
            tooltip: '재연결/세션 갱신',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // window 인디케이터 chips
            if (_windows.isNotEmpty) _windowChips(),
            Expanded(
              child: _native && _term != null
                ? TerminalView(_term!, theme: const TerminalTheme(
                    cursor: Color(0XFFAEAFAD), selection: Color(0XFFFFFF40),
                    foreground: Color(0xFFCFD8DC), background: Color(0xFF000000),
                    black: Color(0xFF000000), red: Color(0xFFCD3131), green: Color(0xFF0DBC79),
                    yellow: Color(0xFFE5E510), blue: Color(0xFF2472C8), magenta: Color(0xFFBC3FBC),
                    cyan: Color(0xFF11A8CD), white: Color(0xFFE5E5E5),
                    brightBlack: Color(0xFF666666), brightRed: Color(0xFFF14C4C), brightGreen: Color(0xFF23D18B),
                    brightYellow: Color(0xFFF5F543), brightBlue: Color(0xFF3B8EEA), brightMagenta: Color(0xFFD670D6),
                    brightCyan: Color(0xFF29B8DB), brightWhite: Color(0xFFE5E5E5),
                    searchHitBackground: Color(0xFFFFFF00), searchHitBackgroundCurrent: Color(0xFFFF9900), searchHitForeground: Color(0xFF000000),
                  ))
                : Stack(children: [
                if (_controller != null) WebViewWidget(controller: _controller!),
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '연결 실패\n$_error\n\nPC: ./scripts/cli-mirror-up.sh',
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ]),
            ),
            _keyboardBar(),
          ],
        ),
      ),
    );
  }

  Widget _windowChips() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: const Color(0xFF0a1220),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _windows.length,
        itemBuilder: (_, i) {
          final w = _windows[i];
          final idx = w['index'] ?? i;
          final name = w['name']?.toString() ?? '';
          final active = w['active'] == true;
          final panes = w['panes'] ?? 1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: GestureDetector(
              onTap: () => _tmuxPrefix(0x30 + (idx is int ? idx : int.tryParse('$idx') ?? 0)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF1B96FF) : const Color(0xFF1e293b),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: active ? const Color(0xFF1FC9E8) : const Color(0xFF334155), width: 0.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('$idx', style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: active ? Colors.white : const Color(0xFFcbd5e1),
                  )),
                  const SizedBox(width: 4),
                  Text(name, style: TextStyle(
                    fontSize: 11,
                    color: active ? Colors.white : const Color(0xFF94a3b8),
                  )),
                  if (panes > 1) ...[
                    const SizedBox(width: 4),
                    Text('×$panes', style: const TextStyle(fontSize: 9, color: Color(0xFF94a3b8))),
                  ],
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _keyboardBar() {
    return Container(
      color: const Color(0xFF0f172a),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1행: 기본 키 (항상 보임)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _keyBtn('Esc', () => _sendBytes([0x1B])),
              _keyBtn('Tab', () => _sendBytes([0x09])),
              _keyBtn('Enter', () => _sendBytes([0x0D])),
              _keyBtn('^C', () => _sendBytes([0x03])),
              _keyBtn('^D', () => _sendBytes([0x04])),
              _keyBtn('^L', () => _sendBytes([0x0C])),
              _keyBtn('^A', () => _sendBytes([0x01])),
              _keyBtn('^E', () => _sendBytes([0x05])),
              _keyBtn('^Z', () => _sendBytes([0x1A])),
              _keyBtn('^B', () => _sendBytes([0x02])),
              const SizedBox(width: 6),
              _keyBtn('↑', () => _sendBytes([0x1B, 0x5B, 0x41]), width: 38),
              _keyBtn('↓', () => _sendBytes([0x1B, 0x5B, 0x42]), width: 38),
              _keyBtn('←', () => _sendBytes([0x1B, 0x5B, 0x44]), width: 38),
              _keyBtn('→', () => _sendBytes([0x1B, 0x5B, 0x43]), width: 38),
              const SizedBox(width: 6),
              _keyBtn('PgUp', () => _sendBytes([0x1B, 0x5B, 0x35, 0x7E])),
              _keyBtn('PgDn', () => _sendBytes([0x1B, 0x5B, 0x36, 0x7E])),
              _keyBtn('Home', () => _sendBytes([0x1B, 0x5B, 0x48])),
              _keyBtn('End', () => _sendBytes([0x1B, 0x5B, 0x46])),
            ]),
          ),
          if (_showTmuxRow) ...[
            const SizedBox(height: 4),
            // tmux 카테고리 선택 탭
            Row(children: [
              _categoryTab('Window', 0),
              _categoryTab('Pane', 1),
              _categoryTab('Session', 2),
              _categoryTab('More', 3),
            ]),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _shortcutsForCategory()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryTab(String label, int idx) {
    final selected = _shortcutCategory == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _shortcutCategory = idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? const Color(0xFF1FC9E8) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF1FC9E8) : const Color(0xFF8b949e),
          )),
        ),
      ),
    );
  }

  List<Widget> _shortcutsForCategory() {
    const blueBg = Color(0xFF1e3a5f);
    const greenBg = Color(0xFF1e3a2f);
    const redBg = Color(0xFF3a1e1e);
    const purpleBg = Color(0xFF2e1f3f);
    switch (_shortcutCategory) {
      case 0: // Window
        return [
          _keyBtn('+win c', () => _tmuxPrefix(0x63), width: 60, bg: blueBg),
          _keyBtn('▶ next n', () => _tmuxPrefix(0x6E), width: 70, bg: blueBg),
          _keyBtn('◀ prev p', () => _tmuxPrefix(0x70), width: 70, bg: blueBg),
          _keyBtn('last l', () => _tmuxPrefix(0x6C), width: 56, bg: blueBg),
          _keyBtn('rename ,', () => _tmuxPrefix(0x2C), width: 70, bg: blueBg),
          _keyBtn('kill &', () => _tmuxPrefix(0x26), width: 60, bg: redBg),
          _keyBtn('tree w', () => _tmuxPrefix(0x77), width: 60, bg: blueBg),
          _keyBtn('move .', () => _tmuxPrefix(0x2E), width: 60, bg: blueBg),
          _keyBtn('find f', () => _tmuxPrefix(0x66), width: 56, bg: blueBg),
          const SizedBox(width: 8),
          for (var i = 0; i <= 9; i++)
            _keyBtn('$i', () => _tmuxPrefix(0x30 + i), width: 30, bg: const Color(0xFF263247)),
        ];
      case 1: // Pane
        return [
          _keyBtn('split |  %', () => _tmuxPrefix(0x25), width: 70, bg: greenBg),
          _keyBtn('split — "', () => _tmuxPrefix(0x22), width: 80, bg: greenBg),
          _keyBtn('next o', () => _tmuxPrefix(0x6F), width: 56, bg: greenBg),
          _keyBtn('last ;', () => _tmuxPrefix(0x3B), width: 56, bg: greenBg),
          _keyBtn('zoom z', () => _tmuxPrefix(0x7A), width: 60, bg: greenBg),
          _keyBtn('kill x', () => _tmuxPrefix(0x78), width: 56, bg: redBg),
          _keyBtn('break !', () => _tmuxPrefix(0x21), width: 60, bg: greenBg),
          _keyBtn('swap← {', () => _tmuxPrefix(0x7B), width: 64, bg: greenBg),
          _keyBtn('swap→ }', () => _tmuxPrefix(0x7D), width: 64, bg: greenBg),
          _keyBtn('layout ␣', () => _tmuxPrefix(0x20), width: 70, bg: greenBg),
          _keyBtn('# q', () => _tmuxPrefix(0x71), width: 50, bg: greenBg),
          _keyBtn('▲ pane', () => _tmuxPrefixSeq([0x1B, 0x5B, 0x41]), width: 64, bg: greenBg),
          _keyBtn('▼ pane', () => _tmuxPrefixSeq([0x1B, 0x5B, 0x42]), width: 64, bg: greenBg),
          _keyBtn('◀ pane', () => _tmuxPrefixSeq([0x1B, 0x5B, 0x44]), width: 64, bg: greenBg),
          _keyBtn('▶ pane', () => _tmuxPrefixSeq([0x1B, 0x5B, 0x43]), width: 64, bg: greenBg),
        ];
      case 2: // Session
        return [
          _keyBtn('detach d', () => _tmuxPrefix(0x64), width: 70, bg: purpleBg),
          _keyBtn('choose s', () => _tmuxPrefix(0x73), width: 70, bg: purpleBg),
          _keyBtn('rename \$', () => _tmuxPrefix(0x24), width: 70, bg: purpleBg),
          _keyBtn('prev (', () => _tmuxPrefix(0x28), width: 60, bg: purpleBg),
          _keyBtn('next )', () => _tmuxPrefix(0x29), width: 60, bg: purpleBg),
          _keyBtn('switch L', () => _tmuxPrefix(0x4C), width: 70, bg: purpleBg),
          const SizedBox(width: 8),
          // 직접 세션 전환 chips
          for (final s in _sessions) ...[
            _keyBtn(
              s['name'] == _currentSession ? '● ${s['name']}' : '${s['name']}',
              () => _switchSession(s['name']?.toString() ?? ''),
              width: 70,
              bg: s['name'] == _currentSession ? const Color(0xFF1B96FF) : const Color(0xFF263247),
              fg: s['name'] == _currentSession ? Colors.white : null,
            ),
          ],
        ];
      case 3: // More
        return [
          _keyBtn('cmd :', () => _tmuxPrefix(0x3A), width: 56, bg: blueBg),
          _keyBtn('copy [', () => _tmuxPrefix(0x5B), width: 60, bg: blueBg),
          _keyBtn('paste ]', () => _tmuxPrefix(0x5D), width: 64, bg: blueBg),
          _keyBtn('msgs ~', () => _tmuxPrefix(0x7E), width: 60, bg: blueBg),
          _keyBtn('clock t', () => _tmuxPrefix(0x74), width: 60, bg: blueBg),
          _keyBtn('refresh r', () => _tmuxPrefix(0x72), width: 70, bg: blueBg),
          _keyBtn('? keys', () => _tmuxPrefix(0x3F), width: 60, bg: blueBg),
          _keyBtn('lock', () => _tmuxPrefixSeq([0x1B, 0x78]), width: 50, bg: blueBg),
          _keyBtn('suspend', () => _tmuxPrefix(0x1A), width: 70, bg: blueBg),
          _keyBtn('reload', () => _tmuxPrefix(0x49), width: 60, bg: blueBg),
          _keyBtn('hist H', () => _tmuxPrefix(0x48), width: 60, bg: blueBg),
        ];
    }
    return [];
  }
}
