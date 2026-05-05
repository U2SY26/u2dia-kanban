import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../cli/cli_jobs_screen.dart';
import '../cli/cli_mirror_screen.dart';
import 'conversation_screen.dart';
import '../resident/supervisor_screen.dart';

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
  http.Client? _activeClient;

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

    // ── CLI 명령 (/ 또는 !) → cliExec API로 직접 처리 ──
    if (text.startsWith('/') || text.startsWith('!')) {
      setState(() {
        _messages.add(_ChatMsg(role: 'user', content: text));
        _loading = true;
      });
      _scrollToBottom();
      try {
        final api = context.read<ApiService>();
        final res = await api.cliExec(text);
        if (!mounted) return;
        final result = res['result'] ?? res['error'] ?? '응답 없음';
        setState(() {
          _messages.add(_ChatMsg(role: 'assistant', content: result));
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _messages.add(_ChatMsg(role: 'error', content: '연결 실패: $e'));
          _loading = false;
        });
      }
      _scrollToBottom();
      return;
    }

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

      _activeClient?.close();
      final client = http.Client();
      _activeClient = client;
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
            } else if (type == 'usage') {
              // Ollama 백엔드 정보 — 무시
            } else if (type == 'done') {
              final tools = (data['tools'] as List?)?.cast<String>() ?? toolsList;
              final doneActions = (data['actions'] as List?)
                  ?.map((a) => Map<String, dynamic>.from(a as Map))
                  .toList() ?? [];
              if (mounted) {
                setState(() {
                  _loading = false;
                  final current = _messages[streamIdx].content;
                  _messages[streamIdx] = _ChatMsg(
                    role: 'assistant',
                    content: current,
                    tools: tools,
                    actions: doneActions,
                    confirmRequired: data['confirm_required'] == true,
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
      _activeClient = null;

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
          final actions = (res['actions'] as List?)
              ?.map((a) => Map<String, dynamic>.from(a as Map))
              .toList() ?? [];
          final toolCalls = (res['tool_calls'] as List?)
              ?.map((a) => Map<String, dynamic>.from(a as Map))
              .toList() ?? [];
          setState(() {
            _messages[streamIdx] = _ChatMsg(
              role: 'assistant',
              content: res['response']?.toString() ?? '응답 없음',
              tools: (res['tools_used'] as List?)?.cast<String>() ?? [],
              actions: actions,
              confirmRequired: res['confirm_required'] == true,
              toolCalls: toolCalls,
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
      _activeClient?.close();
      _activeClient = null;
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _handleAction(Map<String, dynamic> action) async {
    final type = action['type']?.toString() ?? '';
    final label = action['label']?.toString() ?? '';

    if (type == 'cancel') {
      setState(() {
        _messages.add(_ChatMsg(role: 'system', content: '작업이 취소되었습니다.'));
      });
      _scrollToBottom();
      return;
    }

    // CLI 작업 생성 + 승인 플로우
    if (type == 'dispatch' || type == 'ticket') {
      final api = context.read<ApiService>();
      final ticketId = action['id']?.toString();
      final prompt = action['prompt']?.toString() ?? label;

      setState(() {
        _messages.add(_ChatMsg(role: 'system', content: 'CLI 작업 생성 중...'));
      });

      final res = await api.createCliJob({
        if (ticketId != null) 'ticket_id': ticketId,
        'team_id': action['team_id']?.toString(),
        'project_name': _project ?? action['project']?.toString() ?? '',
        'prompt': prompt,
      });

      if (res['ok'] == true) {
        final jobId = res['job_id']?.toString() ?? '';
        setState(() {
          _messages.last = _ChatMsg(
            role: 'system',
            content: 'CLI 작업 생성됨: $jobId\n프로젝트: ${res['project_path']}\n\n아래 버튼으로 승인하면 Worker가 실행합니다.',
            actions: [
              {'type': 'cli_approve', 'label': 'CLI 실행 승인', 'sublabel': jobId, 'id': jobId},
              {'type': 'cancel', 'label': '취소'},
            ],
          );
        });
      } else {
        setState(() {
          _messages.last = _ChatMsg(role: 'error', content: 'CLI 작업 생성 실패: ${res['error']}');
        });
      }
      _scrollToBottom();
      return;
    }

    // CLI 승인
    if (type == 'cli_approve') {
      final api = context.read<ApiService>();
      final jobId = action['id']?.toString() ?? '';
      final res = await api.approveCliJob(jobId);
      if (res['ok'] == true) {
        setState(() {
          _messages.add(_ChatMsg(role: 'system',
            content: '$jobId 승인 완료!\nCLI Worker가 작업을 가져갑니다.\n\n`python cli-worker.py` 가 실행 중인지 확인하세요.'));
        });
      } else {
        setState(() {
          _messages.add(_ChatMsg(role: 'error', content: '승인 실패: ${res['error']}'));
        });
      }
      _scrollToBottom();
      return;
    }

    // 기타 액션 → 텍스트로 전송
    _ctrl.text = '확인: $label';
    _send();
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
          IconButton(
            icon: const Icon(Icons.auto_awesome, size: 20, color: Color(0xFF4AC99B)),
            tooltip: '대화 모드',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConversationScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.verified_user, size: 20, color: Color(0xFFa371f7)),
            tooltip: 'Supervisor QA',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupervisorScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.terminal, size: 20),
            tooltip: 'tmux Mirror',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CliMirrorScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.work_outline, size: 20),
            tooltip: 'CLI 작업',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CliJobsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.history, size: 20, color: Color(0xFF8b949e)),
            tooltip: '대화 기록',
            onPressed: () async {
              final api = context.read<ApiService>();
              final sessions = await api.chatHistory();
              if (!mounted) return;
              showModalBottomSheet(context: context, backgroundColor: const Color(0xFF161b22),
                builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
                  const Padding(padding: EdgeInsets.all(12),
                    child: Text('대화 기록', style: TextStyle(color: Color(0xFFe6edf3), fontWeight: FontWeight.w600))),
                  SizedBox(height: 300, child: ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (_, i) {
                      final s = sessions[i];
                      return ListTile(
                        dense: true,
                        title: Text(s['session_id']?.toString() ?? '', style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12)),
                        subtitle: Text('${s['message_count'] ?? 0}건', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() { _sessionId = s['session_id']?.toString() ?? ''; _messages.clear(); });
                          _addSystem('세션 전환: ${s['session_id']}');
                        },
                      );
                    },
                  )),
                ]),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.delete_outline, size: 20), tooltip: '대화 초기화', onPressed: _confirmClearConversation),
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

        // ── Quick Action 바 (티켓 생성 / 검수 / Supervisor / CLI) ──
        _quickActionBar(),

        // 입력 바
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          decoration: const BoxDecoration(
            color: Color(0xFF161b22),
            border: Border(top: BorderSide(color: Color(0xFF30363d), width: 0.5)),
          ),
          child: SafeArea(
            child: Row(children: [
              // 도구 버튼 (+)
              GestureDetector(
                onTap: () => _showToolsSheet(context),
                child: Container(
                  width: 36, height: 36,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262d),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF30363d)),
                  ),
                  child: const Icon(Icons.add_circle_outline, size: 20, color: Color(0xFF8b949e)),
                ),
              ),
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
          // ── Yudi tool_calls 상세 카드 (티켓 생성/파일 수정 등 강조) ──
          if (msg.toolCalls.isNotEmpty) ...msg.toolCalls.map((tc) => Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _toolCallCard(tc, maxWidth),
          )),
          // ── 액션 버튼 (승인/취소) ──
          if (msg.actions.isNotEmpty)
            Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: msg.actions.map((action) {
                  final type = action['type']?.toString() ?? '';
                  final label = action['label']?.toString() ?? '';
                  final sublabel = action['sublabel']?.toString() ?? '';

                  IconData icon;
                  Color btnColor;
                  if (type == 'ticket') {
                    icon = Icons.confirmation_number_outlined;
                    btnColor = const Color(0xFF58a6ff);
                  } else if (type == 'dispatch') {
                    icon = Icons.rocket_launch_outlined;
                    btnColor = const Color(0xFF3fb950);
                  } else if (type == 'cancel') {
                    icon = Icons.close;
                    btnColor = const Color(0xFF8b949e);
                  } else {
                    icon = Icons.touch_app_outlined;
                    btnColor = const Color(0xFFd29922);
                  }

                  return SizedBox(
                    width: maxWidth,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _loading ? null : () => _handleAction(action),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: btnColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: btnColor.withOpacity(0.3)),
                          ),
                          child: Row(children: [
                            Icon(icon, size: 18, color: btnColor),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: btnColor)),
                                if (sublabel.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(sublabel, style: const TextStyle(fontSize: 11, color: Color(0xFF8b949e))),
                                  ),
                              ],
                            )),
                            Icon(Icons.chevron_right, size: 16, color: btnColor.withOpacity(0.5)),
                          ]),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ── tool_calls 카드 (Flutter 강조 표시) ──
  Widget _toolCallCard(Map<String, dynamic> tc, double maxWidth) {
    final name = tc['name']?.toString() ?? 'tool';
    final input = tc['input'] is Map ? Map<String, dynamic>.from(tc['input'] as Map) : <String, dynamic>{};
    final preview = tc['result_preview']?.toString() ?? '';
    final isDangerous = tc['is_dangerous'] == true;
    final isKanban = tc['is_kanban'] == true;
    final isFileEdit = tc['is_file_edit'] == true;

    Color color;
    IconData icon;
    String typeLabel;
    if (isFileEdit) {
      color = const Color(0xFFd29922); icon = Icons.edit_note; typeLabel = '파일 수정';
    } else if (isKanban) {
      color = const Color(0xFF4AC99B); icon = Icons.dashboard_customize; typeLabel = '칸반';
    } else if (isDangerous) {
      color = const Color(0xFFf85149); icon = Icons.bolt; typeLabel = '실행';
    } else {
      color = const Color(0xFF58a6ff); icon = Icons.build_circle_outlined; typeLabel = '조회';
    }

    String summary = '';
    if (input.containsKey('title')) {
      summary = (input['title'] ?? '').toString();
    } else if (input.containsKey('file_path') || input.containsKey('path')) {
      summary = (input['file_path'] ?? input['path'] ?? '').toString();
    } else if (input.containsKey('command')) {
      summary = (input['command'] ?? '').toString();
    } else if (input.isNotEmpty) {
      summary = input.entries.first.value.toString();
    }
    if (summary.length > 90) summary = '${summary.substring(0, 90)}...';

    // 파일 수정 mini diff
    String diffSnippet = '';
    if (isFileEdit) {
      final old = (input['old_string'] ?? input['old'] ?? '').toString();
      final neu = (input['new_string'] ?? input['new'] ?? input['content'] ?? '').toString();
      if (old.isNotEmpty || neu.isNotEmpty) {
        final oldLines = old.split('\n').take(3).join('\n');
        final newLines = neu.split('\n').take(3).join('\n');
        if (oldLines.isNotEmpty) diffSnippet += '- ${oldLines.replaceAll('\n', '\n- ')}\n';
        if (newLines.isNotEmpty) diffSnippet += '+ ${newLines.replaceAll('\n', '\n+ ')}';
      }
    }

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
            child: Text(typeLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(name, style: TextStyle(fontSize: 12, color: color, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis)),
        ]),
        if (summary.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 4, left: 22),
          child: Text(summary, style: const TextStyle(fontSize: 12, color: Color(0xFFc9d1d9))),
        ),
        if (diffSnippet.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 6, left: 22),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: const Color(0xFF0d1117), borderRadius: BorderRadius.circular(4)),
            child: Text(diffSnippet, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF8b949e), height: 1.4)),
          ),
        ),
        if (preview.isNotEmpty && diffSnippet.isEmpty) Padding(
          padding: const EdgeInsets.only(top: 4, left: 22),
          child: Text(preview.length > 120 ? '${preview.substring(0, 120)}...' : preview,
              style: const TextStyle(fontSize: 10, color: Color(0xFF8b949e), fontFamily: 'monospace')),
        ),
      ]),
    );
  }

  // ── Quick Action 바 (입력창 위) ──
  Widget _quickActionBar() {
    final actions = [
      _QuickAction(Icons.note_add, '티켓 생성', const Color(0xFF4AC99B), _openCreateTicketDialog),
      _QuickAction(Icons.fact_check, '검수 실행', const Color(0xFFf85149), _openReviewDialog),
      _QuickAction(Icons.verified_user, 'Supervisor', const Color(0xFFa371f7),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupervisorScreen()))),
      _QuickAction(Icons.terminal, 'tmux', const Color(0xFF1FC9E8),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CliMirrorScreen()))),
      _QuickAction(Icons.work_outline, 'CLI 작업', const Color(0xFF1B96FF),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CliJobsScreen()))),
    ];
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF161b22),
        border: Border(top: BorderSide(color: Color(0xFF30363d), width: 0.5)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final a = actions[i];
          return Material(
            color: a.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: a.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  Icon(a.icon, size: 14, color: a.color),
                  const SizedBox(width: 5),
                  Text(a.label, style: TextStyle(color: a.color, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 티켓 생성 다이얼로그 — 팀 선택 + 한 줄 설명 → /api/agent/quick-ticket
  Future<void> _openCreateTicketDialog() async {
    final api = context.read<ApiService>();
    final teamsRes = await api.get('/api/teams?status=Active');
    final teams = ((teamsRes['teams'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (!mounted) return;
    if (teams.isEmpty) {
      _addSystem('활성 팀이 없습니다. 먼저 팀을 만들어주세요.');
      return;
    }
    String? selectedTeamId = teams.first['team_id'] as String?;
    final descCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
        backgroundColor: const Color(0xFF161b22),
        title: const Row(children: [
          Icon(Icons.note_add, size: 18, color: Color(0xFF4AC99B)),
          SizedBox(width: 8),
          Text('티켓 생성', style: TextStyle(color: Color(0xFFe6edf3), fontSize: 15)),
        ]),
        content: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('팀', style: TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
          const SizedBox(height: 4),
          DropdownButton<String>(
            value: selectedTeamId,
            isExpanded: true,
            dropdownColor: const Color(0xFF161b22),
            style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12),
            items: teams.map((t) => DropdownMenuItem(
              value: t['team_id'] as String,
              child: Text(t['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setSt(() => selectedTeamId = v),
          ),
          const SizedBox(height: 12),
          const Text('한 줄 설명 (유디가 제목/우선순위 정제)', style: TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
          const SizedBox(height: 4),
          TextField(
            controller: descCtrl,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13),
            decoration: const InputDecoration(
              hintText: '예: 대시보드 로그인 버그 고쳐줘',
              hintStyle: TextStyle(color: Color(0xFF484f58), fontSize: 12),
              border: OutlineInputBorder(),
            ),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 14),
            label: const Text('생성'),
            onPressed: () async {
              final desc = descCtrl.text.trim();
              if (desc.isEmpty || selectedTeamId == null) return;
              Navigator.pop(ctx);
              setState(() => _loading = true);
              final res = await api.agentQuickTicket(desc, selectedTeamId!);
              if (!mounted) return;
              setState(() => _loading = false);
              if (res['ok'] == true) {
                final tid = res['ticket_id'];
                final title = res['title'];
                final usedLlm = res['used_llm'] == true ? '유디가 정제' : '직접 사용';
                setState(() {
                  _messages.add(_ChatMsg(
                    role: 'system',
                    content: '✅ 티켓 생성: $tid\n제목: $title\n($usedLlm)',
                  ));
                });
                _scrollToBottom();
              } else {
                setState(() {
                  _messages.add(_ChatMsg(role: 'error', content: '티켓 생성 실패: ${res['error']}'));
                });
                _scrollToBottom();
              }
            },
          ),
        ],
      )),
    );
  }

  /// 검수 실행 다이얼로그 — 팀 선택 + 배치 검수.
  Future<void> _openReviewDialog() async {
    final api = context.read<ApiService>();
    final teamsRes = await api.get('/api/teams?status=Active');
    final teams = ((teamsRes['teams'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (!mounted) return;
    if (teams.isEmpty) {
      _addSystem('활성 팀이 없습니다.');
      return;
    }
    String? selectedTeamId = teams.first['team_id'] as String?;
    int limit = 5;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
        backgroundColor: const Color(0xFF161b22),
        title: const Row(children: [
          Icon(Icons.fact_check, size: 18, color: Color(0xFFf85149)),
          SizedBox(width: 8),
          Text('Supervisor 배치 검수', style: TextStyle(color: Color(0xFFe6edf3), fontSize: 15)),
        ]),
        content: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('팀', style: TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
          DropdownButton<String>(
            value: selectedTeamId,
            isExpanded: true,
            dropdownColor: const Color(0xFF161b22),
            style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12),
            items: teams.map((t) => DropdownMenuItem(
              value: t['team_id'] as String,
              child: Text(t['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setSt(() => selectedTeamId = v),
          ),
          const SizedBox(height: 12),
          Text('최대 검수 건수: $limit', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
          Slider(
            value: limit.toDouble(), min: 1, max: 10, divisions: 9,
            onChanged: (v) => setSt(() => limit = v.toInt()),
            label: '$limit',
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 14),
            label: const Text('검수 실행'),
            onPressed: () async {
              if (selectedTeamId == null) return;
              Navigator.pop(ctx);
              setState(() {
                _loading = true;
                _messages.add(_ChatMsg(role: 'system', content: '🔍 Supervisor 배치 검수 시작 (최대 $limit건)...'));
              });
              _scrollToBottom();
              final res = await api.supervisorReview(teamId: selectedTeamId, batch: true, limit: limit);
              if (!mounted) return;
              setState(() {
                _loading = false;
                if (res['ok'] == true) {
                  final response = res['response']?.toString() ?? res['summary']?.toString() ?? '검수 완료';
                  _messages.add(_ChatMsg(
                    role: 'assistant',
                    content: '✅ 배치 검수 완료\n\n$response',
                  ));
                } else {
                  _messages.add(_ChatMsg(role: 'error', content: '검수 실패: ${res['error']}'));
                }
              });
              _scrollToBottom();
            },
          ),
        ],
      )),
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

  // ── 도구 팝업 시트 ──
  void _showToolsSheet(BuildContext ctx) {
    const tools = <_ToolItem>[
      // 조회
      _ToolItem('team_list', '팀 목록', Icons.groups, Color(0xFF58a6ff), '현재 활성 팀 목록 보여줘'),
      _ToolItem('board', '칸반보드', Icons.dashboard, Color(0xFF58a6ff), '칸반보드 전체 현황 보여줘'),
      _ToolItem('progress', '진행 현황', Icons.trending_up, Color(0xFF58a6ff), '진행 중인 티켓 현황 보여줘'),
      _ToolItem('activity', '활동 로그', Icons.history, Color(0xFF8b949e), '최근 활동 로그 보여줘'),
      // 작업
      _ToolItem('create_team', '팀 생성', Icons.group_add, Color(0xFF4AC99B), '새 팀을 만들어줘'),
      _ToolItem('create_ticket', '티켓 생성', Icons.note_add, Color(0xFF4AC99B), '새 티켓을 만들어줘: '),
      _ToolItem('spawn_agent', '에이전트 스폰', Icons.smart_toy, Color(0xFFa371f7), '에이전트를 스폰해줘'),
      _ToolItem('dispatch', '작업 실행', Icons.rocket_launch, Color(0xFFFE9339), '이 작업을 실행해줘: '),
      // Supervisor
      _ToolItem('review', '검수 (QA)', Icons.fact_check, Color(0xFFf85149), 'Review 상태 티켓 전체 검수해줘'),
      _ToolItem('review_stats', '검수 통계', Icons.analytics, Color(0xFFf85149), '검수 통계 보여줘'),
      // Sprint
      _ToolItem('sprint', '스프린트 현황', Icons.speed, Color(0xFFd29922), '활성 스프린트 현황 보여줘'),
      _ToolItem('velocity', '벨로시티', Icons.show_chart, Color(0xFFd29922), '팀 벨로시티 보여줘'),
      // 시스템
      _ToolItem('cli_status', 'CLI/Fleet', Icons.terminal, Color(0xFF1FC9E8), 'CLI 작업 현황 보여줘'),
      _ToolItem('model', 'AI 모델 상태', Icons.memory, Color(0xFF1FC9E8), '/model'),
      _ToolItem('gpu', 'GPU 현황', Icons.developer_board, Color(0xFF1FC9E8), '!nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader'),
      _ToolItem('summary', '전체 요약', Icons.summarize, Color(0xFF8b949e), '전체 현황 요약해줘'),
      // 셸 / 개발
      _ToolItem('git_log', 'Git 로그', Icons.history_edu, Color(0xFFd2a8ff), '!git log --oneline -10'),
      _ToolItem('git_status', 'Git 상태', Icons.difference, Color(0xFFd2a8ff), '!git status'),
      _ToolItem('ollama_ps', 'Ollama 상태', Icons.smart_toy, Color(0xFF4AC99B), '!ollama ps'),
      _ToolItem('shell', '셸 명령', Icons.code, Color(0xFF8b949e), '!'),
    ];

    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF161b22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) => Column(children: [
          // 핸들
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(color: const Color(0xFF484f58), borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Icon(Icons.build_circle, color: Color(0xFF58a6ff), size: 18),
              SizedBox(width: 8),
              Text('유디 도구', style: TextStyle(color: Color(0xFFe6edf3), fontSize: 15, fontWeight: FontWeight.w600)),
              Spacer(),
              Text('탭하여 실행', style: TextStyle(color: Color(0xFF484f58), fontSize: 11)),
            ]),
          ),
          const Divider(color: Color(0xFF30363d), height: 1),
          Expanded(
            child: GridView.builder(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: tools.length,
              itemBuilder: (_, i) {
                final t = tools[i];
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    if (t.prompt.endsWith(': ')) {
                      _ctrl.text = t.prompt;
                      _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: t.prompt.length));
                    } else {
                      _ctrl.text = t.prompt;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _send();
                      });
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0d1117),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF30363d)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: t.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(t.icon, color: t.color, size: 20),
                        ),
                        const SizedBox(height: 6),
                        Text(t.label, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 10.5, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _activeClient?.close();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class _ToolItem {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final String prompt;
  const _ToolItem(this.id, this.label, this.icon, this.color, this.prompt);
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.label, this.color, this.onTap);
}

class _ChatMsg {
  final String role;
  final String content;
  final List<String> tools;
  final List<Map<String, dynamic>> actions;
  final bool confirmRequired;
  // ── Yudi tool_calls 카드용 (서버 응답 tool_calls 키 그대로) ──
  // 각 항목: {id, name, input, result_preview, is_dangerous, is_kanban, is_file_edit}
  final List<Map<String, dynamic>> toolCalls;
  _ChatMsg({
    required this.role,
    required this.content,
    this.tools = const [],
    this.actions = const [],
    this.confirmRequired = false,
    this.toolCalls = const [],
  });
}
