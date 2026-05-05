#!/usr/bin/env bash
# active-ticket-sync.sh — .claude/.active_ticket 파일을 KANBAN_TICKET_ID env 로 매번 동기화
# settings.json 의 하드코딩 env 를 대체. 미설정 시 조용히 통과.
ACTIVE_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/.active_ticket"
if [[ -r "$ACTIVE_FILE" ]]; then
  ID=$(tr -d '[:space:]' < "$ACTIVE_FILE")
  if [[ -n "$ID" ]]; then
    # stderr 로 안내 (PreToolUse stderr 는 차단 신호 아님 — exit 0 유지)
    echo "[active-ticket-sync] KANBAN_TICKET_ID=$ID (from .active_ticket)" >&2
  fi
fi
exit 0
