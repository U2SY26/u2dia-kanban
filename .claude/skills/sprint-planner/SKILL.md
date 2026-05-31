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

## 자율 주행 (2026-05-10 통합)

> **사장님 지시 v3.3**: 사장님이 sprint 스킬 트리거 시 칸반에 자동으로 팀+스프린트가 구성되고, 헌법 준수하에 7-phase 가 자율 진행. Reflect 종료 시 자동 보고.

### 단일 진입점 — `POST /api/sprints/auto`

스프린트 시작은 단일 endpoint 호출로 끝낸다. 팀이 없으면 자동 생성, 5게이트 자동 초기화, 마커 티켓 자동 생성, 텔레그램 알림, Plan 자동 진입까지 한 번에.

```bash
curl -X POST http://localhost:5555/api/sprints/auto \
  -H "Content-Type: application/json" \
  -d '{
    "name": "v2.0 릴리즈",
    "goal": "사용자 인증 시스템 구현",
    "team_name": "TEAM-AUTH-V2",
    "project_group": "U2DIA AI",
    "planned_end": "2026-05-20 18:00:00"
  }'
```

응답:
```json
{
  "ok": true,
  "sprint": {"sprint_id": "SP-XXXXXX", "phase": "Think", ...},
  "marker_ticket_id": "T-XXXXXX",
  "gates": ["review", "qa", "security", "design", "performance"],
  "auto_phase": "Think → Plan (5s 후)"
}
```

### 자동으로 일어나는 것

| 시점 | 자동 동작 |
|------|-----------|
| **create** | 5게이트 Pending row + 마커티켓 (체크리스트 description) + 텔레그램 알림 + SSE 푸시 + 5초 후 Plan 자동 진입 |
| **Plan → Build** | sub-ticket 1개 이상 생성 시 자동 진입 (60s scheduler) |
| **Build → Review** | 모든 sub-ticket 이 Review/Done 상태 시 자동 진입 |
| **Review → Test** | review 게이트 자동 평가 (rework_count 기반) → Passed 시 자동 진입 |
| **Test → Ship** | qa+security 게이트 자동 평가 (Supervisor avg_score 기반) → 둘 다 Passed 시 |
| **Ship → Reflect** | performance 게이트 자동 평가 (done_rate 기반) + metrics 스냅샷 후 자동 진입 |
| **Reflect** | 자동 retro 생성 + 마커 티켓에 결과 산출물 등록 + Done 전환 + 텔레그램 알림 |
| **planned_end 도달** | 진행 phase 무관하게 강제 Reflect 전환 |
| **매분 (Build~Ship)** | metrics 스냅샷 자동 (번다운 차트 데이터 누적) |

### 헌법 강제

- 마커 티켓 description 은 GFM 체크박스 (제7원칙 — 체크리스트 강제)
- 모든 Review→Done 은 Supervisor 검수 통과 (제6원칙)
- 위반 시 hook 차단 + activity_log 기록

### 수동 호출 (필요 시)

```bash
# 팀이 이미 있으면
curl -X POST http://localhost:5555/api/teams/{team_id}/sprints \
  -H "Content-Type: application/json" \
  -d '{"name":"v2.0","goal":"..."}'

# 페이즈 강제 전환 (스케줄러를 기다리지 않을 때)
curl -X PUT http://localhost:5555/api/sprints/SP-XXXXXX/phase \
  -H "Content-Type: application/json" \
  -d '{"phase":"Build"}'

# 회고 직접 조회
curl http://localhost:5555/api/sprints/SP-XXXXXX/retro
```

## MCP 도구 연동
- `kanban_sprint_create`: 스프린트 생성 (자율 주행 적용 후 5게이트 + 마커티켓 자동)
- `kanban_sprint_phase`: 페이즈 전환 (의무 동작 자동 트리거)
- `kanban_sprint_gate`: 품질 게이트 수동 평가 (자동 평가는 phase 전환 시)
- `kanban_sprint_metrics`: 메트릭 스냅샷 (자동도 60s 주기)
- `kanban_sprint_velocity`: 벨로시티 보고
- `kanban_sprint_retro`: 회고 생성 (Reflect 진입 시 자동 호출)
