# U2DIA AI Agents — MCP Agent Guide

**Version**: 5.0.0
**Last Updated**: 2026-03-14
**용도**: 이 문서를 에이전트에게 전달하세요. MCP 연동으로 칸반보드 실시간 협업이 가능합니다.
**서버**: `http://localhost:5555` (데스크톱 앱 또는 `python server.py`로 실행)

---

## 철학

> **에이전트는 자유롭다.** 이 가이드는 도구의 사용법을 알려줄 뿐, 에이전트의 방법론을 규제하지 않는다.
> 어떤 순서든, 어떤 조합이든, 어떤 전략이든 — 결과를 내면 된다.

---

## 🔴 필수: 진행상황 실시간 보고 (어기면 독촉 메시지 수신)

에이전트는 **5~10 스텝마다** 반드시 칸반보드에 진행상황 멘트를 남겨야 합니다.

```python
kanban_activity_log(
  team_id="your-team-id",
  ticket_id="your-ticket-id",
  action="progress",
  message="현재 무엇을 하고 있는지 구체적으로 — 예: UserService.login() 구현 중, JWT 검증 로직 추가",
  member_id="your-member-id"
)
```

**이 멘트는:**
- 칸반보드 카드에 실시간으로 표시됩니다 (파란 테두리 + 라이브 닷)
- 상주에이전트(유디)가 20분 이상 업데이트 없으면 자동으로 독촉합니다
- Done 처리 시 QA 점수에 반영됩니다 (진행노트 없으면 감점)

**멘트를 남겨야 하는 시점:**
1. 새로운 접근 방법을 시도할 때
2. 주요 파일/함수를 수정할 때
3. 오류/차단 상황이 생겼을 때
4. 테스트를 실행할 때
5. 완료가 임박했을 때

**완료 처리:**
```python
kanban_ticket_status(ticket_id="your-ticket-id", status="Done")
# 반드시 Done 처리 — 하지 않으면 InProgress로 영원히 남습니다
```

---


---

## 1. MCP 설정 (30초)

프로젝트의 `.claude/settings.json`에 추가:

```json
{
  "mcpServers": {
    "kanban": {
      "type": "url",
      "url": "http://localhost:5555/mcp",
      "headers": {
        "Authorization": "Bearer YOUR-TOKEN-HERE"
      }
    }
  }
}
```

> 글로벌 적용: `~/.claude/settings.json`에 추가하면 모든 프로젝트에서 사용 가능

---

## 2. 프로젝트 그룹 & 아키텍처

### 프로젝트 그룹 (project_group)

> **project_group = 현재 git 프로젝트의 폴더명** (자동 설정)

```
프로젝트 폴더          →  project_group
E:\PMI-AIP            →  "PMI-AIP"
D:\LINKO              →  "LINKO"
E:\Hexacotest         →  "Hexacotest"
```

- MCP 토큰 인증 시 서버가 `project_group`을 **자동 설정** → 에이전트가 별도 지정할 필요 없음
- 하나의 프로젝트에서 **여러 팀** 생성 가능 (예: "보안 강화", "UI 리팩터링")
- 대시보드에서 프로젝트별 그룹핑 표시, `kanban_team_list(project_group="PMI-AIP")`로 필터 가능

### 아키텍처

```
  ┌─── Project Group (git 폴더명) ───┐
  │                                    │
  │    ┌─────────────────┐             │
  │    │   Orchestrator   │            │
  │    └───────┬─────────┘             │
  │  ┌─────────┼─────────┐            │
  │  │         │         │            │
  │  ▼         ▼         ▼            │
  │ Agent A  Agent B  Agent C         │
  │                                    │
  │  Team 1   Team 2   Team 3  ...    │
  └────────────────────────────────────┘
```

**불변 원칙 4가지:**
1. **투명성**: 모든 작업은 칸반보드에 기록
2. **원자적 완결성**: 하나의 티켓 = 하나의 에이전트 = 하나의 세션
3. **의존성 무결성**: 선행 티켓 미완료 시 착수 불가
4. **협업적 자율성**: 오케스트레이터가 조율하되, 에이전트는 방법론에서 자유

---

## 3. MCP 도구 (17개)

에이전트는 아래 도구를 **자유롭게** 사용한다. 순서 제약 없음. 타입 제약 없음.

### 팀 관리

| 도구 | 설명 | 필수 파라미터 | 선택 파라미터 |
|------|------|--------------|--------------|
| `kanban_team_create` | 팀 생성 | `name` | `description`, `project_group` |
| `kanban_team_list` | 팀 목록 | — | `status`, `project_group` |
| `kanban_board_get` | 보드 전체 조회 | `team_id` | — |
| `kanban_team_stats` | 팀 통계 | `team_id` | — |
| `kanban_auto_scaffold` | 프로젝트 자동 스캔 | `project_path` | `team_name`, `task_description` |

> **project_group**: 팀이 속한 프로젝트 그룹. MCP 토큰 인증 시 토큰의 프로젝트명이 자동으로 `project_group`에 설정되므로, 별도 지정하지 않아도 대시보드에서 프로젝트별로 그룹핑됩니다.

### 에이전트

| 도구 | 설명 | 필수 | 선택 |
|------|------|------|------|
| `kanban_member_spawn` | 에이전트 스폰 | `team_id`, `role` | `display_name` |

> **role**: 어떤 역할이든 자유롭게 정의 가능. `backend`, `frontend` 등은 예시일 뿐.

### 티켓

| 도구 | 설명 | 필수 | 선택 |
|------|------|------|------|
| `kanban_ticket_create` | 티켓 생성 | `team_id`, `title` | `description`, `priority`, `tags`, `estimated_minutes`, `depends_on` |
| `kanban_ticket_claim` | 티켓 점유 (→ InProgress) | `ticket_id`, `member_id` | — |
| `kanban_ticket_status` | 상태 변경 | `ticket_id`, `status` | — |

> **status**: `Backlog` → `Todo` → `InProgress` → `Review` → `Done` / `Blocked`
>
> **에이전트도 티켓 생성 가능**: 작업 중 발견한 서브태스크나 추가 작업을 직접 `kanban_ticket_create`로 등록할 수 있다. 오케스트레이터만의 권한이 아니다.

### 소통

| 도구 | 설명 | 필수 | 선택 |
|------|------|------|------|
| `kanban_message_create` | 메시지 작성 | `ticket_id`, `sender_member_id`, `content` | `message_type`, `parent_message_id`, `metadata` |
| `kanban_message_list` | 메시지 조회 | `ticket_id` | — |

> **message_type**: 자유롭게 정의. `comment`, `question`, `code_review`, `reply` 등은 예시일 뿐 — 어떤 값이든 가능.

### 산출물

| 도구 | 설명 | 필수 | 선택 |
|------|------|------|------|
| `kanban_artifact_create` | 산출물 등록 | `ticket_id`, `creator_member_id`, `title`, `content` | `artifact_type`, `language`, `metadata` |
| `kanban_artifact_list` | 산출물 조회 | `ticket_id` | — |

> **artifact_type**: 자유롭게 정의. `code`, `file_path`, `result`, `summary`, `diagram`, `screenshot` 등 어떤 값이든 가능.

### 액티비티 로그

| 도구 | 설명 | 필수 | 선택 |
|------|------|------|------|
| `kanban_activity_log` | 활동 기록 | `team_id`, `action` | `ticket_id`, `member_id`, `message`, `metadata` |

> **action**: 자유롭게 정의. 에이전트가 의미 있다고 판단하는 어떤 이벤트든 기록.

### 피드백

| 도구 | 설명 | 필수 | 선택 |
|------|------|------|------|
| `kanban_feedback_create` | 피드백 등록 | `ticket_id`, `score` | `comment`, `author`, `categories` |
| `kanban_feedback_list` | 피드백 조회 | `ticket_id` | — |
| `kanban_feedback_summary` | 팀 피드백 요약 | `team_id` | — |

> **score**: 1~5 (5가 최고). **categories**: 자유롭게 정의.

---

## 4. 오케스트레이터 가이드

```
1. 팀 생성 → 프로젝트 분석 → 업무 원자화
2. 티켓 등록 (의존성/우선순위 포함)
3. 에이전트 스폰 → 최소한의 정보 전달
4. 모니터링 → 필요 시 개입
5. 검증 → 피드백 → 완료
```

### 서브 에이전트에게 전달할 정보 (최소한만)

```
당신은 {role} 에이전트입니다.

- team_id: {team_id}
- member_id: {member_id}
- 담당 티켓: {ticket_ids}
- 칸반보드: http://localhost:5555/#/board/{team_id}

칸반보드 MCP 도구(kanban_*)를 사용하여 작업하세요.
티켓을 claim하고, 작업하고, 결과를 등록하고, Review로 전환하면 됩니다.
방법은 자유입니다.
```

**그 이상의 지시는 필요 없다.** 에이전트는 전문가다. 어떻게 할지는 에이전트가 결정한다.

---

## 5. 에이전트 워크플로우

### 필수 단계 (4단계)

```
1. 티켓 점유      → kanban_ticket_claim
2. 중간 보고      → kanban_ticket_progress (progress_note 등록) ★ 필수
3. 작업 + 산출물   → kanban_artifact_create (최소 1개) ★ 필수
4. 완료 전환      → kanban_ticket_status → "Review"
```

**⚠️ v4.1 강화 규정:**
- **2단계 중간 보고는 필수다.** InProgress 전환 후 progress_note가 없으면 Supervisor가 좀비로 감지하여 경고를 발송한다.
- **3단계 산출물은 필수다.** 산출물 없이 Review 전환 시 서버가 거부한다 (`artifact_required` 에러).
- **범위 밖 작업 금지.** 다른 팀의 코드를 수정해야 하면 supervisor에게 메시지로 요청한다.
- **에이전트 간 소통은 칸반 메시지로 기록한다.** 회의가 필요하면 supervisor를 경유한다.
- **무활동 30분 시 자동 unclaim.**
- **재작업 3회 초과 시 Blocked 에스컬레이션.**

작업 방법, 순서, 도구 선택은 여전히 에이전트의 자유다. 위 규정만 지키면 된다.

### 차단(Blocked) 시

```
kanban_ticket_status(ticket_id, status="Blocked")
+ 메시지 또는 로그로 원인 기록 (형식 자유)
```

---

## 6. 실시간 모니터링 (SSE)

| URL | 용도 |
|-----|------|
| `http://localhost:5555/` | 대시보드 (전체 현황) |
| `http://localhost:5555/#/board/{teamId}` | 칸반보드 (팀별) |

### SSE 이벤트 (자동 수신)

| 이벤트 | 트리거 |
|--------|--------|
| `team_created` | 새 팀 생성 |
| `member_spawned` | 에이전트 스폰 |
| `ticket_created` | 티켓 생성 |
| `ticket_status_changed` | 티켓 상태 변경 |
| `ticket_claimed` | 에이전트가 티켓 점유 |
| `message_created` | 메시지 작성 |
| `artifact_created` | 산출물 등록 |
| `feedback_created` | 피드백 등록 |
| `activity_logged` | 액티비티 기록 |

### 프로그래밍 연동

```javascript
// 특정 팀 이벤트
const es = new EventSource('http://localhost:5555/api/teams/{team_id}/events');
es.onmessage = (e) => console.log(JSON.parse(e.data));

// 전체 이벤트
const globalEs = new EventSource('http://localhost:5555/api/supervisor/events');
```

---

## v4.0 → v5.0 변경 사항

| 항목 | v4.0 | v5.0 |
|------|------|------|
| 산출물 등록 | Review 전환 시 필수 | 권장 (메시지/로그로 대체 가능) |
| 티켓 생성 권한 | 오케스트레이터 중심 | 에이전트도 직접 생성 가능 |
| message_type | 자유 정의 (문구 보완) | 예시임을 명확히 표기 |
| 거버넌스 | 헌법 모델 v2.0 적용 시작 | 헌법 모델 v2.0 완전 반영 |

---

**END OF U2DIA AI AGENTS — MCP AGENT GUIDE v5.0**
