#!/usr/bin/env python3
"""
Agent Team Kanban — System Tray Manager
========================================
시스템 트레이에서 서버 시작/중지/재시작, 대시보드 열기, 실시간 알림.
Windows + Linux(Ubuntu) 크로스플랫폼 지원.

의존성: pip install pystray pillow plyer
실행:   python tray.py [--port 5555] [--autostart]
"""

import argparse
import json
import os
import platform
import signal
import subprocess
import sys
import threading
import time
import webbrowser
from io import BytesIO
from urllib.error import URLError
from urllib.request import Request, urlopen

# ── 설정 ──

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SERVER_SCRIPT = os.path.join(SCRIPT_DIR, "server.py")
DEFAULT_PORT = 5555
POLL_INTERVAL = 5          # 서버 상태 체크 주기 (초)
SSE_RECONNECT = 3          # SSE 재연결 대기 (초)
IS_WINDOWS = platform.system() == "Windows"
IS_LINUX = platform.system() == "Linux"

# ── 지연 임포트 (설치 안내) ──

def _check_deps():
    missing = []
    for pkg in ["pystray", "PIL", "plyer"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg.replace("PIL", "pillow"))
    if missing:
        print(f"[tray] 필요 패키지 설치: pip install {' '.join(missing)}")
        sys.exit(1)

_check_deps()

import pystray                          # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402
from plyer import notification          # noqa: E402


# ── 아이콘 생성 (동적) ──

def _make_icon(color: str = "#22c55e", size: int = 64) -> Image.Image:
    """단색 원형 트레이 아이콘 생성. 녹색=실행, 빨강=중지, 노랑=시작중."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    margin = 4
    draw.ellipse([margin, margin, size - margin, size - margin], fill=color)
    # 가운데 'K' 글자
    try:
        font = ImageFont.truetype("arial.ttf", size // 2)
    except (OSError, IOError):
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), "K", font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((size - tw) / 2, (size - th) / 2 - 2), "K", fill="white", font=font)
    return img

ICON_RUNNING = _make_icon("#22c55e")   # 녹색
ICON_STOPPED = _make_icon("#ef4444")   # 빨강
ICON_STARTING = _make_icon("#eab308")  # 노랑


# ── 서버 관리 ──

class ServerManager:
    def __init__(self, port: int, autostart: bool = False):
        self.port = port
        self.base_url = f"http://127.0.0.1:{port}"
        self.process: subprocess.Popen | None = None
        self._lock = threading.Lock()
        self.running = False
        self.tray: pystray.Icon | None = None
        self._sse_thread: threading.Thread | None = None
        self._stop_sse = threading.Event()
        self._monitor_thread: threading.Thread | None = None
        self._stop_monitor = threading.Event()

        if autostart:
            self.start_server()

    # ── 서버 상태 ──

    def _ping(self) -> bool:
        try:
            resp = urlopen(f"{self.base_url}/api/tokens", timeout=2)
            return resp.status == 200
        except Exception:
            return False

    def _update_icon(self, state: str = "check"):
        if not self.tray:
            return
        if state == "running" or (state == "check" and self.running):
            self.tray.icon = ICON_RUNNING
            self.tray.title = f"Kanban Server :{self.port} - Running"
        elif state == "starting":
            self.tray.icon = ICON_STARTING
            self.tray.title = f"Kanban Server :{self.port} - Starting..."
        else:
            self.tray.icon = ICON_STOPPED
            self.tray.title = f"Kanban Server :{self.port} - Stopped"

    # ── 서버 시작/중지/재시작 ──

    def start_server(self):
        with self._lock:
            if self._ping():
                self.running = True
                self._update_icon("running")
                self._notify("서버 감지", f"포트 {self.port}에서 이미 실행 중")
                self._start_sse()
                return

            self._update_icon("starting")
            self._notify("서버 시작", f"포트 {self.port}에서 시작 중...")

            cmd = [sys.executable, SERVER_SCRIPT, "--port", str(self.port), "--no-browser"]
            creation_flags = 0
            if IS_WINDOWS:
                creation_flags = subprocess.CREATE_NO_WINDOW

            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                creationflags=creation_flags if IS_WINDOWS else 0,
            )

        # 서버 준비 대기 (최대 15초)
        for _ in range(30):
            time.sleep(0.5)
            if self._ping():
                self.running = True
                self._update_icon("running")
                self._notify("서버 시작 완료", f"http://127.0.0.1:{self.port}")
                self._start_sse()
                return

        self._update_icon("stopped")
        self._notify("서버 시작 실패", "15초 내 응답 없음")

    def stop_server(self):
        with self._lock:
            self._stop_sse_listener()

            if self.process:
                self.process.terminate()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                self.process = None

            # 외부에서 실행된 서버도 중지 시도
            if self._ping():
                try:
                    req = Request(f"{self.base_url}/api/shutdown", method="POST")
                    urlopen(req, timeout=3)
                except Exception:
                    pass
                time.sleep(1)

            self.running = False
            self._update_icon("stopped")
            self._notify("서버 중지", "서버가 중지되었습니다")

    def restart_server(self):
        self.stop_server()
        time.sleep(1)
        self.start_server()

    # ── SSE 이벤트 리스너 (실시간 알림) ──

    def _start_sse(self):
        self._stop_sse_listener()
        self._stop_sse.clear()
        self._sse_thread = threading.Thread(target=self._sse_loop, daemon=True)
        self._sse_thread.start()

    def _stop_sse_listener(self):
        self._stop_sse.set()
        if self._sse_thread and self._sse_thread.is_alive():
            self._sse_thread.join(timeout=3)
        self._sse_thread = None

    def _sse_loop(self):
        while not self._stop_sse.is_set():
            try:
                req = Request(f"{self.base_url}/api/supervisor/events")
                resp = urlopen(req, timeout=60)
                buffer = ""
                while not self._stop_sse.is_set():
                    chunk = resp.read(1).decode("utf-8", errors="replace")
                    if not chunk:
                        break
                    buffer += chunk
                    if buffer.endswith("\n\n"):
                        self._process_sse(buffer)
                        buffer = ""
            except Exception:
                pass
            if not self._stop_sse.is_set():
                self._stop_sse.wait(SSE_RECONNECT)

    def _process_sse(self, raw: str):
        event_type = ""
        data = ""
        for line in raw.strip().split("\n"):
            if line.startswith("event:"):
                event_type = line[6:].strip()
            elif line.startswith("data:"):
                data = line[5:].strip()
            elif line.startswith(":"):
                return  # heartbeat

        if not data:
            return

        try:
            payload = json.loads(data)
        except json.JSONDecodeError:
            return

        # event_type이 없으면 JSON 내부 type 필드 사용
        if not event_type:
            event_type = payload.get("type", "")
        event_data = payload.get("data", payload)

        if not event_type:
            return

        # 주요 이벤트만 알림
        notifications = {
            "team_created": lambda p: (
                "팀 생성",
                f"'{p.get('name', p.get('team_name', '?'))}' 팀이 생성되었습니다",
            ),
            "ticket_created": lambda p: (
                "티켓 생성",
                f"{p.get('title', '?')}",
            ),
            "ticket_status_changed": lambda p: (
                "티켓 상태 변경",
                f"{p.get('ticket_title', '?')} → {p.get('status', p.get('new_status', '?'))}",
            ),
            "member_spawned": lambda p: (
                "에이전트 스폰",
                f"{p.get('role', p.get('member_name', '?'))} 투입",
            ),
            "team_archived": lambda p: (
                "팀 아카이브",
                f"'{p.get('name', p.get('team_name', '?'))}' 아카이브 완료",
            ),
        }

        handler = notifications.get(event_type)
        if handler:
            title, msg = handler(event_data)
            self._notify(title, msg)

    # ── 모니터링 루프 ──

    def _start_monitor(self):
        self._stop_monitor.clear()
        self._monitor_thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self._monitor_thread.start()

    def _monitor_loop(self):
        while not self._stop_monitor.is_set():
            was_running = self.running
            self.running = self._ping()

            if was_running and not self.running:
                self._update_icon("stopped")
                self._notify("서버 다운", "서버 연결이 끊어졌습니다!")
                self._stop_sse_listener()
            elif not was_running and self.running:
                self._update_icon("running")
                self._notify("서버 복구", "서버가 다시 응답합니다")
                self._start_sse()
            else:
                self._update_icon()

            self._stop_monitor.wait(POLL_INTERVAL)

    # ── 알림 ──

    def _notify(self, title: str, message: str):
        try:
            notification.notify(
                title=f"[Kanban] {title}",
                message=message,
                app_name="Kanban Server",
                timeout=5,
            )
        except Exception:
            pass

    # ── 메뉴 액션 ──

    def open_dashboard(self):
        webbrowser.open(f"{self.base_url}/")

    def open_supervisor(self):
        webbrowser.open(f"{self.base_url}/supervisor")

    def _get_status_text(self) -> str:
        if not self.running:
            return "상태: 중지됨"
        try:
            resp = urlopen(f"{self.base_url}/api/tokens", timeout=2)
            tokens = json.loads(resp.read())
            if not isinstance(tokens, list):
                tokens = tokens.get("tokens", [])

            resp2 = urlopen(f"{self.base_url}/api/teams", timeout=2)
            teams = json.loads(resp2.read())
            if isinstance(teams, dict):
                teams = teams.get("teams", [])

            return f"실행 중 | 팀 {len(teams)}개 | 토큰 {len(tokens)}개"
        except Exception:
            return "상태: 확인 불가"

    # ── 트레이 실행 ──

    def run(self):
        # 초기 상태 확인
        self.running = self._ping()
        initial_icon = ICON_RUNNING if self.running else ICON_STOPPED

        def on_start(icon, item):
            threading.Thread(target=self.start_server, daemon=True).start()

        def on_stop(icon, item):
            threading.Thread(target=self.stop_server, daemon=True).start()

        def on_restart(icon, item):
            threading.Thread(target=self.restart_server, daemon=True).start()

        def on_dashboard(icon, item):
            self.open_dashboard()

        def on_supervisor(icon, item):
            self.open_supervisor()

        def on_quit(icon, item):
            self._stop_sse_listener()
            self._stop_monitor.set()
            icon.stop()

        menu = pystray.Menu(
            pystray.MenuItem(
                lambda item: self._get_status_text(),
                None,
                enabled=False,
            ),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("서버 시작", on_start),
            pystray.MenuItem("서버 중지", on_stop),
            pystray.MenuItem("서버 재시작", on_restart),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("대시보드 열기", on_dashboard, default=True),
            pystray.MenuItem("Supervisor 열기", on_supervisor),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("종료", on_quit),
        )

        self.tray = pystray.Icon(
            name="kanban-server",
            icon=initial_icon,
            title=f"Kanban Server :{self.port}",
            menu=menu,
        )

        # 모니터 시작
        self._start_monitor()

        # SSE 시작 (이미 실행중이면)
        if self.running:
            self._start_sse()

        self.tray.run()


# ── 엔트리포인트 ──

def main():
    parser = argparse.ArgumentParser(description="Kanban Server Tray Manager")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--autostart", action="store_true", help="시작 시 서버 자동 기동")
    args = parser.parse_args()

    mgr = ServerManager(port=args.port, autostart=args.autostart)
    mgr.run()


if __name__ == "__main__":
    main()
