#!/bin/bash
# competition-progress.sh — PostToolUse hook for competition agents
# 에이전트 작업 후 자동으로 칸반 서버에 진행상황 업데이트
#
# stdin: JSON { tool_name, tool_input, tool_output }
# 트리거: Bash (train/submit/test/kaggle 키워드) 감지 시 자동 보고
#
# 설치: settings.json PostToolUse에 Bash 매처로 등록
# 경량: 칸반 서버 응답 1초 타임아웃, 실패 시 무시 (에이전트 작업 차단 안 함)

set -euo pipefail

KANBAN_URL="${KANBAN_URL:-http://localhost:5555}"
ACTIVE_TICKET_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/.active_ticket"

# stdin JSON 파싱
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")

# Bash 도구만 처리
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
inp = d.get('tool_input', {})
if isinstance(inp, dict):
    print(inp.get('command', ''))
elif isinstance(inp, str):
    print(inp)
" 2>/dev/null || echo "")

# 빈 명령 무시
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# 유의미한 키워드만 감지 (노이즈 방지)
SIGNIFICANT=false
EVENT_TYPE=""
NOTE=""

case "$COMMAND" in
  *kaggle*submit*|*kaggle*competitions*submit*)
    SIGNIFICANT=true; EVENT_TYPE="submission"; NOTE="Kaggle 제출 실행" ;;
  *python*train*|*python*finetune*|*python*sft*|*python*dpo*|*torchrun*|*accelerate*launch*)
    SIGNIFICANT=true; EVENT_TYPE="training"; NOTE="모델 학습 실행" ;;
  *python*eval*|*python*test*|*python*validate*|*python*infer*|*pytest*)
    SIGNIFICANT=true; EVENT_TYPE="evaluation"; NOTE="평가/테스트 실행" ;;
  *python*submit*|*python*predict*|*python*generate_submission*)
    SIGNIFICANT=true; EVENT_TYPE="submission_prep"; NOTE="제출 파일 생성" ;;
  *wandb*|*tensorboard*|*mlflow*)
    SIGNIFICANT=true; EVENT_TYPE="logging"; NOTE="실험 로깅" ;;
  *git*push*|*git*commit*)
    SIGNIFICANT=true; EVENT_TYPE="git_commit"; NOTE="코드 커밋/푸시" ;;
  *pip*install*|*conda*install*)
    SIGNIFICANT=true; EVENT_TYPE="setup"; NOTE="환경 설정" ;;
  *lambda*|*ssh*|*rsync*cloud*)
    SIGNIFICANT=true; EVENT_TYPE="cloud_ops"; NOTE="클라우드 작업" ;;
esac

if [[ "$SIGNIFICANT" != "true" ]]; then
  exit 0
fi

# 프로젝트 그룹 감지 (디렉토리 이름 기반)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_GROUP=$(basename "$PROJECT_DIR")

# 출력에서 점수/순위 자동 추출 시도
SCORE_UPDATE=""
RANK_UPDATE=""
OUTPUT_TEXT=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
out = d.get('tool_output', {})
if isinstance(out, dict):
    print(out.get('stdout', '')[:2000])
elif isinstance(out, str):
    print(out[:2000])
" 2>/dev/null || echo "")

if [[ -n "$OUTPUT_TEXT" ]]; then
  # score 패턴: "score: 0.847" / "accuracy: 92.3" / "loss: 0.123"
  SCORE=$(echo "$OUTPUT_TEXT" | grep -oiP '(?:score|accuracy|metric|f1|auc|map|bleu|rouge)\s*[:=]\s*[\d.]+' | tail -1 | grep -oP '[\d.]+$' || true)
  if [[ -n "$SCORE" ]]; then
    SCORE_UPDATE="\"current_score\": $SCORE,"
  fi

  # rank 패턴: "rank: 42" / "position: 15"
  RANK=$(echo "$OUTPUT_TEXT" | grep -oiP '(?:rank|position|place)\s*[:=]\s*\d+' | tail -1 | grep -oP '\d+$' || true)
  if [[ -n "$RANK" ]]; then
    RANK_UPDATE="\"current_rank\": $RANK,"
  fi

  # 명령 출력 요약 (첫 200자)
  SUMMARY=$(echo "$OUTPUT_TEXT" | head -5 | tr '\n' ' ' | cut -c1-200)
  if [[ -n "$SUMMARY" ]]; then
    NOTE="$NOTE | $SUMMARY"
  fi
fi

# 칸반 서버에 competition metadata 업데이트 (비동기, 1초 타임아웃)
# 실패해도 에이전트 작업 차단 안 함
{
  # 1) Competition metadata 업데이트
  ESCAPED_NOTE=$(echo "$NOTE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo "\"$NOTE\"")

  curl -s -m 1 -X PUT "$KANBAN_URL/api/competitions/metadata" \
    -H "Content-Type: application/json" \
    -d "{
      \"project_group\": \"$PROJECT_GROUP\",
      \"agent_id\": \"competition-hook\",
      \"fields\": {
        $SCORE_UPDATE
        $RANK_UPDATE
        \"status_notes\": $ESCAPED_NOTE
      }
    }" > /dev/null 2>&1

  # 2) 활성 티켓이 있으면 progress_note 업데이트
  if [[ -f "$ACTIVE_TICKET_FILE" ]]; then
    TICKET_ID=$(cat "$ACTIVE_TICKET_FILE" 2>/dev/null | tr -d '[:space:]')
    if [[ -n "$TICKET_ID" ]]; then
      curl -s -m 1 -X PUT "$KANBAN_URL/api/tickets/$TICKET_ID/progress" \
        -H "Content-Type: application/json" \
        -d "{\"note\": $ESCAPED_NOTE}" > /dev/null 2>&1
    fi
  fi

  # 3) competition_history 이벤트 기록
  curl -s -m 1 -X POST "$KANBAN_URL/api/competitions/history" \
    -H "Content-Type: application/json" \
    -d "{
      \"competition\": \"$PROJECT_GROUP\",
      \"event_type\": \"$EVENT_TYPE\",
      \"title\": \"$EVENT_TYPE: $(echo "$COMMAND" | cut -c1-80)\",
      \"detail\": $ESCAPED_NOTE
    }" > /dev/null 2>&1

} &

# 백그라운드로 실행 후 즉시 종료 (에이전트 차단 방지)
exit 0
