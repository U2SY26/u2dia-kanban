# U2DIA AI Agents 통합 대시보드 — 로드맵

**Version**: 1.0.0
**Last Updated**: 2026-02-25

---

## 현재 상태 (v2.1.0)

### 완료된 기능
| 기능 | 상태 | 설명 |
|------|------|------|
| 칸반보드 서버 | ✅ | Python 단일 파일, SQLite WAL, SSE 실시간 |
| MCP 17개 도구 | ✅ | 팀/티켓/메시지/산출물/피드백/채점 |
| Electron 데스크톱 앱 | ✅ | 서버 자동 관리, 시스템 트레이 |
| Windows 시작 프로그램 | ✅ | 부팅 시 자동 실행, 트레이 숨김 |
| Windows 알림 풍선 | ✅ | SSE 기반 실시간 토스트 알림 (켜기/끄기) |
| 피드백/채점 시스템 | ✅ | 점수 1~5, 카테고리별 세부 평가 |
| 범용 스킬 9개 | ✅ | 13개 프로젝트 배포 완료 |
| 범용 에이전트 5개 | ✅ | 13개 프로젝트 배포 완료 |
| 13개 프로젝트 MCP 연동 | ✅ | settings.json + CLAUDE.md 규정 |

---

## Phase 1: 데이터 영속성 강화 (v2.2.0)

### 1-A. 로컬 데이터 아카이빙

**목표**: 모든 팀 활동을 시간/프로젝트/팀/티켓 단위로 누적 저장

```
agents_team/
├── data/
│   ├── agent_teams.db          # 현재 활성 데이터 (SQLite)
│   └── archives/               # 아카이브 저장소
│       ├── 2026/
│       │   ├── 02/
│       │   │   ├── 2026-02-25_teams.jsonl     # 일별 팀 스냅샷
│       │   │   ├── 2026-02-25_activity.jsonl   # 일별 활동 로그
│       │   │   └── 2026-02-25_messages.jsonl   # 일별 대화 기록
│       │   └── ...
│       └── exports/            # 수동 내보내기
│           ├── team-{id}_full.json
│           └── project_report_2026-02.json
```

**구현 항목**:
- [ ] 시간별 자동 스냅샷 (hourly cron, SQLite → JSONL)
- [ ] 일별 아카이브 압축 (gzip)
- [ ] 팀/티켓 완료 시 자동 아카이브
- [ ] REST API: `GET /api/archives/{year}/{month}` 아카이브 조회
- [ ] REST API: `POST /api/export` 수동 내보내기 (JSON/CSV)
- [ ] 대시보드: 아카이브 브라우저 UI

### 1-B. 데이터 조회/분석 API

- [ ] `GET /api/analytics/team/{team_id}` — 팀 성과 분석
- [ ] `GET /api/analytics/timeline` — 전체 시간축 활동 그래프
- [ ] `GET /api/analytics/agent-performance` — 에이전트별 성과
- [ ] `GET /api/analytics/feedback-trends` — 피드백 트렌드

---

## Phase 2: 클라우드 연동 (v3.0.0)

### 2-A. Vercel 배포

**목표**: 칸반보드 웹 UI를 Vercel로 호스팅하여 어디서든 접근 가능

```
칸반보드 UI (Vercel)  ←→  API 서버 (로컬/클라우드)
     │
     └→ 커스텀 도메인: kanban.u2dia.com
```

**구현 항목**:
- [ ] 프론트엔드 SPA 분리 (server.py에서 HTML 추출 → Next.js 또는 Vite)
- [ ] Vercel 프로젝트 설정 및 자동 배포 (GitHub Actions)
- [ ] 커스텀 도메인 연결
- [ ] API 프록시 설정 (Vercel Serverless → 로컬 서버 터널)
- [ ] 인증 게이트 (API 키 또는 OAuth)

### 2-B. Firebase 연동

**목표**: 실시간 데이터 동기화 + 클라우드 백업

| Firebase 서비스 | 용도 |
|----------------|------|
| **Firestore** | 팀/티켓/메시지 실시간 동기화 |
| **Cloud Functions** | SSE → Firestore 브릿지 |
| **Authentication** | 사용자/팀 접근 제어 |
| **Cloud Storage** | 산출물 파일 저장 |
| **Analytics** | 사용 통계 |

**구현 항목**:
- [ ] Firebase 프로젝트 생성 및 SDK 연동
- [ ] SQLite ↔ Firestore 양방향 동기화 엔진
- [ ] 실시간 리스너 (Firestore onSnapshot → 대시보드 자동 업데이트)
- [ ] 오프라인 우선 (SQLite 로컬 → 온라인 시 Firestore 동기화)
- [ ] Cloud Functions: 알림 트리거, 자동 아카이빙

### 2-C. Supabase 연동 (대안/보조)

**목표**: PostgreSQL 기반 구조화된 데이터 저장 + 실시간 구독

| Supabase 서비스 | 용도 |
|-----------------|------|
| **PostgreSQL** | 팀/티켓/로그 영구 저장 (SQLite 대체) |
| **Realtime** | WebSocket 기반 실시간 구독 |
| **Auth** | Row Level Security (RLS) 기반 접근 제어 |
| **Edge Functions** | 서버리스 API |
| **Storage** | 산출물 바이너리 저장 |

**구현 항목**:
- [ ] Supabase 프로젝트 생성
- [ ] PostgreSQL 스키마 마이그레이션 (SQLite → PostgreSQL)
- [ ] Supabase Realtime 구독 (SSE 보완/대체)
- [ ] Row Level Security 정책 (팀별 접근 제어)
- [ ] Edge Functions: MCP 프록시

---

## Phase 3: 서버 매니저 확장 (v3.1.0)

### 설정 UI 로드맵

```
┌─────────────────────────────────────────┐
│           서버 매니저 설정                  │
├─────────────────────────────────────────┤
│ [기본 설정]                               │
│   포트: [5555]                            │
│   호스트: [0.0.0.0]                       │
│   ☑ 서버 자동 시작                         │
│   ☑ Windows 시작 시 자동 실행              │
│   ☑ 닫기 시 트레이로 최소화                │
│   ☑ 알림 표시                             │
│                                          │
│ [데이터 저장]                              │
│   로컬 DB: agent_teams.db                 │
│   ☑ 시간별 자동 아카이브                    │
│   아카이브 경로: [data/archives/]          │
│   보관 기간: [90일 ▼]                     │
│                                          │
│ [클라우드 연동] (Phase 2)                  │
│   ○ 로컬만  ● Firebase  ○ Supabase       │
│   프로젝트 ID: [__________]               │
│   ☑ 자동 동기화                            │
│   ☑ 오프라인 모드                          │
│                                          │
│ [도메인] (Phase 2)                        │
│   Vercel 도메인: [kanban.u2dia.com]       │
│   API 키: [●●●●●●●●]                     │
│   ☑ 원격 접근 허용                         │
│                                          │
│ [고급]                                    │
│   로그 레벨: [INFO ▼]                     │
│   DB WAL 모드: ☑                          │
│   최대 SSE 클라이언트: [100]              │
│                                          │
│          [저장]  [초기화]                   │
└─────────────────────────────────────────┘
```

---

## Phase 4: 멀티플랫폼 (v4.0.0)

- [ ] macOS 지원 (Electron 크로스 빌드)
- [ ] Linux 지원
- [ ] 모바일 웹뷰 (PWA)
- [ ] Flutter 모바일 앱 (선택)

---

## 데이터 저장 전략 요약

```
┌──────────────────────────────────────────────────────┐
│                    데이터 흐름                          │
├──────────────────────────────────────────────────────┤
│                                                       │
│  에이전트 (MCP)  →  server.py  →  SQLite (로컬)      │
│                        │                              │
│                        ├─→  JSONL 아카이브 (시간별)    │
│                        │     └─ data/archives/YYYY/MM  │
│                        │                              │
│                        ├─→  Firebase Firestore (동기화) │
│                        │     └─ 실시간 + 오프라인      │
│                        │                              │
│                        └─→  Supabase PostgreSQL (대안) │
│                              └─ RLS + Realtime         │
│                                                       │
│  조회: 대시보드 → Vercel (웹) / Electron (로컬)       │
│  알림: SSE → Windows Toast / Firebase Cloud Messaging │
│                                                       │
└──────────────────────────────────────────────────────┘
```

### 저장 단위

| 단위 | 저장 내용 | 보관 기간 |
|------|-----------|-----------|
| **시간** | 활동 로그 스냅샷 | 90일 (로컬) / 무제한 (클라우드) |
| **프로젝트** | 팀 목록, 누적 통계 | 무제한 |
| **팀** | 멤버, 티켓, 메시지, 산출물, 피드백 | 무제한 |
| **티켓** | 상태 이력, 소요시간, 담당자, 피드백 점수 | 무제한 |

---

## 마일스톤 타임라인

| Phase | 버전 | 핵심 기능 | 상태 |
|-------|------|-----------|------|
| 현재 | v2.1.0 | 칸반보드 + MCP + Electron + 트레이/알림 + 피드백 | ✅ 완료 |
| Phase 1 | v2.2.0 | 로컬 아카이빙, 분석 API | 🔜 다음 |
| Phase 2 | v3.0.0 | Vercel + Firebase/Supabase 클라우드 연동 | 📋 계획됨 |
| Phase 3 | v3.1.0 | 서버 매니저 확장 설정 UI | 📋 계획됨 |
| Phase 4 | v4.0.0 | 멀티플랫폼 (macOS, Linux, PWA) | 📋 계획됨 |

---

**END OF ROADMAP v1.0**
