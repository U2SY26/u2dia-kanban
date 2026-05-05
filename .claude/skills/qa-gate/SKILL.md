---
name: qa-gate
description: gstack /qa 패턴 — 3단계 QA 테스트 게이트 (Quick/Standard/Exhaustive)
metadata:
  bashPattern: ["qa", "test", "테스트", "QA"]
  priority: 8
---

# QA Gate (gstack /qa inspired)

## 개요
gstack의 /qa 스킬 패턴을 칸반보드에 적용. 3단계 깊이의 QA 테스트 실행.

## QA 티어

### Tier 1: Quick (Critical + High만)
- 핵심 기능 동작 확인
- 크리티컬 버그 검출
- 소요: ~5분

### Tier 2: Standard (+ Medium)
- API 엔드포인트 응답 검증
- 데이터 무결성 확인
- 에러 핸들링 검증
- 소요: ~15분

### Tier 3: Exhaustive (+ Low + 코스메틱)
- UI/UX 일관성
- 성능 벤치마크
- 접근성 검사
- 보안 스캔
- 소요: ~30분

## QA 프로세스

1. **테스트 범위 결정**: 변경된 파일/기능 기반
2. **테스트 실행**: 티어별 순차 실행
3. **버그 발견 시**:
   - 자동 티켓 생성: `kanban_ticket_create`
   - 아토믹 커밋: 버그 하나당 커밋 하나
   - 리그레션 테스트 추가
4. **건강 점수 산출**: Before/After 비교
5. **게이트 판정**: `kanban_sprint_gate(gate_type="qa")`

## 헬스 스코어 계산
```
score = (passed_tests / total_tests) * 10
- Critical bug: -3점
- High bug: -2점
- Medium bug: -1점
- Low bug: -0.5점
```

## MCP 연동
```
kanban_sprint_gate(sprint_id, gate_type="qa", status="Passed", score=9, findings="Tier 2: 15개 테스트 통과, 0 버그")
```
