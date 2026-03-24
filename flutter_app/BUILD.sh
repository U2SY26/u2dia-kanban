#!/bin/bash
# U2DIA AI 칸반보드 Flutter AAB 빌드 스크립트

echo "═══════════════════════════════════════════"
echo "  U2DIA AI 칸반보드 - Flutter AAB 빌드"
echo "═══════════════════════════════════════════"

# Flutter SDK 설치 확인
if ! command -v flutter &> /dev/null; then
    echo ""
    echo "❌ Flutter SDK가 없습니다."
    echo ""
    echo "설치 방법:"
    echo "  1. https://docs.flutter.dev/get-started/install/linux 접속"
    echo "  2. 또는 snap: sudo snap install flutter --classic"
    echo "  3. 또는 직접: "
    echo "     cd ~ && git clone https://github.com/flutter/flutter.git -b stable"
    echo "     export PATH=\$PATH:\$HOME/flutter/bin"
    echo ""
    exit 1
fi

echo ""
echo "📦 패키지 설치 중..."
flutter pub get

echo ""
echo "🏗️  AAB 빌드 중 (release)..."
flutter build appbundle --release \
  --dart-define=SERVER_URL=http://localhost:5555 \
  --build-name=1.0.0 \
  --build-number=1

echo ""
echo "═══════════════════════════════════════════"
echo "✅ 빌드 완료!"
echo "📁 AAB 위치: build/app/outputs/bundle/release/app-release.aab"
echo ""
echo "▶ Play Store 업로드 또는 내부 테스트용으로 사용하세요."
echo "▶ 직접 설치 시: flutter build apk --release → build/app/outputs/flutter-apk/app-release.apk"
echo "═══════════════════════════════════════════"
