# Agent Team Kanban Board — MCP 연동 가이드

**Version**: 2.0.0
**서버 위치**: `agents_team/server.py`

---

## 1. 서버 실행

```bash
# 방법 A: 데스크톱 앱 (권장)
setup.bat          # 초기 설치 (최초 1회)
start.bat          # 실행 (서버 자동 시작 + GUI)

# 방법 B: 서버만 실행
python server.py

# 방법 C: 포트 변경
python server.py --port 8080 --no-browser
```

**접속 URL**:
- 칸반보드: `http://localhost:5555/board`
- 총괄 대시보드: `http://localhost:5555/supervisor`
- MCP 엔드포인트: `http://localhost:5555/mcp`
- SSE 실시간: `http://localhost:5555/api/teams/{team_id}/events`

---

## 2. Claude Code MCP 설정

### 방법 A: 프로젝트별 설정 (.claude/settings.json)

각 프로젝트의 `.claude/settings.json`에 추가:

```json
{
  "mcpServers": {
    "kanban": {
      "type": "url",
      "url": "http://localhost:5555/mcp"
    }
  }
}
```

### 방법 B: 글로벌 설정 (~/.claude/settings.json)

모든 프로젝트에서 사용:

```json
{
  "mcpServers": {
    "kanban": {
      "type": "url",
      "url": "http://localhost:5555/mcp"
    }
  }
}
```

### 방법 C: Claude Desktop 설정

`claude_desktop_config.json`에 추가:

```json
{
  "mcpServers": {
    "agent-team-kanban": {
      "url": "http://localhost:5555/mcp"
    }
  }
}
```

---

## 3. MCP 도구 목록 (14개)

### 팀 관리
| 도구 | 설명 | 필수 파라미터 |
|------|------|--------------|
| `kanban_team_list` | 팀 목록 조회 | - |
| `kanban_team_create` | 팀 생성 | `name` |
| `kanban_board_get` | 팀 보드 데이터 | `team_id` |
| `kanban_team_stats` | 팀 통계 | `team_id` |
| `kanban_auto_scaffold` | 프로젝트 스캔 → 자동 팀 생성 | `project_path` |

### 에이전트 관리
| 도구 | 설명 | 필수 파라미터 |
|------|------|--------------|
| `kanban_member_spawn` | 에이전트 스폰 | `team_id`, `role` |

### 티켓 관리
| 도구 | 설명 | 필수 파라미터 |
|------|------|--------------|
| `kanban_ticket_create` | 티켓 생성 | `team_id`, `title` |
| `kanban_ticket_claim` | 티켓 점유 (InProgress) | `ticket_id`, `member_id` |
| `kanban_ticket_status` | 상태 변경 | `ticket_id`, `status` |

### 소통 & 산출물
| 도구 | 설명 | 필수 파라미터 |
|------|------|--------------|
| `kanban_message_create` | 메시지 작성 | `ticket_id`, `sender_member_id`, `content` |
| `kanban_message_list` | 메시지 조회 | `ticket_id` |
| `kanban_artifact_create` | 산출물 등록 | `ticket_id`, `creator_member_id`, `title`, `content` |
| `kanban_artifact_list` | 산출물 조회 | `ticket_id` |

### 로그
| 도구 | 설명 | 필수 파라미터 |
|------|------|--------------|
| `kanban_activity_log` | 액티비티 기록 | `team_id`, `action` |

---

## 4. 에이전트 워크플로우 예시

### 4-1. 메인 에이전트 (orchestrator) — 프로젝트 초기화

```
1. kanban_auto_scaffold → 프로젝트 스캔, 팀/멤버/티켓 자동 생성
   또는
   kanban_team_create → 수동 팀 생성
   kanban_member_spawn × N → 에이전트 스폰
   kanban_ticket_create × N → 티켓 생성

2. 각 서브에이전트에 team_id, member_id 전달
```

### 4-2. 서브 에이전트 — 작업 수행

```
1. kanban_ticket_claim → 티켓 점유 (Backlog/Todo → InProgress)

2. kanban_activity_log → 진행 상황 기록
   action: "progress", message: "API 3개 구현 완료"

3. kanban_message_create → 다른 에이전트에 질문/정보 공유
   message_type: "question" | "comment" | "code_review"

4. kanban_artifact_create → 산출물 등록
   artifact_type: "code" | "file_path" | "result" | "summary" | "log"

5. kanban_ticket_status → 완료 (status: "Review" 또는 "Done")
```

### 4-3. 메인 에이전트 — 검증 & 개선

```
1. kanban_board_get → 전체 보드 상태 확인
2. kanban_message_list → 에이전트 대화 확인
3. kanban_artifact_list → 산출물 검토
4. kanban_message_create → 피드백/개선 요청 (message_type: "code_review")
5. kanban_ticket_status → 승인 (Done) 또는 반려 (InProgress/Blocked)
6. kanban_team_stats → 전체 통계 확인
```

---

## 5. 티켓 상태 전이

```
Backlog → Todo → InProgress → Review → Done
                      ↓
                   Blocked
```

| 상태 | 의미 |
|------|------|
| Backlog | 대기열 |
| Todo | 작업 예정 |
| InProgress | 작업 중 (에이전트 점유) |
| Review | 검토 대기 |
| Done | 완료 |
| Blocked | 차단 |

---

## 6. 메시지 타입

| 타입 | 용도 |
|------|------|
| `comment` | 일반 댓글/진행상황 |
| `question` | 다른 에이전트에 질문 |
| `code_review` | 코드 리뷰 요청/피드백 |
| `reply` | 특정 메시지에 대한 답글 |

---

## 7. 산출물 타입

| 타입 | 용도 | 예시 |
|------|------|------|
| `code` | 코드 스니펫 | API 엔드포인트, 함수 구현 |
| `file_path` | 변경된 파일 경로 | `src/api/users.py` |
| `result` | 실행 결과 | 빌드 로그, 테스트 결과 |
| `summary` | 작업 요약 | "3개 API 구현 완료" |
| `log` | 상세 로그 | 디버깅 로그, 에러 트레이스 |

---

## 8. REST API 빠른 참조

| 메서드 | 경로 | 용도 |
|--------|------|------|
| GET | `/api/teams` | 팀 목록 |
| POST | `/api/teams` | 팀 생성 |
| GET | `/api/teams/{id}/board` | 보드 데이터 |
| POST | `/api/teams/{id}/members` | 멤버 스폰 |
| POST | `/api/teams/{id}/tickets` | 티켓 생성 |
| PUT | `/api/tickets/{id}/status` | 상태 변경 |
| PUT | `/api/tickets/{id}/claim` | 티켓 점유 |
| GET | `/api/tickets/{id}/messages` | 메시지 목록 |
| POST | `/api/tickets/{id}/messages` | 메시지 작성 |
| GET | `/api/tickets/{id}/artifacts` | 산출물 목록 |
| POST | `/api/tickets/{id}/artifacts` | 산출물 등록 |
| POST | `/api/activity` | 로그 기록 |
| GET | `/api/teams/{id}/stats` | 팀 통계 |
| GET | `/api/teams/{id}/events` | SSE 이벤트 스트림 |
| POST | `/api/teams/auto-scaffold` | 프로젝트 자동 스캔 |
| GET | `/api/supervisor/overview` | 전체 팀 개요 |
| GET | `/api/supervisor/activity` | 글로벌 액티비티 |
| GET | `/api/supervisor/stats` | 통합 통계 |
| GET | `/api/supervisor/events` | 글로벌 SSE |

---

## 9. 실시간 연동 (SSE)

대시보드는 SSE(Server-Sent Events)로 실시간 업데이트됩니다.

```javascript
// 팀별 이벤트
const es = new EventSource('/api/teams/{team_id}/events');
es.onmessage = (e) => { console.log(JSON.parse(e.data)); };

// 글로벌 이벤트 (Supervisor)
const gs = new EventSource('/api/supervisor/events');
gs.onmessage = (e) => { console.log(JSON.parse(e.data)); };
```

이벤트 타입:
- `team_created`, `member_spawned`, `ticket_created`
- `ticket_status_changed`, `ticket_claimed`
- `message_created`, `artifact_created`, `activity_logged`

---

**END OF MCP SETUP GUIDE v2.0**
