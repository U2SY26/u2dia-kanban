import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMsg> _messages = [];
  String _sessionId = '';
  bool _loading = false;
  String? _project;
  List<Map<String, dynamic>> _projects = [];

  // 프로젝트 별칭 매핑
  static const _projectAliases = {
    '링코': 'LINKO',
    '글로': 'PMI-LINK-GLOBAL',
    '칸반': 'U2DIA-KANBAN-BOARD',
    '헥사': 'Hexacotest',
    '쿠팡': 'cupang_api',
    '이박': 'LEEPARK',
  };

  // 오케스트레이터 디스패치 키워드
  static const _dispatchKeywords = [
    '만들', '추가', '수정', '해줘', '구현', '삭제', '변경', '생성',
    '업데이트', '배포', '실행', '시작', '중지', '고쳐', '리팩터',
  ];

  static const _prefSessionId = 'chat_session_id';

  @override
  void initState() {
    super.initState();
    _restoreSession();
    _loadProjects();
    _addSystem('안녕하세요 대표님! 유디입니다.\n프로젝트를 선택하고 자유롭게 지시해주세요.\n\n예: "로그인 버그 고쳐줘"\n예: "최근 커밋 보여줘"\n예: "테스트 실행해줘"');
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefSessionId);
    if (saved != null && saved.isNotEmpty) {
      setState(() => _sessionId = saved);
    } else {
      _sessionId = 'apk-${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_prefSessionId, _sessionId);
    }
  }

  Future<void> _saveSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSessionId, _sessionId);
  }

  Future<void> _loadProjects() async {
    final api = context.read<ApiService>();
    try {
      final res = await api.get('/api/teams');
      if (res['ok'] == true) {
        final teams = (res['teams'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final groups = <String>{};
        for (final t in teams) {
          final pg = t['project_group']?.toString() ?? '';
          if (pg.isNotEmpty) groups.add(pg);
        }
        setState(() {
          _projects = groups.map((g) => {'name': g}).toList();
        });
      }
    } catch (_) {}
  }

  void _addSystem(String text) {
    setState(() {
      _messages.add(_ChatMsg(role: 'system', content: text));
    });
  }

  /// 메시지에서 프로젝트 자동 감지
  String? _detectProject(String text) {
    for (final entry in _projectAliases.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// 디스패치 키워드 감지
  bool _shouldDispatch(String text) {
    for (final kw in _dispatchKeywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();

    final detectedProject = _detectProject(text);
    if (detectedProject != null && _project == null) {
      setState(() => _project = detectedProject);
    }

    setState(() {
      _messages.add(_ChatMsg(role: 'user', content: text));
      _messages.add(_ChatMsg(role: 'assistant', content: '', tools: [])); // 스트리밍 슬롯
      _loading = true;
    });
    _scrollToBottom();

    final api = context.read<ApiService>();
    final streamIdx = _messages.length - 1;
    final toolsList = <String>[];

    try {
      // SSE 스트리밍 요청
      final url = '${api.baseUrl}/api/agent/chat/stream';
      final request = http.Request('POST', Uri.parse(url));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'message': text,
        'session_id': _sessionId,
        'project': _project ?? detectedProject,
      });

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

            if (type == 'text') {
              if (mounted) {
                setState(() {
                  _messages[streamIdx] = _ChatMsg(
                    role: 'assistant',
                    content: _messages[streamIdx].content + (data['text'] ?? ''),
                    tools: toolsList,
                  );
                });
                _scrollToBottom();
              }
            } else if (type == 'tool') {
              toolsList.add(data['name']?.toString() ?? '');
              if (mounted) {
                setState(() {
                  _messages[streamIdx] = _ChatMsg(
                    role: 'assistant',
                    content: _messages[streamIdx].content + '\n[${data['name']}] ',
                    tools: List.from(toolsList),
                  );
                });
              }
            } else if (type == 'tool_result') {
              // 도구 결과 표시
            } else if (type == 'done') {
              final tools = (data['tools'] as List?)?.cast<String>() ?? toolsList;
              if (mounted && tools.isNotEmpty) {
                setState(() {
                  final current = _messages[streamIdx].content;
                  _messages[streamIdx] = _ChatMsg(
                    role: 'assistant',
                    content: current,
                    tools: tools,
                  );
                });
              }
            } else if (type == 'error') {
              if (mounted) {
                setState(() {
                  _messages[streamIdx] = _ChatMsg(
                    role: 'error',
                    content: data['text']?.toString() ?? '오류',
                  );
                });
              }
            }
          } catch (_) {}
        }
      }
      client.close();

      // 빈 응답 처리
      if (mounted && _messages[streamIdx].content.isEmpty) {
        setState(() {
          _messages[streamIdx] = _ChatMsg(role: 'error', content: '응답 없음');
        });
      }
    } catch (e) {
      // 스트리밍 실패 → 일반 POST 폴백
      try {
        final res = await api.agentChat(text, _sessionId, project: _project ?? detectedProject);
        if (res['ok'] == true && mounted) {
          setState(() {
            _messages[streamIdx] = _ChatMsg(
              role: 'assistant',
              content: res['response']?.toString() ?? '응답 없음',
              tools: (res['tools_used'] as List?)?.cast<String>() ?? [],
            );
          });
        } else if (mounted) {
          setState(() {
            _messages[streamIdx] = _ChatMsg(role: 'error', content: res['error']?.toString() ?? '오류');
          });
        }
      } catch (e2) {
        if (mounted) {
          setState(() {
            _messages[streamIdx] = _ChatMsg(role: 'error', content: '연결 오류: $e2');
          });
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 100,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _confirmClearConversation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161b22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF30363d)),
        ),
        title: const Text('대화 초기화', style: TextStyle(color: Color(0xFFe6edf3), fontSize: 16)),
        content: const Text(
          '현재 대화를 모두 지우고 새 세션을 시작하시겠습니까?',
          style: TextStyle(color: Color(0xFF8b949e), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Color(0xFF8b949e))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _newSession();
            },
            child: const Text('초기화', style: TextStyle(color: Color(0xFFf85149))),
          ),
        ],
      ),
    );
  }

  Future<void> _newSession() async {
    setState(() {
      _sessionId = 'apk-${DateTime.now().millisecondsSinceEpoch}';
      _messages.clear();
      _project = null;
      _addSystem('새 대화를 시작합니다. 무엇을 도와드릴까요?');
    });
    await _saveSessionId();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        elevation: 0,
        title: Row(children: [
          const Icon(Icons.chat_bubble_outline, size: 20, color: Color(0xFF58a6ff)),
          const SizedBox(width: 8),
          const Text('유디 에이전트', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_project != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1B96FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_project!, style: const TextStyle(fontSize: 11, color: Color(0xFF58a6ff))),
            ),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline, size: 20), tooltip: '대화 초기화', onPressed: _confirmClearConversation),
          IconButton(icon: const Icon(Icons.add_comment, size: 20), tooltip: '새 대화', onPressed: _confirmClearConversation),
        ],
      ),
      body: Column(children: [
        // 프로젝트 선택 바
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF161b22),
            border: Border(bottom: BorderSide(color: Color(0xFF30363d), width: 0.5)),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _projectChip(null, '전체'),
              ..._projects.map((p) => _projectChip(p['name']?.toString(), p['name']?.toString() ?? '')),
            ],
          ),
        ),

        // 메시지 리스트
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length + (_loading ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i == _messages.length) return _typingIndicator();
              return _buildMessage(_messages[i]);
            },
          ),
        ),

        // 입력 바
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          decoration: const BoxDecoration(
            color: Color(0xFF161b22),
            border: Border(top: BorderSide(color: Color(0xFF30363d), width: 0.5)),
          ),
          child: SafeArea(
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: '구어체로 지시하세요...',
                    hintStyle: const TextStyle(color: Color(0xFF484f58)),
                    filled: true,
                    fillColor: const Color(0xFF0d1117),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF30363d)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF30363d)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF58a6ff)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                  textInputAction: TextInputAction.send,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: _loading ? const Color(0xFF30363d) : const Color(0xFF1B96FF),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _loading ? null : _send,
                  child: Container(
                    width: 44, height: 44,
                    alignment: Alignment.center,
                    child: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _projectChip(String? value, String label) {
    final selected = _project == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: Material(
        color: selected ? const Color(0xFF1B96FF).withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => setState(() => _project = value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? const Color(0xFF58a6ff) : const Color(0xFF30363d)),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(label, style: TextStyle(
              fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? const Color(0xFF58a6ff) : const Color(0xFF8b949e),
            )),
          ),
        ),
      ),
    );
  }

  Widget _buildMessage(_ChatMsg msg) {
    final isUser = msg.role == 'user';
    final isError = msg.role == 'error';
    final isSystem = msg.role == 'system';

    Color bgColor;
    Color textColor = const Color(0xFFe6edf3);
    CrossAxisAlignment align;
    double maxWidth = MediaQuery.of(context).size.width * 0.85;

    if (isUser) {
      bgColor = const Color(0xFF1B96FF).withOpacity(0.15);
      align = CrossAxisAlignment.end;
    } else if (isError) {
      bgColor = const Color(0xFFda3633).withOpacity(0.15);
      textColor = const Color(0xFFf85149);
      align = CrossAxisAlignment.start;
    } else if (isSystem) {
      bgColor = const Color(0xFF30363d).withOpacity(0.5);
      textColor = const Color(0xFF8b949e);
      align = CrossAxisAlignment.center;
      maxWidth = MediaQuery.of(context).size.width * 0.9;
    } else {
      bgColor = const Color(0xFF21262d);
      align = CrossAxisAlignment.start;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isUser && !isSystem)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.smart_toy, size: 14, color: Color(0xFF58a6ff)),
                const SizedBox(width: 4),
                const Text('유디', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF58a6ff))),
                if (msg.tools.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.build_circle_outlined, size: 12, color: Colors.orange.shade300),
                  const SizedBox(width: 2),
                  Text('${msg.tools.length}', style: TextStyle(fontSize: 10, color: Colors.orange.shade300)),
                ],
              ]),
            ),
          Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: isUser ? null : Border.all(color: const Color(0xFF30363d), width: 0.5),
            ),
            child: SelectableText(
              msg.content,
              style: TextStyle(fontSize: 13, height: 1.5, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingIndicator() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      const Icon(Icons.smart_toy, size: 14, color: Color(0xFF58a6ff)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF21262d),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF30363d), width: 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue.shade300)),
          const SizedBox(width: 8),
          const Text('생각 중...', style: TextStyle(fontSize: 12, color: Color(0xFF8b949e))),
        ]),
      ),
    ]),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class _ChatMsg {
  final String role;
  final String content;
  final List<String> tools;
  _ChatMsg({required this.role, required this.content, this.tools = const []});
}
