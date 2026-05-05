---
description: "Trello 보드 관리 — REST API로 보드, 리스트, 카드 생성/조회/수정."
---

# Trello Skill

Trello REST API로 보드, 리스트, 카드를 관리.

## 활용 시점

- Trello 보드/리스트/카드 조회
- 카드 생성, 이동, 아카이브
- 코멘트 추가
- 프로젝트 보드 자동화

## 설정

1. API 키: https://trello.com/app-key
2. 토큰 생성
3. 환경변수: `TRELLO_API_KEY`, `TRELLO_TOKEN`

## API 사용

```bash
# 보드 목록
curl "https://api.trello.com/1/members/me/boards?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN"

# 리스트 조회
curl "https://api.trello.com/1/boards/{boardId}/lists?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN"

# 카드 생성
curl -X POST "https://api.trello.com/1/cards" \
  -d "key=$TRELLO_API_KEY&token=$TRELLO_TOKEN&idList={listId}&name=새 카드&desc=설명"

# 카드 이동
curl -X PUT "https://api.trello.com/1/cards/{cardId}" \
  -d "key=$TRELLO_API_KEY&token=$TRELLO_TOKEN&idList={targetListId}"

# 코멘트 추가
curl -X POST "https://api.trello.com/1/cards/{cardId}/actions/comments" \
  -d "key=$TRELLO_API_KEY&token=$TRELLO_TOKEN&text=코멘트 내용"
```

## 참고
- Rate limit: API 키당 10초에 300건, 토큰당 10초에 100건
- 보드/리스트/카드 ID는 URL이나 목록 API에서 확인


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: trello","priority":"medium"}'
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
