---
name: code-review-gate
description: gstack /review 패턴 — 프로덕션 버그 사전 차단을 위한 구조화된 코드 리뷰 게이트
metadata:
  bashPattern: ["review", "리뷰", "코드리뷰", "code.review"]
  filePattern: ["**/*.py", "**/*.js", "**/*.ts", "**/*.dart"]
  priority: 9
---

# Code Review Gate (gstack /review inspired)

## 개요
gstack의 /review 스킬을 칸반보드에 적용. 머지 전 프로덕션 버그를 사전 차단하는 구조화된 리뷰 게이트.

## 리뷰 체크리스트

### 1. 보안 (Security)
- [ ] SQL 인젝션 방지 (파라미터 바인딩 사용)
- [ ] XSS 방지 (사용자 입력 이스케이프)
- [ ] 인증/인가 검증
- [ ] 민감 데이터 노출 없음
- [ ] CSRF 보호

### 2. 로직 (Logic)
- [ ] 엣지 케이스 처리
- [ ] 에러 핸들링 적절
- [ ] 레이스 컨디션 없음
- [ ] 상태 관리 일관성

### 3. 성능 (Performance)
- [ ] N+1 쿼리 없음
- [ ] 불필요한 데이터 로딩 없음
- [ ] 메모리 누수 없음
- [ ] 무한 루프 가능성 없음

### 4. 코드 품질 (Quality)
- [ ] 네이밍 명확
- [ ] 중복 코드 없음
- [ ] 복잡도 적절
- [ ] 테스트 커버리지

## 리뷰 프로세스

1. **변경 분석**: `git diff` 또는 아티팩트 검토
2. **체크리스트 실행**: 위 4개 카테고리 순차 검토
3. **게이트 판정**:
   - Score 8-10: Passed (바로 머지 가능)
   - Score 5-7: Conditional (경미한 수정 후 머지)
   - Score 1-4: Failed (재작업 필요)
4. **피드백 등록**: `kanban_sprint_gate`로 결과 기록
5. **SSE 알림**: 팀에 리뷰 결과 브로드캐스트

## MCP 연동
```
kanban_sprint_gate(sprint_id, gate_type="review", status="Passed", score=8, findings="보안 검토 통과, 로직 검증 완료")
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: code-review-gate","priority":"medium"}'
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
