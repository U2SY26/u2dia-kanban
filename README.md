# U2DIA AI Kanban Board

> AI 에이전트 팀의 병렬 개발을 실시간으로 모니터링하는 멀티 에이전트 협업 칸반 플랫폼.

<p align="center">
  <img src="play-assets/feature/feature-1024x500.png" alt="U2DIA AI Kanban Board" width="800"/>
</p>

<p align="center">
  <img src="play-assets/icons/icon-512.png" alt="logo" width="96"/>
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Python](https://img.shields.io/badge/python-3.8%2B-blue)
![Flutter](https://img.shields.io/badge/flutter-3.10%2B-02569B)
![Status](https://img.shields.io/badge/version-5.22.2-success)

---

## ✨ 무엇을 하는가

Claude Code · Cursor · Codex 같은 AI 코딩 에이전트들이 병렬로 일할 때, **누가 뭘 하고 있는지 한눈에 보고**, **체계적으로 협업하게** 만드는 칸반 서버입니다.

### 핵심 기능
- **실시간 칸반보드** — 팀 단위 보드, 티켓 라이프사이클(Backlog→InProgress→Review→Done), SSE 실시간 푸시
- **멀티 에이전트 협업** — 30개 역할 기반 자동 분배, 의존성 그래프
- **Sprint 관리** (gstack 패턴) — 7단계 워크플로우, 5가지 품질 게이트, 번다운/벨로시티
- **Supervisor QA** — Ollama 로컬 LLM 자동 검수, 점수 미달 시 재작업 자동 발행
- **Remote CLI Mirror** — 모바일에서 PC 터미널(tmux) 실시간 미러링
- **Mobile VSCode Workspace** — 폰/태블릿에서 풀 편집 가능한 VSCode (code-server)
- **MCP (Model Context Protocol)** — Claude Code 등 27개 도구
- **Cross-Model Code Review** — Claude · Gemini · Ollama 다중 모델 합의 리뷰
- **Agent Office (픽셀 시뮬레이션)** — 캐릭터 스프라이트로 에이전트 작업 상태 가시화
- **🎭 Demo Mode** — 서버/네트워크/계정 없이 모든 화면 체험

---

## 🚀 빠른 시작

### 모바일 앱 — 데모 모드 (가장 빠름)
1. GitHub Releases에서 최신 AAB 다운로드 → 설치
2. 첫 화면에서 **"Start Demo Mode"** 버튼 탭
3. 서버 없이 샘플 팀 3개·티켓 20개·에이전트 12명·Sprint·VSCode·CLI 모든 화면 즉시 사용

또는 로그인 화면에 `demo` / `demo` 입력해도 동일.

### 모바일 앱 — 프로덕션 모드 (자기 서버 연결)
1. PC에서 `python3 server.py` 실행
2. PC와 모바일 모두 [Tailscale](https://tailscale.com) 설치 (무료)
3. 모바일 앱 로그인 화면에서 PC의 Tailscale IP `100.x.x.x:5555` 와 발급받은 토큰 입력

> ⚠️ 외부 인터넷 직접 노출은 권장하지 않습니다. 자세한 내용은 [보안](#-보안--vpn-필수) 참조.

### 서버 (개발자/셀프호스팅)
```bash
git clone https://github.com/U2SY26/u2dia-kanban.git
cd u2dia-kanban
pip install -r requirements.txt   # 선택 — server.py 자체는 표준 라이브러리만 사용
python3 server.py                 # 기본 :5555
```

브라우저에서 http://localhost:5555/ 접속.

### Flutter 빌드 (개발자)
```bash
cd flutter_app
flutter pub get
flutter build appbundle --release
```

### 데스크톱 앱 (Electron)
```bash
cd desktop/server-manager-app && npm install && npm start
cd desktop/frontend && npm install && npm start
```

---

## 🎭 Demo Mode 상세

데모 모드는 **자격증명·서버·네트워크 없이** 앱 전체를 체험할 수 있도록 정적 mock 데이터를 사용합니다.

### 활성화 방법
- 로그인 화면 하단의 **"Start Demo Mode"** 버튼
- 또는 사용자명/비밀번호에 `demo` / `demo` 입력

### 제공되는 샘플 데이터
- 팀 3개 (`AI Agent Team`, `Sprint v2.0`, `QA Pipeline`)
- 티켓 20개 (모든 상태: InProgress·Review·Done·Backlog·Blocked)
- 에이전트 12명 (Frontend·Backend·DB·QA·Security·Architect·Mobile·Auth·Supervisor 등)
- Sprint 2개 (완료된 v1.9 + 진행 중 v2.0)
- 활동 로그 5건 + Agent Office 시뮬레이션 + VSCode/CLI 미리보기

### 표시
DEMO 모드일 때 모든 화면 상단에 노란 배너 `🎭 DEMO MODE — 샘플 데이터 (서버 미연결)` 가 표시됩니다.

---

## 🔐 보안 — VPN 필수

**이 서버는 외부 인터넷에 직접 노출하지 마세요.**

`server.py`는 단일 사용자/팀 내부용으로 설계되었으며 인증은 라이선스 토큰 기반입니다. 외부 노출 시 **반드시 VPN 또는 Tailscale 같은 오버레이 네트워크 사용**을 권장합니다.

### Tailscale 예시 (가장 쉬움)
1. PC와 모바일 모두 [Tailscale](https://tailscale.com) 설치 (무료)
2. PC: `python3 server.py` (기본 127.0.0.1)
3. 모바일 앱에 PC의 Tailscale IP(`100.x.x.x:5555`) 입력 — 끝.

암호화 + ZeroTrust + ACL이 기본 적용됩니다.

### ❌ 절대 금지
- `0.0.0.0` 바인드로 외부 직접 노출
- `service-account.json`, `.env`, DB 파일을 git에 커밋
- 동일 토큰을 여러 프로젝트에서 재사용
- 첫 빌드/테스트용 자격증명을 production에 그대로 배포 (반드시 변경)

### 환경변수
| 변수 | 용도 | 기본 |
|------|------|------|
| `KANBAN_DB_PATH` | SQLite DB 경로 | `./agent_teams.db` |
| `OPENAI_API_KEY` | OpenAI 연동 (선택) | - |
| `ANTHROPIC_API_KEY` | Claude API (선택) | - |
| `CLI_PROXY_REMOTE_OK` | CLI Mirror 외부 허용 | `0` (차단) |
| `VSCODE_PROXY_REMOTE_OK` | VSCode 워크스페이스 외부 허용 | `0` (차단) |
| `GOOGLE_APPLICATION_CREDENTIALS` | Play Store API용 service account | - |

---

## 📦 모바일 앱 (AAB) 직접 설치

GitHub Releases:
```
https://github.com/U2SY26/u2dia-kanban/releases/latest
```

### Android 설치 방법

```bash
# bundletool 다운로드
wget https://github.com/google/bundletool/releases/latest/download/bundletool-all.jar

# universal APK 생성
java -jar bundletool-all.jar build-apks \
  --bundle=u2dia-kanban-v5.22.2.aab \
  --output=app.apks --mode=universal

# 추출 + 설치
unzip app.apks -d apks
adb install apks/universal.apk
```

설치 후 **Start Demo Mode** 로 즉시 체험. 자기 서버 연결은 위 [보안](#-보안--vpn-필수) 가이드 참조.

---

## 🏗️ 아키텍처

```
서버 (Python 표준 라이브러리만)
├── server.py              단일 파일, SQLite WAL, SSE 실시간 푸시, MCP/REST API
├── web/                   Vanilla JS/CSS SPA (외부 CDN 0)
└── scripts/               cli-mirror, code-server, play-publisher 등

데스크톱 (Electron)
├── desktop/server-manager-app/   서버 관리, 토큰 CRUD, 메트릭
├── desktop/frontend/             칸반보드 뷰어
└── desktop/shared/               공유 모듈

모바일 (Flutter)
└── flutter_app/lib/
    ├── services/        api_service, auth_service, demo_data, notification
    └── screens/         kanban, agent_office, vscode, cli, sprint, dashboard, ...
```

상세는 [docs/](docs/) 참조.

---

## 🤖 MCP 통합

`.claude/settings.json`:
```json
{
  "mcpServers": {
    "kanban": {
      "type": "url",
      "url": "http://localhost:5555/mcp",
      "headers": { "Authorization": "Bearer YOUR-TOKEN-HERE" }
    }
  }
}
```

토큰 발급은 `/admin/tokens` 페이지 또는 `POST /api/tokens` API.

---

## 📚 문서

- [docs/UNIVERSAL_AGENT_RULES.md](docs/UNIVERSAL_AGENT_RULES.md) — 에이전트 헌법 (필독)
- [docs/MCP_AGENT_GUIDE.md](docs/MCP_AGENT_GUIDE.md) — MCP 에이전트 가이드
- [docs/MCP_SETUP_GUIDE.md](docs/MCP_SETUP_GUIDE.md) — MCP 설정
- [docs/REMOTE_ACCESS_GUIDE.md](docs/REMOTE_ACCESS_GUIDE.md) — 원격 접근 가이드
- [docs/ROADMAP.md](docs/ROADMAP.md) — 로드맵

---

## 🤝 기여

PR 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md) 참조.

---

## 📜 라이선스

[MIT License](LICENSE) © 2026 U2DIA

문의: u2dia@naver.com · [www.u2dia.com](https://www.u2dia.com)
