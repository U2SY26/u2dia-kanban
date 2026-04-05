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
    _tabCtrl = TabController(length: 4, vsync: this);
    _serverUrl = context.read<AuthService>().serverUrl;
    _connected = context.read<ApiService>().connected;
    _loadAll();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _loadAll());
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
            Tab(icon: Icon(Icons.info_outline, size: 18), text: '앱 정보'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabCtrl, children: [
        _resourceTab(),
        _clientTab(),
        _tokenTab(),
        _appInfoTab(),
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
        const SizedBox(height: 12),

        // GPU
        if ((_metrics['gpu_name'] as String?)?.isNotEmpty == true) ...[
          _gpuSection(),
          const SizedBox(height: 12),
        ],

        // 온도 센서
        if ((_metrics['temps'] as List?)?.isNotEmpty == true || (_metrics['gpu_temp'] as num? ?? 0) > 0) ...[
          _tempSection(),
          const SizedBox(height: 16),
        ],

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

  Widget _gpuSection() {
    final gpuName = _metrics['gpu_name'] as String? ?? '';
    final gpuUtil = (_metrics['gpu_util'] as num?)?.toDouble() ?? 0;
    final gpuTemp = (_metrics['gpu_temp'] as num?)?.toDouble() ?? 0;
    final vramUsed = (_metrics['gpu_vram_used_mb'] as num?)?.toDouble() ?? 0;
    final vramTotal = (_metrics['gpu_vram_total_mb'] as num?)?.toDouble() ?? 0;
    final vramPct = (_metrics['gpu_vram_percent'] as num?)?.toDouble() ?? 0;
    final powerW = (_metrics['gpu_power_w'] as num?)?.toDouble() ?? 0;
    final powerMax = (_metrics['gpu_power_max_w'] as num?)?.toDouble() ?? 0;
    final fan = (_metrics['gpu_fan_percent'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363d)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.videogame_asset, size: 14, color: Color(0xFF58a6ff)),
          const SizedBox(width: 6),
          Expanded(child: Text(gpuName, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 12),
        // GPU 사용률
        _miniBar('GPU', gpuUtil, '${gpuUtil.toStringAsFixed(0)}%',
          gpuUtil > 80 ? const Color(0xFFf85149) : gpuUtil > 50 ? const Color(0xFFd29922) : const Color(0xFF58a6ff)),
        const SizedBox(height: 8),
        // VRAM
        _miniBar('VRAM', vramPct, '${(vramUsed/1024).toStringAsFixed(1)} / ${(vramTotal/1024).toStringAsFixed(1)} GB',
          vramPct > 80 ? const Color(0xFFf85149) : vramPct > 50 ? const Color(0xFFd29922) : const Color(0xFF3fb950)),
        const SizedBox(height: 10),
        // GPU 세부 정보
        Row(children: [
          _chipInfo('🌡️', '${gpuTemp.toStringAsFixed(0)}°C',
            gpuTemp > 80 ? const Color(0xFFf85149) : gpuTemp > 60 ? const Color(0xFFd29922) : const Color(0xFF8b949e)),
          const SizedBox(width: 8),
          _chipInfo('⚡', '${powerW.toStringAsFixed(0)} / ${powerMax.toStringAsFixed(0)}W', const Color(0xFF8b949e)),
          const SizedBox(width: 8),
          if (fan > 0) _chipInfo('💨', '$fan%', const Color(0xFF8b949e)),
        ]),
      ]),
    );
  }

  Widget _miniBar(String label, double pct, String detail, Color color) {
    final clamped = pct.clamp(0.0, 100.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
        Text(detail, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: clamped / 100, minHeight: 6,
          backgroundColor: const Color(0xFF21262d), valueColor: AlwaysStoppedAnimation(color)),
      ),
    ]);
  }

  Widget _chipInfo(String icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF21262d),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30363d)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _tempSection() {
    final temps = (_metrics['temps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final gpuTemp = (_metrics['gpu_temp'] as num?)?.toDouble() ?? 0;
    final gpuName = _metrics['gpu_name'] as String? ?? '';

    final items = <_TempItem>[];
    if (gpuTemp > 0) items.add(_TempItem('GPU', gpuTemp, '🎮'));
    for (final t in temps) {
      final name = t['name']?.toString() ?? '';
      final temp = (t['temp'] as num?)?.toDouble() ?? 0;
      if (temp <= 0) continue;
      final ln = name.toLowerCase();
      String icon = '🌡️';
      if (ln.contains('tctl') || ln.contains('core') || ln.contains('package') || ln.contains('cpu')) icon = '🔥';
      if (ln.contains('composite') || ln.contains('nvme') || ln.contains('ssd')) icon = '💾';
      if (ln.contains('edge')) icon = '🎮';
      items.add(_TempItem(name, temp, icon));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161b22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363d)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('온도 센서', style: TextStyle(color: Color(0xFF8b949e), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: items.map((t) {
          final color = t.temp > 80 ? const Color(0xFFf85149) : t.temp > 60 ? const Color(0xFFd29922) : const Color(0xFF8b949e);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF21262d),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF30363d)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(t.icon, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t.name, style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
                Text('${t.temp.toStringAsFixed(1)}°C', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
              ]),
            ]),
          );
        }).toList()),
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
  // ── 앱 정보 탭 ──────────────────────────────────
  Widget _appInfoTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadAppInfo(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? {};
        final ollamaStatus = data['ollama_status'] as String? ?? '조회 중...';
        final ollamaModel = data['ollama_model'] as String? ?? '';
        final pipelineHealth = data['pipeline_health'] as String? ?? '조회 중...';
        final pipelinePending = data['pipeline_pending'] as int? ?? 0;
        final activeTeams = data['active_teams'] as int? ?? 0;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 앱 버전
            _infoCard('앱 정보', [
              _infoRow('버전', 'v4.4.0'),
              _infoRow('플랫폼', 'Flutter (Dart)'),
            ]),
            const SizedBox(height: 16),

            // 서버 연결
            _infoCard('서버 연결', [
              _infoRow('서버 URL', _serverUrl),
              _infoRow('연결 상태', _connected ? '연결됨' : '연결 끊김'),
            ]),
            const SizedBox(height: 16),

            // 올라마 상태
            _infoCard('올라마 (Ollama)', [
              _infoRow('상태', ollamaStatus),
              if (ollamaModel.isNotEmpty) _infoRow('모델', ollamaModel),
            ]),
            const SizedBox(height: 16),

            // Supervisor 파이프라인
            _infoCard('Supervisor 파이프라인', [
              _infoRow('상태', pipelineHealth),
              _infoRow('대기 검수', '$pipelinePending건'),
            ]),
            const SizedBox(height: 16),

            // 활성 팀
            _infoCard('팀 현황', [
              _infoRow('활성 팀', '$activeTeams개'),
            ]),
            const SizedBox(height: 32),

            // 알림 설정
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF161b22), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF30363d))),
              child: Row(children: [
                const Icon(Icons.notifications_outlined, size: 16, color: Color(0xFF8b949e)),
                const SizedBox(width: 8),
                const Expanded(child: Text('푸시 알림', style: TextStyle(color: Color(0xFFe6edf3), fontSize: 12))),
                Switch(
                  value: true,
                  onChanged: (v) {},
                  activeColor: const Color(0xFF1B96FF),
                ),
              ]),
            ),

            // 서버 URL
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF161b22), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF30363d))),
              child: Row(children: [
                const Icon(Icons.dns_outlined, size: 16, color: Color(0xFF8b949e)),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('서버 URL', style: TextStyle(color: Color(0xFF8b949e), fontSize: 10)),
                  Text(_serverUrl, style: const TextStyle(color: Color(0xFFe6edf3), fontSize: 12, fontFamily: 'monospace')),
                ])),
                const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF484f58)),
              ]),
            ),

            // 로그아웃 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFf85149).withOpacity(0.15),
                  foregroundColor: const Color(0xFFf85149),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xFFf85149), width: 0.5),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('로그아웃', style: TextStyle(fontWeight: FontWeight.w600)),
                onPressed: () async {
                  final auth = context.read<AuthService>();
                  await auth.logout();
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadAppInfo() async {
    final api = context.read<ApiService>();
    final result = <String, dynamic>{};

    // 올라마 상태
    try {
      final agentRes = await api.get('/api/agent/status');
      result['ollama_status'] = agentRes['running'] == true ? '실행 중' : '중지됨';
      result['ollama_model'] = agentRes['model'] as String? ?? '';
    } catch (_) {
      result['ollama_status'] = '연결 실패';
    }

    // Supervisor 파이프라인
    try {
      final pipeRes = await api.supervisorPipeline();
      result['pipeline_health'] = pipeRes['healthy'] == true ? '정상' : '이상';
      result['pipeline_pending'] = pipeRes['pending_count'] as int? ?? 0;
    } catch (_) {
      result['pipeline_health'] = '연결 실패';
    }

    // 활성 팀
    try {
      final teams = await api.getTeams();
      result['active_teams'] = teams.length;
    } catch (_) {
      result['active_teams'] = 0;
    }

    return result;
  }
}

class _TempItem {
  final String name;
  final double temp;
  final String icon;
  _TempItem(this.name, this.temp, this.icon);
}
