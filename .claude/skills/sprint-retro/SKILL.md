---
name: sprint-retro
description: gstack /retro 패턴 — 스프린트 회고 자동 생성, 벨로시티 추세, 개선점 도출
metadata:
  bashPattern: ["retro", "회고", "retrospective", "반성"]
  priority: 6
---

# Sprint Retrospective (gstack /retro inspired)

## 개요
스프린트 종료 후 자동 회고 생성. 데이터 기반으로 팀 성과를 분석하고 개선점 도출.

## 회고 구조

### 1. 배송 성과 (Delivery)
- 완료율: Done / Total x 100%
- 차단율: Blocked / Total x 100%
- 재작업률: Reworked / Total x 100%
- 벨로시티: 완료 티켓 수

### 2. 품질 지표 (Quality)
- 평균 피드백 점수
- 게이트 통과/실패 비율
- Supervisor 검수 결과

### 3. 시간 분석 (Timing)
- 평균 티켓 소요 시간
- 총 작업 시간
- 예상 vs 실제 비교

### 4. 하이라이트 (What went well)
- 높은 완료율 (>=80%)
- 우수한 품질 (>=4.0/5)
- 효율적 페이즈 전환

### 5. 개선점 (What to improve)
- 높은 재작업률 (>20%)
- 차단 티켓 다수
- 게이트 실패
- 시간 초과 티켓

## 사용법
```
kanban_sprint_retro(sprint_id="SP-XXXXXX")
```

## 출력 형식
```json
{
  "retro": {
    "sprint": { "id", "name", "goal", "phase", "status" },
    "delivery": { "total_tickets", "done", "blocked", "completion_rate", "reworked" },
    "timing": { "avg_minutes_per_ticket", "total_hours" },
    "quality": { "avg_feedback_score", "gates_passed", "gates_failed" },
    "highlights": ["높은 완료율: 85%"],
    "improvements": ["재작업률 높음: 25%"]
  }
}
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: sprint-retro","priority":"medium"}'
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
