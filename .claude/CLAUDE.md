
> **[필수] 모든 작업은 칸반보드를 통해야 합니다. 예외 없음.**
>
> ```
> 1. kanban_team_create → 팀 생성
> 2. kanban_member_spawn → 전문 에이전트 스폰 (역할 지정 필수)
> 3. kanban_ticket_create → 티켓 생성
> 4. kanban_ticket_claim → 에이전트 클레임 (역할-티켓 매칭)
> 5. kanban_ticket_progress → progress_note 등록 (필수)
> 6. 작업 수행
> 7. kanban_artifact_create → 산출물 등록 (필수)
> 8. kanban_ticket_status → Review 전환
> 9. Supervisor QA 자동 검수 → Done 또는 rework
> ```
>
> **위반 시**: InProgress 전환 차단(agent_required), Review 차단(artifact_required), Done 차단(review_required)
> **칸반 오프라인 시**: curl REST API로 재시도 3회. 오프라인 핑계로 규칙 무시 = 헌법 위반.

### REST API 치트시트 (MCP 대체용)

```bash
# 팀 생성
curl -X POST http://localhost:5555/api/teams -H "Content-Type: application/json" -d '{"name":"팀명","project_group":"PG"}'

# 에이전트 스폰
curl -X POST http://localhost:5555/api/teams/{team_id}/members -H "Content-Type: application/json" -d '{"role":"frontend","display_name":"Agent Name"}'

# 티켓 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"제목","priority":"medium"}'

# 티켓 클레임
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/claim -H "Content-Type: application/json" -d '{"member_id":"agent-xxx"}'

# 상태 변경 ★
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/status -H "Content-Type: application/json" -d '{"status":"InProgress"}'

# progress_note 업데이트 ★
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/progress -H "Content-Type: application/json" -d '{"note":"진행 중"}'

# 산출물 등록 ★
curl -X POST http://localhost:5555/api/tickets/{ticket_id}/artifacts -H "Content-Type: application/json" -d '{"creator_member_id":"agent-xxx","title":"결과","content":"내용","artifact_type":"code"}'

# 팀 아카이브
curl -X POST http://localhost:5555/api/teams/{team_id}/archive -H "Content-Type: application/json"
```



### progress_note 업데이트 조건 (v4.1 — 구체적 실행 규칙)

> **에이전트는 아래 5가지 시점에 반드시 progress_note를 업데이트한다.**

| 시점 | 예시 |
|------|------|
| **1. 클레임 직후** | "분석 시작. 파일 3개 확인 예정" |
| **2. 파일 읽기/분석 완료 시** | "코드 분석 완료. 수정 필요 3곳 확인" |
| **3. 코드 수정 시작 시** | "server.py 수정 시작" |
| **4. 코드 수정 완료 시** | "수정 완료. 테스트 진행 중" |
| **5. Review 전환 직전** | "산출물 등록 완료. Review 전환" |

**업데이트 방법 (둘 중 택 1):**
```
# MCP
kanban_ticket_progress(ticket_id, note="수정 완료. 테스트 진행 중")

# REST API
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/progress   -H "Content-Type: application/json"   -d '{"note":"수정 완료. 테스트 진행 중"}'
```

**미이행 시:**
- Supervisor 순회 점검 (5분마다)에서 경고 발송
- 경고 3회 누적 → 자동 unclaim (Backlog 복귀)




# U2DIA AI SERVER AGENT

**Version**: 8.0.0
**Last Updated**: 2026-03-29
**Status**: ACTIVE
**거버넌스**: 헌법 모델 (Constitution Model) v3.0

## 거버넌스 철학

> **규제가 아닌 헌법.** 에이전트의 능력을 100% 발휘할 수 있도록, 최소한의 원칙만 정의한다.
> 어떤 도구든, 어떤 방법이든, 어떤 전략이든 — 에이전트는 자유롭게 선택한다.
> 화이트리스트 없음. 블랙리스트 없음. 결과로 증명한다.

**6가지 불변 원칙:**
1. **투명성** — 모든 작업은 칸반보드에 기록
2. **원자적 완결성** — 하나의 티켓 = 하나의 에이전트 = 하나의 세션
3. **의존성 무결성** — 선행 작업 미완료 시 착수 불가
4. **협업적 자율성** — 오케스트레이터가 조율하되, 방법론은 에이전트의 자유
5. **역할 범위** — CLAUDE.md에 정의된 범위 내에서만 작업
6. **올라마 게이트키퍼** — 올라마(유디)가 품질 검수, 정보 중계, 작업 조율

## 프로젝트 개요

U2DIA AI SERVER AGENT — Claude Code 에이전트 팀의 병렬 개발을 실시간 모니터링하는 엔터프라이즈급 칸반보드 서버.
어떤 프로젝트에서든 MCP로 연결하여 팀 생성, 티켓 관리, 에이전트 간 소통, 산출물 추적, 토큰 사용량 모니터링이 가능.
Python 표준 라이브러리만으로 동작하며, Electron 데스크톱 앱 (Server Manager + Frontend) 지원.

## 실행

```bash
python server.py                    # 기본 (포트 5555)
python server.py --port 8080        # 포트 변경
python server.py --no-browser       # 브라우저 자동 열기 비활성화
```

## 접속

| URL | 용도 |
|-----|------|
| `http://localhost:5555/` | 전체 현황 대시보드 (SPA) |
| `http://localhost:5555/#/board/{teamId}` | 팀 칸반보드 |
| `http://localhost:5555/#/archives` | 아카이브 |
| `http://localhost:5555/supervisor` | Supervisor (레거시) |
| `http://localhost:5555/api/...` | REST API |
| `http://localhost:5555/mcp` | MCP (JSON-RPC 2.0) |
| `http://localhost:5555/api/teams/{id}/events` | SSE 실시간 이벤트 |
| `http://localhost:5555/api/supervisor/events` | SSE 글로벌 이벤트 |

## MCP 연동 (다른 프로젝트에서)

`.claude/settings.json` (인증 토큰 필수):
```json
{
  "mcpServers": {
    "kanban": {
      "type": "url",
      "url": "http://localhost:5555/mcp",
      "headers": {
        "Authorization": "Bearer XXXX-XXXX-XXXX-XXXX"
      }
    }
  }
}
```

## 아키텍처

```
agents_team/
├── server.py              # Python 서버 (단일 파일, 표준 라이브러리만)
├── web/                   # 정적 프론트엔드 (SPA)
│   ├── index.html         # 메인 SPA 셸
│   ├── login.html         # 로그인 페이지
│   ├── css/               # 디자인 시스템 (variables, layout, components)
│   └── js/                # 모듈 (api, sse, router, utils, app, header, sidebar, cli-panel, dashboard, kanban)
│       └── views/         # 섹션별 뷰 (home, teams, sprints, archives, history, competitions, settings)
├── desktop/
│   ├── shared/            # 공유 모듈 (settings, server-manager, notification)
│   ├── server-manager-app/# Server Manager Electron 앱
│   │   ├── main.js, preload.js
│   │   └── renderer/      # 서버/토큰/클라이언트/메트릭/설정 UI
│   ├── frontend/          # Frontend Electron 앱
│   │   ├── main.js, preload.js
│   │   └── renderer/      # 서버 연결 UI
│   └── (기존 통합 앱)     # 레거시 (Phase D에서 정리 예정)
└── docs/                  # 문서
```

## 데스크톱 앱 (Electron)

**Server Manager** — 서버 관리, 토큰 CRUD, 클라이언트 모니터링, 시스템 메트릭
```bash
cd desktop/server-manager-app && npm install && npm start
```

**Frontend** — 칸반보드 UI 뷰어 (server.py에 연결)
```bash
cd desktop/frontend && npm install && npm start
```

## 기술 스택

- Python 3.8+ (표준 라이브러리만 사용)
- SQLite (WAL 모드, 동시 접근 안전)
- SSE (Server-Sent Events) 실시간 푸시
- ThreadedHTTPServer (동시 접속 지원)
- Vanilla JS/CSS SPA (외부 의존성 없음)
- Electron (데스크톱 앱 2종)

## 규칙

1. 모든 답변은 한국어로 작성
2. 서버(server.py): 외부 패키지 의존성 추가 금지, 단일 파일 유지
3. 프론트엔드(web/): 외부 CDN/패키지 없이 순수 JS/CSS
4. 데스크톱(desktop/): Electron + 최소 의존성

## API 엔드포인트 (신규)

| 엔드포인트 | 용도 |
|-----------|------|
| `POST/GET/DELETE /api/tokens` | 인증 토큰 CRUD |
| `GET /api/system/metrics` | CPU/메모리/디스크 시스템 메트릭 |
| `GET /api/system/clients` | 연결된 클라이언트 목록 |
| `POST /api/teams/{id}/archive` | 완료 팀 아카이브 |
| `GET /api/archives` | 아카이브 목록 |
| `POST /api/usage/report` | 토큰 사용량 보고 |
| `GET /api/teams/{id}/usage` | 팀별 토큰 사용량 |
| `GET /api/tickets/{id}/usage` | 티켓별 토큰 사용량 |
| `POST /api/supervisor/review` | Supervisor QA 검수 (ticket_id 또는 team_id+batch) |
| `GET /api/supervisor/review/stats` | Supervisor 검수 통계 (통과/재작업/평균점수) |
| `POST /api/teams/{id}/sprints` | 스프린트 생성 |
| `GET /api/teams/{id}/sprints` | 팀 스프린트 목록 |
| `GET /api/sprints/{id}` | 스프린트 상세 (게이트/메트릭/티켓) |
| `PUT /api/sprints/{id}/phase` | 스프린트 페이즈 전환 |
| `POST /api/sprints/{id}/gates` | 품질 게이트 평가 |
| `POST /api/sprints/{id}/metrics` | 메트릭 스냅샷 |
| `GET /api/teams/{id}/velocity` | 팀 벨로시티 보고 |
| `GET /api/sprints/{id}/burndown` | 번다운 차트 데이터 |
| `POST /api/sprints/{id}/cross-review` | 크로스 모델 리뷰 |
| `GET /api/sprints/{id}/retro` | 스프린트 회고 |
| `GET /api/sprints/global/stats` | 전역 스프린트 통계 |

## Supervisor QA 시스템

올라마 gemma3:27b 기반 자동 QA 검수. Review 상태 티켓을 검수하고 통과/재작업 판정.

**접근 경로:**
- 대화: "검수해줘", "리뷰해줘", "QA", "판정" 등 키워드 → 자동 supervisor 모드
- REST: `POST /api/supervisor/review` (ticket_id 또는 team_id)
- MCP: `kanban_supervisor_review`, `kanban_supervisor_stats`
- 텔레그램: `/review T-XXXXXX`, `/review` (전체), `/review_stats`
- 상주 에이전트: 10분마다 자동 검수 (최대 3개/사이클)

**판정 기준:** 1~5점, 3점 이상 통과, 2점 이하 재작업, 3회 초과 → Blocked 에스컬레이션.

## Sprint 관리 시스템 (gstack-inspired)

gstack (Garry Tan의 AI Software Factory) 패턴을 벤치마킹하여 구현한 엔터프라이즈급 스프린트 관리 시스템.

**7단계 워크플로우:** Think → Plan → Build → Review → Test → Ship → Reflect

**5가지 품질 게이트:** review, qa, security, design, performance

**접근 경로:**
- 대시보드: Sprint 버튼 → Sprint Board 뷰 (번다운 차트, 게이트 상태, 회고)
- REST API: `/api/sprints/*`, `/api/teams/{id}/sprints`, `/api/teams/{id}/velocity`
- MCP: `kanban_sprint_*` 도구 10개
- 스킬: `/sprint-planner`, `/code-review-gate`, `/qa-gate`, `/security-audit`, `/sprint-retro`, `/cross-model-review`, `/ship-workflow`, `/office-hours`, `/careful-mode`, `/autoplan`

**스프린트 워크플로우 예시:**
```
1. kanban_sprint_create(team_id, name="v2.0", goal="인증 시스템 구현")
2. kanban_sprint_phase(sprint_id, phase="Plan")
3. kanban_batch_ticket_create(team_id, tickets=[...])
4. kanban_sprint_phase(sprint_id, phase="Build")
5. kanban_sprint_gate(sprint_id, gate_type="review", status="Passed", score=8)
6. kanban_sprint_gate(sprint_id, gate_type="qa", status="Passed", score=9)
7. kanban_sprint_gate(sprint_id, gate_type="security", status="Passed", score=10)
8. kanban_sprint_phase(sprint_id, phase="Ship")
9. kanban_sprint_metrics(sprint_id)
10. kanban_sprint_retro(sprint_id)
```

**참조:** `gstack-reference/` — 원본 gstack 레포 (MIT License, Garry Tan/YC)

## 문서

| 문서 | 경로 | 설명 |
|------|------|------|
| 에이전트 헌법 | `docs/UNIVERSAL_AGENT_RULES.md` | 연동 프로젝트 공통 헌법 (v2.0) |
| 팀 운영 헌법 | `docs/agent_teams_규정.md` | 팀 운영 원칙 (v4.0) |
| 에이전트 가이드 | `docs/MCP_AGENT_GUIDE.md` | 에이전트 전달용 가이드 (v4.0) |
| MCP 설정 가이드 | `docs/MCP_SETUP_GUIDE.md` | MCP 설정, 도구 목록 |
| Skill 정의 | `docs/SKILL.md` | agent-team 스킬 사양 |
| 원격 접근 가이드 | `docs/REMOTE_ACCESS_GUIDE.md` | 외부 접속, 방화벽, Tailscale |
| 로드맵 | `docs/ROADMAP.md` | 향후 계획 |

## 스킬/에이전트/커맨드/훅

| 분류 | 경로 | 개수 |
|------|------|------|
| 범용 스킬 | `.claude/skills/` | 44개 |
| 범용 에이전트 | `.claude/agents/` | 12개 |
| 커맨드 | `.claude/commands/` | 3개 |
| 훅 | `.claude/hooks/` | 8개 |
| 스킬 트리거 | `.claude/skills/skill-rules.json` | 44개 |

## MCP 도구 (27개)

| 도구 | 용도 |
|------|------|
| `kanban_team_list` / `kanban_team_create` | 팀 관리 (project_group으로 프로젝트별 그룹핑) |
| `kanban_board_get` / `kanban_team_stats` | 보드/통계 조회 |
| `kanban_member_spawn` | 에이전트 스폰 |
| `kanban_ticket_create` / `kanban_ticket_claim` / `kanban_ticket_status` | 티켓 관리 |
| `kanban_message_create` / `kanban_message_list` | 에이전트 간 대화 |
| `kanban_artifact_create` / `kanban_artifact_list` | 산출물 공유 |
| `kanban_activity_log` | 액티비티 기록 |
| `kanban_auto_scaffold` | 프로젝트 자동 스캔 |
| `kanban_feedback_create` / `kanban_feedback_list` / `kanban_feedback_summary` | 피드백/채점 |
| `kanban_supervisor_review` / `kanban_supervisor_stats` | Supervisor QA 검수/통계 |
| `kanban_sprint_create` / `kanban_sprint_list` / `kanban_sprint_get` | 스프린트 CRUD |
| `kanban_sprint_phase` | 페이즈 전환 (Think→Plan→Build→Review→Test→Ship→Reflect) |
| `kanban_sprint_gate` | 품질 게이트 (review/qa/security/design/performance) |
| `kanban_sprint_metrics` / `kanban_sprint_velocity` / `kanban_sprint_burndown` | 메트릭/벨로시티/번다운 |
| `kanban_sprint_cross_review` | 크로스 모델 리뷰 요청 |
| `kanban_sprint_retro` | 스프린트 회고 자동 생성 |

## 연동 프로젝트 및 토큰

> 토큰은 `POST /api/tokens`으로 생성합니다. 아래는 예시입니다.

| 프로젝트 | 경로 | 토큰 |
|----------|------|------|
| my-project | `/path/to/project` | XXXX-XXXX-XXXX-XXXX |

## 에이전트 역할 범위 (헌법 제5원칙)

### 이 프로젝트의 에이전트 전문 분야
- Python 서버 개발 (server.py — 단일 파일, 표준 라이브러리만)
- SQLite DB 스키마 및 쿼리 (WAL 모드)
- SSE 실시간 이벤트 시스템
- MCP (JSON-RPC 2.0) 프로토콜
- Vanilla JS/CSS SPA 프론트엔드 (web/)
- Electron 데스크톱 앱 (desktop/)
- Flutter 모바일 앱 (flutter_app/)
- 올라마 로컬 LLM 연동 (gemma3:27b)

### 작업 범위
- 칸반보드 서버 기능 개발/수정 (API, MCP, SSE)
- 웹 프론트엔드 대시보드 개선
- 데스크톱 앱 (Server Manager, Frontend) 유지보수
- Flutter 앱 기능 추가/버그 수정
- 올라마 상주 에이전트 로직 (QA, 회의, 보고서)
- 인증/토큰 시스템 관리
- 연동 프로젝트 MCP 설정 가이드

### 금지 사항
- server.py에 외부 패키지(pip) 의존성 추가 금지
- web/에 외부 CDN/라이브러리 추가 금지
- 다른 프로젝트 디렉토리의 코드 수정 금지 (MCP 가이드 문서만 제공)
- 불필요한 파일 탐색으로 컨텍스트 낭비 금지

### 의존성 대기
- 선행 티켓(depends_on) 미완료 시 반드시 Blocked 상태 전환
- 대기 사유를 칸반 activity_log에 기록
- 대기 중 범위 내 다른 티켓 처리 가능

### 올라마 게이트키퍼 (헌법 제6원칙)
- Review 전환 시 산출물(artifact) 1개 이상 등록 필수
- 올라마가 자동 품질 검수 (1~5점)
- 2점 미만 시 재작업 티켓 발행 (최대 3회)
- 에이전트 간 소통은 칸반 메시지로 기록

### MCP 연결 실패 시
curl로 REST API 대체:
```bash
curl -s http://localhost:5555/api/teams
curl -s -X POST http://localhost:5555/api/teams -H "Content-Type: application/json" -d '{"name":"팀명","project_group":"PG"}'
```

## 전문 에이전트 운영 규정 (v4.1)

> 모든 에이전트는 전문 역할이 지정되며, 역할 범위 내에서만 작업한다.

### 등록 전문가 — 칸반보드 서버 도메인

| 역할 | 전문 분야 | 클레임 가능 티켓 |
|------|----------|----------------|
| server-expert | Python 서버 | server.py, API, MCP, SSE |
| sqlite-expert | SQLite DB | 스키마, WAL, 쿼리 |
| flutter-expert | Flutter 앱 | Dart, 위젯, 빌드 |
| ollama-expert | Ollama/LLM | 모델 연동, 도구 호출 |
| qa-expert | QA | E2E, 파이프라인 검증 |

### 규칙
1. 역할 밖 작업 금지
2. 범위 밖 → supervisor 호출
3. progress_note 필수
4. 산출물 없이 Review 불가
5. 재작업 3회 → Blocked
