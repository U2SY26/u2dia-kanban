#!/usr/bin/env bash
# cli-mirror-down.sh — Remote CLI Mirror 종료
set -euo pipefail

SESSION="${CLI_MIRROR_SESSION:-claude}"
LOG_DIR="${CLI_MIRROR_LOG_DIR:-$HOME/.local/state/cli-mirror}"
PID_FILE="$LOG_DIR/ttyd.pid"
KILL_TMUX="${CLI_MIRROR_KILL_TMUX:-0}"

if [[ -f "$PID_FILE" ]]; then
  PID="$(cat "$PID_FILE")"
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" && echo "ttyd 종료 (pid=$PID)"
  else
    echo "ttyd pid=$PID 이미 죽어 있음"
  fi
  rm -f "$PID_FILE"
else
  echo "PID 파일 없음 — 실행 중 아님"
fi

if [[ "$KILL_TMUX" == "1" ]]; then
  tmux kill-session -t "$SESSION" 2>/dev/null && echo "tmux 세션 종료: $SESSION" || echo "tmux 세션 없음: $SESSION"
else
  echo "tmux 세션 보존: $SESSION (CLI_MIRROR_KILL_TMUX=1 로 종료 가능)"
fi
