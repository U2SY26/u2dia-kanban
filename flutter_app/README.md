# U2DIA AI 칸반보드 — Flutter 모바일 앱

## 기능
- 로그인 (u2dia / syu211250626)
- 자동 로그인 (SharedPreferences + SecureStorage)
- 대시보드: KPI + 팀 목록
- 칸반보드: 컬럼별 티켓 + 5초 실시간 갱신
- 아카이브 목록
- 설정: 서버 URL 변경

## 빌드

### 사전 요구사항
- Flutter 3.10+ 설치

### AAB 빌드 (Play Store)
```bash
cd flutter_app
./BUILD.sh
```

### APK 빌드 (직접 설치)
```bash
flutter pub get
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

### 디버그 실행 (USB 연결 기기)
```bash
flutter run
```

## 서버 설정

앱 설치 후 "설정" 탭에서 서버 URL 변경 가능:
- **로컬 WiFi**: `http://192.168.x.x:5555`
- **Tailscale**: `http://100.x.x.x:5555`
- **Cloudflare Tunnel**: `https://your-tunnel.trycloudflare.com`

## 기본 계정
- ID: `u2dia`
- PW: `syu211250626`
