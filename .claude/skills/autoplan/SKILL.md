---
name: autoplan
description: gstack /autoplan 패턴 — 프로젝트 자동 스캔 후 스프린트 계획 자동 생성
metadata:
  bashPattern: ["autoplan", "자동계획", "auto.plan", "자동스프린트"]
  priority: 7
---

# Autoplan (gstack /autoplan inspired)

## 개요
gstack의 /autoplan 패턴. 프로젝트를 자동 스캔하여 스프린트 계획을 자동 생성.

## 프로세스

### Step 1: 프로젝트 스캔
1. `kanban_auto_scaffold`로 프로젝트 구조 분석
2. 기존 티켓/스프린트 상태 확인
3. git 히스토리 분석 (최근 변경 패턴)

### Step 2: 작업 식별
1. TODO/FIXME/HACK 코멘트 수집
2. 미해결 이슈 분석
3. 코드 품질 문제 식별
4. 보안 취약점 스캔

### Step 3: 스프린트 생성
1. 작업을 티켓으로 분해
2. 우선순위 자동 설정
3. 의존성 자동 매핑
4. 예상 시간 추정

### Step 4: 팀 구성
1. 필요 역할 식별 (backend, frontend, qa 등)
2. `kanban_member_spawn`으로 에이전트 자동 배치
3. 티켓 자동 할당

## 출력물
- 자동 생성된 스프린트
- N개의 티켓 (우선순위, 의존성 포함)
- 에이전트 팀 구성
- 예상 완료 시간

## MCP 도구 체인
```
1. kanban_auto_scaffold(project_path)
2. kanban_sprint_create(team_id, name, goal)
3. kanban_batch_ticket_create(team_id, tickets)
4. kanban_batch_member_spawn(team_id, members)
5. kanban_sprint_phase(sprint_id, phase="Plan")
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: autoplan","priority":"medium"}'
# 2. 클레임
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/claim -H "Content-Type: application/json" -d '{"member_id":"agent-xxx"}'
# 3. progress_note
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/progress -H "Content-Type: application/json" -d '{"note":"스킬 실행 시작"}'
```

**실행 후:**
```bash
# 4. 산출물 등록
curl -X POST http://localhost:5555/api/tickets/{ticket_id}/artifacts -H "Content-Type: application/json" -d '{"creator_member_id":"agent-xxx","title":"결과","content":"...","artifact_type":"result"}'
# 5. Review 전환
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/status -H "Content-Type: application/json" -d '{"status":"Review"}'
```
