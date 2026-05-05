---
name: error-tracking
description: "에러 추적 및 모니터링"
---

# Error Tracking — 에러 추적/모니터링

## 사용 시기
- "에러 추적", "Sentry", "모니터링", "에러 로깅", "알림" 요청 시

## 에러 추적 원칙

1. **모든 에러 캡처** — 프론트엔드/백엔드/API 에러 통합 추적
2. **컨텍스트 포함** — 유저 정보, 요청 데이터, 스택 트레이스
3. **알림 설정** — 심각도별 알림 채널 (텔레그램, 이메일, Slack)
4. **중복 그룹핑** — 같은 에러를 하나로 묶어 노이즈 감소

## 구현 가이드

### 프론트엔드
```typescript
// Error Boundary + 에러 리포팅
ErrorBoundary → captureException(error, { tags: { page, component } })
```

### 백엔드
```typescript
// Express/Next.js 글로벌 에러 핸들러
app.use((err, req, res, next) => {
  captureException(err, { extra: { path: req.path, method: req.method } });
  res.status(500).json({ error: 'Internal Server Error' });
});
```

### 알림 레벨

| 심각도 | 조건 | 알림 |
|--------|------|------|
| Critical | 서비스 다운, DB 장애 | 텔레그램 즉시 |
| Error | API 실패, 결제 에러 | 텔레그램 5분 내 |
| Warning | 느린 쿼리, 높은 메모리 | 일일 리포트 |
| Info | 새 버전 배포, 설정 변경 | 로그만 |


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: error-tracking","priority":"medium"}'
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
