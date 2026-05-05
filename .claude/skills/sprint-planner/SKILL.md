---
name: sprint-planner
description: gstack 기반 스프린트 플래너 — Think→Plan→Build→Review→Test→Ship→Reflect 워크플로우로 구조화된 스프린트 생성
metadata:
  bashPattern: ["sprint", "plan", "플랜", "스프린트"]
  priority: 8
---

# Sprint Planner (gstack-inspired)

## 개요
gstack의 Software Factory 모델을 칸반보드에 적용하는 스프린트 플래너.
7단계 워크플로우 (Think → Plan → Build → Review → Test → Ship → Reflect)로 에이전트 팀의 작업을 구조화.

## 워크플로우

### Phase 1: Think (문제 정의)
1. 프로젝트 스캔: `kanban_auto_scaffold`로 현재 상태 파악
2. 목표 정의: 스프린트 목표를 명확하게 설정
3. 제약 조건 식별: 기술적 제약, 의존성, 리소스 한계

### Phase 2: Plan (설계)
1. 티켓 분해: 목표를 atomic한 티켓으로 분해
2. 의존성 매핑: `depends_on`으로 선후관계 설정
3. 우선순위 결정: Critical → High → Medium → Low
4. 예상 시간 설정: `estimated_minutes`

### Phase 3: Build (구현)
1. 에이전트 스폰: `kanban_member_spawn`으로 역할별 에이전트 배치
2. 티켓 클레임: `kanban_ticket_claim`으로 작업 시작
3. 아티팩트 등록: `kanban_artifact_create`로 산출물 기록
4. 진행 보고: `kanban_activity_log`로 상태 공유

### Phase 4: Review (코드 리뷰)
1. 코드 리뷰 게이트: `kanban_sprint_gate` (gate_type: "review")
2. 크로스 리뷰: `kanban_sprint_cross_review`로 다중 모델 리뷰
3. 피드백 반영: 리뷰 결과에 따라 재작업 또는 통과

### Phase 5: Test (QA)
1. QA 게이트: `kanban_sprint_gate` (gate_type: "qa")
2. 보안 게이트: `kanban_sprint_gate` (gate_type: "security")
3. Supervisor QA: `kanban_supervisor_review`로 자동 검수

### Phase 6: Ship (배포)
1. 최종 확인: 모든 게이트 통과 확인
2. 배포 게이트: `kanban_sprint_gate` (gate_type: "performance")
3. 메트릭 스냅샷: `kanban_sprint_metrics`

### Phase 7: Reflect (회고)
1. 회고 생성: `kanban_sprint_retro`로 자동 분석
2. 벨로시티 추적: `kanban_sprint_velocity`
3. 개선점 도출 및 다음 스프린트에 반영

## 사용법

### 스프린트 시작
```
/sprint-planner create --team TEAM-ID --name "v2.0 릴리즈" --goal "사용자 인증 시스템 구현"
```

### 페이즈 전환
```
/sprint-planner phase --sprint SP-XXXXXX --to Build
```

### 스프린트 상태 확인
```
/sprint-planner status --sprint SP-XXXXXX
```

## MCP 도구 연동
- `kanban_sprint_create`: 스프린트 생성
- `kanban_sprint_phase`: 페이즈 전환
- `kanban_sprint_gate`: 품질 게이트
- `kanban_sprint_metrics`: 메트릭 스냅샷
- `kanban_sprint_velocity`: 벨로시티 보고
- `kanban_sprint_retro`: 회고 생성
