import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});
  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Timer? _timer;

  // 시스템 메트릭
  Map<String, dynamic> _metrics = {};
  bool _loadingMetrics = false;

  // 클라이언트
  List<Map<String, dynamic>> _clients = [];

  // 토큰
  List<Map<String, dynamic>> _tokens = [];

  // 연결 상태
  bool _connected = false;
  String _serverUrl = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _serverUrl = context.read<AuthService>().serverUrl;
    _connected = context.read<ApiService>().connected;
    _loadAll();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _loadAll());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _loadMetrics();
    _loadClients();
    _loadTokens();
    final ok = await context.read<ApiService>().ping();
    if (mounted) setState(() => _connected = ok);
  }

  Future<void> _loadMetrics() async {
    setState(() => _loadingMetrics = true);
    final res = await context.read<ApiService>().getMetrics();
    if (!mounted) return;
    setState(() {
      _metrics = (res['metrics'] as Map<String, dynamic>?) ?? {};
      _loadingMetrics = false;
    });
  }

  Future<void> _loadClients() async {
    final clients = await context.read<ApiService>().getClients();
    if (!mounted) return;
    setState(() => _clients = clients);
  }

  Future<void> _loadTokens() async {
    final tokens = await context.read<ApiService>().getTokens();
    if (!mounted) return;
    setState(() => _tokens = tokens);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        elevation: 0,
        title: Row(children: [
          Icon(Icons.monitor_heart,
            color: _connected ? const Color(0xFF3fb950) : const Color(0xFFf85149), size: 20),
          const SizedBox(width: 8),
          const Text('시스템', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (_connected ? const Color(0xFF3fb950) : const Color(0xFFf85149)).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: (_connected ? const Color(0xFF3fb950) : const Color(0xFFf85149)).withOpacity(0.4)),
            ),
            child: Text(_connected ? 'ONLINE' : 'OFFLINE',
              style: TextStyle(
                color: _connected ? const Color(0xFF3fb950) : const Color(0xFFf85149),
                fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadAll, tooltip: '새로고침'),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF1B96FF),
          labelColor: const Color(0xFF1B96FF),
          unselectedLabelColor: const Color(0xFF8b949e),
          tabs: const [
            Tab(icon: Icon(Icons.memory, size: 18), text: '리소스'),
            Tab(icon: Icon(Icons.devices, size: 18), text: '클라이언트'),
            Tab(icon: Icon(Icons.vpn_key_outlined, size: 18), text: '토큰'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabCtrl, children: [
        _resourceTab(),
        _clientTab(),
        _tokenTab(),
      ]),
    );
  }

  // ── 리소스 탭 ──────────────────────────────────
  Widget _resourceTab() {
    if (_loadingMetrics && _metrics.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final cpu = (_metrics['cpu_percent'] as num?)?.toDouble() ?? 0;
    // API는 MB 단위 반환: memory_total_mb, memory_used_mb, memory_percent
    final memTotalMb = (_metrics['memory_total_mb'] as num?)?.toDouble() ?? 0;
    final memUsedMb = (_metrics['memory_used_mb'] as num?)?.toDouble() ?? 0;
    final memTotal = memTotalMb / 1024; // GB
    final memUsed = memUsedMb / 1024;  // GB
    final memPct = (_metrics['memory_percent'] as num?)?.toDouble() ?? 
        (memTotal > 0 ? memUsed / memTotal * 100 : 0.0);
    final diskTotal = (_metrics['disk_total_gb'] as num?)?.toDouble() ?? 0;
    final diskUsed = (_metrics['disk_used_gb'] as num?)?.toDouble() ?? 0;
    final diskPct = (_metrics['disk_percent'] as num?)?.toDouble() ??
        (diskTotal > 0 ? diskUsed / diskTotal * 100 : 0.0);
    final uptime = _metrics['uptime_seconds'] as int? ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // 서버 정보
        _infoCard('서버 정보', [
          _infoRow('URL', _serverUrl),
          _infoRow('상태', _connected ? '연결됨' : '연결 끊김'),
          _infoRow('업타임', uptime > 0 ? _fmtUptime(uptime) : '-'),
          _infoRow('플랫폼', _metrics['platform'] as String? ?? '-'),
          _infoRow('호스트', _metrics['hostname'] as String? ?? '-'),
          _infoRow('Python', _metrics['python_version'] as String? ?? '-'),
        ]),
        const SizedBox(height: 16),

        // CPU
        _gaugeCard('CPU', cpu, '${cpu.toStringAsFixed(1)}%',
          color: cpu > 80 ? const Color(0xFFf85149) : cpu > 60 ? const Color(0xFFd29922) : const Color(0xFF3fb950),
          sub: 'CPU 사용률'),
        const SizedBox(height: 12),

        // 메모리
        _gaugeCard('메모리', memPct.toDouble(), '${memUsed.toStringAsFixed(1)} / ${memTotal.toStringAsFixed(1)} GB',
          color: memPct > 85 ? const Color(0xFFf85149) : memPct > 70 ? const Color(0xFFd29922) : const Color(0xFF1B96FF),
          sub: '${memPct.toStringAsFixed(1)}% 사용 중'),
        const SizedBox(height: 12),

        // 디스크
        _gaugeCard('디스크', diskPct.toDouble(), '${diskUsed.toStringAsFixed(1)} / ${diskTotal.toStringAsFixed(1)} GB',
          color: diskPct > 90 ? const Color(0xFFf85149) : diskPct > 75 ? const Color(0xFFd29922) : const Color(0xFFa371f7),
          sub: '${diskPct.toStringAsFixed(1)}% 사용 중'),
        const SizedBox(height: 16),

        // MCP 서버 상태
        _infoCard('MCP 서버 현황', [
          _infoRow('엔드포인트', '$_serverUrl/mcp'),
          _infoRow('SSE 클라이언트', '${_metrics['sse_clients'] ?? 0}개'),
          _infoRow('활성 팀', '${_metrics['active_teams'] ?? 0}개'),
          _infoRow('활성 티켓', '${_metrics['active_tickets'] ?? 0}개'),
          _infoRow('DB 크기', '${(_metrics['db_size_mb'] as num?)?.toStringAsFixed(2) ?? '0'}MB'),
        ]),
      ]),
    );
  }

  Widget _gaugeCard(String title, double value, String label, {required Color color, required String sub}) {
    final clamped = value.clamp(0.0, 100.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363d)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12, fontWeight: FontWeight.w600)),
          Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: clamped / 100,
            minHeight: 8,
            backgroundColor: const Color(0xFF21262d),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(sub, style: const TextStyle(color: Color(0xFF484f58), fontSize: 11)),
      ]),
    );
  }

  Widget _infoCard(String title, List<Widget> rows) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF161b22),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF30363d)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      const Divider(color: Color(0xFF30363d), height: 1),
      const SizedBox(height: 8),
      ...rows,
    ]),
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12), overflow: TextOverflow.ellipsis)),
    ]),
  );

  String _fmtUptime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h}h ${m}m ${s}s';
  }

  // ── 클라이언트 탭 ──────────────────────────────
  Widget _clientTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFF161b22),
        child: Row(children: [
          Text('연결된 클라이언트: ${_clients.length}개',
            style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
          const Spacer(),
          const Icon(Icons.circle, color: Color(0xFF3fb950), size: 8),
          const SizedBox(width: 4),
          const Text('실시간', style: TextStyle(color: Color(0xFF3fb950), fontSize: 11)),
        ]),
      ),
      Expanded(
        child: _clients.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.devices_other, size: 48, color: Color(0xFF30363d)),
                SizedBox(height: 12),
                Text('연결된 클라이언트 없음', style: TextStyle(color: Color(0xFF8b949e))),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _clients.length,
                itemBuilder: (ctx, i) {
                  final c = _clients[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161b22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF30363d)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B96FF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.computer, color: Color(0xFF1B96FF), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['ip'] as String? ?? '알 수 없음',
                          style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(c['user_agent'] as String? ?? '',
                          style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3fb950).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF3fb950).withOpacity(0.3)),
                        ),
                        child: const Text('연결됨', style: TextStyle(color: Color(0xFF3fb950), fontSize: 11)),
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  // ── 토큰 탭 ──────────────────────────────────
  Widget _tokenTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFF161b22),
        child: Row(children: [
          Text('MCP 토큰: ${_tokens.length}개',
            style: const TextStyle(color: Color(0xFF8b949e), fontSize: 12)),
        ]),
      ),
      Expanded(
        child: _tokens.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.vpn_key_off, size: 48, color: Color(0xFF30363d)),
                SizedBox(height: 12),
                Text('등록된 토큰 없음', style: TextStyle(color: Color(0xFF8b949e))),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _tokens.length,
                itemBuilder: (ctx, i) {
                  final t = _tokens[i];
                  final label = t['label'] as String? ?? t['name'] as String? ?? '알 수 없음';
                  final token = t['token'] as String? ?? '';
                  final masked = token.length > 8
                      ? '${token.substring(0, 4)}****${token.substring(token.length - 4)}'
                      : '****';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161b22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF30363d)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFa371f7).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.vpn_key, color: Color(0xFFa371f7), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(masked, style: const TextStyle(color: Color(0xFF484f58), fontSize: 11, fontFamily: 'monospace')),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3fb950).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF3fb950).withOpacity(0.3)),
                        ),
                        child: const Text('활성', style: TextStyle(color: Color(0xFF3fb950), fontSize: 11)),
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}
