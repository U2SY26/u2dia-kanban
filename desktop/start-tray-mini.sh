#!/bin/bash
# U2DIA 미니 트레이 — 상태창 아이콘
# 사용법: ./start-tray-mini.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ELECTRON="$SCRIPT_DIR/server-manager-app/node_modules/electron/dist/electron"

if [ ! -f "$ELECTRON" ]; then
  echo "Electron not found. Run: cd server-manager-app && npm install" >&2
  exit 1
fi

# 이미 실행 중이면 종료
pkill -f "tray-mini.js" 2>/dev/null

exec env -u ELECTRON_RUN_AS_NODE -u ELECTRON_NO_ATTACH_CONSOLE \
  DISPLAY="${DISPLAY:-:1}" \
  "$ELECTRON" "$SCRIPT_DIR/tray-mini.js" --no-sandbox "$@"
