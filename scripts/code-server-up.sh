#!/usr/bin/env bash
# code-server-up.sh — 단일 워크스페이스용 code-server spawn (systemd-run transient unit)
# Usage: code-server-up.sh <session_id> <port> <workspace_path>
# kanban-board.service 와 cgroup 분리하여 서버 재시작에 영향 없게 함.
set -euo pipefail

SID="${1:-}"
PORT="${2:-}"
WS_PATH="${3:-}"

if [[ -z "$SID" || -z "$PORT" || -z "$WS_PATH" ]]; then
  echo "Usage: $0 <session_id> <port> <workspace_path>" >&2
  exit 2
fi

if [[ ! -d "$WS_PATH" ]]; then
  echo "워크스페이스 디렉토리 없음: $WS_PATH" >&2
  exit 3
fi

CODE_SERVER="${CODE_SERVER_BIN:-$HOME/.local/bin/code-server}"
if [[ ! -x "$CODE_SERVER" ]]; then
  echo "code-server 미설치: $CODE_SERVER" >&2
  exit 4
fi

DATA_DIR="$HOME/.local/share/code-server-sessions/$SID"
EXT_DIR="$HOME/.local/share/code-server/extensions"
LOG_DIR="$HOME/.local/state/code-server-sessions"
mkdir -p "$DATA_DIR" "$EXT_DIR" "$LOG_DIR"

UNIT="code-server-$SID.service"

# 이미 transient unit 으로 실행 중이면 패스
if systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
  echo "이미 실행 중: $UNIT"
  exit 0
fi

# systemd-run 으로 transient user service 등록 — 별도 cgroup
systemd-run --user --no-block \
  --unit "$UNIT" \
  --description "code-server $SID @ $WS_PATH" \
  --collect \
  --setenv "HOME=$HOME" \
  --setenv "PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  -p StandardOutput="append:$LOG_DIR/$SID.log" \
  -p StandardError="append:$LOG_DIR/$SID.log" \
  "$CODE_SERVER" \
  --bind-addr "127.0.0.1:$PORT" \
  --auth none \
  --disable-telemetry \
  --disable-update-check \
  --user-data-dir "$DATA_DIR" \
  --extensions-dir "$EXT_DIR" \
  "$WS_PATH"

# 부팅 확인 — 최대 8초
for _ in $(seq 1 40); do
  if bash -c ">/dev/tcp/127.0.0.1/$PORT" 2>/dev/null; then
    # MainPID 추출 (참고용)
    PID=$(systemctl --user show -p MainPID --value "$UNIT" 2>/dev/null || echo 0)
    echo "$PID" > "$LOG_DIR/$SID.pid" 2>/dev/null || true
    echo "code-server up: sid=$SID unit=$UNIT pid=$PID port=$PORT path=$WS_PATH"
    exit 0
  fi
  sleep 0.2
done

echo "부팅 8초 내 응답 없음 — journalctl --user -u $UNIT" >&2
exit 5
