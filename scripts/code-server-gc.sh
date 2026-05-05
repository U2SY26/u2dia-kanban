#!/usr/bin/env bash
# code-server-gc.sh — idle 세션 정리 (last_active > IDLE_MIN 분)
# 5분마다 systemd timer로 호출
set -euo pipefail

KANBAN_URL="${KANBAN_URL:-http://127.0.0.1:5555}"
IDLE_MIN="${VSCODE_IDLE_MIN:-30}"
TOKEN="${KANBAN_TOKEN:-}"

# 인증 헤더 (로컬은 면제이지만 안전을 위해 포함 가능)
AUTH_ARGS=()
[[ -n "$TOKEN" ]] && AUTH_ARGS=(-H "Authorization: Bearer $TOKEN")

NOW=$(date +%s)
THRESHOLD=$(( NOW - IDLE_MIN * 60 ))

# 세션 목록 조회
SESSIONS_JSON=$(curl -sf "${AUTH_ARGS[@]}" "$KANBAN_URL/api/vscode/sessions" || echo '{"sessions":[]}')

# python3 로 idle 세션 추출
IDLE_IDS=$(echo "$SESSIONS_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    threshold = $THRESHOLD
    for s in d.get('sessions', []):
        if int(s.get('last_active', 0)) < threshold:
            print(s['id'])
except Exception as e:
    sys.stderr.write(f'parse error: {e}\n')
")

if [[ -z "$IDLE_IDS" ]]; then
  echo "idle 세션 없음 (임계: ${IDLE_MIN}분)"
  exit 0
fi

for SID in $IDLE_IDS; do
  echo "GC 종료: $SID"
  curl -sf -X DELETE "${AUTH_ARGS[@]}" "$KANBAN_URL/api/vscode/sessions/$SID" >/dev/null || true
done
