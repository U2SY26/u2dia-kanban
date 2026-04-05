#!/usr/bin/env python3
"""
U2DIA Kanban Board — 알림 데몬 v1.0
SSE 이벤트를 수신하여 데스크톱 알림(notify-send) + Telegram 요약 발송

사용법:
  python3 notifier.py
  python3 notifier.py --port 5555 --no-telegram
"""
import sys, os, json, time, threading, urllib.request, urllib.parse, subprocess, argparse, signal

BASE_URL = "http://localhost:{port}"
SSE_PATH = "/api/supervisor/events"
RECONNECT_DELAY = 5
MAX_RECONNECT = 10

# 이벤트 → 알림 메시지 매핑
EVENT_MAP = {
    "team_created":            lambda d: ("🆕 팀 생성",         d.get("name","?")),
    "ticket_created":          lambda d: ("📋 티켓 생성",        d.get("title","?")),
    "ticket_status_changed":   lambda d: ("🔄 티켓 상태 변경",   f"{d.get('title','?')} → {d.get('status','?')}"),
    "ticket_claimed":          lambda d: ("⚡ 티켓 클레임",      f"{d.get('title','?')} by {d.get('member_name','?')}"),
    "member_spawned":          lambda d: ("🤖 에이전트 스폰",    f"{d.get('role','?')} in {d.get('team_name','?')}"),
    "team_archived":           lambda d: ("📦 팀 아카이브",      d.get("team_name","?")),
    "team_auto_archived":      lambda d: ("✅ 팀 자동 완료",     d.get("team_name","?")),
    "feedback_created":        lambda d: ("⭐ 피드백",           f"점수: {d.get('score','?')}/5 [{d.get('ticket_title','?')}]"),
    "artifact_created":        lambda d: ("📦 산출물",           f"{d.get('artifact_type','?')}: {d.get('title','?')}"),
}

def notify_send(title: str, body: str, icon: str = "dialog-information"):
    """notify-send로 데스크톱 알림 표시."""
    try:
        subprocess.Popen(
            ["notify-send", "-a", "U2DIA Kanban", "-i", icon, "-t", "6000", title, body],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except Exception as e:
        print(f"[notify] {e}", file=sys.stderr)

def parse_sse_line(line: str):
    """SSE data 줄 파싱 → dict or None."""
    if line.startswith("data:"):
        try:
            return json.loads(line[5:].strip())
        except:
            pass
    return None

class NotifierDaemon:
    def __init__(self, port: int = 5555, telegram: bool = True):
        self.port = port
        self.telegram = telegram
        self._stop = threading.Event()
        self._reconnect_count = 0
        self._last_summary_time = 0
        self._event_count = 0

    def start(self):
        print(f"[U2DIA Notifier] 시작 — 서버: localhost:{self.port}", flush=True)
        self._connect_loop()

    def stop(self):
        self._stop.set()

    def _connect_loop(self):
        while not self._stop.is_set():
            try:
                self._listen()
                self._reconnect_count = 0
            except Exception as e:
                self._reconnect_count += 1
                if self._reconnect_count > MAX_RECONNECT:
                    print(f"[notifier] 최대 재시도 초과. 종료.", file=sys.stderr)
                    break
                wait = min(RECONNECT_DELAY * self._reconnect_count, 60)
                print(f"[notifier] 재연결 대기 {wait}초 ({e})", flush=True)
                self._stop.wait(wait)

    def _listen(self):
        url = f"http://localhost:{self.port}{SSE_PATH}"
        req = urllib.request.Request(url, headers={"Accept": "text/event-stream"})
        print(f"[notifier] SSE 연결: {url}", flush=True)
        with urllib.request.urlopen(req, timeout=None) as resp:
            if resp.status != 200:
                raise ConnectionError(f"HTTP {resp.status}")
            print("[notifier] SSE 연결 성공 ✓", flush=True)
            notify_send("U2DIA Kanban Board", "알림 데몬 연결됨 — 실시간 이벤트 수신 중")
            buf = ""
            while not self._stop.is_set():
                chunk = resp.read(512)
                if not chunk:
                    break
                buf += chunk.decode("utf-8", errors="replace")
                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    line = line.strip()
                    if not line or line.startswith(":"):
                        continue
                    event = parse_sse_line(line)
                    if event:
                        self._on_event(event)

    def _on_event(self, event: dict):
        et = event.get("event_type") or event.get("type", "")
        data = event.get("data") or event.get("payload") or {}
        self._event_count += 1

        handler = EVENT_MAP.get(et)
        if handler:
            title, body = handler(data)
            team = data.get("team_name") or event.get("team_name", "")
            if team:
                body = f"[{team}] {body}"
            icon = {
                "team_created": "emblem-new",
                "ticket_status_changed": "emblem-synchronizing",
                "team_archived": "emblem-package",
                "team_auto_archived": "emblem-default",
                "member_spawned": "system-run",
                "feedback_created": "starred",
            }.get(et, "dialog-information")
            notify_send(title, body, icon)
            print(f"[notify] {title}: {body}", flush=True)

def main():
    parser = argparse.ArgumentParser(description="U2DIA 알림 데몬")
    parser.add_argument("--port", type=int, default=5555)
    parser.add_argument("--no-telegram", action="store_true")
    args = parser.parse_args()

    daemon = NotifierDaemon(port=args.port, telegram=not args.no_telegram)
    
    def handle_signal(sig, frame):
        print("\n[notifier] 종료 신호 수신", flush=True)
        daemon.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    
    daemon.start()

if __name__ == "__main__":
    main()
