#!/usr/bin/env python3
"""
CLI Worker v2.0 — 칸반 서버의 승인된 작업을 폴링하여 Claude Code CLI 실행.

v2.0 변경:
  - 잡별 모델 선택 지원 (model 필드)
  - 실행 중 실시간 로그 스트리밍 (서버에 PUT)
  - 실행 중 킬 체크 (서버에서 cancelled 상태 감지 → 프로세스 종료)

사용법:
    python cli-worker.py                    # 기본 (localhost:5555, 10초 폴링)
    python cli-worker.py --server http://192.168.1.100:5555
    python cli-worker.py --interval 5       # 5초마다 폴링
    python cli-worker.py --once             # 1회만 실행 후 종료
    python cli-worker.py --token XXXX       # 인증 토큰
"""

import argparse
import json
import os
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime
from urllib.request import Request, urlopen
from urllib.error import URLError

WORKER_ID = f"worker-{uuid.uuid4().hex[:6]}"
VERSION = "2.0.0"
DEFAULT_MODEL = "claude-sonnet-4-20250514"


def log(msg, level="INFO"):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] [{level}] {msg}", flush=True)


def api_call(server, path, method="GET", body=None, token=None):
    """서버 API 호출."""
    url = f"{server}{path}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    data = json.dumps(body).encode() if body else None
    req = Request(url, data=data, headers=headers, method=method)

    try:
        with urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except URLError as e:
        return {"ok": False, "error": str(e)}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def find_claude_cli():
    """Claude CLI 경로 탐지."""
    candidates = ["claude"]
    if os.name != "nt":
        candidates += [
            "/usr/bin/claude",
            os.path.expanduser("~/.npm-global/bin/claude"),
            "/usr/local/bin/claude",
            os.path.expanduser("~/.local/bin/claude"),
        ]
    for c in candidates:
        try:
            result = subprocess.run([c, "--version"], capture_output=True, timeout=5)
            if result.returncode == 0:
                ver = result.stdout.decode().strip()
                log(f"Claude CLI 발견: {c} ({ver})")
                return c
        except Exception:
            continue
    return None


def stream_log(server, token, job_id, line):
    """실시간 로그 한 줄을 서버에 전송."""
    try:
        api_call(server, f"/api/cli/jobs/{job_id}/log", method="PUT",
                 body={"log": line + "\n", "append": True}, token=token)
    except Exception:
        pass


def check_killed(server, token, job_id):
    """서버에서 작업이 cancelled 상태인지 확인."""
    try:
        resp = api_call(server, f"/api/cli/jobs/{job_id}/log", token=token)
        return resp.get("status") == "cancelled"
    except Exception:
        return False


def execute_job(job, claude_cli, server, token):
    """단일 작업 실행 — 실시간 로그 + 킬 체크."""
    job_id = job["job_id"]
    project_path = job["project_path"]
    prompt = job["prompt"]
    allowed_tools = job.get("allowed_tools", "Read,Write,Edit,Bash,Glob,Grep")
    max_turns = job.get("max_turns", 30)
    timeout_sec = job.get("timeout_sec", 300)
    model = job.get("model", "") or DEFAULT_MODEL

    if not os.path.isdir(project_path):
        return False, "", f"프로젝트 경로 없음: {project_path}"

    # Claude CLI 명령 구성
    cmd = [
        claude_cli, "-p", prompt,
        "--model", model,
        "--max-turns", str(max_turns),
        "--permission-mode", "bypassPermissions",
        "--output-format", "json",
    ]

    # allowedTools로 범위 제한
    if allowed_tools:
        tools_str = ",".join(t.strip() for t in allowed_tools.split(",") if t.strip())
        if tools_str:
            cmd.extend(["--allowedTools", tools_str])

    log(f"실행: {job_id} @ {project_path}")
    log(f"모델: {model}")
    log(f"프롬프트: {prompt[:100]}...")

    stream_log(server, token, job_id, f"[시작] 모델: {model}")
    stream_log(server, token, job_id, f"[시작] 프로젝트: {project_path}")
    stream_log(server, token, job_id, f"[시작] 프롬프트: {prompt[:200]}")

    try:
        proc = subprocess.Popen(
            cmd, cwd=project_path,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            env={**os.environ, "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
                 "KANBAN_TICKET_ID": job.get("ticket_id") or job_id}
        )

        output_lines = []
        killed = False
        start_time = time.time()
        log_counter = 0

        # 실시간 stdout 읽기 + 로그 스트리밍
        for raw_line in iter(proc.stdout.readline, b""):
            line = raw_line.decode("utf-8", errors="replace").rstrip()
            output_lines.append(line)

            # 5줄마다 서버에 로그 전송 (과도한 API 호출 방지)
            log_counter += 1
            if log_counter % 5 == 0 or "error" in line.lower() or "completed" in line.lower():
                stream_log(server, token, job_id, line)

            # 30초마다 킬 체크
            elapsed = time.time() - start_time
            if int(elapsed) % 30 == 0 and int(elapsed) > 0:
                if check_killed(server, token, job_id):
                    log(f"킬 요청 감지: {job_id}", "WARN")
                    proc.kill()
                    killed = True
                    break

            # 타임아웃 체크
            if elapsed > timeout_sec:
                proc.kill()
                stream_log(server, token, job_id, f"[타임아웃] {timeout_sec}초 초과")
                return False, "\n".join(output_lines), f"타임아웃 ({timeout_sec}s)"

        proc.wait(timeout=10)
        output = "\n".join(output_lines)

        if killed:
            stream_log(server, token, job_id, "[중단] 사용자 요청에 의해 중단됨")
            return False, output, "사용자 중단"

        # max turns 도달은 부분 성공으로 처리
        max_turns_reached = "max turns" in output.lower() or "Reached max turns" in output

        if proc.returncode == 0 or max_turns_reached:
            log(f"완료: {job_id} ({len(output)}자){' (max turns)' if max_turns_reached else ''}")
            stream_log(server, token, job_id,
                       f"[완료] {len(output)}자{' (max turns 도달)' if max_turns_reached else ''}")

            # git commit (선택적)
            try:
                subprocess.run(["git", "add", "-A"], cwd=project_path, timeout=10, capture_output=True)
                subprocess.run(
                    ["git", "commit", "-m", f"feat: [cli-worker] {job.get('ticket_id', job_id)} — {prompt[:50]}"],
                    cwd=project_path, timeout=10, capture_output=True
                )
                log(f"Git 커밋 완료: {job_id}")
                stream_log(server, token, job_id, "[Git] 자동 커밋 완료")
            except Exception:
                pass

            return True, output, ""
        else:
            log(f"실패 (exit {proc.returncode}): {job_id}", "ERROR")
            stream_log(server, token, job_id, f"[실패] exit code {proc.returncode}")
            return False, output, f"exit code {proc.returncode}"

    except subprocess.TimeoutExpired:
        try:
            proc.kill()
        except Exception:
            pass
        log(f"타임아웃: {job_id} ({timeout_sec}s)", "ERROR")
        stream_log(server, token, job_id, f"[타임아웃] {timeout_sec}초 초과")
        return False, "", f"타임아웃 ({timeout_sec}s)"
    except Exception as e:
        log(f"예외: {job_id} — {e}", "ERROR")
        stream_log(server, token, job_id, f"[오류] {e}")
        return False, "", str(e)


def poll_and_execute(server, token, claude_cli):
    """승인된 작업 1개를 가져와서 실행."""
    resp = api_call(server, f"/api/cli/jobs/next?worker_id={WORKER_ID}", token=token)

    if not resp.get("ok"):
        if "error" in resp:
            log(f"API 오류: {resp['error']}", "WARN")
        return False

    job = resp.get("job")
    if not job:
        return False

    job_id = job["job_id"]
    model = job.get("model", "") or DEFAULT_MODEL
    log(f"━━━ 작업 시작: {job_id} ━━━")
    log(f"  티켓: {job.get('ticket_id', '-')}")
    log(f"  프로젝트: {job.get('project_name', '-')} ({job['project_path']})")
    log(f"  모델: {model}")

    # 실행
    success, output, error = execute_job(job, claude_cli, server, token)

    # JSON 출력에서 토큰 사용량 파싱
    input_tokens = 0
    output_tokens = 0
    try:
        import re
        # --output-format json은 마지막에 JSON 객체 출력
        json_match = re.search(r'\{[^{}]*"input_tokens"\s*:\s*(\d+)[^{}]*"output_tokens"\s*:\s*(\d+)[^{}]*\}', output)
        if json_match:
            input_tokens = int(json_match.group(1))
            output_tokens = int(json_match.group(2))
        else:
            # 전체 출력을 JSON 파싱 시도
            for line in reversed(output.split("\n")):
                line = line.strip()
                if line.startswith("{") and "input_tokens" in line:
                    try:
                        jdata = json.loads(line)
                        input_tokens = jdata.get("input_tokens", 0) or jdata.get("usage", {}).get("input_tokens", 0)
                        output_tokens = jdata.get("output_tokens", 0) or jdata.get("usage", {}).get("output_tokens", 0)
                        break
                    except Exception:
                        pass
    except Exception as e:
        log(f"토큰 파싱 실패: {e}", "WARN")

    # 결과 보고
    result_resp = api_call(server, f"/api/cli/jobs/{job_id}/result", method="PUT", body={
        "success": success,
        "output": output[:10000],
        "error": error,
    }, token=token)

    # 토큰 사용량 보고
    if input_tokens > 0 or output_tokens > 0:
        usage_resp = api_call(server, "/api/usage/report", method="POST", body={
            "team_id": job.get("team_id", ""),
            "ticket_id": job.get("ticket_id", ""),
            "agent_id": f"cli-worker-{WORKER_ID}",
            "model": model,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
        }, token=token)
        log(f"토큰 보고: in={input_tokens:,} out={output_tokens:,} (${(input_tokens*15+output_tokens*75)/1e6:.4f})")
        stream_log(server, token, job_id, f"[토큰] in:{input_tokens:,} out:{output_tokens:,}")
    else:
        log(f"토큰 정보 없음 (출력 {len(output)}자)")

    status = "완료" if success else "실패"
    log(f"━━━ 작업 {status}: {job_id} ━━━")

    if not result_resp.get("ok"):
        log(f"결과 보고 실패: {result_resp.get('error', '?')}", "WARN")

    return True


def main():
    parser = argparse.ArgumentParser(description="CLI Worker v2.0 — 칸반 서버 연동 Claude Code 실행기")
    parser.add_argument("--server", default="http://localhost:5555", help="칸반 서버 URL")
    parser.add_argument("--token", default=None, help="인증 토큰")
    parser.add_argument("--interval", type=int, default=10, help="폴링 간격 (초)")
    parser.add_argument("--once", action="store_true", help="1회만 실행")
    args = parser.parse_args()

    log(f"═══ CLI Worker {VERSION} 시작 ═══")
    log(f"  Worker ID: {WORKER_ID}")
    log(f"  서버: {args.server}")
    log(f"  폴링 간격: {args.interval}초")
    log(f"  기본 모델: {DEFAULT_MODEL}")

    # Claude CLI 탐지
    claude_cli = find_claude_cli()
    if not claude_cli:
        log("Claude CLI를 찾을 수 없습니다. npm install -g @anthropic-ai/claude-code", "FATAL")
        sys.exit(1)

    # 서버 연결 확인
    resp = api_call(args.server, "/api/teams", token=args.token)
    if resp.get("ok") is not False and "teams" in resp:
        log(f"서버 연결 확인: {len(resp.get('teams', []))}개 팀")
    else:
        log(f"서버 연결 실패: {resp.get('error', '응답 없음')}", "WARN")
        if not args.once:
            log("서버 연결 대기 중...")

    if args.once:
        executed = poll_and_execute(args.server, args.token, claude_cli)
        if not executed:
            log("실행할 작업이 없습니다.")
        return

    # 상주 모드
    log("상주 모드 시작 — Ctrl+C로 종료")
    idle_count = 0
    while True:
        try:
            executed = poll_and_execute(args.server, args.token, claude_cli)
            if executed:
                idle_count = 0
                time.sleep(2)
            else:
                idle_count += 1
                if idle_count % 30 == 0:
                    stats = api_call(args.server, "/api/cli/stats", token=args.token)
                    s = stats.get("stats", {})
                    log(f"대기 중... (pending={s.get('pending',0)} approved={s.get('approved',0)} "
                        f"completed={s.get('completed',0)})")
                time.sleep(args.interval)
        except KeyboardInterrupt:
            log("종료 요청...")
            break
        except Exception as e:
            log(f"루프 오류: {e}", "ERROR")
            time.sleep(args.interval)

    log("═══ CLI Worker 종료 ═══")


if __name__ == "__main__":
    main()
