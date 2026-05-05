#!/bin/bash
# Flutter build 전 자동 versionCode +1
# PreToolUse(Bash) 훅 — Claude Code v4.6 stdin JSON 파싱
#
# Claude Code는 훅에 도구 입력을 stdin JSON으로 전달:
#   {"tool_name": "Bash", "tool_input": {"command": "..."}, "session_id": "...", ...}
#
# 이전 버전은 $TOOL_INPUT 환경변수를 사용했지만 v4.6에서 동작하지 않음 → stdin 파싱으로 교체

PUBSPEC="$CLAUDE_PROJECT_DIR/flutter_app/pubspec.yaml"

# stdin JSON 읽어서 command 필드만 추출 (python3는 모든 Linux에서 보장됨)
CMD=$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input') or {}
    print(ti.get('command', ''))
except Exception:
    pass
" 2>/dev/null)

# flutter build 감지 (appbundle/apk/ios 모두 포함)
if echo "$CMD" | grep -qE 'flutter\s+build\s+(appbundle|apk|ios|web|macos|windows|linux)'; then
  if [ -f "$PUBSPEC" ]; then
    python3 -c "
import re, sys
p = '$PUBSPEC'
s = open(p).read()
m = re.search(r'^version:\s*(.+?)\+(\d+)', s, re.M)
if not m:
    sys.stderr.write('FLUTTER_VERSION_BUMP: version line not found\n')
    sys.exit(0)
old_code = int(m.group(2))
new_code = old_code + 1
s2 = re.sub(r'^(version:\s*)(.+?)\+(\d+)',
            lambda mm: f'{mm.group(1)}{mm.group(2)}+{new_code}', s, count=1, flags=re.M)
open(p, 'w').write(s2)
sys.stderr.write(f'FLUTTER_VERSION_BUMP: {m.group(1)}+{old_code} -> {m.group(1)}+{new_code}\n')
"
  fi
fi

exit 0
