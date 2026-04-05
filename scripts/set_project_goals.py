#!/usr/bin/env python3
"""
프로젝트 페이지 최종 목표 설정 CLI 스크립트
- LINKO 팀 (없으면 자동 생성)
- E-COMMERCE-AI 팀
각 팀에 '프로젝트 페이지 최종 목표 설정' 티켓을 강제 생성합니다.

사용법:
  python3 scripts/set_project_goals.py
  python3 scripts/set_project_goals.py --host http://localhost:5555
  python3 scripts/set_project_goals.py --dry-run
"""

import argparse
import json
import logging
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime


# ─── 로깅 설정 ───────────────────────────────────────────────
def setup_logging(verbose: bool = False) -> logging.Logger:
    level = logging.DEBUG if verbose else logging.INFO
    fmt = "%(asctime)s [%(levelname)s] %(message)s"
    logging.basicConfig(level=level, format=fmt, stream=sys.stdout)
    return logging.getLogger("set_project_goals")


# ─── URL 유효성 검사 ─────────────────────────────────────────
def validate_host(host: str) -> None:
    """host URL이 허용된 형식인지 검사. 허용: http/https 스키마만."""
    try:
        parsed = urllib.parse.urlparse(host)
    except Exception as e:
        raise ValueError(f"URL 파싱 오류: {host!r}: {e}") from e
    if parsed.scheme not in ("http", "https"):
        raise ValueError(
            f"허용되지 않는 URL 스키마: {parsed.scheme!r}. http 또는 https만 사용 가능합니다."
        )
    if not parsed.netloc:
        raise ValueError(f"유효하지 않은 host URL: {host!r} (netloc 없음)")


# ─── HTTP 헬퍼 ───────────────────────────────────────────────
def api_request(host: str, method: str, path: str, body: dict | None = None) -> dict:
    """HTTP 요청 헬퍼. 에러 시 예외 발생."""
    url = f"{host}{path}"
    data = json.dumps(body).encode() if body else None
    headers = {"Content-Type": "application/json"}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        raise RuntimeError(f"HTTP {e.code} {method} {path}: {raw}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"연결 실패 {url}: {e.reason}") from e


# ─── 팀 조회/생성 ────────────────────────────────────────────
def get_or_create_team(host: str, project_group: str, name: str, description: str, log: logging.Logger) -> str:
    """project_group으로 팀을 찾거나 없으면 생성 후 team_id 반환."""
    data = api_request(host, "GET", "/api/teams")
    teams = data.get("teams", [])

    for t in teams:
        if t.get("project_group", "").upper() == project_group.upper():
            log.info("기존 팀 발견: %s (team_id=%s)", t["name"], t["team_id"])
            return t["team_id"]

    log.info("팀 없음 — 신규 생성: project_group=%s", project_group)
    result = api_request(host, "POST", "/api/teams", {
        "name": name,
        "description": description,
        "project_group": project_group,
        "leader_agent": "orchestrator",
    })
    if not result.get("ok"):
        raise RuntimeError(f"팀 생성 실패: {result}")
    team_id = result.get("team", {}).get("team_id") or result.get("team_id")
    log.info("팀 생성 완료: team_id=%s", team_id)
    return team_id


# ─── 티켓 생성 ───────────────────────────────────────────────
def create_goal_ticket(
    host: str,
    team_id: str,
    project_label: str,
    log: logging.Logger,
    dry_run: bool = False,
) -> str | None:
    """팀에 '프로젝트 페이지 최종 목표 설정' 티켓 생성."""
    title = f"[{project_label}] 프로젝트 페이지 최종 목표 설정"

    # 팀별 구체적 KPI 정의 (숫자/빈도 포함)
    kpi_blocks: dict[str, str] = {
        "E-COMMERCE-AI": (
            "## E-COMMERCE-AI 프로젝트 최종 목표\n\n"
            "### 비전\n"
            "AI 기반 개인화 추천으로 전환율을 높이고, 운영 비용을 절감하는 스마트 커머스 플랫폼 구축\n\n"
            "### 핵심 목표 (OKR)\n"
            "- **O1**: 상품 추천 정확도 향상\n"
            "  - KR1: 추천 클릭률(CTR) ≥ 12% (현재 기준선 측정 후 8주 내 달성)\n"
            "  - KR2: 추천 기반 구매전환율 ≥ 5% (A/B 테스트 4주 이상 운영)\n"
            "- **O2**: 검색 품질 개선\n"
            "  - KR3: 검색 후 구매까지 평균 클릭 수 ≤ 3회 (UX 세션 분석, 매주 측정)\n"
            "  - KR4: 검색 결과 무응답률(Zero-result) ≤ 2% (일별 로그 집계)\n"
            "- **O3**: 운영 자동화\n"
            "  - KR5: 상품 등록 처리 시간 ≤ 30초/건 (배치 처리 기준, 스프린트마다 측정)\n"
            "  - KR6: 재고 오차율 ≤ 0.5% (월 1회 실재고 대비 시스템 수치 비교)\n\n"
            "### 완료 기준 (Definition of Done)\n"
            "- 모든 KPI가 목표치를 2주 연속 충족\n"
            "- 부하 테스트: TPS ≥ 500, p99 응답시간 ≤ 200ms\n"
            "- 보안 취약점 Critical/High 0건 (OWASP 스캔)\n\n"
            "### 주요 마일스톤\n"
            "| 주차 | 마일스톤 |\n"
            "|------|----------|\n"
            "| W2   | 추천 엔진 MVP 배포 + 기준선 KPI 측정 시작 |\n"
            "| W4   | A/B 테스트 시작 (추천 CTR/전환율) |\n"
            "| W6   | 검색 Zero-result 자동 알림 파이프라인 가동 |\n"
            "| W8   | 전체 KPI 목표치 달성 검증 + 최종 보고 |\n\n"
            "### 추적 방법\n"
            "- 추천 CTR/전환율: GA4 이벤트 + 서버 로그 (일별 자동 집계)\n"
            "- 검색 품질: 검색 로그 → Elasticsearch 집계 쿼리 (매일 00:00 UTC 배치)\n"
            "- 재고 오차율: ERP 연동 대사 스크립트 (매월 말 실행)\n"
            "- 성능 지표: k6 부하 테스트 스크립트 CI 연동 (PR 머지마다 자동 실행)\n\n"
            f"생성일시: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        ),
        "LINKO": (
            "## LINKO 프로젝트 최종 목표\n\n"
            "### 비전\n"
            "링크 공유·큐레이션 플랫폼으로 콘텐츠 발견성을 높이고 사용자 재방문을 극대화\n\n"
            "### 핵심 목표 (OKR)\n"
            "- **O1**: 사용자 참여도 향상\n"
            "  - KR1: DAU/MAU 비율 ≥ 25% (매일 측정, 4주 평균)\n"
            "  - KR2: 링크 저장 후 48시간 내 재방문율 ≥ 40% (코호트 분석, 주별)\n"
            "- **O2**: 콘텐츠 품질 향상\n"
            "  - KR3: 큐레이션 정확도 평점 ≥ 4.0/5.0 (월 1회 사용자 설문, n≥200)\n"
            "  - KR4: 링크 중복 제거율 ≥ 95% (URL 정규화 처리, 일별 집계)\n"
            "- **O3**: 성능 안정성\n"
            "  - KR5: API 응답시간 p95 ≤ 150ms (매 배포 후 5분 모니터링)\n"
            "  - KR6: 월간 가용성 ≥ 99.5% (Uptime Robot 기준)\n\n"
            "### 완료 기준 (Definition of Done)\n"
            "- DAU/MAU 25% 이상 4주 연속 유지\n"
            "- p95 응답시간 150ms 이하 (실서버 기준)\n"
            "- 자동화 테스트 커버리지 ≥ 80%\n\n"
            "### 주요 마일스톤\n"
            "| 주차 | 마일스톤 |\n"
            "|------|----------|\n"
            "| W2   | URL 정규화 + 중복 제거 파이프라인 배포 |\n"
            "| W4   | 재방문 코호트 분석 대시보드 오픈 |\n"
            "| W6   | 큐레이션 추천 알고리즘 v1 배포 |\n"
            "| W8   | 전체 KPI 목표치 달성 검증 + 최종 보고 |\n\n"
            "### 추적 방법\n"
            "- DAU/MAU: Mixpanel 자동 집계 (일별)\n"
            "- 재방문율: 서버 세션 로그 코호트 쿼리 (주별 배치)\n"
            "- 큐레이션 평점: 인앱 설문 팝업 (월 1회, 트리거: 10회 방문 이상)\n"
            "- 성능: Grafana 대시보드 + PagerDuty 알림 (p95 > 200ms 시 즉시 알림)\n\n"
            f"생성일시: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        ),
    }

    description = kpi_blocks.get(project_label, (
        f"{project_label} 프로젝트의 최종 목표를 프로젝트 페이지에 명시합니다.\n\n"
        "- 프로젝트 비전 및 핵심 목표 (OKR) 정의\n"
        "- 완료 기준(Definition of Done) 작성\n"
        "- 주요 마일스톤 및 일정 설정\n"
        "- 성공 지표(KPI) 등록\n"
        f"\n생성일시: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    ))
    payload = {
        "title": title,
        "description": description,
        "priority": "High",
        "type": "task",
    }
    log.info("[%s] 티켓 생성 시도: %s", project_label, title)
    if dry_run:
        log.info("[DRY-RUN] 실제 생성 생략. payload=%s", json.dumps(payload, ensure_ascii=False))
        return "DRY-RUN"

    result = api_request(host, "POST", f"/api/teams/{team_id}/tickets", payload)
    if not result.get("ok"):
        raise RuntimeError(f"티켓 생성 실패 (team_id={team_id}): {result}")
    ticket_id = result.get("ticket", {}).get("ticket_id") or result.get("ticket_id")
    log.info("[%s] 티켓 생성 완료: ticket_id=%s", project_label, ticket_id)
    return ticket_id


# ─── 팀별 설정 ───────────────────────────────────────────────
TEAM_CONFIGS = [
    {
        "project_group": "LINKO",
        "name": "LINKO 프로젝트 목표 설정",
        "description": "LINKO 서비스의 프로젝트 페이지 최종 목표 수립",
        "label": "LINKO",
    },
    {
        "project_group": "E-COMMERCE-AI",
        "name": "E-COMMERCE-AI 프로젝트 목표 설정",
        "description": "E-COMMERCE-AI 서비스의 프로젝트 페이지 최종 목표 수립",
        "label": "E-COMMERCE-AI",
    },
]


# ─── 메인 ────────────────────────────────────────────────────
def main() -> int:
    parser = argparse.ArgumentParser(description="프로젝트 페이지 최종 목표 설정 티켓 생성")
    parser.add_argument("--host", default="http://localhost:5555", help="칸반 서버 주소")
    parser.add_argument("--dry-run", action="store_true", help="실제 변경 없이 동작 확인")
    parser.add_argument("-v", "--verbose", action="store_true", help="디버그 로그 출력")
    args = parser.parse_args()

    log = setup_logging(args.verbose)
    log.info("=== 프로젝트 목표 설정 스크립트 시작 ===")
    log.info("서버: %s | dry-run: %s", args.host, args.dry_run)

    try:
        validate_host(args.host)
    except ValueError as e:
        log.error("잘못된 서버 주소: %s", e)
        return 2

    results = []
    exit_code = 0

    for cfg in TEAM_CONFIGS:
        label = cfg["label"]
        log.info("--- [%s] 처리 시작 ---", label)
        try:
            team_id = get_or_create_team(
                host=args.host,
                project_group=cfg["project_group"],
                name=cfg["name"],
                description=cfg["description"],
                log=log,
            )
            ticket_id = create_goal_ticket(
                host=args.host,
                team_id=team_id,
                project_label=label,
                log=log,
                dry_run=args.dry_run,
            )
            results.append({"label": label, "team_id": team_id, "ticket_id": ticket_id, "status": "ok"})
            log.info("[%s] 완료 ✓ team_id=%s, ticket_id=%s", label, team_id, ticket_id)
        except RuntimeError as e:
            log.error("[%s] 실패: %s", label, e)
            results.append({"label": label, "status": "error", "error": str(e)})
            exit_code = 1

    log.info("=== 처리 결과 ===")
    for r in results:
        status_icon = "✓" if r["status"] == "ok" else "✗"
        log.info("%s [%s] team_id=%s ticket_id=%s",
                 status_icon, r["label"],
                 r.get("team_id", "-"), r.get("ticket_id", "-"))
        if r["status"] == "error":
            log.error("  오류: %s", r["error"])

    log.info("=== 스크립트 종료 (exit_code=%d) ===", exit_code)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
