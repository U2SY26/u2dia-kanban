---
name: mcp-builder
description: "MCP 서버 개발 가이드"
---

# MCP Builder — MCP 서버 개발

## 사용 시기
- "MCP 서버", "MCP 도구", "JSON-RPC" 관련 개발 요청 시

## MCP 프로토콜 핵심

- **JSON-RPC 2.0** 기반 통신
- `initialize` → `tools/list` → `tools/call` 순서
- 도구 정의: `name`, `description`, `inputSchema` (JSON Schema)

## 도구 설계 원칙

1. **단일 책임** — 하나의 도구는 하나의 명확한 작업 수행
2. **명확한 스키마** — required/optional 파라미터 구분, description 필수
3. **에러 처리** — isError 플래그로 성공/실패 구분
4. **멱등성** — 같은 입력에 같은 결과 보장 (가능한 경우)

## 설정 패턴

```json
{
  "mcpServers": {
    "서버명": {
      "type": "url",
      "url": "http://localhost:PORT/mcp"
    }
  }
}
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: mcp-builder","priority":"medium"}'
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
