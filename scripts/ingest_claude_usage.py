#!/usr/bin/env python3
"""
실측 토큰 사용량 ingest — Claude Code 세션 트랜스크립트(~/.claude/projects/*/*.jsonl)에서
각 assistant 메시지의 실제 usage(input/output/cache_creation/cache_read)를
일자·모델·프로젝트별로 집계해 kanban DB(claude_usage_daily)에 적재한다.

- 결제 역산 추정값이 아닌 "실제 처리 토큰"이 대시보드에 반영되도록 하는 파이프라인.
- 중복 카운트 방지: message.id 로 전역 dedup (재시도/중복 라인 제거 — ccusage 방식).
- 멱등: 매 실행마다 전체 재집계 후 테이블 교체.

실행: python3 scripts/ingest_claude_usage.py [--db PATH] [--projects DIR]
"""
import argparse, glob, json, os, sqlite3, sys, time

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(os.path.dirname(__file__), "..", "agent_teams.db"))
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    args = ap.parse_args()

    db_path = os.path.abspath(args.db)
    # 재귀: 메인 세션 + subagents/ 하위 트랜스크립트까지 모두 포함 (서브에이전트 토큰 누락 방지)
    files = sorted(glob.glob(os.path.join(args.projects, "**", "*.jsonl"), recursive=True))
    if not files:
        print("트랜스크립트 없음:", args.projects); return 1

    # (day, model, project) -> [in, out, cc, cr, msgs]
    agg = {}
    seen = set()           # 전역 dedup 키 (message.id)
    dup = 0; parsed = 0; t0 = time.time()

    for fp in files:
        # 프로젝트 = projects/ 바로 아래 폴더 (subagents 등 하위경로 무시)
        rel = os.path.relpath(fp, args.projects)
        project = rel.split(os.sep)[0]
        # 프로젝트 폴더명 정리: -home-u2dia-github-LINKO -> LINKO
        proj = project.replace("-home-u2dia-github-", "").replace("-home-u2dia-", "").strip("-") or project
        try:
            with open(fp, "r", errors="replace") as f:
                for line in f:
                    if '"usage"' not in line:
                        continue
                    try:
                        o = json.loads(line)
                    except Exception:
                        continue
                    if o.get("type") != "assistant":
                        continue
                    msg = o.get("message", {})
                    u = msg.get("usage") or {}
                    if not u:
                        continue
                    mid = msg.get("id") or o.get("requestId") or ""
                    if mid:
                        if mid in seen:
                            dup += 1; continue
                        seen.add(mid)
                    model = msg.get("model") or "unknown"
                    if model == "<synthetic>":
                        continue
                    ts = o.get("timestamp") or ""
                    day = ts[:10] if len(ts) >= 10 else "unknown"
                    key = (day, model, proj)
                    a = agg.get(key)
                    if a is None:
                        a = [0, 0, 0, 0, 0]; agg[key] = a
                    a[0] += int(u.get("input_tokens", 0) or 0)
                    a[1] += int(u.get("output_tokens", 0) or 0)
                    a[2] += int(u.get("cache_creation_input_tokens", 0) or 0)
                    a[3] += int(u.get("cache_read_input_tokens", 0) or 0)
                    a[4] += 1
                    parsed += 1
        except Exception:
            continue

    # DB 적재 (멱등: 테이블 비우고 재적재)
    conn = sqlite3.connect(db_path)
    conn.execute("""CREATE TABLE IF NOT EXISTS claude_usage_daily (
        day TEXT NOT NULL, model TEXT NOT NULL, project TEXT NOT NULL,
        input_tokens INTEGER DEFAULT 0, output_tokens INTEGER DEFAULT 0,
        cache_creation_tokens INTEGER DEFAULT 0, cache_read_tokens INTEGER DEFAULT 0,
        message_count INTEGER DEFAULT 0, updated_at TEXT,
        PRIMARY KEY (day, model, project))""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_cud_day ON claude_usage_daily(day)")
    conn.execute("DELETE FROM claude_usage_daily")
    now = time.strftime("%Y-%m-%d %H:%M:%S")
    conn.executemany(
        "INSERT INTO claude_usage_daily(day,model,project,input_tokens,output_tokens,"
        "cache_creation_tokens,cache_read_tokens,message_count,updated_at) "
        "VALUES (?,?,?,?,?,?,?,?,?)",
        [(d, m, p, a[0], a[1], a[2], a[3], a[4], now) for (d, m, p), a in agg.items()])
    conn.commit()

    # 요약
    ti = sum(a[0] for a in agg.values()); to = sum(a[1] for a in agg.values())
    tcc = sum(a[2] for a in agg.values()); tcr = sum(a[3] for a in agg.values())
    B = 1e9
    print(f"파일 {len(files)} · 메시지 {parsed} (중복제거 {dup}) · {time.time()-t0:.1f}s")
    print(f"실측 토큰: input {ti/B:.2f}B · output {to/B:.2f}B · cache_create {tcc/B:.2f}B · cache_read {tcr/B:.2f}B")
    print(f"  유효(in+out+cache_create) = {(ti+to+tcc)/B:.2f}B · 총처리 = {(ti+to+tcc+tcr)/B:.1f}B")
    print(f"  적재행 {len(agg)} → {db_path}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
