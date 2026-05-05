#!/bin/bash
# Claude Code → Flutter 앱 푸시 알림 훅
# Notification 이벤트: CLI가 승인 대기 → type=cli_approval
# Stop 이벤트: CLI가 세션 완료 → type=cli_phase_done
#
# Claude Code v4.6 stdin JSON 파싱.
# Notification 훅 payload: {"hook_event_name":"Notification","message":"...","session_id":"..."}
# Stop 훅 payload: {"hook_event_name":"Stop","stop_hook_active":false,"session_id":"..."}

SERVER_URL="http://localhost:5555/api/notifications"

# stdin JSON 읽기
PAYLOAD=$(cat 2>/dev/null)

# python3로 안전 파싱
INFO=$(python3 -c "
import json, sys, os
try:
    d = json.loads(sys.stdin.read())
    event = d.get('hook_event_name', '')
    msg = d.get('message', '')
    sid = d.get('session_id', '')[:8]
    cwd = os.path.basename(os.environ.get('CLAUDE_PROJECT_DIR', os.getcwd()))
    print(f'{event}|{msg}|{sid}|{cwd}')
except Exception:
    print('|||')
" <<< "$PAYLOAD" 2>/dev/null)

IFS='|' read -r EVENT MSG SID CWD <<< "$INFO"

# 이벤트별 타입 매핑
case "$EVENT" in
  Notification)
    TYPE="cli_approval"
    TITLE="[승인 대기] $CWD"
    BODY="${MSG:-Claude Code가 승인을 대기 중} (세션 $SID)"
    ;;
  Stop)
    TYPE="cli_phase_done"
    TITLE="[Phase 완료] $CWD"
    BODY="Claude Code가 작업을 마쳤습니다 (세션 $SID)"
    ;;
  *)
    exit 0
    ;;
esac

# 서버에 POST (실패해도 무음)
python3 -c "
import json, urllib.request, urllib.error
try:
    data = json.dumps({
        'type': '$TYPE',
        'title': '''$TITLE''',
        'body': '''$BODY''',
        'data': {'event': '$EVENT', 'session': '$SID', 'project': '$CWD'}
    }).encode()
    req = urllib.request.Request(
        '$SERVER_URL',
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    urllib.request.urlopen(req, timeout=3)
except Exception:
    pass
" 2>/dev/null

exit 0
