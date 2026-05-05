#!/usr/bin/env bash
# cli-mirror-up.sh — Remote CLI Mirror 기동 (ttyd + tmux)
# 헌법 제2원칙: 외부 0.0.0.0 바인드 절대 금지. Tailscale 또는 127.0.0.1 만 허용.
set -euo pipefail

SESSION="${CLI_MIRROR_SESSION:-claude}"
PORT="${CLI_MIRROR_PORT:-7681}"
BIND="${CLI_MIRROR_BIND:-127.0.0.1}"
WRITABLE="${CLI_MIRROR_WRITABLE:-1}"
AUTH="${CLI_MIRROR_AUTH:-}"
LOG_DIR="${CLI_MIRROR_LOG_DIR:-$HOME/.local/state/cli-mirror}"
TTYD_BIN="${TTYD_BIN:-$HOME/.local/bin/ttyd}"

if [[ "$BIND" == "0.0.0.0" || "$BIND" == "::" || "$BIND" == "*" ]]; then
  echo "ERROR: 0.0.0.0 바인드 금지. CLI_MIRROR_BIND 를 127.0.0.1 또는 Tailscale IP 로 설정." >&2
  exit 1
fi

command -v tmux >/dev/null || { echo "tmux 미설치"; exit 1; }
[[ -x "$TTYD_BIN" ]] || { echo "ttyd 없음: $TTYD_BIN"; exit 1; }

mkdir -p "$LOG_DIR"
PID_FILE="$LOG_DIR/ttyd.pid"
LOG_FILE="$LOG_DIR/ttyd.log"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "이미 실행 중 (pid=$(cat "$PID_FILE")). down 후 다시 up 하세요."
  exit 0
fi

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux new-session -d -s "$SESSION" -x 200 -y 50
  echo "tmux 세션 생성: $SESSION"
else
  echo "tmux 세션 재사용: $SESSION"
fi

ARGS=(-i "$BIND" -p "$PORT")
[[ "$WRITABLE" == "1" ]] && ARGS+=(--writable)
[[ -n "$AUTH" ]] && ARGS+=(-c "$AUTH")
ARGS+=(-t fontSize=14 -t 'theme={"background":"#0b0f17"}')

nohup "$TTYD_BIN" "${ARGS[@]}" tmux attach -t "$SESSION" >"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

sleep 0.3
if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "ttyd 기동: pid=$(cat "$PID_FILE")  bind=$BIND:$PORT  writable=$WRITABLE  session=$SESSION"
  echo "로그: $LOG_FILE"
  [[ "$BIND" == "127.0.0.1" ]] && echo "외부 접근: Tailscale 사용 또는 server.py 의 /cli WS 프록시 필요"
else
  echo "기동 실패. 로그 확인:" >&2
  tail -20 "$LOG_FILE" >&2
  exit 1
fi
