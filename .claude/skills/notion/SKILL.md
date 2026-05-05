---
description: "Notion API — 페이지, 데이터베이스, 블록 생성/조회/수정. 팀 노트, 프로젝트 문서 관리."
---

# Notion Skill

Notion API로 페이지, 데이터베이스, 블록을 관리.

## 활용 시점

- Notion 페이지 생성/수정
- 데이터베이스(데이터 소스) 쿼리
- 블록 추가/수정
- 팀 문서 자동화

## 설정

1. https://notion.so/my-integrations 에서 인테그레이션 생성
2. API 키 복사 (`ntn_` 또는 `secret_` 시작)
3. 대상 페이지/DB에 인테그레이션 공유

## API 기본

```bash
# 검색
curl -X POST 'https://api.notion.com/v1/search' \
  -H 'Authorization: Bearer '"$NOTION_API_KEY" \
  -H 'Notion-Version: 2025-09-03' \
  -H 'Content-Type: application/json' \
  -d '{"query": "검색어"}'

# 페이지 조회
curl 'https://api.notion.com/v1/pages/{page_id}' \
  -H 'Authorization: Bearer '"$NOTION_API_KEY" \
  -H 'Notion-Version: 2025-09-03'

# 페이지 콘텐츠 (블록)
curl 'https://api.notion.com/v1/blocks/{page_id}/children' \
  -H 'Authorization: Bearer '"$NOTION_API_KEY" \
  -H 'Notion-Version: 2025-09-03'
```

## 데이터베이스 쿼리

```bash
curl -X POST 'https://api.notion.com/v1/databases/{db_id}/query' \
  -H 'Authorization: Bearer '"$NOTION_API_KEY" \
  -H 'Notion-Version: 2025-09-03' \
  -H 'Content-Type: application/json' \
  -d '{"filter": {"property": "Status", "select": {"equals": "Done"}}}'
```

## 참고
- `NOTION_API_KEY` 환경변수 필요
- Rate limit: 평균 3 req/sec
- 페이지/DB ID는 UUID 형식


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: notion","priority":"medium"}'
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
