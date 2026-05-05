---
name: agent-team
description: "U2DIA AI Agents — 에이전트 팀 생성/관리 및 칸반보드 실시간 모니터링"
---

# U2DIA AI Agents — 에이전트 팀 관리

## 사용 시기

- "팀 생성", "에이전트 스폰", "티켓 생성" 등의 요청 시
- 병렬 개발 워크플로우 구축 시
- 칸반보드 대시보드 운영 시
- 다른 프로젝트에서 MCP로 연동하여 작업 관리 시

## 철학

> **칸반보드는 추적 도구이지, 규제 시스템이 아니다.**
> 에이전트는 모든 도구, 스킬, 방법론을 자유롭게 사용한다.
> 칸반보드는 팀의 투명성과 협업을 위해 존재할 뿐이다.

## 프로젝트 그룹 규칙 (필수)

> **project_group = 현재 git 프로젝트의 폴더명**
> 예: `E:\PMI-AIP` → project_group = `PMI-AIP`, `D:\LINKO` → project_group = `LINKO`

- 팀 생성 시 `project_group`은 **MCP 토큰 인증으로 자동 설정**됨 (별도 지정 불필요)
- 하나의 프로젝트에서 **여러 팀**을 생성할 수 있음 (예: "PMI-AIP UI 리팩터링", "PMI-AIP 보안 강화")
- 대시보드에서 **프로젝트별로 그룹핑**되어 표시됨
- 팀 목록 조회 시 `project_group`으로 필터 가능: `kanban_team_list(project_group="PMI-AIP")`

## 워크플로우 개요

### 일반적 흐름 (참고용)

1. **팀 생성** → `kanban_team_create` (project_group 자동 설정)
2. **티켓 등록** → `kanban_ticket_create` (오케스트레이터 또는 에이전트 모두 가능)
3. **에이전트 스폰** → `kanban_member_spawn`
4. **작업 수행** → `ticket_claim` → 개발 → `ticket_status`
5. **검증/통합** → 오케스트레이터가 검토 → 최종 승인

> 위 흐름은 **전형적 패턴**이다. 에이전트는 상황에 따라 순서를 조정하거나 단계를 병합할 수 있다.

### 원칙

- **투명성 권장** — 작업 내용은 가능한 한 칸반보드에 기록한다
- **티켓 기반 작업 권장** — 업무를 티켓으로 분할하면 추적이 쉬워진다
- **에이전트도 티켓 생성 가능** — 작업 중 발견한 서브태스크를 직접 티켓으로 등록할 수 있다
- **산출물 등록 권장** — 완료된 작업의 결과물을 artifact로 등록하면 팀 전체가 참조할 수 있다
- **액티비티 로그 권장** — 진행 상황 기록은 팀 가시성을 높인다

### 에이전트 간 소통

- `kanban_message_create`로 메시지를 주고받는다
- `message_type`은 자유 정의: `comment`, `question`, `code_review`, `reply` 등 어떤 값이든 사용 가능
- `parent_message_id`로 스레드 답글 지원
- 대시보드에서 실시간 모니터링 가능

## MCP 도구 (17개)

### 팀 관리
| 도구 | 필수 파라미터 |
|------|-------------|
| `kanban_team_list` | — (선택: `status`, `project_group`) |
| `kanban_team_create` | `name` (선택: `description`, `project_group` — 토큰 인증 시 자동 설정) |
| `kanban_board_get` | `team_id` |
| `kanban_team_stats` | `team_id` |
| `kanban_auto_scaffold` | `project_path` |

### 에이전트
| 도구 | 필수 파라미터 |
|------|-------------|
| `kanban_member_spawn` | `team_id`, `role` |

### 티켓
| 도구 | 필수 파라미터 |
|------|-------------|
| `kanban_ticket_create` | `team_id`, `title` |
| `kanban_ticket_claim` | `ticket_id`, `member_id` |
| `kanban_ticket_status` | `ticket_id`, `status` |

### 소통/산출물
| 도구 | 필수 파라미터 |
|------|-------------|
| `kanban_message_create` | `ticket_id`, `sender_member_id`, `content` |
| `kanban_message_list` | `ticket_id` |
| `kanban_artifact_create` | `ticket_id`, `creator_member_id`, `title`, `content` |
| `kanban_artifact_list` | `ticket_id` |

### 로그
| 도구 | 필수 파라미터 |
|------|-------------|
| `kanban_activity_log` | `team_id`, `action` |

### 피드백/채점
| 도구 | 필수 파라미터 |
|------|-------------|
| `kanban_feedback_create` | `ticket_id`, `score` |
| `kanban_feedback_list` | `ticket_id` |
| `kanban_feedback_summary` | `team_id` |

## 접속

- 대시보드: `http://localhost:5555/`
- 칸반보드: `http://localhost:5555/#/board/{teamId}`
- 아카이브: `http://localhost:5555/#/archives`
- MCP: `http://localhost:5555/mcp` (JSON-RPC 2.0)
- SSE: `http://localhost:5555/api/teams/{id}/events`

## 상세 규정

- `docs/MCP_AGENT_GUIDE.md` — 에이전트 전달용 완전 가이드
- `docs/agent_teams_규정.md` — 팀 아키텍처, 역할, 워크플로우 규정
- `docs/MCP_SETUP_GUIDE.md` — 기술적 MCP 설정 가이드
