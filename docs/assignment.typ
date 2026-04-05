// ─────────────────────────────────────────────────
// U2DIA AI Kanban Board — 과제 제출용 소개 문서
// ─────────────────────────────────────────────────

#set document(
  title: "U2DIA AI Server Agent — AI 에이전트 팀 협업 칸반보드",
  author: "U2DIA",
)

#set page(
  paper: "a4",
  margin: (top: 2.5cm, bottom: 2.5cm, left: 2cm, right: 2cm),
)

#set text(font: "Noto Sans CJK KR", size: 10.5pt, lang: "ko")
#set par(justify: true, leading: 0.8em)
#set heading(numbering: "1.1")

// ── 색상 정의 ──
#let accent = rgb("#4F8EF7")
#let accent-dark = rgb("#2D5FBE")
#let bg-light = rgb("#F0F4FF")
#let gray-text = rgb("#555555")

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  표지
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#page(margin: (top: 3cm, bottom: 3cm, left: 2.5cm, right: 2.5cm))[
  #align(center)[
    #v(2cm)

    #image("logo_u2dia.png", width: 35%)

    #v(1.2cm)

    #text(size: 28pt, weight: "bold", fill: accent-dark)[
      U2DIA AI Server Agent
    ]

    #v(0.3cm)

    #text(size: 14pt, fill: gray-text)[
      AI 에이전트 팀의 병렬 개발을 실시간 모니터링하는\
      엔터프라이즈급 칸반보드 시스템
    ]

    #v(1.5cm)

    #line(length: 60%, stroke: 1pt + accent)

    #v(1cm)

    #text(size: 12pt)[
      #table(
        columns: (auto, auto),
        align: (right, left),
        stroke: none,
        inset: (x: 12pt, y: 6pt),
        [*과목*], [소프트웨어 공학],
        [*제출자*], [U2DIA],
        [*제출일*], [2026년 3월 28일],
        [*GitHub*], [#link("https://github.com/U2SY26/U2DIA-KANBAN-BOARD")[U2SY26/U2DIA-KANBAN-BOARD]],
        [*버전*], [v7.0.0],
      )
    ]

    #v(2cm)

    #rect(
      fill: bg-light,
      radius: 8pt,
      inset: 16pt,
      width: 80%,
    )[
      #align(center)[
        #text(size: 9pt, fill: gray-text)[
          본 프로젝트는 오픈소스로 공개되어 있습니다.\
          Python 표준 라이브러리만으로 구동되며 외부 의존성이 없습니다.\
          서버 단일 파일 11,175줄 · 37 커밋 · 개발 기간 7일
        ]
      ]
    ]
  ]
]


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  목차
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#page[
  #outline(title: [목차], indent: 1.5em, depth: 2)
]


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  본문
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

= 프로젝트 개요

== 배경 및 동기

AI 코딩 에이전트(Claude Code, Cursor 등)가 실제 개발 현장에 투입되면서, 복수의 AI 에이전트가 동시에 하나의 프로젝트를 작업하는 *병렬 에이전트 개발* 패러다임이 등장했다. 그러나 기존 프로젝트 관리 도구(Jira, Trello 등)는 사람 중심으로 설계되어 있어, AI 에이전트의 고속 작업 흐름을 실시간으로 추적하기 어려웠다.

*U2DIA AI Server Agent*는 이 문제를 해결하기 위해 탄생한 *AI 에이전트 전용 칸반보드 시스템*이다.

== 핵심 목표

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt + luma(200),
  inset: 10pt,
  fill: (x, y) => if y == 0 { bg-light } else { none },
  [*목표*], [*설명*],
  [실시간 모니터링], [SSE(Server-Sent Events)로 에이전트 작업 상태를 밀리초 단위로 추적],
  [MCP 프로토콜], [JSON-RPC 2.0 기반 MCP로 어떤 AI 에이전트든 연동 가능],
  [제로 의존성], [Python 표준 라이브러리만 사용 — pip install 없이 즉시 실행],
  [자동 QA], [로컬 LLM(Ollama gemma3:27b)으로 코드 품질 자동 검수],
  [멀티플랫폼], [웹 SPA + Electron 데스크톱 + Flutter 모바일 앱],
)


= 시스템 아키텍처

== 전체 구조

```
┌─────────────────────────────────────────────────────────────┐
│                    U2DIA AI Server Agent                     │
│                      (server.py 단일 파일)                    │
├──────────┬──────────┬──────────┬──────────┬─────────────────┤
│ REST API │   MCP    │   SSE    │  Auth    │  Supervisor QA  │
│ (17 EP)  │(JSON-RPC)│(실시간)  │ (Token)  │ (Ollama LLM)   │
├──────────┴──────────┴──────────┴──────────┴─────────────────┤
│                    SQLite (WAL Mode)                         │
└─────────────────────────────────────────────────────────────┘
         ▲              ▲              ▲
         │              │              │
    ┌────┴───┐    ┌────┴───┐    ┌────┴───┐
    │ Web    │    │Electron│    │Flutter │
    │ SPA    │    │Desktop │    │Mobile  │
    └────────┘    └────────┘    └────────┘
```

== 기술 스택

#grid(
  columns: (1fr, 1fr),
  gutter: 12pt,
  rect(fill: bg-light, radius: 6pt, inset: 12pt, width: 100%)[
    *백엔드*
    - Python 3.8+ (표준 라이브러리만)
    - `http.server.ThreadingHTTPServer`
    - SQLite WAL 모드 (동시 접근 안전)
    - SSE 실시간 이벤트 푸시
    - MCP (JSON-RPC 2.0) 프로토콜
  ],
  rect(fill: bg-light, radius: 6pt, inset: 12pt, width: 100%)[
    *프론트엔드*
    - Vanilla JS/CSS SPA (CDN 없음)
    - 다크 모드 대시보드
    - Activity Heatmap / 차트
    - 반응형 칸반보드
    - 토큰 사용량 시각화
  ],
  rect(fill: bg-light, radius: 6pt, inset: 12pt, width: 100%)[
    *데스크톱 (Electron)*
    - Server Manager: 서버/토큰/메트릭 관리
    - Frontend Viewer: 칸반보드 뷰어
    - 시스템 트레이 통합
  ],
  rect(fill: bg-light, radius: 6pt, inset: 12pt, width: 100%)[
    *모바일 (Flutter)*
    - Android APK/AAB 빌드
    - 실시간 대시보드 조회
    - 티켓 관리 및 채팅
    - Ollama AI 채팅 통합
  ],
)


= 주요 기능

== 칸반보드 워크플로우

에이전트의 작업 생명주기를 6단계 칸반 파이프라인으로 관리한다:

#align(center)[
  #rect(fill: bg-light, radius: 8pt, inset: 14pt)[
    #text(size: 9.5pt)[
      *Open* #sym.arrow.r *In Progress* #sym.arrow.r *Review* #sym.arrow.r *QA (자동 검수)* #sym.arrow.r *Done* #sym.arrow.r *Archive*
    ]
  ]
]

- *Open*: 티켓 생성, 에이전트 할당 대기
- *In Progress*: 에이전트가 claim하여 작업 진행
- *Review*: 산출물(artifact) 등록 후 검수 요청
- *QA*: Ollama gemma3:27b가 자동 품질 검수 (1~5점)
- *Done*: 검수 통과 (3점 이상)
- *Blocked*: 재작업 3회 초과 시 에스컬레이션

== MCP (Model Context Protocol) 연동

MCP는 AI 에이전트가 외부 도구와 통신하는 표준 프로토콜이다. 본 시스템은 17개의 MCP 도구를 제공하여, 어떤 프로젝트의 Claude Code 에이전트든 칸반보드에 연결할 수 있다.

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt + luma(200),
  inset: 8pt,
  fill: (x, y) => if y == 0 { bg-light } else { none },
  [*MCP 도구*], [*기능*],
  [`kanban_team_create`], [팀 생성 (프로젝트 그룹별 분류)],
  [`kanban_ticket_create`], [작업 티켓 생성 (우선순위, 의존성 설정)],
  [`kanban_ticket_claim`], [에이전트가 티켓 수임],
  [`kanban_message_create`], [에이전트 간 메시지 교환],
  [`kanban_artifact_create`], [산출물(코드, 문서 등) 등록],
  [`kanban_supervisor_review`], [AI 자동 품질 검수 요청],
  [`kanban_auto_scaffold`], [프로젝트 구조 자동 스캔 후 티켓 생성],
)

#text(size: 9pt, fill: gray-text)[
  _외 10개 도구: team_list, board_get, team_stats, member_spawn, ticket_status, message_list, artifact_list, activity_log, feedback_create/list/summary, supervisor_stats_
]

== Supervisor QA 시스템

로컬 LLM(Ollama gemma3:27b)을 활용한 *자동 코드 품질 검수* 시스템:

+ *Review 상태* 티켓을 자동으로 감지
+ 산출물(artifact)을 LLM에게 전달하여 검수
+ 1~5점 척도로 판정 (3점 이상 통과, 2점 이하 재작업)
+ 재작업 3회 초과 시 *Blocked* 에스컬레이션
+ 10분 주기 상주 에이전트로 자동 순회

== 실시간 대시보드

SSE(Server-Sent Events)를 통해 브라우저에 실시간으로 데이터를 푸시한다.

#figure(
  image("screenshots/dashboard.png", width: 95%),
  caption: [실시간 대시보드 — 팀/에이전트/티켓 현황, Activity Heatmap, 토큰 사용량],
)

대시보드는 다음 지표를 실시간으로 표시한다:
- 팀 수, 활성 에이전트 수, 티켓 완료율
- 48시간 Activity Heatmap (10분 단위)
- 24시간 Ticket Activity 그래프
- 누적 토큰 사용량 및 비용 추적
- Live Feed (에이전트 활동 로그)

== 인증 및 보안

- Bearer 토큰 기반 인증 (CRUD API 제공)
- 클라이언트 연결 모니터링
- IP 기반 접근 제어 (Tailscale 대역 신뢰)
- 토큰별 권한 격리


= 거버넌스 모델

본 프로젝트는 *헌법 모델(Constitution Model) v3.0*을 적용한다. 기존의 화이트리스트/블랙리스트 방식 대신, 최소한의 불변 원칙만 정의하고 에이전트에게 최대한의 자율성을 부여한다.

== 6가지 불변 원칙

#enum(
  [*투명성* — 모든 작업은 칸반보드에 기록되어야 한다],
  [*원자적 완결성* — 하나의 티켓 = 하나의 에이전트 = 하나의 세션],
  [*의존성 무결성* — 선행 작업 미완료 시 착수 불가],
  [*협업적 자율성* — 오케스트레이터가 조율하되, 방법론은 에이전트의 자유],
  [*역할 범위* — 정의된 전문 분야 내에서만 작업],
  [*올라마 게이트키퍼* — LLM이 품질 검수, 정보 중계, 작업 조율을 담당],
)

이 거버넌스 모델은 AI 에이전트의 능력을 100% 발휘할 수 있도록 설계되었으며, "규제가 아닌 헌법"이라는 철학을 따른다.


= 기술적 도전과 해결

== 단일 파일 11,175줄 서버

`server.py` 하나로 REST API, MCP, SSE, 인증, SQLite, Supervisor QA를 모두 구현했다. 외부 프레임워크(Flask, FastAPI 등) 없이 Python 표준 라이브러리의 `http.server`만으로 엔터프라이즈급 기능을 달성한 점이 기술적 도전이었다.

*해결 전략*:
- `ThreadingHTTPServer`로 동시 접속 처리
- SQLite WAL 모드로 읽기/쓰기 동시성 확보
- 라우팅 테이블 패턴 매칭으로 URL 디스패치 구현
- SSE 커넥션 풀링으로 실시간 이벤트 브로드캐스트

== 제로 의존성 철학

```bash
# 설치 과정 — 이것이 전부다
python server.py
```

pip install이 필요 없다. Python 3.8 이상이 설치된 어떤 환경에서든 즉시 실행 가능하다. 이는 AI 에이전트가 새 환경에 배포될 때 의존성 충돌 없이 바로 사용할 수 있게 하기 위한 설계 결정이다.

== SQLite WAL 모드

여러 에이전트가 동시에 티켓을 생성/업데이트할 때 데이터 무결성을 보장하기 위해 WAL(Write-Ahead Logging) 모드를 사용한다. 이를 통해 읽기 작업이 쓰기 작업을 블로킹하지 않는다.


= 프로젝트 통계

#align(center)[
  #grid(
    columns: (1fr, 1fr, 1fr),
    gutter: 12pt,
    rect(fill: bg-light, radius: 8pt, inset: 16pt, width: 100%)[
      #align(center)[
        #text(size: 24pt, weight: "bold", fill: accent)[11,175]
        #linebreak()
        #text(size: 9pt, fill: gray-text)[서버 코드 (줄)]
      ]
    ],
    rect(fill: bg-light, radius: 8pt, inset: 16pt, width: 100%)[
      #align(center)[
        #text(size: 24pt, weight: "bold", fill: accent)[17]
        #linebreak()
        #text(size: 9pt, fill: gray-text)[MCP 도구]
      ]
    ],
    rect(fill: bg-light, radius: 8pt, inset: 16pt, width: 100%)[
      #align(center)[
        #text(size: 24pt, weight: "bold", fill: accent)[0]
        #linebreak()
        #text(size: 9pt, fill: gray-text)[외부 의존성]
      ]
    ],
    rect(fill: bg-light, radius: 8pt, inset: 16pt, width: 100%)[
      #align(center)[
        #text(size: 24pt, weight: "bold", fill: accent)[4]
        #linebreak()
        #text(size: 9pt, fill: gray-text)[플랫폼 (Web, Desktop, Mobile, CLI)]
      ]
    ],
    rect(fill: bg-light, radius: 8pt, inset: 16pt, width: 100%)[
      #align(center)[
        #text(size: 24pt, weight: "bold", fill: accent)[37]
        #linebreak()
        #text(size: 9pt, fill: gray-text)[커밋]
      ]
    ],
    rect(fill: bg-light, radius: 8pt, inset: 16pt, width: 100%)[
      #align(center)[
        #text(size: 24pt, weight: "bold", fill: accent)[7일]
        #linebreak()
        #text(size: 9pt, fill: gray-text)[개발 기간]
      ]
    ],
  )
]


= 실행 방법

== 서버 실행

```bash
# 기본 실행 (포트 5555)
python server.py

# 포트 변경
python server.py --port 8080

# 브라우저 자동 열기 비활성화
python server.py --no-browser
```

== MCP 연동 (다른 프로젝트에서)

AI 에이전트 프로젝트의 `.claude/settings.json`에 다음을 추가한다:

```json
{
  "mcpServers": {
    "kanban": {
      "type": "url",
      "url": "http://localhost:5555/mcp",
      "headers": {
        "Authorization": "Bearer YOUR-TOKEN"
      }
    }
  }
}
```

== 접속 URL

#table(
  columns: (1fr, 1fr),
  stroke: 0.5pt + luma(200),
  inset: 8pt,
  fill: (x, y) => if y == 0 { bg-light } else { none },
  [*URL*], [*용도*],
  [`http://localhost:5555/`], [전체 현황 대시보드],
  [`http://localhost:5555/#/board/{id}`], [팀별 칸반보드],
  [`http://localhost:5555/#/archives`], [아카이브],
  [`http://localhost:5555/api/...`], [REST API],
  [`http://localhost:5555/mcp`], [MCP (JSON-RPC 2.0)],
)


= 결론 및 향후 계획

*U2DIA AI Server Agent*는 AI 에이전트 시대의 프로젝트 관리 도구가 어떤 모습이어야 하는지를 실험적으로 제시하는 프로젝트이다.

*기여 포인트*:
- AI 에이전트 전용 칸반보드라는 새로운 카테고리 제안
- MCP 프로토콜을 활용한 에이전트 간 표준 통신 구현
- 로컬 LLM 기반 자동 QA 파이프라인 설계
- 헌법 모델(Constitution Model) 거버넌스 프레임워크

*향후 계획*:
- 멀티 에이전트 오케스트레이션 고도화
- 프로젝트 간 의존성 그래프 시각화
- AI 에이전트 성과 분석 리포트 자동 생성


#v(1.5cm)

#align(center)[
  #rect(
    fill: rgb("#1a1a2e"),
    radius: 10pt,
    inset: 20pt,
    width: 85%,
  )[
    #text(fill: white, size: 10pt)[
      #align(center)[
        *오픈소스 저장소*\
        #v(0.3cm)
        #text(fill: accent, size: 12pt)[
          #link("https://github.com/U2SY26/U2DIA-KANBAN-BOARD")[
            github.com/U2SY26/U2DIA-KANBAN-BOARD
          ]
        ]
        #v(0.3cm)
        #text(fill: rgb("#aaaaaa"), size: 8.5pt)[
          Star, Fork, Issue 환영합니다.
        ]
      ]
    ]
  ]
]
