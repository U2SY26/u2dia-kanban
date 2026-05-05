---
name: dependency-audit
description: 의존성 보안 감사 — npm audit/pip audit 실행, 취약점 분석 및 업데이트 권고
triggers:
  - "의존성"
  - "audit"
  - "취약점"
  - "보안 감사"
  - "패키지 업데이트"
---

# dependency audit Skill

의존성 보안 감사 — npm audit/pip audit 실행, 취약점 분석 및 업데이트 권고

이 스킬은 칸반보드 오케스트레이터(유디)와 연동하여 자동 실행될 수 있습니다.


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: dependency-audit","priority":"medium"}'
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
