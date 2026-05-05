# U2DIA AI SERVER AGENT — 원격 접근 가이드

**Version**: 1.0.0
**Last Updated**: 2026-02-28

---

## 1. 개요

기본적으로 서버는 `127.0.0.1` (로컬)에만 바인딩됩니다.
같은 네트워크의 다른 PC나 Tailscale VPN 기기에서 접근하려면 아래 설정이 필요합니다.

| 단계 | 설명 | 필수 여부 |
|------|------|-----------|
| 1 | 서버 바인딩을 `0.0.0.0`으로 변경 | 필수 |
| 2 | Windows 방화벽 인바운드 규칙 추가 | 필수 (Tailscale 제외) |
| 3 | 클라이언트 MCP 설정에 IP 지정 | 필수 |

---

## 2. 서버 바인딩 변경

### 방법 A: CLI 직접 실행

```bash
python server.py --host 0.0.0.0 --port 5555
```

### 방법 B: Server Manager 앱 설정

Server Manager UI에서:
1. **설정** 탭 열기
2. **원격 접근 허용 (allowRemoteAccess)** 토글 ON
3. 서버 재시작

> `allowRemoteAccess: true`이면 자동으로 `0.0.0.0`에 바인딩됩니다.
> `allowRemoteAccess: false`이면 `127.0.0.1` (로컬만).

### 확인

```bash
# 0.0.0.0으로 바인딩되었는지 확인
netstat -ano | findstr ":5555"

# 정상 출력 예시:
# TCP    0.0.0.0:5555    0.0.0.0:0    LISTENING    12345
```

---

## 3. Windows 방화벽 설정

**PowerShell (관리자 권한)** 에서 실행:

```powershell
# 규칙 추가
netsh advfirewall firewall add rule name="U2DIA Kanban Server" dir=in action=allow protocol=TCP localport=5555

# 규칙 확인
netsh advfirewall firewall show rule name="U2DIA Kanban Server"

# 규칙 삭제 (필요 시)
netsh advfirewall firewall delete rule name="U2DIA Kanban Server"
```

> **Tailscale 네트워크**: Tailscale은 자체 터널을 사용하므로 방화벽 규칙 없이도
> Tailscale IP (`100.x.x.x`)로 접근 가능할 수 있습니다.

---

## 4. 접근 주소

서버가 실행 중인 PC의 IP를 확인합니다:

```bash
ipconfig
```

| 네트워크 | 접근 URL | 비고 |
|----------|----------|------|
| 로컬 | `http://localhost:5555` | 항상 가능 |
| 같은 Wi-Fi/LAN | `http://{Wi-Fi IP}:5555` | 방화벽 필요 |
| Tailscale VPN | `http://{Tailscale IP}:5555` | 방화벽 불필요 (보통) |

### 현재 서버 PC IP (참고)

| 인터페이스 | IP |
|------------|-----|
| Wi-Fi | `192.168.219.138` |
| Tailscale | `100.78.114.73` |

> IP는 네트워크 환경에 따라 변경될 수 있습니다.

---

## 5. 원격 MCP 연동

다른 PC의 프로젝트에서 `.claude/settings.json`:

```json
{
  "mcpServers": {
    "kanban": {
      "type": "url",
      "url": "http://{서버IP}:5555/mcp",
      "headers": {
        "Authorization": "Bearer XXXX-XXXX-XXXX-XXXX"
      }
    }
  }
}
```

### 예시: Tailscale 경유

```json
{
  "mcpServers": {
    "kanban": {
      "type": "url",
      "url": "http://100.78.114.73:5555/mcp",
      "headers": {
        "Authorization": "Bearer ZJCT-R1QM-Y40E-GD4Z"
      }
    }
  }
}
```

### 예시: 같은 Wi-Fi

```json
{
  "mcpServers": {
    "kanban": {
      "type": "url",
      "url": "http://192.168.219.138:5555/mcp",
      "headers": {
        "Authorization": "Bearer ZJCT-R1QM-Y40E-GD4Z"
      }
    }
  }
}
```

---

## 6. 원격 대시보드 접속

브라우저에서 직접 접속:

| 페이지 | URL |
|--------|-----|
| 대시보드 | `http://{서버IP}:5555/` |
| 팀 칸반보드 | `http://{서버IP}:5555/#/board/{teamId}` |
| 히스토리 | `http://{서버IP}:5555/#/history` |
| 아카이브 | `http://{서버IP}:5555/#/archives` |

---

## 7. 연결 테스트

원격 PC에서:

```bash
# API 테스트
curl http://{서버IP}:5555/api/teams

# MCP 테스트 (토큰 인증)
curl -X POST http://{서버IP}:5555/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer XXXX-XXXX-XXXX-XXXX" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

---

## 8. 보안 주의사항

| 항목 | 설명 |
|------|------|
| **토큰 인증** | MCP 엔드포인트(`/mcp`)는 Bearer 토큰 필수. 토큰 없이 접근 불가 |
| **대시보드** | 웹 UI는 인증 없이 접근 가능 (읽기 전용). 민감 환경에서는 방화벽으로 IP 제한 권장 |
| **토큰 관리** | Server Manager의 토큰 탭에서 생성/삭제. 프로젝트별 고유 토큰 사용 |
| **포트 노출** | 공용 네트워크에서는 `allowRemoteAccess`를 끄거나, 특정 IP만 허용하는 방화벽 규칙 사용 |

### IP 제한 방화벽 규칙 (선택)

특정 IP만 허용하려면:

```powershell
netsh advfirewall firewall add rule name="U2DIA Kanban Server (Restricted)" ^
  dir=in action=allow protocol=TCP localport=5555 ^
  remoteip=192.168.219.0/24
```

---

## 9. 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| 연결 거부 (Connection refused) | 서버가 `127.0.0.1`에 바인딩됨 | `--host 0.0.0.0` 또는 `allowRemoteAccess: true` |
| 연결 시간 초과 (Timeout) | 방화벽 차단 | 인바운드 규칙 추가 (섹션 3) |
| 빈 응답 (Empty reply) | 여러 서버 프로세스 충돌 | `netstat -ano \| findstr :5555`로 확인 후 중복 프로세스 종료 |
| 401 Unauthorized | 잘못된 토큰 | Server Manager에서 토큰 확인, `Authorization: Bearer` 형식 확인 |
| 대시보드 빈 화면 | 서버 기동 전 접속 | 서버 완전 기동 후 새로고침 |

---

## 6. Remote CLI Mirror (ttyd + tmux + /cli 프록시)

PC 의 Claude Code CLI 화면을 모바일/원격 브라우저에서 양방향으로 보고 입력.

### 6-1. 아키텍처

```
PC tmux 세션 "claude"
  └─ ttyd (--writable, 127.0.0.1:7681)        ← 외부 미노출 (강제)
       └─ server.py /cli, /cli/ws  (리버스 프록시 + 토큰 인증)
            └─ Tailscale 100.x.x.x:5555
                 └─ 모바일 앱 / 외부 브라우저 (xterm.js / xterm.dart)
```

### 6-2. 기동

```bash
./scripts/cli-mirror-up.sh        # ttyd 7681 + tmux 'claude'
# 같은 PC에서 작업 시작:
cc                                # = tmux new-session -A -s claude claude
```

종료: `./scripts/cli-mirror-down.sh` (tmux 세션은 보존, `CLI_MIRROR_KILL_TMUX=1` 로 종료)

### 6-3. 외부 접근 허용 (Tailscale 권장)

`server.py` 환경변수:

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `CLI_PROXY_TARGET` | `127.0.0.1:7681` | ttyd 주소 |
| `CLI_PROXY_DISABLED` | (없음) | `1` 이면 503 응답 (전면 차단) |
| `CLI_PROXY_REMOTE_OK` | (없음) | `1` 일 때만 외부 IP 접근 허용 (Tailscale 사용 시 필수) |

기본값: 외부 접근 차단. Tailscale 내부에서만 사용한다면:

```bash
CLI_PROXY_REMOTE_OK=1 python3 server.py
```

### 6-4. 보안 원칙

- ttyd 자체는 **127.0.0.1 만 바인드** (cli-mirror-up.sh 가 0.0.0.0/`*`/`::` 거부)
- 외부 노출은 server.py /cli 프록시를 통해서만 — 모든 요청이 칸반 토큰 (Bearer) 또는 세션 쿠키로 인증
- `--writable` 모드는 **사실상 원격 셸**과 동등: 누구든 붙으면 임의 명령 실행 가능 → Tailscale ACL 필수
- Basic Auth 추가 강화: `CLI_MIRROR_AUTH=user:pass ./scripts/cli-mirror-up.sh`

### 6-5. 동작 확인

```bash
# 로컬 HTML 응답
curl -sI http://127.0.0.1:5555/cli | head -2
# → HTTP/1.1 200 OK / server: ttyd/...

# WebSocket 핸드쉐이크 (101 Switching Protocols)
python3 -c "
import socket, base64, os
key = base64.b64encode(os.urandom(16)).decode()
s = socket.create_connection(('127.0.0.1',5555))
s.sendall(f'GET /cli/ws HTTP/1.1\r\nHost: 127.0.0.1:5555\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: tty\r\n\r\n'.encode())
print(s.recv(2048).decode().split('\r\n\r\n')[0])
"
```

### 6-6. 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `502 upstream_unavailable` | ttyd 미기동 | `./scripts/cli-mirror-up.sh` |
| `403 remote_disabled` | 외부 IP 인데 옵트인 안 함 | `CLI_PROXY_REMOTE_OK=1` 환경변수 |
| `503 disabled` | 전면 차단 | `CLI_PROXY_DISABLED` 해제 |
| WS 끊김 반복 | select 60초 타임아웃 정상 | 클라이언트가 재연결하면 OK |

---

**END OF REMOTE ACCESS GUIDE v1.1** (CLI Mirror 섹션 추가)
