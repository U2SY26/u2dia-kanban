import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/auth_service.dart';
import 'dashboard_screen.dart' show DashboardScreen;

/// WebView shell — KANBAN 웹 SPA(/#/) 를 그대로 로드해서 모바일에 미러링.
/// 네이티브 백업은 [DashboardScreen] (헤더 좌측 ⓘ 버튼으로 접근).
class DashboardWebViewScreen extends StatefulWidget {
  final void Function(String, String)? onTeamTap;
  final void Function(int)? onNavigateToTab;
  final void Function(int)? onNavigateToOperations;

  const DashboardWebViewScreen({
    super.key,
    this.onTeamTap,
    this.onNavigateToTab,
    this.onNavigateToOperations,
  });

  @override
  State<DashboardWebViewScreen> createState() => _DashboardWebViewScreenState();
}

class _DashboardWebViewScreenState extends State<DashboardWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    final base = (auth.serverUrl).replaceAll(RegExp(r'/$'), '');
    final url = '$base/#/';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0E16))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() {
          _loading = true;
          _error = null;
        }),
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (e) => setState(() {
          _loading = false;
          _error = '${e.errorCode}: ${e.description}';
        }),
      ))
      ..loadRequest(Uri.parse(url));
  }

  void _reload() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _controller.reload();
  }

  void _showNativeFallback() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Native Dashboard (백업)')),
        body: DashboardScreen(
          onTeamTap: widget.onTeamTap,
          onNavigateToTab: widget.onNavigateToTab,
          onNavigateToOperations: widget.onNavigateToOperations,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Dashboard', style: TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.dashboard_customize_outlined, size: 20),
          tooltip: 'Native 백업 보기',
          onPressed: _showNativeFallback,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '새로고침',
            onPressed: _reload,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ),
          if (_error != null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.85),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    const Text('웹 대시보드 로드 실패',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(_error ?? '',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, children: [
                      ElevatedButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('재시도'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showNativeFallback,
                        icon: const Icon(Icons.dashboard_customize_outlined, size: 16),
                        label: const Text('Native 백업 사용'),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
