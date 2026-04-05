#!/bin/bash
# U2DIA Server Manager — Linux 트레이 실행 스크립트
# Claude Code(VSCode) 환경에서 ELECTRON_RUN_AS_NODE=1이 설정되어 있어 반드시 제거 필요
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/server-manager-app"
ELECTRON="$APP_DIR/node_modules/electron/dist/electron"

if [ ! -f "$ELECTRON" ]; then
  echo "Electron not found: $ELECTRON" >&2
  exit 1
fi

exec env -u ELECTRON_RUN_AS_NODE -u ELECTRON_NO_ATTACH_CONSOLE \
  DISPLAY="${DISPLAY:-:1}" \
  "$ELECTRON" "$APP_DIR" "$@"
