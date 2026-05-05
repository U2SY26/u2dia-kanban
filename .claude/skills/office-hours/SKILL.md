---
name: office-hours
description: gstack /office-hours 패턴 — YC 스타일 문제 진단, 핵심 질문으로 프로젝트 방향 수립
metadata:
  bashPattern: ["office.hours", "진단", "방향", "상담", "YC"]
  priority: 7
---

# Office Hours (gstack /office-hours inspired)

## 개요
gstack의 /office-hours 패턴. YC 스타일의 6가지 핵심 질문으로 프로젝트 문제를 진단하고 방향을 수립.

## 6가지 핵심 질문

### 1. "무엇을 만들고 있나요?"
- 한 문장으로 설명할 수 있는가?
- 사용자는 누구인가?

### 2. "왜 이것을 만드나요?"
- 어떤 문제를 해결하는가?
- 이 문제가 진짜 존재하는가?

### 3. "사용자가 지금 이 문제를 어떻게 해결하고 있나요?"
- 현재 대안은?
- 왜 부족한가?

### 4. "왜 지금인가?"
- 이전에 불가능했던 이유는?
- 타이밍이 맞는 이유는?

### 5. "우리만의 고유한 이점은?"
- 경쟁자 대비 차별점은?
- 기술적 해자(moat)는?

### 6. "첫 번째 마일스톤은?"
- 1주 내 검증 가능한 것은?
- 최소 기능 제품(MVP)은?

## 출력물
- 프로젝트 진단 보고서
- 5가지 핵심 인사이트
- 3가지 구현 접근법 (노력 수준별)
- 스프린트 목표 제안

## 모드
- **Startup**: 수요 중심 진단
- **Builder**: 브레인스토밍 + 구현 경로


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: office-hours","priority":"medium"}'
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
