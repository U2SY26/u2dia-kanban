#!/usr/bin/env bash
# U2DIA CLI Reverse Hook Poller — v1.0 (2026-04-18)
# 목적: 서버의 cli_jobs 큐를 폴링해서 로컬에서 실제 명령을 실행하고 결과를 리턴.
#       모바일 ↔ 서버 ↔ 데스크톱 Claude Code 왕복 채널의 데스크톱 측 워커.
#
# 사용:
#   ./hooks/cli-poller.sh                       # 기본 포트 5555, 토큰은 환경변수 U2DIA_TOKEN
#   U2DIA_URL=http://remote:5555 ./hooks/cli-poller.sh
#   POLL_INTERVAL=3 ./hooks/cli-poller.sh
#
# systemd user service 설치:
#   cp hooks/cli-poller.service ~/.config/systemd/user/
#   systemctl --user enable --now cli-poller

set -u

: "${U2DIA_URL:=http://localhost:5555}"
: "${U2DIA_TOKEN:=}"
: "${POLL_INTERVAL:=5}"
: "${WORKER_ID:=$(hostname)-$$}"
: "${DEFAULT_CWD:=$HOME}"
: "${LOG_FILE:=/tmp/u2dia-cli-poller.log}"

log() {
  echo "[$(date +'%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

auth_header() {
  if [ -n "$U2DIA_TOKEN" ]; then
    echo "Authorization: Bearer $U2DIA_TOKEN"
  else
    echo "X-Ignore: none"
  fi
}

# 한 번에 한 개의 approved job 을 claim
claim_next() {
  curl -sS -X GET "$U2DIA_URL/api/cli/jobs/next?worker_id=$WORKER_ID" \
    -H "$(auth_header)" -H "Content-Type: application/json" \
    --max-time 10
}

# 결과 전송
report_result() {
  local job_id="$1" status="$2" summary="$3" error="$4"
  # 안전한 JSON 페이로드 생성 (파이썬으로 escaping)
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({
  "status": sys.argv[1],
  "result_summary": sys.argv[2],
  "error": sys.argv[3],
  "worker_id": sys.argv[4],
}))
' "$status" "$summary" "$error" "$WORKER_ID")

  curl -sS -X PUT "$U2DIA_URL/api/cli/jobs/$job_id/result" \
    -H "$(auth_header)" -H "Content-Type: application/json" \
    -d "$payload" --max-time 15 > /dev/null || true
}

# 진행 상황 로그 (live_log 업데이트)
stream_log() {
  local job_id="$1" chunk="$2"
  local payload
  payload=$(python3 -c 'import json,sys; print(json.dumps({"chunk": sys.argv[1]}))' "$chunk")
  curl -sS -X POST "$U2DIA_URL/api/cli/jobs/$job_id/log" \
    -H "$(auth_header)" -H "Content-Type: application/json" \
    -d "$payload" --max-time 5 > /dev/null 2>&1 || true
}

# job 실행
execute_job() {
  local job_json="$1"
  local job_id prompt cwd timeout model allowed
  job_id=$(echo "$job_json"    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("job_id",""))')
  prompt=$(echo "$job_json"    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("prompt",""))')
  cwd=$(echo "$job_json"       | python3 -c 'import sys,json;print(json.load(sys.stdin).get("project_path","") or "")')
  timeout=$(echo "$job_json"   | python3 -c 'import sys,json;print(json.load(sys.stdin).get("timeout_sec",300))')
  model=$(echo "$job_json"     | python3 -c 'import sys,json;print(json.load(sys.stdin).get("model","") or "claude-opus-4-7")')
  allowed=$(echo "$job_json"   | python3 -c 'import sys,json;print(json.load(sys.stdin).get("allowed_tools","Read,Write,Edit,Bash,Glob,Grep"))')

  if [ -z "$job_id" ] || [ -z "$prompt" ]; then
    log "job 포맷 이상 — 스킵"
    return
  fi

  cwd="${cwd:-$DEFAULT_CWD}"
  [ -d "$cwd" ] || cwd="$DEFAULT_CWD"

  log "▶ job $job_id 시작 (cwd=$cwd, model=$model)"
  stream_log "$job_id" "poller: 실행 시작 (worker=$WORKER_ID)"

  local tmp_out
  tmp_out=$(mktemp)
  local exit_code=0

  if command -v claude >/dev/null 2>&1; then
    # Claude Code CLI 로 실행
    (
      cd "$cwd"
      timeout "${timeout}s" claude -p "$prompt" \
        --model "$model" \
        --allowedTools "$allowed" \
        --max-turns 30 \
        2>&1
    ) > "$tmp_out"
    exit_code=$?
  else
    # Claude 미설치 시 단순 Bash 실행 모드
    log "⚠ claude CLI 없음 → bash 실행 모드로 fallback"
    (
      cd "$cwd"
      timeout "${timeout}s" bash -lc "$prompt" 2>&1
    ) > "$tmp_out"
    exit_code=$?
  fi

  local summary
  summary=$(tail -c 4000 "$tmp_out")
  local status="completed"
  local err=""
  if [ $exit_code -ne 0 ]; then
    status="failed"
    err="exit_code=$exit_code"
  fi

  report_result "$job_id" "$status" "$summary" "$err"
  rm -f "$tmp_out"
  log "✓ job $job_id $status (exit=$exit_code, ${#summary} chars)"
}

# 메인 루프
log "U2DIA CLI 리버스 폴러 시작 — worker_id=$WORKER_ID, url=$U2DIA_URL, interval=${POLL_INTERVAL}s"
trap 'log "폴러 종료"; exit 0' INT TERM

while true; do
  response=$(claim_next || echo '')
  if [ -z "$response" ]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  # ok=false 또는 job=null 이면 대기
  ok=$(echo "$response" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("ok",False))' 2>/dev/null || echo "False")
  has_job=$(echo "$response" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("yes" if d.get("job") else "no")' 2>/dev/null || echo "no")

  if [ "$ok" = "True" ] && [ "$has_job" = "yes" ]; then
    job=$(echo "$response" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps(d["job"]))')
    execute_job "$job"
  else
    sleep "$POLL_INTERVAL"
  fi
done
