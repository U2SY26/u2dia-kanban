---
name: cross-model-review
description: gstack /codex 패턴 — 다중 AI 모델 합의 리뷰 (Claude + Ollama + Gemini)
metadata:
  bashPattern: ["cross.review", "크로스", "codex", "multi.model", "합의"]
  priority: 7
---

# Cross-Model Review (gstack /codex inspired)

## 개요
gstack의 크로스 모델 합의 패턴. 하나의 AI 모델만으로는 놓칠 수 있는 문제를 다중 모델 리뷰로 보완.

## 원칙
> "Cross-model agreement is signal, not mandate." -- gstack ETHOS.md
> AI는 추천하고, 사용자가 결정한다.

## 리뷰 유형
1. **code**: 코드 품질, 버그, 성능
2. **security**: 보안 취약점
3. **design**: 설계 패턴, 아키텍처
4. **architecture**: 시스템 설계, 확장성

## 프로세스
1. 아티팩트 수집: 최근 20개 아티팩트
2. 리뷰 요청: `kanban_sprint_cross_review`
3. 모델별 결과 비교
4. 합의 도출: 2/3 이상 동의 시 채택
5. 게이트 기록: `kanban_sprint_gate`

## 지원 모델
- **Primary**: Claude (현재 세션)
- **Secondary**: Ollama gemma3:27b (로컬)
- **Tertiary**: 추가 모델 (설정 가능)

## MCP 연동
```
kanban_sprint_cross_review(sprint_id, review_type="code", model="ollama")
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: cross-model-review","priority":"medium"}'
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
