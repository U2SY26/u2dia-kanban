---
name: notification-system
description: "알림 시스템 (텔레그램, 이메일, 푸시)"
---

# Notification System — 알림 시스템

## 사용 시기
- "알림", "노티피케이션", "푸시", "이메일 발송" 요청 시

## 알림 채널

| 채널 | 용도 | 라이브러리 |
|------|------|-----------|
| 텔레그램 | 실시간 알림 (관리자) | grammy |
| 이메일 | 공식 알림 (업체, 유저) | Resend / Nodemailer |
| 인앱 | 웹 알림 (대시보드 내) | SSE / WebSocket |
| 푸시 | 모바일 알림 | Firebase Cloud Messaging |

## 알림 유형

| 유형 | 트리거 | 수신자 |
|------|--------|--------|
| 주문 접수 | 새 주문 생성 | 업체 관리자 |
| 재고 부족 | 안전재고 미달 | 업체 관리자 |
| 배송 완료 | 운송장 상태 변경 | 구매자 |
| 개발 요청 | 게시판 등록 | 개발자 (텔레그램) |
| 시스템 에러 | 에러 발생 | 운영자 |
| API 연결 실패 | 마켓플레이스 API 에러 | 업체 관리자 |

## 구현 원칙

1. **비동기 전송** — 큐 기반 (BullMQ)으로 알림 발송
2. **중복 방지** — 동일 알림 일정 시간 내 재발송 차단
3. **선호 설정** — 유저별 알림 채널/유형 선택 가능
4. **템플릿** — 알림 메시지 템플릿 관리


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: notification-system","priority":"medium"}'
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
