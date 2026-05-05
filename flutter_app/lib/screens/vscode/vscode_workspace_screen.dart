import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/api_service.dart';

class VsCodeWorkspaceScreen extends StatefulWidget {
  const VsCodeWorkspaceScreen({super.key});
  @override
  State<VsCodeWorkspaceScreen> createState() => _VsCodeWorkspaceScreenState();
}

class _VsCodeWorkspaceScreenState extends State<VsCodeWorkspaceScreen> {
  WebViewController? _controller;
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _currentSession;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    _refresh();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => _touchCurrent());
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final api = context.read<ApiService>();
    setState(() { _loading = true; _error = null; });
    try {
      final list = await api.vscodeSessions();
      if (!mounted) return;
      setState(() {
        _sessions = list;
        if (_currentSession == null && list.isNotEmpty) {
          _currentSession = list.first;
        } else if (_currentSession != null) {
          final id = _currentSession!['id'];
          final found = list.where((s) => s['id'] == id).cast<Map<String, dynamic>?>().firstWhere((_) => true, orElse: () => null);
          _currentSession = found ?? (list.isNotEmpty ? list.first : null);
        }
        _loading = false;
      });
      _loadCurrentInWebView();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  void _loadCurrentInWebView() {
    final s = _currentSession;
    if (s == null) { setState(() { _controller = null; }); return; }
    final api = context.read<ApiService>();
    final base = api.baseUrl;
    final id = s['id'];
    final folder = Uri.encodeQueryComponent(s['path']?.toString() ?? '');
    final url = '$base/vscode/$id/?folder=$folder';
    final headers = <String, String>{};
    final token = api.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1e1e1e))
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) {
          if (!mounted) return;
          setState(() { _error = '${e.errorCode}: ${e.description}'; });
        },
      ))
      ..loadRequest(Uri.parse(url), headers: headers);
    setState(() { _controller = c; _error = null; });
  }

  Future<void> _touchCurrent() async {
    final s = _currentSession;
    if (s == null) return;
    try {
      await context.read<ApiService>().vscodeTouchSession(s['id']);
    } catch (_) {}
  }

  Future<void> _spawnSession(String path, {String? label}) async {
    setState(() => _busy = true);
    try {
      final api = context.read<ApiService>();
      final r = await api.vscodeCreateSession(path, label: label);
      if (r['ok'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('실패: ${r['message'] ?? r['error'] ?? "unknown"}')));
        }
        return;
      }
      _currentSession = {
        'id': r['id'], 'path': r['path'], 'port': r['port'],
        'label': r['label'] ?? '', 'status': 'running',
      };
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('워크스페이스 시작: ${r['path']}'),
            duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCurrent() async {
    final s = _currentSession;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text('세션 종료', style: TextStyle(color: Colors.white)),
        content: Text('${s['path']} 워크스페이스를 종료할까요?',
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('종료', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await context.read<ApiService>().vscodeDeleteSession(s['id']);
      _currentSession = null;
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showNewSheet() async {
    final api = context.read<ApiService>();
    List<Map<String, dynamic>> recent = [];
    try { recent = await api.vscodeRecent(); } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0f172a),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.4,
        expand: false,
        builder: (_, scroll) => Column(children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('새 워크스페이스',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: recent.length,
              itemBuilder: (_, i) {
                final c = recent[i];
                final src = c['source']?.toString() ?? '';
                final path = c['path']?.toString() ?? '';
                final label = c['label']?.toString() ?? path.split('/').last;
                return ListTile(
                  leading: Icon(
                    src == 'github_dir' ? Icons.code : Icons.history,
                    color: src == 'github_dir'
                      ? const Color(0xFF1FC9E8) : const Color(0xFF94a3b8),
                    size: 20,
                  ),
                  title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(path, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  dense: true,
                  onTap: () { Navigator.pop(ctx); _spawnSession(path, label: label); },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _switchSession(Map<String, dynamic> s) {
    setState(() { _currentSession = s; });
    _loadCurrentInWebView();
  }

  @override
  Widget build(BuildContext context) {
    final s = _currentSession;
    return Scaffold(
      backgroundColor: const Color(0xFF1e1e1e),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0f172a),
        title: Row(children: [
          const Icon(Icons.code, size: 18, color: Color(0xFF1FC9E8)),
          const SizedBox(width: 8),
          const Text('VSCode', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 12),
          if (_sessions.isNotEmpty)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0e2435),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF1FC9E8).withValues(alpha: 0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: s?['id'],
                    isDense: true,
                    isExpanded: true,
                    iconEnabledColor: const Color(0xFF1FC9E8),
                    dropdownColor: const Color(0xFF0e2435),
                    style: const TextStyle(color: Color(0xFF1FC9E8), fontSize: 12, fontWeight: FontWeight.w600),
                    items: _sessions.map((sess) {
                      final label = sess['label']?.toString() ?? '';
                      final path = sess['path']?.toString() ?? '';
                      final name = label.isNotEmpty ? label : path.split('/').last;
                      final alive = sess['alive'] == true;
                      return DropdownMenuItem<String>(
                        value: sess['id']?.toString(),
                        child: Text('${alive ? '●' : '○'} $name',
                          overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final picked = _sessions.firstWhere(
                        (e) => e['id'] == v,
                        orElse: () => <String, dynamic>{},
                      );
                      if (picked.isNotEmpty) _switchSession(picked);
                    },
                  ),
                ),
              ),
            ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 22),
            tooltip: '새 워크스페이스',
            onPressed: _busy ? null : _showNewSheet,
          ),
          if (s != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFf87171)),
              tooltip: '현재 세션 종료',
              onPressed: _busy ? null : _deleteCurrent,
            ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _refresh,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
            ? _emptyState()
            : (_controller == null
                ? const Center(child: Text('세션 선택', style: TextStyle(color: Colors.white54)))
                : Stack(children: [
                    WebViewWidget(controller: _controller!),
                    if (_busy) const Positioned(top: 0, left: 0, right: 0,
                      child: LinearProgressIndicator(minHeight: 2)),
                    if (_error != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1e293b),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.redAccent),
                            ),
                            child: Text('연결 실패\n$_error',
                              style: const TextStyle(color: Colors.redAccent),
                              textAlign: TextAlign.center),
                          ),
                        ),
                      ),
                  ])),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.code, size: 64, color: Color(0xFF334155)),
          const SizedBox(height: 16),
          const Text('VSCode 워크스페이스 없음',
            style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('+ 버튼으로 새 워크스페이스를 시작하세요',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('워크스페이스 추가'),
            onPressed: _busy ? null : _showNewSheet,
          ),
        ],
      ),
    );
  }
}
