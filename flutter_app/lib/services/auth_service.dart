import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService extends ChangeNotifier {
  static const _keyLoggedIn = 'is_logged_in';
  static const _keyUsername = 'username';
  static const _keyAutoLogin = 'auto_login';
  static const _secKeyPassword = 'password';
  static const _keyServerUrl = 'server_url';

  // 기본 자격증명
  static const defaultUsername = 'u2dia';
  static const defaultPassword = 'syu211250626';
  static const defaultServerUrl = 'http://localhost:5555';

  final _secureStorage = const FlutterSecureStorage();

  bool _isLoggedIn = false;
  bool _autoLogin = false;
  String _username = '';
  String _serverUrl = defaultServerUrl;
  String? _token;

  bool get isLoggedIn => _isLoggedIn;
  bool get autoLogin => _autoLogin;
  String get username => _username;
  String get serverUrl => _serverUrl;
  String? get token => _token;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _autoLogin = prefs.getBool(_keyAutoLogin) ?? false;
    _username = prefs.getString(_keyUsername) ?? '';
    _serverUrl = prefs.getString(_keyServerUrl) ?? defaultServerUrl;

    if (_autoLogin && _username.isNotEmpty) {
      final savedPassword = await _secureStorage.read(key: _secKeyPassword);
      if (savedPassword != null) {
        await _performLogin(_username, savedPassword, silent: true);
      }
    }
  }

  Future<bool> login(String username, String password, {bool rememberMe = true}) async {
    // 자격증명 검증
    if (username == defaultUsername && password == defaultPassword) {
      await _performLogin(username, password, silent: false);
      if (rememberMe) {
        await _saveCredentials(username, password);
      }
      return true;
    }
    // 서버에서도 검증 시도 (추후 확장)
    return false;
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
    await _secureStorage.delete(key: _secKeyPassword);
    _isLoggedIn = false;
    _autoLogin = false;
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
