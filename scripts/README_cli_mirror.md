# Remote CLI Mirror — ttyd + tmux

PC 의 Claude Code CLI 환경을 Flutter 앱/웹 SPA에 양방향으로 미러링.

## 구성

```
PC tmux 세션 "claude"
  └─ ttyd (--writable, 127.0.0.1:7681)
       └─ Tailscale 또는 server.py /cli WS 프록시
            └─ 앱(xterm.js / xterm.dart)
```

## 사전 요구

- tmux (`apt install tmux`)
- ttyd (`~/.local/bin/ttyd`, GitHub release 정적 바이너리)

## 기동/종료

```bash
./scripts/cli-mirror-up.sh        # 127.0.0.1:7681 + tmux 세션 "claude"
./scripts/cli-mirror-down.sh      # ttyd 종료, tmux 세션 보존
CLI_MIRROR_KILL_TMUX=1 ./scripts/cli-mirror-down.sh   # tmux 세션까지 종료
```

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| CLI_MIRROR_SESSION | `claude` | tmux 세션명 |
| CLI_MIRROR_PORT | `7681` | ttyd 포트 |
| CLI_MIRROR_BIND | `127.0.0.1` | **0.0.0.0 금지** (스크립트가 거부) |
| CLI_MIRROR_WRITABLE | `1` | 양방향 (`0`이면 읽기전용) |
| CLI_MIRROR_AUTH | _(없음)_ | `user:pass` Basic Auth |
| CLI_MIRROR_LOG_DIR | `~/.local/state/cli-mirror` | 로그/PID |
| TTYD_BIN | `~/.local/bin/ttyd` | ttyd 경로 |

## 보안

- 기본 바인드는 `127.0.0.1` — 외부 노출 금지
- 외부 접근은 두 경로 중 하나:
  1. **Tailscale**: `CLI_MIRROR_BIND=<tailscale_ip>` + Basic Auth
  2. **server.py /cli WS 프록시**: 칸반 토큰으로 인증 후 ttyd로 프록시 (CLI-2 티켓)
- 0.0.0.0 / `*` / `::` 바인드는 스크립트가 차단

## systemd (자동 재시작, 선택)

```bash
mkdir -p ~/.config/systemd/user
cp scripts/cli-mirror.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now cli-mirror.service
systemctl --user status cli-mirror.service
```

## 🚀 지금 세션 끝내고 tmux로 이동하는 절차

이미 셋업 완료 상태:
- `~/.bashrc` 에 `alias cc` 추가됨 (다음 셸부터 적용)
- `~/.tmux.conf` 기본 설정 작성됨 (마우스 ON, 트루컬러, 50k 스크롤백)
- ttyd + tmux 세션 `claude` 가 기동되어 있음 (`http://127.0.0.1:7681`)

**이동 명령 (한 줄):**
```bash
exec bash         # alias 활성화
cc                # = tmux new-session -A -s claude claude
```

세션 detach 는 `Ctrl+b d`. 다시 들어가려면 그냥 `cc`.

CLI-2 (Tailscale + 인증) 와 CLI-3/4 (앱 임베드) 가 끝나면 PC 외부에서도 같은 화면을 볼 수 있게 됩니다.

## 운영 권장 — `cc` alias

매일 작업 시 tmux 부담을 0으로 만드는 한 줄 alias:

```bash
# ~/.bashrc 또는 ~/.zshrc 에 추가
alias cc='tmux new-session -A -s claude claude'
```

- `cc` 만 치면 `claude` 세션이 있으면 attach, 없으면 새로 만들어 Claude Code 시작
- 그 안에서 작업하면 앱(`/cli` 라우트)에서 같은 화면을 보면서 같이 입력 가능
- tmux 단축키 부담 줄이려면: `~/.tmux.conf` 에 `set -g mouse on`

## 동작 확인

```bash
./scripts/cli-mirror-up.sh
curl -s http://127.0.0.1:7681 | head -5     # ttyd 웹페이지 응답
tmux ls                                      # claude 세션 확인
./scripts/cli-mirror-down.sh
```

## 관련 티켓

- `T-8BA2D7` (CLI-1) ttyd + tmux 셋업 — 본 스크립트
- `T-9AC786` (CLI-2) Tailscale 바인드 + 인증 프록시
- `T-AC5224` (CLI-3) web SPA xterm.js 임베드
- `T-26273D` (CLI-4) Flutter xterm.dart 뷰
