#!/usr/bin/env python3
"""
U2DIA Kanban Board — 알림 데몬 v2.0
SSE 이벤트를 수신하여 데스크톱 알림(notify-send) 발송

근본 대책 (v2.0):
  1. PID 파일로 단일 인스턴스 보장
  2. subprocess.run (blocking) — 좀비 프로세스 원천 차단
  3. 슬라이딩 윈도우 속도 제한 (5초당 최대 3건)
  4. 이벤트 배치 그룹핑 (2초간 모아서 요약 알림 1건)
  5. SIGCHLD 자동 수거 (추가 안전장치)

사용법:
  python3 notifier.py
  python3 notifier.py --port 5555
"""
import sys, os, json, time, threading, urllib.request, subprocess, argparse, signal, atexit
from collections import deque

SSE_PATH = "/api/supervisor/events"
RECONNECT_DELAY = 5
MAX_RECONNECT = 10

# 속도 제한
RATE_WINDOW = 5        # 슬라이딩 윈도우 (초)
RATE_MAX = 3           # 윈도우 내 최대 알림 수
BATCH_DELAY = 2.0      # 이벤트 배치 대기 (초)

PID_FILE = "/tmp/u2dia-notifier.pid"

# 이벤트 → 알림 메시지 매핑
EVENT_MAP = {
    "team_created":            ("팀 생성",       lambda d: d.get("name","?")),
    "ticket_created":          ("티켓 생성",     lambda d: d.get("title","?")),
    "ticket_status_changed":   ("티켓 상태",     lambda d: f"{d.get('title','?')} → {d.get('status','?')}"),
    "ticket_claimed":          ("티켓 클레임",   lambda d: f"{d.get('title','?')} by {d.get('member_name','?')}"),
    "member_spawned":          ("에이전트 스폰", lambda d: f"{d.get('role','?')} in {d.get('team_name','?')}"),
    "team_archived":           ("팀 아카이브",   lambda d: d.get("team_name","?")),
    "team_auto_archived":      ("팀 자동 완료",  lambda d: d.get("team_name","?")),
    "feedback_created":        ("피드백",        lambda d: f"점수 {d.get('score','?')}/5 [{d.get('ticket_title','?')}]"),
    "artifact_created":        ("산출물",        lambda d: f"{d.get('artifact_type','?')}: {d.get('title','?')}"),
}


# ── PID 잠금 ──

def _acquire_pid():
    """단일 인스턴스 보장. 이미 실행 중이면 종료."""
    if os.path.exists(PID_FILE):
        try:
            old_pid = int(open(PID_FILE).read().strip())
            # 프로세스 존재 여부 확인
            os.kill(old_pid, 0)
            print(f"[notifier] 이미 실행 중 (PID {old_pid}). 종료.", file=sys.stderr)
            sys.exit(1)
        except (ProcessLookupError, ValueError):
            pass  # 이전 프로세스 없음 — 계속 진행
        except PermissionError:
            print(f"[notifier] PID {old_pid} 접근 불가. 종료.", file=sys.stderr)
            sys.exit(1)
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))
    atexit.register(_release_pid)

def _release_pid():
    try:
        os.unlink(PID_FILE)
    except OSError:
        pass


# ── 알림 발송 ──

def _notify(title: str, body: str, icon: str = "dialog-information"):
    """notify-send blocking 호출. 좀비 불가."""
    try:
        subprocess.run(
            ["notify-send", "-a", "U2DIA Kanban", "-i", icon, "-t", "6000", title, body],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=5
        )
    except Exception as e:
        print(f"[notify-err] {e}", file=sys.stderr)


def parse_sse_line(line: str):
    if line.startswith("data:"):
        try:
            return json.loads(line[5:].strip())
        except Exception:
            pass
    return None


class NotifierDaemon:
    def __init__(self, port: int = 5555):
        self.port = port
        self._stop = threading.Event()
        self._reconnect_count = 0
        self._event_count = 0
        # 속도 제한 — 최근 알림 타임스탬프
        self._rate_times: deque = deque()
        # 배치 버퍼 — {event_type: [data_list]}
        self._batch_buf: dict = {}
        self._batch_lock = threading.Lock()
        self._batch_timer: threading.Timer | None = None

    def start(self):
        _acquire_pid()
        # SIGCHLD 자동 수거 (추가 안전장치)
        signal.signal(signal.SIGCHLD, signal.SIG_IGN)
        print(f"[U2DIA Notifier v2.0] 시작 — PID {os.getpid()}, 서버 localhost:{self.port}", flush=True)
        self._connect_loop()

    def stop(self):
        self._stop.set()
        if self._batch_timer:
            self._batch_timer.cancel()

    # ── 속도 제한 ──

    def _rate_ok(self) -> bool:
        now = time.time()
        # 윈도우 밖 항목 제거
        while self._rate_times and self._rate_times[0] < now - RATE_WINDOW:
            self._rate_times.popleft()
        if len(self._rate_times) >= RATE_MAX:
            return False
        self._rate_times.append(now)
        return True

    # ── 이벤트 배치 ──

    def _flush_batch(self):
        """배치 버퍼를 플러시하여 요약 알림 발송."""
        with self._batch_lock:
            buf = dict(self._batch_buf)
            self._batch_buf.clear()
            self._batch_timer = None

        if not buf:
            return

        for et, items in buf.items():
            mapping = EVENT_MAP.get(et)
            if not mapping:
                continue
            label, _ = mapping

            if len(items) == 1:
                # 단건 — 개별 알림
                title = f"[Kanban] {label}"
                body = items[0]
            else:
                # 다건 — 요약 알림 (14개 팀 아카이브 → "14건" 1줄)
                title = f"[Kanban] {label} {len(items)}건"
                # 최대 3줄만 표시
                preview = items[:3]
                if len(items) > 3:
                    preview.append(f"...외 {len(items) - 3}건")
                body = "\n".join(preview)

            if self._rate_ok():
                _notify(title, body)
                print(f"[notify] {title}: {body[:80]}", flush=True)
            else:
                print(f"[notify-skip] 속도 제한: {title}", flush=True)

    def _enqueue_event(self, event_type: str, body_text: str):
        """이벤트를 배치 버퍼에 추가. BATCH_DELAY 후 플러시."""
        with self._batch_lock:
            self._batch_buf.setdefault(event_type, []).append(body_text)
            # 타이머 리셋
            if self._batch_timer:
                self._batch_timer.cancel()
            self._batch_timer = threading.Timer(BATCH_DELAY, self._flush_batch)
            self._batch_timer.daemon = True
            self._batch_timer.start()

    # ── SSE 연결 ──

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
            print("[notifier] SSE 연결 성공", flush=True)
            _notify("[Kanban] 알림 데몬", "실시간 이벤트 수신 중")
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

        mapping = EVENT_MAP.get(et)
        if not mapping:
            return

        _, body_fn = mapping
        body_text = body_fn(data)
        team = data.get("team_name") or event.get("team_name", "")
        if team:
            body_text = f"[{team}] {body_text}"

        self._enqueue_event(et, body_text)


def main():
    parser = argparse.ArgumentParser(description="U2DIA 알림 데몬 v2.0")
    parser.add_argument("--port", type=int, default=5555)
    args = parser.parse_args()

    daemon = NotifierDaemon(port=args.port)

    def handle_signal(sig, frame):
        print("\n[notifier] 종료 신호 수신", flush=True)
        daemon.stop()
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    daemon.start()

if __name__ == "__main__":
    main()
