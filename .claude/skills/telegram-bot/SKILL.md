---
name: telegram-bot
description: "텔레그램 봇 통합 및 U2DIA AI 에이전트"
---

# Telegram Bot — U2DIA AI 에이전트 연결

## 사용 시기
- "텔레그램", "봇", "채팅 위젯", "U2DIA AI", "고객 소통" 요청 시

## 아키텍처

```
업체 프론트엔드 (우측 하단 위젯)
  ↓ WebSocket/SSE
API Server
  ↓ Telegram Bot API
텔레그램 (관리자 수신/답변)
  ↓ Claude Code --remote-control
즉시 코드 개선/배포
```

## 핵심 기능

### 1. 채팅 위젯
- 업체별 프론트엔드 우측 하단 고정 위젯
- 실시간 메시지 전송/수신
- 파일 첨부 (이미지, 문서)
- 읽음 표시, 타이핑 인디케이터

### 2. 텔레그램 봇
- 업체별 대화 스레드 분리
- 관리자 답변 → 위젯으로 실시간 전달
- 명령어: `/status` (업체 상태), `/orders` (최근 주문), `/deploy` (배포)

### 3. Claude Code Remote Control
- 텔레그램에서 `/fix {이슈}` → Claude Code가 자동 수정
- 수정 완료 → 자동 커밋 + 배포
- 결과를 텔레그램으로 알림

## 기술 스택

- `grammy` 또는 `node-telegram-bot-api` (Node.js)
- WebSocket (실시간 양방향 통신)
- Redis Pub/Sub (메시지 브로드캐스트)

## 보안

- 업체별 텔레그램 채팅 격리
- 관리자 인증 (텔레그램 user_id 기반)
- 민감 데이터 마스킹


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: telegram-bot","priority":"medium"}'
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
