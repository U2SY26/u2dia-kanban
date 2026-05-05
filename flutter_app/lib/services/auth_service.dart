import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService extends ChangeNotifier {
  static const _keyLoggedIn = 'is_logged_in';
  static const _keyUsername = 'username';
  static const _keyAutoLogin = 'auto_login';
  static const _secKeyPassword = 'password';
  static const _keyServerUrl = 'server_url';
  static const _keyDemoMode = 'demo_mode';

  // 기본값 — 사용자가 직접 자기 서버 URL/자격증명을 입력해야 함
  static const defaultServerUrl = '';
  // Demo 모드: 자격증명 불필요. 정적 mock 데이터로 동작.
  static const demoUsername = 'demo';
  static const demoPassword = 'demo';

  final _secureStorage = const FlutterSecureStorage();

  bool _isLoggedIn = false;
  bool _autoLogin = false;
  bool _demoMode = false;
  String _username = '';
  String _serverUrl = defaultServerUrl;
  String? _token;

  bool get isLoggedIn => _isLoggedIn;
  bool get autoLogin => _autoLogin;
  bool get demoMode => _demoMode;
  String get username => _username;
  String get serverUrl => _serverUrl;
  String? get token => _token;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _autoLogin = prefs.getBool(_keyAutoLogin) ?? false;
    _demoMode = prefs.getBool(_keyDemoMode) ?? false;
    _username = prefs.getString(_keyUsername) ?? '';
    _serverUrl = prefs.getString(_keyServerUrl) ?? defaultServerUrl;

    if (_demoMode) {
      await _performLogin(demoUsername, demoPassword, silent: true);
      return;
    }
    if (_autoLogin && _username.isNotEmpty) {
      final savedPassword = await _secureStorage.read(key: _secKeyPassword);
      if (savedPassword != null) {
        await _performLogin(_username, savedPassword, silent: true);
      }
    }
  }

  /// 사용자 직접 입력한 자격증명으로 로그인.
  /// 데모 'demo'/'demo' 입력 시 자동으로 데모 모드 진입.
  Future<bool> login(String username, String password, {bool rememberMe = true}) async {
    if (username == demoUsername && password == demoPassword) {
      return startDemoMode();
    }
    if (username.isEmpty || password.isEmpty) {
      return false;
    }
    await _performLogin(username, password, silent: false);
    if (rememberMe) {
      await _saveCredentials(username, password);
    }
    return true;
  }

  /// Play Store 검토 / 일반 사용자 첫 체험용 데모 모드 진입.
  /// 정적 mock 데이터로 모든 화면 동작.
  Future<bool> startDemoMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDemoMode, true);
    await prefs.setBool(_keyLoggedIn, true);
    _demoMode = true;
    await _performLogin(demoUsername, demoPassword, silent: false);
    return true;
  }

  Future<void> _performLogin(String username, String password, {required bool silent}) async {
    _isLoggedIn = true;
    _username = username;
    // 서버 토큰 (서버가 토큰 인증 방식일 경우 여기서 취득)
    // 현재는 심플 인증
    if (!silent) notifyListeners();
  }

  Future<void> _saveCredentials(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLoggedIn, true);
    await prefs.setBool(_keyAutoLogin, true);
    await prefs.setString(_keyUsername, username);
    await _secureStorage.write(key: _secKeyPassword, value: password);
    _autoLogin = true;
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLoggedIn, false);
    await prefs.setBool(_keyAutoLogin, false);
    await prefs.setBool(_keyDemoMode, false);
    await _secureStorage.delete(key: _secKeyPassword);
    _isLoggedIn = false;
    _autoLogin = false;
    _demoMode = false;
    _token = null;
    notifyListeners();
  }

  Future<void> updateServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = url.trimRight().replaceAll(RegExp(r'/$'), '');
    await prefs.setString(_keyServerUrl, _serverUrl);
    notifyListeners();
  }
}
