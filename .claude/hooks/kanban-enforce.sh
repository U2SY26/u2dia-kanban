#!/bin/bash
# kanban-enforce.sh — Edit/Write 전 칸반 티켓 클레임 강제 확인
#
# KANBAN_TICKET_ID 환경변수가 없으면 강력한 경고 출력.
# exit 2 = Claude Code에서 tool use 차단.

TOOL_NAME="${TOOL_NAME:-}"
FILE_PATH="${TOOL_INPUT_file_path:-${TOOL_INPUT_path:-}}"

# 칸반 관련 파일이나 설정 파일은 예외
if [[ "$FILE_PATH" == *"/.claude/"* ]] || \
   [[ "$FILE_PATH" == *"/kanban"* ]] || \
   [[ "$FILE_PATH" == *"CLAUDE.md"* ]] || \
   [[ "$FILE_PATH" == *"settings.json"* ]]; then
  exit 0
fi

# KANBAN_TICKET_ID가 설정되어 있으면 통과
if [[ -n "$KANBAN_TICKET_ID" ]]; then
  exit 0
fi

# fallback: .active_ticket 파일에서 동적 로드 (HARD-2)
ACTIVE_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/.active_ticket"
if [[ -r "$ACTIVE_FILE" ]]; then
  ID=$(tr -d '[:space:]' < "$ACTIVE_FILE")
  if [[ -n "$ID" ]]; then
    export KANBAN_TICKET_ID="$ID"
    exit 0
  fi
fi

# 강력한 경고 — exit 2로 tool use 차단
cat >&2 <<'EOF'

┌─────────────────────────────────────────────────────┐
│  ⛔ 칸반 티켓 없이 코드 수정 불가                    │
│                                                     │
│  코드 수정 전 반드시:                                │
│  1. kanban_ticket_create() 로 티켓 생성              │
│  2. kanban_ticket_claim()  로 티켓 클레임            │
│  3. export KANBAN_TICKET_ID=T-XXXXXX                │
│                                                     │
│  칸반보드: http://localhost:5555                     │
└─────────────────────────────────────────────────────┘

EOF

exit 2
