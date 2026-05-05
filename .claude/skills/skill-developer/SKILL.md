---
name: skill-developer
description: "Claude Code 스킬 생성 및 관리 가이드"
---

# Skill Developer — 스킬 생성 가이드

## 사용 시기
- "스킬 만들어", "스킬 생성", "create skill" 등 스킬 생성 요청 시

## 스킬 구조

```
.claude/skills/{skill-name}/
├── SKILL.md          # 메인 정의 (500줄 이내 권장)
└── resources/        # 참조 자료 (선택)
```

## SKILL.md 필수 구조

```yaml
---
name: skill-name
description: "한 줄 설명"
---
```

본문: 사용 시기, 핵심 원칙, 실행 절차

## 헌법적 원칙

1. **Claude의 능력을 제한하지 않는다** — 가이드라인을 제공하되 가능성을 닫지 않는다
2. **추상적이고 범용적으로 작성** — 특정 프레임워크/라이브러리에 종속되지 않는다
3. **500줄 이내** — 초과 시 resources/ 하위로 분리
4. **YAML 프론트매터는 name, description만** 사용


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: skill-developer","priority":"medium"}'
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
