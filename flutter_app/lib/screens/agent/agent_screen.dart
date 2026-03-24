import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../resident/resident_screen.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/sse_service.dart';

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});
  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  List<Map<String, dynamic>> _teams = [];
  String? _selectedTeamId;
  String _selectedTeamName = '';
  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  bool _sending = false;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final SseService _sse = SseService();
  StreamSubscription? _sseSub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _sse.disconnect();
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    final api = context.read<ApiService>();
    final teams = await api.getTeams(status: 'active');
    if (!mounted) return;
    setState(() => _teams = teams);
    if (teams.isNotEmpty && _selectedTeamId == null) {
      _selectTeam(teams.first);
    }
  }

  void _selectTeam(Map<String, dynamic> team) {
    setState(() {
      _selectedTeamId = team['team_id'] as String;
      _selectedTeamName = team['name'] as String? ?? '';
      _messages = [];
    });
    _sseSub?.cancel();
    _sse.disconnect();
    _loadMessages();
    _connectSse();
    _startPoll();
  }

  Future<void> _loadMessages() async {
    if (_selectedTeamId == null) return;
    setState(() => _loading = true);
    final api = context.read<ApiService>();
    final msgs = await api.getMessages(_selectedTeamId!);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
    });
    _scrollBottom();
  }

  void _connectSse() {
    if (_selectedTeamId == null) return;
    final url = '\${context.read<AuthService>().serverUrl}/api/teams/\$_selectedTeamId/events';
    _sse.connect(url).then((_) {
      _sseSub = _sse.stream?.listen((data) {
        final et = data['event_type'] ?? data['type'] ?? '';
        if (et == 'message_created' || et == 'message') {
          _loadMessages();
        }
      });
    });
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadMessages());
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _selectedTeamId == null || _sending) return;
    setState(() => _sending = true);
    _inputCtrl.clear();
    final optimistic = {
      'content': text,
      'sender': '유디(앱)',
      'role': 'orchestrator',
      'created_at': DateTime.now().toIso8601String(),
      '_optimistic': true,
    };
    setState(() => _messages.add(optimistic));
    _scrollBottom();
    final api = context.read<ApiService>();
    await api.sendMessage(_selectedTeamId!, text);
    await _loadMessages();
    if (!mounted) return;
    setState(() => _sending = false);
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'orchestrator': return const Color(0xFF1B96FF);
      case 'agent': return const Color(0xFF3fb950);
      case 'system': return const Color(0xFFd29922);
      default: return const Color(0xFF8b949e);
    }
  }

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'orchestrator': return Icons.manage_accounts;
      case 'agent': return Icons.smart_toy;
      case 'system': return Icons.settings_suggest;
      default: return Icons.person;
    }
  }

  String _fmtTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResidentScreen())),
        backgroundColor: const Color(0xFF1B96FF),
        icon: const Icon(Icons.smart_toy, size: 18),
        label: const Text('유디', style: TextStyle(fontSize: 12)),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        elevation: 0,
        title: const Row(children: [
          Icon(Icons.smart_toy, color: Color(0xFF3fb950), size: 20),
          SizedBox(width: 8),
          Text('에이전트 소통', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadMessages, tooltip: '새로고침'),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _teams.isEmpty
              ? const SizedBox.shrink()
              : SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: _teams.length,
                    itemBuilder: (ctx, i) {
                      final t = _teams[i];
                      final selected = t['team_id'] == _selectedTeamId;
                      return GestureDetector(
                        onTap: () => _selectTeam(t),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF1B96FF).withOpacity(0.15) : const Color(0xFF21262d),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: selected ? const Color(0xFF1B96FF) : const Color(0xFF30363d)),
                          ),
                          child: Text(t['name'] as String? ?? '',
                            style: TextStyle(
                              color: selected ? const Color(0xFF1B96FF) : const Color(0xFF8b949e),
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            )),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
      body: Column(children: [
        if (_selectedTeamId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF1c2128),
            child: Row(children: [
              Container(width: 8, height: 8,
                decoration: const BoxDecoration(color: Color(0xFF3fb950), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(_selectedTeamName, style: const TextStyle(color: Color(0xFF3fb950), fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              Text('\${_messages.length}개 메시지', style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
            ]),
          ),
        Expanded(
          child: _loading && _messages.isEmpty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _selectedTeamId == null
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.group_off, size: 48, color: Color(0xFF30363d)),
                      SizedBox(height: 12),
                      Text('활성 팀을 선택하세요', style: TextStyle(color: Color(0xFF8b949e))),
                    ]))
                  : _messages.isEmpty
                      ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.chat_bubble_outline, size: 48, color: Color(0xFF30363d)),
                          SizedBox(height: 12),
                          Text('메시지가 없습니다', style: TextStyle(color: Color(0xFF8b949e))),
                          SizedBox(height: 4),
                          Text('아래에서 에이전트에게 메시지를 보내세요',
                            style: TextStyle(color: Color(0xFF484f58), fontSize: 12)),
                        ]))
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, i) {
                            final msg = _messages[i];
                            final role = msg['role'] as String?;
                            final sender = msg['sender'] as String? ?? role ?? 'unknown';
                            final content = msg['content'] as String? ?? '';
                            final isMe = sender == '유디(앱)' || sender.contains('유디');
                            final roleColor = _roleColor(role);
                            final isOptimistic = msg['_optimistic'] == true;
                            final time = _fmtTime(msg['created_at'] as String?);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                children: [
                                  if (!isMe) ...[
                                    CircleAvatar(radius: 14,
                                      backgroundColor: roleColor.withOpacity(0.15),
                                      child: Icon(_roleIcon(role), size: 14, color: roleColor)),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(child: Column(
                                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    children: [
                                      Row(mainAxisSize: MainAxisSize.min, children: [
                                        Text(sender, style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.w600)),
                                        const SizedBox(width: 6),
                                        Text(time, style: const TextStyle(color: Color(0xFF484f58), fontSize: 10)),
                                        if (isOptimistic) ...[
                                          const SizedBox(width: 4),
                                          const SizedBox(width: 8, height: 8,
                                            child: CircularProgressIndicator(strokeWidth: 1.5)),
                                        ],
                                      ]),
                                      const SizedBox(height: 3),
                                      GestureDetector(
                                        onLongPress: () {
                                          Clipboard.setData(ClipboardData(text: content));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('복사됨'), duration: Duration(seconds: 1)));
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: isMe ? const Color(0xFF1B96FF).withOpacity(0.15) : const Color(0xFF21262d),
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(12),
                                              topRight: const Radius.circular(12),
                                              bottomLeft: Radius.circular(isMe ? 12 : 2),
                                              bottomRight: Radius.circular(isMe ? 2 : 12),
                                            ),
                                            border: Border.all(
                                              color: isMe ? const Color(0xFF1B96FF).withOpacity(0.3) : const Color(0xFF30363d)),
                                          ),
                                          child: SelectableText(content,
                                            style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13, height: 1.5)),
                                        ),
                                      ),
                                    ],
                                  )),
                                  if (isMe) ...[
                                    const SizedBox(width: 8),
                                    CircleAvatar(radius: 14,
                                      backgroundColor: roleColor.withOpacity(0.15),
                                      child: Icon(_roleIcon(role), size: 14, color: roleColor)),
                                  ],
                                ],
                              ),
                            );
                          }),
        ),
        // 입력창
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: const BoxDecoration(
            color: Color(0xFF161b22),
            border: Border(top: BorderSide(color: Color(0xFF30363d), width: 0.5)),
          ),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.send_to_mobile, size: 20, color: Color(0xFF58a6ff)),
              tooltip: '텔레그램 전송',
              onPressed: _selectedTeamId != null && !_sending ? () async {
                final text = _inputCtrl.text.trim();
                if (text.isEmpty) return;
                _inputCtrl.clear();
                final api = context.read<ApiService>();
                final res = await api.sendTelegram('[\$_selectedTeamName] \$text');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(res['ok'] == true ? '텔레그램 전송 완료' : '텔레그램 실패'),
                  backgroundColor: res['ok'] == true ? const Color(0xFF3fb950) : const Color(0xFFf85149),
                  duration: const Duration(seconds: 2),
                ));
              } : null,
            ),
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                enabled: _selectedTeamId != null,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 14),
                decoration: InputDecoration(
                  hintText: _selectedTeamId != null ? '에이전트에게 메시지...' : '팀을 선택하세요',
                  hintStyle: const TextStyle(color: Color(0xFF484f58), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF21262d),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFF30363d))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFF30363d))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFF1B96FF))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _selectedTeamId != null && !_sending ? _send : null,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _selectedTeamId != null && !_sending ? const Color(0xFF1B96FF) : const Color(0xFF30363d),
                  shape: BoxShape.circle,
                ),
                child: _sending
                    ? const Padding(padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 18, color: Colors.white),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
