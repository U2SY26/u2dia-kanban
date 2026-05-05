# Mobile VSCode Workspace (code-server) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter 앱에서 code-server 기반 풀 편집 가능 VSCode 워크스페이스를 다중 세션으로 사용하고 새 세션 spawn까지 지원. 기존 ttyd+tmux CLI Mirror는 손대지 않는다. 완료 후 AAB 빌드+Play Store production 출시.

**Architecture:**
- code-server를 워크스페이스(폴더)당 1 프로세스로 spawn (포트 풀 8100~8199, 127.0.0.1 바인드, --auth none)
- server.py가 vscode_sessions 테이블로 세션 메타데이터 관리, `/vscode/{id}/*` HTTP+WS 리버스 프록시 (`/cli` 패턴 재사용)
- Flutter 신규 `vscode_workspace_screen.dart` (CLI Mirror와 별도 화면), WebView로 임베드
- systemd user 서비스 `code-server-manager.service`로 auto-stop idle 세션 GC

**Tech Stack:** Python 3 stdlib only, code-server, SQLite WAL, Flutter webview_flutter, systemd user units, fastlane (production track)

---

## File Structure

| 파일 | 역할 | 신규/수정 |
|------|------|---------|
| `server.py` | vscode_sessions 테이블 + 5 API + 리버스 프록시 핸들러 | 수정 |
| `scripts/code-server-up.sh` | code-server 단일 워크스페이스 spawn 스크립트 | 신규 |
| `scripts/code-server-gc.sh` | idle 세션 GC (30분) | 신규 |
| `scripts/code-server-manager.service` | systemd user unit | 신규 |
| `flutter_app/lib/screens/vscode/vscode_workspace_screen.dart` | 워크스페이스 화면 (세션 리스트+WebView) | 신규 |
| `flutter_app/lib/services/api_service.dart` | vscode 세션 CRUD 메서드 추가 | 수정 |
| `flutter_app/lib/screens/home_screen.dart` | VSCode 메뉴 라우팅 추가 | 수정 |
| `flutter_app/pubspec.yaml` | versionCode +1 (auto-bump 훅) | 수정 |

---

## Task 0: 환경 셋업

**Files:** N/A (환경)

- [ ] `code-server` 설치 — `curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=$HOME/.local`
- [ ] 동작 확인 — `~/.local/bin/code-server --version`
- [ ] fastlane 설치 — `gem install --user-install fastlane` (또는 `bundle init` → Gemfile 작성)
- [ ] `fastlane --version` 동작 확인
- [ ] PATH 갱신 (`~/.gem/ruby/<ver>/bin`, `~/.local/bin`)

---

## Task 1: vscode_sessions 테이블 + DB 마이그레이션

**Files:** `server.py` (스키마 정의 영역, init_db 근처)

- [ ] **Step 1: 스키마 추가**
```sql
CREATE TABLE IF NOT EXISTS vscode_sessions (
  id TEXT PRIMARY KEY,
  path TEXT NOT NULL,
  label TEXT,
  port INTEGER UNIQUE NOT NULL,
  pid INTEGER,
  started_at INTEGER NOT NULL,
  last_active INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'running'
);
CREATE INDEX IF NOT EXISTS idx_vscode_status ON vscode_sessions(status);
```

- [ ] **Step 2: 서버 재시작 후 테이블 생성 검증** — `sqlite3 agents_team.db ".schema vscode_sessions"`

- [ ] **Step 3: 커밋** — `feat(server): add vscode_sessions table for code-server session tracking`

---

## Task 2: VSCode Session API 5종

**Files:** `server.py` (라우트 영역, /api/cli 근처)

- [ ] `GET /api/vscode/sessions` — running 세션 목록
- [ ] `POST /api/vscode/sessions` — body `{path, label?}` → 빈 포트 할당, code-server-up.sh 실행, row insert
- [ ] `DELETE /api/vscode/sessions/{id}` — pid kill, status='stopped'
- [ ] `PUT /api/vscode/sessions/{id}/touch` — last_active 갱신 (heartbeat)
- [ ] `GET /api/vscode/recent` — `~/.config/Code/User/globalStorage/storage.json` 파싱 후 최근 폴더 + 현재 칸반 프로젝트 목록(`~/github/*`) 반환
- [ ] curl 5종 모두 200 응답 검증
- [ ] 커밋 — `feat(server): add vscode session manager API`

---

## Task 3: code-server spawn/gc 스크립트

**Files:** `scripts/code-server-up.sh`, `scripts/code-server-down.sh`, `scripts/code-server-gc.sh`

- [ ] `code-server-up.sh` — 인자 `<id> <port> <path>` → `nohup code-server --bind-addr 127.0.0.1:$PORT --auth none --user-data-dir ~/.local/share/code-server/$ID --extensions-dir ~/.local/share/code-server/extensions $PATH &`
- [ ] `code-server-down.sh` — 인자 `<id>` → pid kill + user-data-dir cleanup
- [ ] `code-server-gc.sh` — last_active > 30분 idle → DELETE API 호출
- [ ] systemd timer로 5분마다 gc 실행
- [ ] 셋 모두 `chmod +x`, `bash -n` 구문 통과
- [ ] 커밋 — `feat(scripts): add code-server lifecycle scripts`

---

## Task 4: HTTP+WS 리버스 프록시 `/vscode/{id}/*`

**Files:** `server.py` (`_handle_cli_proxy` 근처에 `_handle_vscode_proxy` 신규)

- [ ] **Step 1: 라우트 추가** — `if path.startswith("/vscode/"):` → id 추출 → `_handle_vscode_proxy(id, sub)`
- [ ] **Step 2: 핸들러 작성** — id로 port 조회, http.client로 backend 요청, 헤더+body 그대로 전달, WebSocket Upgrade 시 `_handle_cli_proxy` WS 펌프 패턴 재사용
- [ ] **Step 3: 인증** — `_check_auth` 통과 + `_is_local_request` 또는 `CLI_PROXY_REMOTE_OK=1` (CLI 프록시와 동일 정책)
- [ ] **Step 4: 검증** — `curl -H "Authorization: Bearer <T>" http://localhost:5555/vscode/<id>/healthz` 200 + 브라우저 임베드 동작
- [ ] **Step 5: 커밋** — `feat(server): add /vscode/{id} HTTP+WS reverse proxy`

---

## Task 5: systemd user 서비스 `code-server-manager`

**Files:** `scripts/code-server-manager.service`, `scripts/code-server-gc.timer`

- [ ] `code-server-manager.service` — server.py의 vscode 세션 관리만 담당하는 게 아니라, gc만 cron-like로 실행
- [ ] `~/.config/systemd/user/`에 install + `systemctl --user enable --now`
- [ ] `systemctl --user status code-server-gc.timer` active 확인
- [ ] 커밋 — `feat(systemd): add code-server-gc user timer`

---

## Task 6: Flutter API 메서드 추가

**Files:** `flutter_app/lib/services/api_service.dart`

- [ ] `Future<List<Map<String, dynamic>>> vscodeSessions()` 
- [ ] `Future<Map<String, dynamic>> vscodeCreateSession(String path, {String? label})`
- [ ] `Future<void> vscodeDeleteSession(String id)`
- [ ] `Future<void> vscodeTouchSession(String id)`
- [ ] `Future<List<Map<String, dynamic>>> vscodeRecent()`
- [ ] 커밋 — `feat(app): add vscode session API client`

---

## Task 7: Flutter 화면 `vscode_workspace_screen.dart`

**Files:** `flutter_app/lib/screens/vscode/vscode_workspace_screen.dart` (신규), `flutter_app/lib/screens/home_screen.dart` (메뉴 추가)

- [ ] **Step 1: 화면 골격** — AppBar 세션 dropdown + "+" 액션, Body WebView, 30초마다 touch heartbeat
- [ ] **Step 2: "+" 시트** — recent 목록 + 직접 경로 입력 → `vscodeCreateSession` → WebView 로드
- [ ] **Step 3: 세션 close 액션** — 휴지통 아이콘 → `vscodeDeleteSession` → 목록 갱신
- [ ] **Step 4: home 메뉴 라우팅** — VSCode 카드/버튼 추가 → push route
- [ ] **Step 5: `flutter analyze` 통과**
- [ ] **Step 6: 커밋** — `feat(app): add VSCode workspace screen with multi-session support`

---

## Task 8: E2E 통합 테스트 (100% 검증)

**Files:** N/A (런타임 검증)

- [ ] code-server가 워크스페이스 1 spawn → WebView 로드 OK (브라우저로 사전 확인)
- [ ] 두 번째 워크스페이스 spawn → 세션 dropdown에 둘 다 보임
- [ ] 세션 전환 시 WebView 다시 로드 OK
- [ ] DELETE 후 WebView 에러 페이지 + 목록에서 제거
- [ ] Heartbeat 동작 확인 (last_active 갱신)
- [ ] `/cli` 기존 동작 그대로 (회귀 테스트)
- [ ] `flutter test` 통과 (있다면)
- [ ] 모든 산출물 칸반에 등록 + supervisor 검수 통과

---

## Task 9: AAB 빌드 + 검증

**Files:** `flutter_app/pubspec.yaml`

- [ ] **Step 1: versionCode bump** — pre-build hook이 자동 처리. 수동: `version: 5.22.0+131` (마이너 +1, 빌드 +1)
- [ ] **Step 2: clean** — `cd flutter_app && flutter clean`
- [ ] **Step 3: pub get** — `flutter pub get`
- [ ] **Step 4: build aab** — `flutter build appbundle --release`
- [ ] **Step 5: 산출물 확인** — `ls -lh build/app/outputs/bundle/release/app-release.aab`
- [ ] **Step 6: 사이즈/체크섬 보고**
- [ ] **Step 7: 커밋** — `chore(app): v5.22.0+131 — VSCode 워크스페이스 통합`

---

## Task 10: ⚠️ 프로덕션 출시 (사용자 컨펌 필수)

**Files:** N/A (Play Store)

- [ ] **Step 1: 사용자에게 빌드 결과 보여주고 GO/NO-GO 응답 받기**
- [ ] **Step 2: GO 시** `cd flutter_app/android && fastlane production` 실행
- [ ] **Step 3: Play Console에서 출시 상태 확인** (rollout %, errors)
- [ ] **Step 4: git push** + GitHub release 태그 (선택)
- [ ] **Step 5: 칸반 모든 티켓 Done + 팀 archive**

---

## Self-Review

**Spec coverage:**
- ✅ 풀 편집 — code-server (Task 4 WS 프록시)
- ✅ 다중 워크스페이스 — Task 1~3 (포트 풀 + 매니저)
- ✅ 새 세션 열기 — Task 7 "+" UI
- ✅ tmux 분리 — `/cli` 손대지 않음 (Task 4에서 명시)
- ✅ AAB → 프로덕션 — Task 9, 10
- ✅ 100% 확인 — Task 8 E2E

**Risks:**
- code-server 확장(Claude Code 등) Open VSX 미지원 → 모바일에선 코드 편집/리뷰만
- 모바일 키보드 가시성 — WebView 자체 동작에 의존
- WS 프록시 양방향 펌프가 stdlib만으론 까다로움 — 기존 `/cli` 구현 답습이 핵심
- 프로덕션 즉시 출시 = 롤백이 어렵다 → Task 10 사용자 컨펌 필수
