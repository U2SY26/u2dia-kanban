---
name: auto-code-review
description: AI 자동 코드 리뷰 — git diff 기반 변경사항 분석, 보안 취약점, 성능 이슈, 코드 스타일 검사. Ralph Loop 리뷰와 연동.
triggers:
  - "코드 리뷰"
  - "리뷰해줘"
  - "code review"
  - "PR 리뷰"
  - "변경사항 검토"
---

# Auto Code Review

git diff 또는 PR의 변경사항을 AI가 자동 리뷰합니다.

## 리뷰 기준

### 1. 보안 (Critical)
- SQL Injection, XSS, CSRF
- 하드코딩된 시크릿/API 키
- 인증/인가 누락

### 2. 로직 (High)
- Off-by-one 에러
- Null/undefined 미처리
- 무한 루프 가능성
- Race condition

### 3. 성능 (Medium)
- N+1 쿼리
- 불필요한 리렌더링
- 메모리 누수 패턴
- 대용량 데이터 미페이지네이션

### 4. 코드 품질 (Low)
- 네이밍 컨벤션
- 중복 코드
- 미사용 import
- 매직 넘버

## 실행

```bash
# 최근 커밋 diff 리뷰
git diff HEAD~1 > /tmp/diff.patch
claude -p "아래 코드 변경을 리뷰해주세요. 보안/로직/성능/품질 순서로. 문제만 간결하게:\n$(cat /tmp/diff.patch)"

# 특정 파일 리뷰
git diff main -- src/api/ | claude -p "이 API 변경을 보안 관점에서 리뷰해주세요"
```

## 리뷰 결과 형식

```
🔍 코드 리뷰 결과
━━━━━━━━━━━━━━━━
🔴 CRITICAL (1건)
  - auth.ts:42 — SQL injection 가능성. 파라미터 바인딩 사용

🟡 WARNING (2건)
  - api.ts:128 — try/catch 없이 외부 API 호출
  - db.ts:55 — connection pool 미반환

🔵 SUGGESTION (1건)
  - utils.ts:20 — lodash.get 대신 optional chaining 권장

점수: 7/10
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: auto-code-review","priority":"medium"}'
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
