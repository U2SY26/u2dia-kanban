#!/bin/bash
# checklist-enforce.sh — 헌법 제7원칙 강제: 체크리스트 + 전문스킬 + Supervisor 승인
# stdin JSON 파싱 (Claude Code v4.6+)

KANBAN_API="${KANBAN_API:-http://localhost:5555}"
STRICT="${CHECKLIST_STRICT:-1}"

PAYLOAD=$(cat 2>/dev/null || true)
FILE_PATH=$(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read() or '{}')
    ti = d.get('tool_input') or {}
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')
" 2>/dev/null)

# 메타 작업 화이트리스트 (HARD-3 — 좁힌 범위)
# 도메인 docs/ 작업도 체크리스트 받게 하려면 CHECKLIST_STRICT_DOCS=1
if [[ "$CHECKLIST_STRICT_DOCS" == "1" ]]; then
  case "$FILE_PATH" in
    */.claude/.active_ticket|*/.claude/hooks/*|*/.claude/settings*.json|*CLAUDE.md|*UNIVERSAL_AGENT_RULES*|*/docs/plans/*|*/docs/reports/*)
      exit 0
      ;;
  esac
else
  case "$FILE_PATH" in
    */.claude/*|*/kanban*|*CLAUDE.md|*settings.json|*/docs/*|*UNIVERSAL_AGENT_RULES*|*/hooks/*)
      exit 0
      ;;
  esac
fi

# fallback: .active_ticket 파일에서 동적 로드 (HARD-2)
if [[ -z "$KANBAN_TICKET_ID" ]]; then
  ACTIVE_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/.active_ticket"
  if [[ -r "$ACTIVE_FILE" ]]; then
    ID=$(tr -d '[:space:]' < "$ACTIVE_FILE")
    [[ -n "$ID" ]] && export KANBAN_TICKET_ID="$ID"
  fi
fi
[[ -z "$KANBAN_TICKET_ID" ]] && exit 0

TICKET_JSON=$(curl -s --max-time 3 "${KANBAN_API}/api/tickets/${KANBAN_TICKET_ID}" 2>/dev/null)
[[ -z "$TICKET_JSON" ]] && exit 0

read -r STATUS HAS_CHK <<<"$(printf '%s' "$TICKET_JSON" | python3 -c "
import json, re, sys
try:
    d = json.load(sys.stdin)
    t = d.get('ticket') or d
    desc = (t.get('description') or '')
    has = bool(re.search(r'^\s*-\s*\[[ xX]\]', desc, re.MULTILINE))
    print(t.get('status') or '', '1' if has else '0')
except Exception:
    print('Unknown 0')
" 2>/dev/null)"

case "$STATUS" in
  Done|Archived|Cancelled) exit 0 ;;
esac

[[ "$HAS_CHK" == "1" ]] && exit 0

cat >&2 <<EOF

┌──────────────────────────────────────────────────────────────┐
│  ⚠️  헌법 제7원칙 위반: 티켓에 체크리스트가 없음               │
│                                                              │
│  티켓 ${KANBAN_TICKET_ID} (status=${STATUS})                  │
│  description 에 GFM 체크박스가 존재하지 않습니다.              │
│                                                              │
│  의무: '- [ ] 항목' 형식으로 분해 → 진행 시 [x] 업데이트       │
│  → 100% 완료 후 supervisor 검수                                │
│                                                              │
│  헌법: docs/UNIVERSAL_AGENT_RULES.md 제7원칙                   │
└──────────────────────────────────────────────────────────────┘

EOF

[[ "$STRICT" == "1" ]] && exit 2 || exit 0
