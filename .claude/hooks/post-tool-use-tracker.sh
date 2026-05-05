#!/bin/bash
# PostToolUse hook — 파일 수정 추적
# 이벤트: PostToolUse (Edit, Write)
# 용도: 수정된 파일을 추적하여 영향 범위 파악

TOOL_NAME="${CLAUDE_TOOL_NAME:-}"
FILE_PATH="${CLAUDE_FILE_PATH:-}"

# Edit 또는 Write 도구 사용 시에만 동작
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# 수정 파일 로그 (세션별)
LOG_DIR=".claude/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/modified_files.log"

# 중복 방지 후 기록
if [[ -n "$FILE_PATH" ]]; then
  grep -qxF "$FILE_PATH" "$LOG_FILE" 2>/dev/null || echo "$FILE_PATH" >> "$LOG_FILE"
fi
