#!/usr/bin/env bash
# code-server-down.sh — transient unit 종료
# Usage: code-server-down.sh <session_id>
set -euo pipefail

SID="${1:-}"
if [[ -z "$SID" ]]; then
  echo "Usage: $0 <session_id>" >&2
  exit 2
fi

UNIT="code-server-$SID.service"
LOG_DIR="$HOME/.local/state/code-server-sessions"

if systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
  systemctl --user stop "$UNIT" 2>/dev/null || true
  echo "code-server down: unit=$UNIT"
else
  echo "이미 정지: $UNIT"
fi

# pid 파일 정리 (참고용)
rm -f "$LOG_DIR/$SID.pid" 2>/dev/null || true
exit 0
