#!/usr/bin/env bash
# U2DIA Kanban — 자동 출시 (빌드 → fastlane 업로드)
# 사용: ./deploy.sh internal     # 내부 테스트 트랙
#       ./deploy.sh production    # 프로덕션
#       ./deploy.sh both          # 내부 + 프로덕션
set -euo pipefail

TRACK="${1:-internal}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="$HOME/.config/play-store/service-account.json"
export PATH="$PATH:$HOME/sdk/flutter/bin:$HOME/.gem/ruby/bin:/home/linuxbrew/.linuxbrew/bin"

# 0) 서비스계정 키 확인
if [ ! -f "$KEY" ]; then
  echo "❌ Play 서비스계정 키가 없습니다: $KEY"
  echo "   Google Cloud에서 서비스계정 생성 → Play Console에서 권한 연결 → JSON 다운로드 후 위 경로에 저장하세요."
  exit 1
fi
command -v fastlane >/dev/null 2>&1 || { echo "❌ fastlane 미설치. 'gem install fastlane' 또는 'brew install fastlane'"; exit 1; }

cd "$APP_DIR"

# 1) AAB 빌드
echo "▶ AAB 빌드..."
flutter build appbundle --release

# 2) fastlane 업로드
cd "$APP_DIR/android"
case "$TRACK" in
  internal)   fastlane internal ;;
  production) fastlane production ;;
  both)       fastlane internal && fastlane production ;;
  *) echo "사용: ./deploy.sh [internal|production|both]"; exit 1 ;;
esac
echo "✅ 완료: $TRACK 트랙 업로드"
