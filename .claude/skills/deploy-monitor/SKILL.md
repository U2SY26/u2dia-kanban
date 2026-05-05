---
name: deploy-monitor
description: 배포 모니터링 — 서버 상태 체크, 포트 확인, 프로세스 감시, 장애 자동 감지 및 알림
triggers:
  - "배포"
  - "deploy"
  - "서버 상태"
  - "모니터링"
  - "포트 확인"
  - "프로세스"
---

# deploy monitor Skill

배포 모니터링 — 서버 상태 체크, 포트 확인, 프로세스 감시, 장애 자동 감지 및 알림

이 스킬은 칸반보드 오케스트레이터(유디)와 연동하여 자동 실행될 수 있습니다.


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: deploy-monitor","priority":"medium"}'
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
