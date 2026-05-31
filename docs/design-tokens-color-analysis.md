# U2DIA 칸반보드 — CSS 색상 체계 & 디자인 토큰 분석

> **작성일**: 2026-03-23
> **대상 파일**: `web/css/variables.css`, `kanban.css`, `components.css`, `layout.css`, `sidebar.css`, `cli.css`
> **디자인 테마**: Salesforce Lightning Dark Mode (Navy layered system)
> **tailwind.config / globals.css / SCSS**: 해당 없음 (Vanilla CSS만 사용)

---

## 1. 색상 체계 개요

본 프로젝트는 **외부 CSS 프레임워크 없이** 순수 CSS Custom Properties (CSS 변수) 기반의 디자인 토큰 시스템을 구축한다.
모든 색상은 `web/css/variables.css`의 `:root`에 선언되며, 다른 파일은 토큰만 참조한다.

---

## 2. 핵심 색상 팔레트 — 전수 목록

### 2-1. 브랜드 컬러 (Brand)

| 토큰 | HEX / RGBA | 용도 |
|------|-----------|------|
| `--brand` | `#0176D3` | U2DIA 기본 브랜드 블루 |
| `--brand-light` | `#1B96FF` | 강조·링크·활성 요소 |
| `--brand-dark` | `#014486` | 호버·눌림 상태 |
| `--brand-bg` | `rgba(27,150,255,0.08)` | 브랜드 색상 배경 틴트 |

### 2-2. 배경 레이어 (Background)

| 토큰 | HEX / RGBA | 밝기 순위 | 용도 |
|------|-----------|---------|------|
| `--bg-sunken` | `#13151C` | 0 (극심층) | CLI 헤더, 사이드바 헤더 |
| `--bg` | `#16181D` | 1 (최심층) | 페이지 기본 배경 |
| `--bg-elevated` | `#1C1F26` | 2 | 헤더 바, 푸터, CLI 패널 |
| `--panel` | `#22252E` | 3 | 칸반 컬럼 배경 |
| `--card` | `#272B35` | 4 | 카드 기본 배경 |
| `--card-hover` | `#2E323E` | 5 | 카드 호버 배경 |
| `--surface-raised` | `#2E323E` | 5 | 올라온 서피스 |
| `--surface-sunken` | `rgba(0,0,0,0.18)` | — | 함몰 서피스 (팀카드 푸터 등) |
| `--surface-glass` | `rgba(39,43,53,0.65)` | — | 블러 패널 배경 |
| `--surface-glass-sm` | `rgba(39,43,53,0.70)` | — | 블러 카드 배경 (task-card) |

### 2-3. 텍스트 (Text)

| 토큰 | HEX | 용도 |
|------|-----|------|
| `--text` | `#ECEDEE` | 기본 텍스트 (고대비) |
| `--text-secondary` | `#8E9BAE` | 보조 텍스트 |
| `--muted` | `#5E6C84` | 약화 텍스트 (레이블, 메타) |
| `--text-inverse` | `#16181D` | 밝은 배경 위 텍스트 |
| `--text-muted` (별칭) | `→ --muted` | 사이드바·CLI 레이블 |

### 2-4. 테두리 / 구분선 (Border)

| 토큰 | RGBA | 용도 |
|------|-----|------|
| `--line` | `rgba(255,255,255,0.05)` | 기본 테두리 |
| `--line-light` | `rgba(255,255,255,0.08)` | 강조 테두리 |
| `--line-focus` | `→ --brand-light` | 포커스 테두리 |
| `--divider` | `rgba(255,255,255,0.03)` | 로그 항목 구분선 |
| `--line-solid` | `#2a2f3e` | 불투명 테두리 (스크롤바) |
| `--border-glass` | `rgba(255,255,255,0.06)` | 블러 패널 테두리 |
| `--border-hover` | `rgba(255,255,255,0.10)` | 호버 시 테두리 강조 |
| `--border-subtle` | `rgba(255,255,255,0.03)` | 극미세 구분선 |
| `--border-mid` | `rgba(255,255,255,0.04)` | 중간 구분선 |
| `--border-strong` | `rgba(255,255,255,0.08)` | 강조 구분선 |

### 2-5. 시맨틱 컬러 (Semantic)

| 토큰 | HEX | 배경 토큰 | 배경 RGBA | 용도 |
|------|-----|---------|---------|------|
| `--green` | `#4BCA81` | `--green-bg` | `rgba(75,202,129,0.10)` | 성공·Done·완료 |
| `--red` | `#EA001E` | `--red-bg` | `rgba(234,0,30,0.08)` | 오류·Blocked·위험 |
| `--red-light` | `#FF5D2D` | — | — | 삭제 버튼·오류 강조 |
| `--orange` | `#FE9339` | `--orange-bg` | `rgba(254,147,57,0.08)` | 경고·Review·High |
| `--yellow` | `#E4A201` | `--yellow-bg` | `rgba(228,162,1,0.08)` | 주의·Medium·별점 |
| `--yellow-light` | `#FCC003` | — | — | 노란색 강조 |
| `--cyan` | `#1FC9E8` | `--cyan-bg` | `rgba(31,201,232,0.08)` | 에이전트·SSE·파일명 |
| `--purple` | `#8B5CF6` | `--purple-bg` | `rgba(139,92,246,0.08)` | 시스템·ToDo 컬럼 |
| `--purple-light` | `#A78BFA` | — | — | 퍼플 강조 |

### 2-6. 차트 팔레트 (Chart)

| 토큰 | HEX | 로그 `data-type` 용도 |
|------|-----|-----------------|
| `--chart-blue` | `#1B96FF` | `ticket_status` 로그 |
| `--chart-green` | `#4BCA81` | `ticket_created` 로그, 터미널 정보 |
| `--chart-red` | `#FF5D2D` | 이슈·오류 텍스트 |
| `--chart-orange` | `#FE9339` | `artifact_created` 로그, 히스토리 리뷰 |
| `--chart-purple` | `#8B5CF6` | `team_created` 로그, 스폰 피드 |
| `--chart-cyan` | `#1FC9E8` | `member_spawned` 로그, 파일명 |
| `--chart-yellow` | `#E4A201` | `feedback_created` 로그 |
| `--chart-lime` | `#84CC16` | 예약 |
| `--chart-gray` | `#5E6C84` | `team_archived` 로그 |
| `--chart-pink` | `#E0479E` | 예약 |
| `--chart-indigo` | `#5A67D8` | 예약 |

### 2-7. 배지 틴트 & 호버 미세 배경

| 토큰 | RGBA | 용도 |
|------|-----|------|
| `--yellow-tint` | `rgba(228,162,1,0.14)` | Ralph r1 배지 배경 |
| `--orange-tint` | `rgba(254,147,57,0.14)` | Ralph r2 배지 배경 |
| `--orange-bg-faint` | `rgba(254,147,57,0.04)` | Ralph 로그 행 배경 |
| `--red-tint` | `rgba(234,0,30,0.12)` | Ralph r-max 배지 배경 |
| `--bg-hover` | `rgba(255,255,255,0.04)` | 일반 항목 호버 |
| `--bg-hover-subtle` | `rgba(255,255,255,0.015)` | 로그 항목 호버 |
| `--bg-hover-micro` | `rgba(255,255,255,0.02)` | 피드 항목 호버 |

---

## 3. 칸반 컬럼 색상 매핑

### 3-1. 컬럼 기본 색상 토큰

| 상태 | 토큰 | HEX |
|------|------|-----|
| Backlog | `--col-backlog` | `#5E6C84` |
| ToDo | `--col-todo` | `#8B5CF6` |
| InProgress | `--col-inprogress` | `#1B96FF` |
| Review | `--col-review` | `#FE9339` |
| Done | `--col-done` | `#4BCA81` |
| Blocked | `--col-blocked` | `#EA001E` |

### 3-2. 컬럼 영역별 투명도 토큰 (상태 × 4영역)

| 상태 | 컬럼 배경 (`-bg`) | 컬럼 테두리 (`-border`) | 헤더 배경 (`-header-bg`) | 카운트 배지 (`-count-bg`) |
|------|---------------|------------------|---------------------|-------------------|
| Backlog | `rgba(94,108,132,0.08)` | `rgba(94,108,132,0.15)` | `rgba(94,108,132,0.12)` | `rgba(94,108,132,0.15)` |
| ToDo | `rgba(139,92,246,0.08)` | `rgba(139,92,246,0.15)` | `rgba(139,92,246,0.12)` | `rgba(139,92,246,0.15)` |
| InProgress | `rgba(27,150,255,0.08)` | `rgba(27,150,255,0.15)` | `rgba(27,150,255,0.12)` | `rgba(27,150,255,0.15)` |
| Review | `rgba(254,147,57,0.08)` | `rgba(254,147,57,0.15)` | `rgba(254,147,57,0.12)` | `rgba(254,147,57,0.15)` |
| Done | `rgba(75,202,129,0.08)` | `rgba(75,202,129,0.15)` | `rgba(75,202,129,0.12)` | `rgba(75,202,129,0.15)` |
| Blocked | `rgba(234,0,30,0.08)` | `rgba(234,0,30,0.15)` | `rgba(234,0,30,0.12)` | `rgba(234,0,30,0.15)` |

### 3-3. 헤더 색상 적용 방식

```css
/* 헤더 배경 = --col-{status}-header-bg  (불투명도 12%) */
/* 헤더 하단 강조선 = --col-{status}  (solid HEX) */
/* 헤더 텍스트 = --col-{status}  (solid HEX) */
/* 카운트 배지 배경 = --col-{status}-count-bg  (불투명도 15%) */
/* 카운트 배지 텍스트 = --col-{status}  (solid HEX) */
```

**드롭 타겟 상태** (드래그 오버 시):
- 배경: `rgba(27,150,255,0.08)` (`--brand-bg`)
- 테두리: `#0176D3` (`--brand`)

---

## 4. 카드 색상 매핑

### 4-1. 칸반 카드 (`kb-card`)

| 속성 | 토큰 | 실제 값 |
|------|------|--------|
| 배경 | `--card` | `#272B35` |
| 테두리 | `--color-border` → `--line` | `rgba(255,255,255,0.05)` |
| 호버 테두리 | `--brand` | `#0176D3` |
| 호버 그림자 | `--shadow-sm` | `0 2px 4px rgba(0,0,0,0.20)` |
| 라이브 카드 테두리 | `--brand` | `#1B96FF` (!important) |
| 라이브 카드 글로우 | `--shadow-brand-glow` | `0 0 0 1px rgba(27,150,255,0.25)` |

### 4-2. 태스크 카드 (`task-card` — 글래스모피즘)

| 속성 | 토큰 | 실제 값 |
|------|------|--------|
| 배경 | `--surface-glass-sm` | `rgba(39,43,53,0.70)` |
| backdrop-filter | `blur(8px)` | — |
| 테두리 | `--line` | `rgba(255,255,255,0.05)` |
| 호버 테두리 | `--border-hover` | `rgba(255,255,255,0.10)` |

### 4-3. 우선순위별 좌측 강조선

| 우선순위 | 색상 토큰 | HEX |
|---------|---------|-----|
| Critical | `--red` | `#EA001E` |
| High | `--orange` | `#FE9339` |
| Medium | `--yellow` | `#E4A201` |
| Low | `--green` | `#4BCA81` |

### 4-4. 에이전트 아바타 / 진행상태 표시

| 요소 | 배경 토큰 | 텍스트/색상 토큰 |
|------|---------|------------|
| 아바타 (`kb-card-avatar`) | `--cyan-bg` = `rgba(31,201,232,0.08)` | `--cyan` = `#1FC9E8` |
| 라이브 점 (`kb-live-dot`) | `--green` = `#4BCA81` | — |
| 진행 텍스트 (`kb-progress-text`) | — | `--text-secondary` = `#8E9BAE` |
| 진행 컨테이너 | `--brand-bg` = `rgba(27,150,255,0.08)` | — |
| 진행 컨테이너 좌측선 | `--brand` = `#0176D3` | — |

---

## 5. 상태 배지 / 우선순위 라벨

### 5-1. 상태 배지 (`.status-badge`)

| 클래스 | 배경 토큰 | 배경 HEX | 텍스트 토큰 | 텍스트 HEX |
|--------|---------|---------|----------|---------|
| `.status-Backlog` | `--col-backlog-header-bg` | `rgba(94,108,132,0.12)` | `--muted` | `#5E6C84` |
| `.status-Todo` | `--purple-bg` | `rgba(139,92,246,0.08)` | `--purple` | `#8B5CF6` |
| `.status-InProgress` | `--brand-bg` | `rgba(27,150,255,0.08)` | `--brand-light` | `#1B96FF` |
| `.status-Review` | `--orange-bg` | `rgba(254,147,57,0.08)` | `--orange` | `#FE9339` |
| `.status-Done` | `--green-bg` | `rgba(75,202,129,0.10)` | `--green` | `#4BCA81` |
| `.status-Blocked` | `--red-bg` | `rgba(234,0,30,0.08)` | `--red-light` | `#FF5D2D` |

### 5-2. 우선순위 라벨 (`.pri`)

| 클래스 | 배경 토큰 | 배경 HEX | 텍스트 토큰 | 텍스트 HEX |
|--------|---------|---------|----------|---------|
| `.pri-Critical` | `--red-bg` | `rgba(234,0,30,0.08)` | `--red-light` | `#FF5D2D` |
| `.pri-High` | `--orange-bg` | `rgba(254,147,57,0.08)` | `--orange` | `#FE9339` |
| `.pri-Medium` | `--yellow-bg` | `rgba(228,162,1,0.08)` | `--yellow` | `#E4A201` |
| `.pri-Low` | `--green-bg` | `rgba(75,202,129,0.10)` | `--green` | `#4BCA81` |

---

## 6. 네비게이션 & 사이드바 색상 매핑

### 6-1. 네비게이션 바

| 토큰 | 참조 토큰 | 실제 HEX/RGBA |
|------|---------|------------|
| `--nav-bg` | `--bg-elevated` | `#1C1F26` |
| `--nav-text` | `--text-secondary` | `#8E9BAE` |
| `--nav-border` | `--line` | `rgba(255,255,255,0.05)` |
| `--nav-active-bg` | `--brand-bg` | `rgba(27,150,255,0.08)` |
| `--nav-active-border` | `--brand` | `#0176D3` |
| `--nav-active-text` | `--brand-light` | `#1B96FF` |
| 로고 아이콘 배경 | `--brand` | `#0176D3` |
| 로고 아이콘 텍스트 | 하드코딩 | `#fff` |

### 6-2. 사이드바

| 토큰 | 참조 토큰 | 실제 HEX/RGBA |
|------|---------|------------|
| `--sidebar-bg` | `--bg-elevated` | `#1C1F26` |
| `--sidebar-header-bg` | `--bg-sunken` | `#13151C` |
| `--sidebar-border` | `--line` | `rgba(255,255,255,0.05)` |
| `--sidebar-active-bg` | `--brand-bg` | `rgba(27,150,255,0.08)` |
| `--sidebar-active-border` | `--brand` | `#0176D3` |
| `--sidebar-active-text` | `--brand-light` | `#1B96FF` |

---

## 7. 버튼 색상 매핑

| 변형 | 배경 HEX | 호버 배경 HEX | 테두리 | 텍스트 |
|------|---------|------------|------|------|
| 기본 | `#272B35` | `#2E323E` | `rgba(255,255,255,0.08)` | `#ECEDEE` |
| Primary | `#0176D3` | `#014486` | `#0176D3` | `#fff` |
| Primary active | `#012f5e` | — | — | — |
| Secondary | `#22252E` | `#272B35` | `rgba(255,255,255,0.08)` | `#8E9BAE` |
| Danger | `#EA001E` | `#c2001a` | `#EA001E` | `#fff` |
| Ghost | `transparent` | `rgba(255,255,255,0.05)` | `transparent` | `#8E9BAE` |
| Disabled | `rgba(255,255,255,0.04)` | — | `transparent` | `#5E6C84` |

---

## 8. 폼 입력 색상

| 속성 | 토큰 | 실제 값 |
|------|------|--------|
| 배경 | `--input-bg` → `--bg-elevated` | `#1C1F26` |
| 테두리 기본 | `--input-border` → `--line-light` | `rgba(255,255,255,0.08)` |
| 테두리 포커스 | `--input-border-focus` → `--brand-light` | `#1B96FF` |
| 텍스트 | `--input-text` → `--text` | `#ECEDEE` |
| 플레이스홀더 | `--input-placeholder` → `--muted` | `#5E6C84` |
| 포커스 링 | `--shadow-focus` | `0 0 0 3px rgba(27,150,255,0.35)` |

---

## 9. 모달 색상 매핑

| 속성 | 토큰 | 실제 값 |
|------|------|--------|
| 배경 | `--modal-bg` → `--bg-elevated` | `#1C1F26` |
| 오버레이 | `--modal-overlay-bg` | `rgba(0,0,0,0.65)` |
| 테두리 | `--modal-border` → `--line` | `rgba(255,255,255,0.05)` |
| 활성 탭 텍스트 | `--brand-light` | `#1B96FF` |
| 활성 탭 밑줄 | `--brand-light` | `#1B96FF` |
| 닫기 버튼 호버 배경 | `--red-bg` | `rgba(234,0,30,0.08)` |
| 닫기 버튼 호버 텍스트 | `--red-light` | `#FF5D2D` |

---

## 10. CLI 패널 색상 매핑

### 10-1. 구조 색상

| 요소 | 배경 | 테두리 |
|------|------|------|
| 패널 전체 | `--bg-elevated` = `#1C1F26` | `--line` (상단) |
| 헤더 행 | `--bg-sunken` = `#13151C` | `--line` (하단) |
| 입력 행 | `--bg-sunken` = `#13151C` | `--line` (상단) |
| 리사이저 | `--line` → 호버: `--brand` = `#0176D3` | — |

### 10-2. 로그 타입별 색상

| 타입 클래스 | 좌측 강조선 | 메시지 색상 | 배경 |
|-----------|-----------|----------|-----|
| `.log-user` | `#0176D3` | `#0176D3` | — |
| `.log-system` | `#8B5CF6` | `#8B5CF6` | — |
| `.log-sse` | `#1FC9E8` | `#1FC9E8` | — |
| `.log-success` | `#4BCA81` | `#4BCA81` | — |
| `.log-warn` | `#E4A201` | `#E4A201` | — |
| `.log-error` | `#EA001E` | `#EA001E` | — |
| `.log-ralph` | `#FE9339` | `#FE9339` | `rgba(254,147,57,0.04)` |

### 10-3. Ralph 배지 (`.cli-ralph-badge`)

| 클래스 | 배경 | 텍스트 |
|--------|------|------|
| `.ok` | `rgba(75,202,129,0.10)` | `#4BCA81` |
| `.warn` | `rgba(228,162,1,0.08)` | `#E4A201` |
| `.block` | `rgba(234,0,30,0.08)` | `#EA001E` |

---

## 11. 글로벌 피드 색상 매핑

| 피드 타입 클래스 | 좌측 강조선 토큰 | HEX |
|--------------|-------------|-----|
| `.feed-status` | `--chart-orange` | `#FE9339` |
| `.feed-artifact` | `--yellow` | `#E4A201` |
| `.feed-feedback` | `--green` | `#4BCA81` |
| `.feed-error` | `--red` | `#EA001E` |
| `.feed-warn` | `--yellow` | `#E4A201` |
| `.feed-spawn` | `--chart-purple` | `#8B5CF6` |
| `.feed-team` | `--chart-blue` | `#1B96FF` |

---

## 12. 액티비티 로그 좌측 강조선

| `data-type` 속성값 | 강조선 토큰 | HEX |
|-----------------|----------|-----|
| `ticket_status` | `--chart-blue` | `#1B96FF` |
| `ticket_created` | `--chart-green` | `#4BCA81` |
| `member_spawned` | `--chart-cyan` | `#1FC9E8` |
| `team_created` | `--chart-purple` | `#8B5CF6` |
| `team_archived` | `--chart-gray` | `#5E6C84` |
| `artifact_created` | `--chart-orange` | `#FE9339` |
| `feedback_created` | `--chart-yellow` | `#E4A201` |

---

## 13. 그라디언트 토큰

| 토큰 | 값 |
|------|---|
| `--grad-blue` | `linear-gradient(135deg, #1B96FF, #0176D3)` |
| `--grad-green` | `linear-gradient(135deg, #4BCA81, #2E844A)` |
| `--grad-red` | `linear-gradient(135deg, #FF5D2D, #EA001E)` |
| `--grad-purple` | `linear-gradient(135deg, #A78BFA, #8B5CF6)` |
| `--grad-cyan` | `linear-gradient(135deg, #1FC9E8, #0D9DDA)` |
| `--grad-orange` | `linear-gradient(135deg, #FE9339, #DD7A01)` |

---

## 14. 표준 시맨틱 API 별칭 (`--color-*`)

외부 컴포넌트 호환성을 위한 표준 네이밍 별칭.

| 표준 토큰 | 참조 토큰 | 실제 값 |
|---------|---------|--------|
| `--color-primary` | `--brand` | `#0176D3` |
| `--color-secondary` | `--purple` | `#8B5CF6` |
| `--color-bg` | `--bg` | `#16181D` |
| `--color-surface` | `--card` | `#272B35` |
| `--color-text` | `--text` | `#ECEDEE` |
| `--color-border` | `--line` | `rgba(255,255,255,0.05)` |
| `--color-accent` | `--brand-light` | `#1B96FF` |

---

## 15. 하드코딩된 색상 — 토큰화 권장 목록

토큰 대신 직접 HEX/RGBA로 기재된 색상. 향후 정리 대상.

| 위치 | 파일 | 하드코딩 값 | 권장 토큰 |
|------|------|-----------|---------|
| `.git-card-done` 배경 | `components.css` | `rgba(34,197,94,0.04)` | `--green-bg` 계열 |
| `.git-card-blocked` 배경 | `components.css` | `rgba(239,68,68,0.04)` | `--red-bg` 계열 |
| `.git-artifact-type` 배경 | `components.css` | `rgba(245,158,11,0.1)` | `--orange-tint` |
| `.td-filename` fallback | `layout.css` | `#06b6d4` | `--chart-cyan` |
| `.td-changes` fallback | `layout.css` | `#22c55e` | `--chart-green` |
| `.td-issues` fallback | `layout.css` | `#ef4444` | `--chart-red` |
| `.ticket-detail-modal` bg fallback | `layout.css` | `#1e2028` | `--bg-elevated` |
| `.kanban-card-progress-anim` fallback | `layout.css` | `#06b6d4` | `--chart-cyan` |
| `.tl-dot` border fallback | `components.css` | `#0d1117` | `--bg` |
| `.dash-team-card.complete` 글로우 | `components.css` | `rgba(75,202,129,0.2)` | `--green-bg` 강화 |
| `.mk-seg` 텍스트 | `components.css` | `#fff` | `--btn-primary-text` |
| 모달 박스섀도우 | `layout.css` | `rgba(0,0,0,0.5)` | `--shadow-xl` 계열 |

---

## 16. 파일별 역할 요약

| 파일 | 역할 | 색상 관련 내용 |
|------|------|------------|
| `variables.css` | **토큰 선언 전용** | 모든 CSS 변수 정의 (~280줄) |
| `kanban.css` | 칸반 컬럼·카드 | 상태별 6색 컬럼 색상 적용 |
| `components.css` | 공통 UI 컴포넌트 | 배지, 버튼, 모달, 로그 강조선 |
| `layout.css` | 레이아웃 구조 | 대시보드 패널, 팀 카드, 티켓 리스트 |
| `sidebar.css` | 사이드바 | 항목 활성/비활성 색상 |
| `cli.css` | CLI 패널 | 로그 타입별 7가지 색상, Ralph 배지 |

---

*본 문서는 티켓 `tkt-9ab3076d` — "칸반보드 현재 CSS 색상 체계 분석 및 디자인 토큰 정리" 작업 산출물입니다.*
