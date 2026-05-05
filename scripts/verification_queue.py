#!/usr/bin/env python3
"""
verification_queue.py — 칸반 검증 큐 워커 (stand-alone)

역할:
  1. 모든 활성팀의 Review 상태 티켓 수집 → 우선순위 큐
  2. 동시 N개 병렬 검증 (default 5)
  3. 디바운스: 같은 티켓 5분 내 재검수 금지 (LLM 노이즈 흡수)
  4. 평균 점수 fallback: 최근 1시간 내 평균 ≥ 3.0 → Done 강제
  5. 재 티켓 한도 강제: parent_ticket_id 체인 누적 ≥ 3 이면 신규 발행 차단 + Blocked 에스컬레이션

server.py 미수정 — REST API + 외부 워커.

실행:
  python3 verification_queue.py [--cycle 300] [--workers 5] [--once]

환경변수:
  KANBAN_API     기본 http://localhost:5555
  VQ_DEBOUNCE    디바운스 초 (기본 300)
  VQ_PASS_AVG    평균 통과 점수 (기본 3.0)
  VQ_BLOCK_AVG   Blocked 임계 (기본 2.5)
  VQ_MAX_REWORK  체인 누적 재작업 한도 (기본 3)
  VQ_LOG         로그 파일 경로 (기본 /tmp/verification_queue.log)
"""
import os, sys, time, json, argparse
import urllib.request as ur
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta

API = os.environ.get("KANBAN_API", "http://localhost:5555")
DEBOUNCE = int(os.environ.get("VQ_DEBOUNCE", "300"))
PASS_AVG = float(os.environ.get("VQ_PASS_AVG", "3.0"))
BLOCK_AVG = float(os.environ.get("VQ_BLOCK_AVG", "2.5"))
MAX_REWORK = int(os.environ.get("VQ_MAX_REWORK", "3"))
LOG_PATH = os.environ.get("VQ_LOG", "/tmp/verification_queue.log")

PRIORITY_RANK = {"critical": 0, "Critical": 0, "high": 1, "High": 1,
                 "medium": 2, "Medium": 2, "low": 3, "Low": 3}

# 메모리 점수 누적 (재시작 시 supervisor stats API 로 복원 가능)
_SCORE_MEMO = {}  # ticket_id -> [(datetime, score), ...]
_LAST_REVIEW_AT = {}  # ticket_id -> datetime


def log(msg, level="INFO"):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] [{level}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def call(method, path, data=None, timeout=10):
    body = json.dumps(data).encode() if data is not None else None
    req = ur.Request(
        f"{API}{path}",
        data=body,
        headers={"Content-Type": "application/json"} if body else {},
        method=method,
    )
    try:
        with ur.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": f"HTTP {e.code}", "body": e.read().decode("utf-8", errors="ignore")}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def collect_review_queue():
    """모든 활성팀 Review 티켓 수집 → 우선순위 큐."""
    teams = call("GET", "/api/teams").get("teams", [])
    queue = []
    for t in teams:
        if t.get("status") != "Active":
            continue
        b = call("GET", f"/api/teams/{t['team_id']}/board")
        tickets = b.get("board", b).get("tickets", []) if isinstance(b.get("board", b), dict) else b.get("tickets", [])
        for tk in tickets:
            if tk.get("status") == "Review":
                queue.append(tk)
    queue.sort(key=lambda x: (
        PRIORITY_RANK.get(str(x.get("priority", "low")), 9),
        x.get("created_at", "")
    ))
    return queue


def get_chain_rework_count(ticket_id, max_depth=10):
    """체인 누적 재작업 횟수.
    1) parent_ticket_id 체인 추적 (정식 경로)
    2) title 의 [REWORK]/[재작업 N/3] 패턴 (서버측 supervisor 재작업 발행 결함 워크어라운드)"""
    import re
    r = call("GET", f"/api/tickets/{ticket_id}")
    if not r.get("ok"):
        return 0
    t = r.get("ticket", {})

    # 1. parent_ticket_id 체인
    count = 0
    current = ticket_id
    seen = set()
    for _ in range(max_depth):
        if current in seen:
            break
        seen.add(current)
        rr = call("GET", f"/api/tickets/{current}")
        if not rr.get("ok"):
            break
        tt = rr.get("ticket", {})
        parent = tt.get("parent_ticket_id")
        if not parent:
            break
        count += 1
        current = parent
    if count > 0:
        return count

    # 2. title 패턴 폴백
    title = t.get("title", "")
    m = re.search(r"\[재작업\s*(\d+)\s*/\s*\d+\]", title)
    if m:
        return int(m.group(1))
    if "[REWORK]" in title or "[재작업]" in title:
        return 1  # 1차 재작업으로 가정

    return 0


def get_recent_scores(ticket_id, hours=1):
    """메모리 누적 점수 + supervisor stats API 백필."""
    cutoff = datetime.now() - timedelta(hours=hours)

    # 1) 메모리에서 우선
    mem = _SCORE_MEMO.get(ticket_id, [])
    scores = [(ts, s) for ts, s in mem if ts >= cutoff]

    # 2) supervisor stats recent 에서 백필
    if not scores:
        r = call("GET", "/api/supervisor/review/stats")
        for rec in r.get("recent", []):
            if rec.get("ticket_id") == ticket_id and rec.get("score") is not None:
                try:
                    ts = datetime.strptime(rec["created_at"], "%Y-%m-%d %H:%M:%S")
                    if ts >= cutoff:
                        scores.append((ts, int(rec["score"])))
                except Exception:
                    pass

    last = _LAST_REVIEW_AT.get(ticket_id)
    if scores:
        latest = max(ts for ts, _ in scores)
        if last is None or latest > last:
            last = latest

    return scores, last


def record_score(ticket_id, score):
    """검수 결과 누적."""
    now = datetime.now()
    _SCORE_MEMO.setdefault(ticket_id, []).append((now, int(score)))
    _LAST_REVIEW_AT[ticket_id] = now
    # 1시간 이전 데이터 정리
    cutoff = now - timedelta(hours=1)
    _SCORE_MEMO[ticket_id] = [(t, s) for t, s in _SCORE_MEMO[ticket_id] if t >= cutoff]


def parse_supervisor_score(actions):
    """actions_executed 리스트에서 점수 추출.
    예: ['✅ T-XX: 4점 통과 → Done (산출물 1개)', '🔄 T-YY: 3점 재작업 (1/3회) → InProgress']"""
    import re
    for a in actions or []:
        m = re.search(r"(\d)\s*점", a)
        if m:
            try:
                return int(m.group(1))
            except Exception:
                pass
    return None


def has_artifacts(ticket_id):
    r = call("GET", f"/api/tickets/{ticket_id}/artifacts")
    arts = r.get("artifacts", [])
    return len(arts) > 0


def verify_one(ticket):
    """단건 검증 — 디바운스 → 평균 점수 → 결정."""
    tid = ticket["ticket_id"]
    title = ticket.get("title", "")[:50]

    # 1. 디바운스
    scores, last_at = get_recent_scores(tid, hours=1)
    if last_at is not None:
        elapsed = (datetime.now() - last_at).total_seconds()
        if elapsed < DEBOUNCE:
            log(f"[{tid}] 디바운스 ({elapsed:.0f}s < {DEBOUNCE}s) skip", "DEBOUNCE")
            return {"ticket_id": tid, "action": "debounce_skip"}

    # 2. 재 티켓 체인 검사
    chain = get_chain_rework_count(tid)
    if chain >= MAX_REWORK:
        log(f"[{tid}] 체인 누적 재작업 {chain}회 ≥ {MAX_REWORK} → Blocked 에스컬레이션", "BLOCK")
        call("PUT", f"/api/tickets/{tid}/patch", {
            "status": "Blocked",
            "progress_note": f"체인 재작업 {chain}회 한도 초과 — 사람 개입 필요. 신규 재 티켓 발행 차단됨."
        })
        return {"ticket_id": tid, "action": "blocked_chain", "chain": chain}

    # 3. supervisor 검수 1회 호출 (점수 추가)
    r = call("POST", "/api/supervisor/review", {"ticket_id": tid})
    actions = r.get('actions_executed', [])
    log(f"[{tid}] supervisor 검수: {actions}", "REVIEW")

    # actions 에서 점수 추출 → 메모리 누적
    extracted = parse_supervisor_score(actions)
    if extracted is not None:
        record_score(tid, extracted)

    # 4. 누적 평균 재계산 → fallback 결정
    time.sleep(0.5)  # DB 반영 대기
    scores, _ = get_recent_scores(tid, hours=1)
    arts_ok = has_artifacts(tid)

    if scores:
        avg = sum(s for _, s in scores) / len(scores)
        log(f"[{tid}] 누적 점수 {[s for _,s in scores]} 평균 {avg:.2f} (산출물={arts_ok})", "SCORE")
    else:
        avg = 0
        log(f"[{tid}] 점수 추출 실패 — supervisor 응답 직접 의존", "WARN")

    # 5. fallback 정책
    # 평균 ≥ PASS_AVG AND 산출물 1개 이상 → Done 강제
    if avg >= PASS_AVG and arts_ok:
        cur = call("GET", f"/api/tickets/{tid}").get("ticket", {})
        if cur.get("status") != "Done":
            call("PUT", f"/api/tickets/{tid}/patch", {
                "status": "Done",
                "progress_note": f"검증 큐 통과 (평균 {avg:.2f}/5, {len(scores)}회 누적). 산출물 {1 if arts_ok else 0}+"
            })
            log(f"[{tid}] 평균 {avg:.2f} ≥ {PASS_AVG} → Done 강제", "PASS")
            return {"ticket_id": tid, "action": "force_done", "avg": avg}

    # 평균 < BLOCK_AVG AND 시도 ≥ MAX_REWORK → Blocked
    if scores and avg < BLOCK_AVG and len(scores) >= MAX_REWORK:
        call("PUT", f"/api/tickets/{tid}/patch", {
            "status": "Blocked",
            "progress_note": f"검증 큐 차단 (평균 {avg:.2f}/5, {len(scores)}회 누적 미달). 사람 개입 필요."
        })
        log(f"[{tid}] 평균 {avg:.2f} < {BLOCK_AVG}, {len(scores)}회 → Blocked", "BLOCK")
        return {"ticket_id": tid, "action": "blocked_avg", "avg": avg}

    # 그 외: supervisor 결정 그대로 유지
    return {"ticket_id": tid, "action": "passthrough", "avg": avg}


def cycle_once(workers=5):
    queue = collect_review_queue()
    log(f"큐 수집: {len(queue)} 티켓 (Review 상태)")
    if not queue:
        return 0

    results = []
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futures = {ex.submit(verify_one, tk): tk["ticket_id"] for tk in queue[:30]}
        for f in as_completed(futures):
            try:
                results.append(f.result())
            except Exception as e:
                log(f"[{futures[f]}] 워커 예외: {e}", "ERROR")

    summary = {}
    for r in results:
        a = r.get("action", "unknown")
        summary[a] = summary.get(a, 0) + 1
    log(f"사이클 완료: {summary}")
    return len(results)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cycle", type=int, default=300, help="cycle interval seconds")
    ap.add_argument("--workers", type=int, default=5, help="parallel workers")
    ap.add_argument("--once", action="store_true", help="run once and exit")
    args = ap.parse_args()

    log(f"verification_queue 시작 — workers={args.workers} cycle={args.cycle}s "
        f"debounce={DEBOUNCE}s pass_avg={PASS_AVG} block_avg={BLOCK_AVG} max_rework={MAX_REWORK}")

    if args.once:
        cycle_once(args.workers)
        return

    while True:
        try:
            cycle_once(args.workers)
        except Exception as e:
            log(f"사이클 예외: {e}", "ERROR")
        time.sleep(args.cycle)


if __name__ == "__main__":
    main()
