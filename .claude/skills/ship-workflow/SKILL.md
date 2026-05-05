---
name: ship-workflow
description: gstack /ship 패턴 — 테스트→PR→배포 자동화 워크플로우
metadata:
  bashPattern: ["ship", "배포", "deploy", "출시", "릴리즈"]
  priority: 8
---

# Ship Workflow (gstack /ship inspired)

## 개요
gstack의 /ship 패턴. 테스트 실행 -> 게이트 확인 -> PR 생성 -> 배포까지 자동화.

## 워크플로우

### Step 1: Pre-flight Check
1. 모든 게이트 상태 확인
2. 블로커 티켓 없음 확인
3. 미완료 리뷰 없음 확인

### Step 2: Test
1. 유닛 테스트 실행
2. 통합 테스트 실행
3. 테스트 결과 기록

### Step 3: Ship
1. 변경사항 커밋
2. PR 생성 (또는 직접 머지)
3. 메트릭 스냅샷: `kanban_sprint_metrics`
4. 스프린트 페이즈 -> Ship

### Step 4: Verify
1. 배포 확인
2. 성능 게이트: `kanban_sprint_gate(gate_type="performance")`
3. 모니터링 확인

## 게이트 체크 자동화
```
# 모든 게이트 통과 확인
sprint = kanban_sprint_get(sprint_id)
gates = sprint.gates
all_passed = all(g["status"] == "Passed" for g in gates if g["status"] != "Waived")
if not all_passed:
    print("미통과 게이트 존재 -- ship 불가")
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: ship-workflow","priority":"medium"}'
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
