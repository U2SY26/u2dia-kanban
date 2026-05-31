import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme/colors.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _rememberMe = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthService>();
      _urlCtrl.text = auth.serverUrl;
    });
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });

    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();

    final url = _urlCtrl.text.trim();
    final token = _tokenCtrl.text.trim();

    // IP(서버 주소)와 토큰은 필수.
    if (url.isEmpty) {
      setState(() { _loading = false; _error = '서버 IP / 주소를 입력하세요'; });
      return;
    }
    if (token.isEmpty) {
      setState(() { _loading = false; _error = '접속 토큰을 입력하세요'; });
      return;
    }

    await auth.updateServerUrl(url);
    api.configure(auth.serverUrl, token: token);

    // 토큰으로 서버 연결·인증 확인
    final reachable = await api.ping();
    if (!reachable && mounted) {
      setState(() {
        _loading = false;
        _error = '서버에 연결할 수 없습니다. IP와 토큰을 확인하세요.';
      });
      return;
    }

    final ok = await auth.loginWithToken(url, token, rememberMe: _rememberMe);

    if (!mounted) return;
    setState(() { _loading = false; });

    if (ok) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() { _error = '토큰 인증에 실패했습니다.'; });
    }
  }

  Future<void> _enterDemoMode() async {
    setState(() { _loading = true; _error = null; });
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    api.setDemoMode(true);
    await auth.startDemoMode();
    if (!mounted) return;
    setState(() { _loading = false; });
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 로고
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.brandLight,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Center(
                      child: Text(
                        'U',
                        style: TextStyle(
                          fontSize: 38, 
                          fontWeight: FontWeight.w800, 
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'U2DIA AI 칸반보드', 
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI 에이전트 팀 실시간 모니터링', 
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // 서버 IP / 주소 (필수)
                  TextFormField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '서버 IP / 주소',
                      hintText: 'http://100.x.x.x:5555',
                      prefixIcon: Icon(Icons.dns_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 접속 토큰 (필수)
                  TextFormField(
                    controller: _tokenCtrl,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: '접속 토큰',
                      hintText: 'XXXX-XXXX-XXXX-XXXX',
                      prefixIcon: const Icon(Icons.key_outlined, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onFieldSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 10),

                  // 자동 로그인 체크박스
                  Row(
                    children: [
                      SizedBox(
                        width: 20, height: 20,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (v) => setState(() => _rememberMe = v ?? true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '자동 로그인', 
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                      ),
                      const Spacer(),
                    ],
                  ),

                  // 서버 주소 프리셋 — 개인 빌드에서만 노출 (IP 필드 빠른 입력)
                  if (AuthService.serverPresets.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AuthService.serverPresets.map((p) {
                        final selected = _urlCtrl.text.trim() == p['url'];
                        return InkWell(
                          onTap: () => setState(() => _urlCtrl.text = p['url']!),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.brandLight.withValues(alpha: 0.16)
                                  : AppColors.card,
                              border: Border.all(
                                color: selected ? AppColors.brandLight : AppColors.border,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  p['label']!,
                                  style: TextStyle(
                                    color: selected ? AppColors.brandLight : AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  p['desc']!,
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // 에러
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Text(
                        _error!, 
                        style: const TextStyle(
                          color: AppColors.error, 
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (_error != null) const SizedBox(height: 14),

                  // 로그인 버튼
                  ElevatedButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '로그인',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  // 구분자
                  Row(children: [
                    Expanded(child: Divider(color: AppColors.textSecondary.withValues(alpha: 0.2))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('또는',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ),
                    Expanded(child: Divider(color: AppColors.textSecondary.withValues(alpha: 0.2))),
                  ]),
                  const SizedBox(height: 14),
                  // Start Demo Mode 버튼
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _enterDemoMode,
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text(
                      'Start Demo Mode',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      side: BorderSide(color: AppColors.brand.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      minimumSize: const Size(double.infinity, 0),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '서버 없이 샘플 데이터로 모든 기능 체험',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}