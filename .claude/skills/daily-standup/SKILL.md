---
name: daily-standup
description: 일일 스탠드업 자동 보고 — 어제 완료, 오늘 예정, 차단 이슈를 프로젝트별로 정리. Telegram 자동 발송 가능.
triggers:
  - "스탠드업"
  - "standup"
  - "일일 보고"
  - "어제 뭐했어"
  - "오늘 뭐해"
  - "데일리"
---

# Daily Standup

24시간 내 활동을 기반으로 자동 스탠드업 보고서를 생성합니다.

## 보고 항목

1. **어제 완료** — 최근 24h 내 Done 전환된 티켓
2. **오늘 예정** — InProgress + Todo(의존성 충족) 티켓
3. **차단 이슈** — Blocked 티켓 + 원인

## SQL 쿼리

```sql
-- 어제 완료
SELECT t.title, tm.name FROM tickets t
JOIN agent_teams tm ON t.team_id=tm.team_id
WHERE t.status='Done' AND t.completed_at > datetime('now', '-24 hours');

-- 오늘 예정
SELECT t.title, tm.name FROM tickets t
JOIN agent_teams tm ON t.team_id=tm.team_id
WHERE t.status IN ('InProgress','Todo') AND tm.status='Active';

-- 차단
SELECT t.title, tm.name FROM tickets t
JOIN agent_teams tm ON t.team_id=tm.team_id
WHERE t.status='Blocked';
```
