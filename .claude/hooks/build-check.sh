#!/bin/bash
# Stop hook — 세션 종료 전 빌드 체크
# 이벤트: Stop
# 용도: 작업 종료 전 빌드 에러 없는지 확인 안내

LOG_DIR=".claude/logs"
LOG_FILE="$LOG_DIR/modified_files.log"

if [[ ! -f "$LOG_FILE" ]]; then
  exit 0
fi

FILE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

if [[ "$FILE_COUNT" -gt 0 ]]; then
  echo "이번 세션에서 ${FILE_COUNT}개 파일이 수정되었습니다."
  echo "빌드/테스트를 실행하여 오류가 없는지 확인하세요."
fi

# 로그 정리
rm -f "$LOG_FILE"
