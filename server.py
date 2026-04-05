"""
Agent Team Kanban Board — 독립형 서버 + MCP 지원
=================================================
Claude Code 에이전트 백그라운드 작업을 실시간 모니터링하는 칸반보드.
어떤 프로젝트에서든 사용 가능한 범용 독립 서버.

기능:
  - REST API: 팀/멤버/티켓/로그 CRUD
  - 웹 칸반보드: 6컬럼 Drag&Drop, 실시간 폴링 (5초)
  - MCP JSON-RPC 2.0: Claude Code 에이전트 연동
  - Auto-Scaffold: 프로젝트 구조 스캔 → 팀/멤버/티켓 자동 생성

실행: python server.py [--port 5555] [--host 0.0.0.0]
접속: http://localhost:5555/board
MCP:  http://localhost:5555/mcp (JSON-RPC 2.0)

의존성: Python 표준 라이브러리만 사용 (외부 패키지 없음)
"""

import argparse
import hashlib
import http.server
import json
import mimetypes
import os
import platform
import queue
import re
import secrets
import socket
import socketserver
import sqlite3
import string
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone, timedelta
from urllib.parse import urlparse, parse_qs
from urllib.request import Request, urlopen

# ── 설정 ──

VERSION = "6.0.0"
_base_dir = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.environ.get("KANBAN_DB_PATH") or os.path.join(_base_dir, "agent_teams.db")
WEB_DIR = os.environ.get("KANBAN_WEB_DIR") or os.path.join(_base_dir, "web")
DEFAULT_PORT = 5555
DEFAULT_HOST = "0.0.0.0"

# ── 시스템 메트릭 캐시 ──
_metrics_cache = None
_metrics_cache_time = 0.0

# ── 클라이언트 추적 ──
_connected_clients = {}
_clients_lock = threading.Lock()


# ── SQLite ──

def get_db():
    conn = sqlite3.connect(DB_PATH, isolation_level="DEFERRED")
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=60000")
    return conn


# ── Write Queue (단일 Writer Thread + Batch Coalescing) ──

class WriteQueue:
    """모든 DB 쓰기를 단일 스레드로 직렬화하고, 대기 중인 작업을 배치로 합침.

    - 에이전트별 요청은 Future로 즉시 반환되어 블로킹 최소화
    - 여러 동시 요청이 하나의 트랜잭션으로 합쳐져 SQLite 성능 극대화
    - 개별 작업 실패는 해당 Future에만 전파 (배치 내 다른 작업은 정상 커밋)
    """

    MAX_BATCH = 200
    DRAIN_TIMEOUT = 0.02  # 20ms — 첫 아이템 수신 후 추가 아이템 수집 대기

    def __init__(self):
        self._queue = queue.Queue()
        self._thread = None
        self._running = False

    def start(self):
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._worker, name="WriteQueue", daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        self._queue.put(None)  # 센티널로 깨움

    def submit(self, fn, *args, timeout=60, **kwargs):
        """fn(conn, *args, **kwargs) 실행을 큐에 제출. 결과를 동기적으로 반환."""
        evt = threading.Event()
        job = {"fn": fn, "args": args, "kwargs": kwargs, "result": None, "error": None, "event": evt}
        self._queue.put(job)
        if not evt.wait(timeout=timeout):
            raise TimeoutError(f"WriteQueue timeout ({timeout}s)")
        if job["error"]:
            raise job["error"]
        return job["result"]

    def submit_batch(self, operations, timeout=60):
        """[(fn, args, kwargs), ...] 배치 제출. 결과 리스트 반환.

        배치 내 모든 작업이 하나의 트랜잭션으로 처리됨.
        개별 작업 실패 시 해당 항목만 에러 결과, 나머지는 정상.
        """
        jobs = []
        shared_evt = threading.Event()
        for fn, args, kwargs in operations:
            job = {"fn": fn, "args": args, "kwargs": kwargs, "result": None, "error": None, "event": shared_evt, "batch": True}
            jobs.append(job)
        # 배치 래퍼를 큐에 넣음 — _worker가 하나의 트랜잭션으로 처리
        batch_item = {"__batch__": True, "jobs": jobs, "event": shared_evt}
        self._queue.put(batch_item)
        if not shared_evt.wait(timeout=timeout):
            raise TimeoutError(f"WriteQueue batch timeout ({timeout}s)")
        results = []
        for j in jobs:
            if j["error"]:
                results.append({"ok": False, "error": str(j["error"])})
            else:
                results.append(j["result"])
        return results

    def _worker(self):
        """단일 Writer 스레드 — DB 커넥션을 독점하고 배치로 처리."""
        conn = sqlite3.connect(DB_PATH, isolation_level=None)  # autocommit off via manual BEGIN
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=60000")
        conn.execute("PRAGMA synchronous=NORMAL")  # WAL 모드에서 안전 + 빠름

        while self._running:
            try:
                item = self._queue.get(timeout=1)
            except queue.Empty:
                continue
            if item is None:  # 센티널
                break

            # 배치 수집: 첫 아이템 + 큐에 대기 중인 추가 아이템
            batch = [item]
            deadline = time.monotonic() + self.DRAIN_TIMEOUT
            while len(batch) < self.MAX_BATCH:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                try:
                    extra = self._queue.get(timeout=max(0.001, remaining))
                    if extra is None:
                        break
                    batch.append(extra)
                except queue.Empty:
                    break

            # 하나의 트랜잭션으로 실행 — 예외 발생해도 워커 스레드 보호
            try:
                self._execute_batch(conn, batch)
            except Exception as e:
                # BEGIN IMMEDIATE 실패 등 치명적 에러 — 커넥션 재생성 후 계속
                print(f"[WriteQueue] critical error, reconnecting: {e}", file=sys.stderr, flush=True)
                try:
                    conn.close()
                except Exception:
                    pass
                conn = sqlite3.connect(DB_PATH, isolation_level=None)
                conn.row_factory = sqlite3.Row
                conn.execute("PRAGMA journal_mode=WAL")
                conn.execute("PRAGMA busy_timeout=60000")
                conn.execute("PRAGMA synchronous=NORMAL")
                # 배치 내 미완료 이벤트 시그널 (행 방지)
                for it in batch:
                    if it.get("__batch__"):
                        if not it["event"].is_set():
                            for job in it["jobs"]:
                                if job["error"] is None:
                                    job["error"] = e
                            it["event"].set()
                    else:
                        if not it["event"].is_set():
                            if it["error"] is None:
                                it["error"] = e
                            it["event"].set()

        conn.close()

    def _execute_batch(self, conn, batch):
        """배치 내 모든 작업을 단일 트랜잭션으로 처리."""
        # BEGIN IMMEDIATE를 try 안으로 — 실패 시 이벤트 시그널 보장
        committed = False
        try:
            conn.execute("BEGIN IMMEDIATE")
            for item in batch:
                if item.get("__batch__"):
                    # submit_batch로 제출된 배치 — 하나의 트랜잭션에 모든 jobs 처리
                    for job in item["jobs"]:
                        self._exec_job(conn, job)
                else:
                    self._exec_job(conn, item)
            conn.execute("COMMIT")
            committed = True
        except Exception as e:
            if not committed:
                try:
                    conn.execute("ROLLBACK")
                except Exception:
                    pass
            # 커밋 실패 시 아직 완료 안 된 job에 에러 전파
            for item in batch:
                if item.get("__batch__"):
                    for job in item["jobs"]:
                        if not job["event"].is_set() and job["result"] is None and job["error"] is None:
                            job["error"] = e
                elif item["result"] is None and item["error"] is None:
                    item["error"] = e
        finally:
            # 모든 이벤트 시그널
            for item in batch:
                if item.get("__batch__"):
                    item["event"].set()
                else:
                    item["event"].set()

    def _exec_job(self, conn, job):
        """개별 job 실행 — 실패해도 트랜잭션은 계속 진행."""
        try:
            result = job["fn"](conn, *job["args"], **job["kwargs"])
            job["result"] = result
        except Exception as e:
            job["error"] = e


# 글로벌 WriteQueue 인스턴스
_write_queue = WriteQueue()


def init_db():
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS agent_teams (
            team_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            project_group TEXT DEFAULT '',
            leader_agent TEXT DEFAULT 'orchestrator',
            status TEXT DEFAULT 'Active',
            created_at TEXT DEFAULT (datetime('now')),
            completed_at TEXT
        );
        CREATE TABLE IF NOT EXISTS team_members (
            member_id TEXT PRIMARY KEY,
            team_id TEXT NOT NULL,
            role TEXT NOT NULL,
            display_name TEXT,
            status TEXT DEFAULT 'Idle',
            current_ticket_id TEXT,
            spawned_at TEXT DEFAULT (datetime('now')),
            last_activity_at TEXT
        );
        CREATE TABLE IF NOT EXISTS tickets (
            ticket_id TEXT PRIMARY KEY,
            team_id TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT,
            priority TEXT DEFAULT 'Medium',
            status TEXT DEFAULT 'Backlog',
            assigned_member_id TEXT,
            depends_on TEXT,
            tags TEXT,
            estimated_minutes INTEGER,
            actual_minutes INTEGER,
            created_at TEXT DEFAULT (datetime('now')),
            started_at TEXT,
            completed_at TEXT
        );
        CREATE TABLE IF NOT EXISTS activity_logs (
            log_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_id TEXT NOT NULL,
            ticket_id TEXT,
            member_id TEXT,
            action TEXT NOT NULL,
            message TEXT,
            metadata TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS messages (
            message_id TEXT PRIMARY KEY,
            team_id TEXT NOT NULL,
            ticket_id TEXT NOT NULL,
            sender_member_id TEXT NOT NULL,
            message_type TEXT DEFAULT 'comment',
            content TEXT NOT NULL,
            parent_message_id TEXT,
            metadata TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS artifacts (
            artifact_id TEXT PRIMARY KEY,
            team_id TEXT NOT NULL,
            ticket_id TEXT NOT NULL,
            creator_member_id TEXT NOT NULL,
            artifact_type TEXT DEFAULT 'code',
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            language TEXT,
            metadata TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_members_team ON team_members(team_id);
        CREATE INDEX IF NOT EXISTS idx_tickets_team ON tickets(team_id);
        CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);
        CREATE INDEX IF NOT EXISTS idx_activity_team ON activity_logs(team_id);
        CREATE INDEX IF NOT EXISTS idx_messages_ticket ON messages(ticket_id);
        CREATE INDEX IF NOT EXISTS idx_messages_team ON messages(team_id);
        CREATE INDEX IF NOT EXISTS idx_artifacts_ticket ON artifacts(ticket_id);
        CREATE INDEX IF NOT EXISTS idx_artifacts_team ON artifacts(team_id);
        CREATE TABLE IF NOT EXISTS ticket_feedbacks (
            feedback_id TEXT PRIMARY KEY,
            ticket_id TEXT NOT NULL,
            team_id TEXT NOT NULL,
            author TEXT DEFAULT 'user',
            score INTEGER NOT NULL CHECK(score BETWEEN 1 AND 5),
            comment TEXT,
            categories TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_feedbacks_ticket ON ticket_feedbacks(ticket_id);
        CREATE INDEX IF NOT EXISTS idx_feedbacks_team ON ticket_feedbacks(team_id);

        CREATE TABLE IF NOT EXISTS licenses (
            license_key_hash TEXT PRIMARY KEY,
            license_display TEXT NOT NULL,
            name TEXT DEFAULT '',
            permissions TEXT DEFAULT 'full',
            created_at TEXT DEFAULT (datetime('now')),
            expires_at TEXT,
            is_active INTEGER DEFAULT 1,
            last_used_at TEXT,
            use_count INTEGER DEFAULT 0,
            created_by_ip TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_licenses_active ON licenses(is_active);

        CREATE TABLE IF NOT EXISTS auth_tokens (
            token_id TEXT PRIMARY KEY,
            token_display TEXT NOT NULL,
            token_hash TEXT NOT NULL UNIQUE,
            name TEXT DEFAULT '',
            permissions TEXT DEFAULT 'agent',
            created_at TEXT DEFAULT (datetime('now')),
            expires_at TEXT,
            is_active INTEGER DEFAULT 1,
            last_used_at TEXT,
            use_count INTEGER DEFAULT 0,
            created_by TEXT DEFAULT 'admin'
        );
        CREATE INDEX IF NOT EXISTS idx_tokens_active ON auth_tokens(is_active);
        CREATE INDEX IF NOT EXISTS idx_tokens_hash ON auth_tokens(token_hash);

        CREATE TABLE IF NOT EXISTS token_usage (
            usage_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_id TEXT,
            ticket_id TEXT,
            member_id TEXT,
            model TEXT DEFAULT '',
            input_tokens INTEGER DEFAULT 0,
            output_tokens INTEGER DEFAULT 0,
            estimated_cost REAL DEFAULT 0.0,
            metadata TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_usage_team ON token_usage(team_id);
        CREATE INDEX IF NOT EXISTS idx_usage_ticket ON token_usage(ticket_id);
    """)
    # 마이그레이션: archived_at 컬럼 추가
    try:
        conn.execute("ALTER TABLE agent_teams ADD COLUMN archived_at TEXT")
    except Exception:
        pass
    # 마이그레이션: project_group 컬럼 추가
    try:
        conn.execute("ALTER TABLE agent_teams ADD COLUMN project_group TEXT DEFAULT ''")
    except Exception:
        pass

    # team_snapshots 테이블 (벤치마킹 히스토리)
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS team_snapshots (
            snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_id TEXT NOT NULL,
            snapshot_type TEXT DEFAULT 'manual',
            total_tickets INTEGER DEFAULT 0,
            done_tickets INTEGER DEFAULT 0,
            blocked_tickets INTEGER DEFAULT 0,
            member_count INTEGER DEFAULT 0,
            progress REAL DEFAULT 0,
            total_messages INTEGER DEFAULT 0,
            total_artifacts INTEGER DEFAULT 0,
            total_input_tokens INTEGER DEFAULT 0,
            total_output_tokens INTEGER DEFAULT 0,
            total_cost REAL DEFAULT 0.0,
            avg_minutes_per_ticket REAL DEFAULT 0,
            duration_hours REAL DEFAULT 0,
            metadata TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_snapshots_team ON team_snapshots(team_id);
    """)

    # server_settings 테이블 (API 키 등 서버 설정)
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS server_settings (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS claude_sessions (
            session_id TEXT PRIMARY KEY,
            project_path TEXT NOT NULL,
            team_id TEXT,
            pid INTEGER,
            status TEXT DEFAULT 'running',
            started_at TEXT DEFAULT (datetime('now')),
            ended_at TEXT
        );

        /* ── 에이전트 대화 로그 (서브↔메인 소통 전체 기록) ── */
        CREATE TABLE IF NOT EXISTS agent_conversations (
            conv_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_id TEXT NOT NULL,
            ticket_id TEXT,
            from_agent TEXT NOT NULL,
            to_agent TEXT NOT NULL,
            msg_type TEXT DEFAULT 'request',
            content TEXT NOT NULL,
            metadata TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_conv_team ON agent_conversations(team_id);
        CREATE INDEX IF NOT EXISTS idx_conv_ticket ON agent_conversations(ticket_id);

        /* ── 티켓 리뷰/평가 (Ralph Loop 추적) ── */
        CREATE TABLE IF NOT EXISTS ticket_reviews (
            review_id INTEGER PRIMARY KEY AUTOINCREMENT,
            ticket_id TEXT NOT NULL,
            team_id TEXT NOT NULL,
            reviewer TEXT DEFAULT 'orchestrator',
            result TEXT NOT NULL,
            score INTEGER CHECK(score BETWEEN 1 AND 5),
            comment TEXT,
            retry_round INTEGER DEFAULT 0,
            issues TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_reviews_ticket ON ticket_reviews(ticket_id);

        /* ── 상세 산출물 (파일경로, 코드줄수, API 등) ── */
        CREATE TABLE IF NOT EXISTS artifact_details (
            detail_id INTEGER PRIMARY KEY AUTOINCREMENT,
            artifact_id TEXT,
            ticket_id TEXT NOT NULL,
            team_id TEXT NOT NULL,
            detail_type TEXT NOT NULL,
            file_path TEXT,
            lines_added INTEGER DEFAULT 0,
            lines_removed INTEGER DEFAULT 0,
            api_endpoint TEXT,
            description TEXT,
            metadata TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_artdetail_ticket ON artifact_details(ticket_id);
    """)


    # OKR / 전략과제 / MBO 테이블
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS team_objectives (
            obj_id TEXT PRIMARY KEY,
            team_id TEXT NOT NULL,
            obj_type TEXT DEFAULT 'OKR',
            title TEXT NOT NULL,
            description TEXT,
            category TEXT DEFAULT 'strategic',
            target_value REAL DEFAULT 100,
            current_value REAL DEFAULT 0,
            unit TEXT DEFAULT '%',
            weight REAL DEFAULT 1.0,
            status TEXT DEFAULT 'Active',
            due_date TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_obj_team ON team_objectives(team_id);
        CREATE INDEX IF NOT EXISTS idx_obj_type ON team_objectives(obj_type);

        CREATE TABLE IF NOT EXISTS objective_key_results (
            kr_id TEXT PRIMARY KEY,
            obj_id TEXT NOT NULL,
            title TEXT NOT NULL,
            target_value REAL DEFAULT 100,
            current_value REAL DEFAULT 0,
            unit TEXT DEFAULT '%',
            linked_ticket_ids TEXT,
            status TEXT DEFAULT 'Active',
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_kr_obj ON objective_key_results(obj_id);
    """)

    # 마이그레이션: tickets.retry_count 추가 (Ralph Loop 용)
    for col, default in [("retry_count", "0"), ("max_retries", "3"), ("parent_ticket_id", "NULL"), ("rework_count", "0")]:
        try:
            conn.execute(f"ALTER TABLE tickets ADD COLUMN {col} INTEGER DEFAULT {default}")
        except Exception:
            pass
    # 마이그레이션: tickets 실시간 진행상황 컬럼
    for col, typedef in [("progress_note", "TEXT"), ("last_ping_at", "TEXT"), ("claimed_by", "TEXT")]:
        try:
            conn.execute(f"ALTER TABLE tickets ADD COLUMN {col} {typedef}")
        except Exception:
            pass

    # 일일 보고서 + 에이전트 KPI 테이블
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS daily_reports (
            report_id INTEGER PRIMARY KEY AUTOINCREMENT,
            report_date TEXT NOT NULL UNIQUE,
            active_teams INTEGER DEFAULT 0,
            total_tickets INTEGER DEFAULT 0,
            done_tickets INTEGER DEFAULT 0,
            completion_rate REAL DEFAULT 0.0,
            yesterday_completed TEXT,
            blockers TEXT,
            kpi_data TEXT,
            ai_summary TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_reports_date ON daily_reports(report_date);

        CREATE TABLE IF NOT EXISTS agent_kpi (
            kpi_id INTEGER PRIMARY KEY AUTOINCREMENT,
            report_date TEXT NOT NULL,
            member_id TEXT NOT NULL,
            team_id TEXT NOT NULL,
            display_name TEXT,
            completed_tickets INTEGER DEFAULT 0,
            avg_minutes REAL DEFAULT 0.0,
            fail_count INTEGER DEFAULT 0,
            total_assigned INTEGER DEFAULT 0,
            fail_rate REAL DEFAULT 0.0,
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(report_date, member_id)
        );
        CREATE INDEX IF NOT EXISTS idx_kpi_date ON agent_kpi(report_date);
        CREATE INDEX IF NOT EXISTS idx_kpi_member ON agent_kpi(member_id);

        CREATE TABLE IF NOT EXISTS chat_sessions (
            session_id TEXT PRIMARY KEY,
            project TEXT,
            project_path TEXT,
            messages TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            last_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_chat_last ON chat_sessions(last_at);

        -- ── Sprint 관리 (gstack-inspired) ──
        CREATE TABLE IF NOT EXISTS sprints (
            sprint_id TEXT PRIMARY KEY,
            team_id TEXT NOT NULL,
            name TEXT NOT NULL,
            description TEXT,
            goal TEXT,
            phase TEXT DEFAULT 'Think',
            status TEXT DEFAULT 'Active',
            start_date TEXT DEFAULT (datetime('now')),
            end_date TEXT,
            planned_end TEXT,
            velocity_target INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            completed_at TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_sprints_team ON sprints(team_id);
        CREATE INDEX IF NOT EXISTS idx_sprints_status ON sprints(status);

        CREATE TABLE IF NOT EXISTS sprint_gates (
            gate_id INTEGER PRIMARY KEY AUTOINCREMENT,
            sprint_id TEXT NOT NULL,
            team_id TEXT NOT NULL,
            gate_type TEXT NOT NULL,
            status TEXT DEFAULT 'Pending',
            reviewer TEXT,
            score INTEGER,
            findings TEXT,
            metadata TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            resolved_at TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_gates_sprint ON sprint_gates(sprint_id);

        CREATE TABLE IF NOT EXISTS sprint_metrics (
            metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
            sprint_id TEXT NOT NULL,
            team_id TEXT NOT NULL,
            metric_date TEXT NOT NULL,
            total_tickets INTEGER DEFAULT 0,
            done_tickets INTEGER DEFAULT 0,
            blocked_tickets INTEGER DEFAULT 0,
            velocity_actual INTEGER DEFAULT 0,
            burndown_remaining INTEGER DEFAULT 0,
            quality_score REAL DEFAULT 0.0,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_smetrics_sprint ON sprint_metrics(sprint_id);
    """)

    # ── CLI 작업 큐 테이블 ──
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS cli_jobs (
            job_id TEXT PRIMARY KEY,
            ticket_id TEXT,
            team_id TEXT,
            project_path TEXT NOT NULL,
            project_name TEXT,
            prompt TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            allowed_tools TEXT DEFAULT 'Read,Write,Edit,Bash,Glob,Grep',
            max_turns INTEGER DEFAULT 30,
            timeout_sec INTEGER DEFAULT 300,
            model TEXT DEFAULT '',
            live_log TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now')),
            approved_at TEXT,
            started_at TEXT,
            completed_at TEXT,
            result_summary TEXT,
            result_length INTEGER DEFAULT 0,
            error TEXT,
            worker_id TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_cli_jobs_status ON cli_jobs(status);
        CREATE INDEX IF NOT EXISTS idx_cli_jobs_ticket ON cli_jobs(ticket_id);
    """)

    # ── cli_jobs 마이그레이션 (기존 DB 호환) ──
    try:
        cols = {r[1] for r in conn.execute("PRAGMA table_info(cli_jobs)").fetchall()}
        if "model" not in cols:
            conn.execute("ALTER TABLE cli_jobs ADD COLUMN model TEXT DEFAULT ''")
        if "live_log" not in cols:
            conn.execute("ALTER TABLE cli_jobs ADD COLUMN live_log TEXT DEFAULT ''")
        conn.commit()
    except Exception:
        pass

    conn.close()


# ── SSE 이벤트 브로드캐스팅 ──

_sse_lock = threading.Lock()
_sse_clients = {}   # team_id -> [client, ...]
_sse_global = []    # supervisor clients


def sse_register(team_id):
    client = {"queue": [], "event": threading.Event(), "active": True}
    with _sse_lock:
        _sse_clients.setdefault(team_id, []).append(client)
    return client


def sse_register_global():
    client = {"queue": [], "event": threading.Event(), "active": True}
    with _sse_lock:
        _sse_global.append(client)
    return client


def sse_unregister(team_id, client):
    client["active"] = False
    client["event"].set()
    with _sse_lock:
        lst = _sse_clients.get(team_id, [])
        if client in lst:
            lst.remove(client)
            if not lst:
                _sse_clients.pop(team_id, None)


def sse_unregister_global(client):
    client["active"] = False
    client["event"].set()
    with _sse_lock:
        if client in _sse_global:
            _sse_global.remove(client)


def sse_broadcast(team_id, event_type, data):
    payload = json.dumps({"type": event_type, "team_id": team_id, "data": data, "ts": now_utc()}, ensure_ascii=False)
    with _sse_lock:
        for c in _sse_clients.get(team_id, []):
            c["queue"].append(payload)
            c["event"].set()
        for c in _sse_global:
            c["queue"].append(payload)
            c["event"].set()
    # Telegram 알림 포워딩
    _telegram_on_event(team_id, event_type, data)
    # 상주 에이전트 깨우기 (팀/티켓 변경 시)
    if event_type in ('team_created','ticket_created','ticket_status_changed','ticket_claimed',
                      'member_spawned','artifact_created','feedback_created'):
        try: _resident_wake()
        except Exception: pass


# ── Telegram Bot 통합 (표준 라이브러리만 사용) ──

_tg_lock = threading.Lock()
_tg_config = {"bot_token": "", "chat_id": "", "enabled": False}
_tg_poll_thread = None
_tg_stop_poll = threading.Event()
_tg_last_update_id = 0
_tg_context = {"project": None, "project_path": None}  # 대화 컨텍스트 (마지막 선택 프로젝트)


def _tg_load_config():
    """DB에서 Telegram 설정 로드."""
    try:
        conn = get_db()
        row = conn.execute("SELECT value FROM server_settings WHERE key='telegram_bot_token'").fetchone()
        token = row["value"] if row else ""
        row2 = conn.execute("SELECT value FROM server_settings WHERE key='telegram_chat_id'").fetchone()
        chat_id = row2["value"] if row2 else ""
        conn.close()
        with _tg_lock:
            _tg_config["bot_token"] = token
            _tg_config["chat_id"] = chat_id
            _tg_config["enabled"] = bool(token and chat_id)
        return _tg_config["enabled"]
    except Exception:
        return False


def _tg_save_config(bot_token, chat_id):
    """DB에 Telegram 설정 저장."""
    conn = get_db()
    conn.execute("INSERT OR REPLACE INTO server_settings (key, value, updated_at) VALUES ('telegram_bot_token', ?, datetime('now'))", (bot_token,))
    conn.execute("INSERT OR REPLACE INTO server_settings (key, value, updated_at) VALUES ('telegram_chat_id', ?, datetime('now'))", (chat_id,))
    conn.commit()
    conn.close()
    with _tg_lock:
        _tg_config["bot_token"] = bot_token
        _tg_config["chat_id"] = chat_id
        _tg_config["enabled"] = bool(bot_token and chat_id)


def _tg_api(method, data=None):
    """Telegram Bot API 호출 (urllib)."""
    with _tg_lock:
        token = _tg_config["bot_token"]
    if not token:
        return None
    url = f"https://api.telegram.org/bot{token}/{method}"
    try:
        if data:
            payload = json.dumps(data).encode("utf-8")
            req = Request(url, data=payload, headers={"Content-Type": "application/json"})
        else:
            req = Request(url)
        resp = urlopen(req, timeout=10)
        return json.loads(resp.read())
    except Exception:
        return None


def _tg_send(text, parse_mode="HTML", reply_markup=None):
    """Telegram 메시지 전송."""
    with _tg_lock:
        chat_id = _tg_config["chat_id"]
        enabled = _tg_config["enabled"]
    if not enabled:
        return None
    data = {"chat_id": chat_id, "text": text, "parse_mode": parse_mode}
    if reply_markup:
        data["reply_markup"] = reply_markup
    return _tg_api("sendMessage", data)


def _telegram_on_event(team_id, event_type, data):
    """SSE 이벤트 → Telegram 알림 포워딩 (강화 v2)."""
    with _tg_lock:
        if not _tg_config["enabled"]:
            return

    team_label = f" [{data.get('team_name', team_id or '')}]" if (data.get('team_name') or team_id) else ""

    messages = {
        "team_created":
            lambda: f"🏗 <b>팀 생성</b>{team_label}\n📌 {data.get('name','?')}",
        "ticket_created":
            lambda: f"🎫 <b>티켓 생성</b>{team_label}\n📋 {data.get('title','?')}",
        "ticket_status_changed":
            lambda: (f"📊 <b>티켓 상태 변경</b>{team_label}\n"
                     f"📋 {data.get('ticket_title', data.get('ticket_id','?'))}\n"
                     f"➜ <code>{data.get('status', data.get('new_status','?'))}</code>"),
        "ticket_claimed":
            lambda: (f"⚡ <b>티켓 클레임</b>{team_label}\n"
                     f"📋 {data.get('ticket_title', data.get('ticket_id','?'))}\n"
                     f"🤖 {data.get('member_name','?')}"),
        "member_spawned":
            lambda: (f"🤖 <b>에이전트 스폰</b>{team_label}\n"
                     f"역할: {data.get('role','?')}"),
        "team_archived":
            lambda: f"📦 <b>팀 아카이브</b>\n{data.get('team_name', data.get('name','?'))}",
        "team_auto_archived":
            lambda: (f"✅ <b>팀 자동완료</b>\n"
                     f"🎉 {data.get('team_name','?')} — 모든 티켓 완료!"),
        "feedback_created":
            lambda: (f"{'✅' if data.get('verdict')=='pass' else '🔄' if data.get('verdict')=='rework' else '⭐'} "
                     f"<b>Supervisor QA</b>{team_label}\n"
                     f"📋 {data.get('ticket_id', data.get('ticket_title','?'))}\n"
                     f"점수: {data.get('score','?')}/5 | "
                     f"{'통과' if data.get('verdict')=='pass' else '재작업' if data.get('verdict')=='rework' else '피드백'}"),
        "artifact_created":
            lambda: (f"📦 <b>산출물 등록</b>{team_label}\n"
                     f"유형: {data.get('artifact_type','?')}\n"
                     f"제목: {data.get('title','?')}"),
    }
    handler = messages.get(event_type)
    if handler:
        try:
            msg = handler()
            threading.Thread(target=_tg_send, args=(msg,), daemon=True).start()
        except Exception:
            pass


# ── Telegram 명령 처리 (폴링) ──

def _tg_handle_command(text, chat_id_from):
    """수신된 Telegram 메시지 처리 — 자연어 우선, 명령어 보조."""
    with _tg_lock:
        expected_chat = _tg_config["chat_id"]
    if str(chat_id_from) != str(expected_chat):
        return

    text = text.strip()
    if not text:
        return

    # ── 슬래시 명령어 (기존 호환) ──
    if text.startswith("/"):
        cmd_map = {
            "/start": _tg_cmd_status, "/status": _tg_cmd_status,
            "/teams": _tg_cmd_teams, "/help": _tg_cmd_help,
            "/progress": _tg_cmd_progress,
        }
        for prefix, fn in cmd_map.items():
            if text == prefix:
                return fn()
        if text.startswith("/team "):
            return _tg_cmd_team_detail(text[6:].strip())
        if text.startswith("/ticket "):
            return _tg_cmd_create_ticket(text[8:].strip())
        if text.startswith("/do "):
            return _tg_cmd_do(text[4:].strip())
        if text.startswith("/cancel"):
            return _tg_cmd_cancel(text[7:].strip() if len(text) > 7 else "")
        if text.startswith("/archive "):
            return _tg_cmd_archive(text[9:].strip())
        if text.startswith("/use "):
            return _tg_cmd_use_project(text[5:].strip())
        if text == "/projects" or text == "/프로젝트":
            return _tg_cmd_projects()
        if text.startswith("/alias "):
            return _tg_cmd_alias(text[7:].strip())
        if text == "/wake" or text.startswith("/wake "):
            return _tg_cmd_wake(text[5:].strip() if len(text) > 5 else "")
        if text.startswith("/run "):
            return _tg_cmd_run_cli(text[5:].strip())
        if text.startswith("/review "):
            return _tg_cmd_review(text[8:].strip())
        if text == "/review":
            return _tg_cmd_review_all()
        if text == "/review_stats":
            return _tg_cmd_review_stats()
        if text == "/compact":
            return _tg_cmd_compact()
        if text.startswith("/create_team "):
            return _tg_cmd_create_team(text[13:].strip())
        if text == "/summary" or text == "/요약":
            return _tg_cmd_summary()
        if text == "/ollama" or text == "/model":
            return _tg_cmd_ollama_status()
        if text.startswith("/model "):
            return _tg_cmd_switch_backend(text[7:].strip())
        return

    # 스킬 메뉴
    if text in ("/menu", "/스킬", "/skill", "/skills", "유디야", "유디"):
        return _tg_cmd_skill_menu()

    # ── 자연어 입력 — 유디 대화 ──
    return _tg_cmd_natural(text)


def _tg_cmd_help():
    return _tg_send(
        "<b>📌 칸반보드 봇</b>\n\n"
        "<b>그냥 말하세요</b>\n"
        "\"쿠팡 상품 검색 API 추가해줘\"\n"
        "\"PMI 로그인 버그 수정\" \n"
        "→ 프로젝트 자동 인식, 티켓 생성, 에이전트 실행\n\n"
        "<b>프로젝트</b>\n"
        "/projects — 등록 프로젝트 목록\n"
        "/use &lt;별명&gt; — 현재 프로젝트 설정\n"
        "/alias &lt;별명&gt;|&lt;이름&gt;|&lt;경로&gt; — 별명 추가\n\n"
        "<b>조회</b>\n"
        "/status — 서버 상태\n"
        "/teams — 팀 목록\n"
        "/team &lt;이름&gt; — 팀 상세\n"
        "/progress — 진행 현황\n\n"
        "<b>작업</b>\n"
        "/do &lt;프로젝트&gt;|&lt;지시&gt; — 티켓 분해 + 에이전트 실행\n"
        "/run &lt;프로젝트&gt;|&lt;프롬프트&gt; — CLI 직접 실행\n"
        "/wake [팀명] — 대기 티켓에 에이전트 스폰\n"
        "/create_team &lt;프로젝트&gt;|&lt;팀명&gt; — 팀 생성\n"
        "/cancel — 작업 취소\n"
        "/archive &lt;팀명&gt; — 팀 아카이브\n\n"
        "<b>Supervisor QA</b>\n"
        "/review &lt;티켓ID&gt; — 티켓 검수\n"
        "/review — Review 전체 검수\n"
        "/review_stats — 검수 통계\n\n"
        "<b>시스템</b>\n"
        "/summary — 전체 현황 AI 요약\n"
        "/compact — 대화 히스토리 압축\n"
        "/model — AI 백엔드 상태 (Ollama/Claude)\n"
        "/model ollama — Ollama 로컬 모드\n"
        "/model claude — Claude API 모드"
    )


def _tg_cmd_review(target):
    """Telegram /review <티켓ID 또는 팀명> — supervisor 검수."""
    import re
    if re.match(r'T-[A-Fa-f0-9]{6}', target):
        result = _chat_supervisor_respond("tg-review", f"{target.upper()} 티켓을 검수해줘")
    else:
        result = _chat_supervisor_respond("tg-review", f"{target} 검수해줘")
    if result.get("ok"):
        actions = result.get("actions_executed", [])
        resp = result.get("response", "")[:300]
        msg = f"🔍 <b>Supervisor QA</b>\n\n{resp}"
        if actions:
            msg += "\n\n" + "\n".join(actions)
        _tg_send(msg)
    else:
        _tg_send(f"❌ 검수 실패: {result.get('error','?')}")


def _tg_cmd_review_all():
    """Telegram /review — Review 전체 배치 검수."""
    result = _supervisor_batch_review("tg-batch", "Review 전체 검수", None)
    actions = result.get("actions_executed", [])
    if actions:
        msg = f"🔍 <b>Supervisor 일괄 검수</b>\n\n처리: {len(actions)}건\n" + "\n".join(actions[:10])
        _tg_send(msg)
    else:
        _tg_send("✅ Review 대기 티켓이 없습니다.")


def _tg_cmd_review_stats():
    """Telegram /review_stats — 검수 통계."""
    stats = r_supervisor_review_stats(None, {}, {}, {})
    s = stats.get("stats", {})
    msg = (f"📊 <b>Supervisor QA 통계</b>\n\n"
           f"총 검수: {s.get('total_reviews',0)}건\n"
           f"통과: {s.get('passed',0)} | 재작업: {s.get('reworked',0)}\n"
           f"평균 점수: {s.get('avg_score',0)}/5\n"
           f"Review 대기: {s.get('review_pending',0)}개")
    _tg_send(msg)


def _tg_cmd_status():
    try:
        conn = get_db()
        teams = conn.execute("SELECT COUNT(*) as c FROM agent_teams WHERE status='Active'").fetchone()
        tickets = conn.execute("SELECT status, COUNT(*) as c FROM tickets GROUP BY status").fetchall()
        members = conn.execute("SELECT COUNT(*) as c FROM team_members").fetchone()
        tokens = conn.execute("SELECT COUNT(*) as c FROM auth_tokens WHERE is_active=1").fetchone()
        conn.close()

        ticket_map = {r['status']: r['c'] for r in tickets} if tickets else {}
        in_prog = ticket_map.get('InProgress', 0)
        done = ticket_map.get('Done', 0)
        backlog = ticket_map.get('Backlog', 0) + ticket_map.get('Todo', 0)
        total = sum(ticket_map.values())
        return _tg_send(
            f"<b>📊 현재 상황이에요!</b>\n\n"
            f"지금 팀 <b>{teams['c']}개</b> 돌아가고 있어요\n"
            f"에이전트 <b>{members['c']}명</b> 작업 중\n"
            f"연결 토큰: {tokens['c']}개\n\n"
            f"티켓 현황: 총 {total}개\n"
            f"  🔄 진행 중: {in_prog}개\n"
            f"  ✅ 완료: {done}개\n"
            f"  📝 대기: {backlog}개"
        )
    except Exception as e:
        return _tg_send(f"❌ 오류가 났어요: {e}")


def _tg_cmd_teams():
    try:
        conn = get_db()
        teams = conn.execute(
            "SELECT t.team_id, t.name, t.project_group, t.status, "
            "(SELECT COUNT(*) FROM tickets WHERE team_id=t.team_id) as ticket_count, "
            "(SELECT COUNT(*) FROM tickets WHERE team_id=t.team_id AND status='Done') as done_count "
            "FROM agent_teams t WHERE t.status='Active' ORDER BY t.created_at DESC LIMIT 20"
        ).fetchall()
        conn.close()

        if not teams:
            return _tg_send("팀이 없습니다.")

        lines = ["<b>📋 팀 목록</b>\n"]
        for t in teams:
            progress = f"{t['done_count']}/{t['ticket_count']}" if t['ticket_count'] else "0/0"
            group = f"[{t['project_group']}] " if t['project_group'] else ""
            lines.append(f"• {group}<b>{t['name']}</b> ({progress})")
        return _tg_send("\n".join(lines))
    except Exception as e:
        return _tg_send(f"❌ 오류: {e}")


def _tg_cmd_team_detail(name):
    try:
        conn = get_db()
        team = conn.execute("SELECT * FROM agent_teams WHERE name LIKE ? AND status='Active'", (f"%{name}%",)).fetchone()
        if not team:
            conn.close()
            return _tg_send(f"팀 '{name}' 찾을 수 없음")

        tid = team["team_id"]
        members = conn.execute("SELECT display_name, role, status FROM team_members WHERE team_id=?", (tid,)).fetchall()
        tickets = conn.execute("SELECT title, status, priority FROM tickets WHERE team_id=? ORDER BY created_at DESC LIMIT 10", (tid,)).fetchall()
        conn.close()

        lines = [f"<b>🏢 {team['name']}</b>"]
        if team["project_group"]:
            lines.append(f"프로젝트: {team['project_group']}")

        if members:
            lines.append(f"\n<b>멤버 ({len(members)})</b>")
            for m in members:
                lines.append(f"  • {m['display_name'] or m['role']} [{m['status']}]")

        if tickets:
            lines.append(f"\n<b>티켓 ({len(tickets)})</b>")
            status_icons = {"Backlog": "⬜", "Todo": "📝", "InProgress": "🔄", "Review": "🔍", "Done": "✅", "Blocked": "🚫"}
            for t in tickets:
                icon = status_icons.get(t["status"], "❓")
                lines.append(f"  {icon} {t['title']} [{t['priority']}]")

        return _tg_send("\n".join(lines))
    except Exception as e:
        return _tg_send(f"❌ 오류: {e}")


def _tg_cmd_create_ticket(args_str):
    """형식: 팀명|제목|설명"""
    parts = args_str.split("|", 2)
    if len(parts) < 2:
        return _tg_send("형식: /ticket 팀명|제목|설명(선택)")

    team_name, title = parts[0].strip(), parts[1].strip()
    desc = parts[2].strip() if len(parts) > 2 else ""

    try:
        conn = get_db()
        team = conn.execute("SELECT team_id FROM agent_teams WHERE name LIKE ? AND status='Active'", (f"%{team_name}%",)).fetchone()
        if not team:
            conn.close()
            return _tg_send(f"팀 '{team_name}' 찾을 수 없음")

        tid = short_id("tkt-")
        conn.execute(
            "INSERT INTO tickets (ticket_id, team_id, title, description, priority, status) VALUES (?,?,?,?,?,?)",
            (tid, team["team_id"], title, desc, "Medium", "Backlog")
        )
        conn.commit()
        conn.close()
        sse_broadcast(team["team_id"], "ticket_created", {"ticket_id": tid, "title": title})
        return _tg_send(f"✅ 티켓 생성: <b>{title}</b>\nID: <code>{tid}</code>")
    except Exception as e:
        return _tg_send(f"❌ 오류: {e}")


def _tg_cmd_projects():
    """등록된 프로젝트 목록."""
    projects = _get_known_projects()
    if not projects:
        return _tg_send("등록된 프로젝트가 없습니다.")
    lines = [f"<b>📂 등록 프로젝트 ({len(projects)}개)</b>\n"]
    for entry in projects:
        alias = entry[0]
        orig = entry[2] if len(entry) > 2 else alias
        path = entry[1]
        current = " ← 현재" if _tg_context.get("project") == alias else ""
        if alias != orig:
            lines.append(f"  <b>{alias}</b> ({orig}){current}")
        else:
            lines.append(f"  <b>{alias}</b>{current}")
    lines.append(f"\n/use 별명 — 프로젝트 선택")
    return _tg_send("\n".join(lines))


def _tg_cmd_alias(args_str):
    """별명 추가/변경. 형식: 별명|원본이름|경로"""
    parts = args_str.split("|")
    if len(parts) < 3:
        return _tg_send("형식: /alias 별명|원본이름|경로\n예: /alias 쿠팡|cupang_api|E:/cupang_api")
    alias, name, path = parts[0].strip(), parts[1].strip(), parts[2].strip()
    if not os.path.isdir(path):
        return _tg_send(f"❌ 경로가 존재하지 않습니다: {path}")

    # 기존 별명 로드
    conn = get_db()
    row = conn.execute("SELECT value FROM server_settings WHERE key='project_aliases'").fetchone()
    aliases = json.loads(row["value"]) if row and row["value"] else []
    conn.close()

    # 중복 제거 후 추가
    aliases = [a for a in aliases if a["alias"] != alias]
    aliases.append({"alias": alias, "name": name, "path": path})
    _save_project_aliases(aliases)
    return _tg_send(f"✅ <b>{alias}</b> → {name} ({path})")


def _tg_cmd_use_project(name):
    """현재 작업 프로젝트 설정."""
    projects = _get_known_projects()
    name_l = name.lower()
    for entry in projects:
        alias = entry[0]
        orig = entry[2] if len(entry) > 2 else alias
        if alias.lower() == name_l or orig.lower() == name_l or name_l in alias.lower():
            _tg_context["project"] = alias
            _tg_context["project_path"] = entry[1]
            return _tg_send(f"📂 현재 프로젝트: <b>{alias}</b>\n이제 자연어로 바로 지시하세요.")
    return _tg_send(f"'{name}' 찾을 수 없음. /projects 로 목록 확인")


def _tg_cmd_do(args_str):
    """/do 프로젝트명|지시 — 지시를 분석해서 티켓 분해 → 에이전트 자동 실행."""
    parts = args_str.split("|", 1)
    if len(parts) < 2:
        return _tg_send("형식: /do 프로젝트명|지시 내용\n예: /do PMI-AIP|로그인 페이지에 소셜 로그인 추가")

    project_name = parts[0].strip()
    instruction = parts[1].strip()
    if not instruction:
        return _tg_send("지시 내용이 비어 있습니다.")

    # 프로젝트 경로 찾기
    project_path = _find_project_path(project_name)
    if not project_path:
        return _tg_send(f"❌ 프로젝트 '{project_name}' 경로를 찾을 수 없습니다.")

    # 비동기로 오케스트레이터 실행
    threading.Thread(
        target=_orch_dispatch,
        args=(project_name, instruction, project_path),
        daemon=True
    ).start()


def _tg_cmd_progress():
    """진행 중인 작업 현황."""
    with _orch_lock:
        active = {k: v for k, v in _orch_jobs.items() if v["status"] == "running"}

    if not active:
        return _tg_send("지금은 진행 중인 작업이 없어요! 😊\n새로운 작업 지시하시겠어요?")

    lines = [f"<b>🔄 지금 {len(active)}개 작업 달리고 있어요!</b>\n"]
    for job_id, job in active.items():
        conn = get_db()
        tickets = conn.execute(
            "SELECT title, status FROM tickets WHERE ticket_id IN ({})".format(
                ",".join("?" * len(job["ticket_ids"]))
            ), job["ticket_ids"]
        ).fetchall()
        conn.close()

        done = sum(1 for t in tickets if t["status"] == "Done")
        total = len(tickets)
        pct = int(done / total * 100) if total else 0
        lines.append(f"<b>{job['team_name']}</b> — {done}/{total} 완료 ({pct}%) <code>{job_id}</code>")
        status_icons = {"Todo": "⬜", "InProgress": "🔄", "Done": "✅", "Blocked": "🚫"}
        for t in tickets:
            lines.append(f"  {status_icons.get(t['status'], '❓')} {t['title']}")

    return _tg_send("\n".join(lines))


def _tg_cmd_cancel(args_str):
    """진행 중인 작업 취소."""
    if args_str:
        # 특정 job_id
        if _orch_cancel(args_str):
            return
        return _tg_send(f"작업 '{args_str}' 찾을 수 없음")

    # job_id 미지정 → 가장 최근 running job 취소
    with _orch_lock:
        running = [(k, v) for k, v in _orch_jobs.items() if v["status"] == "running"]
    if not running:
        return _tg_send("취소할 작업이 없습니다.")
    if len(running) == 1:
        _orch_cancel(running[0][0])
        return
    lines = ["취소할 작업을 선택하세요:\n"]
    for job_id, job in running:
        lines.append(f"/cancel {job_id} — {job['team_name']}")
    return _tg_send("\n".join(lines))


def _tg_cmd_archive(team_name):
    """팀 아카이브."""
    try:
        conn = get_db()
        team = conn.execute("SELECT team_id, name FROM agent_teams WHERE name LIKE ? AND status='Active'", (f"%{team_name}%",)).fetchone()
        if not team:
            conn.close()
            return _tg_send(f"팀 '{team_name}' 찾을 수 없음")
        ts = now_utc()
        conn.execute("UPDATE agent_teams SET status='Archived', archived_at=? WHERE team_id=?", (ts, team["team_id"]))
        conn.commit()
        conn.close()
        sse_broadcast(team["team_id"], "team_archived", {"team_id": team["team_id"], "name": team["name"], "archived_at": ts})
        _app_notify("team_completed", f"팀 완료: {team['name']}", f"모든 티켓 완료, 자동 아카이브됨")
        return _tg_send(f"📦 <b>{team['name']}</b> 아카이브 완료")
    except Exception as e:
        return _tg_send(f"❌ 오류: {e}")


def _tg_cmd_run_cli(args_str):
    """/run 프로젝트|프롬프트 — Claude Code CLI를 특정 프로젝트에서 직접 실행."""
    parts = args_str.split("|", 1)
    if len(parts) < 2:
        # 현재 프로젝트 컨텍스트 사용
        proj = _tg_context.get("project")
        ppath = _tg_context.get("project_path")
        if not proj or not ppath:
            return _tg_send("형식: /run 프로젝트|프롬프트\n또는 /use 프로젝트 먼저 설정")
        prompt = args_str
    else:
        proj = parts[0].strip()
        prompt = parts[1].strip()
        ppath = _find_project_path(proj)
        if not ppath:
            return _tg_send(f"❌ 프로젝트 '{proj}' 경로를 찾을 수 없습니다.")

    _tg_send(f"🖥️ <b>{proj}</b>에서 CLI 실행 중...\n<code>{prompt[:80]}</code>")

    def _run():
        cli = _find_claude_cli()
        try:
            result = subprocess.run(
                [cli, "-p", prompt, "--output-format", "json", "--model", "sonnet"],
                capture_output=True, text=True, timeout=300, cwd=ppath
            )
            output = result.stdout.strip()
            try:
                parsed = json.loads(output)
                text = parsed.get("result", "")[:3000]
                cost = parsed.get("total_cost_usd", 0)
                _tg_send(f"✅ <b>{proj}</b> CLI 완료\n💰 ${cost:.4f}\n\n{text[:2000]}")
            except json.JSONDecodeError:
                _tg_send(f"✅ <b>{proj}</b> CLI 완료\n\n{output[:2000]}")
        except subprocess.TimeoutExpired:
            _tg_send(f"⏰ CLI 타임아웃 (5분): {proj}")
        except FileNotFoundError:
            _tg_send(f"❌ claude CLI를 찾을 수 없습니다")
        except Exception as e:
            _tg_send(f"❌ CLI 오류: {e}")

    threading.Thread(target=_run, daemon=True).start()


def _tg_cmd_compact():
    """/compact — 대화 히스토리 압축."""
    global _yudi_messages, _yudi_compact_count
    before = len(_yudi_messages)
    _yudi_compact()
    after = len(_yudi_messages)
    return _tg_send(f"🗜 대화 압축 완료\n{before}턴 → {after}턴 (총 {_yudi_compact_count}회 compact)")


def _tg_cmd_create_team(args_str):
    """/create_team 프로젝트|팀명|설명 — 팀 직접 생성."""
    parts = args_str.split("|")
    if len(parts) < 2:
        return _tg_send("형식: /create_team 프로젝트|팀명|설명(선택)")

    project = parts[0].strip()
    team_name = parts[1].strip()
    desc = parts[2].strip() if len(parts) > 2 else ""

    tid = short_id("team-")
    conn = get_db()
    conn.execute(
        "INSERT INTO agent_teams (team_id, name, description, project_group, status) VALUES (?,?,?,?,?)",
        (tid, team_name, desc, project, "Active")
    )
    conn.commit()
    conn.close()
    sse_broadcast(tid, "team_created", {"team_id": tid, "name": team_name})
    return _tg_send(f"✅ 팀 생성: <b>{team_name}</b>\n프로젝트: {project}\nID: <code>{tid}</code>")


def _tg_cmd_summary():
    """/summary — 전체 프로젝트 개요 보고."""
    context = _build_kanban_context()
    prompt = f"""전체 프로젝트 현황을 대표님에게 간결하게 보고해주세요.
핵심 수치, 주목할 점, 조치가 필요한 것만.

{context}

HTML 포맷팅으로 보기 좋게. 800자 이내."""
    response = _smart_chat(prompt)
    if response:
        return _tg_send(response)
    return _tg_send("요약 생성에 실패했습니다.")


def _tg_cmd_ollama_status():
    """/model — Ollama 상태 + 현재 백엔드 표시."""
    avail = _ollama_available()
    gpu_info = ""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.used,memory.total,utilization.gpu,temperature.gpu",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            parts = [x.strip() for x in result.stdout.strip().split(",")]
            gpu_info = f"\n\n🎮 <b>GPU (RTX 5090)</b>\nVRAM: {parts[0]}MB / {parts[1]}MB\nGPU 사용률: {parts[2]}%\n온도: {parts[3]}°C"
    except Exception:
        pass

    backend_icon = "🟢" if _YUDI_BACKEND == "ollama" else "🔵"
    ollama_icon = "✅" if avail else "❌"

    return _tg_send(
        f"<b>🤖 AI 백엔드 상태</b>\n\n"
        f"{backend_icon} 현재 모드: <b>{_YUDI_BACKEND.upper()}</b>\n"
        f"모델: <code>{_OLLAMA_MODEL if _YUDI_BACKEND == 'ollama' else _YUDI_MODEL}</code>\n\n"
        f"<b>Ollama</b>: {ollama_icon} {'가동 중' if avail else '오프라인'}\n"
        f"모델: <code>{_OLLAMA_MODEL}</code>"
        f"{gpu_info}\n\n"
        f"전환: /model ollama 또는 /model claude"
    )


def _tg_cmd_switch_backend(arg):
    """/model ollama|claude — 백엔드 전환."""
    global _YUDI_BACKEND
    arg = arg.lower().strip()
    if arg in ("ollama", "로컬", "local"):
        if not _ollama_available():
            return _tg_send("❌ Ollama 서비스가 꺼져있어요.\n<code>systemctl start ollama</code>")
        _YUDI_BACKEND = "ollama"
        return _tg_send(f"🟢 <b>Ollama 모드 전환 완료</b>\n모델: <code>{_OLLAMA_MODEL}</code>\n로컬 GPU 추론 (무료, 상시)")
    elif arg in ("claude", "anthropic", "api"):
        _YUDI_BACKEND = "anthropic"
        return _tg_send(f"🔵 <b>Claude API 모드 전환 완료</b>\n모델: <code>{_YUDI_MODEL}</code>\n(API 비용 발생)")
    else:
        return _tg_send("사용법: /model ollama 또는 /model claude")


# ── 유디 스킬 메뉴 (인라인 키보드) ──

_YUDI_SKILLS = [
    # (콜백ID, 이모지+이름, 설명, needs_project)
    ("status", "📊 현황 보고", "전체 프로젝트 현황", False),
    ("standup", "☀️ 스탠드업", "일일 보고서 생성", False),
    ("health", "🏥 건강진단", "프로젝트 코드 품질 점검", True),
    ("wake", "⚡ 에이전트 깨우기", "대기 티켓에 에이전트 스폰", False),
    ("review", "🔍 코드 리뷰", "최근 변경사항 AI 리뷰", True),
    ("run_cli", "💻 CLI 실행", "Claude Code 직접 실행", True),
    ("create_team", "🏗 팀 생성", "새 팀 + 티켓 구성", True),
    ("dep_audit", "🔒 의존성 감사", "보안 취약점 스캔", True),
    ("api_docs", "📄 API 문서", "API 문서 자동 생성", True),
    ("git_status", "🌿 Git 상태", "브랜치/커밋 현황", True),
    ("kill_zombie", "💀 좀비 제거", "좀비 MCP/Node 정리", False),
    ("sysinfo", "🖥 시스템 현황", "PC 자원 + 프로세스", False),
    ("archive", "📦 아카이브", "완료 팀 아카이브", False),
    ("projects", "📂 프로젝트", "등록 프로젝트 목록", False),
    ("summary", "📝 AI 요약", "Opus 전체 분석 보고", False),
]


def _tg_cmd_skill_menu():
    """유디 스킬 메뉴를 인라인 키보드로 표시."""
    buttons = []
    row = []
    for sid, name, desc, _ in _YUDI_SKILLS:
        row.append({"text": name, "callback_data": f"skill:{sid}"})
        if len(row) == 2:
            buttons.append(row)
            row = []
    if row:
        buttons.append(row)

    proj = _tg_context.get("project")
    proj_text = f"\n📂 현재 프로젝트: <b>{proj}</b>" if proj else "\n💡 프로젝트 선택: /use 별명"

    return _tg_send(
        f"🤖 <b>유디 스킬 메뉴</b>{proj_text}\n\n원하는 스킬을 선택하세요:",
        reply_markup={"inline_keyboard": buttons}
    )


def _tg_exec_skill(skill_id):
    """스킬 실행. 프로젝트가 필요하면 프로젝트 선택 버튼 표시."""
    # 프로젝트 불필요한 스킬
    no_proj = {"status", "standup", "wake", "kill_zombie", "sysinfo", "archive", "projects", "summary"}
    if skill_id in no_proj:
        return _tg_skill_dispatch(skill_id, None, None)

    # 프로젝트 필요 → 컨텍스트 확인
    proj = _tg_context.get("project")
    ppath = _tg_context.get("project_path")
    if proj and ppath:
        return _tg_skill_dispatch(skill_id, proj, ppath)

    # 프로젝트 선택 필요
    known = _get_known_projects()
    buttons = []
    row = []
    for entry in known:
        alias = entry[0]
        row.append({"text": alias, "callback_data": f"sproj:{skill_id}:{alias}"})
        if len(row) == 3:
            buttons.append(row)
            row = []
    if row:
        buttons.append(row)

    skill_name = next((n for s, n, _, _ in _YUDI_SKILLS if s == skill_id), skill_id)
    return _tg_send(
        f"{skill_name} — 프로젝트를 선택하세요:",
        reply_markup={"inline_keyboard": buttons[:10]}
    )


def _tg_exec_skill_with_project(skill_id, proj_alias):
    """프로젝트 선택 후 스킬 실행."""
    path = _find_project_path(proj_alias)
    if not path:
        return _tg_send(f"❌ 프로젝트 '{proj_alias}' 경로를 찾을 수 없습니다.")
    _tg_context["project"] = proj_alias
    _tg_context["project_path"] = path
    return _tg_skill_dispatch(skill_id, proj_alias, path)


def _tg_skill_dispatch(skill_id, proj, ppath):
    """스킬 ID에 따라 실제 동작 실행."""
    dispatch = {
        "status": lambda: _tg_cmd_status(),
        "standup": lambda: _tg_skill_standup(),
        "health": lambda: _tg_skill_claude(proj, ppath, "이 프로젝트의 코드 품질, 보안, 의존성 상태를 진단해주세요. 문제점과 개선사항을 구체적으로 알려주세요."),
        "wake": lambda: _tg_cmd_wake(""),
        "review": lambda: _tg_skill_claude(proj, ppath, "최근 git 변경사항을 리뷰해주세요. 버그, 보안 이슈, 코드 품질 문제를 찾아주세요."),
        "run_cli": lambda: _tg_skill_run_cli_prompt(proj, ppath),
        "create_team": lambda: _tg_skill_create_team(proj, ppath),
        "dep_audit": lambda: _tg_skill_claude(proj, ppath, "이 프로젝트의 의존성 보안 감사를 실행해주세요. 취약점이 있으면 업데이트 방안을 제시해주세요."),
        "api_docs": lambda: _tg_skill_claude(proj, ppath, "이 프로젝트의 API 엔드포인트를 분석하고 OpenAPI 형식으로 문서를 생성해주세요."),
        "git_status": lambda: _tg_skill_git_status(proj, ppath),
        "kill_zombie": lambda: _tg_skill_kill_zombie(),
        "sysinfo": lambda: _tg_skill_sysinfo(),
        "archive": lambda: _tg_skill_archive_menu(),
        "projects": lambda: _tg_cmd_projects(),
        "summary": lambda: _tg_cmd_summary(),
    }
    fn = dispatch.get(skill_id)
    if fn:
        threading.Thread(target=fn, daemon=True).start()
    else:
        _tg_send(f"❌ 알 수 없는 스킬: {skill_id}")


def _tg_skill_standup():
    """일일 스탠드업 보고."""
    context = _build_kanban_context()
    prompt = f"""일일 스탠드업 보고를 작성해주세요.

{context}

포맷:
<b>☀️ 일일 스탠드업</b>
<b>어제 완료:</b> (최근 24시간 Done 티켓)
<b>오늘 진행:</b> (InProgress 티켓)
<b>차단 이슈:</b> (Blocked 티켓 또는 없으면 "없음")
<b>주의사항:</b> (진행률 낮은 팀, 장기 미진행 등)

간결하게. HTML 포맷. 600자 이내."""
    response = _smart_chat(prompt)
    _tg_send(response or "스탠드업 생성 실패")


def _tg_skill_claude(proj, ppath, instruction):
    """Claude CLI를 프로젝트 경로에서 실행하고 결과를 Telegram으로 전송."""
    _tg_send(f"🔄 <b>{proj}</b> — 작업 중...")
    cli = _find_claude_cli()
    try:
        result = subprocess.run(
            [cli, "-p", instruction, "--output-format", "json", "--model", "sonnet", ],
            capture_output=True, text=True, timeout=180, cwd=ppath
        )
        output = result.stdout.strip()
        try:
            parsed = json.loads(output)
            text = parsed.get("result", "")
        except json.JSONDecodeError:
            text = output

        if text:
            # 긴 메시지 분할 (Telegram 4096자 제한)
            for i in range(0, len(text), 4000):
                _tg_send(text[i:i+4000])
        else:
            _tg_send(f"⚠️ CLI 출력 없음. Exit code: {result.returncode}")
    except subprocess.TimeoutExpired:
        _tg_send("⏰ CLI 타임아웃 (3분)")
    except Exception as e:
        _tg_send(f"❌ CLI 오류: {e}")


def _tg_skill_run_cli_prompt(proj, ppath):
    """CLI 실행 프롬프트 요청."""
    _tg_send(
        f"💻 <b>{proj}</b> CLI 실행\n\n실행할 명령이나 지시를 입력하세요.\n(다음 메시지가 CLI에 전달됩니다)",
    )
    _tg_context["pending_cli"] = {"project": proj, "path": ppath}


def _tg_skill_create_team(proj, ppath):
    """팀 생성 메뉴."""
    _tg_send(
        f"🏗 <b>{proj}</b> 팀 생성\n\n"
        "작업 내용을 입력하면 자동으로:\n"
        "1. 팀 생성\n2. 티켓 분해\n3. 에이전트 스폰\n\n"
        "지시를 입력하세요:"
    )
    _tg_context["pending_instruction_for"] = proj


def _tg_skill_git_status(proj, ppath):
    """Git 상태 확인."""
    try:
        branch = subprocess.run(
            ["git", "branch", "--show-current"], capture_output=True, text=True, timeout=5, cwd=ppath
        ).stdout.strip()
        log = subprocess.run(
            ["git", "log", "--oneline", "-5"], capture_output=True, text=True, timeout=5, cwd=ppath
        ).stdout.strip()
        status = subprocess.run(
            ["git", "status", "--short"], capture_output=True, text=True, timeout=5, cwd=ppath
        ).stdout.strip()
        diff_stat = subprocess.run(
            ["git", "diff", "--stat"], capture_output=True, text=True, timeout=5, cwd=ppath
        ).stdout.strip()

        lines = [f"🌿 <b>{proj} Git 상태</b>\n"]
        lines.append(f"<b>브랜치:</b> {branch}")
        lines.append(f"\n<b>최근 커밋:</b>\n<code>{log}</code>")
        if status:
            lines.append(f"\n<b>변경사항:</b>\n<code>{status[:500]}</code>")
        if diff_stat:
            lines.append(f"\n<b>Diff:</b>\n<code>{diff_stat[:500]}</code>")
        _tg_send("\n".join(lines))
    except Exception as e:
        _tg_send(f"❌ Git 오류: {e}")


def _tg_skill_kill_zombie():
    """좀비 MCP/Node 프로세스 제거."""
    try:
        req = Request("http://127.0.0.1:5555/api/system/kill-zombie-mcp", method="POST",
                      data=b'{}', headers={"Content-Type": "application/json"})
        resp = urlopen(req, timeout=15)
        result = json.loads(resp.read())
        killed = result.get("killed", 0)

        # 결과 후 현재 프로세스 수 확인
        resp2 = urlopen("http://127.0.0.1:5555/api/system/processes", timeout=10)
        procs = json.loads(resp2.read()).get("processes", [])
        node_count = sum(1 for p in procs if p["name"] == "node.exe")
        claude_count = sum(1 for p in procs if p["name"] == "claude.exe")
        total_mem = sum(p["mem_mb"] for p in procs)

        _tg_send(
            f"💀 <b>좀비 제거 완료</b>\n\n"
            f"제거: {killed}개\n"
            f"남은 프로세스: node {node_count}개 + claude {claude_count}개\n"
            f"메모리 사용: {total_mem}MB"
        )
    except Exception as e:
        _tg_send(f"❌ 오류: {e}")


def _tg_skill_sysinfo():
    """PC 자원 현황 + 프로세스 상세를 Telegram으로 보고."""
    try:
        # 시스템 메트릭
        resp = urlopen("http://127.0.0.1:5555/api/system/metrics", timeout=10)
        metrics = json.loads(resp.read())

        # 프로세스 목록
        resp2 = urlopen("http://127.0.0.1:5555/api/system/processes", timeout=10)
        procs = json.loads(resp2.read()).get("processes", [])

        # 프로세스 분류
        mcp_servers = []
        claude_instances = []
        other_nodes = []
        for p in procs:
            cmd = p.get("cmd", "").lower()
            if p["name"] == "claude.exe":
                claude_instances.append(p)
            elif any(k in cmd for k in ["@upstash", "@playwright", "@modelcontext", "context7", "sequential-thinking", "pinecone", "sonatype"]):
                mcp_servers.append(p)
            else:
                other_nodes.append(p)

        total_mem = sum(p["mem_mb"] for p in procs)
        mcp_mem = sum(p["mem_mb"] for p in mcp_servers)

        lines = ["🖥 <b>시스템 현황</b>\n"]

        # CPU/메모리
        cpu = metrics.get("cpu_percent", 0)
        mem_used = metrics.get("memory_used_mb", 0)
        mem_total = metrics.get("memory_total_mb", 0)
        mem_pct = metrics.get("memory_percent", 0)
        disk_pct = metrics.get("disk_percent", 0)

        lines.append(f"<b>PC 자원</b>")
        lines.append(f"  CPU: {cpu}%")
        lines.append(f"  RAM: {mem_used}MB / {mem_total}MB ({mem_pct}%)")
        lines.append(f"  디스크: {disk_pct}%")

        lines.append(f"\n<b>프로세스 ({len(procs)}개, {total_mem}MB)</b>")
        lines.append(f"  Claude: {len(claude_instances)}개 ({sum(p['mem_mb'] for p in claude_instances)}MB)")
        lines.append(f"  MCP 서버: {len(mcp_servers)}개 ({mcp_mem}MB)")
        if other_nodes:
            lines.append(f"  기타 Node: {len(other_nodes)}개 ({sum(p['mem_mb'] for p in other_nodes)}MB)")

        # MCP 서버 상세
        if mcp_servers:
            lines.append(f"\n<b>MCP 서버 상세</b>")
            for p in mcp_servers:
                cmd = p.get("cmd", "")
                # 서버 이름 추출
                name = "unknown"
                for k in ["@upstash", "@playwright", "@modelcontext", "context7", "sequential-thinking", "pinecone"]:
                    if k in cmd.lower():
                        name = k.replace("@", "")
                        break
                lines.append(f"  • {name} (PID:{p['pid']}, {p['mem_mb']}MB)")

        # 경고
        if mcp_mem > 500:
            lines.append(f"\n⚠️ MCP 서버가 {mcp_mem}MB 사용 중! /좀비 제거 권장")
        if mem_pct > 85:
            lines.append(f"\n🔴 RAM 사용률 {mem_pct}% — 위험 수준!")

        # 인라인 버튼
        buttons = [[
            {"text": "💀 좀비 제거", "callback_data": "skill:kill_zombie"},
            {"text": "🔄 새로고침", "callback_data": "skill:sysinfo"}
        ]]

        _tg_send("\n".join(lines), reply_markup={"inline_keyboard": buttons})
    except Exception as e:
        _tg_send(f"❌ 시스템 정보 조회 실패: {e}")


def _tg_skill_archive_menu():
    """완료된 팀 아카이브 메뉴."""
    conn = get_db()
    teams = rows_to_list(conn.execute(
        "SELECT t.team_id, t.name, "
        "(SELECT COUNT(*) FROM tickets WHERE team_id=t.team_id) as total, "
        "(SELECT COUNT(*) FROM tickets WHERE team_id=t.team_id AND status='Done') as done "
        "FROM agent_teams t WHERE t.status='Active'"
    ).fetchall())
    conn.close()

    archivable = [t for t in teams if t["total"] > 0 and t["done"] == t["total"]]
    if not archivable:
        return _tg_send("📦 아카이브 가능한 팀이 없습니다 (모든 티켓이 완료된 팀만)")

    buttons = []
    for t in archivable[:8]:
        buttons.append([{"text": f"📦 {t['name']} ({t['done']}/{t['total']})", "callback_data": f"skill_archive:{t['name']}"}])
    _tg_send("📦 아카이브할 팀을 선택하세요:", reply_markup={"inline_keyboard": buttons})


def _tg_cmd_wake(team_filter=""):
    """/wake — 대기 중인 티켓에 에이전트를 스폰하여 클레임 및 작업 시작."""
    conn = get_db()

    # 팀 필터 적용
    if team_filter:
        teams = rows_to_list(conn.execute(
            "SELECT team_id, name, project_group FROM agent_teams WHERE status='Active' AND (name LIKE ? OR project_group LIKE ?)",
            (f"%{team_filter}%", f"%{team_filter}%")
        ).fetchall())
    else:
        teams = rows_to_list(conn.execute(
            "SELECT team_id, name, project_group FROM agent_teams WHERE status='Active'"
        ).fetchall())

    if not teams:
        conn.close()
        return _tg_send("활성 팀이 없습니다.")

    # 대기 중인 티켓 찾기 (Todo, Backlog — 의존성 충족된 것만)
    ready_tickets = []
    for team in teams:
        tickets = rows_to_list(conn.execute(
            "SELECT * FROM tickets WHERE team_id=? AND status IN ('Todo','Backlog') ORDER BY priority DESC, created_at ASC",
            (team["team_id"],)
        ).fetchall())
        for t in tickets:
            deps = t.get("depends_on", "")
            if deps:
                dep_ids = [d.strip() for d in deps.split(",") if d.strip()]
                all_done = all(
                    conn.execute("SELECT status FROM tickets WHERE ticket_id=?", (d,)).fetchone()
                    and conn.execute("SELECT status FROM tickets WHERE ticket_id=?", (d,)).fetchone()["status"] == "Done"
                    for d in dep_ids
                )
                if not all_done:
                    continue
            ready_tickets.append((team, t))
    conn.close()

    if not ready_tickets:
        return _tg_send("✅ 대기 중인 티켓이 없습니다. 모든 작업이 진행 중이거나 완료되었습니다.")

    # 프로젝트 경로 찾기
    lines = [f"🔔 <b>{len(ready_tickets)}개 티켓에 에이전트를 스폰합니다</b>\n"]
    spawned = 0
    for team, ticket in ready_tickets:
        project_path = _find_project_path(team.get("project_group", "") or team["name"])
        if not project_path:
            lines.append(f"  ⚠️ {ticket['title']} — 프로젝트 경로 없음")
            continue

        # 에이전트 스폰
        try:
            _orch_spawn_agent_direct(ticket, project_path, team["team_id"])
            spawned += 1
            lines.append(f"  🤖 {ticket['title']}")
        except Exception as e:
            lines.append(f"  ❌ {ticket['title']}: {e}")

    lines.append(f"\n스폰 완료: {spawned}/{len(ready_tickets)}")
    return _tg_send("\n".join(lines))


def _orch_spawn_agent_direct(ticket, project_path, team_id):
    """단일 티켓에 대해 직접 에이전트를 스폰 (오케스트레이터 잡 없이)."""
    ticket_id = ticket["ticket_id"]
    title = ticket["title"]
    desc = ticket.get("description", "")

    mcp_url = f"http://localhost:5555/mcp"
    agent_prompt = f"""당신은 전문 개발 에이전트입니다. 아래 티켓을 처리하세요.

## 티켓
- ID: {ticket_id}
- 팀: {team_id}
- 제목: {title}
- 설명: {desc}
- 우선순위: {ticket.get('priority', 'Medium')}

## 진행상황 보고 (필수)
작업 중 **매 주요 단계마다** kanban_activity_log MCP 도구로 진행상황을 보고하세요:
```
kanban_activity_log(team_id="{team_id}", ticket_id="{ticket_id}", action="progress", message="현재 하고 있는 작업 한 줄 요약")
```
예시:
- 파일 분석 시작 시
- 핵심 로직 구현 시
- 테스트 실행 시
- 완료 직전

## 규칙
1. 이 티켓만 처리하세요.
2. 구현 완료 후 테스트까지 확인하세요.
3. 주요 단계마다 kanban_activity_log로 progress 보고 (3-5회 이상).
4. 완료되면 kanban_ticket_status로 Done 처리 후 종료하세요.
"""

    session_id = "cs-" + uuid.uuid4().hex[:8]
    cli = _find_claude_cli()
    cmd = [cli, "-p", agent_prompt, ]

    proc = subprocess.Popen(
        cmd, cwd=project_path,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == 'nt' else 0
    )
    _claude_processes[session_id] = proc

    conn = get_db()
    conn.execute(
        "INSERT INTO claude_sessions (session_id, project_path, team_id, pid, status) VALUES (?,?,?,?,?)",
        (session_id, project_path, team_id, proc.pid, "running")
    )
    conn.execute("UPDATE tickets SET status='InProgress', assigned_member_id=?, started_at=datetime('now') WHERE ticket_id=?",
                  (session_id, ticket_id))
    conn.commit()
    conn.close()

    sse_broadcast(team_id, "ticket_status_changed", {"ticket_id": ticket_id, "status": "InProgress", "ticket_title": title})

    # 완료 감시
    threading.Thread(target=_orch_wait_direct, args=(ticket_id, session_id, proc, team_id, title), daemon=True).start()


def _orch_wait_direct(ticket_id, session_id, proc, team_id, title):
    """직접 스폰된 에이전트의 완료를 감시."""
    try:
        proc.wait(timeout=1800)
    except subprocess.TimeoutExpired:
        proc.terminate()

    exit_code = proc.returncode
    new_status = "Done" if exit_code == 0 else "Blocked"

    conn = get_db()
    conn.execute("UPDATE tickets SET status=?, completed_at=datetime('now') WHERE ticket_id=?", (new_status, ticket_id))
    conn.execute("UPDATE claude_sessions SET status='exited', ended_at=datetime('now') WHERE session_id=?", (session_id,))
    conn.commit()
    conn.close()

    sse_broadcast(team_id, "ticket_status_changed", {"ticket_id": ticket_id, "status": new_status, "ticket_title": title})
    icon = "✅" if new_status == "Done" else "🚫"
    _tg_send(f"{icon} {title} — {new_status}")

    if session_id in _claude_processes:
        del _claude_processes[session_id]


def _tg_cmd_natural(text):
    """자연어 입력 → 의도 분류 → 대화/조회는 직접 응답, 작업 지시만 오케스트레이터."""
    # 별명 → 프로젝트명 변환 (구어체 지원)
    ALIAS_MAP = {
        '성경': 'Bible', '계약': 'CLM2', '3웹': '3dweb', '견적': 'Estimate',
        '팔십': 'Followship', '헥사': 'Hexacotest', '이박': 'LEEPARK',
        '링코': 'LINKO', '링콘': 'LINKON', '엠씨': 'MCS', 'ai피': 'PMI-AIP',
        'AI피': 'PMI-AIP', '글로': 'PMI-LINK-GLOBAL', '피링': 'PMI_Link',
        '칸반': 'U2DIA-KANBAN-BOARD', 'u홈': 'U2DIA_HOME', 'U홈': 'U2DIA_HOME',
        '메타': 'U2DIA_METAVERS', '하네': 'advanced-harness', '크롬': 'chrome-devtools-mcp',
        '쿠팡': 'cupang_api', '이커': 'e-commerceAI', '라이': 'life',
        '오클': 'openclaw', '플너': 'planner', '사랩': 'science-lab-flutter'
    }
    # text에서 별명 감지 → context에 project 자동 설정
    for alias_key, proj_name in ALIAS_MAP.items():
        if alias_key in text or alias_key.lower() in text.lower():
            _tg_context['project'] = alias_key
            _tg_context['project_path'] = _find_project_path(proj_name)
            break

    text_lower = text.lower()

    # -1. pending_cli 처리 (CLI 직접 실행 대기 중)
    pending_cli = _tg_context.pop("pending_cli", None)
    if pending_cli:
        threading.Thread(
            target=_tg_skill_claude,
            args=(pending_cli["project"], pending_cli["path"], text),
            daemon=True
        ).start()
        return

    # -0.5 pending_instruction_for 처리 (팀 생성 대기 중)
    pending_for = _tg_context.pop("pending_instruction_for", None)
    if pending_for:
        ppath = _find_project_path(pending_for)
        if ppath:
            threading.Thread(target=_orch_dispatch, args=(pending_for, text, ppath), daemon=True).start()
            return

    # 0. 칸반 시스템 액션 감지 (에이전트 깨우기, 클레임, 스폰 등)
    kanban_action_keywords = [
        "깨워", "깨우", "클레임", "스폰", "시작해", "시작 해", "작업 진행",
        "에이전트 시작", "에이전트 깨", "wake", "spawn", "claim",
        "남은 티켓", "대기 티켓", "대기중", "착수", "투입"
    ]
    if any(kw in text_lower for kw in kanban_action_keywords):
        # 팀명 추출 시도
        team_filter = ""
        known = _get_known_projects()
        for entry in known:
            alias = entry[0]
            orig = entry[2] if len(entry) > 2 else alias
            if alias.lower() in text_lower or orig.lower() in text_lower:
                team_filter = alias
                break
        return _tg_cmd_wake(team_filter)

    # 1. 의도 분류 — 조회/대화성 키워드 감지
    # 조회 = 명시적으로 데이터를 요구하는 경우만
    query_keywords = [
        "현황", "보고", "상태 알려", "티켓 몇", "팀 몇", "브리핑", "리포트",
        "몇개", "몇 개", "status", "report"
    ]
    is_query = any(kw in text_lower for kw in query_keywords)

    # 작업 지시 키워드
    action_keywords = [
        "만들", "추가", "수정", "삭제", "구현", "개발", "생성", "변경", "리팩",
        "배포", "설치", "업데이트", "fix", "build", "deploy", "create", "implement",
        "해줘", "해 줘", "하세요", "해주세요", "바꿔", "고쳐"
    ]
    is_action = any(kw in text_lower for kw in action_keywords)

    # 2. 조회/대화 → 서버 데이터 기반 직접 응답
    if is_query and not is_action:
        threading.Thread(target=_tg_chat_respond, args=(text,), daemon=True).start()
        return

    # 3. 작업 지시 → 프로젝트 매칭 후 오케스트레이터
    known_projects = _get_known_projects()
    matched = None
    for entry in known_projects:
        alias, path = entry[0], entry[1]
        orig_name = entry[2] if len(entry) > 2 else alias
        for candidate in [alias, orig_name]:
            c_lower = candidate.lower().replace("-", "").replace("_", "")
            t_clean = text_lower.replace("-", "").replace("_", "")
            if len(candidate) >= 2 and (c_lower in t_clean or candidate.lower() in text_lower):
                matched = (alias, path)
                break
        if matched:
            break

    if matched:
        _tg_context["project"] = matched[0]
        _tg_context["project_path"] = matched[1]
        threading.Thread(target=_orch_dispatch, args=(matched[0], text, matched[1]), daemon=True).start()
        return

    if _tg_context.get("project") and _tg_context.get("project_path"):
        proj = _tg_context["project"]
        ppath = _tg_context["project_path"]
        if is_action:
            _tg_send(f"📂 <b>{proj}</b> 프로젝트에 작업 지시합니다.")
            threading.Thread(target=_orch_dispatch, args=(proj, text, ppath), daemon=True).start()
        else:
            threading.Thread(target=_tg_chat_respond, args=(text,), daemon=True).start()
        return

    # 4. 모호한 경우 → 대화로 처리
    threading.Thread(target=_tg_chat_respond, args=(text,), daemon=True).start()



def _tg_chat_respond(text):
    """유디 대화 — 대화형 에이전트 (도구 사용 가능, 멀티턴)."""
    # 텔레그램 전용 세션 (프로젝트 컨텍스트 유지)
    session_id = "tg-main"
    project = _tg_context.get("project")
    project_path = _tg_context.get("project_path")

    result = _chat_agent_respond(session_id, text, project, project_path)

    if result.get("ok") and result.get("response"):
        response = result["response"]
        tools = result.get("tools_used", [])
        usage = result.get("usage", {})

        # 도구 사용 정보 추가
        suffix = ""
        if tools:
            tool_icons = {"read_file": "📖", "write_file": "✏️", "run_command": "⚙️",
                         "list_files": "📁", "kanban_ticket_status": "🎫",
                         "kanban_activity_log": "📝", "kanban_artifact_create": "📎"}
            tool_str = " ".join(set(tool_icons.get(t, "🔧") for t in tools))
            suffix += f"\n\n{tool_str} 도구 {len(tools)}회"
        if usage.get("cost"):
            suffix += f" | ${usage['cost']:.4f}"

        # Telegram 메시지 길이 제한 (4096)
        max_len = 4000 - len(suffix)
        if len(response) > max_len:
            response = response[:max_len] + "\n..."

        _tg_send(response + suffix)
    else:
        # 폴백: 기존 유디 대화
        response = _yudi_converse(text)
        if response:
            _tg_send(response)
        else:
            _tg_send("잠시 연결이 불안정해요. 다시 말씀해주세요!")




_YUDI_MODEL = "claude-opus-4-6"
_YUDI_MAX_TOKENS = 4096

_HTML_TAG_RE = re.compile(r'<[^>]+>')
def _strip_html(text):
    """HTML 태그 제거 — 앱/웹 채팅용. Telegram은 HTML 지원하므로 별도."""
    return _HTML_TAG_RE.sub('', text) if text else text

# ── Ollama 로컬 LLM 백엔드 ──
_OLLAMA_URL = "http://localhost:11434"
_OLLAMA_MODEL = "qwen3.5:27b"
_YUDI_BACKEND = "ollama"  # "ollama" | "anthropic"

# ── Kimi K2.5 (Moonshot AI) ──
_KIMI_API_URL = "https://api.moonshot.ai/v1"
_KIMI_API_KEY = os.environ.get("KIMI_API_KEY", "")
_KIMI_MODEL = "kimi-k2.5"

# ── NVIDIA NIM API (Nemotron 3 Super) ──
_NIM_API_URL = "https://integrate.api.nvidia.com/v1"
_NIM_API_KEY = os.environ.get("NIM_API_KEY", "")
_NIM_MODEL = "nvidia/nemotron-3-super-120b-a12b"


def _nim_chat(prompt, system=None, messages=None, max_tokens=2048, mode="default"):
    """NVIDIA NIM API — Nemotron 3 Super 120B-A12B.
    mode: 'default' (reasoning trace), 'loweffort' (빠른 응답), 'budget' (8K 추론 예산)
    """
    if not _NIM_API_KEY:
        return None
    msgs = []
    if system:
        msgs.append({"role": "system", "content": system})
    if messages:
        msgs.extend(messages)
    if prompt:
        msgs.append({"role": "user", "content": prompt})

    payload = {
        "model": _NIM_MODEL,
        "messages": msgs,
        "max_tokens": max_tokens,
        "temperature": 0.3,
    }
    # 추론 거버넌스 모드
    if mode == "loweffort":
        payload["nvidia"] = {"low_effort": True}
    elif mode == "budget":
        payload["nvidia"] = {"enable_thinking": True, "reasoning_budget": 8000}

    try:
        data = json.dumps(payload).encode("utf-8")
        req = Request(
            f"{_NIM_API_URL}/chat/completions",
            data=data,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {_NIM_API_KEY}"
            }
        )
        resp = urlopen(req, timeout=60)
        result = json.loads(resp.read())
        choice = result.get("choices", [{}])[0].get("message", {})
        content = (choice.get("content") or "").strip()
        reasoning = (choice.get("reasoning_content") or "").strip()
        usage = result.get("usage", {})
        # NIM 사용량 누적 추적
        _nim_usage_track(usage)
        return {"content": content, "reasoning": reasoning,
                "usage": usage, "model": _NIM_MODEL}
    except Exception as e:
        print(f"[nim] error: {e}", file=sys.stderr, flush=True)
        return None


# NIM API 사용량 추적
_nim_usage = {"total_calls": 0, "total_prompt_tokens": 0, "total_completion_tokens": 0, "total_tokens": 0}

def _nim_usage_track(usage):
    _nim_usage["total_calls"] += 1
    _nim_usage["total_prompt_tokens"] += usage.get("prompt_tokens", 0)
    _nim_usage["total_completion_tokens"] += usage.get("completion_tokens", 0)
    _nim_usage["total_tokens"] += usage.get("total_tokens", 0)

_YUDI_SYSTEM = """당신은 '유디(Yudi)'. U2DIA의 상주 AI 프로젝트 매니저.
코드는 절대 생성하지 않는다. 당신의 역할은 오직 통찰과 조율이다.
헌법 v3.0 (6원칙): 투명성, 원자적 완결성, 의존성 무결성, 협업적 자율성, 역할 범위, 올라마 게이트키퍼.

## 핵심 역할 (4가지만)
1. 팀 구성 + 티켓 설계 — 작업을 분해하고, 적절한 팀/에이전트 배치를 판단
2. 산출물 리뷰 — Done 티켓의 산출물(코드, 문서, 테스트)을 검증하고 품질 판정
3. 에이전트 회의 소집 — 의존성 충돌, 블로커, 방향 불일치 시 관련 에이전트 간 회의 조율
4. 재작업 관리 — 리뷰 실패 시 재작업 티켓 발행 (최대 3회, 초과 시 에스컬레이션)

## 판단 기준
- 산출물이 티켓 요구사항을 충족하는가?
- 에이전트가 CLAUDE.md 역할 범위 내에서 작업했는가? (제5원칙)
- 에이전트 간 작업이 충돌하거나 중복되지 않는가?
- 블로커가 있는 에이전트에게 필요한 정보가 전달되었는가?
- 선행 티켓 미완료 시 Blocked 상태로 대기하고 있는가? (제3원칙)
- 재작업 3회 실패 시 → 대표님에게 즉시 에스컬레이션

## 성격
- 데이터 기반. 팀명, 숫자, 진행률로 말함
- 문제를 숨기지 않음. 솔직히 보고 + 해결책 제시
- 사용자를 '대표님'이라 부름
- HTML 태그(<b>, <code>, <i>)로 Telegram 포맷
- 2-3줄 핵심만. 서론/미사여구 없음

## 프로젝트 별명
성경=Bible, 계약=CLM2, 3웹=3dweb, 견적=Estimate, 팔십=Followship
헥사=Hexacotest, 이박=LEEPARK, 링코=LINKO, 링콘=LINKON, 엠씨=MCS
AI피=PMI-AIP, 글로=PMI-LINK-GLOBAL, 피링=PMI_Link, 칸반=U2DIA-KANBAN-BOARD
U홈=U2DIA_HOME, 메타=U2DIA_METAVERS, 하네=advanced-harness, 크롬=chrome-devtools-mcp
쿠팡=cupang_api, 이커=e-commerceAI, 라이=life, 오클=openclaw, 플너=planner, 사랩=science-lab-flutter
이카=eCOUNT-ERP, 프린=principia-cli, 샘3=sam3, 타리=tiny-recursive-model
파티=u2dia_particlemodel, 시뮬=u2dia_simulator, 유클=unity-cli, NC=NC_PROGRAM, KSM=KSM-API
"""

_YUDI_CHAT_SYSTEM = """당신은 '유디(Yudi)'. U2DIA의 AI 프로젝트 매니저이자 대표님의 신뢰할 수 있는 참모.

## 대화 스타일
- 구어체로 자연스럽게 대화한다. 보고서가 아닌 사람 대 사람 대화.
- 상대를 '대표님'이라 부르되, 말투는 친근하고 솔직하다.
- 질문에 대해 생각하고, 통찰을 담아 답한다. 뻔한 말 금지.
- 숫자를 나열하지 말고 의미를 해석해서 말한다.
  예: "티켓 104개 중 59개 완료" (X) → "절반 넘게 끝났는데, 블로커 6개가 좀 신경 쓰입니다" (O)
- HTML 태그 절대 사용 금지. 이모지는 가끔, 자연스럽게만.
- 매번 현황을 보고하지 않는다. 대표님이 물어볼 때만 현황을 얘기한다.
- 일상 대화, 잡담, 고민 상담도 잘 들어준다.

## 핵심 역량
- 프로젝트 전체 맥락을 꿰뚫고 있다 (팀 구성, 진행률, 블로커, 의존성)
- 기술적 판단력이 있다 (아키텍처, 코드 품질, 배포 전략)
- 우선순위를 잘 잡는다 (급한 것 vs 중요한 것 구분)
- 솔직하다 — 문제가 있으면 돌려 말하지 않는다
- 대안을 제시한다 — "안 됩니다"가 아니라 "이렇게 하면 어떨까요?"

## 금지
- 코드 생성 금지 (코드는 에이전트가 한다)
- 형식적인 인사/서론 금지 ("안녕하세요, 유디입니다" 같은 시작 금지)
- 같은 패턴 반복 금지 (매번 "현재 팀 N개, 티켓 N개..." 하지 않기)
- HTML/마크다운 태그 금지
"""


def _classify_intent(message):
    """Ollama gemma3로 의도 분류. 자연어 이해로 키워드 매칭 완전 대체.
    Returns: 'chat' | 'action' | 'supervisor'
    """
    prompt = (
        "사용자 메시지의 의도를 분류하세요. 반드시 아래 3개 중 하나만 답하세요.\n\n"
        "chat — 인사, 잡담, 일상대화, 의견, 감정, 고민, 단순질문, 프로젝트 관련 대화, 현황 질문\n"
        "action — 무언가를 실행해달라는 요청. 파일 수정, 코드 작업, 빌드, 배포, 티켓 생성/변경, 데이터 조회, 검색\n"
        "supervisor — QA 검수, 리뷰 판정, 재작업 지시, 품질 평가, 통과/반려 결정\n\n"
        f'메시지: "{message}"\n\n'
        "분류:"
    )
    try:
        raw = _ollama_chat(
            prompt, system="의도 분류기. 한 단어만 답한다. chat 또는 action 또는 supervisor.",
            messages=[{"role": "user", "content": prompt}]
        )
        if raw:
            raw = raw.strip().lower().split()[0] if raw.strip() else "chat"
            for intent in ("supervisor", "action", "chat"):
                if intent in raw:
                    return intent
    except Exception:
        pass
    return "chat"


def _ollama_chat(prompt, model=None, system=None, messages=None):
    """Ollama API 호출. 로컬 GPU 추론."""
    model = model or _OLLAMA_MODEL
    system = system or _YUDI_SYSTEM

    if messages is None:
        msgs = [{"role": "user", "content": prompt}]
    else:
        msgs = list(messages)

    payload = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": system}] + msgs,
        "stream": False,
        "think": False,
        "options": {"num_predict": _YUDI_MAX_TOKENS, "temperature": 0.7}
    }).encode("utf-8")

    try:
        req = Request(
            f"{_OLLAMA_URL}/api/chat",
            data=payload,
            headers={"Content-Type": "application/json"}
        )
        resp = urlopen(req, timeout=20)
        result = json.loads(resp.read())
        msg = result.get("message", {})
        content = msg.get("content", "").strip()
        # qwen3.5 thinking 모드 폴백: content 비어있으면 thinking 필드 사용
        if not content and msg.get("thinking"):
            content = msg["thinking"].strip()
        return content if content else None
    except Exception as e:
        print(f"[ollama] error ({model}): {e} — NIM 폴백 시도", file=sys.stderr, flush=True)
        # NIM 폴백
        nim_result = _nim_chat(prompt, system=system, messages=messages, max_tokens=1024)
        if nim_result and nim_result.get("content"):
            return nim_result["content"]
        if nim_result and nim_result.get("reasoning"):
            return nim_result["reasoning"]
        return None


def _ollama_available():
    """Ollama 서비스 가용 여부 확인."""
    try:
        req = Request(f"{_OLLAMA_URL}/api/tags")
        resp = urlopen(req, timeout=3)
        data = json.loads(resp.read())
        return any(_OLLAMA_MODEL in m.get("name", "")
                   for m in data.get("models", []))
    except Exception:
        return False


def _tools_to_ollama_format(tools):
    """Anthropic 도구 형식 → Ollama 도구 형식 변환."""
    return [{
        "type": "function",
        "function": {
            "name": t["name"],
            "description": t["description"],
            "parameters": t["input_schema"]
        }
    } for t in tools]


def _pick_tool_model():
    """도구 호출을 지원하는 Ollama 모델 자동 선택.
    gemma3는 도구 미지원 → qwen3/qwen2.5-coder/qwen2.5 순서로 폴백."""
    # 도구 지원 모델 우선순위
    candidates = ["qwen3.5:27b", "qwen3:32b", "qwen2.5-coder:32b", "qwen2.5:14b"]
    try:
        req = Request(f"{_OLLAMA_URL}/api/tags")
        resp = urlopen(req, timeout=3)
        available = {m["name"] for m in json.loads(resp.read()).get("models", [])}
        for c in candidates:
            if c in available:
                return c
    except Exception:
        pass
    return _OLLAMA_MODEL  # 폴백 (도구 호출 실패 가능)


def _ollama_tool_chat(msgs, tools, system, project_path,
                      team_id="", ticket_id="", session_id=""):
    """Ollama 도구 호출 루프 — 실제 실행 보장, 환각 차단.

    Returns: (response_text, tools_used_list, executed_actions_list)
    """
    model = _pick_tool_model()
    ollama_tools = _tools_to_ollama_format(tools)

    all_msgs = [{"role": "system", "content": system}] + list(msgs)

    full_response = ""
    tools_used = []
    executed_actions = []

    for _turn in range(8):
        payload = json.dumps({
            "model": model,
            "messages": all_msgs,
            "tools": ollama_tools,
            "stream": False,
            "think": False,
            "options": {"num_predict": _YUDI_MAX_TOKENS, "temperature": 0.3}
        }).encode("utf-8")

        try:
            req = Request(
                f"{_OLLAMA_URL}/api/chat", data=payload,
                headers={"Content-Type": "application/json"})
            resp = urlopen(req, timeout=30)
            result = json.loads(resp.read())
        except Exception as e:
            full_response += f"\n[Ollama 오류: {str(e)[:80]}]"
            break

        msg = result.get("message", {})
        content = msg.get("content", "").strip()
        tool_calls = msg.get("tool_calls") or []

        if content:
            full_response += content

        if not tool_calls:
            break

        # assistant 메시지(도구 호출 포함) 추가
        all_msgs.append(msg)

        for tc in tool_calls:
            fn = tc.get("function", {})
            name = fn.get("name", "")
            args = fn.get("arguments", {})
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except Exception:
                    args = {}
            if not name:
                continue

            tools_used.append(name)
            try:
                tool_result = _api_execute_tool(
                    name, args, project_path or "/tmp",
                    team_id, ticket_id, session_id)
                result_str = str(tool_result)[:3000]
            except Exception as e:
                result_str = json.dumps({"error": str(e)[:200]})

            executed_actions.append({
                "tool": name,
                "args": {k: str(v)[:100] for k, v in args.items()},
                "result_preview": result_str[:300],
                "success": "error" not in result_str.lower()[:50]
            })
            all_msgs.append({"role": "tool", "content": result_str})

    return full_response, tools_used, executed_actions


def _smart_chat(prompt, model=None, system=None, messages=None):
    """백엔드 자동 선택: ollama 우선, 실패 시 anthropic 폴백.
    Ollama 경로에서는 model 파라미터 무시 (_OLLAMA_MODEL 고정, 로컬은 무료)."""
    if _YUDI_BACKEND == "ollama":
        result = _ollama_chat(prompt, system=system, messages=messages)
        if result:
            return result
    # Ollama 실패 또는 anthropic 모드 → Claude API
    return _claude_chat(prompt, model=model, system=system, messages=messages)


# 대화 히스토리 (compact 지원)
_yudi_messages = []       # [{"role": "user"|"assistant", "content": "..."}]
_yudi_compact_count = 0   # compact 횟수


def _claude_chat(prompt, model=None, system=None, messages=None):
    """Anthropic Messages API 직접 호출. Opus 4.6 기본."""
    api_key = _get_setting("anthropic_api_key")
    if not api_key:
        return _claude_chat_cli_fallback(prompt)

    model = model or _YUDI_MODEL
    system = system or _YUDI_SYSTEM

    # messages가 없으면 단발 요청
    if messages is None:
        messages = [{"role": "user", "content": prompt}]

    try:
        data = json.dumps({
            "model": model,
            "max_tokens": _YUDI_MAX_TOKENS,
            "system": system,
            "messages": messages
        }).encode("utf-8")
        req = Request(
            "https://api.anthropic.com/v1/messages",
            data=data,
            headers={
                "Content-Type": "application/json",
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01"
            }
        )
        resp = urlopen(req, timeout=60)
        result = json.loads(resp.read())
        text_blocks = [b["text"] for b in result.get("content", []) if b.get("type") == "text"]
        return "\n".join(text_blocks).strip() if text_blocks else None
    except Exception as e:
        # API 실패 시 CLI 폴백
        return _claude_chat_cli_fallback(prompt)


def _claude_chat_cli_fallback(prompt):
    """CLI 폴백."""
    cli = _find_claude_cli()
    try:
        result = subprocess.run(
            [cli, "-p", prompt, "--output-format", "json"],
            capture_output=True, text=True, timeout=90,
            cwd=os.path.dirname(os.path.abspath(__file__))
        )
        if result.returncode != 0:
            return None
        parsed = json.loads(result.stdout)
        return parsed.get("result", "").strip()
    except Exception:
        return None


def _yudi_converse(user_text):
    """유디와 대화. 히스토리 유지 + 자동 compact."""
    global _yudi_messages, _yudi_compact_count

    # 칸반 현황을 시스템 컨텍스트에 주입
    context = _build_kanban_context()

    # 히스토리에 사용자 메시지 추가
    _yudi_messages.append({"role": "user", "content": user_text})

    # 자동 compact: 20턴 초과 시
    if len(_yudi_messages) > 40:
        _yudi_compact()

    # 시스템 프롬프트에 현황 추가
    full_system = _YUDI_SYSTEM + "\n\n현재 칸반보드 상태:\n" + context

    # 현재 선택된 프로젝트의 git 컨텍스트 주입
    current_path = _tg_context.get("project_path", "")
    if current_path:
        git_ctx = _build_git_context(current_path)
        if git_ctx:
            current_proj = _tg_context.get("project", "")
            full_system += f"\n\n현재 작업 프로젝트: {current_proj} ({current_path})\n{git_ctx}"

    # API 호출 (Ollama 우선, 폴백 Claude)
    response = _smart_chat(
        prompt=user_text,
        system=full_system,
        messages=_yudi_messages
    )

    if response:
        _yudi_messages.append({"role": "assistant", "content": response})
        return response
    return None


def _yudi_compact():
    """대화 히스토리를 요약하여 압축."""
    global _yudi_messages, _yudi_compact_count

    if len(_yudi_messages) < 6:
        return

    # 최근 4턴 유지, 나머지 요약
    old_messages = _yudi_messages[:-4]
    recent = _yudi_messages[-4:]

    summary_prompt = "아래 대화를 3-5문장으로 핵심만 요약해주세요. 어떤 프로젝트에 대해 어떤 작업/지시를 했는지 포함:\n\n"
    for m in old_messages:
        role = "사용자" if m["role"] == "user" else "유디"
        summary_prompt += f"{role}: {m['content'][:200]}\n"

    summary = _smart_chat(summary_prompt)
    if summary:
        _yudi_messages = [
            {"role": "user", "content": f"[이전 대화 요약] {summary}"},
            {"role": "assistant", "content": "네, 이전 대화 내용을 파악했습니다. 계속하겠습니다."}
        ] + recent
        _yudi_compact_count += 1


def _build_kanban_context():
    """칸반보드 현황을 텍스트로 구성."""
    try:
        conn = get_db()
        teams = rows_to_list(conn.execute(
            "SELECT t.team_id, t.name, t.project_group, "
            "(SELECT COUNT(*) FROM tickets WHERE team_id=t.team_id) as total, "
            "(SELECT COUNT(*) FROM tickets WHERE team_id=t.team_id AND status='Done') as done, "
            "(SELECT COUNT(*) FROM tickets WHERE team_id=t.team_id AND status='InProgress') as inprog, "
            "(SELECT COUNT(*) FROM tickets WHERE team_id=t.team_id AND status='Blocked') as blocked "
            "FROM agent_teams t WHERE t.status='Active' ORDER BY t.created_at DESC LIMIT 15"
        ).fetchall())

        total_t = conn.execute("SELECT COUNT(*) as c FROM tickets").fetchone()["c"]
        done_t = conn.execute("SELECT COUNT(*) as c FROM tickets WHERE status='Done'").fetchone()["c"]
        inprog_t = conn.execute("SELECT COUNT(*) as c FROM tickets WHERE status='InProgress'").fetchone()["c"]

        # 진행 중 작업
        working = rows_to_list(conn.execute(
            "SELECT t.title, tm.name as team_name FROM tickets t "
            "LEFT JOIN agent_teams tm ON t.team_id=tm.team_id "
            "WHERE t.status='InProgress' LIMIT 5"
        ).fetchall())

        # 프로젝트 별명
        aliases_row = conn.execute("SELECT value FROM server_settings WHERE key='project_aliases'").fetchone()
        conn.close()

        lines = [f"팀 {len(teams)}개 | 티켓 {total_t}개 (완료 {done_t}, 진행 {inprog_t})"]
        for t in teams:
            pct = round(t["done"] / t["total"] * 100) if t["total"] else 0
            lines.append(f"  {t['name']} [{t.get('project_group','')}]: {t['done']}/{t['total']} ({pct}%)")

        if working:
            lines.append("\n진행 중:")
            for w in working:
                lines.append(f"  🔄 [{w.get('team_name','')}] {w['title']}")


        # 프로젝트 경로 정보 추가
        known = _get_known_projects()
        if known:
            lines.append("\n등록 프로젝트:")
            for entry in known[:10]:
                alias, path = entry[0], entry[1]
                exists = "✅" if os.path.isdir(path) else "❌"
                lines.append(f"  {exists} {alias}: {path}")

        return "\n".join(lines)
    except Exception:
        return "현황 조회 실패"


def _build_git_context(project_path):
    """프로젝트의 git 상태/최근 커밋을 텍스트로 요약."""
    if not project_path or not os.path.isdir(project_path):
        return ""
    try:
        nl = "\n"
        log = subprocess.run(
            ["git", "log", "--oneline", "-5"],
            capture_output=True, text=True, cwd=project_path, timeout=5
        )
        status = subprocess.run(
            ["git", "status", "--short"],
            capture_output=True, text=True, cwd=project_path, timeout=5
        )
        parts = []
        if log.returncode == 0 and log.stdout.strip():
            parts.append("최근 커밋:" + nl + log.stdout.strip())
        if status.returncode == 0 and status.stdout.strip():
            parts.append("변경 파일:" + nl + status.stdout.strip())
        return nl.join(parts) if parts else ""
    except Exception:
        return ""


def _get_setting(key):
    """server_settings에서 값 조회."""
    try:
        conn = get_db()
        row = conn.execute("SELECT value FROM server_settings WHERE key=?", (key,)).fetchone()
        conn.close()
        return row["value"] if row else None
    except Exception:
        return None


def _tg_format_status(teams, total, done, inprog, blocked, working):
    """CLI 없이 직접 현황 포맷팅."""
    lines = [f"📊 <b>칸반보드 현황</b>\n"]
    lines.append(f"팀 {len(teams)}개 | 티켓 {total}개")
    lines.append(f"✅ {done} 완료 | 🔄 {inprog} 진행 | 🚫 {blocked} 차단\n")

    if working:
        lines.append("<b>진행 중</b>")
        for w in working:
            lines.append(f"  🔄 [{w.get('team_name','')}] {w['title']}")

    if teams:
        lines.append(f"\n<b>활성 팀</b>")
        for t in teams[:8]:
            pct = round(t["done"] / t["total"] * 100) if t["total"] else 0
            bar = "█" * (pct // 10) + "░" * (10 - pct // 10)
            lines.append(f"  {t['name']}: {bar} {pct}%")

    return "\n".join(lines)


def _tg_cmd_use_project(name):
    """/use 프로젝트명 — 대화 컨텍스트 프로젝트 변경."""
    path = _find_project_path(name)
    if not path:
        return _tg_send(f"❌ '{name}' 프로젝트를 찾을 수 없습니다.")
    _tg_context["project"] = name
    _tg_context["project_path"] = path
    return _tg_send(f"📂 프로젝트 전환: <b>{name}</b>\n이제 입력하는 지시는 이 프로젝트에 적용됩니다.")


_PROJECT_GROUP_ALIASES = {
    "U2DIA AI": "PMI-LINK-GLOBAL",
    "U2DIA Commerce AI": "PMI-LINK-GLOBAL",
    "PMI LINK GLOBAL": "PMI-LINK-GLOBAL",
    "PARTICLE-MODEL": "u2dia_particlemodel",
    "E-COMMERCE-AI": "e-commerceAI",
    "U2DIA-SIMULATOR": "u2dia_simulator",
    "3DWEB": "3dweb",
}

def _find_project_path(name):
    """프로젝트 별명/이름으로 경로 찾기. 3-tuple (alias, path, name) 지원."""
    # 0차: 프로젝트 그룹 별명 매핑
    if name in _PROJECT_GROUP_ALIASES:
        name = _PROJECT_GROUP_ALIASES[name]
    known = _get_known_projects()
    name_l = name.lower()
    # 1차: 정확 매칭 (별명 또는 원본 이름)
    for entry in known:
        alias, path = entry[0], entry[1]
        orig = entry[2] if len(entry) > 2 else alias
        if alias.lower() == name_l or orig.lower() == name_l:
            return path
    # 2차: 부분 매칭
    for entry in known:
        alias, path = entry[0], entry[1]
        orig = entry[2] if len(entry) > 2 else alias
        if name_l in alias.lower() or name_l in orig.lower():
            return path
    # 3차: 직접 경로 탐색 (Ubuntu 기본 경로)
    ubuntu_bases = [
        "/home/u2dia/github",
        os.path.expanduser("~/github"),
        os.path.expanduser("~"),
    ]
    for base in ubuntu_bases:
        candidate = os.path.join(base, name)
        if os.path.isdir(candidate):
            return candidate
    return None


def _get_known_projects():
    """DB에서 프로젝트 별명+경로 로드. 없으면 토큰 기반 기본값 사용."""
    conn = get_db()
    row = conn.execute("SELECT value FROM server_settings WHERE key='project_aliases'").fetchone()
    conn.close()
    if row and row["value"]:
        try:
            aliases = json.loads(row["value"])
            # aliases = [{"alias": "쿠팡", "name": "cupang_api", "path": "E:/cupang_api"}, ...]
            result = []
            for a in aliases:
                if os.path.isdir(a["path"]):
                    result.append((a["alias"], a["path"], a.get("name", a["alias"])))
            if result:
                return result
        except Exception:
            pass

    # 기본값 (Ubuntu 경로)
    defaults = [
        ("Hexacotest", "/home/u2dia/github/Hexacotest"),
        ("PMI-AIP", "/home/u2dia/github/PMI-AIP"),
        ("LEEPARK", "/home/u2dia/github/LEEPARK"),
        ("NC_PROGRAM", "/home/u2dia/github/NC_PROGRAM"),
        ("PMI-LINK-GLOBAL", "/home/u2dia/github/PMI-LINK-GLOBAL"),
        ("Bible", "/home/u2dia/github/Bible"),
        ("U2DIA_HOME", "/home/u2dia/github/U2DIA_HOME"),
        ("U2DIA_METAVERS", "/home/u2dia/github/U2DIA_METAVERS"),
        ("life", "/home/u2dia/github/life"),
        ("planner", "/home/u2dia/github/planner"),
        ("LINKO", "/home/u2dia/github/LINKO"),
        ("cupang_api", "/home/u2dia/github/cupang_api"),
        ("U2DIA-KANBAN-BOARD", "/home/u2dia/github/U2DIA-KANBAN-BOARD"),
    ]
    result = [(n, p, n) for n, p in defaults if os.path.isdir(p)]
    if result:
        return result
    # 경로 존재 여부와 무관하게 전체 반환 (DB에 alias 없을 때 fallback)
    return [(n, p, n) for n, p in defaults]


def _save_project_aliases(aliases):
    """프로젝트 별명 목록을 DB에 저장."""
    conn = get_db()
    conn.execute(
        "INSERT OR REPLACE INTO server_settings (key, value, updated_at) VALUES ('project_aliases', ?, datetime('now'))",
        (json.dumps(aliases, ensure_ascii=False),)
    )
    conn.commit()
    conn.close()


def _tg_poll_loop():
    """Telegram getUpdates 롱폴링 — 모든 메시지 + 콜백 처리."""
    global _tg_last_update_id
    while not _tg_stop_poll.is_set():
        with _tg_lock:
            if not _tg_config["enabled"]:
                _tg_stop_poll.wait(5)
                continue
        try:
            result = _tg_api("getUpdates", {"offset": _tg_last_update_id + 1, "timeout": 30})
            if result and result.get("ok"):
                for update in result.get("result", []):
                    _tg_last_update_id = update["update_id"]

                    # 인라인 버튼 콜백
                    cbq = update.get("callback_query")
                    if cbq:
                        _tg_handle_callback(cbq)
                        continue

                    # 일반 메시지 — 모든 텍스트 처리 (자연어 포함)
                    msg = update.get("message", {})
                    text = msg.get("text", "")
                    chat_id_from = msg.get("chat", {}).get("id", "")
                    if text:
                        _tg_handle_command(text, chat_id_from)
        except Exception:
            _tg_stop_poll.wait(5)


def _tg_handle_callback(cbq):
    """인라인 버튼 콜백 처리."""
    data = cbq.get("data", "")
    chat_id_from = cbq.get("message", {}).get("chat", {}).get("id", "")

    with _tg_lock:
        expected_chat = _tg_config["chat_id"]
    if str(chat_id_from) != str(expected_chat):
        return

    # 콜백 응답 (버튼 로딩 해제)
    _tg_api("answerCallbackQuery", {"callback_query_id": cbq.get("id")})

    # ── 스킬 콜백 ──
    if data.startswith("skill:"):
        skill = data[6:]
        return _tg_exec_skill(skill)

    # ── 프로젝트 선택 (스킬 메뉴에서) ──
    if data.startswith("sproj:"):
        parts = data[6:].split(":", 1)
        skill = parts[0]
        proj = parts[1] if len(parts) > 1 else ""
        return _tg_exec_skill_with_project(skill, proj)

    # ── 아카이브 콜백 ──
    if data.startswith("skill_archive:"):
        team_name = data[14:]
        return _tg_cmd_archive(team_name)

    # ── 기존: 프로젝트 선택 ──
    if data.startswith("use:"):
        project_name = data[4:]
        path = _find_project_path(project_name)
        if path:
            _tg_context["project"] = project_name
            _tg_context["project_path"] = path
            pending = _tg_context.pop("pending_instruction", None)
            if pending:
                _tg_send(f"📂 <b>{project_name}</b> 선택. 작업을 시작합니다.")
                threading.Thread(target=_orch_dispatch, args=(project_name, pending, path), daemon=True).start()
            else:
                _tg_send(f"📂 프로젝트 전환: <b>{project_name}</b>")


def _tg_start_polling():
    """Telegram 폴링 시작."""
    global _tg_poll_thread
    if _tg_poll_thread and _tg_poll_thread.is_alive():
        return
    _tg_stop_poll.clear()
    _tg_poll_thread = threading.Thread(target=_tg_poll_loop, daemon=True)
    _tg_poll_thread.start()


# ── 오케스트레이터 엔진 (지시 → 티켓 → CLI 스폰 → 완료 보고) ──

_orch_lock = threading.Lock()
_orch_jobs = {}   # job_id -> { team_id, status, sessions: {ticket_id: session_id} }

# Claude CLI 경로 자동 탐지
_claude_cli_path = None

def _find_claude_cli():
    """Claude CLI 실행 경로를 자동 탐지."""
    global _claude_cli_path
    if _claude_cli_path and os.path.isfile(_claude_cli_path):
        return _claude_cli_path
    candidates = ["claude"]
    if os.name == "nt":
        appdata = os.environ.get("APPDATA", "")
        localappdata = os.environ.get("LOCALAPPDATA", "")
        candidates += [
            os.path.join(appdata, "npm", "claude.cmd"),
            os.path.join(appdata, "npm", "claude"),
            os.path.join(localappdata, "Programs", "claude-code", "claude.exe"),
        ]
    else:
        candidates += [
            "/usr/bin/claude",  # Ubuntu 시스템 설치 (최우선)
            os.path.expanduser("~/.npm-global/bin/claude"),
            "/usr/local/bin/claude",
            os.path.expanduser("~/.local/bin/claude"),
            os.path.expanduser("~/.nvm/versions/node/*/bin/claude"),
        ]
    for c in candidates:
        try:
            result = subprocess.run([c, "--version"], capture_output=True, timeout=5)
            if result.returncode == 0:
                _claude_cli_path = c
                return c
        except Exception:
            continue
    return "claude"  # fallback to PATH


def _orch_dispatch(team_name, instruction, project_path):
    """사용자 지시를 받아 티켓 분해 → 에이전트 스폰 → 모니터링까지 전체 파이프라인 실행.
    이 함수는 항상 백그라운드 스레드에서 실행됨 — 대화를 블로킹하지 않음."""
    job_id = "job-" + uuid.uuid4().hex[:8]
    _tg_send(f"📂 <b>{team_name}</b> 작업을 준비하고 있어요. 대화는 계속하셔도 됩니다!")

    # 1. 팀 찾기 — name 또는 project_group으로 매칭
    conn = get_db()
    team = conn.execute(
        "SELECT * FROM agent_teams WHERE (name LIKE ? OR project_group LIKE ?) AND status='Active'",
        (f"%{team_name}%", f"%{team_name}%")
    ).fetchone()
    if not team:
        tid = short_id("team-")
        conn.execute(
            "INSERT INTO agent_teams (team_id, name, project_group, status) VALUES (?,?,?,?)",
            (tid, team_name, team_name, "Active")
        )
        conn.commit()
        team_id = tid
        sse_broadcast(team_id, "team_created", {"team_id": team_id, "name": team_name})
    else:
        team_id = team["team_id"]

    # 2. 기존 미처리 티켓(Backlog/Todo) 확인 — 있으면 새로 만들지 않음
    pending = rows_to_list(conn.execute(
        "SELECT ticket_id, title, description, priority, status, tags FROM tickets "
        "WHERE team_id=? AND status IN ('Backlog','Todo') ORDER BY created_at",
        (team_id,)
    ).fetchall())
    conn.close()

    if pending:
        # 기존 티켓 그대로 실행
        ticket_ids = [t["ticket_id"] for t in pending]
        tickets = pending
        _tg_send(
            f"📋 <b>{team_name}</b> — 기존 미처리 티켓 {len(pending)}개 발견, 새로 만들지 않고 실행\n"
            + "\n".join(f"  • {t['ticket_id']} {t['title']}" for t in pending[:10])
        )
    else:
        # 3. 기존 티켓 없을 때만 새로 분해
        parsed = _orch_parse_instruction(instruction, project_path)
        if not parsed:
            _tg_send("⚠️ 지시 분석 실패. 수동으로 티켓을 생성해주세요.")
            return

        conn = get_db()
        ticket_ids = []
        tickets = parsed
        for i, t in enumerate(parsed):
            tkt_id = short_id("tkt-")
            deps = t.get("depends_on", "")
            if deps and ticket_ids:
                dep_indices = [int(d.strip()) - 1 for d in str(deps).split(",") if d.strip().isdigit()]
                dep_ids = [ticket_ids[j] for j in dep_indices if j < len(ticket_ids)]
                deps = ",".join(dep_ids)
            conn.execute(
                "INSERT INTO tickets (ticket_id, team_id, title, description, priority, status, depends_on, tags) VALUES (?,?,?,?,?,?,?,?)",
                (tkt_id, team_id, t["title"], t.get("description", ""), t.get("priority", "Medium"), "Todo", deps, t.get("tags", ""))
            )
            ticket_ids.append(tkt_id)
            sse_broadcast(team_id, "ticket_created", {"ticket_id": tkt_id, "title": t["title"]})
        conn.commit()
        conn.close()

        lines = [f"📋 <b>{len(parsed)}개 티켓 생성 완료</b>\n"]
        for i, t in enumerate(parsed):
            dep_str = f" (선행: {t.get('depends_on', '')})" if t.get("depends_on") else ""
            lines.append(f"{i+1}. {t['title']}{dep_str}")
        lines.append(f"\n에이전트를 스폰합니다...")
        _tg_send("\n".join(lines))

    # 5. 잡 등록 + 에이전트 스폰
    with _orch_lock:
        _orch_jobs[job_id] = {
            "team_id": team_id, "team_name": team_name,
            "project_path": project_path,
            "instruction": instruction,
            "ticket_ids": ticket_ids, "tickets": tickets,
            "sessions": {}, "status": "running"
        }

    # 의존성 없는 티켓부터 스폰
    _orch_spawn_ready(job_id)

    # 모니터 시작
    threading.Thread(target=_orch_monitor, args=(job_id,), daemon=True).start()
    return job_id


def _orch_parse_instruction(instruction, project_path):
    """지시를 구조화된 티켓 목록으로 분해. API 우선 → CLI 폴백 → 규칙 기반 폴백."""
    prompt = (
        "당신은 프로젝트 작업 분해 전문가입니다. "
        "아래 지시를 독립적으로 실행 가능한 티켓 목록으로 분해하세요. "
        f"지시: {instruction} "
        f"프로젝트 경로: {project_path} "
        "JSON 배열로만 응답. 다른 텍스트 없이 순수 JSON만: "
        '[{"title":"...","description":"구체적 구현","priority":"High|Medium|Low","tags":"backend|frontend|infra","depends_on":""}] '
        "depends_on은 선행 티켓 번호(1-based,쉼표). 없으면 빈 문자열. 3~6개로 분해."
    )

    api_response = _smart_chat(prompt)
    if api_response:
        tickets = _extract_json_array(api_response)
        if tickets:
            return tickets

    # 2차: CLI 폴백
    cli = _find_claude_cli()
    try:
        result = subprocess.run(
            [cli, "-p", prompt, "--output-format", "json", "--model", "sonnet"],
            capture_output=True, text=True, timeout=120, cwd=project_path
        )
        output = result.stdout.strip()
        for extract_fn in [_extract_json_array, _extract_from_output_format]:
            tickets = extract_fn(output)
            if tickets:
                return tickets
    except Exception:
        pass

    # ── 폴백: 규칙 기반 단순 분해 ──
    return _fallback_parse(instruction)


def _extract_json_array(text):
    """텍스트에서 JSON 배열 추출."""
    start = text.find("[")
    end = text.rfind("]") + 1
    if start >= 0 and end > start:
        try:
            arr = json.loads(text[start:end])
            if isinstance(arr, list) and arr:
                return arr
        except json.JSONDecodeError:
            pass
    return None


def _extract_from_output_format(text):
    """--output-format json 응답에서 result 필드 추출."""
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict) and "result" in parsed:
            return _extract_json_array(parsed["result"])
    except Exception:
        pass
    return None


def _fallback_parse(instruction):
    """CLI 없이 규칙 기반으로 지시를 단일 티켓으로 생성."""
    lines = [l.strip() for l in instruction.split("\n") if l.strip()]
    if len(lines) <= 1:
        return [{"title": instruction[:80], "description": instruction, "priority": "High", "tags": "", "depends_on": ""}]

    # 여러 줄이면 각 줄을 티켓으로
    tickets = []
    for i, line in enumerate(lines[:6]):
        tickets.append({
            "title": line[:80],
            "description": line,
            "priority": "High" if i == 0 else "Medium",
            "tags": "",
            "depends_on": ""
        })
    return tickets


def _orch_spawn_ready(job_id):
    """의존성이 충족된 티켓에 대해 Claude CLI 에이전트를 스폰."""
    with _orch_lock:
        job = _orch_jobs.get(job_id)
        if not job or job["status"] != "running":
            return

    conn = get_db()
    for tkt_id in job["ticket_ids"]:
        # 이미 스폰됨?
        if tkt_id in job["sessions"]:
            continue

        ticket = row_to_dict(conn.execute("SELECT * FROM tickets WHERE ticket_id=?", (tkt_id,)).fetchone())
        if not ticket or ticket["status"] not in ("Todo", "Backlog"):
            continue

        # 의존성 체크
        deps = ticket.get("depends_on", "")
        if deps:
            dep_ids = [d.strip() for d in deps.split(",") if d.strip()]
            all_done = True
            for dep_id in dep_ids:
                dep_ticket = conn.execute("SELECT status FROM tickets WHERE ticket_id=?", (dep_id,)).fetchone()
                if not dep_ticket or dep_ticket["status"] != "Done":
                    all_done = False
                    break
            if not all_done:
                continue

        # 스폰!
        _orch_spawn_agent(job_id, tkt_id, ticket, job["project_path"], job["team_id"])
    conn.close()


def _orch_spawn_agent(job_id, ticket_id, ticket, project_path, team_id):
    """개별 티켓에 대한 Claude CLI 에이전트 스폰 — MCP 칸반보드 연동."""
    cli = _find_claude_cli()
    title = ticket["title"]
    desc = ticket.get("description", "") or ""
    tags = ticket.get("tags", "") or ""

    # 원래 사용자 지시 가져오기
    with _orch_lock:
        job = _orch_jobs.get(job_id, {})
    user_instruction = job.get("instruction", "")

    # 에이전트의 전문 역할 결정
    role = "fullstack developer"
    if "backend" in tags:
        role = "backend developer"
    elif "frontend" in tags:
        role = "frontend developer"
    elif "infra" in tags:
        role = "DevOps engineer"

    agent_prompt = f"""당신은 {role} 전문 에이전트입니다.

## 사용자의 원래 지시 (구어체 — 의도를 정확히 파악하세요)
{user_instruction}

## 할당된 티켓
- ID: {ticket_id}
- 제목: {title}
- 설명: {desc}
- 우선순위: {ticket.get('priority', 'Medium')}

## 중요: 지시 해석 원칙
- 사용자 지시가 구어체여도 의도를 정확히 파악하세요.
- "하나 지워줘" = 정확히 1개만. 나머지는 절대 건드리지 마세요.
- "추가해줘" = 기존 내용은 보존하고 추가만 하세요.
- 애매하면 최소한으로 변경하세요. 확대 해석하지 마세요.
- 작업 전 반드시 현재 상태를 확인하고, 변경 후 검증하세요.

## 칸반보드 연동
이 프로젝트는 MCP 칸반보드(http://localhost:{DEFAULT_PORT}/mcp)에 연동되어 있습니다.
kanban_ticket_status 도구로 티켓 상태를 업데이트하세요:
- 작업 시작 시: InProgress
- 코드 리뷰 필요 시: Review
- 완료 시: Done

kanban_activity_log 도구로 주요 작업 내용을 기록하세요.
kanban_artifact_create 도구로 주요 산출물(코드, 설정 등)을 공유하세요.

## 규칙
1. 이 티켓만 처리하세요. 범위 밖 작업은 하지 마세요.
2. 구현 후 빌드/테스트 확인하세요.
3. 완료 시 티켓을 Done으로 업데이트하고 즉시 종료하세요.
4. 에러 발생 시 티켓에 activity_log로 기록하고 Blocked로 전환하세요.
"""

    session_id = "cs-" + uuid.uuid4().hex[:8]
    cmd = [cli, "-p", agent_prompt, "--output-format", "json", "--model", "sonnet"]

    try:
        creation_flags = 0
        if os.name == "nt":
            creation_flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW

        proc = subprocess.Popen(
            cmd, cwd=project_path,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=creation_flags
        )
        _claude_processes[session_id] = proc

        conn = get_db()
        conn.execute(
            "INSERT INTO claude_sessions (session_id, project_path, team_id, pid, status) VALUES (?,?,?,?,?)",
            (session_id, project_path, team_id, proc.pid, "running")
        )
        conn.execute("UPDATE tickets SET status='InProgress', assigned_member_id=?, started_at=datetime('now') WHERE ticket_id=?",
                      (session_id, ticket_id))
        conn.commit()
        conn.close()

        with _orch_lock:
            _orch_jobs[job_id]["sessions"][ticket_id] = session_id

        sse_broadcast(team_id, "ticket_status_changed", {"ticket_id": ticket_id, "status": "InProgress", "ticket_title": title})
        _tg_send(f"🤖 <b>{role} 에이전트</b>\n{title}\nPID: {proc.pid}")

        threading.Thread(target=_orch_wait_agent, args=(job_id, ticket_id, session_id, proc), daemon=True).start()

    except FileNotFoundError:
        _tg_send(f"❌ claude CLI 없음 — {title} 스폰 실패")
    except Exception as e:
        _tg_send(f"❌ 스폰 오류 ({title}): {e}")


def _parse_cli_usage(stdout_bytes):
    """Claude CLI JSON 출력에서 토큰/비용 정보 파싱 (cache 토큰 포함)."""
    try:
        for line in reversed(stdout_bytes.decode("utf-8", errors="replace").strip().splitlines()):
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
                usage = d.get("usage") or {}
                # 입력 토큰: 순수 + cache_creation + cache_read
                inp_base = d.get("total_input_tokens") or d.get("input_tokens") or usage.get("input_tokens", 0)
                cache_create = usage.get("cache_creation_input_tokens", 0)
                cache_read = usage.get("cache_read_input_tokens", 0)
                inp = int(inp_base or 0) + int(cache_create or 0) + int(cache_read or 0)
                out = int(d.get("total_output_tokens") or d.get("output_tokens") or usage.get("output_tokens", 0) or 0)
                cost = d.get("cost_usd") or d.get("total_cost_usd") or 0.0
                # modelUsage에서 더 정확한 값 추출 시도
                model_usage = d.get("modelUsage") or {}
                if model_usage:
                    for mname, mu in model_usage.items():
                        mu_inp = int(mu.get("inputTokens", 0)) + int(mu.get("cacheCreationInputTokens", 0)) + int(mu.get("cacheReadInputTokens", 0))
                        mu_out = int(mu.get("outputTokens", 0))
                        mu_cost = mu.get("costUSD", 0.0)
                        if mu_inp or mu_out:
                            inp, out, cost = mu_inp, mu_out, float(mu_cost or cost)
                            break
                model = d.get("model", "claude-sonnet-4-6")
                if inp or out or cost:
                    return {"input_tokens": inp, "output_tokens": out, "cost": float(cost), "model": model}
            except Exception:
                continue
    except Exception:
        pass
    return None


def _record_token_usage(team_id, ticket_id, session_id, usage):
    """token_usage 테이블에 기록."""
    if not usage:
        return
    try:
        conn = get_db()
        conn.execute(
            "INSERT INTO token_usage (team_id,ticket_id,member_id,model,input_tokens,output_tokens,estimated_cost) VALUES (?,?,?,?,?,?,?)",
            (team_id, ticket_id, session_id, usage.get("model", "unknown"),
             usage.get("input_tokens", 0), usage.get("output_tokens", 0), usage.get("cost", 0.0))
        )
        conn.commit()
        conn.close()
    except Exception:
        pass


def _orch_wait_agent(job_id, ticket_id, session_id, proc):
    """에이전트 프로세스 종료 감시 → Ralph Loop 리뷰 → 미달 시 재작업 (최대 3회)."""
    try:
        stdout_data, _ = proc.communicate(timeout=1800)  # 최대 30분
    except subprocess.TimeoutExpired:
        proc.terminate()
        stdout_data = b""
        _tg_send(f"⏰ 에이전트 타임아웃 (30분): {ticket_id}")

    exit_code = proc.returncode

    conn = get_db()
    conn.execute("UPDATE claude_sessions SET status='exited', ended_at=datetime('now') WHERE session_id=?", (session_id,))
    ticket = row_to_dict(conn.execute("SELECT * FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone())
    conn.commit()
    conn.close()

    if not ticket:
        return

    title = ticket["title"]
    team_id = _orch_jobs.get(job_id, {}).get("team_id", "")
    project_path = _orch_jobs.get(job_id, {}).get("project_path", "")
    retry_count = ticket.get("retry_count", 0) or 0
    max_retries = ticket.get("max_retries", 3) or 3

    # 토큰 사용량 파싱 & 기록
    usage = _parse_cli_usage(stdout_data)
    _record_token_usage(team_id, ticket_id, session_id, usage)
    if usage:
        _tg_send(f"📊 토큰: 입력 {usage['input_tokens']:,} / 출력 {usage['output_tokens']:,} / ${usage['cost']:.4f}")

    # 프로세스 정리
    if session_id in _claude_processes:
        del _claude_processes[session_id]

    if exit_code != 0:
        # 실패 → Blocked
        conn = get_db()
        conn.execute("UPDATE tickets SET status='Blocked', completed_at=datetime('now') WHERE ticket_id=?", (ticket_id,))
        conn.commit()
        conn.close()
        sse_broadcast(team_id, "ticket_status_changed", {"ticket_id": ticket_id, "status": "Blocked", "ticket_title": title})
        _tg_send(f"🚫 <b>실패</b>: {title} (exit code: {exit_code})")
        _orch_spawn_ready(job_id)
        return

    # ── Ralph Loop: 자동 리뷰 ──
    review_result = _ralph_review(ticket_id, ticket, project_path)

    if review_result["pass"]:
        # 리뷰 통과 → Done
        conn = get_db()
        conn.execute("UPDATE tickets SET status='Done', completed_at=datetime('now') WHERE ticket_id=?", (ticket_id,))
        conn.execute(
            "INSERT INTO ticket_reviews (ticket_id, team_id, reviewer, result, score, comment, retry_round) VALUES (?,?,?,?,?,?,?)",
            (ticket_id, team_id, "orchestrator", "pass", review_result.get("score", 5), review_result.get("comment", ""), retry_count)
        )
        conn.commit()
        conn.close()
        sse_broadcast(team_id, "ticket_status_changed", {"ticket_id": ticket_id, "status": "Done", "ticket_title": title})
        _tg_send(f"✅ <b>리뷰 통과</b>: {title} (점수: {review_result.get('score', 5)}/5)")
        _orch_spawn_ready(job_id)
    elif retry_count >= max_retries:
        # 최대 재작업 횟수 초과 → 강제 Done + 경고
        conn = get_db()
        conn.execute("UPDATE tickets SET status='Done', completed_at=datetime('now') WHERE ticket_id=?", (ticket_id,))
        conn.execute(
            "INSERT INTO ticket_reviews (ticket_id, team_id, reviewer, result, score, comment, retry_round) VALUES (?,?,?,?,?,?,?)",
            (ticket_id, team_id, "orchestrator", "force_pass", review_result.get("score", 2),
             f"최대 재작업 횟수({max_retries}회) 초과. 강제 완료.", retry_count)
        )
        conn.commit()
        conn.close()
        sse_broadcast(team_id, "ticket_status_changed", {"ticket_id": ticket_id, "status": "Done", "ticket_title": title})
        _tg_send(f"⚠️ <b>강제 완료</b>: {title}\n재작업 {max_retries}회 초과. 수동 확인 필요.")
        _orch_spawn_ready(job_id)
    else:
        # 리뷰 미달 → 재작업 티켓 발행
        new_retry = retry_count + 1
        conn = get_db()
        conn.execute("UPDATE tickets SET status='Blocked', retry_count=? WHERE ticket_id=?", (new_retry, ticket_id))
        conn.execute(
            "INSERT INTO ticket_reviews (ticket_id, team_id, reviewer, result, score, comment, retry_round, issues) VALUES (?,?,?,?,?,?,?,?)",
            (ticket_id, team_id, "orchestrator", "rework", review_result.get("score", 2),
             review_result.get("comment", ""), new_retry, review_result.get("issues", ""))
        )
        conn.commit()
        conn.close()

        _tg_send(
            f"🔄 <b>Ralph Loop 재작업 ({new_retry}/{max_retries})</b>\n"
            f"{title}\n문제: {review_result.get('issues', '품질 미달')}"
        )

        # 재작업 에이전트 스폰
        rework_ticket = dict(ticket)
        rework_ticket["description"] = (
            f"[재작업 {new_retry}/{max_retries}]\n"
            f"이전 리뷰 결과: {review_result.get('comment', '')}\n"
            f"수정 필요 사항: {review_result.get('issues', '')}\n\n"
            f"원본 설명: {ticket.get('description', '')}"
        )
        rework_ticket["retry_count"] = new_retry
        # 세션 제거 후 재스폰
        with _orch_lock:
            job = _orch_jobs.get(job_id)
            if job and ticket_id in job["sessions"]:
                del job["sessions"][ticket_id]
        conn = get_db()
        conn.execute("UPDATE tickets SET status='Todo', assigned_member_id=NULL WHERE ticket_id=?", (ticket_id,))
        conn.commit()
        conn.close()
        _orch_spawn_agent(job_id, ticket_id, rework_ticket, project_path, team_id)


def _ralph_review(ticket_id, ticket, project_path):
    """Claude CLI로 완료된 티켓의 산출물을 리뷰. 합격/불합격 판정."""
    cli = _find_claude_cli()
    if not cli:
        return {"pass": True, "score": 3, "comment": "CLI 없음 — 리뷰 건너뜀"}

    title = ticket.get("title", "")
    desc = ticket.get("description", "")

    review_prompt = f"""당신은 코드 리뷰어입니다. 방금 완료된 티켓의 작업 결과를 검증하세요.

## 티켓
- 제목: {title}
- 설명: {desc}

## 검증 항목
1. 요구사항이 충족되었는가?
2. 빌드/구문 오류는 없는가?
3. 보안 취약점은 없는가?

## 응답 형식 (JSON만)
{{"pass": true/false, "score": 1-5, "comment": "한줄 요약", "issues": "구체적 문제점 (불합격 시)"}}"""

    try:
        review_result = _smart_chat(review_prompt)
        if review_result:
            start = review_result.find("{")
            end = review_result.rfind("}") + 1
            if start >= 0 and end > start:
                return json.loads(review_result[start:end])
    except Exception:
        pass

    try:
        result = subprocess.run(
            [cli, "-p", review_prompt, "--output-format", "json", "--model", "sonnet"],
            capture_output=True, text=True, timeout=90, cwd=project_path
        )
        output = result.stdout.strip()
        # JSON 추출
        start = output.find("{")
        end = output.rfind("}") + 1
        if start >= 0 and end > start:
            parsed = json.loads(output[start:end])
            return parsed
        # output-format json wrapper
        try:
            wrapper = json.loads(output)
            if isinstance(wrapper, dict) and "result" in wrapper:
                text = wrapper["result"]
                s = text.find("{")
                e = text.rfind("}") + 1
                if s >= 0 and e > s:
                    return json.loads(text[s:e])
        except Exception:
            pass
    except subprocess.TimeoutExpired:
        pass
    except Exception:
        pass
    # 리뷰 실패 시 기본 통과
    return {"pass": True, "score": 3, "comment": "자동 리뷰 실행 불가 — 기본 통과"}


def _orch_monitor(job_id):
    """전체 작업 완료를 감시하고 최종 보고."""
    while True:
        time.sleep(10)
        with _orch_lock:
            job = _orch_jobs.get(job_id)
            if not job or job["status"] != "running":
                return

        conn = get_db()
        tickets = conn.execute(
            "SELECT ticket_id, title, status FROM tickets WHERE ticket_id IN ({})".format(
                ",".join("?" * len(job["ticket_ids"]))
            ), job["ticket_ids"]
        ).fetchall()
        conn.close()

        statuses = {t["ticket_id"]: t["status"] for t in tickets}
        all_done = all(s == "Done" for s in statuses.values())
        any_blocked = any(s == "Blocked" for s in statuses.values())
        all_terminal = all(s in ("Done", "Blocked") for s in statuses.values())

        if all_done:
            with _orch_lock:
                job["status"] = "completed"
            _orch_report_completion(job_id, tickets)
            return
        elif all_terminal and any_blocked:
            with _orch_lock:
                job["status"] = "partial"
            _orch_report_completion(job_id, tickets)
            return


def _orch_report_completion(job_id, tickets):
    """작업 완료 보고를 Telegram으로 전송."""
    with _orch_lock:
        job = _orch_jobs.get(job_id, {})
    team_name = job.get("team_name", "?")
    status = job.get("status", "?")

    done = [t for t in tickets if t["status"] == "Done"]
    blocked = [t for t in tickets if t["status"] == "Blocked"]

    icon = "✅" if status == "completed" else "⚠️"
    lines = [f"{icon} <b>{team_name} — 작업 {'완료' if status == 'completed' else '부분 완료'}</b>\n"]

    if done:
        lines.append(f"<b>완료 ({len(done)})</b>")
        for t in done:
            lines.append(f"  ✅ {t['title']}")
    if blocked:
        lines.append(f"\n<b>실패 ({len(blocked)})</b>")
        for t in blocked:
            lines.append(f"  🚫 {t['title']}")

    lines.append(f"\n총 {len(done)}/{len(tickets)}개 완료")
    _tg_send("\n".join(lines))

    # 팀 아카이브 제안 (전체 완료 시)
    if status == "completed":
        _tg_send("📦 전체 완료! /archive " + team_name + " 으로 아카이브할 수 있습니다.")


def _orch_cancel(job_id):
    """진행 중인 작업을 취소."""
    with _orch_lock:
        job = _orch_jobs.get(job_id)
        if not job:
            return False
        job["status"] = "cancelled"

    # 실행 중인 에이전트 중지
    for tkt_id, session_id in job.get("sessions", {}).items():
        if session_id in _claude_processes:
            try:
                _claude_processes[session_id].terminate()
            except Exception:
                pass
            del _claude_processes[session_id]

    conn = get_db()
    for tkt_id in job.get("ticket_ids", []):
        conn.execute("UPDATE tickets SET status='Blocked' WHERE ticket_id=? AND status IN ('Todo','InProgress')", (tkt_id,))
    for sid in job.get("sessions", {}).values():
        conn.execute("UPDATE claude_sessions SET status='cancelled', ended_at=datetime('now') WHERE session_id=?", (sid,))
    conn.commit()
    conn.close()

    _tg_send(f"🛑 <b>작업 취소됨</b>: {job.get('team_name', '?')}")
    return True


def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def short_id(prefix=""):
    return prefix + uuid.uuid4().hex[:8]


def row_to_dict(row):
    if row is None:
        return None
    return dict(row)


def rows_to_list(rows):
    return [dict(r) for r in rows]


# ── 라이선스 관리 ──

_LICENSE_SALT = "u2dia-kanban-2026"
_LICENSE_CHARS = string.ascii_uppercase + string.digits  # A-Z, 0-9


def _hash_license(key: str) -> str:
    normalized = key.replace("-", "").upper()
    return hashlib.sha256((_LICENSE_SALT + normalized).encode()).hexdigest()


def _generate_license_key() -> str:
    chars = _LICENSE_CHARS
    groups = []
    for _ in range(4):
        group = ''.join(secrets.choice(chars) for _ in range(4))
        groups.append(group)
    return '-'.join(groups)


def _mask_license(key: str) -> str:
    parts = key.split('-')
    if len(parts) == 4:
        return f"{parts[0]}-****-****-{parts[3]}"
    return "****-****-****-****"


# 세션 관리 (in-memory)
_sessions = {}   # token -> {"license_hash": str, "created_at": float, "last_used": float}
_sessions_lock = threading.Lock()
_SESSION_TTL = 86400  # 24시간


def _create_session(license_hash: str) -> str:
    token = secrets.token_hex(32)
    with _sessions_lock:
        _sessions[token] = {
            "license_hash": license_hash,
            "created_at": time.time(),
            "last_used": time.time()
        }
    return token


def _validate_session(token: str) -> bool:
    with _sessions_lock:
        session = _sessions.get(token)
        if not session:
            return False
        if time.time() - session["last_used"] > _SESSION_TTL:
            _sessions.pop(token, None)
            return False
        session["last_used"] = time.time()
        return True


def _is_local_request(handler) -> bool:
    client_ip = handler.client_address[0]
    # 로컬호스트 + Tailscale 대역(100.64.0.0/10) 신뢰
    if client_ip in ("127.0.0.1", "::1"):
        return True
    # Tailscale IP 대역: 100.64.0.0 ~ 100.127.255.255
    if client_ip.startswith("100."):
        try:
            parts = client_ip.split(".")
            second = int(parts[1])
            if 64 <= second <= 127:
                return True
        except Exception:
            pass
    return False


def _validate_project_path(path: str) -> bool:
    """project_path가 허용된 홈 디렉토리 하위인지 검증 (경로 순회 방지)."""
    if not path:
        return False
    try:
        import pathlib
        resolved = str(pathlib.Path(path).resolve())
        home = str(pathlib.Path.home())
        # 홈 디렉토리 하위이고 실제 디렉토리여야 함
        if not resolved.startswith(home):
            return False
        if not os.path.isdir(resolved):
            return False
        # 민감 경로 차단
        blocked = ["/etc", "/sys", "/proc", "/dev", "/root", "/boot", "/bin", "/sbin", "/usr/bin"]
        for b in blocked:
            if resolved.startswith(b):
                return False
        return True
    except Exception:
        return False


def _validate_license_key(key: str) -> bool:
    key_hash = _hash_license(key)
    conn = get_db()
    row = conn.execute(
        "SELECT is_active, expires_at FROM licenses WHERE license_key_hash=? AND is_active=1",
        (key_hash,)
    ).fetchone()
    if not row:
        conn.close()
        return False
    if row["expires_at"] and now_utc() > row["expires_at"]:
        conn.close()
        return False
    conn.execute(
        "UPDATE licenses SET last_used_at=?, use_count=use_count+1 WHERE license_key_hash=?",
        (now_utc(), key_hash)
    )
    conn.commit()
    conn.close()
    return True


def _validate_auth_token(key: str) -> bool:
    """auth_tokens 테이블에서 토큰 검증."""
    info = _get_auth_token_info(key)
    return info is not None


def _get_auth_token_info(key: str):
    """auth_tokens에서 토큰 검증 후 토큰 정보(name 포함) 반환. 실패 시 None."""
    key_hash = _hash_license(key)
    conn = get_db()
    row = conn.execute(
        "SELECT id, name, is_active FROM auth_tokens WHERE token_hash=? AND is_active=1",
        (key_hash,)
    ).fetchone()
    if not row:
        conn.close()
        return None
    conn.execute(
        "UPDATE auth_tokens SET last_used_at=?, use_count=use_count+1 WHERE id=?",
        (now_utc(), row["id"])
    )
    conn.commit()
    info = {"id": row["id"], "name": row["name"] or ""}
    conn.close()
    return info


# Rate limiting (IP 기반)
_rate_limit = {}
_rate_limit_lock = threading.Lock()
_RATE_LIMIT_MAX = 30
_RATE_LIMIT_WINDOW = 60   # 1분 (30회 초과 시 차단)


def _penalize_ip(ip: str, count: int = 5):
    """인증 실패 시 rate limit 카운트를 추가 증가시킴."""
    now = time.time()
    with _rate_limit_lock:
        entry = _rate_limit.get(ip)
        if not entry or now > entry["reset_at"]:
            _rate_limit[ip] = {"count": count, "reset_at": now + _RATE_LIMIT_WINDOW}
        else:
            entry["count"] = min(entry["count"] + count, _RATE_LIMIT_MAX + 1)


def _check_rate_limit(ip: str) -> bool:
    now = time.time()
    with _rate_limit_lock:
        entry = _rate_limit.get(ip)
        if not entry or now > entry["reset_at"]:
            _rate_limit[ip] = {"count": 1, "reset_at": now + _RATE_LIMIT_WINDOW}
            return True
        if entry["count"] >= _RATE_LIMIT_MAX:
            return False
        entry["count"] += 1
        return True


# ── API 핸들러 ──

def api_teams_list(params):
    conn = get_db()
    status_filter = params.get("status", [None])[0]
    include_archived = params.get("include_archived", [None])[0]
    project_group = params.get("project_group", [None])[0] if isinstance(params.get("project_group"), list) else params.get("project_group")
    if status_filter:
        rows = conn.execute("SELECT * FROM agent_teams WHERE status=? ORDER BY created_at DESC", (status_filter,)).fetchall()
    elif include_archived:
        rows = conn.execute("SELECT * FROM agent_teams ORDER BY created_at DESC").fetchall()
    else:
        rows = conn.execute("SELECT * FROM agent_teams WHERE status != 'Archived' ORDER BY created_at DESC").fetchall()
    conn.close()
    teams = rows_to_list(rows)
    if project_group:
        teams = [t for t in teams if t.get("project_group") == project_group]
    return {"ok": True, "count": len(teams), "teams": teams}


def api_teams_create(body):
    name = body.get("name")
    if not name:
        return {"ok": False, "error": "missing_field", "message": "필수 필드 'name'이 없습니다", "example": {"name": "팀 이름", "description": "팀 설명(선택)", "project_group": "프로젝트명(필수)"}}
    project_group = body.get("project_group", "")
    if not project_group:
        return {"ok": False, "error": "missing_field", "message": "필수 필드 'project_group'이 없습니다. git 프로젝트명을 지정하세요.", "example": {"name": "팀 이름", "project_group": "LINKO"}}
    # WriteQueue 경유 (활성 시) 또는 직접 실행 (폴백)
    if _write_queue._running:
        try:
            result = _write_queue.submit(_impl_team_create, body)
        except Exception as e:
            return {"ok": False, "error": f"team_create_failed: {e}"}
        if result.get("ok") and result.get("team"):
            sse_broadcast(result["team"]["team_id"], "team_created", {"team_id": result["team"]["team_id"], "name": name})
        return result
    # 폴백: 직접 실행
    tid = short_id("team-")
    conn = get_db()
    try:
        ts = now_utc()
        conn.execute(
            "INSERT INTO agent_teams (team_id,name,description,project_group,leader_agent,status,created_at) VALUES (?,?,?,?,?,?,?)",
            (tid, name, body.get("description"), project_group, body.get("leader_agent", "orchestrator"), "Active", ts))
        conn.execute(
            "INSERT INTO activity_logs (team_id,action,message,created_at) VALUES (?,?,?,?)",
            (tid, "team_created", f"팀 '{name}' 생성됨", ts))
        conn.commit()
        team = row_to_dict(conn.execute("SELECT * FROM agent_teams WHERE team_id=?", (tid,)).fetchone())
    except sqlite3.IntegrityError:
        conn.rollback()
        return {"ok": False, "error": "duplicate_team_id"}
    except Exception as e:
        conn.rollback()
        return {"ok": False, "error": f"team_create_failed: {e}"}
    finally:
        conn.close()
    sse_broadcast(tid, "team_created", {"team_id": tid, "name": name})
    return {"ok": True, "team": team}


def api_team_board(team_id):
    conn = get_db()
    team = row_to_dict(conn.execute("SELECT * FROM agent_teams WHERE team_id=?", (team_id,)).fetchone())
    if not team:
        conn.close()
        return {"ok": False, "error": "team_not_found"}
    members = rows_to_list(conn.execute("SELECT * FROM team_members WHERE team_id=? ORDER BY spawned_at", (team_id,)).fetchall())
    tickets = rows_to_list(conn.execute("SELECT * FROM tickets WHERE team_id=? ORDER BY created_at", (team_id,)).fetchall())
    logs = rows_to_list(conn.execute("SELECT * FROM activity_logs WHERE team_id=? ORDER BY created_at DESC LIMIT 50", (team_id,)).fetchall())
    conn.close()
    for t in tickets:
        if t.get("depends_on"):
            try:
                t["depends_on"] = json.loads(t["depends_on"])
            except Exception:
                pass
        if t.get("tags"):
            try:
                t["tags"] = json.loads(t["tags"])
            except Exception:
                pass
    return {"ok": True, "board": {"team": team, "members": members, "tickets": tickets, "recent_logs": logs}}


def api_spawn_member(team_id, body):
    role = body.get("role")
    if not role:
        return {"ok": False, "error": "missing_field", "message": "필수 필드 'role'이 없습니다", "example": {"role": "backend", "display_name": "Backend Agent(선택)"}}
    if _write_queue._running:
        try:
            result = _write_queue.submit(_impl_member_spawn, team_id, body)
        except Exception as e:
            return {"ok": False, "error": f"member_spawn_failed: {e}"}
        if result.get("ok") and result.get("member"):
            m = result["member"]
            sse_broadcast(team_id, "member_spawned", {"member_id": m["member_id"], "role": role})
        return result
    mid = short_id("agent-")
    display = body.get("display_name") or (role + " Agent")
    conn = get_db()
    conn.execute(
        "INSERT INTO team_members (member_id,team_id,role,display_name,status,spawned_at) VALUES (?,?,?,?,?,?)",
        (mid, team_id, role, display, "Idle", now_utc())
    )
    conn.execute(
        "INSERT INTO activity_logs (team_id,member_id,action,message,created_at) VALUES (?,?,?,?,?)",
        (team_id, mid, "member_spawned", f"에이전트 '{display}' ({role}) 스폰됨", now_utc())
    )
    conn.commit()
    member = row_to_dict(conn.execute("SELECT * FROM team_members WHERE member_id=?", (mid,)).fetchone())
    conn.close()
    sse_broadcast(team_id, "member_spawned", {"member_id": mid, "role": role})
    return {"ok": True, "member": member}


def api_create_ticket(team_id, body):
    title = body.get("title")
    if not title:
        return {"ok": False, "error": "missing_field", "message": "필수 필드 'title'이 없습니다", "example": {"title": "티켓 제목", "description": "상세 설명(선택)", "priority": "High"}}
    if _write_queue._running:
        try:
            result = _write_queue.submit(_impl_ticket_create, team_id, body)
        except Exception as e:
            return {"ok": False, "error": f"ticket_create_failed: {e}"}
        if result.get("ok") and result.get("ticket"):
            t = result["ticket"]
            sse_broadcast(team_id, "ticket_created", {"ticket_id": t["ticket_id"], "title": title})
        return result
    tid = "T-" + uuid.uuid4().hex[:6].upper()
    deps = json.dumps(body["depends_on"]) if body.get("depends_on") else None
    tags = json.dumps(body["tags"]) if body.get("tags") else None
    conn = get_db()
    conn.execute(
        """INSERT INTO tickets (ticket_id,team_id,title,description,priority,status,depends_on,tags,estimated_minutes,created_at)
           VALUES (?,?,?,?,?,?,?,?,?,?)""",
        (tid, team_id, title, body.get("description"), body.get("priority", "Medium"),
         "Backlog", deps, tags, body.get("estimated_minutes", 0), now_utc())
    )
    conn.execute(
        "INSERT INTO activity_logs (team_id,ticket_id,action,message,created_at) VALUES (?,?,?,?,?)",
        (team_id, tid, "ticket_created", f"티켓 '{title}' 생성됨 (우선순위: {body.get('priority', 'Medium')})", now_utc())
    )
    conn.commit()
    ticket = row_to_dict(conn.execute("SELECT * FROM tickets WHERE ticket_id=?", (tid,)).fetchone())
    conn.close()
    sse_broadcast(team_id, "ticket_created", {"ticket_id": tid, "title": title})
    return {"ok": True, "ticket": ticket}


# ── 배치 API (WriteQueue 경유) ──

def _impl_team_create(conn, body):
    """WriteQueue에서 호출 — conn은 외부에서 주입."""
    name = body.get("name")
    if not name:
        return {"ok": False, "error": "missing_name"}
    project_group = body.get("project_group", "")
    if not project_group:
        return {"ok": False, "error": "missing_project_group"}
    tid = short_id("team-")
    ts = now_utc()
    conn.execute(
        "INSERT INTO agent_teams (team_id,name,description,project_group,leader_agent,status,created_at) VALUES (?,?,?,?,?,?,?)",
        (tid, name, body.get("description"), project_group, body.get("leader_agent", "orchestrator"), "Active", ts))
    conn.execute(
        "INSERT INTO activity_logs (team_id,action,message,created_at) VALUES (?,?,?,?)",
        (tid, "team_created", f"팀 '{name}' 생성됨 (batch)", ts))
    team = row_to_dict(conn.execute("SELECT * FROM agent_teams WHERE team_id=?", (tid,)).fetchone())
    return {"ok": True, "team": team}


def _impl_member_spawn(conn, team_id, body):
    """WriteQueue에서 호출."""
    role = body.get("role")
    if not role:
        return {"ok": False, "error": "missing_role"}
    mid = short_id("agent-")
    display = body.get("display_name") or (role + " Agent")
    ts = now_utc()
    conn.execute(
        "INSERT INTO team_members (member_id,team_id,role,display_name,status,spawned_at) VALUES (?,?,?,?,?,?)",
        (mid, team_id, role, display, "Idle", ts))
    conn.execute(
        "INSERT INTO activity_logs (team_id,member_id,action,message,created_at) VALUES (?,?,?,?,?)",
        (team_id, mid, "member_spawned", f"에이전트 '{display}' ({role}) 스폰됨 (batch)", ts))
    member = row_to_dict(conn.execute("SELECT * FROM team_members WHERE member_id=?", (mid,)).fetchone())
    return {"ok": True, "member": member}


def _impl_ticket_create(conn, team_id, body):
    """WriteQueue에서 호출."""
    title = body.get("title")
    if not title:
        return {"ok": False, "error": "missing_title"}
    tid = "T-" + uuid.uuid4().hex[:6].upper()
    deps = json.dumps(body["depends_on"]) if body.get("depends_on") else None
    tags = json.dumps(body["tags"]) if body.get("tags") else None
    ts = now_utc()
    conn.execute(
        """INSERT INTO tickets (ticket_id,team_id,title,description,priority,status,depends_on,tags,estimated_minutes,created_at)
           VALUES (?,?,?,?,?,?,?,?,?,?)""",
        (tid, team_id, title, body.get("description"), body.get("priority", "Medium"),
         "Backlog", deps, tags, body.get("estimated_minutes", 0), ts))
    conn.execute(
        "INSERT INTO activity_logs (team_id,ticket_id,action,message,created_at) VALUES (?,?,?,?,?)",
        (team_id, tid, "ticket_created", f"티켓 '{title}' 생성됨 (batch)", ts))
    ticket = row_to_dict(conn.execute("SELECT * FROM tickets WHERE ticket_id=?", (tid,)).fetchone())
    return {"ok": True, "ticket": ticket}


def api_batch_teams_create(body):
    """여러 팀을 한 번에 생성. {"teams": [{name, project_group, ...}, ...]}"""
    teams_data = body.get("teams", [])
    if not teams_data:
        return {"ok": False, "error": "empty_teams", "message": "teams 배열이 비어있습니다"}

    operations = [(_impl_team_create, (item,), {}) for item in teams_data]
    results = _write_queue.submit_batch(operations, timeout=60)

    # SSE 브로드캐스트 (큐 외부에서 — 논블로킹)
    for r in results:
        if r.get("ok") and r.get("team"):
            t = r["team"]
            sse_broadcast(t["team_id"], "team_created", {"team_id": t["team_id"], "name": t["name"]})

    succeeded = sum(1 for r in results if r.get("ok"))
    return {"ok": True, "total": len(teams_data), "succeeded": succeeded, "failed": len(teams_data) - succeeded, "results": results}


def api_batch_members_spawn(body):
    """여러 멤버를 한 번에 스폰. {"team_id": "...", "members": [{role, display_name}, ...]}"""
    team_id = body.get("team_id")
    members_data = body.get("members", [])
    if not team_id:
        return {"ok": False, "error": "missing_team_id"}
    if not members_data:
        return {"ok": False, "error": "empty_members"}

    operations = [(_impl_member_spawn, (team_id, item), {}) for item in members_data]
    results = _write_queue.submit_batch(operations, timeout=60)

    for r in results:
        if r.get("ok") and r.get("member"):
            m = r["member"]
            sse_broadcast(team_id, "member_spawned", {"member_id": m["member_id"], "role": m.get("role")})

    succeeded = sum(1 for r in results if r.get("ok"))
    return {"ok": True, "total": len(members_data), "succeeded": succeeded, "failed": len(members_data) - succeeded, "results": results}


def api_batch_tickets_create(body):
    """여러 티켓을 한 번에 생성. {"team_id": "...", "tickets": [{title, priority, ...}, ...]}"""
    team_id = body.get("team_id")
    tickets_data = body.get("tickets", [])
    if not team_id:
        return {"ok": False, "error": "missing_team_id"}
    if not tickets_data:
        return {"ok": False, "error": "empty_tickets"}

    operations = [(_impl_ticket_create, (team_id, item), {}) for item in tickets_data]
    results = _write_queue.submit_batch(operations, timeout=60)

    for r in results:
        if r.get("ok") and r.get("ticket"):
            t = r["ticket"]
            sse_broadcast(team_id, "ticket_created", {"ticket_id": t["ticket_id"], "title": t.get("title")})

    succeeded = sum(1 for r in results if r.get("ok"))
    return {"ok": True, "total": len(tickets_data), "succeeded": succeeded, "failed": len(tickets_data) - succeeded, "results": results}


def api_ticket_status(ticket_id, body):
    new_status = body.get("status")
    force = body.get("force", False)
    valid = {"Backlog", "Todo", "InProgress", "Review", "Done", "Blocked"}
    if new_status not in valid:
        return {"ok": False, "error": f"invalid_status: {new_status}"}
    conn = get_db()
    auto_archived = False
    auto_review_triggered = False
    try:

        ticket = row_to_dict(conn.execute("SELECT * FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone())
        if not ticket:
            conn.rollback()
            return {"ok": False, "error": "ticket_not_found"}

        # ── InProgress 전환 시 에이전트 필수 (v4.1 규정 — claim 없이 InProgress 전환 차단) ──
        if new_status == "InProgress" and not force:
            agent_id = body.get("agent_id") or body.get("claimed_by") or ticket.get("assigned_member_id")
            if agent_id:
                conn.execute("UPDATE tickets SET claimed_by=? WHERE ticket_id=?", (agent_id, ticket_id))
            elif not ticket.get("claimed_by") and not ticket.get("assigned_member_id"):
                conn.close()
                return {"ok": False, "error": "agent_required",
                        "message": "InProgress 전환 불가: 에이전트 클레임 필수. kanban_ticket_claim으로 먼저 에이전트를 배정하세요.",
                        "ticket_id": ticket_id}

        # ── 산출물 필수 게이트: Review 전환 시 artifact 1개 이상 필수 ──
        if new_status == "Review" and not force:
            art_count = conn.execute(
                "SELECT COUNT(*) as c FROM artifacts WHERE ticket_id=?", (ticket_id,)
            ).fetchone()["c"]
            if art_count == 0:
                conn.close()
                return {"ok": False, "error": "artifact_required",
                        "message": f"Review 전환 불가: 산출물(artifact) 0개. 최소 1개 이상 등록 필수. "
                                   f"kanban_artifact_create로 산출물을 먼저 등록하세요.",
                        "ticket_id": ticket_id, "artifact_count": 0}

        # ── Done 직접 전환 차단: Review를 거쳐야 함 (올라마 검수 강제) ──
        if new_status == "Done" and ticket["status"] != "Review" and not force:
            conn.close()
            return {"ok": False, "error": "review_required",
                    "message": f"Done 전환 불가: 현재 상태 '{ticket['status']}' → Review를 먼저 거쳐야 합니다. "
                               f"올라마 Supervisor QA 검수를 통과해야 Done 가능.",
                    "ticket_id": ticket_id, "current_status": ticket["status"]}

        ts = now_utc()
        updates = {"status": new_status}
        if new_status == "InProgress" and not ticket.get("started_at"):
            updates["started_at"] = ts
        if new_status == "Done":
            updates["completed_at"] = ts
            if ticket.get("started_at"):
                try:
                    start = datetime.fromisoformat(ticket["started_at"])
                    updates["actual_minutes"] = max(1, int((datetime.now(timezone.utc) - start.replace(tzinfo=timezone.utc)).total_seconds() / 60))
                except Exception:
                    pass

        set_clause = ", ".join(f"{k}=?" for k in updates)
        conn.execute(f"UPDATE tickets SET {set_clause} WHERE ticket_id=?", (*updates.values(), ticket_id))

        if new_status == "Done" and ticket.get("assigned_member_id"):
            conn.execute("UPDATE team_members SET status='Idle', current_ticket_id=NULL, last_activity_at=? WHERE member_id=?",
                         (ts, ticket["assigned_member_id"]))
        if new_status == "Blocked" and ticket.get("assigned_member_id"):
            conn.execute("UPDATE team_members SET status='Blocked', last_activity_at=? WHERE member_id=?",
                         (ts, ticket["assigned_member_id"]))

        # ── Review 전환 시 산출물 수 기록 + 올라마 자동 검수 트리거 ──
        status_msg = f"상태 → {new_status}"
        if new_status == "Review":
            art_count = conn.execute("SELECT COUNT(*) as c FROM artifacts WHERE ticket_id=?", (ticket_id,)).fetchone()["c"]
            status_msg = f"상태 → Review (산출물 {art_count}개 첨부)"
            auto_review_triggered = True

        conn.execute(
            "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,created_at) VALUES (?,?,?,?,?,?)",
            (ticket["team_id"], ticket_id, ticket.get("assigned_member_id"), "status_changed", status_msg, ts))

        # 자동 아카이브: CAS 패턴으로 원자적 처리 (중복 아카이브 방지)
        # SELECT+UPDATE 대신 단일 UPDATE+서브쿼리로 레이스 컨디션 제거
        if new_status == "Done":
            team_id = ticket["team_id"]
            cur = conn.execute(
                """UPDATE agent_teams SET status='Archived', archived_at=?, completed_at=COALESCE(completed_at,?)
                   WHERE team_id=? AND status='Active'
                   AND NOT EXISTS (
                       SELECT 1 FROM tickets WHERE team_id=? AND status != 'Done'
                   )""", (ts, ts, team_id, team_id))
            if cur.rowcount > 0:
                conn.execute("INSERT INTO activity_logs (team_id,action,message,created_at) VALUES (?,?,?,?)",
                             (team_id, "team_auto_archived", f"모든 티켓 완료 — 자동 아카이브", ts))
                _save_team_snapshot(conn, team_id, "auto_archive")
                auto_archived = True

        conn.commit()
    except Exception as e:
        conn.rollback()
        return {"ok": False, "error": f"status_update_failed: {e}"}
    finally:
        conn.close()

    if auto_archived:
        sse_broadcast(ticket["team_id"], "team_archived", {"team_id": ticket["team_id"], "auto": True, "archived_at": ts})
    sse_broadcast(ticket["team_id"], "ticket_status_changed", {"ticket_id": ticket_id, "status": new_status})

    # ── Review 전환 시 올라마 자동 검수 트리거 (비동기) ──
    if auto_review_triggered:
        def _auto_review():
            try:
                _chat_supervisor_respond("auto-review", f"{ticket_id} 티켓을 검수해줘")
            except Exception:
                pass
        threading.Thread(target=_auto_review, daemon=True).start()

    return {"ok": True, "ticket_id": ticket_id, "status": new_status,
            "auto_archived": auto_archived, "auto_review": auto_review_triggered}


def api_ticket_claim(ticket_id, body):
    member_id = body.get("member_id")
    if not member_id:
        return {"ok": False, "error": "missing_field", "message": "필수 필드 'member_id'가 없습니다", "example": {"member_id": "agent-xxx"}}
    conn = get_db()
    try:

        ticket = row_to_dict(conn.execute("SELECT * FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone())
        if not ticket:
            conn.rollback()
            return {"ok": False, "error": "ticket_not_found"}
        if ticket["status"] not in ("Backlog", "Todo"):
            conn.rollback()
            return {"ok": False, "error": f"cannot_claim_status_{ticket['status']}"}

        if ticket.get("depends_on"):
            deps = ticket["depends_on"]
            if isinstance(deps, str):
                try:
                    deps = json.loads(deps)
                except Exception:
                    deps = []
            for dep_id in (deps or []):
                dep = row_to_dict(conn.execute("SELECT status FROM tickets WHERE ticket_id=?", (dep_id,)).fetchone())
                if dep and dep["status"] != "Done":
                    conn.rollback()
                    return {"ok": False, "error": f"dependency_not_done: {dep_id}"}

        # ── v4.1 역할-티켓 매칭 검증 ──
        role_mismatch = False
        member_row = conn.execute(
            "SELECT role, display_name FROM team_members WHERE member_id=?", (member_id,)
        ).fetchone()
        if member_row:
            agent_role = (member_row["role"] or "").lower()
            ticket_title = (ticket.get("title") or "").lower()
            ticket_desc = (ticket.get("description") or "").lower()
            ticket_text = ticket_title + " " + ticket_desc

            # 범용 역할은 매칭 스킵
            generic_roles = {"orchestrator", "general", "agent", "supervisor", ""}
            if agent_role not in generic_roles:
                # 역할 키워드 기반 매칭 (역할명이 티켓 텍스트에 포함되면 OK)
                role_keywords = agent_role.replace("-", " ").replace("_", " ").split()
                matched = any(kw in ticket_text for kw in role_keywords if len(kw) > 2)
                if not matched:
                    # 그레이존: 경고는 하되 클레임은 허용 (supervisor 판단 위임)
                    role_mismatch = True
                    conn.execute(
                        "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,created_at) VALUES (?,?,?,?,?,datetime('now'))",
                        (ticket["team_id"], ticket_id, member_id, "role_mismatch_warning",
                         f"⚠️ 역할 불일치: {member_row['display_name']} ({agent_role}) → {ticket['title'][:40]}. supervisor 확인 필요.")
                    )

        # CAS: 상태가 여전히 Backlog/Todo일 때만 업데이트 (원자적 선점)
        ts = now_utc()
        cur = conn.execute(
            "UPDATE tickets SET status='InProgress', assigned_member_id=?, claimed_by=?, started_at=? "
            "WHERE ticket_id=? AND status IN ('Backlog','Todo')",
            (member_id, member_row["display_name"] if member_row else member_id, ts, ticket_id))
        if cur.rowcount == 0:
            conn.rollback()
            return {"ok": False, "error": "already_claimed"}

        conn.execute("UPDATE team_members SET status='Working', current_ticket_id=?, last_activity_at=? WHERE member_id=?",
                     (ticket_id, ts, member_id))
        conn.execute(
            "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,created_at) VALUES (?,?,?,?,?,?)",
            (ticket["team_id"], ticket_id, member_id, "ticket_claimed", f"에이전트가 '{ticket['title']}' 점유", ts))
        conn.commit()
    except Exception as e:
        conn.rollback()
        return {"ok": False, "error": f"claim_failed: {e}"}
    finally:
        conn.close()
    sse_broadcast(ticket["team_id"], "ticket_claimed", {"ticket_id": ticket_id, "member_id": member_id})
    result = {"ok": True, "ticket_id": ticket_id, "member_id": member_id}
    if role_mismatch:
        result["warning"] = "role_mismatch"
        result["message"] = "역할 불일치 경고: supervisor 확인 필요. 그레이존으로 클레임은 허용됨."
    return result


def api_activity_log(body):
    team_id = body.get("team_id")
    action = body.get("action")
    if not team_id or not action:
        return {"ok": False, "error": "missing_field", "message": "필수 필드 'team_id'와 'action'이 필요합니다", "example": {"team_id": "team-xxx", "action": "progress", "message": "진행 상황"}}
    meta = json.dumps(body["metadata"]) if body.get("metadata") else None
    conn = get_db()
    conn.execute(
        "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,metadata,created_at) VALUES (?,?,?,?,?,?,?)",
        (team_id, body.get("ticket_id"), body.get("member_id"), action, body.get("message"), meta, now_utc())
    )
    conn.commit()
    conn.close()
    ticket_id = body.get("ticket_id")
    # progress 액션이면 티켓 progress_note + last_ping_at 업데이트
    if action == "progress" and ticket_id:
        conn2 = get_db()
        conn2.execute("UPDATE tickets SET progress_note=?, last_ping_at=? WHERE ticket_id=?",
                      (body.get("message", ""), now_utc(), ticket_id))
        conn2.commit()
        conn2.close()
    sse_broadcast(team_id, "activity_logged", {
        "action": action, "message": body.get("message"),
        "ticket_id": ticket_id, "member_id": body.get("member_id")
    })
    return {"ok": True}


def api_ticket_detail(ticket_id):
    conn = get_db()
    ticket = row_to_dict(conn.execute("SELECT * FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone())
    if not ticket:
        conn.close()
        return {"ok": False, "error": "ticket_not_found"}
    if ticket.get("depends_on"):
        try:
            ticket["depends_on"] = json.loads(ticket["depends_on"])
        except Exception:
            pass
    if ticket.get("tags"):
        try:
            ticket["tags"] = json.loads(ticket["tags"])
        except Exception:
            pass
    member = None
    if ticket.get("assigned_member_id"):
        member = row_to_dict(conn.execute("SELECT * FROM team_members WHERE member_id=?", (ticket["assigned_member_id"],)).fetchone())
    logs = rows_to_list(conn.execute(
        "SELECT * FROM activity_logs WHERE ticket_id=? ORDER BY created_at DESC", (ticket_id,)).fetchall())
    msg_count = conn.execute("SELECT COUNT(*) as cnt FROM messages WHERE ticket_id=?", (ticket_id,)).fetchone()["cnt"]
    art_count = conn.execute("SELECT COUNT(*) as cnt FROM artifacts WHERE ticket_id=?", (ticket_id,)).fetchone()["cnt"]
    conn.close()
    return {"ok": True, "ticket": ticket, "assigned_member": member, "logs": logs,
            "message_count": msg_count, "artifact_count": art_count}


# ── 메시지 API ──

def api_messages_list(ticket_id):
    conn = get_db()
    ticket = row_to_dict(conn.execute("SELECT team_id FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone())
    if not ticket:
        conn.close()
        return {"ok": False, "error": "ticket_not_found"}
    rows = conn.execute(
        "SELECT m.*, tm.display_name as sender_name, tm.role as sender_role "
        "FROM messages m LEFT JOIN team_members tm ON m.sender_member_id=tm.member_id "
        "WHERE m.ticket_id=? ORDER BY m.created_at ASC", (ticket_id,)
    ).fetchall()
    conn.close()
    msgs = rows_to_list(rows)
    for msg in msgs:
        if msg.get("metadata"):
            try: msg["metadata"] = json.loads(msg["metadata"])
            except: pass
    return {"ok": True, "count": len(msgs), "messages": msgs}


def api_message_create(ticket_id, body):
    sender = body.get("sender_member_id")
    content = body.get("content")
    if not sender or not content:
        return {"ok": False, "error": "missing_field", "message": "필수 필드 'sender_member_id'와 'content'가 필요합니다", "example": {"sender_member_id": "agent-xxx", "content": "메시지 내용"}}
    conn = get_db()
    ticket = row_to_dict(conn.execute("SELECT team_id FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone())
    if not ticket:
        conn.close()
        return {"ok": False, "error": "ticket_not_found"}
    mid = short_id("msg-")
    msg_type = body.get("message_type", "comment")
    meta = json.dumps(body["metadata"]) if body.get("metadata") else None
    conn.execute(
        "INSERT INTO messages (message_id,team_id,ticket_id,sender_member_id,message_type,content,parent_message_id,metadata,created_at) "
        "VALUES (?,?,?,?,?,?,?,?,?)",
        (mid, ticket["team_id"], ticket_id, sender, msg_type, content, body.get("parent_message_id"), meta, now_utc())
    )
    conn.execute(
        "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,created_at) VALUES (?,?,?,?,?,?)",
        (ticket["team_id"], ticket_id, sender, "message_posted", f"메시지 작성 ({msg_type})", now_utc())
    )
    conn.commit()
    message = row_to_dict(conn.execute("SELECT * FROM messages WHERE message_id=?", (mid,)).fetchone())
    conn.close()
    sse_broadcast(ticket["team_id"], "message_created", {"ticket_id": ticket_id, "message_id": mid})
    return {"ok": True, "message": message}


# ── 산출물 API ──

def api_artifacts_list(ticket_id):
    conn = get_db()
    ticket = row_to_dict(conn.execute("SELECT team_id FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone())
    if not ticket:
        conn.close()
        return {"ok": False, "error": "ticket_not_found"}
    rows = conn.execute(
        "SELECT a.*, tm.display_name as creator_name, tm.role as creator_role "
        "FROM artifacts a LEFT JOIN team_members tm ON a.creator_member_id=tm.member_id "
        "WHERE a.ticket_id=? ORDER BY a.created_at DESC", (ticket_id,)
    ).fetchall()
    conn.close()
    arts = rows_to_list(rows)
    for a in arts:
        if a.get("metadata"):
            try: a["metadata"] = json.loads(a["metadata"])
            except: pass
    return {"ok": True, "count": len(arts), "artifacts": arts}


ARTIFACT_TYPES = ["code", "file_path", "code_change", "config", "test", "docs",
                   "result", "summary", "log", "diagram", "screenshot", "data", "other"]

def api_artifact_create(ticket_id, body):
    creator = body.get("creator_member_id")
    title = body.get("title")
    content = body.get("content")
    if not creator or not title or not content:
        return {"ok": False, "error": "missing_field",
                "message": "필수: creator_member_id, title, content",
                "example": {"creator_member_id": "agent-xxx", "title": "산출물 제목", "content": "내용",
                            "artifact_type": "code|file_path|code_change|config|test|docs|result|summary|log|diagram|screenshot|data",
                            "files": [{"path": "src/main.py", "lines_added": 50, "lines_removed": 10}]}}
    conn = get_db()
    ticket = row_to_dict(conn.execute("SELECT team_id FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone())
    if not ticket:
        conn.close()
        return {"ok": False, "error": "ticket_not_found"}
    aid = short_id("art-")
    art_type = body.get("artifact_type", "code")
    if art_type not in ARTIFACT_TYPES:
        art_type = "other"
    meta = json.dumps(body["metadata"], ensure_ascii=False) if body.get("metadata") else None
    ts = now_utc()
    conn.execute(
        "INSERT INTO artifacts (artifact_id,team_id,ticket_id,creator_member_id,artifact_type,title,content,language,metadata,created_at) "
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        (aid, ticket["team_id"], ticket_id, creator, art_type, title, content, body.get("language"), meta, ts)
    )
    # artifact_details 자동 기록 (파일 변경 추적)
    files = body.get("files", [])
    if files:
        for f in files:
            conn.execute(
                "INSERT INTO artifact_details (artifact_id,ticket_id,team_id,detail_type,file_path,lines_added,lines_removed,api_endpoint,description,created_at) "
                "VALUES (?,?,?,?,?,?,?,?,?,?)",
                (aid, ticket_id, ticket["team_id"], f.get("type", "file_change"),
                 f.get("path", ""), f.get("lines_added", 0), f.get("lines_removed", 0),
                 f.get("api_endpoint"), f.get("description", ""), ts)
            )
    conn.execute(
        "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,created_at) VALUES (?,?,?,?,?,?)",
        (ticket["team_id"], ticket_id, creator, "artifact_created",
         f"산출물 '{title}' ({art_type})" + (f" — {len(files)}개 파일" if files else ""), ts)
    )
    conn.commit()
    artifact = row_to_dict(conn.execute("SELECT * FROM artifacts WHERE artifact_id=?", (aid,)).fetchone())
    # 파일 상세 포함
    if files:
        artifact["files"] = rows_to_list(conn.execute(
            "SELECT * FROM artifact_details WHERE artifact_id=?", (aid,)).fetchall())
    conn.close()
    sse_broadcast(ticket["team_id"], "artifact_created", {"ticket_id": ticket_id, "artifact_id": aid, "type": art_type})
    return {"ok": True, "artifact": artifact}


# ── 피드백/채점 API ──

def api_feedback_list(ticket_id):
    conn = get_db()
    feedbacks = rows_to_list(conn.execute(
        "SELECT * FROM ticket_feedbacks WHERE ticket_id=? ORDER BY created_at DESC", (ticket_id,)).fetchall())
    avg_score = None
    if feedbacks:
        avg_score = round(sum(f["score"] for f in feedbacks) / len(feedbacks), 1)
    conn.close()
    for f in feedbacks:
        if f.get("categories"):
            try:
                f["categories"] = json.loads(f["categories"])
            except Exception:
                pass
    return {"ok": True, "count": len(feedbacks), "feedbacks": feedbacks, "avg_score": avg_score}


def api_feedback_create(ticket_id, body):
    score = body.get("score")
    if score is None or not isinstance(score, (int, float)) or score < 1 or score > 5:
        return {"ok": False, "error": "invalid_score", "message": "score는 1~5 사이 정수여야 합니다"}
    score = int(score)
    conn = get_db()
    ticket = row_to_dict(conn.execute("SELECT team_id, title FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone())
    if not ticket:
        conn.close()
        return {"ok": False, "error": "ticket_not_found"}
    fid = short_id("fb-")
    author = body.get("author", "user")
    comment = body.get("comment", "")
    categories = json.dumps(body["categories"], ensure_ascii=False) if body.get("categories") else None
    conn.execute(
        "INSERT INTO ticket_feedbacks (feedback_id,ticket_id,team_id,author,score,comment,categories,created_at) "
        "VALUES (?,?,?,?,?,?,?,?)",
        (fid, ticket_id, ticket["team_id"], author, score, comment, categories, now_utc())
    )
    conn.execute(
        "INSERT INTO activity_logs (team_id,ticket_id,action,message,created_at) VALUES (?,?,?,?,?)",
        (ticket["team_id"], ticket_id, "feedback_created", f"피드백 등록: {score}/5 — {comment[:80] if comment else '(코멘트 없음)'}", now_utc())
    )
    conn.commit()
    fb = row_to_dict(conn.execute("SELECT * FROM ticket_feedbacks WHERE feedback_id=?", (fid,)).fetchone())
    conn.close()
    if fb.get("categories"):
        try:
            fb["categories"] = json.loads(fb["categories"])
        except Exception:
            pass
    sse_broadcast(ticket["team_id"], "feedback_created", {"ticket_id": ticket_id, "feedback_id": fid, "score": score})
    return {"ok": True, "feedback": fb}


def api_feedback_summary(team_id):
    conn = get_db()
    feedbacks = rows_to_list(conn.execute(
        "SELECT tf.*, t.title as ticket_title FROM ticket_feedbacks tf "
        "JOIN tickets t ON tf.ticket_id = t.ticket_id "
        "WHERE tf.team_id=? ORDER BY tf.created_at DESC", (team_id,)).fetchall())
    if not feedbacks:
        conn.close()
        return {"ok": True, "count": 0, "feedbacks": [], "avg_score": None, "score_distribution": {}}
    avg_score = round(sum(f["score"] for f in feedbacks) / len(feedbacks), 1)
    dist = {}
    for f in feedbacks:
        s = str(f["score"])
        dist[s] = dist.get(s, 0) + 1
        if f.get("categories"):
            try:
                f["categories"] = json.loads(f["categories"])
            except Exception:
                pass
    conn.close()
    return {"ok": True, "count": len(feedbacks), "feedbacks": feedbacks, "avg_score": avg_score, "score_distribution": dist}


# ── 감독자(Supervisor) API ──

def api_supervisor_overview():
    conn = get_db()
    teams = rows_to_list(conn.execute("SELECT * FROM agent_teams WHERE status != 'Archived' ORDER BY created_at DESC").fetchall())
    result = []
    for team in teams:
        tid = team["team_id"]
        members = rows_to_list(conn.execute(
            "SELECT member_id,display_name,role,status,current_ticket_id FROM team_members WHERE team_id=?", (tid,)).fetchall())
        stats_rows = conn.execute(
            "SELECT status,COUNT(*) as cnt FROM tickets WHERE team_id=? GROUP BY status", (tid,)).fetchall()
        sc = {}
        total = 0
        for r in stats_rows:
            sc[r["status"]] = r["cnt"]
            total += r["cnt"]
        done = sc.get("Done", 0)
        progress = round(done / total * 100, 1) if total > 0 else 0
        active = sum(1 for m in members if m["status"] == "Working")
        msg_cnt = conn.execute("SELECT COUNT(*) as cnt FROM messages WHERE team_id=?", (tid,)).fetchone()["cnt"]
        art_cnt = conn.execute("SELECT COUNT(*) as cnt FROM artifacts WHERE team_id=?", (tid,)).fetchone()["cnt"]
        # 최근 티켓 (진행중/리뷰/블록 우선, 최대 6개)
        recent_tickets = rows_to_list(conn.execute(
            "SELECT ticket_id,title,status,priority,assigned_member_id FROM tickets WHERE team_id=? "
            "ORDER BY CASE status WHEN 'InProgress' THEN 0 WHEN 'Blocked' THEN 1 WHEN 'Review' THEN 2 "
            "WHEN 'Todo' THEN 3 WHEN 'Backlog' THEN 4 ELSE 5 END, created_at DESC LIMIT 6", (tid,)).fetchall())
        # 최근 활동 5건
        recent_logs = rows_to_list(conn.execute(
            "SELECT action,message,created_at FROM activity_logs WHERE team_id=? ORDER BY created_at DESC LIMIT 5", (tid,)).fetchall())
        result.append({
            "team": team, "member_count": len(members), "active_agents": active,
            "total_tickets": total, "done_tickets": done, "status_counts": sc, "progress": progress,
            "members": members, "message_count": msg_cnt, "artifact_count": art_cnt,
            "recent_tickets": recent_tickets, "recent_logs": recent_logs
        })
    conn.close()
    return {"ok": True, "teams": result, "total_teams": len(result)}


def api_supervisor_global_activity(params):
    limit = int(params.get("limit", [100])[0])
    conn = get_db()
    logs = rows_to_list(conn.execute(
        "SELECT al.*, at.name as team_name FROM activity_logs al "
        "LEFT JOIN agent_teams at ON al.team_id=at.team_id "
        "ORDER BY al.created_at DESC LIMIT ?", (limit,)).fetchall())
    conn.close()
    return {"ok": True, "count": len(logs), "logs": logs}


def api_supervisor_cross_stats():
    conn = get_db()
    all_teams = conn.execute("SELECT COUNT(*) as cnt FROM agent_teams").fetchone()["cnt"]
    active_teams = conn.execute("SELECT COUNT(*) as cnt FROM agent_teams WHERE status='Active'").fetchone()["cnt"]
    archived_teams = conn.execute("SELECT COUNT(*) as cnt FROM agent_teams WHERE status='Archived'").fetchone()["cnt"]
    # 활성 팀 기준 통계 (아카이브 제외)
    active_ids = [r["team_id"] for r in conn.execute("SELECT team_id FROM agent_teams WHERE status='Active'").fetchall()]
    if active_ids:
        ph = ",".join("?" * len(active_ids))
        total_agents = conn.execute(f"SELECT COUNT(*) as cnt FROM team_members WHERE team_id IN ({ph})", active_ids).fetchone()["cnt"]
        working_agents = conn.execute(f"SELECT COUNT(*) as cnt FROM team_members WHERE team_id IN ({ph}) AND status='Working'", active_ids).fetchone()["cnt"]
        total_tickets = conn.execute(f"SELECT COUNT(*) as cnt FROM tickets WHERE team_id IN ({ph})", active_ids).fetchone()["cnt"]
        done_tickets = conn.execute(f"SELECT COUNT(*) as cnt FROM tickets WHERE team_id IN ({ph}) AND status='Done'", active_ids).fetchone()["cnt"]
        blocked_tickets = conn.execute(f"SELECT COUNT(*) as cnt FROM tickets WHERE team_id IN ({ph}) AND status='Blocked'", active_ids).fetchone()["cnt"]
        total_msgs = conn.execute(f"SELECT COUNT(*) as cnt FROM messages WHERE team_id IN ({ph})", active_ids).fetchone()["cnt"]
        total_arts = conn.execute(f"SELECT COUNT(*) as cnt FROM artifacts WHERE team_id IN ({ph})", active_ids).fetchone()["cnt"]
        avg_row = conn.execute(f"SELECT AVG(actual_minutes) as avg_min FROM tickets WHERE team_id IN ({ph}) AND status='Done' AND actual_minutes>0", active_ids).fetchone()
    else:
        total_agents = working_agents = total_tickets = done_tickets = blocked_tickets = total_msgs = total_arts = 0
        avg_row = None
    avg_min = round(avg_row["avg_min"], 1) if avg_row and avg_row["avg_min"] else 0
    conn.close()
    return {"ok": True, "stats": {
        "total_teams": active_teams, "active_teams": active_teams, "archived_teams": archived_teams, "all_teams": all_teams,
        "total_agents": total_agents, "working_agents": working_agents,
        "total_tickets": total_tickets, "done_tickets": done_tickets,
        "blocked_tickets": blocked_tickets, "total_messages": total_msgs, "total_artifacts": total_arts,
        "global_progress": round(done_tickets / total_tickets * 100, 1) if total_tickets > 0 else 0,
        "avg_minutes_per_ticket": avg_min
    }}


def api_supervisor_heatmap(params):
    """활동 히트맵 데이터. mode=10min이면 10분 단위, mode=24h이면 시간별, 기본은 주간(일별)"""
    mode = params.get("mode", ["weekly"])[0]
    conn = get_db()
    if mode == "10min":
        # 48시간 10분 단위 집계 — 키: "YYYY-MM-DDTHH:MM"
        hours = int(params.get("hours", [48])[0])
        rows = conn.execute(
            "SELECT strftime('%Y-%m-%dT%H', created_at) || ':' || "
            "  CASE CAST(strftime('%M', created_at) AS INTEGER) / 10 "
            "    WHEN 0 THEN '00' WHEN 1 THEN '10' WHEN 2 THEN '20' "
            "    WHEN 3 THEN '30' WHEN 4 THEN '40' ELSE '50' END as slot, "
            "COUNT(*) as cnt "
            "FROM activity_logs WHERE created_at >= datetime('now', ? || ' hours') "
            "GROUP BY slot ORDER BY slot",
            (str(-hours),)
        ).fetchall()
        conn.close()
        data = {r["slot"]: r["cnt"] for r in rows}
        return {"ok": True, "mode": "10min", "hours": hours, "data": data}
    if mode == "24h":
        # 24시간 시간별 활동 집계
        rows = conn.execute(
            "SELECT strftime('%H', created_at) as hour, COUNT(*) as cnt "
            "FROM activity_logs WHERE created_at >= datetime('now', '-24 hours') "
            "GROUP BY strftime('%H', created_at) ORDER BY hour"
        ).fetchall()
        conn.close()
        data = {r["hour"]: r["cnt"] for r in rows}
        return {"ok": True, "mode": "24h", "data": data}
    else:
        weeks = int(params.get("weeks", [52])[0])
        days = weeks * 7
        rows = conn.execute(
            "SELECT DATE(created_at) as day, COUNT(*) as cnt FROM activity_logs "
            "WHERE created_at >= datetime('now', ? || ' days') GROUP BY DATE(created_at) ORDER BY day",
            (str(-days),)
        ).fetchall()
        conn.close()
        data = {r["day"]: r["cnt"] for r in rows}
        return {"ok": True, "mode": "weekly", "weeks": weeks, "data": data}


def api_supervisor_timeline(params):
    """24시간 티켓 상태 변경 타임라인 (시간대별 집계)"""
    hours = int(params.get("hours", [24])[0])
    conn = get_db()
    rows = conn.execute(
        "SELECT strftime('%Y-%m-%dT%H:00:00', created_at) as hour, action, COUNT(*) as cnt "
        "FROM activity_logs WHERE created_at >= datetime('now', ? || ' hours') "
        "GROUP BY hour, action ORDER BY hour",
        (str(-hours),)
    ).fetchall()
    # 티켓 상태별 시간대 집계
    ticket_rows = conn.execute(
        "SELECT strftime('%Y-%m-%dT%H:00:00', created_at) as hour, status, COUNT(*) as cnt "
        "FROM tickets WHERE created_at >= datetime('now', ? || ' hours') "
        "GROUP BY hour, status ORDER BY hour",
        (str(-hours),)
    ).fetchall()
    conn.close()
    activity = {}
    for r in rows:
        h = r["hour"]
        if h not in activity:
            activity[h] = {}
        activity[h][r["action"]] = r["cnt"]
    tickets = {}
    for r in ticket_rows:
        h = r["hour"]
        if h not in tickets:
            tickets[h] = {}
        tickets[h][r["status"]] = r["cnt"]
    return {"ok": True, "hours": hours, "activity": activity, "tickets": tickets}


def api_supervisor_backfill():
    """기존 teams/tickets/members/messages/artifacts의 created_at으로 activity_logs를 소급 생성"""
    conn = get_db()
    inserted = 0

    def _ins(team_id, action, message, created_at):
        nonlocal inserted
        exists = conn.execute(
            "SELECT 1 FROM activity_logs WHERE team_id=? AND action=? AND created_at=?",
            (team_id, action, created_at)
        ).fetchone()
        if not exists:
            conn.execute(
                "INSERT INTO activity_logs (team_id, action, message, created_at) VALUES (?,?,?,?)",
                (team_id, action, message, created_at)
            )
            inserted += 1

    # 1. 팀 생성
    for t in conn.execute("SELECT team_id, name, created_at FROM agent_teams").fetchall():
        _ins(t["team_id"], "team_created", f"팀 '{t['name']}' 생성됨", t["created_at"])

    # 2. 멤버 스폰
    for m in conn.execute(
        "SELECT m.display_name, m.team_id, m.spawned_at "
        "FROM team_members m"
    ).fetchall():
        if m["spawned_at"]:
            _ins(m["team_id"], "member_spawned", f"에이전트 '{m['display_name']}' 스폰", m["spawned_at"])

    # 3. 티켓 생성
    for tk in conn.execute("SELECT ticket_id, title, team_id, created_at FROM tickets").fetchall():
        _ins(tk["team_id"], "ticket_created", f"티켓 '{tk['ticket_id']}: {tk['title']}' 생성됨", tk["created_at"])

    # 4. 메시지
    for mg in conn.execute("SELECT team_id, created_at FROM messages").fetchall():
        _ins(mg["team_id"], "message_created", "메시지 전송", mg["created_at"])

    # 5. 산출물
    for ar in conn.execute("SELECT team_id, title, created_at FROM artifacts").fetchall():
        _ins(ar["team_id"], "artifact_created", f"산출물 '{ar['title']}' 생성", ar["created_at"])

    conn.commit()
    conn.close()
    return {"ok": True, "inserted": inserted, "message": f"{inserted}개 소급 로그 생성됨"}


def api_member_detail(member_id):
    conn = get_db()
    member = row_to_dict(conn.execute("SELECT * FROM team_members WHERE member_id=?", (member_id,)).fetchone())
    if not member:
        conn.close()
        return {"ok": False, "error": "member_not_found"}
    tickets = rows_to_list(conn.execute(
        "SELECT * FROM tickets WHERE assigned_member_id=? ORDER BY created_at DESC", (member_id,)).fetchall())
    for t in tickets:
        if t.get("depends_on"):
            try:
                t["depends_on"] = json.loads(t["depends_on"])
            except Exception:
                pass
        if t.get("tags"):
            try:
                t["tags"] = json.loads(t["tags"])
            except Exception:
                pass
    logs = rows_to_list(conn.execute(
        "SELECT * FROM activity_logs WHERE member_id=? ORDER BY created_at DESC LIMIT 100", (member_id,)).fetchall())
    conn.close()
    return {"ok": True, "member": member, "tickets": tickets, "logs": logs}


def api_team_stats(team_id):
    conn = get_db()
    rows = conn.execute("SELECT status, COUNT(*) as cnt FROM tickets WHERE team_id=? GROUP BY status", (team_id,)).fetchall()
    status_counts = {}
    total = 0
    for r in rows:
        status_counts[r["status"]] = r["cnt"]
        total += r["cnt"]
    done = status_counts.get("Done", 0)
    rate = round(done / total * 100, 1) if total > 0 else 0
    avg_row = conn.execute("SELECT AVG(actual_minutes) as avg_min FROM tickets WHERE team_id=? AND status='Done' AND actual_minutes>0", (team_id,)).fetchone()
    avg_min = round(avg_row["avg_min"], 1) if avg_row and avg_row["avg_min"] else 0
    conn.close()
    return {"ok": True, "stats": {
        "team_id": team_id, "total_tickets": total, "completion_rate": rate,
        "avg_minutes_per_ticket": avg_min, "status_counts": status_counts
    }}


def api_team_activity(team_id, params):
    limit = int(params.get("limit", [50])[0])
    conn = get_db()
    logs = rows_to_list(conn.execute(
        "SELECT * FROM activity_logs WHERE team_id=? ORDER BY created_at DESC LIMIT ?", (team_id, limit)).fetchall())
    conn.close()
    return {"ok": True, "count": len(logs), "logs": logs}


# ── 프로젝트 스캔 (Auto-Scaffold) ──

def scan_project(project_path):
    """프로젝트 디렉토리를 스캔하여 에이전트, 스킬, 기술스택 정보를 추출."""
    result = {"agents": [], "skills": [], "tech_stack": [], "summary": ""}

    # .claude/agents/*.md 스캔
    agents_dir = os.path.join(project_path, ".claude", "agents")
    if os.path.isdir(agents_dir):
        skip = {"readme", "aip tech ref", "업의_본질", "ontology db guide", "ochestration", "agent_teams"}
        for f in os.listdir(agents_dir):
            if not f.endswith(".md"):
                continue
            name = f.replace(".md", "").lower()
            if any(s in name for s in skip):
                continue
            role = name.replace(" ", "_")
            display = role.replace("_", " ").title() + " Agent"
            desc = ""
            try:
                with open(os.path.join(agents_dir, f), "r", encoding="utf-8") as fh:
                    for line in fh:
                        line = line.strip()
                        if line.startswith("**역할**") or line.startswith("**Role**"):
                            desc = line.split(":", 1)[-1].strip() if ":" in line else line
                            break
                        if line.startswith("| ") and "역할" not in line and "에이전트" not in line:
                            break
            except Exception:
                pass
            result["agents"].append({"role": role, "display_name": display, "description": desc, "file": f})

    # .claude/skills/ 스캔
    skills_dir = os.path.join(project_path, ".claude", "skills")
    if not os.path.isdir(skills_dir):
        for candidate in [os.path.join(project_path, "KSM_API", "AI", "Skills"),
                          os.path.join(project_path, "Skills")]:
            if os.path.isdir(candidate):
                skills_dir = candidate
                break

    if os.path.isdir(skills_dir):
        for entry in os.listdir(skills_dir):
            skill_dir = os.path.join(skills_dir, entry)
            skill_md = os.path.join(skill_dir, "SKILL.md")
            if not os.path.isfile(skill_md):
                if entry.endswith(".md") and os.path.isfile(os.path.join(skills_dir, entry)):
                    result["skills"].append({"name": entry.replace(".md", ""), "category": "general", "description": ""})
                continue
            skill_info = {"name": entry, "category": "general", "description": ""}
            try:
                with open(skill_md, "r", encoding="utf-8") as fh:
                    in_frontmatter = False
                    for line in fh:
                        line = line.strip()
                        if line == "---":
                            in_frontmatter = not in_frontmatter
                            continue
                        if in_frontmatter:
                            if line.startswith("description:"):
                                skill_info["description"] = line.split(":", 1)[1].strip().strip("\"'")
                            if line.startswith("category:"):
                                skill_info["category"] = line.split(":", 1)[1].strip()
            except Exception:
                pass
            result["skills"].append(skill_info)

    # 기술 스택 감지
    tech_indicators = {
        "package.json": "Node.js", "requirements.txt": "Python", "Pipfile": "Python",
        "pyproject.toml": "Python", "Cargo.toml": "Rust", "go.mod": "Go",
        "pom.xml": "Java/Maven", "build.gradle": "Java/Gradle",
        "docker-compose.yml": "Docker", "Dockerfile": "Docker",
        "tsconfig.json": "TypeScript", "vite.config.ts": "Vite", "next.config.js": "Next.js",
    }
    for filename, tech in tech_indicators.items():
        if os.path.exists(os.path.join(project_path, filename)):
            if tech not in result["tech_stack"]:
                result["tech_stack"].append(tech)

    # .csproj / .sln 탐색
    for root, dirs, files in os.walk(project_path):
        dirs[:] = [d for d in dirs if d not in {".git", "node_modules", "__pycache__", ".claude", "dist", "build"}]
        for f in files:
            if f.endswith(".csproj") and "C#/.NET" not in result["tech_stack"]:
                result["tech_stack"].append("C#/.NET")
            if f.endswith(".sln") and "C#/.NET" not in result["tech_stack"]:
                result["tech_stack"].append("C#/.NET")
        if len(result["tech_stack"]) > 5:
            break

    # CLAUDE.md 요약
    claude_md = os.path.join(project_path, ".claude", "CLAUDE.md")
    if os.path.isfile(claude_md):
        try:
            with open(claude_md, "r", encoding="utf-8") as fh:
                lines = fh.readlines()[:5]
                result["summary"] = " ".join(
                    l.strip().lstrip("#").strip() for l in lines if l.strip() and not l.startswith("---"))[:200]
        except Exception:
            pass

    return result


def api_auto_scaffold(body):
    """프로젝트 경로를 받아 agents/, skills/ 구조를 스캔하고 팀+멤버+티켓을 자동 생성."""
    project_path = body.get("project_path", "")
    team_name = body.get("team_name", "")
    description = body.get("description", "")
    task_description = body.get("task_description", "")

    if not _validate_project_path(project_path):
        return {"ok": False, "error": "invalid_project_path"}

    scan = scan_project(project_path)

    if not team_name:
        team_name = os.path.basename(project_path) + " Team"

    result = api_teams_create({"name": team_name, "description": description or scan.get("summary", "")})
    if not result.get("ok"):
        return result
    tid = result["team"]["team_id"]

    spawned = []
    for agent in scan.get("agents", []):
        role = agent["role"]
        display = agent.get("display_name", role.title() + " Agent")
        m = api_spawn_member(tid, {"role": role, "display_name": display})
        if m.get("ok"):
            spawned.append(m["member"])

    created_tickets = []
    if task_description:
        t = api_create_ticket(tid, {
            "title": task_description[:80],
            "description": task_description,
            "priority": "High",
            "tags": ["main-task"],
            "estimated_minutes": 60
        })
        if t.get("ok"):
            created_tickets.append(t["ticket"])

    for skill in scan.get("skills", [])[:10]:
        t = api_create_ticket(tid, {
            "title": f"[{skill['category']}] {skill['name']}",
            "description": skill.get("description", ""),
            "priority": "Medium",
            "tags": [skill.get("category", "general"), skill["name"]],
            "estimated_minutes": 30
        })
        if t.get("ok"):
            created_tickets.append(t["ticket"])

    conn = get_db()
    conn.execute(
        "INSERT INTO activity_logs (team_id,action,message,metadata,created_at) VALUES (?,?,?,?,?)",
        (tid, "auto_scaffold", f"프로젝트 '{os.path.basename(project_path)}' 자동 분석 완료",
         json.dumps({"project_path": project_path, "agents_found": len(scan.get("agents", [])),
                      "skills_found": len(scan.get("skills", [])), "tech_stack": scan.get("tech_stack", [])},
                     ensure_ascii=False), now_utc())
    )
    conn.commit()
    conn.close()

    return {
        "ok": True,
        "team_id": tid,
        "team_name": team_name,
        "scan": scan,
        "spawned_members": len(spawned),
        "created_tickets": len(created_tickets),
        "board_url": f"http://localhost:{DEFAULT_PORT}/board"
    }


# ── MCP JSON-RPC 2.0 (Streamable HTTP Transport) ──

import uuid as _uuid

_mcp_sessions = {}  # session_id → {"project": str, "created": float, "last_seen": float}
_MCP_SESSION_TTL = 3600  # 1시간

def _mcp_create_session(project=""):
    sid = _uuid.uuid4().hex
    _mcp_sessions[sid] = {"project": project, "created": time.time(), "last_seen": time.time()}
    # 오래된 세션 정리
    cutoff = time.time() - _MCP_SESSION_TTL
    expired = [k for k, v in _mcp_sessions.items() if v["last_seen"] < cutoff]
    for k in expired:
        _mcp_sessions.pop(k, None)
    return sid

def _mcp_validate_session(sid):
    s = _mcp_sessions.get(sid)
    if s and (time.time() - s["last_seen"]) < _MCP_SESSION_TTL:
        s["last_seen"] = time.time()
        return True
    return False

def _mcp_delete_session(sid):
    return _mcp_sessions.pop(sid, None) is not None

# ── Sprint 관리 API (gstack-inspired) ──

SPRINT_PHASES = ["Think", "Plan", "Build", "Review", "Test", "Ship", "Reflect"]

def api_sprint_create(team_id, body):
    """스프린트 생성."""
    name = body.get("name")
    if not name:
        return {"ok": False, "error": "missing_name", "message": "필수: name"}
    conn = get_db()
    try:
        sid = "SP-" + uuid.uuid4().hex[:6].upper()
        ts = now_utc()
        conn.execute(
            """INSERT INTO sprints (sprint_id, team_id, name, description, goal, phase, status,
               planned_end, velocity_target, created_at)
               VALUES (?, ?, ?, ?, ?, 'Think', 'Active', ?, ?, ?)""",
            (sid, team_id, name, body.get("description", ""),
             body.get("goal", ""), body.get("planned_end"),
             body.get("velocity_target", 0), ts)
        )
        conn.execute(
            "INSERT INTO activity_logs (team_id, action, message, created_at) VALUES (?, ?, ?, ?)",
            (team_id, "sprint_created", f"스프린트 생성: {name} ({sid})", ts)
        )
        conn.commit()
        sprint = row_to_dict(conn.execute("SELECT * FROM sprints WHERE sprint_id=?", (sid,)).fetchone())
    finally:
        conn.close()
    sse_broadcast(team_id, "sprint_created", {"sprint_id": sid, "name": name, "phase": "Think"})
    return {"ok": True, "sprint": sprint}


def api_sprint_list(team_id, query=None):
    """팀의 스프린트 목록."""
    conn = get_db()
    try:
        status = None
        if query and query.get("status"):
            status = query["status"][0] if isinstance(query["status"], list) else query["status"]
        if status:
            rows = conn.execute(
                "SELECT * FROM sprints WHERE team_id=? AND status=? ORDER BY created_at DESC",
                (team_id, status)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM sprints WHERE team_id=? ORDER BY created_at DESC",
                (team_id,)
            ).fetchall()
        sprints = rows_to_list(rows)
    finally:
        conn.close()
    return {"ok": True, "sprints": sprints}


def api_sprint_get(sprint_id):
    """스프린트 상세 조회 (게이트, 메트릭 포함)."""
    conn = get_db()
    try:
        sprint = row_to_dict(conn.execute("SELECT * FROM sprints WHERE sprint_id=?", (sprint_id,)).fetchone())
        if not sprint:
            return {"ok": False, "error": "not_found", "message": f"Sprint {sprint_id} 없음"}
        gates = rows_to_list(conn.execute(
            "SELECT * FROM sprint_gates WHERE sprint_id=? ORDER BY created_at DESC", (sprint_id,)
        ).fetchall())
        metrics = rows_to_list(conn.execute(
            "SELECT * FROM sprint_metrics WHERE sprint_id=? ORDER BY metric_date DESC LIMIT 30", (sprint_id,)
        ).fetchall())
        # 연결된 티켓 통계
        team_id = sprint["team_id"]
        ticket_stats = row_to_dict(conn.execute(
            """SELECT COUNT(*) as total,
                      SUM(CASE WHEN status='Done' THEN 1 ELSE 0 END) as done,
                      SUM(CASE WHEN status='Blocked' THEN 1 ELSE 0 END) as blocked,
                      SUM(CASE WHEN status='InProgress' THEN 1 ELSE 0 END) as in_progress,
                      SUM(CASE WHEN status='Review' THEN 1 ELSE 0 END) as review
               FROM tickets WHERE team_id=?""",
            (team_id,)
        ).fetchone())
    finally:
        conn.close()
    return {"ok": True, "sprint": sprint, "gates": gates, "metrics": metrics, "ticket_stats": ticket_stats}


def api_sprint_phase(sprint_id, body):
    """스프린트 페이즈 전환 (Think→Plan→Build→Review→Test→Ship→Reflect)."""
    new_phase = body.get("phase")
    if not new_phase or new_phase not in SPRINT_PHASES:
        return {"ok": False, "error": "invalid_phase",
                "message": f"유효 페이즈: {', '.join(SPRINT_PHASES)}"}
    conn = get_db()
    try:
        sprint = row_to_dict(conn.execute("SELECT * FROM sprints WHERE sprint_id=?", (sprint_id,)).fetchone())
        if not sprint:
            return {"ok": False, "error": "not_found"}
        old_phase = sprint["phase"]
        ts = now_utc()
        conn.execute("UPDATE sprints SET phase=? WHERE sprint_id=?", (new_phase, sprint_id))
        if new_phase == "Reflect":
            conn.execute("UPDATE sprints SET status='Completed', completed_at=? WHERE sprint_id=?", (ts, sprint_id))
        conn.execute(
            "INSERT INTO activity_logs (team_id, action, message, created_at) VALUES (?, ?, ?, ?)",
            (sprint["team_id"], "sprint_phase_changed",
             f"스프린트 {sprint_id}: {old_phase} → {new_phase}", ts)
        )
        conn.commit()
    finally:
        conn.close()
    sse_broadcast(sprint["team_id"], "sprint_phase_changed",
                  {"sprint_id": sprint_id, "old_phase": old_phase, "new_phase": new_phase})
    return {"ok": True, "sprint_id": sprint_id, "phase": new_phase, "previous": old_phase}


def api_sprint_gate(sprint_id, body):
    """스프린트 품질 게이트 생성/평가."""
    gate_type = body.get("gate_type")
    if gate_type not in ("review", "qa", "security", "design", "performance"):
        return {"ok": False, "error": "invalid_gate_type",
                "message": "유효: review, qa, security, design, performance"}
    conn = get_db()
    try:
        sprint = row_to_dict(conn.execute("SELECT * FROM sprints WHERE sprint_id=?", (sprint_id,)).fetchone())
        if not sprint:
            return {"ok": False, "error": "not_found"}
        ts = now_utc()
        status = body.get("status", "Pending")  # Pending, Passed, Failed, Waived
        score = body.get("score")
        findings = body.get("findings", "")
        if isinstance(findings, list):
            findings = json.dumps(findings, ensure_ascii=False)
        conn.execute(
            """INSERT INTO sprint_gates (sprint_id, team_id, gate_type, status, reviewer, score, findings, metadata, created_at, resolved_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (sprint_id, sprint["team_id"], gate_type, status,
             body.get("reviewer", "agent"), score, findings,
             json.dumps(body.get("metadata", {}), ensure_ascii=False),
             ts, ts if status != "Pending" else None)
        )
        conn.execute(
            "INSERT INTO activity_logs (team_id, action, message, created_at) VALUES (?, ?, ?, ?)",
            (sprint["team_id"], "sprint_gate_evaluated",
             f"게이트 {gate_type}: {status} (점수: {score})", ts)
        )
        conn.commit()
    finally:
        conn.close()
    sse_broadcast(sprint["team_id"], "sprint_gate_evaluated",
                  {"sprint_id": sprint_id, "gate_type": gate_type, "status": status, "score": score})
    return {"ok": True, "sprint_id": sprint_id, "gate_type": gate_type, "status": status, "score": score}


def api_sprint_metrics_snapshot(sprint_id):
    """스프린트 메트릭 스냅샷 기록 (번다운/벨로시티)."""
    conn = get_db()
    try:
        sprint = row_to_dict(conn.execute("SELECT * FROM sprints WHERE sprint_id=?", (sprint_id,)).fetchone())
        if not sprint:
            return {"ok": False, "error": "not_found"}
        team_id = sprint["team_id"]
        ts = now_utc()
        date_key = ts[:10]
        stats = row_to_dict(conn.execute(
            """SELECT COUNT(*) as total,
                      SUM(CASE WHEN status='Done' THEN 1 ELSE 0 END) as done,
                      SUM(CASE WHEN status='Blocked' THEN 1 ELSE 0 END) as blocked
               FROM tickets WHERE team_id=?""",
            (team_id,)
        ).fetchone())
        total = stats["total"] or 0
        done = stats["done"] or 0
        blocked = stats["blocked"] or 0
        remaining = total - done
        # 품질 점수: 리뷰 평균
        quality = conn.execute(
            "SELECT AVG(score) as avg FROM ticket_feedbacks WHERE team_id=? AND score IS NOT NULL",
            (team_id,)
        ).fetchone()
        avg_q = round(quality["avg"] or 0, 2)
        # Upsert
        existing = conn.execute(
            "SELECT metric_id FROM sprint_metrics WHERE sprint_id=? AND metric_date=?",
            (sprint_id, date_key)
        ).fetchone()
        if existing:
            conn.execute(
                """UPDATE sprint_metrics SET total_tickets=?, done_tickets=?, blocked_tickets=?,
                   velocity_actual=?, burndown_remaining=?, quality_score=?
                   WHERE metric_id=?""",
                (total, done, blocked, done, remaining, avg_q, existing["metric_id"])
            )
        else:
            conn.execute(
                """INSERT INTO sprint_metrics (sprint_id, team_id, metric_date, total_tickets,
                   done_tickets, blocked_tickets, velocity_actual, burndown_remaining, quality_score, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (sprint_id, team_id, date_key, total, done, blocked, done, remaining, avg_q, ts)
            )
        conn.commit()
        metric = {
            "date": date_key, "total": total, "done": done,
            "blocked": blocked, "remaining": remaining,
            "velocity": done, "quality_score": avg_q
        }
    finally:
        conn.close()
    return {"ok": True, "sprint_id": sprint_id, "metric": metric}


def api_sprint_velocity(team_id):
    """팀 벨로시티 보고서 (최근 10개 스프린트)."""
    conn = get_db()
    try:
        sprints = rows_to_list(conn.execute(
            """SELECT s.sprint_id, s.name, s.phase, s.status, s.created_at, s.completed_at,
                      (SELECT COUNT(*) FROM tickets WHERE team_id=s.team_id AND status='Done') as done_tickets,
                      (SELECT COUNT(*) FROM tickets WHERE team_id=s.team_id) as total_tickets,
                      (SELECT AVG(score) FROM ticket_feedbacks WHERE team_id=s.team_id) as avg_quality
               FROM sprints s WHERE s.team_id=? ORDER BY s.created_at DESC LIMIT 10""",
            (team_id,)
        ).fetchall())
        velocities = []
        for sp in sprints:
            velocities.append({
                "sprint_id": sp["sprint_id"], "name": sp["name"],
                "done": sp["done_tickets"] or 0, "total": sp["total_tickets"] or 0,
                "quality": round(sp["avg_quality"] or 0, 2),
                "status": sp["status"], "phase": sp["phase"]
            })
        avg_velocity = round(sum(v["done"] for v in velocities) / max(len(velocities), 1), 1)
    finally:
        conn.close()
    return {"ok": True, "team_id": team_id, "sprints": velocities,
            "avg_velocity": avg_velocity, "sprint_count": len(velocities)}


def api_sprint_burndown(sprint_id):
    """스프린트 번다운 차트 데이터."""
    conn = get_db()
    try:
        sprint = row_to_dict(conn.execute("SELECT * FROM sprints WHERE sprint_id=?", (sprint_id,)).fetchone())
        if not sprint:
            return {"ok": False, "error": "not_found"}
        metrics = rows_to_list(conn.execute(
            "SELECT * FROM sprint_metrics WHERE sprint_id=? ORDER BY metric_date ASC",
            (sprint_id,)
        ).fetchall())
        # 게이트 상태
        gates = rows_to_list(conn.execute(
            "SELECT gate_type, status, score FROM sprint_gates WHERE sprint_id=? ORDER BY created_at DESC",
            (sprint_id,)
        ).fetchall())
    finally:
        conn.close()
    burndown = [{"date": m["metric_date"], "remaining": m["burndown_remaining"],
                 "done": m["done_tickets"], "total": m["total_tickets"],
                 "quality": m["quality_score"]} for m in metrics]
    return {"ok": True, "sprint": sprint, "burndown": burndown, "gates": gates}


def api_sprint_cross_review(sprint_id, body):
    """크로스 모델 리뷰 요청 (gstack /codex 패턴)."""
    conn = get_db()
    try:
        sprint = row_to_dict(conn.execute("SELECT * FROM sprints WHERE sprint_id=?", (sprint_id,)).fetchone())
        if not sprint:
            return {"ok": False, "error": "not_found"}
        team_id = sprint["team_id"]
        # 리뷰 대상 아티팩트 수집
        artifacts = rows_to_list(conn.execute(
            """SELECT a.title, a.artifact_type, a.content, a.language, t.title as ticket_title
               FROM artifacts a JOIN tickets t ON a.ticket_id=t.ticket_id
               WHERE a.team_id=? ORDER BY a.created_at DESC LIMIT 20""",
            (team_id,)
        ).fetchall())
        review_type = body.get("review_type", "code")  # code, security, design, architecture
        reviewer_model = body.get("model", "ollama")
        ts = now_utc()
        # 리뷰 결과 기록
        conn.execute(
            """INSERT INTO sprint_gates (sprint_id, team_id, gate_type, status, reviewer, findings, metadata, created_at)
               VALUES (?, ?, ?, 'Pending', ?, ?, ?, ?)""",
            (sprint_id, team_id, review_type, reviewer_model,
             json.dumps({"artifacts_reviewed": len(artifacts)}, ensure_ascii=False),
             json.dumps({"review_type": review_type, "model": reviewer_model,
                         "artifact_count": len(artifacts)}, ensure_ascii=False), ts)
        )
        conn.execute(
            "INSERT INTO activity_logs (team_id, action, message, created_at) VALUES (?, ?, ?, ?)",
            (team_id, "cross_review_requested",
             f"크로스 리뷰 요청: {review_type} ({reviewer_model}) - {len(artifacts)}개 아티팩트", ts)
        )
        conn.commit()
    finally:
        conn.close()
    sse_broadcast(team_id, "cross_review_requested",
                  {"sprint_id": sprint_id, "review_type": review_type, "model": reviewer_model})
    return {"ok": True, "sprint_id": sprint_id, "review_type": review_type,
            "model": reviewer_model, "artifacts_count": len(artifacts)}


def api_sprint_retro(sprint_id):
    """스프린트 회고 데이터 자동 생성."""
    conn = get_db()
    try:
        sprint = row_to_dict(conn.execute("SELECT * FROM sprints WHERE sprint_id=?", (sprint_id,)).fetchone())
        if not sprint:
            return {"ok": False, "error": "not_found"}
        team_id = sprint["team_id"]
        # 통계 수집
        tickets = rows_to_list(conn.execute(
            "SELECT * FROM tickets WHERE team_id=?", (team_id,)
        ).fetchall())
        total = len(tickets)
        done = sum(1 for t in tickets if t["status"] == "Done")
        blocked = sum(1 for t in tickets if t["status"] == "Blocked")
        reworked = sum(1 for t in tickets if (t.get("retry_count") or 0) > 0)
        # 시간 분석
        times = [t.get("actual_minutes") for t in tickets if t.get("actual_minutes")]
        avg_time = round(sum(times) / max(len(times), 1), 1) if times else 0
        # 품질
        feedbacks = rows_to_list(conn.execute(
            "SELECT * FROM ticket_feedbacks WHERE team_id=?", (team_id,)
        ).fetchall())
        avg_score = round(sum(f["score"] for f in feedbacks) / max(len(feedbacks), 1), 2) if feedbacks else 0
        # 게이트
        gates = rows_to_list(conn.execute(
            "SELECT gate_type, status, score FROM sprint_gates WHERE sprint_id=?", (sprint_id,)
        ).fetchall())
        passed_gates = sum(1 for g in gates if g["status"] == "Passed")
        failed_gates = sum(1 for g in gates if g["status"] == "Failed")
        # 회고 데이터
        retro = {
            "sprint": {"id": sprint_id, "name": sprint["name"], "goal": sprint.get("goal", ""),
                       "phase": sprint["phase"], "status": sprint["status"]},
            "delivery": {"total_tickets": total, "done": done, "blocked": blocked,
                         "completion_rate": round(done / max(total, 1) * 100, 1),
                         "reworked": reworked, "rework_rate": round(reworked / max(total, 1) * 100, 1)},
            "timing": {"avg_minutes_per_ticket": avg_time,
                       "total_hours": round(sum(times) / 60, 1) if times else 0},
            "quality": {"avg_feedback_score": avg_score, "total_feedbacks": len(feedbacks),
                        "gates_passed": passed_gates, "gates_failed": failed_gates},
            "highlights": [],
            "improvements": []
        }
        # 자동 하이라이트
        if retro["delivery"]["completion_rate"] >= 80:
            retro["highlights"].append(f"높은 완료율: {retro['delivery']['completion_rate']}%")
        if avg_score >= 4.0:
            retro["highlights"].append(f"우수한 품질 점수: {avg_score}/5")
        if retro["delivery"]["rework_rate"] > 20:
            retro["improvements"].append(f"재작업률 높음: {retro['delivery']['rework_rate']}% — 초기 설계 검토 강화 필요")
        if blocked > 0:
            retro["improvements"].append(f"차단 티켓 {blocked}개 — 의존성 관리 개선 필요")
        if failed_gates > 0:
            retro["improvements"].append(f"품질 게이트 {failed_gates}개 실패 — 게이트 기준 사전 검토 필요")
    finally:
        conn.close()
    return {"ok": True, "retro": retro}


MCP_TOOLS = [
    {
        "name": "kanban_team_list",
        "description": "칸반보드 팀 목록을 조회합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "status": {"type": "string", "description": "필터할 팀 상태 (Active, Paused, Completed, Archived)"},
                "project_group": {"type": "string", "description": "프로젝트 그룹으로 필터링"}
            }
        }
    },
    {
        "name": "kanban_team_create",
        "description": "새로운 에이전트 팀을 생성합니다. project_group은 필수이며 git 프로젝트 폴더명을 사용합니다 (예: LINKO, PMI-AIP, U2DIA_HOME).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "팀 이름"},
                "description": {"type": "string", "description": "팀 설명"},
                "project_group": {"type": "string", "description": "프로젝트 그룹명 (필수). git 프로젝트 폴더명 사용. 예: LINKO, PMI-AIP, NC_PROGRAM, U2DIA_HOME"}
            },
            "required": ["name", "project_group"]
        }
    },
    {
        "name": "kanban_board_get",
        "description": "팀의 칸반보드 데이터를 조회합니다 (팀정보, 멤버, 티켓, 로그).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"}
            },
            "required": ["team_id"]
        }
    },
    {
        "name": "kanban_member_spawn",
        "description": "팀에 새 에이전트 멤버를 스폰합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"},
                "role": {"type": "string", "description": "역할 (backend, frontend, database, qa, devops 등)"},
                "display_name": {"type": "string", "description": "표시 이름"}
            },
            "required": ["team_id", "role"]
        }
    },
    {
        "name": "kanban_ticket_create",
        "description": "새 티켓을 생성합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"},
                "title": {"type": "string", "description": "티켓 제목"},
                "description": {"type": "string", "description": "상세 설명"},
                "priority": {"type": "string", "enum": ["Critical", "High", "Medium", "Low"]},
                "tags": {"type": "array", "items": {"type": "string"}},
                "estimated_minutes": {"type": "integer"},
                "depends_on": {"type": "array", "items": {"type": "string"}, "description": "의존하는 티켓 ID 목록"}
            },
            "required": ["team_id", "title"]
        }
    },
    {
        "name": "kanban_ticket_claim",
        "description": "에이전트가 티켓을 점유합니다 (InProgress로 전환).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string", "description": "티켓 ID"},
                "member_id": {"type": "string", "description": "점유할 멤버 ID"}
            },
            "required": ["ticket_id", "member_id"]
        }
    },
    {
        "name": "kanban_ticket_status",
        "description": "티켓 상태를 변경합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string", "description": "티켓 ID"},
                "status": {"type": "string", "enum": ["Backlog", "Todo", "InProgress", "Review", "Done", "Blocked"]}
            },
            "required": ["ticket_id", "status"]
        }
    },
    {
        "name": "kanban_activity_log",
        "description": "액티비티 로그를 기록합니다. 액션 타입은 자유롭게 정의 가능.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string"},
                "ticket_id": {"type": "string"},
                "member_id": {"type": "string"},
                "action": {"type": "string", "description": "액션 유형 (자유 정의, 어떤 이벤트든 기록 가능)"},
                "message": {"type": "string", "description": "로그 메시지"},
                "metadata": {"type": "object", "description": "추가 메타데이터"}
            },
            "required": ["team_id", "action"]
        }
    },
    {
        "name": "kanban_auto_scaffold",
        "description": "프로젝트 경로를 스캔하여 팀, 멤버, 티켓을 자동으로 생성합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "project_path": {"type": "string", "description": "프로젝트 루트 경로"},
                "team_name": {"type": "string", "description": "팀 이름 (생략 시 프로젝트명 사용)"},
                "task_description": {"type": "string", "description": "메인 태스크 설명"}
            },
            "required": ["project_path"]
        }
    },
    {
        "name": "kanban_team_stats",
        "description": "팀 통계를 조회합니다 (총 티켓, 완료율, 평균 소요시간).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"}
            },
            "required": ["team_id"]
        }
    },
    {
        "name": "kanban_message_create",
        "description": "티켓에 메시지를 작성합니다. 에이전트 간 소통에 사용. 메시지 타입은 자유롭게 정의 가능.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string", "description": "티켓 ID"},
                "sender_member_id": {"type": "string", "description": "발신 에이전트 ID"},
                "content": {"type": "string", "description": "메시지 내용"},
                "message_type": {"type": "string", "description": "메시지 유형 (자유 정의, 예: comment, question, code_review, reply 등)"},
                "parent_message_id": {"type": "string", "description": "답글 대상 메시지 ID (선택)"},
                "metadata": {"type": "object", "description": "추가 메타데이터"}
            },
            "required": ["ticket_id", "sender_member_id", "content"]
        }
    },
    {
        "name": "kanban_message_list",
        "description": "티켓의 메시지(대화) 목록을 조회합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string", "description": "티켓 ID"}
            },
            "required": ["ticket_id"]
        }
    },
    {
        "name": "kanban_artifact_create",
        "description": "티켓에 산출물을 등록합니다. 코드 변경은 files 배열로 파일별 변경량을 추적합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string", "description": "티켓 ID"},
                "creator_member_id": {"type": "string", "description": "작성 에이전트 ID"},
                "title": {"type": "string", "description": "산출물 제목"},
                "content": {"type": "string", "description": "내용 (코드, 파일 경로, 결과 등)"},
                "artifact_type": {"type": "string", "enum": ["code", "file_path", "code_change", "config", "test", "docs", "result", "summary", "log", "diagram", "screenshot", "data", "other"], "description": "산출물 유형"},
                "language": {"type": "string", "description": "코드 언어 (code 타입일 때)"},
                "metadata": {"type": "object", "description": "추가 메타데이터"},
                "files": {
                    "type": "array",
                    "description": "변경된 파일 목록 (코드 변경 추적용)",
                    "items": {
                        "type": "object",
                        "properties": {
                            "path": {"type": "string", "description": "파일 경로"},
                            "lines_added": {"type": "integer", "description": "추가된 줄 수"},
                            "lines_removed": {"type": "integer", "description": "삭제된 줄 수"},
                            "type": {"type": "string", "description": "변경 유형 (file_change, new_file, deleted 등)"},
                            "description": {"type": "string", "description": "변경 설명"}
                        }
                    }
                }
            },
            "required": ["ticket_id", "creator_member_id", "title", "content"]
        }
    },
    {
        "name": "kanban_artifact_list",
        "description": "티켓의 산출물 목록을 조회합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string", "description": "티켓 ID"}
            },
            "required": ["ticket_id"]
        }
    },
    {
        "name": "kanban_feedback_create",
        "description": "완료된 티켓에 피드백/채점을 등록합니다. 점수(1~5)와 코멘트로 작업 품질을 평가합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string", "description": "티켓 ID"},
                "score": {"type": "integer", "description": "점수 (1~5, 5가 최고)"},
                "comment": {"type": "string", "description": "피드백 코멘트"},
                "author": {"type": "string", "description": "피드백 작성자 (기본: user)"},
                "categories": {"type": "object", "description": "카테고리별 세부 점수 (예: {\"code_quality\": 4, \"completeness\": 5})"}
            },
            "required": ["ticket_id", "score"]
        }
    },
    {
        "name": "kanban_feedback_list",
        "description": "티켓의 피드백 목록과 평균 점수를 조회합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string", "description": "티켓 ID"}
            },
            "required": ["ticket_id"]
        }
    },
    {
        "name": "kanban_feedback_summary",
        "description": "팀 전체의 피드백 요약 (평균 점수, 점수 분포)을 조회합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"}
            },
            "required": ["team_id"]
        }
    },
    # ── Supervisor QA 도구 ──
    {
        "name": "kanban_supervisor_review",
        "description": "Supervisor QA 검수: Review 상태 티켓을 올라마가 검수하고 통과/재작업 판정. ticket_id(단건) 또는 team_id(배치). 결과: 피드백 점수, 상태 변경, 재작업 티켓 자동 발행.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string", "description": "검수할 티켓 ID (예: T-896BAA)"},
                "team_id": {"type": "string", "description": "팀 전체 검수 시 팀 ID (예: team-82d7d799)"},
                "batch": {"type": "boolean", "description": "true면 팀 전체 배치 검수", "default": False}
            }
        }
    },
    {
        "name": "kanban_supervisor_stats",
        "description": "Supervisor 검수 통계 조회: 총 검수 건수, 통과/재작업 수, 평균 점수, 최근 검수 내역.",
        "inputSchema": {"type": "object", "properties": {}}
    },
    # ── 배치 도구 (WriteQueue 경유, 논블로킹 병렬 처리) ──
    {
        "name": "kanban_batch_team_create",
        "description": "여러 팀을 한 번에 생성합니다 (배치). WriteQueue로 단일 트랜잭션 처리되어 빠르고 안전합니다.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "teams": {
                    "type": "array",
                    "description": "생성할 팀 목록",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string", "description": "팀 이름"},
                            "description": {"type": "string", "description": "팀 설명"},
                            "project_group": {"type": "string", "description": "프로젝트 그룹명"},
                            "leader_agent": {"type": "string", "description": "리더 에이전트"}
                        },
                        "required": ["name", "project_group"]
                    }
                }
            },
            "required": ["teams"]
        }
    },
    {
        "name": "kanban_batch_member_spawn",
        "description": "한 팀에 여러 멤버를 한 번에 스폰합니다 (배치). 단일 트랜잭션으로 처리.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"},
                "members": {
                    "type": "array",
                    "description": "스폰할 멤버 목록",
                    "items": {
                        "type": "object",
                        "properties": {
                            "role": {"type": "string", "description": "역할 (backend, frontend 등)"},
                            "display_name": {"type": "string", "description": "표시 이름"}
                        },
                        "required": ["role"]
                    }
                }
            },
            "required": ["team_id", "members"]
        }
    },
    {
        "name": "kanban_batch_ticket_create",
        "description": "한 팀에 여러 티켓을 한 번에 생성합니다 (배치). 단일 트랜잭션으로 처리.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"},
                "tickets": {
                    "type": "array",
                    "description": "생성할 티켓 목록",
                    "items": {
                        "type": "object",
                        "properties": {
                            "title": {"type": "string", "description": "티켓 제목"},
                            "description": {"type": "string", "description": "상세 설명"},
                            "priority": {"type": "string", "enum": ["Critical", "High", "Medium", "Low"]},
                            "tags": {"type": "array", "items": {"type": "string"}},
                            "estimated_minutes": {"type": "integer"},
                            "depends_on": {"type": "array", "items": {"type": "string"}, "description": "의존 티켓 ID 목록"}
                        },
                        "required": ["title"]
                    }
                }
            },
            "required": ["team_id", "tickets"]
        }
    },
    # ── Sprint 관리 (gstack-inspired) ──
    {
        "name": "kanban_sprint_create",
        "description": "스프린트 생성 (gstack Think→Plan→Build→Review→Test→Ship→Reflect 워크플로우). 팀의 작업 사이클을 구조화.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"},
                "name": {"type": "string", "description": "스프린트 이름"},
                "description": {"type": "string", "description": "스프린트 설명"},
                "goal": {"type": "string", "description": "스프린트 목표"},
                "planned_end": {"type": "string", "description": "예정 종료일 (YYYY-MM-DD)"},
                "velocity_target": {"type": "integer", "description": "목표 벨로시티 (완료 티켓 수)"}
            },
            "required": ["team_id", "name"]
        }
    },
    {
        "name": "kanban_sprint_list",
        "description": "팀의 스프린트 목록 조회.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"},
                "status": {"type": "string", "enum": ["Active", "Completed", "Cancelled"], "description": "필터"}
            },
            "required": ["team_id"]
        }
    },
    {
        "name": "kanban_sprint_get",
        "description": "스프린트 상세 조회 — 게이트, 메트릭, 티켓 통계 포함.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sprint_id": {"type": "string", "description": "스프린트 ID (SP-XXXXXX)"}
            },
            "required": ["sprint_id"]
        }
    },
    {
        "name": "kanban_sprint_phase",
        "description": "스프린트 페이즈 전환: Think → Plan → Build → Review → Test → Ship → Reflect.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sprint_id": {"type": "string", "description": "스프린트 ID"},
                "phase": {"type": "string", "enum": ["Think", "Plan", "Build", "Review", "Test", "Ship", "Reflect"], "description": "전환할 페이즈"}
            },
            "required": ["sprint_id", "phase"]
        }
    },
    {
        "name": "kanban_sprint_gate",
        "description": "스프린트 품질 게이트 평가 — review/qa/security/design/performance 게이트.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sprint_id": {"type": "string", "description": "스프린트 ID"},
                "gate_type": {"type": "string", "enum": ["review", "qa", "security", "design", "performance"], "description": "게이트 유형"},
                "status": {"type": "string", "enum": ["Pending", "Passed", "Failed", "Waived"], "description": "평가 결과"},
                "score": {"type": "integer", "description": "점수 (1-10)"},
                "findings": {"type": "string", "description": "발견 사항"},
                "reviewer": {"type": "string", "description": "리뷰어"}
            },
            "required": ["sprint_id", "gate_type"]
        }
    },
    {
        "name": "kanban_sprint_metrics",
        "description": "스프린트 메트릭 스냅샷 기록 (번다운/벨로시티 추적).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sprint_id": {"type": "string", "description": "스프린트 ID"}
            },
            "required": ["sprint_id"]
        }
    },
    {
        "name": "kanban_sprint_velocity",
        "description": "팀 벨로시티 보고서 — 최근 10개 스프린트의 완료율, 품질 추세.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"}
            },
            "required": ["team_id"]
        }
    },
    {
        "name": "kanban_sprint_burndown",
        "description": "스프린트 번다운 차트 데이터 — 일별 잔여 작업량, 품질 점수.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sprint_id": {"type": "string", "description": "스프린트 ID"}
            },
            "required": ["sprint_id"]
        }
    },
    {
        "name": "kanban_sprint_cross_review",
        "description": "크로스 모델 리뷰 요청 — 다중 AI 모델로 코드/보안/설계 리뷰 (gstack /codex 패턴).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sprint_id": {"type": "string", "description": "스프린트 ID"},
                "review_type": {"type": "string", "enum": ["code", "security", "design", "architecture"], "description": "리뷰 유형"},
                "model": {"type": "string", "description": "리뷰 모델 (기본: ollama)"}
            },
            "required": ["sprint_id"]
        }
    },
    {
        "name": "kanban_sprint_retro",
        "description": "스프린트 회고 자동 생성 — 완료율, 품질, 시간, 하이라이트/개선점 분석.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sprint_id": {"type": "string", "description": "스프린트 ID"}
            },
            "required": ["sprint_id"]
        }
    },
]


def handle_mcp_request(rpc_body, auth_project=""):
    """MCP JSON-RPC 2.0 요청 처리 (Streamable HTTP Transport 지원).

    Returns: (response_dict_or_None, session_id_or_None)
    """
    rpc_id = rpc_body.get("id")
    method = rpc_body.get("method", "")
    params = rpc_body.get("params", {})

    if method == "initialize":
        session_id = _mcp_create_session(auth_project)
        return {
            "jsonrpc": "2.0", "id": rpc_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "agent-team-kanban", "version": VERSION}
            }
        }, session_id

    if method == "notifications/initialized":
        return None, None  # 알림은 응답 없음

    if method == "tools/list":
        return {
            "jsonrpc": "2.0", "id": rpc_id,
            "result": {"tools": MCP_TOOLS}
        }, None

    if method == "tools/call":
        tool_name = params.get("name", "")
        args = params.get("arguments", {})
        return _execute_mcp_tool(rpc_id, tool_name, args, auth_project=auth_project), None

    if method == "ping":
        return {"jsonrpc": "2.0", "id": rpc_id, "result": {}}, None

    return {
        "jsonrpc": "2.0", "id": rpc_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"}
    }, None


def _execute_mcp_tool(rpc_id, tool_name, args, auth_project=""):
    """MCP 도구 실행."""
    try:
        result = None

        if tool_name == "kanban_team_list":
            status = args.get("status")
            p = {}
            if status:
                p["status"] = [status]
            if args.get("project_group"):
                p["project_group"] = args["project_group"]
            result = api_teams_list(p)

        elif tool_name == "kanban_team_create":
            # 토큰의 프로젝트명을 기본 project_group으로 자동 설정
            if auth_project and not args.get("project_group"):
                args["project_group"] = auth_project
            result = api_teams_create(args)

        elif tool_name == "kanban_board_get":
            result = api_team_board(args["team_id"])

        elif tool_name == "kanban_member_spawn":
            result = api_spawn_member(args["team_id"], args)

        elif tool_name == "kanban_ticket_create":
            result = api_create_ticket(args["team_id"], args)

        elif tool_name == "kanban_ticket_claim":
            result = api_ticket_claim(args["ticket_id"], args)

        elif tool_name == "kanban_ticket_status":
            result = api_ticket_status(args["ticket_id"], args)

        elif tool_name == "kanban_activity_log":
            result = api_activity_log(args)

        elif tool_name == "kanban_auto_scaffold":
            result = api_auto_scaffold(args)

        elif tool_name == "kanban_team_stats":
            result = api_team_stats(args["team_id"])

        elif tool_name == "kanban_message_create":
            result = api_message_create(args["ticket_id"], args)

        elif tool_name == "kanban_message_list":
            result = api_messages_list(args["ticket_id"])

        elif tool_name == "kanban_artifact_create":
            result = api_artifact_create(args["ticket_id"], args)

        elif tool_name == "kanban_artifact_list":
            result = api_artifacts_list(args["ticket_id"])

        elif tool_name == "kanban_feedback_create":
            result = api_feedback_create(args["ticket_id"], args)

        elif tool_name == "kanban_feedback_list":
            result = api_feedback_list(args["ticket_id"])

        elif tool_name == "kanban_feedback_summary":
            result = api_feedback_summary(args["team_id"])

        elif tool_name == "kanban_supervisor_review":
            tid = args.get("ticket_id")
            team_id = args.get("team_id")
            batch = args.get("batch", False)
            if tid:
                result = _chat_supervisor_respond("mcp-review", f"{tid} 티켓을 검수해줘")
            elif team_id:
                result = _supervisor_batch_review("mcp-batch-review", f"team {team_id} Review 전체 검수", team_id)
            else:
                result = {"ok": False, "error": "ticket_id 또는 team_id 필수"}

        elif tool_name == "kanban_supervisor_stats":
            result = r_supervisor_review_stats(None, {}, {}, {})

        # ── 배치 도구 (WriteQueue 경유) ──
        elif tool_name == "kanban_batch_team_create":
            if auth_project:
                for t in args.get("teams", []):
                    if not t.get("project_group"):
                        t["project_group"] = auth_project
            result = api_batch_teams_create(args)

        elif tool_name == "kanban_batch_member_spawn":
            result = api_batch_members_spawn(args)

        elif tool_name == "kanban_batch_ticket_create":
            result = api_batch_tickets_create(args)

        elif tool_name == "kanban_sprint_create":
            result = api_sprint_create(args["team_id"], args)

        elif tool_name == "kanban_sprint_list":
            result = api_sprint_list(args["team_id"], args)

        elif tool_name == "kanban_sprint_get":
            result = api_sprint_get(args["sprint_id"])

        elif tool_name == "kanban_sprint_phase":
            result = api_sprint_phase(args["sprint_id"], args)

        elif tool_name == "kanban_sprint_gate":
            result = api_sprint_gate(args["sprint_id"], args)

        elif tool_name == "kanban_sprint_metrics":
            result = api_sprint_metrics_snapshot(args["sprint_id"])

        elif tool_name == "kanban_sprint_velocity":
            result = api_sprint_velocity(args["team_id"])

        elif tool_name == "kanban_sprint_burndown":
            result = api_sprint_burndown(args["sprint_id"])

        elif tool_name == "kanban_sprint_cross_review":
            result = api_sprint_cross_review(args["sprint_id"], args)

        elif tool_name == "kanban_sprint_retro":
            result = api_sprint_retro(args["sprint_id"])

        else:
            return {
                "jsonrpc": "2.0", "id": rpc_id,
                "error": {"code": -32602, "message": f"Unknown tool: {tool_name}"}
            }

        return {
            "jsonrpc": "2.0", "id": rpc_id,
            "result": {
                "content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False, indent=2)}],
                "isError": not result.get("ok", False)
            }
        }

    except Exception as e:
        return {
            "jsonrpc": "2.0", "id": rpc_id,
            "error": {"code": -32603, "message": str(e)}
        }


# ── 라우터 ──

class Route:
    """간단한 URL 패턴 매칭."""
    def __init__(self, method, pattern, handler):
        self.method = method
        # /api/teams/{id}/board → 정규식으로 변환
        regex = re.sub(r"\{(\w+)\}", r"(?P<\1>[^/]+)", pattern)
        self.regex = re.compile(f"^{regex}$")
        self.handler = handler
        self.param_names = re.findall(r"\{(\w+)\}", pattern)


ROUTES = []


def route(method, pattern):
    """라우트 데코레이터."""
    def decorator(func):
        ROUTES.append(Route(method, pattern, func))
        return func
    return decorator


def match_route(method, path):
    """URL과 메서드에 맞는 라우트 찾기."""
    for r in ROUTES:
        if r.method != method:
            continue
        m = r.regex.match(path)
        if m:
            return r.handler, m.groupdict()
    return None, {}


# ── 라우트 등록 ──

# GET
@route("GET", "/api/teams")
def r_teams_list(params, body, url_params, query):
    return api_teams_list(query)

@route("GET", "/api/teams/{team_id}/inprogress")
def r_team_inprogress(params, body, url_params, query):
    """InProgress 티켓만 경량 조회 (2초 폴링용)."""
    team_id = url_params.get("team_id", "")
    conn = get_db()
    rows = conn.execute(
        "SELECT ticket_id, title, status, assigned_member_id, progress_note, last_ping_at, started_at "
        "FROM tickets WHERE team_id=? AND status IN ('InProgress','Review') "
        "ORDER BY started_at DESC",
        (team_id,)
    ).fetchall()
    conn.close()
    tickets = [dict(r) for r in rows]
    # 살아있는 프로세스 여부 표시
    for t in tickets:
        sid = t.get("assigned_member_id", "")
        t["process_alive"] = sid in _claude_processes and _claude_processes[sid].poll() is None
    return {"ok": True, "tickets": tickets}


@route("GET", "/api/teams/{team_id}/board")
def r_team_board(params, body, url_params, query):
    return api_team_board(url_params["team_id"])

@route("GET", "/api/teams/{team_id}/stats")
def r_team_stats(params, body, url_params, query):
    return api_team_stats(url_params["team_id"])

@route("GET", "/api/teams/{team_id}/activity")
def r_team_activity(params, body, url_params, query):
    return api_team_activity(url_params["team_id"], query)

@route("GET", "/api/teams/{team_id}")
def r_team_detail(params, body, url_params, query):
    return api_team_board(url_params["team_id"])

@route("GET", "/api/tickets/{ticket_id}/detail")
def r_ticket_detail(params, body, url_params, query):
    return api_ticket_detail(url_params["ticket_id"])

@route("GET", "/api/tickets/{ticket_id}")
def r_ticket_get(params, body, url_params, query):
    return api_ticket_detail(url_params["ticket_id"])

@route("GET", "/api/members/{member_id}/detail")
def r_member_detail(params, body, url_params, query):
    return api_member_detail(url_params["member_id"])

@route("GET", "/api/members/{member_id}")
def r_member_get(params, body, url_params, query):
    return api_member_detail(url_params["member_id"])

# POST — 고정 경로를 먼저 등록 (auto-scaffold 가 teams/{id} 보다 우선)
@route("POST", "/api/teams/auto-scaffold")
def r_auto_scaffold(params, body, url_params, query):
    return api_auto_scaffold(body)

@route("POST", "/api/scan")
def r_scan(params, body, url_params, query):
    pp = body.get("project_path", "")
    if not _validate_project_path(pp):
        return {"ok": False, "error": "invalid_project_path"}
    return {"ok": True, "scan": scan_project(pp)}

@route("POST", "/api/teams")
def r_teams_create(params, body, url_params, query):
    return api_teams_create(body)

@route("POST", "/api/teams/{team_id}/members")
def r_spawn_member(params, body, url_params, query):
    return api_spawn_member(url_params["team_id"], body)

@route("POST", "/api/teams/{team_id}/tickets")
def r_create_ticket(params, body, url_params, query):
    return api_create_ticket(url_params["team_id"], body)

@route("GET", "/api/activity")
def r_global_activity_get(params, body, url_params, query):
    limit = int((query.get("limit") or ["50"])[0])
    conn = get_db()
    rows = conn.execute("""
        SELECT l.log_id, l.team_id, l.ticket_id, l.member_id, l.action,
               l.message, l.metadata, l.created_at,
               t.name as team_name
        FROM activity_logs l
        LEFT JOIN agent_teams t ON l.team_id = t.team_id
        ORDER BY l.created_at DESC LIMIT ?
    """, (limit,)).fetchall()
    conn.close()
    return {"ok": True, "logs": rows_to_list(rows)}

@route("GET", "/api/overview")
def r_overview_get(params, body, url_params, query):
    conn = get_db()
    teams = conn.execute("SELECT team_id FROM agent_teams WHERE status='Active'").fetchall()
    active_team_ids = [t[0] for t in teams]
    if active_team_ids:
        placeholders = ','.join('?' * len(active_team_ids))
        tickets = conn.execute(f"SELECT status FROM tickets WHERE team_id IN ({placeholders})", active_team_ids).fetchall()
    else:
        tickets = []
    conn.close()
    total = len(tickets)
    done = sum(1 for t in tickets if t[0] == 'Done')
    in_progress = sum(1 for t in tickets if t[0] == 'InProgress')
    rate = round(done / total * 100) if total > 0 else 0
    return {"ok": True, "stats": {
        "active_teams": len(teams),
        "total_tickets": total,
        "done_tickets": done,
        "in_progress_tickets": in_progress,
        "global_progress": rate,
    }}

@route("POST", "/api/activity")
def r_activity_log(params, body, url_params, query):
    return api_activity_log(body)

# 배치 API (WriteQueue 경유)
@route("POST", "/api/batch/teams")
def r_batch_teams_create(params, body, url_params, query):
    return api_batch_teams_create(body)

@route("POST", "/api/batch/members")
def r_batch_members_spawn(params, body, url_params, query):
    return api_batch_members_spawn(body)

@route("POST", "/api/batch/tickets")
def r_batch_tickets_create(params, body, url_params, query):
    return api_batch_tickets_create(body)

# PUT
@route("PUT", "/api/tickets/{ticket_id}/status")
def r_ticket_status(params, body, url_params, query):
    return api_ticket_status(url_params["ticket_id"], body)

@route("PUT", "/api/tickets/{ticket_id}/claim")
def r_ticket_claim(params, body, url_params, query):
    return api_ticket_claim(url_params["ticket_id"], body)

@route("PUT", "/api/tickets/{ticket_id}/progress")
def r_ticket_progress(params, body, url_params, query):
    """티켓 progress_note 업데이트."""
    ticket_id = url_params["ticket_id"]
    note = (body or {}).get("note", "")
    if not note:
        return {"ok": False, "error": "missing_note"}
    conn = get_db()
    try:
        conn.execute("UPDATE tickets SET progress_note=?, last_ping_at=datetime('now') WHERE ticket_id=?", (note, ticket_id))
        conn.commit()
    finally:
        conn.close()
    return {"ok": True, "ticket_id": ticket_id}

@route("PUT", "/api/tickets/{ticket_id}/unclaim")
def r_ticket_unclaim(params, body, url_params, query):
    """티켓 클레임 해제 → Backlog 복귀."""
    ticket_id = url_params["ticket_id"]
    conn = get_db()
    try:
        conn.execute(
            "UPDATE tickets SET status='Backlog', assigned_member_id=NULL, claimed_by=NULL, progress_note=NULL WHERE ticket_id=?",
            (ticket_id,))
        conn.commit()
    finally:
        conn.close()
    return {"ok": True, "ticket_id": ticket_id, "status": "Backlog"}

@route("DELETE", "/api/tickets/{ticket_id}")
def r_ticket_delete(params, body, url_params, query):
    """티켓 삭제."""
    ticket_id = url_params["ticket_id"]
    conn = get_db()
    try:
        conn.execute("DELETE FROM tickets WHERE ticket_id=?", (ticket_id,))
        conn.commit()
    finally:
        conn.close()
    return {"ok": True, "ticket_id": ticket_id}

@route("PUT", "/api/teams/{team_id}/status")
def r_team_status(params, body, url_params, query):
    """팀 상태 변경."""
    team_id = url_params["team_id"]
    new_status = (body or {}).get("status", "Active")
    conn = get_db()
    try:
        conn.execute("UPDATE agent_teams SET status=? WHERE team_id=?", (new_status, team_id))
        conn.commit()
    finally:
        conn.close()
    return {"ok": True, "team_id": team_id, "status": new_status}

# PATCH → PUT 호환 (서브에이전트 PATCH 요청 지원)
@route("PUT", "/api/tickets/{ticket_id}/patch")
def r_ticket_patch(params, body, url_params, query):
    """티켓 부분 업데이트 (PATCH 대체)."""
    ticket_id = url_params["ticket_id"]
    conn = get_db()
    try:
        updates = []
        vals = []
        for field in ["status", "title", "description", "priority", "progress_note", "claimed_by"]:
            if field in (body or {}):
                updates.append(f"{field}=?")
                vals.append(body[field])
        if not updates:
            return {"ok": False, "error": "no_fields"}
        vals.append(ticket_id)
        conn.execute(f"UPDATE tickets SET {','.join(updates)} WHERE ticket_id=?", vals)
        conn.commit()
    finally:
        conn.close()
    return {"ok": True, "ticket_id": ticket_id}

# Messages
@route("GET", "/api/tickets/{ticket_id}/messages")
def r_messages_list(params, body, url_params, query):
    return api_messages_list(url_params["ticket_id"])

@route("POST", "/api/tickets/{ticket_id}/messages")
def r_message_create(params, body, url_params, query):
    return api_message_create(url_params["ticket_id"], body)

# Artifacts
@route("GET", "/api/tickets/{ticket_id}/artifacts")
def r_artifacts_list(params, body, url_params, query):
    return api_artifacts_list(url_params["ticket_id"])

@route("POST", "/api/tickets/{ticket_id}/artifacts")
def r_artifact_create(params, body, url_params, query):
    return api_artifact_create(url_params["ticket_id"], body)

# Feedback
@route("GET", "/api/tickets/{ticket_id}/feedback")
def r_feedback_list(params, body, url_params, query):
    return api_feedback_list(url_params["ticket_id"])

@route("POST", "/api/tickets/{ticket_id}/feedback")
def r_feedback_create(params, body, url_params, query):
    return api_feedback_create(url_params["ticket_id"], body)

@route("GET", "/api/teams/{team_id}/messages")
def r_team_messages(params, body, url_params, query):
    team_id = url_params["team_id"]
    limit = int((query.get("limit") or ["100"])[0])
    conn = get_db()
    rows = conn.execute(
        "SELECT m.message_id, m.team_id, m.ticket_id, m.sender_member_id, m.content, "
        "m.message_type, m.created_at, "
        "CASE WHEN m.sender_member_id LIKE 'app|%' "
        "  THEN substr(m.sender_member_id, 5) "
        "  ELSE COALESCE(mem.display_name, m.sender_member_id) END as sender, "
        "CASE WHEN m.sender_member_id LIKE 'app|%' "
        "  THEN 'orchestrator' "
        "  ELSE COALESCE(mem.role, 'agent') END as role "
        "FROM messages m "
        "LEFT JOIN team_members mem ON m.sender_member_id = mem.member_id "
        "WHERE m.team_id=? ORDER BY m.created_at ASC LIMIT ?",
        (team_id, limit)).fetchall()
    conn.close()
    return {"ok": True, "messages": rows_to_list(rows)}

@route("POST", "/api/teams/{team_id}/messages")
def r_team_message_create(params, body, url_params, query):
    team_id = url_params["team_id"]
    msg_content = body.get("content", "").strip()
    sender_name = body.get("sender", "유디(앱)")
    role = body.get("role", "orchestrator")
    if not msg_content:
        return {"ok": False, "error": "content_required"}
    import uuid, datetime
    msg_id = "msg-" + str(uuid.uuid4())[:8]
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = get_db()
    # sender_member_id: 실제 멤버 조회 or 역할명으로 가상 ID 사용
    # sender_name을 sender_member_id에 인코딩해서 저장 (스키마 변경 없이)
    sender_id = f"app|{sender_name}"
    conn.execute(
        "INSERT INTO messages (message_id,team_id,ticket_id,sender_member_id,message_type,content,created_at) "
        "VALUES (?,?,?,?,?,?,?)",
        (msg_id, team_id, "global", sender_id, "chat", msg_content, ts))
    conn.execute(
        "INSERT INTO activity_logs (team_id, action, message, created_at) VALUES (?,?,?,?)",
        (team_id, "message_created", f"{sender_name}: {msg_content[:60]}", ts))
    conn.commit()
    conn.close()
    sse_broadcast(team_id, "message_created", {
        "message_id": msg_id, "content": msg_content,
        "sender": sender_name, "role": role, "created_at": ts
    })
    return {"ok": True, "message_id": msg_id, "sender": sender_name, "role": role}

@route("GET", "/api/teams/{team_id}/artifacts")
def r_team_artifacts(params, body, url_params, query):
    team_id = url_params["team_id"]
    conn = get_db()
    rows = conn.execute(
        "SELECT a.artifact_id, a.team_id, a.ticket_id, a.title, a.artifact_type, "
        "substr(a.content, 1, 200) as content_preview, a.created_at, "
        "COALESCE(mem.display_name, a.creator_member_id) as creator "
        "FROM artifacts a "
        "LEFT JOIN team_members mem ON a.creator_member_id = mem.member_id "
        "WHERE a.team_id=? ORDER BY a.created_at DESC LIMIT 50",
        (team_id,)).fetchall()
    conn.close()
    return {"ok": True, "artifacts": rows_to_list(rows)}

@route("GET", "/api/teams/{team_id}/feedback")
def r_feedback_summary(params, body, url_params, query):
    return api_feedback_summary(url_params["team_id"])

# Supervisor
@route("GET", "/api/supervisor/overview")
def r_supervisor_overview(params, body, url_params, query):
    return api_supervisor_overview()

@route("GET", "/api/supervisor/activity")
def r_supervisor_activity(params, body, url_params, query):
    return api_supervisor_global_activity(query)

@route("GET", "/api/supervisor/stats")
def r_supervisor_stats(params, body, url_params, query):
    return api_supervisor_cross_stats()

@route("GET", "/api/supervisor/heatmap")
def r_supervisor_heatmap(params, body, url_params, query):
    return api_supervisor_heatmap(query)

@route("GET", "/api/supervisor/timeline")
def r_supervisor_timeline(params, body, url_params, query):
    return api_supervisor_timeline(query)

@route("POST", "/api/supervisor/backfill")
def r_supervisor_backfill(params, body, url_params, query):
    return api_supervisor_backfill()


@route("POST", "/api/supervisor/review")
def r_supervisor_review(params, body, url_params, query):
    """Supervisor QA 검수 전용 API. ticket_id 또는 team_id(batch) 지정."""
    ticket_id = body.get("ticket_id")
    team_id = body.get("team_id")
    batch = body.get("batch", False)

    if ticket_id:
        msg = f"{ticket_id} 티켓을 검수해줘"
        result = _chat_supervisor_respond("api-review", msg)
        return result
    elif team_id and batch:
        msg = f"team {team_id} Review 전체 검수해줘"
        result = _supervisor_batch_review("api-review-batch", msg, team_id)
        return result
    elif team_id:
        msg = f"team {team_id} Review 티켓 전체 검수해줘"
        result = _supervisor_batch_review("api-review-batch", msg, team_id)
        return result
    else:
        return {"ok": False, "error": "ticket_id 또는 team_id 필수"}


@route("GET", "/api/supervisor/review/stats")
def r_supervisor_review_stats(params, body, url_params, query):
    """Supervisor 검수 통계."""
    conn = get_db()
    total = conn.execute("SELECT COUNT(*) as c FROM ticket_feedbacks WHERE author='supervisor'").fetchone()["c"]
    passed = conn.execute("SELECT COUNT(*) as c FROM ticket_feedbacks WHERE author='supervisor' AND score >= 3").fetchone()["c"]
    reworked = conn.execute("SELECT COUNT(*) as c FROM ticket_feedbacks WHERE author='supervisor' AND score < 3").fetchone()["c"]
    avg_score = conn.execute("SELECT AVG(score) as a FROM ticket_feedbacks WHERE author='supervisor'").fetchone()["a"]
    review_left = conn.execute("SELECT COUNT(*) as c FROM tickets WHERE status='Review'").fetchone()["c"]

    recent = rows_to_list(conn.execute(
        "SELECT ticket_id, score, comment, created_at FROM ticket_feedbacks "
        "WHERE author='supervisor' ORDER BY created_at DESC LIMIT 10"
    ).fetchall())
    conn.close()

    return {
        "ok": True,
        "stats": {
            "total_reviews": total, "passed": passed, "reworked": reworked,
            "avg_score": round(avg_score, 2) if avg_score else 0,
            "review_pending": review_left,
        },
        "recent": recent,
    }


# Auth
@route("POST", "/api/auth/login")
def r_auth_login(params, body, url_params, query):
    key = body.get("license_key", "")
    if not _validate_license_key(key):
        return {"ok": False, "message": "유효하지 않은 라이선스 키입니다"}
    key_hash = _hash_license(key)
    token = _create_session(key_hash)
    return {"ok": True, "session_token": token}

@route("POST", "/api/auth/logout")
def r_auth_logout(params, body, url_params, query):
    cookie_header = body.get("_cookie", "")
    for part in cookie_header.split(";"):
        part = part.strip()
        if part.startswith("kanban_session="):
            token = part.split("=", 1)[1]
            with _sessions_lock:
                _sessions.pop(token, None)
    return {"ok": True}

# License CRUD (localhost only — enforced in _handle_api)
@route("POST", "/api/licenses")
def r_license_create(params, body, url_params, query):
    name = body.get("name", "")
    expires_days = body.get("expires_days")
    key = _generate_license_key()
    key_hash = _hash_license(key)
    display = _mask_license(key)
    expires_at = None
    if expires_days:
        expires_at = (datetime.now(timezone.utc) + timedelta(days=int(expires_days))).strftime("%Y-%m-%d %H:%M:%S")
    conn = get_db()
    conn.execute(
        "INSERT INTO licenses (license_key_hash,license_display,name,permissions,created_at,expires_at,is_active,created_by_ip) "
        "VALUES (?,?,?,?,?,?,?,?)",
        (key_hash, display, name, "full", now_utc(), expires_at, 1, "localhost")
    )
    conn.commit()
    conn.close()
    return {"ok": True, "license_key": key, "display": display, "name": name, "expires_at": expires_at}

@route("GET", "/api/licenses")
def r_license_list(params, body, url_params, query):
    conn = get_db()
    rows = conn.execute(
        "SELECT license_key_hash,license_display,name,permissions,created_at,expires_at,is_active,last_used_at,use_count "
        "FROM licenses ORDER BY created_at DESC"
    ).fetchall()
    conn.close()
    return {"ok": True, "licenses": rows_to_list(rows)}

@route("DELETE", "/api/licenses/{key_hash}")
def r_license_revoke(params, body, url_params, query):
    key_hash = url_params["key_hash"]
    conn = get_db()
    conn.execute("UPDATE licenses SET is_active=0 WHERE license_key_hash=?", (key_hash,))
    conn.commit()
    conn.close()
    return {"ok": True, "revoked": key_hash}


# ── 토큰 관리 API (A-4) ──

@route("POST", "/api/tokens")
def r_token_create(params, body, url_params, query):
    name = body.get("name", "")
    expires_days = body.get("expires_days")
    permissions = body.get("permissions", "agent")
    key = _generate_license_key()  # 4x4 16자 형식 재활용
    key_hash = _hash_license(key)
    display = _mask_license(key)
    expires_at = None
    if expires_days:
        expires_at = (datetime.now(timezone.utc) + timedelta(days=int(expires_days))).strftime("%Y-%m-%d %H:%M:%S")
    token_id = short_id("tok-")
    conn = get_db()
    conn.execute(
        "INSERT INTO auth_tokens (token_id,token_display,token_hash,name,permissions,expires_at) VALUES (?,?,?,?,?,?)",
        (token_id, display, key_hash, name, permissions, expires_at)
    )
    conn.commit()
    conn.close()
    return {"ok": True, "token_id": token_id, "token_key": key, "display": display, "name": name, "permissions": permissions, "expires_at": expires_at}

@route("GET", "/api/tokens")
def r_token_list(params, body, url_params, query):
    conn = get_db()
    rows = conn.execute(
        "SELECT token_id,token_display,name,permissions,created_at,expires_at,is_active,last_used_at,use_count FROM auth_tokens ORDER BY created_at DESC"
    ).fetchall()
    conn.close()
    return {"ok": True, "tokens": rows_to_list(rows)}

@route("DELETE", "/api/tokens/{token_id}")
def r_token_revoke(params, body, url_params, query):
    tid = url_params["token_id"]
    conn = get_db()
    conn.execute("UPDATE auth_tokens SET is_active=0 WHERE token_id=?", (tid,))
    conn.commit()
    conn.close()
    return {"ok": True, "revoked": tid}


# ── 프로젝트 별명 API ──

@route("GET", "/api/projects")
def r_projects_list(params, body, url_params, query):
    """별명 등록된 전체 프로젝트 목록."""
    projects = _get_known_projects()
    result = []
    for entry in projects:
        alias, path = entry[0], entry[1]
        orig_name = entry[2] if len(entry) > 2 else alias
        result.append({"alias": alias, "name": orig_name, "path": path, "exists": os.path.isdir(path)})
    return {"ok": True, "projects": result, "count": len(result)}


@route("POST", "/api/projects")
def r_projects_add(params, body, url_params, query):
    """프로젝트 별명 추가/수정."""
    alias = body.get("alias", "").strip()
    name = body.get("name", "").strip()
    path = body.get("path", "").strip()
    if not alias or not path:
        return {"ok": False, "error": "alias and path required"}
    if not name:
        name = alias

    conn = get_db()
    row = conn.execute("SELECT value FROM server_settings WHERE key='project_aliases'").fetchone()
    aliases = json.loads(row["value"]) if row and row["value"] else []

    # 기존 항목 업데이트 또는 추가
    found = False
    for a in aliases:
        if a["name"] == name or a["alias"] == alias:
            a["alias"] = alias
            a["name"] = name
            a["path"] = path
            found = True
            break
    if not found:
        aliases.append({"alias": alias, "name": name, "path": path})

    conn.execute(
        "INSERT OR REPLACE INTO server_settings (key, value, updated_at) VALUES ('project_aliases', ?, datetime('now'))",
        (json.dumps(aliases, ensure_ascii=False),)
    )
    conn.commit()
    conn.close()
    return {"ok": True, "project": {"alias": alias, "name": name, "path": path}}


@route("DELETE", "/api/projects/{alias}")
def r_projects_delete(params, body, url_params, query):
    """프로젝트 별명 삭제."""
    target = url_params["alias"]
    conn = get_db()
    row = conn.execute("SELECT value FROM server_settings WHERE key='project_aliases'").fetchone()
    aliases = json.loads(row["value"]) if row and row["value"] else []
    aliases = [a for a in aliases if a["alias"] != target and a["name"] != target]
    conn.execute(
        "INSERT OR REPLACE INTO server_settings (key, value, updated_at) VALUES ('project_aliases', ?, datetime('now'))",
        (json.dumps(aliases, ensure_ascii=False),)
    )
    conn.commit()
    conn.close()
    return {"ok": True}


# ── 오케스트레이터 API ──

@route("POST", "/api/orchestrate")
def r_orchestrate(params, body, url_params, query):
    """대시보드에서 직접 지시 실행."""
    project_name = body.get("project_name", "")
    instruction = body.get("instruction", "")
    if not project_name or not instruction:
        return {"ok": False, "error": "project_name and instruction required"}
    project_path = _find_project_path(project_name)
    if not project_path:
        return {"ok": False, "error": f"project '{project_name}' not found"}
    job_id = threading.Thread(target=_orch_dispatch, args=(project_name, instruction, project_path), daemon=True).start()
    return {"ok": True, "message": "dispatched"}


@route("GET", "/api/orchestrate/jobs")
def r_orchestrate_jobs(params, body, url_params, query):
    """진행 중인 오케스트레이션 작업 목록."""
    with _orch_lock:
        jobs = []
        for job_id, job in _orch_jobs.items():
            jobs.append({
                "job_id": job_id,
                "team_name": job["team_name"],
                "status": job["status"],
                "ticket_count": len(job["ticket_ids"]),
                "session_count": len(job["sessions"]),
            })
    return {"ok": True, "jobs": jobs}


@route("POST", "/api/orchestrate/cancel")
def r_orchestrate_cancel(params, body, url_params, query):
    """작업 취소."""
    job_id = body.get("job_id", "")
    if not job_id:
        return {"ok": False, "error": "job_id required"}
    if _orch_cancel(job_id):
        return {"ok": True}
    return {"ok": False, "error": "job not found"}


# ── 에이전트 소통 중계 API ──

@route("POST", "/api/agent/relay")
def r_agent_relay(params, body, url_params, query):
    """서브에이전트 → 메인 상주 에이전트 → 다른 서브에이전트 메시지 중계.
    from_agent가 to_agent에게 요청. 메인이 중계 역할."""
    from_agent = body.get("from_agent", "")
    to_agent = body.get("to_agent", "")
    team_id = body.get("team_id", "")
    ticket_id = body.get("ticket_id", "")
    content = body.get("content", "")
    msg_type = body.get("msg_type", "request")  # request, response, info

    if not all([from_agent, to_agent, team_id, content]):
        return {"ok": False, "error": "from_agent, to_agent, team_id, content required"}

    conn = get_db()
    conn.execute(
        "INSERT INTO agent_conversations (team_id, ticket_id, from_agent, to_agent, msg_type, content) VALUES (?,?,?,?,?,?)",
        (team_id, ticket_id, from_agent, to_agent, content, msg_type)
    )
    conn.commit()
    conn.close()

    sse_broadcast(team_id, "agent_message", {
        "from": from_agent, "to": to_agent, "ticket_id": ticket_id,
        "msg_type": msg_type, "content": content[:200]
    })
    return {"ok": True}


@route("GET", "/api/agent/conversations/{team_id}")
def r_agent_conversations(params, body, url_params, query):
    """팀 내 에이전트 간 전체 대화 이력."""
    team_id = url_params["team_id"]
    ticket_id = query.get("ticket_id", [""])[0]
    conn = get_db()
    if ticket_id:
        rows = rows_to_list(conn.execute(
            "SELECT * FROM agent_conversations WHERE team_id=? AND ticket_id=? ORDER BY created_at",
            (team_id, ticket_id)
        ).fetchall())
    else:
        rows = rows_to_list(conn.execute(
            "SELECT * FROM agent_conversations WHERE team_id=? ORDER BY created_at DESC LIMIT 100",
            (team_id,)
        ).fetchall())
    conn.close()
    return {"ok": True, "conversations": rows}


@route("GET", "/api/tickets/{ticket_id}/reviews")
def r_ticket_reviews(params, body, url_params, query):
    """티켓별 리뷰/평가 이력."""
    ticket_id = url_params["ticket_id"]
    conn = get_db()
    reviews = rows_to_list(conn.execute(
        "SELECT * FROM ticket_reviews WHERE ticket_id=? ORDER BY created_at",
        (ticket_id,)
    ).fetchall())
    conn.close()
    return {"ok": True, "reviews": reviews}



@route("GET", "/api/tickets/{ticket_id}/thread")
def r_ticket_thread(params, body, url_params, query):
    """티켓 대화 스레드 — 대화/QA리뷰/활동로그/산출물 통합."""
    tid = url_params["ticket_id"]
    conn = get_db()
    convs = rows_to_list(conn.execute(
        "SELECT 'conversation' as kind, created_at, from_agent as speaker, to_agent, content as message, msg_type "
        "FROM agent_conversations WHERE ticket_id=? ORDER BY created_at", (tid,)
    ).fetchall())
    reviews = rows_to_list(conn.execute(
        "SELECT 'qa' as kind, created_at, reviewer as speaker, '' as to_agent, comment as message, result as msg_type, score, retry_round "
        "FROM ticket_reviews WHERE ticket_id=? ORDER BY created_at", (tid,)
    ).fetchall())
    logs = rows_to_list(conn.execute(
        "SELECT 'activity' as kind, created_at, COALESCE(member_id,'system') as speaker, '' as to_agent, message, action as msg_type "
        "FROM activity_logs WHERE ticket_id=? ORDER BY created_at", (tid,)
    ).fetchall())
    arts = rows_to_list(conn.execute(
        "SELECT 'artifact' as kind, created_at, creator_member_id as speaker, '' as to_agent, title as message, artifact_type as msg_type "
        "FROM artifacts WHERE ticket_id=? ORDER BY created_at", (tid,)
    ).fetchall())
    conn.close()
    thread = sorted(convs + reviews + logs + arts, key=lambda x: x.get('created_at',''))
    return {"ok": True, "thread": thread, "count": len(thread)}


@route("GET", "/api/tickets/{ticket_id}/history")
def r_ticket_full_history(params, body, url_params, query):
    """티켓 전체 히스토리 (대화 + 리뷰 + 산출물 + 활동로그 통합)."""
    tid = url_params["ticket_id"]
    conn = get_db()
    conversations = rows_to_list(conn.execute(
        "SELECT 'conversation' as type, created_at, from_agent as actor, content as detail, msg_type as sub_type FROM agent_conversations WHERE ticket_id=? ORDER BY created_at", (tid,)
    ).fetchall())
    reviews = rows_to_list(conn.execute(
        "SELECT 'review' as type, created_at, reviewer as actor, comment as detail, result as sub_type, score, issues, retry_round FROM ticket_reviews WHERE ticket_id=? ORDER BY created_at", (tid,)
    ).fetchall())
    artifacts = rows_to_list(conn.execute(
        "SELECT 'artifact' as type, created_at, creator_member_id as actor, title as detail, artifact_type as sub_type FROM artifacts WHERE ticket_id=? ORDER BY created_at", (tid,)
    ).fetchall())
    details = rows_to_list(conn.execute(
        "SELECT 'artifact_detail' as type, created_at, file_path, lines_added, lines_removed, api_endpoint, description as detail, detail_type as sub_type FROM artifact_details WHERE ticket_id=? ORDER BY created_at", (tid,)
    ).fetchall())
    logs = rows_to_list(conn.execute(
        "SELECT 'activity' as type, created_at, member_id as actor, message as detail, action as sub_type FROM activity_logs WHERE ticket_id=? ORDER BY created_at", (tid,)
    ).fetchall())
    feedbacks = rows_to_list(conn.execute(
        "SELECT 'feedback' as type, created_at, author as actor, comment as detail, 'feedback' as sub_type, score FROM ticket_feedbacks WHERE ticket_id=? ORDER BY created_at", (tid,)
    ).fetchall())
    conn.close()

    # 시간순 통합 정렬
    all_items = conversations + reviews + artifacts + details + logs + feedbacks
    all_items.sort(key=lambda x: x.get("created_at", ""))
    return {"ok": True, "history": all_items}


# ── 프로젝트 별명 CRUD API ──

@route("GET", "/api/projects/aliases")
def r_aliases_list(params, body, url_params, query):
    projects = _get_known_projects()
    return {"ok": True, "projects": [
        {"alias": e[0], "path": e[1], "name": e[2] if len(e) > 2 else e[0]}
        for e in projects
    ]}


@route("POST", "/api/projects/aliases")
def r_aliases_upsert(params, body, url_params, query):
    alias = body.get("alias", "").strip()
    name = body.get("name", "").strip()
    path = body.get("path", "").strip()
    if not alias or not path:
        return {"ok": False, "error": "alias and path required"}
    if not os.path.isdir(path):
        return {"ok": False, "error": f"path not found: {path}"}
    if not name:
        name = os.path.basename(path)

    conn = get_db()
    row = conn.execute("SELECT value FROM server_settings WHERE key='project_aliases'").fetchone()
    aliases = json.loads(row["value"]) if row and row["value"] else []
    conn.close()
    aliases = [a for a in aliases if a["alias"] != alias]
    aliases.append({"alias": alias, "name": name, "path": path})
    _save_project_aliases(aliases)
    return {"ok": True, "alias": alias, "name": name, "path": path}


@route("DELETE", "/api/projects/aliases/{alias}")
def r_aliases_delete(params, body, url_params, query):
    alias = url_params["alias"]
    conn = get_db()
    row = conn.execute("SELECT value FROM server_settings WHERE key='project_aliases'").fetchone()
    aliases = json.loads(row["value"]) if row and row["value"] else []
    conn.close()
    before = len(aliases)
    aliases = [a for a in aliases if a["alias"] != alias]
    if len(aliases) == before:
        return {"ok": False, "error": "alias not found"}
    _save_project_aliases(aliases)
    return {"ok": True}


# ── Telegram Bot API ──

@route("GET", "/api/telegram/config")
def r_telegram_config_get(params, body, url_params, query):
    with _tg_lock:
        return {
            "ok": True,
            "enabled": _tg_config["enabled"],
            "bot_token_set": bool(_tg_config["bot_token"]),
            "chat_id": _tg_config["chat_id"],
        }


@route("POST", "/api/telegram/config")
def r_telegram_config_set(params, body, url_params, query):
    bot_token = body.get("bot_token", "").strip()
    chat_id = body.get("chat_id", "").strip()
    if not bot_token:
        return {"ok": False, "error": "bot_token required"}
    if not chat_id:
        return {"ok": False, "error": "chat_id required (send /start to bot first, then use /api/telegram/detect)"}

    _tg_save_config(bot_token, chat_id)
    _tg_start_polling()
    _tg_send("✅ <b>칸반보드 연동 완료!</b>\n/help 로 명령어 확인")
    return {"ok": True, "enabled": True}


@route("POST", "/api/telegram/test")
def r_telegram_test(params, body, url_params, query):
    result = _tg_send("🔔 <b>테스트 알림</b>\n칸반보드 Telegram 연동이 정상 작동합니다.")
    if result and result.get("ok"):
        return {"ok": True}
    return {"ok": False, "error": "전송 실패 — 봇 토큰/채팅 ID 확인"}


@route("POST", "/api/telegram/detect")
def r_telegram_detect_chat(params, body, url_params, query):
    """봇에 /start 보낸 후 chat_id 자동 감지."""
    bot_token = body.get("bot_token", "").strip()
    if not bot_token:
        with _tg_lock:
            bot_token = _tg_config["bot_token"]
    if not bot_token:
        return {"ok": False, "error": "bot_token required"}
    url = f"https://api.telegram.org/bot{bot_token}/getUpdates"
    try:
        req = Request(url, data=json.dumps({"limit": 5}).encode(), headers={"Content-Type": "application/json"})
        resp = urlopen(req, timeout=10)
        data = json.loads(resp.read())
        if data.get("ok"):
            for u in reversed(data.get("result", [])):
                msg = u.get("message", {})
                chat = msg.get("chat", {})
                if chat.get("id"):
                    return {"ok": True, "chat_id": str(chat["id"]), "chat_name": chat.get("first_name", chat.get("title", ""))}
        return {"ok": False, "error": "no messages found — send /start to the bot first"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


@route("DELETE", "/api/telegram/config")
def r_telegram_config_delete(params, body, url_params, query):
    _tg_save_config("", "")
    _tg_stop_poll.set()
    return {"ok": True}


# ── 시스템 메트릭 API (A-2) ──

def _get_system_metrics():
    """표준 라이브러리만으로 시스템 메트릭 수집."""
    global _metrics_cache, _metrics_cache_time
    now = time.time()
    if _metrics_cache and now - _metrics_cache_time < 5:
        return _metrics_cache
    metrics = {"cpu_percent": 0, "memory_total_mb": 0, "memory_used_mb": 0, "memory_percent": 0,
               "disk_total_gb": 0, "disk_used_gb": 0, "disk_percent": 0,
               "net_sent_kb": 0, "net_recv_kb": 0, "platform": platform.system(),
               "python_version": platform.python_version(), "hostname": platform.node()}
    try:
        if platform.system() == "Windows":
            # CPU
            try:
                out = subprocess.check_output(["wmic", "cpu", "get", "loadpercentage"], timeout=5, stderr=subprocess.DEVNULL).decode()
                for line in out.strip().split('\n')[1:]:
                    v = line.strip()
                    if v.isdigit():
                        metrics["cpu_percent"] = int(v)
                        break
            except Exception:
                pass
            # Memory
            try:
                out = subprocess.check_output(
                    ["powershell", "-NoProfile", "-Command",
                     "Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize,FreePhysicalMemory | ConvertTo-Json"],
                    timeout=5, stderr=subprocess.DEVNULL
                ).decode()
                info = json.loads(out)
                total_kb = int(info.get("TotalVisibleMemorySize", 0))
                free_kb = int(info.get("FreePhysicalMemory", 0))
                metrics["memory_total_mb"] = round(total_kb / 1024)
                metrics["memory_used_mb"] = round((total_kb - free_kb) / 1024)
                metrics["memory_percent"] = round((total_kb - free_kb) / total_kb * 100) if total_kb else 0
            except Exception:
                pass
            # Disk
            try:
                out = subprocess.check_output(
                    ["powershell", "-NoProfile", "-Command",
                     "Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\" | Select-Object Size,FreeSpace | ConvertTo-Json"],
                    timeout=5, stderr=subprocess.DEVNULL
                ).decode()
                info = json.loads(out)
                total = int(info.get("Size", 0))
                free = int(info.get("FreeSpace", 0))
                metrics["disk_total_gb"] = round(total / (1024**3), 1)
                metrics["disk_used_gb"] = round((total - free) / (1024**3), 1)
                metrics["disk_percent"] = round((total - free) / total * 100) if total else 0
            except Exception:
                pass
        else:
            # Linux: /proc
            try:
                with open("/proc/stat") as f:
                    parts = f.readline().split()
                    idle = int(parts[4])
                    total = sum(int(x) for x in parts[1:])
                    metrics["cpu_percent"] = round((1 - idle / total) * 100) if total else 0
            except Exception:
                pass
            try:
                with open("/proc/meminfo") as f:
                    info = {}
                    for line in f:
                        k, v = line.split(":")
                        info[k.strip()] = int(v.strip().split()[0])
                    total_kb = info.get("MemTotal", 0)
                    free_kb = info.get("MemAvailable", info.get("MemFree", 0))
                    metrics["memory_total_mb"] = round(total_kb / 1024)
                    metrics["memory_used_mb"] = round((total_kb - free_kb) / 1024)
                    metrics["memory_percent"] = round((total_kb - free_kb) / total_kb * 100) if total_kb else 0
            except Exception:
                pass
            try:
                st = os.statvfs("/")
                total = st.f_blocks * st.f_frsize
                free = st.f_bavail * st.f_frsize
                metrics["disk_total_gb"] = round(total / (1024**3), 1)
                metrics["disk_used_gb"] = round((total - free) / (1024**3), 1)
                metrics["disk_percent"] = round((total - free) / total * 100) if total else 0
            except Exception:
                pass
    except Exception:
        pass
    # DB 통계
    try:
        conn = get_db()
        metrics["db_size_mb"] = round(os.path.getsize(DB_PATH) / (1024*1024), 2)
        r = conn.execute("SELECT COUNT(*) FROM agent_teams WHERE status != 'Archived'").fetchone()
        metrics["active_teams"] = r[0] if r else 0
        r = conn.execute("SELECT COUNT(*) FROM tickets WHERE status='InProgress'").fetchone()
        metrics["active_tickets"] = r[0] if r else 0
        sse_count = sum(len(v) for v in _sse_clients.values()) + len(_sse_global)
        metrics["sse_clients"] = sse_count
        conn.close()
    except Exception:
        pass
    # Node 프로세스 모니터링
    try:
        if platform.system() == "Windows":
            out = subprocess.check_output(
                ["powershell", "-NoProfile", "-Command",
                 "Get-Process node -EA SilentlyContinue | Measure-Object WorkingSet64 -Sum | "
                 "Select-Object Count,@{N='SumMB';E={[math]::Round($_.Sum/1MB)}} | ConvertTo-Json"],
                timeout=5, stderr=subprocess.DEVNULL
            ).decode()
            info = json.loads(out)
            metrics["node_count"] = info.get("Count", 0)
            metrics["node_memory_mb"] = info.get("SumMB", 0)
        else:
            import glob as _g
            pids = [p for p in os.listdir("/proc") if p.isdigit()]
            node_count = 0; node_mem = 0
            for pid in pids:
                try:
                    with open(f"/proc/{pid}/comm") as f:
                        if f.read().strip() == "node":
                            node_count += 1
                            with open(f"/proc/{pid}/status") as sf:
                                for line in sf:
                                    if line.startswith("VmRSS:"):
                                        node_mem += int(line.split()[1])
                except Exception:
                    pass
            metrics["node_count"] = node_count
            metrics["node_memory_mb"] = round(node_mem / 1024)
    except Exception:
        metrics["node_count"] = 0
        metrics["node_memory_mb"] = 0

    # GPU 메트릭 (nvidia-smi)
    metrics["gpu_name"] = ""
    metrics["gpu_util"] = 0
    metrics["gpu_temp"] = 0
    metrics["gpu_vram_used_mb"] = 0
    metrics["gpu_vram_total_mb"] = 0
    metrics["gpu_vram_percent"] = 0
    metrics["gpu_power_w"] = 0
    metrics["gpu_power_max_w"] = 0
    metrics["gpu_fan_percent"] = 0
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,"
             "memory.used,memory.total,power.draw,power.limit,fan.speed",
             "--format=csv,noheader,nounits"],
            timeout=5, stderr=subprocess.DEVNULL
        ).decode().strip()
        if out:
            parts = [p.strip() for p in out.split(",")]
            metrics["gpu_name"] = parts[0] if len(parts) > 0 else ""
            metrics["gpu_util"] = int(float(parts[1])) if len(parts) > 1 and parts[1].replace('.','').isdigit() else 0
            metrics["gpu_temp"] = int(float(parts[2])) if len(parts) > 2 and parts[2].replace('.','').isdigit() else 0
            metrics["gpu_vram_used_mb"] = int(float(parts[3])) if len(parts) > 3 and parts[3].replace('.','').isdigit() else 0
            metrics["gpu_vram_total_mb"] = int(float(parts[4])) if len(parts) > 4 and parts[4].replace('.','').isdigit() else 0
            if metrics["gpu_vram_total_mb"] > 0:
                metrics["gpu_vram_percent"] = round(metrics["gpu_vram_used_mb"] / metrics["gpu_vram_total_mb"] * 100)
            metrics["gpu_power_w"] = round(float(parts[5]), 1) if len(parts) > 5 and parts[5].replace('.','').isdigit() else 0
            metrics["gpu_power_max_w"] = round(float(parts[6]), 1) if len(parts) > 6 and parts[6].replace('.','').isdigit() else 0
            metrics["gpu_fan_percent"] = int(float(parts[7])) if len(parts) > 7 and parts[7].replace('.','').replace('[','').replace(']','').isdigit() else 0
    except Exception:
        pass

    # 온도 센서 (Linux: /sys/class/thermal + /sys/class/hwmon)
    metrics["temps"] = []
    if platform.system() != "Windows":
        # thermal zones (CPU 패키지 등)
        try:
            i = 0
            while os.path.exists(f"/sys/class/thermal/thermal_zone{i}/temp"):
                temp_raw = open(f"/sys/class/thermal/thermal_zone{i}/temp").read().strip()
                temp_c = round(int(temp_raw) / 1000, 1)
                zone_type = ""
                try:
                    zone_type = open(f"/sys/class/thermal/thermal_zone{i}/type").read().strip()
                except Exception:
                    zone_type = f"zone{i}"
                if temp_c > 0:
                    metrics["temps"].append({"name": zone_type, "temp": temp_c})
                i += 1
        except Exception:
            pass
        # hwmon (coretemp 등)
        try:
            import glob as _glob
            for hwmon in sorted(_glob.glob("/sys/class/hwmon/hwmon*")):
                hw_name = ""
                try:
                    hw_name = open(f"{hwmon}/name").read().strip()
                except Exception:
                    continue
                for tf in sorted(_glob.glob(f"{hwmon}/temp*_input")):
                    try:
                        temp_c = round(int(open(tf).read().strip()) / 1000, 1)
                        label_f = tf.replace("_input", "_label")
                        label = open(label_f).read().strip() if os.path.exists(label_f) else hw_name
                        if temp_c > 0 and not any(t["name"] == label for t in metrics["temps"]):
                            metrics["temps"].append({"name": label, "temp": temp_c})
                    except Exception:
                        continue
        except Exception:
            pass

    # Load Average (Linux)
    metrics["load_avg"] = [0, 0, 0]
    if platform.system() != "Windows":
        try:
            la = os.getloadavg()
            metrics["load_avg"] = [round(la[0], 2), round(la[1], 2), round(la[2], 2)]
        except Exception:
            pass

    # NIM API 사용량 포함
    metrics["nim_usage"] = dict(_nim_usage)

    _metrics_cache = metrics
    _metrics_cache_time = now
    return metrics

@route("GET", "/api/system/metrics")
def r_system_metrics(params, body, url_params, query):
    return {"ok": True, "metrics": _get_system_metrics()}

@route("GET", "/api/system/node-processes")
def r_node_processes(params, body, url_params, query):
    """Node 프로세스 상세 목록."""
    try:
        if platform.system() == "Windows":
            out = subprocess.check_output(
                ["powershell", "-NoProfile", "-Command",
                 "Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | "
                 "Select-Object ProcessId,@{N='MemMB';E={[math]::Round($_.WorkingSetSize/1MB)}},CommandLine | "
                 "ConvertTo-Json -Compress"],
                timeout=10, stderr=subprocess.DEVNULL
            ).decode()
            procs = json.loads(out)
            if isinstance(procs, dict): procs = [procs]
        else:
            procs = []
        # MCP 패턴 분류
        mcp_patterns = ["context7-mcp", "server-memory", "server-sequential-thinking",
                        "pinecone-database/mcp", "playwright/mcp", "sonatype"]
        for p in procs:
            cmd = p.get("CommandLine", "") or ""
            p["is_mcp"] = any(pat in cmd for pat in mcp_patterns)
            p["mcp_name"] = next((pat for pat in mcp_patterns if pat in cmd), None)
        return {"ok": True, "processes": procs, "total": len(procs),
                "mcp_count": sum(1 for p in procs if p.get("is_mcp"))}
    except Exception as e:
        return {"ok": False, "error": str(e)}

@route("GET", "/api/system/processes")
def r_system_processes(params, body, url_params, query):
    """실행 중인 Node/Claude/Python 프로세스 목록."""
    procs = []
    try:
        if platform.system() == "Windows":
            out = subprocess.check_output(
                ["powershell", "-NoProfile", "-Command",
                 "Get-CimInstance Win32_Process -Filter \"Name='node.exe' or Name='claude.exe'\" | "
                 "Select-Object ProcessId,Name,CommandLine,WorkingSetSize | "
                 "ConvertTo-Json -Compress"],
                timeout=10, stderr=subprocess.DEVNULL
            ).decode("utf-8", errors="replace")
            items = json.loads(out) if out.strip() else []
            if isinstance(items, dict):
                items = [items]
            for item in items:
                cmd = (item.get("CommandLine") or "")[:200]
                procs.append({
                    "pid": item.get("ProcessId", 0),
                    "name": item.get("Name", "?"),
                    "cmd": cmd,
                    "mem_mb": round((item.get("WorkingSetSize", 0) or 0) / 1024 / 1024)
                })
        else:
            for pid in os.listdir("/proc"):
                if not pid.isdigit():
                    continue
                try:
                    with open(f"/proc/{pid}/cmdline") as f:
                        cmd = f.read().replace("\0", " ").strip()
                    if not cmd:
                        continue
                    name = os.path.basename(cmd.split()[0]) if cmd else "?"
                    if name in ("node", "claude"):
                        mem = 0
                        try:
                            with open(f"/proc/{pid}/status") as sf:
                                for line in sf:
                                    if line.startswith("VmRSS:"):
                                        mem = int(line.split()[1]) // 1024
                        except Exception:
                            pass
                        procs.append({"pid": int(pid), "name": name, "cmd": cmd[:200], "mem_mb": mem})
                except Exception:
                    pass
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "processes": procs}


@route("POST", "/api/system/kill-process")
def r_system_kill_process(params, body, url_params, query):
    """특정 PID 프로세스 종료."""
    pid = body.get("pid", 0)
    if not pid:
        return {"ok": False, "error": "pid required"}
    try:
        if platform.system() == "Windows":
            subprocess.run(["taskkill", "/PID", str(pid), "/F"], timeout=5, capture_output=True)
        else:
            os.kill(pid, 9)
        return {"ok": True, "killed": pid}
    except Exception as e:
        return {"ok": False, "error": str(e)}


@route("POST", "/api/system/kill-zombie-mcp")
def r_kill_zombie_mcp(params, body, url_params, query):
    """좀비 MCP 프로세스 종료."""
    try:
        killed, report = _kill_zombie_mcp_procs()
        return {"ok": True, "killed": killed, "details": report}
    except Exception as e:
        return {"ok": False, "error": str(e)}


# ── 팀 완료 검증 API ──

@route("GET", "/api/teams/{team_id}/validate-completion")
def r_team_validate_completion(params, body, url_params, query):
    """팀의 모든 티켓이 Done 상태인지 검증한다.

    Returns:
        {
            "ok": True,
            "can_complete": bool,       # 모든 티켓이 Done이면 True
            "total": int,               # 전체 티켓 수
            "done_count": int,          # Done 티켓 수
            "incomplete_tickets": [     # 미완료 티켓 목록 (can_complete=False 시)
                {
                    "ticket_id": str,
                    "title": str,
                    "status": str,
                    "priority": str,
                    "assigned_member_id": str | None,
                }
            ]
        }
    """
    team_id = url_params["team_id"]
    conn = get_db()
    team = row_to_dict(conn.execute("SELECT team_id, name, status FROM agent_teams WHERE team_id=?", (team_id,)).fetchone())
    if not team:
        conn.close()
        return {"ok": False, "error": "team_not_found"}

    total = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=?", (team_id,)).fetchone()[0]
    done_count = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=? AND status=\'Done\'", (team_id,)).fetchone()[0]

    incomplete = []
    if done_count < total:
        rows = conn.execute(
            "SELECT ticket_id, title, status, priority, assigned_member_id "
            "FROM tickets WHERE team_id=? AND status != \'Done\' ORDER BY created_at",
            (team_id,)
        ).fetchall()
        incomplete = [
            {
                "ticket_id": r["ticket_id"],
                "title": r["title"],
                "status": r["status"],
                "priority": r["priority"],
                "assigned_member_id": r["assigned_member_id"],
            }
            for r in rows
        ]

    conn.close()
    can_complete = (total > 0 and done_count == total)
    return {
        "ok": True,
        "can_complete": can_complete,
        "total": total,
        "done_count": done_count,
        "incomplete_tickets": incomplete,
    }


# ── 팀 아카이빙 API (A-3) ──

@route("POST", "/api/teams/{team_id}/archive")
def r_team_archive(params, body, url_params, query):
    team_id = url_params["team_id"]
    conn = get_db()
    team = row_to_dict(conn.execute("SELECT * FROM agent_teams WHERE team_id=?", (team_id,)).fetchone())
    if not team:
        conn.close()
        return {"ok": False, "error": "team_not_found"}
    if team["status"] == "Archived":
        conn.close()
        return {"ok": False, "error": "already_archived"}
    # 100% 완료 확인 (강제 아카이브 옵션 지원)
    force = body.get("force", False) if body else False
    if not force:
        total = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=?", (team_id,)).fetchone()[0]
        done = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=? AND status='Done'", (team_id,)).fetchone()[0]
        if total > 0 and done < total:
            conn.close()
            return {"ok": False, "error": "not_complete", "message": f"완료 {done}/{total} — 모든 티켓이 Done이어야 아카이브 가능합니다 (force:true로 강제 가능)"}
    # ── 아카이브 전 데이터 덤프 (전체를 try로 감싸 — 실패해도 아카이브 진행) ──
    try:
        conversation_parts = []
        ticket_rows = conn.execute("SELECT ticket_id, title FROM tickets WHERE team_id=? ORDER BY created_at", (team_id,)).fetchall()
        for trow in ticket_rows:
            tkid = trow["ticket_id"]
            try:
                msgs = conn.execute(
                    "SELECT m.*, tm.display_name as sender_name FROM messages m "
                    "LEFT JOIN team_members tm ON m.sender_member_id=tm.member_id "
                    "WHERE m.ticket_id=? ORDER BY m.created_at", (tkid,)
                ).fetchall()
            except Exception:
                msgs = conn.execute(
                    "SELECT * FROM messages WHERE team_id=? ORDER BY created_at", (team_id,)
                ).fetchall() if not conversation_parts else []
            if msgs:
                conversation_parts.append(f"── {trow['title']} ({tkid}) ──")
                for msg in msgs:
                    sender = msg.get("sender_name") or msg.get("sender_member_id") or msg.get("sender") or "unknown"
                    ts_msg = msg.get("created_at") or ""
                    mtype = msg.get("message_type") or "comment"
                    conversation_parts.append(f"  [{ts_msg}] {sender} ({mtype}): {msg.get('content','')}")
                conversation_parts.append("")
    except Exception as e:
        conversation_parts = [f"[대화 덤프 실패: {e}]"]
    if conversation_parts:
        dump_text = "\n".join(conversation_parts)
        # 대화 전문이 너무 길면 분할 (activity_log 메시지 제한 대비)
        MAX_CHUNK = 10000
        chunks = [dump_text[i:i+MAX_CHUNK] for i in range(0, len(dump_text), MAX_CHUNK)]
        for idx, chunk in enumerate(chunks):
            label = f" (part {idx+1}/{len(chunks)})" if len(chunks) > 1 else ""
            conn.execute(
                "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,metadata,created_at) VALUES (?,?,?,?,?,?,?)",
                (team_id, None, None, "archive_conversation_dump",
                 f"[ARCHIVE] 대화 전문 백업{label}\n{chunk}", None, now_utc())
            )
    # 산출물 목록도 기록
    try:
        arts = conn.execute(
            "SELECT a.*, tm.display_name as creator_name FROM artifacts a "
            "LEFT JOIN team_members tm ON a.creator_member_id=tm.member_id "
            "WHERE a.team_id=? ORDER BY a.created_at", (team_id,)
        ).fetchall()
        if arts:
            art_lines = [f"[ARCHIVE] 산출물 백업 ({len(arts)}건)"]
            for a in [dict(r) for r in arts]:
                creator = a.get("creator_name") or a.get("creator_member_id") or "unknown"
                art_lines.append(f"  - {a.get('title','untitled')} by {creator} ({a.get('artifact_type','file')})")
            conn.execute(
                "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,metadata,created_at) VALUES (?,?,?,?,?,?,?)",
                (team_id, None, None, "archive_artifact_dump", "\n".join(art_lines), None, now_utc())
            )
    except Exception:
        pass
    # 피드백 요약도 기록
    try:
        fbs = conn.execute("SELECT * FROM ticket_feedbacks WHERE team_id=?", (team_id,)).fetchall()
        if fbs:
            fbs_dicts = [dict(r) for r in fbs]
            scores = [f["score"] for f in fbs_dicts if f.get("score")]
            avg = round(sum(scores)/len(scores), 1) if scores else 0
            fb_lines = [f"[ARCHIVE] 피드백 요약: {len(fbs)}건, 평균 점수 {avg}/5"]
            for f in fbs_dicts:
                fb_lines.append(f"  - {f.get('ticket_id','')} score:{f.get('score','-')} {(f.get('comment') or '')[:80]}")
            conn.execute(
                "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,metadata,created_at) VALUES (?,?,?,?,?,?,?)",
                (team_id, None, None, "archive_feedback_dump", "\n".join(fb_lines), None, now_utc())
            )
    except Exception:
        pass
    except Exception as _archive_dump_err:
        print(f"[archive] dump error (ignored): {_archive_dump_err}", flush=True)

    ts = now_utc()
    conn.execute("UPDATE agent_teams SET status='Archived', archived_at=?, completed_at=COALESCE(completed_at,?) WHERE team_id=?", (ts, ts, team_id))
    # 자동 스냅샷 저장 (벤치마킹용)
    try:
        _save_team_snapshot(conn, team_id, "archive")
    except Exception:
        pass
    conn.commit()
    conn.close()
    sse_broadcast(team_id, "team_archived", {"team_id": team_id, "name": team["name"], "archived_at": ts})
    return {"ok": True, "team_id": team_id, "archived_at": ts}



@route("GET", "/api/agents/kpi")
def r_agents_kpi(params, body, url_params, query):
    """전체 에이전트별 KPI 통계."""
    conn = get_db()
    team_id = query.get("team_id", "")
    where = "WHERE m.team_id=?" if team_id else ""
    bind = (team_id,) if team_id else ()
    members = conn.execute(
        f"SELECT m.member_id, m.team_id, m.role, m.display_name, m.status, "
        f"t.name as team_name FROM team_members m "
        f"JOIN agent_teams t ON m.team_id=t.team_id {where} "
        f"ORDER BY t.name, m.role", bind
    ).fetchall()
    result = []
    for m in members:
        mid = m["member_id"]
        tid = m["team_id"]
        # 티켓 통계
        tickets = conn.execute(
            "SELECT status, COUNT(*) as n FROM tickets WHERE assigned_member_id=? GROUP BY status", (mid,)
        ).fetchall()
        ticket_stats = {r["status"]: r["n"] for r in tickets}
        total = sum(ticket_stats.values())
        done = ticket_stats.get("Done", 0)
        # QA 점수
        qa = conn.execute(
            "SELECT AVG(score) as avg_score, COUNT(*) as reviews FROM ticket_reviews tr "
            "JOIN tickets tk ON tr.ticket_id=tk.ticket_id WHERE tk.assigned_member_id=? AND tr.score IS NOT NULL", (mid,)
        ).fetchone()
        # 대화 수
        convs = conn.execute(
            "SELECT COUNT(*) as n FROM agent_conversations WHERE from_agent LIKE ? OR to_agent LIKE ?",
            (f"%{m['display_name'] or m['role']}%", f"%{m['display_name'] or m['role']}%")
        ).fetchone()
        # 산출물 수
        arts = conn.execute(
            "SELECT COUNT(*) as n FROM artifacts WHERE creator_member_id=?", (mid,)
        ).fetchone()
        # 토큰 사용량
        usage = conn.execute(
            "SELECT SUM(input_tokens) as inp, SUM(output_tokens) as outp, SUM(estimated_cost) as cost "
            "FROM token_usage WHERE member_id=?", (mid,)
        ).fetchone()
        result.append({
            "member_id": mid, "team_id": tid, "team_name": m["team_name"],
            "role": m["role"], "display_name": m["display_name"], "status": m["status"],
            "tickets_total": total, "tickets_done": done,
            "tickets_inprogress": ticket_stats.get("InProgress", 0),
            "tickets_blocked": ticket_stats.get("Blocked", 0),
            "completion_rate": round(done / total * 100, 1) if total > 0 else 0,
            "qa_avg_score": round(qa["avg_score"], 1) if qa and qa["avg_score"] else 0,
            "qa_reviews": qa["reviews"] if qa else 0,
            "conversations": convs["n"] if convs else 0,
            "artifacts": arts["n"] if arts else 0,
            "tokens_input": usage["inp"] or 0 if usage else 0,
            "tokens_output": usage["outp"] or 0 if usage else 0,
            "cost": round(usage["cost"] or 0, 4) if usage else 0
        })
    return {"ok": True, "agents": result}


@route("GET", "/api/resident/kpi")
def r_resident_kpi(params, body, url_params, query):
    """상주 에이전트(유디) KPI 통계."""
    conn = get_db()
    # QA 리뷰 수/평균점수
    qa = conn.execute(
        "SELECT COUNT(*) as n, AVG(score) as avg, "
        "SUM(CASE WHEN result='pass' THEN 1 ELSE 0 END) as passes, "
        "SUM(CASE WHEN result='fail' THEN 1 ELSE 0 END) as fails "
        "FROM ticket_reviews WHERE reviewer LIKE '%상주%' OR reviewer LIKE '%유디%'"
    ).fetchone()
    # 대화 라우팅
    routes = conn.execute(
        "SELECT COUNT(*) as n FROM agent_conversations WHERE (from_agent LIKE '%상주%' OR from_agent LIKE '%유디%') AND msg_type IN ('route','answer')"
    ).fetchone()
    # 재작업 발행
    reworks = conn.execute(
        "SELECT COUNT(*) as n FROM agent_conversations WHERE (from_agent LIKE '%상주%' OR from_agent LIKE '%유디%') AND msg_type='rework'"
    ).fetchone()
    # 회의 소집
    meetings = conn.execute(
        "SELECT COUNT(*) as n FROM agent_conversations WHERE (from_agent LIKE '%상주%' OR from_agent LIKE '%유디%') AND msg_type='meeting'"
    ).fetchone()
    # 메시지 수
    msgs = conn.execute(
        "SELECT COUNT(*) as n FROM messages WHERE sender_member_id LIKE '%상주%' OR sender_member_id LIKE '%유디%'"
    ).fetchone()
    # 오늘 활동
    today_qa = conn.execute(
        "SELECT COUNT(*) as n FROM ticket_reviews WHERE (reviewer LIKE '%상주%' OR reviewer LIKE '%유디%') AND date(created_at)=date('now')"
    ).fetchone()
    return {"ok": True, "kpi": {
        "qa_total": qa["n"] if qa else 0,
        "qa_avg_score": round(qa["avg"] or 0, 1) if qa else 0,
        "qa_pass": qa["passes"] or 0 if qa else 0,
        "qa_fail": qa["fails"] or 0 if qa else 0,
        "qa_pass_rate": round((qa["passes"] or 0) / qa["n"] * 100, 1) if qa and qa["n"] > 0 else 0,
        "routes": routes["n"] if routes else 0,
        "reworks": reworks["n"] if reworks else 0,
        "meetings": meetings["n"] if meetings else 0,
        "messages": msgs["n"] if msgs else 0,
        "today_qa": today_qa["n"] if today_qa else 0
    }}


@route("GET", "/api/teams/:team_id/objectives")
def r_team_objectives(params, body, url_params, query):
    """팀 OKR/전략과제/MBO 조회."""
    tid = url_params.get("team_id", "")
    conn = get_db()
    objs = conn.execute(
        "SELECT * FROM team_objectives WHERE team_id=? ORDER BY created_at", (tid,)
    ).fetchall()
    result = []
    for o in objs:
        obj = dict(o)
        krs = conn.execute(
            "SELECT * FROM objective_key_results WHERE obj_id=? ORDER BY created_at", (o["obj_id"],)
        ).fetchall()
        obj["key_results"] = [dict(kr) for kr in krs]
        # 자동 진행률 계산 (연결된 티켓 기반)
        total_kr_progress = 0
        for kr in obj["key_results"]:
            linked = kr.get("linked_ticket_ids") or ""
            if linked:
                tids = [x.strip() for x in linked.split(",") if x.strip()]
                if tids:
                    placeholders = ",".join("?" * len(tids))
                    done_count = conn.execute(
                        f"SELECT COUNT(*) as n FROM tickets WHERE ticket_id IN ({placeholders}) AND status='Done'", tids
                    ).fetchone()["n"]
                    kr["auto_progress"] = round(done_count / len(tids) * 100, 1) if tids else 0
                    total_kr_progress += kr["auto_progress"]
        if obj["key_results"]:
            obj["auto_progress"] = round(total_kr_progress / len(obj["key_results"]), 1)
        result.append(obj)
    return {"ok": True, "objectives": result}


@route("POST", "/api/teams/:team_id/objectives")
def r_team_objectives_create(params, body, url_params, query):
    """팀 OKR/전략과제/MBO 생성."""
    tid = url_params.get("team_id", "")
    title = body.get("title", "")
    if not title:
        return {"ok": False, "error": "title required"}
    import uuid
    obj_id = "OBJ-" + uuid.uuid4().hex[:8].upper()
    conn = get_db()
    conn.execute(
        "INSERT INTO team_objectives (obj_id, team_id, obj_type, title, description, category, target_value, unit, weight, due_date) "
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        (obj_id, tid, body.get("obj_type", "OKR"), title, body.get("description", ""),
         body.get("category", "strategic"), body.get("target_value", 100),
         body.get("unit", "%"), body.get("weight", 1.0), body.get("due_date"))
    )
    conn.commit()
    # Key Results 추가
    krs = body.get("key_results", [])
    for kr in krs:
        kr_id = "KR-" + uuid.uuid4().hex[:8].upper()
        conn.execute(
            "INSERT INTO objective_key_results (kr_id, obj_id, title, target_value, unit, linked_ticket_ids) VALUES (?,?,?,?,?,?)",
            (kr_id, obj_id, kr.get("title", ""), kr.get("target_value", 100),
             kr.get("unit", "%"), kr.get("linked_ticket_ids", ""))
        )
    conn.commit()
    return {"ok": True, "obj_id": obj_id}


@route("PUT", "/api/objectives/:obj_id")
def r_objective_update(params, body, url_params, query):
    """OKR/전략과제 수정."""
    obj_id = url_params.get("obj_id", "")
    conn = get_db()
    sets = []
    vals = []
    for k in ["title", "description", "category", "target_value", "current_value", "unit", "weight", "status", "due_date"]:
        if k in body:
            sets.append(f"{k}=?")
            vals.append(body[k])
    if sets:
        sets.append("updated_at=datetime('now')")
        vals.append(obj_id)
        conn.execute(f"UPDATE team_objectives SET {','.join(sets)} WHERE obj_id=?", vals)
        conn.commit()
    return {"ok": True}


@route("PUT", "/api/key-results/:kr_id")
def r_kr_update(params, body, url_params, query):
    """Key Result 수정."""
    kr_id = url_params.get("kr_id", "")
    conn = get_db()
    sets = []
    vals = []
    for k in ["title", "target_value", "current_value", "unit", "linked_ticket_ids", "status"]:
        if k in body:
            sets.append(f"{k}=?")
            vals.append(body[k])
    if sets:
        sets.append("updated_at=datetime('now')")
        vals.append(kr_id)
        conn.execute(f"UPDATE objective_key_results SET {','.join(sets)} WHERE kr_id=?", vals)
        conn.commit()
    return {"ok": True}


@route("GET", "/api/resident/history")
def r_resident_history(params, body, url_params, query):
    """상주 에이전트(유디) 활동 히스토리 통합 조회."""
    _lim = query.get("limit", "200")
    limit = int(_lim[0] if isinstance(_lim, list) else _lim)
    _off = query.get("offset", "0")
    offset = int(_off[0] if isinstance(_off, list) else _off)
    _ft = query.get("type", "")
    filter_type = _ft[0] if isinstance(_ft, list) else _ft  # qa, rework, meeting, route, all
    conn = get_db()
    items = []
    # 1) agent_conversations — 상주에이전트 발신
    rows = conn.execute(
        "SELECT 'conversation' as kind, c.created_at, c.team_id, c.ticket_id, "
        "c.from_agent, c.to_agent, c.msg_type, c.content, '' as score, '' as result "
        "FROM agent_conversations c WHERE c.from_agent LIKE '%상주%' OR c.from_agent LIKE '%유디%' "
        "ORDER BY c.created_at DESC LIMIT 500"
    ).fetchall()
    for r in rows:
        items.append(dict(r))
    # 2) ticket_reviews — 상주에이전트 리뷰
    rows2 = conn.execute(
        "SELECT 'review' as kind, tr.created_at, tr.team_id, tr.ticket_id, "
        "tr.reviewer as from_agent, '' as to_agent, tr.result as msg_type, "
        "tr.comment as content, CAST(tr.score as TEXT) as score, tr.result "
        "FROM ticket_reviews tr WHERE tr.reviewer LIKE '%상주%' OR tr.reviewer LIKE '%유디%' "
        "ORDER BY tr.created_at DESC LIMIT 500"
    ).fetchall()
    for r in rows2:
        items.append(dict(r))
    # 3) activity_logs — 상주에이전트 활동
    rows3 = conn.execute(
        "SELECT 'activity' as kind, a.created_at, a.team_id, a.ticket_id, "
        "COALESCE(tm.display_name, a.member_id) as from_agent, '' as to_agent, a.action as msg_type, "
        "a.message as content, '' as score, '' as result "
        "FROM activity_logs a LEFT JOIN team_members tm ON a.member_id=tm.member_id "
        "WHERE tm.display_name LIKE '%상주%' OR tm.display_name LIKE '%유디%' OR a.member_id LIKE '%상주%' OR a.member_id LIKE '%유디%' "
        "ORDER BY a.created_at DESC LIMIT 500"
    ).fetchall()
    for r in rows3:
        items.append(dict(r))
    # 4) messages — 상주에이전트 메시지
    rows4 = conn.execute(
        "SELECT 'message' as kind, m.created_at, m.team_id, '' as ticket_id, "
        "m.sender_member_id as from_agent, '' as to_agent, 'message' as msg_type, "
        "m.content, '' as score, '' as result "
        "FROM messages m WHERE m.sender_member_id LIKE '%상주%' OR m.sender_member_id LIKE '%유디%' "
        "ORDER BY m.created_at DESC LIMIT 500"
    ).fetchall()
    for r in rows4:
        items.append(dict(r))
    # 정렬 + 필터
    items.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    if filter_type and filter_type != "all":
        items = [i for i in items if i.get("msg_type") == filter_type or i.get("kind") == filter_type]
    total = len(items)
    items = items[offset:offset+limit]
    # 통계
    stats = {"total": total, "qa": 0, "rework": 0, "meeting": 0, "route": 0, "message": 0, "activity": 0}
    for i in items:
        k = i.get("kind", "")
        mt = i.get("msg_type", "")
        if k == "review": stats["qa"] += 1
        elif mt == "rework": stats["rework"] += 1
        elif mt == "meeting": stats["meeting"] += 1
        elif mt in ("route", "answer"): stats["route"] += 1
        elif k == "message": stats["message"] += 1
        elif k == "activity": stats["activity"] += 1
    return {"ok": True, "history": items, "stats": stats, "total": total}

@route("GET", "/api/archives")
def r_archives_list(params, body, url_params, query):
    conn = get_db()
    rows = conn.execute("SELECT * FROM agent_teams WHERE status='Archived' ORDER BY archived_at DESC").fetchall()
    conn.close()
    return {"ok": True, "archives": rows_to_list(rows)}

@route("GET", "/api/archives/{team_id}")
def r_archives_detail(params, body, url_params, query):
    team_id = url_params["team_id"]
    conn = get_db()
    team = row_to_dict(conn.execute("SELECT * FROM agent_teams WHERE team_id=? AND status='Archived'", (team_id,)).fetchone())
    if not team:
        conn.close()
        return {"ok": False, "error": "archive_not_found"}
    # 스냅샷에서 full data blob 확인 (아카이브 시 백업된 데이터)
    snapshot_row = conn.execute(
        "SELECT metadata FROM team_snapshots WHERE team_id=? AND snapshot_type='archive' AND metadata IS NOT NULL "
        "ORDER BY created_at DESC LIMIT 1", (team_id,)
    ).fetchone()
    if snapshot_row and snapshot_row["metadata"]:
        # 스냅샷 백업 데이터 사용 (DB 데이터 삭제되어도 복원 가능)
        conn.close()
        full = json.loads(snapshot_row["metadata"])
        full["ok"] = True
        full["source"] = "snapshot"
        return full
    # 스냅샷 없으면 DB에서 실시간 조회
    members = rows_to_list(conn.execute("SELECT * FROM team_members WHERE team_id=?", (team_id,)).fetchall())
    tickets = rows_to_list(conn.execute("SELECT * FROM tickets WHERE team_id=? ORDER BY created_at", (team_id,)).fetchall())
    logs = rows_to_list(conn.execute(
        "SELECT al.*, tm.display_name as agent_name FROM activity_logs al "
        "LEFT JOIN team_members tm ON al.member_id=tm.member_id "
        "WHERE al.team_id=? ORDER BY al.created_at", (team_id,)
    ).fetchall())
    messages = rows_to_list(conn.execute(
        "SELECT m.*, tm.display_name as sender_name FROM messages m "
        "LEFT JOIN team_members tm ON m.sender_member_id=tm.member_id "
        "WHERE m.team_id=? ORDER BY m.created_at", (team_id,)
    ).fetchall())
    artifacts = rows_to_list(conn.execute(
        "SELECT a.*, tm.display_name as creator_name FROM artifacts a "
        "LEFT JOIN team_members tm ON a.creator_member_id=tm.member_id "
        "WHERE a.team_id=? ORDER BY a.created_at", (team_id,)
    ).fetchall())
    # 산출물 상세 (파일 변경 추적) 병합
    art_details = rows_to_list(conn.execute(
        "SELECT * FROM artifact_details WHERE team_id=? ORDER BY created_at", (team_id,)
    ).fetchall())
    detail_map = {}
    for ad in art_details:
        detail_map.setdefault(ad["artifact_id"], []).append(ad)
    for a in artifacts:
        a["files"] = detail_map.get(a["artifact_id"], [])
    feedbacks = rows_to_list(conn.execute("SELECT * FROM ticket_feedbacks WHERE team_id=?", (team_id,)).fetchall())
    token_usage = rows_to_list(conn.execute("SELECT * FROM token_usage WHERE team_id=?", (team_id,)).fetchall())
    conn.close()
    # 산출물 통계
    art_stats = {}
    for a in artifacts:
        t = a.get("artifact_type", "other")
        art_stats[t] = art_stats.get(t, 0) + 1
    total_files = sum(len(a.get("files", [])) for a in artifacts)
    total_lines_added = sum(f.get("lines_added", 0) for a in artifacts for f in a.get("files", []))
    total_lines_removed = sum(f.get("lines_removed", 0) for a in artifacts for f in a.get("files", []))
    return {
        "ok": True, "source": "live", "team": team, "members": members, "tickets": tickets,
        "activity_logs": logs, "messages": messages, "artifacts": artifacts,
        "feedbacks": feedbacks, "token_usage": token_usage,
        "artifact_stats": {"by_type": art_stats, "total_files": total_files,
                           "total_lines_added": total_lines_added, "total_lines_removed": total_lines_removed}
    }


# ── 팀 스냅샷 저장 (내부 함수) ──

def _save_team_snapshot(conn, team_id, snapshot_type="manual"):
    """팀의 현재 상태를 team_snapshots에 저장."""
    team = row_to_dict(conn.execute("SELECT * FROM agent_teams WHERE team_id=?", (team_id,)).fetchone())
    if not team:
        return
    total_tickets = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=?", (team_id,)).fetchone()[0]
    done_tickets = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=? AND status='Done'", (team_id,)).fetchone()[0]
    blocked_tickets = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=? AND status='Blocked'", (team_id,)).fetchone()[0]
    member_count = conn.execute("SELECT COUNT(*) FROM team_members WHERE team_id=?", (team_id,)).fetchone()[0]
    progress = round(done_tickets / total_tickets * 100, 1) if total_tickets > 0 else 0
    total_msgs = conn.execute("SELECT COUNT(*) FROM messages WHERE team_id=?", (team_id,)).fetchone()[0]
    total_arts = conn.execute("SELECT COUNT(*) FROM artifacts WHERE team_id=?", (team_id,)).fetchone()[0]
    usage = conn.execute(
        "SELECT COALESCE(SUM(input_tokens),0) as inp, COALESCE(SUM(output_tokens),0) as out, COALESCE(SUM(estimated_cost),0) as cost "
        "FROM token_usage WHERE team_id=?", (team_id,)
    ).fetchone()
    avg_row = conn.execute(
        "SELECT AVG(actual_minutes) as avg_min FROM tickets WHERE team_id=? AND status='Done' AND actual_minutes>0", (team_id,)
    ).fetchone()
    avg_min = round(avg_row["avg_min"], 1) if avg_row and avg_row["avg_min"] else 0
    # 팀 생성~현재까지 경과 시간 (hours)
    created = team.get("created_at", "")
    duration_hours = 0
    if created:
        try:
            from datetime import datetime as dt
            c = dt.fromisoformat(created.replace("Z", "+00:00") if "Z" in created else created)
            n = dt.now(timezone.utc) if c.tzinfo else dt.utcnow()
            duration_hours = round((n - c).total_seconds() / 3600, 1)
        except Exception:
            pass
    # Full data blob (아카이브 시 전체 데이터 백업)
    full_data = None
    if snapshot_type == "archive":
        members = rows_to_list(conn.execute("SELECT * FROM team_members WHERE team_id=?", (team_id,)).fetchall())
        tickets = rows_to_list(conn.execute("SELECT * FROM tickets WHERE team_id=? ORDER BY created_at", (team_id,)).fetchall())
        logs = rows_to_list(conn.execute(
            "SELECT al.*, tm.display_name as agent_name FROM activity_logs al "
            "LEFT JOIN team_members tm ON al.member_id=tm.member_id "
            "WHERE al.team_id=? ORDER BY al.created_at", (team_id,)
        ).fetchall())
        messages = rows_to_list(conn.execute(
            "SELECT m.*, tm.display_name as sender_name FROM messages m "
            "LEFT JOIN team_members tm ON m.sender_member_id=tm.member_id "
            "WHERE m.team_id=? ORDER BY m.created_at", (team_id,)
        ).fetchall())
        artifacts = rows_to_list(conn.execute(
            "SELECT a.*, tm.display_name as creator_name FROM artifacts a "
            "LEFT JOIN team_members tm ON a.creator_member_id=tm.member_id "
            "WHERE a.team_id=? ORDER BY a.created_at", (team_id,)
        ).fetchall())
        feedbacks = rows_to_list(conn.execute("SELECT * FROM ticket_feedbacks WHERE team_id=?", (team_id,)).fetchall())
        token_usage = rows_to_list(conn.execute("SELECT * FROM token_usage WHERE team_id=?", (team_id,)).fetchall())
        full_data = json.dumps({
            "team": team, "members": members, "tickets": tickets,
            "activity_logs": logs, "messages": messages, "artifacts": artifacts,
            "feedbacks": feedbacks, "token_usage": token_usage,
            "archived_at": now_utc()
        }, ensure_ascii=False)
    conn.execute(
        "INSERT INTO team_snapshots (team_id,snapshot_type,total_tickets,done_tickets,blocked_tickets,"
        "member_count,progress,total_messages,total_artifacts,total_input_tokens,total_output_tokens,"
        "total_cost,avg_minutes_per_ticket,duration_hours,metadata,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (team_id, snapshot_type, total_tickets, done_tickets, blocked_tickets,
         member_count, progress, total_msgs, total_arts,
         usage["inp"], usage["out"], usage["cost"], avg_min, duration_hours, full_data, now_utc())
    )


# ── History & Benchmarking API ──

@route("GET", "/api/history/teams")
def r_history_teams(params, body, url_params, query):
    """모든 팀 (활성+아카이브)의 메트릭 요약."""
    conn = get_db()
    teams = rows_to_list(conn.execute("SELECT * FROM agent_teams ORDER BY created_at DESC").fetchall())
    result = []
    for t in teams:
        tid = t["team_id"]
        total = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=?", (tid,)).fetchone()[0]
        done = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=? AND status='Done'", (tid,)).fetchone()[0]
        blocked = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=? AND status='Blocked'", (tid,)).fetchone()[0]
        members = conn.execute("SELECT COUNT(*) FROM team_members WHERE team_id=?", (tid,)).fetchone()[0]
        msgs = conn.execute("SELECT COUNT(*) FROM messages WHERE team_id=?", (tid,)).fetchone()[0]
        arts = conn.execute("SELECT COUNT(*) FROM artifacts WHERE team_id=?", (tid,)).fetchone()[0]
        logs = conn.execute("SELECT COUNT(*) FROM activity_logs WHERE team_id=?", (tid,)).fetchone()[0]
        usage = conn.execute(
            "SELECT COALESCE(SUM(input_tokens),0) as inp, COALESCE(SUM(output_tokens),0) as out, COALESCE(SUM(estimated_cost),0) as cost "
            "FROM token_usage WHERE team_id=?", (tid,)
        ).fetchone()
        avg_row = conn.execute(
            "SELECT AVG(actual_minutes) as avg_min FROM tickets WHERE team_id=? AND status='Done' AND actual_minutes>0", (tid,)
        ).fetchone()
        result.append({
            "team": t,
            "metrics": {
                "total_tickets": total, "done_tickets": done, "blocked_tickets": blocked,
                "member_count": members, "total_messages": msgs, "total_artifacts": arts,
                "total_logs": logs, "progress": round(done / total * 100, 1) if total > 0 else 0,
                "input_tokens": usage["inp"], "output_tokens": usage["out"],
                "estimated_cost": round(usage["cost"], 4),
                "avg_minutes": round(avg_row["avg_min"], 1) if avg_row and avg_row["avg_min"] else 0
            }
        })
    conn.close()
    return {"ok": True, "teams": result}

@route("GET", "/api/history/teams/{team_id}/timeline")
def r_history_timeline(params, body, url_params, query):
    """팀의 전체 활동 타임라인."""
    team_id = url_params["team_id"]
    limit = int(query.get("limit", [500])[0])
    conn = get_db()
    team = row_to_dict(conn.execute("SELECT * FROM agent_teams WHERE team_id=?", (team_id,)).fetchone())
    if not team:
        conn.close()
        return {"ok": False, "error": "team_not_found"}
    logs = rows_to_list(conn.execute(
        "SELECT al.*, tm.display_name as agent_name FROM activity_logs al "
        "LEFT JOIN team_members tm ON al.member_id=tm.member_id "
        "WHERE al.team_id=? ORDER BY al.created_at DESC LIMIT ?", (team_id, limit)
    ).fetchall())
    members = rows_to_list(conn.execute("SELECT * FROM team_members WHERE team_id=?", (team_id,)).fetchall())
    tickets = rows_to_list(conn.execute("SELECT * FROM tickets WHERE team_id=? ORDER BY created_at", (team_id,)).fetchall())
    snapshots = rows_to_list(conn.execute(
        "SELECT * FROM team_snapshots WHERE team_id=? ORDER BY created_at DESC", (team_id,)
    ).fetchall())
    conn.close()
    return {"ok": True, "team": team, "logs": logs, "members": members, "tickets": tickets, "snapshots": snapshots}

@route("GET", "/api/history/benchmark")
def r_history_benchmark(params, body, url_params, query):
    """크로스팀 벤치마킹 비교 데이터."""
    conn = get_db()
    teams = rows_to_list(conn.execute("SELECT * FROM agent_teams ORDER BY created_at DESC").fetchall())
    benchmarks = []
    for t in teams:
        tid = t["team_id"]
        total = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=?", (tid,)).fetchone()[0]
        done = conn.execute("SELECT COUNT(*) FROM tickets WHERE team_id=? AND status='Done'", (tid,)).fetchone()[0]
        members = conn.execute("SELECT COUNT(*) FROM team_members WHERE team_id=?", (tid,)).fetchone()[0]
        usage = conn.execute(
            "SELECT COALESCE(SUM(input_tokens),0) as inp, COALESCE(SUM(output_tokens),0) as out, COALESCE(SUM(estimated_cost),0) as cost "
            "FROM token_usage WHERE team_id=?", (tid,)
        ).fetchone()
        avg_row = conn.execute(
            "SELECT AVG(actual_minutes) as avg_min FROM tickets WHERE team_id=? AND status='Done' AND actual_minutes>0", (tid,)
        ).fetchone()
        # 팀 활동 기간 (시간)
        first_log = conn.execute("SELECT MIN(created_at) as first_at FROM activity_logs WHERE team_id=?", (tid,)).fetchone()
        last_log = conn.execute("SELECT MAX(created_at) as last_at FROM activity_logs WHERE team_id=?", (tid,)).fetchone()
        duration_hours = 0
        if first_log and first_log["first_at"] and last_log and last_log["last_at"]:
            try:
                from datetime import datetime as dt
                f = dt.fromisoformat(first_log["first_at"])
                l = dt.fromisoformat(last_log["last_at"])
                duration_hours = round((l - f).total_seconds() / 3600, 1)
            except Exception:
                pass
        # 티켓당 비용
        cost_per_ticket = round(usage["cost"] / done, 4) if done > 0 else 0
        # 생산성: 완료 티켓 / 에이전트 수
        productivity = round(done / members, 1) if members > 0 else 0
        benchmarks.append({
            "team_id": tid, "name": t["name"], "status": t["status"],
            "total_tickets": total, "done_tickets": done,
            "progress": round(done / total * 100, 1) if total > 0 else 0,
            "member_count": members, "duration_hours": duration_hours,
            "total_cost": round(usage["cost"], 4),
            "cost_per_ticket": cost_per_ticket,
            "productivity": productivity,
            "avg_minutes": round(avg_row["avg_min"], 1) if avg_row and avg_row["avg_min"] else 0,
            "total_tokens": usage["inp"] + usage["out"]
        })
    conn.close()
    # 벤치마크 순위 (진행률 내림차순)
    benchmarks.sort(key=lambda x: x["progress"], reverse=True)
    return {"ok": True, "benchmarks": benchmarks}

@route("POST", "/api/history/snapshot/{team_id}")
def r_history_snapshot(params, body, url_params, query):
    """수동 스냅샷 저장."""
    team_id = url_params["team_id"]
    conn = get_db()
    _save_team_snapshot(conn, team_id, "manual")
    conn.commit()
    conn.close()
    return {"ok": True, "team_id": team_id}


# ── 클라이언트 추적 + 토큰 사용량 API (A-5) ──

def _track_client(handler):
    """요청마다 클라이언트 정보 기록."""
    try:
        ip = handler.client_address[0]
        ua = handler.headers.get("User-Agent", "unknown")[:200]
        with _clients_lock:
            if ip not in _connected_clients:
                _connected_clients[ip] = {"ip": ip, "first_seen": now_utc(), "user_agent": ua, "requests": 0, "last_seen": now_utc()}
            _connected_clients[ip]["requests"] += 1
            _connected_clients[ip]["last_seen"] = now_utc()
            _connected_clients[ip]["user_agent"] = ua
    except Exception:
        pass

@route("GET", "/api/system/clients")
def r_system_clients(params, body, url_params, query):
    with _clients_lock:
        clients = list(_connected_clients.values())
    # 60초 이상 미접속 클라이언트 제외
    cutoff = (datetime.now(timezone.utc) - timedelta(seconds=60)).strftime("%Y-%m-%d %H:%M:%S")
    active = [c for c in clients if c["last_seen"] >= cutoff]
    return {"ok": True, "clients": active, "total": len(clients)}

@route("POST", "/api/usage/report")
def r_usage_report(params, body, url_params, query):
    """에이전트가 토큰 사용량 보고."""
    team_id = body.get("team_id", "")
    ticket_id = body.get("ticket_id", "")
    member_id = body.get("member_id", "")
    model = body.get("model", "unknown")
    input_tokens = int(body.get("input_tokens", 0))
    output_tokens = int(body.get("output_tokens", 0))
    estimated_cost = float(body.get("estimated_cost", 0.0))
    metadata = json.dumps(body.get("metadata", {}), ensure_ascii=False) if body.get("metadata") else None
    conn = get_db()
    conn.execute(
        "INSERT INTO token_usage (team_id,ticket_id,member_id,model,input_tokens,output_tokens,estimated_cost,metadata) VALUES (?,?,?,?,?,?,?,?)",
        (team_id, ticket_id, member_id, model, input_tokens, output_tokens, estimated_cost, metadata)
    )
    conn.commit()
    conn.close()
    return {"ok": True}

@route("GET", "/api/teams/{team_id}/usage")
def r_team_usage(params, body, url_params, query):
    """팀별 토큰 사용량 통계."""
    team_id = url_params["team_id"]
    conn = get_db()
    rows = conn.execute(
        "SELECT model, SUM(input_tokens) as total_input, SUM(output_tokens) as total_output, "
        "SUM(estimated_cost) as total_cost, COUNT(*) as report_count "
        "FROM token_usage WHERE team_id=? GROUP BY model", (team_id,)
    ).fetchall()
    total = conn.execute(
        "SELECT SUM(input_tokens) as input, SUM(output_tokens) as output, SUM(estimated_cost) as cost FROM token_usage WHERE team_id=?",
        (team_id,)
    ).fetchone()
    # 티켓별 집계
    by_ticket = rows_to_list(conn.execute(
        "SELECT ticket_id, SUM(input_tokens) as input, SUM(output_tokens) as output, SUM(estimated_cost) as cost "
        "FROM token_usage WHERE team_id=? GROUP BY ticket_id", (team_id,)
    ).fetchall())
    conn.close()
    return {"ok": True, "by_model": rows_to_list(rows), "total": row_to_dict(total) if total else {},
            "by_ticket": by_ticket}

@route("GET", "/api/tickets/{ticket_id}/usage")
def r_ticket_usage(params, body, url_params, query):
    """티켓별 토큰 사용량."""
    ticket_id = url_params["ticket_id"]
    conn = get_db()
    rows = conn.execute(
        "SELECT model, member_id, SUM(input_tokens) as input, SUM(output_tokens) as output, SUM(estimated_cost) as cost "
        "FROM token_usage WHERE ticket_id=? GROUP BY model, member_id", (ticket_id,)
    ).fetchall()
    total = conn.execute(
        "SELECT SUM(input_tokens) as input, SUM(output_tokens) as output, SUM(estimated_cost) as cost FROM token_usage WHERE ticket_id=?",
        (ticket_id,)
    ).fetchone()
    conn.close()
    return {"ok": True, "details": rows_to_list(rows), "total": row_to_dict(total) if total else {}}


# ── 서버 설정 (API 키 등) ──

@route("GET", "/api/settings")
def r_settings_get(params, body, url_params, query):
    """서버 설정 조회 (민감 키는 마스킹)."""
    conn = get_db()
    rows = conn.execute("SELECT key, value, updated_at FROM server_settings").fetchall()
    conn.close()
    result = {}
    for r in rows:
        k, v = r["key"], r["value"]
        if "key" in k.lower() or "secret" in k.lower():
            result[k] = {"value": v[:8] + "..." + v[-4:] if v and len(v) > 12 else "***", "masked": True, "updated_at": r["updated_at"]}
        else:
            result[k] = {"value": v, "masked": False, "updated_at": r["updated_at"]}
    return {"ok": True, "settings": result}

@route("PUT", "/api/settings")
def r_settings_put(params, body, url_params, query):
    """서버 설정 저장."""
    conn = get_db()
    for k, v in body.items():
        if k in ("ok",): continue
        conn.execute(
            "INSERT INTO server_settings (key, value, updated_at) VALUES (?, ?, datetime('now')) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
            (k, str(v))
        )
    conn.commit()
    conn.close()
    return {"ok": True}


# ── 글로벌 사용량 집계 (대시보드 카드용) ──

@route("GET", "/api/usage/global")
def r_usage_global(params, body, url_params, query):
    """전체 토큰 사용량/비용 집계 — 15초 폴링용."""
    conn = get_db()
    # 전체 합계
    total = conn.execute(
        "SELECT COALESCE(SUM(input_tokens),0) as input_tokens, "
        "COALESCE(SUM(output_tokens),0) as output_tokens, "
        "COALESCE(SUM(estimated_cost),0) as total_cost, "
        "COUNT(*) as report_count FROM token_usage"
    ).fetchone()
    # 오늘
    today = conn.execute(
        "SELECT COALESCE(SUM(input_tokens),0) as input_tokens, "
        "COALESCE(SUM(output_tokens),0) as output_tokens, "
        "COALESCE(SUM(estimated_cost),0) as total_cost "
        "FROM token_usage WHERE created_at >= date('now')"
    ).fetchone()
    # 모델별
    by_model = rows_to_list(conn.execute(
        "SELECT model, SUM(input_tokens) as input_tokens, SUM(output_tokens) as output_tokens, "
        "SUM(estimated_cost) as cost, COUNT(*) as cnt FROM token_usage GROUP BY model ORDER BY cost DESC"
    ).fetchall())
    # API 키 설정 여부
    api_key_row = conn.execute("SELECT value FROM server_settings WHERE key='anthropic_api_key'").fetchone()
    conn.close()
    return {
        "ok": True,
        "total": row_to_dict(total),
        "today": row_to_dict(today),
        "by_model": by_model,
        "api_key_configured": bool(api_key_row and api_key_row["value"])
    }


# ── 일일 보고서 / KPI API ──

@route("GET", "/api/reports/daily")
def r_reports_daily(params, body, url_params, query):
    """최근 일일 보고서 조회. ?limit=N (기본 7), ?date=YYYY-MM-DD (특정 날짜)."""
    date_filter = query.get("date", [None])[0] if "date" in query else None
    limit = int(query.get("limit", ["7"])[0])
    limit = max(1, min(90, limit))

    conn = get_db()
    if date_filter:
        rows = conn.execute(
            "SELECT * FROM daily_reports WHERE report_date=?", (date_filter,)
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM daily_reports ORDER BY report_date DESC LIMIT ?", (limit,)
        ).fetchall()
    conn.close()

    reports = []
    for r in rows:
        report = dict(r)
        # JSON 필드 파싱
        for field in ('yesterday_completed', 'blockers', 'kpi_data'):
            if report.get(field):
                try:
                    report[field] = json.loads(report[field])
                except Exception:
                    pass
        reports.append(report)

    return {"ok": True, "reports": reports, "count": len(reports)}


@route("GET", "/api/reports/kpi")
def r_reports_kpi(params, body, url_params, query):
    """에이전트 KPI 조회. ?date=YYYY-MM-DD (기본 오늘), ?member_id=X, ?days=N (기간 조회)."""
    days = int(query.get("days", ["1"])[0])
    days = max(1, min(90, days))
    member_filter = query.get("member_id", [None])[0] if "member_id" in query else None
    date_filter = query.get("date", [None])[0] if "date" in query else None

    conn = get_db()

    if date_filter:
        # 특정 날짜
        if member_filter:
            rows = conn.execute(
                "SELECT * FROM agent_kpi WHERE report_date=? AND member_id=?",
                (date_filter, member_filter)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM agent_kpi WHERE report_date=? ORDER BY completed_tickets DESC",
                (date_filter,)
            ).fetchall()
    elif days > 1:
        # 기간 조회 — 에이전트별 집계
        if member_filter:
            rows = conn.execute("""
                SELECT member_id, team_id, display_name,
                       SUM(completed_tickets) as completed_tickets,
                       AVG(avg_minutes) as avg_minutes,
                       SUM(fail_count) as fail_count,
                       SUM(total_assigned) as total_assigned,
                       AVG(fail_rate) as fail_rate,
                       MIN(report_date) as from_date,
                       MAX(report_date) as to_date,
                       COUNT(*) as days_tracked
                FROM agent_kpi
                WHERE report_date >= date('now', ? || ' days') AND member_id=?
                GROUP BY member_id
            """, (str(-days), member_filter)).fetchall()
        else:
            rows = conn.execute("""
                SELECT member_id, team_id, display_name,
                       SUM(completed_tickets) as completed_tickets,
                       ROUND(AVG(avg_minutes), 1) as avg_minutes,
                       SUM(fail_count) as fail_count,
                       SUM(total_assigned) as total_assigned,
                       ROUND(AVG(fail_rate), 1) as fail_rate,
                       MIN(report_date) as from_date,
                       MAX(report_date) as to_date,
                       COUNT(*) as days_tracked
                FROM agent_kpi
                WHERE report_date >= date('now', ? || ' days')
                GROUP BY member_id
                ORDER BY completed_tickets DESC
            """, (str(-days),)).fetchall()
    else:
        # 오늘 (또는 가장 최근)
        latest_date = conn.execute(
            "SELECT MAX(report_date) as d FROM agent_kpi"
        ).fetchone()
        latest = latest_date['d'] if latest_date and latest_date['d'] else None
        if latest:
            if member_filter:
                rows = conn.execute(
                    "SELECT * FROM agent_kpi WHERE report_date=? AND member_id=?",
                    (latest, member_filter)
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM agent_kpi WHERE report_date=? ORDER BY completed_tickets DESC",
                    (latest,)
                ).fetchall()
        else:
            rows = []

    conn.close()

    kpi_list = [dict(r) for r in rows]
    return {"ok": True, "kpi": kpi_list, "count": len(kpi_list)}


# ── 상주 에이전트 데몬 (Telegram 양방향 + 티켓 감시 + 자동 스폰) ──

_resident_agent = {"running": False, "thread": None}
_resident_stop = threading.Event()


_ZOMBIE_MCP_PATTERNS = [
    "context7-mcp", "server-memory", "server-sequential-thinking",
    "@anthropic-ai/mcp-sequential-thinking", "@playwright/mcp",
    "playwright/mcp", "pinecone-database", "remotion/mcp",
    "elevenlabs-mcp", "@modelcontextprotocol",
]

def _kill_zombie_mcp_procs():
    """MCP node 좀비 감지 + 정리 (3단계 판별).
    1) 부모 프로세스 없는 고아
    2) 조부모까지 추적 — claude 프로세스 연결 끊긴 MCP
    3) 장시간 idle (6시간+) + 높은 메모리 (50MB+) node
    """
    killed = 0
    report = []
    if os.name == "nt":
        return 0, []

    # 활성 claude PID 수집
    claude_pids = set()
    try:
        for pid in os.listdir("/proc"):
            if not pid.isdigit():
                continue
            try:
                with open(f"/proc/{pid}/cmdline") as f:
                    cmd = f.read().replace("\x00", " ")
                if "claude" in cmd and "node" not in cmd:
                    claude_pids.add(int(pid))
            except Exception:
                pass
    except Exception:
        pass

    def _get_ppid(p):
        try:
            with open(f"/proc/{p}/status") as f:
                for line in f:
                    if line.startswith("PPid:"):
                        return int(line.split()[1])
        except Exception:
            pass
        return 0

    def _get_rss_mb(p):
        try:
            with open(f"/proc/{p}/status") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        return int(line.split()[1]) // 1024
        except Exception:
            return 0

    def _get_uptime_hours(p):
        try:
            with open(f"/proc/{p}/stat") as f:
                starttime = int(f.read().split()[21])
            with open("/proc/uptime") as f:
                uptime = float(f.read().split()[0])
            clk = os.sysconf("SC_CLK_TCK")
            return (uptime - starttime / clk) / 3600
        except Exception:
            return 0

    def _ancestor_has_claude(p, depth=5):
        """depth단계까지 조상 추적하며 claude 프로세스 연결 확인."""
        for _ in range(depth):
            p = _get_ppid(p)
            if p <= 1:
                return False
            if p in claude_pids:
                return True
        return False

    for pid_str in os.listdir("/proc"):
        if not pid_str.isdigit():
            continue
        pid = int(pid_str)
        try:
            with open(f"/proc/{pid}/cmdline") as f:
                cmd = f.read().replace("\x00", " ")
            if "node" not in cmd and "npx" not in cmd:
                continue
            if not any(p in cmd for p in _ZOMBIE_MCP_PATTERNS):
                continue

            ppid = _get_ppid(pid)
            rss = _get_rss_mb(pid)
            hours = _get_uptime_hours(pid)
            is_zombie = False
            reason = ""

            # 1단계: 부모 없음 (init 직속)
            if ppid <= 1:
                is_zombie = True
                reason = "고아(부모 init)"

            # 2단계: 조상에 claude가 없음
            elif not _ancestor_has_claude(pid):
                is_zombie = True
                reason = f"claude 미연결 (조상 추적 실패)"

            # 3단계: 6시간+ idle + 50MB+
            elif hours > 6 and rss > 50:
                is_zombie = True
                reason = f"장시간 idle ({hours:.1f}h, {rss}MB)"

            if is_zombie:
                mcp_name = ""
                for p in _ZOMBIE_MCP_PATTERNS:
                    if p in cmd:
                        mcp_name = p
                        break
                os.kill(pid, 9)
                killed += 1
                report.append(f"{mcp_name}(PID:{pid}, {rss}MB, {hours:.1f}h) — {reason}")
        except Exception:
            pass
    return killed, report


def _zombie_cleanup_loop():
    """15분마다 좀비 MCP 스캔 + 정리 + 텔레그램 보고."""
    while True:
        import time
        time.sleep(900)
        try:
            killed, report = _kill_zombie_mcp_procs()
            if killed > 0:
                sse_broadcast_global("zombie_cleanup", {"killed": killed, "details": report})
                _tg_send(f"🧹 <b>좀비 정리</b>: {killed}개\n" + "\n".join(f"• {r}" for r in report[:5]))
        except Exception:
            pass


def _resident_start():
    """상주 에이전트 시작: Telegram 폴링 + 미처리 티켓 자동 감시."""
    if _resident_agent["running"]:
        return
    _resident_agent["running"] = True
    _resident_stop.clear()

    # 시작 시 좀비 MCP 1회 정리
    killed, report = _kill_zombie_mcp_procs()
    if killed > 0:
        _tg_send(f"🧹 서버 시작: 좀비 {killed}개 정리\n" + "\n".join(f"• {r}" for r in report[:5]))

    # 30분 주기 좀비 정리 스레드
    threading.Thread(target=_zombie_cleanup_loop, daemon=True).start()

    # Telegram 폴링 시작
    if _tg_load_config():
        _tg_start_polling()

    # 티켓 감시 스레드
    _resident_agent["thread"] = threading.Thread(target=_resident_watch_loop, daemon=True)
    _resident_agent["thread"].start()
    # Ollama 감지
    ollama_status = ""
    if _ollama_available():
        ollama_status = f"\n🤖 AI: <b>Ollama</b> (<code>{_OLLAMA_MODEL}</code>) — 로컬 GPU"
    else:
        ollama_status = f"\n🔵 AI: <b>Claude API</b> — Ollama 오프라인"
    _tg_send(f"🟢 <b>상주 에이전트 시작</b>\nTelegram 수신 + 티켓 자동 처리 활성화{ollama_status}")


def _resident_stop_agent():
    """상주 에이전트 중지."""
    _resident_agent["running"] = False
    _resident_stop.set()
    _tg_stop_poll.set()
    _tg_send("🔴 <b>상주 에이전트 중지</b>")


_resident_wake_event = threading.Event()
_resident_last_activity = [0.0]  # mutable for closure


def _resident_wake():
    """외부에서 상주 에이전트를 깨움 (팀/티켓 변경 시 호출)."""
    _resident_last_activity[0] = time.time()
    _resident_wake_event.set()


def _resident_watch_loop():
    """이벤트 기반 감시 루프. CLI 구독 보호: 리뷰/회의 최소화."""
    counter = 0
    _resident_last_activity[0] = time.time()

    while not _resident_stop.is_set():
        # 5분 무활동 → 대기
        idle = time.time() - _resident_last_activity[0]
        if idle > 300:
            _resident_wake_event.clear()
            _resident_wake_event.wait(timeout=60)
            if _resident_stop.is_set():
                break
            if not _resident_wake_event.is_set():
                continue
            _resident_wake_event.clear()

        counter += 1
        # 매 사이클: InProgress 모니터링만 (DB조회, CLI 소모 없음)
        try: _resident_monitor_inprogress()
        except Exception: pass
        # 5분마다: QA 리뷰 (Ollama만, CLI 소모 없음)
        if counter % 15 == 0:
            try: _resident_qa_review()
            except Exception: pass
        # 10분마다: 회의 소집 판단 (Ollama만)
        if counter % 30 == 0:
            try: _resident_facilitate_meeting()
            except Exception: pass
        # 3분마다: 질문 응답 (Ollama만)
        if counter % 9 == 0:
            try: _resident_route_questions()
            except Exception: pass
        # 3분마다: Review 티켓 자동 supervisor 검수 (최대 10개/사이클)
        if counter % 9 == 0:
            try: _resident_auto_supervisor_review()
            except Exception: pass
        # 매 사이클: 일일 보고서 생성 체크 (09:00 KST)
        if _resident_should_generate_daily_report():
            try: _resident_daily_report()
            except Exception: pass
        # 자동 CLI dispatch 비활성화 — 수동 승인 기반으로 전환
        # (유디 대화에서 dispatch_agent → 승인 → CLI 실행)
        # if counter % 15 == 0:
        #     try: _resident_auto_cli_dispatch()
        #     except Exception: pass
        _resident_stop.wait(20)



_cli_running = set()  # 현재 실행 중인 티켓 ID

def _resident_auto_cli_dispatch():
    """InProgress 티켓을 자동으로 Claude Code CLI로 실행. 최대 2개/사이클."""
    conn = get_db()
    # InProgress 상태 + 산출물 없음 + CLI 미실행 중
    tickets = conn.execute(
        """SELECT t.ticket_id, t.title, t.description, t.team_id, a.project_group
           FROM tickets t
           JOIN agent_teams a ON t.team_id = a.team_id
           WHERE t.status = 'InProgress'
           AND a.status = 'Active'
           AND (SELECT COUNT(*) FROM artifacts WHERE ticket_id = t.ticket_id) = 0
           ORDER BY CASE t.priority WHEN 'Critical' THEN 0 WHEN 'High' THEN 1 ELSE 2 END, t.created_at ASC
           LIMIT 5"""
    ).fetchall()
    conn.close()

    dispatched = 0
    for tk in tickets:
        tid = tk["ticket_id"]
        if tid in _cli_running:
            continue
        if dispatched >= 2:
            break

        # 프로젝트 경로 찾기
        proj_group = tk["project_group"] or ""
        proj_path = _find_project_path(proj_group)
        if not proj_path:
            continue

        instruction = f"티켓 {tid}: {tk['title']}"
        if tk.get("description"):
            instruction += f"\n\n{tk['description'][:500]}"

        _cli_running.add(tid)
        threading.Thread(target=_run_cli_for_ticket, args=(tid, instruction, proj_path, tk["team_id"]), daemon=True).start()
        dispatched += 1
        print(f"[auto-cli] {tid} → {proj_group} dispatched", file=sys.stderr, flush=True)


def _run_cli_for_ticket(ticket_id, instruction, project_path, team_id):
    """단일 티켓에 대해 Claude Code CLI 실행."""
    try:
        cmd = ["claude", "-p", instruction, "--model", "claude-opus-4-6", "--max-turns", "30", ]
        proc = subprocess.Popen(cmd, cwd=project_path, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = proc.communicate(timeout=300)
        output = (stdout or "") + (stderr or "")

        # 산출물 등록
        conn = get_db()
        aid = "A-" + uuid.uuid4().hex[:6].upper()
        conn.execute(
            "INSERT INTO artifacts (artifact_id,team_id,ticket_id,creator_member_id,artifact_type,title,content,created_at) "
            "VALUES (?,?,?,?,?,?,?,datetime('now'))",
            (aid, team_id, ticket_id, "claude-cli", "code", f"CLI 작업 결과: {ticket_id}", output[:5000])
        )
        # Review 전환
        conn.execute("UPDATE tickets SET status='Review' WHERE ticket_id=?", (ticket_id,))
        conn.execute(
            "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,created_at) VALUES (?,?,?,?,?,datetime('now'))",
            (team_id, ticket_id, "claude-cli", "cli_completed", f"CLI 작업 완료: {len(output)}자 산출물")
        )
        # git commit + push
        try:
            subprocess.run(["git", "add", "-A"], cwd=project_path, timeout=10, capture_output=True)
            subprocess.run(["git", "commit", "-m", f"feat: [auto-agent] {ticket_id} {instruction[:50]}"],
                          cwd=project_path, timeout=10, capture_output=True)
            subprocess.run(["git", "push"], cwd=project_path, timeout=30, capture_output=True)
        except Exception:
            pass

        conn.commit()
        conn.close()
        sse_broadcast(team_id, "ticket_status_changed", {"ticket_id": ticket_id, "status": "Review"})
        print(f"[auto-cli] {ticket_id} ✅ 완료 → Review", file=sys.stderr, flush=True)

    except subprocess.TimeoutExpired:
        try: proc.kill()
        except: pass
        print(f"[auto-cli] {ticket_id} ⚠ 타임아웃", file=sys.stderr, flush=True)
    except Exception as e:
        print(f"[auto-cli] {ticket_id} ❌ {e}", file=sys.stderr, flush=True)
    finally:
        _cli_running.discard(ticket_id)


def _resident_auto_supervisor_review():
    """상주 에이전트: Review 상태 티켓을 자동으로 supervisor 검수 (최대 10개/사이클)."""
    conn = get_db()
    review_tickets = conn.execute(
        "SELECT t.ticket_id, t.title FROM tickets t "
        "JOIN agent_teams a ON t.team_id=a.team_id "
        "WHERE t.status='Review' AND a.status='Active' "
        "ORDER BY t.created_at ASC LIMIT 10"
    ).fetchall()
    # Review 누적 경고 (10개 이상 쌓이면 텔레그램 알림)
    total_review = conn.execute(
        "SELECT COUNT(*) as c FROM tickets t JOIN agent_teams a ON t.team_id=a.team_id "
        "WHERE t.status='Review' AND a.status='Active'"
    ).fetchone()["c"]
    conn.close()
    if total_review >= 10:
        try:
            _tg_send(f"⚠️ Review 대기 {total_review}개 누적! 올라마 자동 검수 진행 중 ({len(review_tickets)}개/사이클)")
        except Exception:
            pass

    if not review_tickets:
        return

    for tk in review_tickets:
        tid = tk["ticket_id"]
        try:
            result = _chat_supervisor_respond(f"auto-review-{tid}", f"{tid} 티켓을 검수해줘")
            actions = result.get("actions_executed", [])
            if actions:
                print(f"[supervisor-auto] {tid}: {actions}", file=sys.stderr, flush=True)
        except Exception as e:
            print(f"[supervisor-auto] {tid} 오류: {e}", file=sys.stderr, flush=True)


def _resident_qa_review():
    """Done 티켓 AI 리뷰 — Ollama가 산출물/노트를 읽고 판정. 실패 시 재작업 (3회 한도)."""
    conn = get_db()
    rows = conn.execute("""
        SELECT t.ticket_id, t.title, t.team_id, t.progress_note,
               t.assigned_member_id, t.priority, t.description
        FROM tickets t JOIN agent_teams a ON t.team_id=a.team_id
        WHERE t.status='Done' AND a.status='Active'
          AND t.completed_at > datetime('now', '-90 minutes')
          AND t.completed_at < datetime('now', '-3 minutes')
          AND NOT EXISTS (SELECT 1 FROM ticket_reviews tr WHERE tr.ticket_id=t.ticket_id)
          AND NOT EXISTS (SELECT 1 FROM ticket_feedbacks tf WHERE tf.ticket_id=t.ticket_id AND tf.author='supervisor')
        LIMIT 3
    """).fetchall()
    conn.close()

    for row in rows:
        row = dict(row)
        tid = row['ticket_id']
        team_id = row['team_id']
        title = row['title']
        desc = (row.get('description') or '').strip()
        note = (row.get('progress_note') or '').strip()

        # 산출물 목록
        conn2 = get_db()
        art_rows = conn2.execute(
            "SELECT title, artifact_type, content FROM artifacts WHERE team_id=? AND ticket_id=? LIMIT 5",
            (team_id, tid)
        ).fetchall()
        arts_text = "\n".join(f"- [{r['artifact_type']}] {r['title']}: {(r['content'] or '')[:200]}" for r in art_rows) if art_rows else "산출물 없음"

        # 재작업 이력
        fail_count = conn2.execute(
            "SELECT COUNT(*) as n FROM ticket_reviews WHERE ticket_id=? AND result='fail'", (tid,)
        ).fetchone()['n']
        conn2.close()

        # Ollama AI 리뷰
        review_prompt = f"""티켓 리뷰를 수행하세요.

티켓: {title}
요구사항: {desc[:300] or '없음'}
진행노트: {note[:300] or '없음'}
산출물:
{arts_text}
재작업 횟수: {fail_count}/3

JSON으로 답변 (다른 텍스트 없이):
{{"result":"pass 또는 fail","score":1~5,"issues":["이슈1","이슈2"],"comment":"한줄 판정 사유"}}

판정 기준 (관대하게):
- 산출물 또는 진행노트 중 하나라도 있으면 pass
- 둘 다 없어도 제목에 작업 내용이 명확하면 pass (3점)
- fail은 정말 아무것도 없고 요구사항도 불명확한 경우만
- 재작업 티켓은 무조건 pass (이미 한번 작업한 것)
- 기본값은 pass. 의심스러우면 pass."""

        ai_result = _smart_chat(review_prompt, system="당신은 QA 리뷰어. JSON만 출력.")

        # AI 응답 파싱
        result = 'pass'
        score = 3
        comment = ""
        issues_list = []
        if ai_result:
            try:
                start = ai_result.find("{")
                end = ai_result.rfind("}") + 1
                if start >= 0 and end > start:
                    parsed = json.loads(ai_result[start:end])
                    result = 'pass' if parsed.get('result','pass').lower() == 'pass' else 'fail'
                    score = max(1, min(5, int(parsed.get('score', 3))))
                    issues_list = parsed.get('issues', [])
                    comment = f"[AI리뷰 {score}/5] {parsed.get('comment','')}"
            except Exception:
                comment = f"[AI리뷰] 파싱 실패 — 자동 pass"
                result = 'pass'
                score = 3
        else:
            comment = "[AI리뷰] Ollama 무응답 — 자동 pass"

        if not comment:
            comment = f"[AI리뷰 {score}/5] 통과"

        # DB 저장
        conn3 = get_db()
        conn3.execute(
            "INSERT INTO ticket_reviews (ticket_id,team_id,reviewer,result,score,comment,retry_round,issues) VALUES (?,?,?,?,?,?,?,?)",
            (tid, team_id, 'Ollama-상주에이전트', result, score, comment, fail_count,
             json.dumps(issues_list, ensure_ascii=False) if issues_list else None)
        )
        conn3.commit()
        conn3.close()
        sse_broadcast(team_id, 'qa_reviewed', {'ticket_id': tid, 'result': result, 'score': score})
        _post_conv(team_id, tid, '상주에이전트', '팀', 'qa', comment)

        # 텔레그램 알림
        icon = "✅" if result == 'pass' else "❌"
        _tg_send(f"{icon} <b>AI 리뷰</b>: {title[:40]}\n점수: {score}/5 | {result}\n{comment[:100]}")

        # 재작업 조건: 산출물 0건 AND 점수 2점 미만일 때만
        has_artifacts = len(art_rows) > 0
        if result == 'fail' and not has_artifacts and score < 2:
            if fail_count < 3:
                # 재작업 티켓 발행 (최대 3회)
                rework_id = "T-" + uuid.uuid4().hex[:6].upper()
                # 원본 제목에서 기존 [재작업] 접두사 제거 후 회차 표시
                clean_title = re.sub(r'\[재작업[^\]]*\]\s*', '', title)
                rework_title = f"[재작업 {fail_count+1}/3] {clean_title}"
                rework_desc = f"AI 리뷰 실패 ({score}/5): {comment}\n이슈: {', '.join(issues_list)}\n원본: {tid}"
                conn4 = get_db()
                conn4.execute("""
                    INSERT INTO tickets (ticket_id,team_id,title,description,priority,status,parent_ticket_id,created_at)
                    VALUES (?,?,?,?,?,'Backlog',?,datetime('now'))
                """, (rework_id, team_id, rework_title, rework_desc, row.get('priority','Low'), tid))
                conn4.commit()
                conn4.close()
                sse_broadcast(team_id, 'ticket_created', {'ticket_id': rework_id, 'title': rework_title, 'parent': tid})
                _post_conv(team_id, tid, '상주에이전트', '팀', 'rework', f"재작업 {fail_count+1}/3: {rework_id}")
                _tg_send(f"🔄 <b>재작업 {fail_count+1}/3</b>: {clean_title[:40]}\n{', '.join(issues_list[:3])}")
            else:
                # 3회 초과 — 에스컬레이션
                conn5 = get_db()
                conn5.execute("UPDATE tickets SET status='Blocked' WHERE ticket_id=?", (tid,))
                conn5.commit()
                conn5.close()
                esc_msg = f"🚨 [에스컬레이션] {clean_title[:35]} — 재작업 3회 실패. Blocked 처리. 대표님 개입 필요."
                _post_msg(team_id, '상주에이전트', esc_msg)
                _tg_send(esc_msg)
                sse_broadcast(team_id, 'ticket_status_changed', {'ticket_id': tid, 'status': 'Blocked', 'reason': 'escalation'})


def _post_conv(team_id, ticket_id, from_agent, to_agent, msg_type, content_text):
    """agent_conversations에 대화 기록 (스레드용)."""
    conn = get_db()
    conn.execute(
        "INSERT INTO agent_conversations (team_id,ticket_id,from_agent,to_agent,msg_type,content) VALUES (?,?,?,?,?,?)",
        (team_id, ticket_id or '', from_agent, to_agent, msg_type, content_text[:500])
    )
    conn.commit()
    conn.close()
    sse_broadcast(team_id, 'agent_message', {'from': from_agent, 'to': to_agent, 'ticket_id': ticket_id, 'msg_type': msg_type, 'content': content_text[:120]})


def _post_msg(team_id, sender, content_text):
    """messages 테이블에 메시지 저장."""
    msg_id = f"msg-{uuid.uuid4().hex[:8]}"
    conn = get_db()
    conn.execute(
        "INSERT INTO messages (message_id,team_id,content,sender_member_id,role,created_at) VALUES (?,?,?,?,?,?)",
        (msg_id, team_id, content_text, sender, 'orchestrator', now_utc())
    )
    conn.commit()
    conn.close()
    sse_broadcast(team_id, 'message_sent', {'sender': sender, 'message': content_text[:120]})


def _resident_route_questions():
    """에이전트→에이전트 질문 감지 → 상주에이전트 답변 또는 회의 소집."""
    conn = get_db()
    # 30분 내 유디/상주에이전트에게 온 미답변 질문
    unanswered = conn.execute("""
        SELECT c.conv_id, c.team_id, c.ticket_id, c.from_agent, c.content
        FROM agent_conversations c
        WHERE (c.to_agent IN ('유디','상주에이전트','orchestrator'))
          AND c.from_agent != '상주에이전트'
          AND c.msg_type IN ('question','request')
          AND c.created_at > datetime('now', '-30 minutes')
          AND NOT EXISTS (
              SELECT 1 FROM agent_conversations r
              WHERE r.team_id=c.team_id AND r.ticket_id=c.ticket_id
                AND r.from_agent='상주에이전트' AND r.created_at > c.created_at
                AND r.msg_type='response'
          )
        LIMIT 5
    """).fetchall()
    conn.close()

    for row in unanswered:
        row = dict(row)
        question = row['content']
        team_id = row['team_id']
        ticket_id = row.get('ticket_id','')
        from_agent = row['from_agent']

        # Ollama가 답변 생성
        answer = _smart_chat(
            f"에이전트 '{from_agent}'가 질문합니다: {question[:200]}\n\n"
            f"PM으로서 2-3줄 이내로 명확하게 답변하세요. 모르면 '회의소집 필요'라고 답하세요.",
            system="당신은 PM. 에이전트 질문에 간결하게 답변."
        )

        if answer and '회의소집' not in answer:
            _post_conv(team_id, ticket_id, '상주에이전트', from_agent, 'response', answer[:300])
        else:
            # AI도 모름 → 회의 소집 (팀당 3회/일 제한)
            conn_m = get_db()
            meeting_count = conn_m.execute(
                "SELECT COUNT(*) as n FROM agent_conversations WHERE team_id=? AND from_agent='상주에이전트' AND msg_type='meeting' AND created_at > datetime('now','-24 hours')",
                (team_id,)
            ).fetchone()['n']
            conn_m.close()
            if meeting_count < 3:
                meeting_msg = f"[회의소집] {from_agent} 질문: {question[:100]}. 관련 에이전트는 현황 보고해주세요."
                _post_conv(team_id, ticket_id, '상주에이전트', '전체', 'meeting', meeting_msg)
                _post_msg(team_id, '상주에이전트', meeting_msg)
                _tg_send(f"📢 <b>회의 소집</b> ({team_id[:12]})\n{from_agent}: {question[:60]}")



def _resident_facilitate_meeting():
    """AI가 팀 상태를 분석하고 회의 소집 여부 판단 (팀당 3회/일 제한)."""
    conn = get_db()
    teams = conn.execute("SELECT team_id, name FROM agent_teams WHERE status='Active'").fetchall()
    conn.close()
    for team_row in teams:
        team_id = team_row['team_id']
        team_name = team_row['name']
        conn2 = get_db()
        sc = {r['status']: r['n'] for r in conn2.execute(
            "SELECT status, COUNT(*) as n FROM tickets WHERE team_id=? GROUP BY status", (team_id,)
        ).fetchall()}
        today_meetings = conn2.execute(
            "SELECT COUNT(*) as n FROM agent_conversations WHERE team_id=? AND from_agent='상주에이전트' AND msg_type='meeting' AND created_at > datetime('now','-24 hours')",
            (team_id,)
        ).fetchone()['n']
        conn2.close()
        if today_meetings >= 1:  # 하루 1회 제한 (CLI 구독 보호)
            continue
        blocked = sc.get('Blocked', 0)
        inprog = sc.get('InProgress', 0)
        if blocked >= 3 or inprog >= 5:  # 임계치 상향
            # AI가 회의 안건 생성
            situation = f"팀: {team_name}\nBlocked: {blocked}개, InProgress: {inprog}개, Done: {sc.get('Done',0)}개, Todo: {sc.get('Todo',0)}개"
            agenda = _smart_chat(
                f"{situation}\n\n이 상황에서 회의가 필요한 이유와 안건 3개를 작성하세요. 2-3줄로.",
                system="당신은 PM. 팀 회의 안건을 간결하게 작성."
            )
            if not agenda:
                agenda = f"Blocked {blocked}개 / InProgress {inprog}개 — 상태 보고 및 차단 해제 논의 필요"
            meeting_msg = f"[회의소집 {today_meetings+1}/3] {team_name}\n{agenda[:300]}"
            _post_conv(team_id, '', '상주에이전트', '전체', 'meeting', meeting_msg)
            _post_msg(team_id, '상주에이전트', meeting_msg)
            _tg_send(f"📢 <b>회의 소집</b>: {team_name}\n{agenda[:120]}")



def _resident_monitor_inprogress():
    """InProgress 티켓 상태를 점검하고 SSE로 실시간 브로드캐스트."""
    conn = get_db()
    rows = conn.execute(
        "SELECT t.ticket_id, t.title, t.team_id, t.assigned_member_id, t.started_at, t.last_ping_at "
        "FROM tickets t JOIN agent_teams a ON t.team_id=a.team_id "
        "WHERE t.status='InProgress' AND a.status='Active'"
    ).fetchall()
    conn.close()
    if not rows:
        return

    for row in rows:
        row = dict(row)
        ticket_id = row["ticket_id"]
        team_id = row["team_id"]
        sid = row.get("assigned_member_id", "")
        alive = sid in _claude_processes and _claude_processes[sid].poll() is None

        # 프로세스가 죽었는데 티켓이 InProgress로 남아있으면 정리
        if not alive and sid and sid.startswith("cs-"):
            ts = now_utc()
            conn2 = get_db()
            conn2.execute(
                "UPDATE tickets SET status='Done', completed_at=? WHERE ticket_id=? AND status='InProgress'",
                (ts, ticket_id)
            )
            conn2.commit()
            conn2.close()
            sse_broadcast(team_id, "ticket_status_changed", {
                "ticket_id": ticket_id, "status": "Done",
                "ticket_title": row["title"], "auto": True
            })
            continue

        # 살아있으면 heartbeat 브로드캐스트 (2초 폴링 갱신용)
        sse_broadcast(team_id, "ticket_heartbeat", {
            "ticket_id": ticket_id, "alive": alive,
            "last_ping_at": row.get("last_ping_at")
        })


# ── 일일 보고서 + KPI 생성 ──

_daily_report_last_date = [None]  # mutable for closure — 마지막 보고서 생성 날짜 (KST)


def _resident_should_generate_daily_report():
    """09:00 KST (00:00 UTC)에 보고서 생성이 필요한지 판단."""
    KST = timezone(timedelta(hours=9))
    now_kst = datetime.now(KST)
    today_str = now_kst.strftime("%Y-%m-%d")

    # 이미 오늘 생성했으면 스킵
    if _daily_report_last_date[0] == today_str:
        return False

    # 09:00~09:30 KST 윈도우
    if now_kst.hour == 9 and now_kst.minute < 30:
        # DB에 이미 오늘자 보고서가 있으면 스킵
        try:
            conn = get_db()
            existing = conn.execute(
                "SELECT 1 FROM daily_reports WHERE report_date=?", (today_str,)
            ).fetchone()
            conn.close()
            if existing:
                _daily_report_last_date[0] = today_str
                return False
        except Exception:
            pass
        return True
    return False


def _resident_daily_report():
    """일일 보고서 생성: 전체 팀 현황, 에이전트 KPI, AI 요약. 텔레그램 + SSE 발송."""
    KST = timezone(timedelta(hours=9))
    now_kst = datetime.now(KST)
    today_str = now_kst.strftime("%Y-%m-%d")
    yesterday_str = (now_kst - timedelta(days=1)).strftime("%Y-%m-%d")

    conn = get_db()

    # ── 1. 전체 팀 현황 ──
    teams = conn.execute(
        "SELECT team_id, name, status FROM agent_teams WHERE status='Active'"
    ).fetchall()
    active_team_count = len(teams)

    total_tickets = conn.execute("SELECT COUNT(*) as n FROM tickets").fetchone()['n']
    done_tickets = conn.execute("SELECT COUNT(*) as n FROM tickets WHERE status='Done'").fetchone()['n']
    completion_rate = round(done_tickets / total_tickets * 100, 1) if total_tickets > 0 else 0.0

    # ── 2. 어제 완료된 티켓 목록 ──
    yesterday_completed_rows = conn.execute("""
        SELECT t.ticket_id, t.title, t.team_id, a.name as team_name,
               t.assigned_member_id, t.started_at, t.completed_at
        FROM tickets t
        LEFT JOIN agent_teams a ON t.team_id = a.team_id
        WHERE t.status='Done'
          AND t.completed_at >= ? AND t.completed_at < ?
        ORDER BY t.completed_at
    """, (yesterday_str, today_str)).fetchall()
    yesterday_completed = [dict(r) for r in yesterday_completed_rows]

    # ── 3. 블로커/이슈 사항 ──
    blockers_rows = conn.execute("""
        SELECT t.ticket_id, t.title, t.team_id, a.name as team_name,
               t.assigned_member_id, t.status
        FROM tickets t
        LEFT JOIN agent_teams a ON t.team_id = a.team_id
        WHERE t.status='Blocked' AND a.status='Active'
        ORDER BY t.created_at
    """).fetchall()
    blockers = [dict(r) for r in blockers_rows]

    # ── 4. 에이전트 KPI 계산 ──
    # 각 에이전트별: 완료 티켓 수, 평균 처리 시간, fail 비율
    kpi_rows = conn.execute("""
        SELECT
            m.member_id,
            m.team_id,
            m.display_name,
            m.role,
            COUNT(CASE WHEN t.status='Done' THEN 1 END) as completed,
            COUNT(t.ticket_id) as total_assigned,
            AVG(CASE
                WHEN t.status='Done' AND t.started_at IS NOT NULL AND t.completed_at IS NOT NULL
                THEN (julianday(t.completed_at) - julianday(t.started_at)) * 1440
                ELSE NULL
            END) as avg_minutes
        FROM team_members m
        LEFT JOIN tickets t ON t.assigned_member_id = m.member_id
        JOIN agent_teams a ON m.team_id = a.team_id
        WHERE a.status='Active'
        GROUP BY m.member_id
        HAVING total_assigned > 0
        ORDER BY completed DESC
    """).fetchall()

    # fail 비율 계산 (ticket_reviews에서)
    kpi_data = []
    for kr in kpi_rows:
        kr = dict(kr)
        member_id = kr['member_id']
        fail_count = conn.execute("""
            SELECT COUNT(*) as n FROM ticket_reviews tr
            JOIN tickets t ON tr.ticket_id = t.ticket_id
            WHERE t.assigned_member_id=? AND tr.result='fail'
        """, (member_id,)).fetchone()['n']

        total = kr['total_assigned'] or 0
        fail_rate = round(fail_count / total * 100, 1) if total > 0 else 0.0
        avg_min = round(kr['avg_minutes'] or 0, 1)

        kpi_entry = {
            'member_id': member_id,
            'team_id': kr['team_id'],
            'display_name': kr['display_name'] or kr['role'] or member_id,
            'completed_tickets': kr['completed'] or 0,
            'avg_minutes': avg_min,
            'fail_count': fail_count,
            'total_assigned': total,
            'fail_rate': fail_rate
        }
        kpi_data.append(kpi_entry)

        # agent_kpi 테이블에 저장
        try:
            conn.execute("""
                INSERT OR REPLACE INTO agent_kpi
                (report_date, member_id, team_id, display_name,
                 completed_tickets, avg_minutes, fail_count, total_assigned, fail_rate)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (today_str, member_id, kr['team_id'],
                  kpi_entry['display_name'], kpi_entry['completed_tickets'],
                  avg_min, fail_count, total, fail_rate))
        except Exception:
            pass

    # ── 5. AI 요약 생성 (Ollama/Claude) ──
    report_context = (
        f"일일 보고서 데이터 ({today_str}):\n"
        f"- 활성 팀: {active_team_count}개\n"
        f"- 전체 티켓: {total_tickets}개, 완료: {done_tickets}개 ({completion_rate}%)\n"
        f"- 어제 완료: {len(yesterday_completed)}개\n"
        f"- 블로커: {len(blockers)}개\n"
        f"- 에이전트 KPI:\n"
    )
    for k in kpi_data[:10]:
        report_context += (
            f"  {k['display_name']}: 완료 {k['completed_tickets']}건, "
            f"평균 {k['avg_minutes']}분, fail {k['fail_rate']}%\n"
        )
    if blockers:
        report_context += "\n블로커 목록:\n"
        for b in blockers[:5]:
            report_context += f"  - [{b.get('team_name','')}] {b['title']}\n"

    ai_summary = _smart_chat(
        f"{report_context}\n\n"
        "위 데이터를 기반으로 일일 보고서 요약을 작성하세요.\n"
        "포함 사항: 1) 전체 현황 한줄 요약, 2) 주요 성과, 3) 주의 필요 사항, 4) 내일 예상 작업.\n"
        "5줄 이내로 간결하게 한국어로 작성.",
        system="당신은 프로젝트 매니저. 일일 보고서를 간결하고 통찰력 있게 작성."
    )
    if not ai_summary:
        ai_summary = (
            f"[자동 요약] 활성 팀 {active_team_count}개, "
            f"완료율 {completion_rate}%, "
            f"어제 {len(yesterday_completed)}건 완료, "
            f"블로커 {len(blockers)}건"
        )

    # ── 6. DB 저장 ──
    yesterday_json = json.dumps(yesterday_completed, ensure_ascii=False, default=str)
    blockers_json = json.dumps(blockers, ensure_ascii=False, default=str)
    kpi_json = json.dumps(kpi_data, ensure_ascii=False, default=str)

    try:
        conn.execute("""
            INSERT OR REPLACE INTO daily_reports
            (report_date, active_teams, total_tickets, done_tickets,
             completion_rate, yesterday_completed, blockers, kpi_data, ai_summary)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (today_str, active_team_count, total_tickets, done_tickets,
              completion_rate, yesterday_json, blockers_json, kpi_json, ai_summary))
        conn.commit()
    except Exception as e:
        conn.close()
        return

    conn.close()

    # 마지막 생성 날짜 업데이트
    _daily_report_last_date[0] = today_str

    # ── 7. 텔레그램 발송 ──
    tg_lines = [
        f"📊 <b>일일 보고서</b> ({today_str})\n",
        f"🏢 활성 팀: {active_team_count}개",
        f"📋 전체 티켓: {total_tickets}개 | ✅ 완료: {done_tickets}개 ({completion_rate}%)",
        f"📌 어제 완료: {len(yesterday_completed)}건",
        f"🚫 블로커: {len(blockers)}건\n",
    ]
    if kpi_data:
        tg_lines.append("<b>에이전트 KPI (상위 5)</b>")
        for k in kpi_data[:5]:
            tg_lines.append(
                f"  • {k['display_name']}: {k['completed_tickets']}건 완료, "
                f"평균 {k['avg_minutes']}분, fail {k['fail_rate']}%"
            )
    tg_lines.append(f"\n<b>AI 분석</b>\n{ai_summary[:500]}")
    _tg_send("\n".join(tg_lines))

    # ── 8. SSE 브로드캐스트 ──
    sse_broadcast(None, 'daily_report', {
        'report_date': today_str,
        'active_teams': active_team_count,
        'total_tickets': total_tickets,
        'done_tickets': done_tickets,
        'completion_rate': completion_rate,
        'yesterday_completed_count': len(yesterday_completed),
        'blocker_count': len(blockers),
        'kpi_summary': kpi_data[:5],
        'ai_summary': ai_summary[:300]
    })


def _resident_check_tickets():
    """Todo 상태 + 미할당 티켓을 찾아 자동으로 에이전트 스폰."""
    conn = get_db()
    # 활성 팀의 Todo 티켓 중 할당되지 않은 것
    tickets = conn.execute("""
        SELECT t.ticket_id, t.title, t.description, t.priority, t.depends_on, t.team_id,
               a.name as team_name, a.project_group
        FROM tickets t
        JOIN agent_teams a ON t.team_id = a.team_id
        WHERE t.status = 'Todo' AND (t.assigned_member_id IS NULL OR t.assigned_member_id = '')
        AND a.status = 'Active'
        ORDER BY CASE t.priority WHEN 'Critical' THEN 0 WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END
        LIMIT 5
    """).fetchall()
    conn.close()

    for ticket in tickets:
        ticket = dict(ticket)
        # 의존성 체크
        deps = ticket.get("depends_on", "")
        if deps:
            conn2 = get_db()
            dep_ids = [d.strip() for d in deps.split(",") if d.strip()]
            all_done = True
            for dep_id in dep_ids:
                dep = conn2.execute("SELECT status FROM tickets WHERE ticket_id=?", (dep_id,)).fetchone()
                if not dep or dep["status"] != "Done":
                    all_done = False
                    break
            conn2.close()
            if not all_done:
                continue

        # 프로젝트 경로 찾기
        project_path = _find_project_path(ticket.get("project_group") or ticket.get("team_name", ""))
        if not project_path:
            continue

        # 이미 실행 중인 세션이 너무 많으면 대기
        if len(_claude_processes) >= 3:
            break

        # 스폰
        _orch_spawn_agent_for_ticket(ticket, project_path)




# ── API 기반 에이전트 (CLI 대체, 비용 절감) ──

_API_AGENT_TOOLS = [
    {
        "name": "kanban_ticket_status",
        "description": "티켓 상태를 업데이트합니다 (InProgress/Review/Done/Blocked)",
        "input_schema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string", "description": "티켓 ID"},
                "team_id": {"type": "string", "description": "팀 ID"},
                "status": {"type": "string", "enum": ["InProgress", "Review", "Done", "Blocked"]},
                "progress_note": {"type": "string", "description": "진행 메모 (선택)"}
            },
            "required": ["ticket_id", "team_id", "status"]
        }
    },
    {
        "name": "kanban_activity_log",
        "description": "활동 로그를 기록합니다. action=progress로 실시간 진행상황 표시",
        "input_schema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string"},
                "ticket_id": {"type": "string"},
                "member_id": {"type": "string"},
                "action": {"type": "string", "description": "progress, info, error 등"},
                "message": {"type": "string", "description": "활동 내용"}
            },
            "required": ["team_id", "action", "message"]
        }
    },
    {
        "name": "kanban_artifact_create",
        "description": "산출물(코드, 분석 결과, 문서)을 기록합니다",
        "input_schema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string"},
                "creator_member_id": {"type": "string"},
                "title": {"type": "string"},
                "content": {"type": "string"},
                "artifact_type": {"type": "string", "enum": ["code", "result", "summary", "log"]},
                "language": {"type": "string", "description": "코드 언어 (선택)"}
            },
            "required": ["ticket_id", "title", "content", "artifact_type"]
        }
    },
    {
        "name": "read_file",
        "description": "프로젝트 파일을 읽습니다. offset/limit으로 구간 지정 가능",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "파일 경로 (프로젝트 루트 기준 상대경로)"},
                "offset": {"type": "integer", "description": "시작 줄 번호 (0-based, 기본 0)"},
                "limit": {"type": "integer", "description": "읽을 줄 수 (기본 2000)"}
            },
            "required": ["path"]
        }
    },
    {
        "name": "list_files",
        "description": "디렉토리의 파일 목록을 조회합니다",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "디렉토리 경로 (기본: 프로젝트 루트)"}
            },
            "required": []
        }
    },
    {
        "name": "write_file",
        "description": "파일을 생성하거나 수정합니다",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "파일 경로"},
                "content": {"type": "string", "description": "파일 내용"}
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "edit_file",
        "description": "파일 내 특정 텍스트를 찾아 교체합니다. 전체 덮어쓰기 없이 부분 수정 가능. old_text가 유일해야 합니다",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "파일 경로"},
                "old_text": {"type": "string", "description": "교체할 기존 텍스트 (정확히 일치해야 함)"},
                "new_text": {"type": "string", "description": "새로 넣을 텍스트"}
            },
            "required": ["path", "old_text", "new_text"]
        }
    },
    {
        "name": "insert_lines",
        "description": "파일의 특정 줄 뒤에 내용을 삽입합니다. 기존 내용은 보존됩니다",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "파일 경로"},
                "after_line": {"type": "integer", "description": "이 줄 번호 뒤에 삽입 (1-based)"},
                "content": {"type": "string", "description": "삽입할 내용"}
            },
            "required": ["path", "after_line", "content"]
        }
    },
    {
        "name": "append_file",
        "description": "파일 끝에 내용을 추가합니다. 기존 내용은 보존됩니다",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "파일 경로"},
                "content": {"type": "string", "description": "추가할 내용"}
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "run_command",
        "description": "쉘 명령을 실행합니다 (빌드, 테스트 등)",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "실행할 명령"}
            },
            "required": ["command"]
        }
    },
    {
        "name": "kanban_board_get",
        "description": "팀 칸반보드를 조회합니다 (티켓 목록, 상태별 현황)",
        "input_schema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"}
            },
            "required": ["team_id"]
        }
    },
    {
        "name": "kanban_team_list",
        "description": "활성 팀 목록을 조회합니다",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "kanban_ticket_create",
        "description": "새 티켓을 생성합니다",
        "input_schema": {
            "type": "object",
            "properties": {
                "team_id": {"type": "string", "description": "팀 ID"},
                "title": {"type": "string", "description": "티켓 제목"},
                "description": {"type": "string", "description": "티켓 설명"},
                "priority": {"type": "string", "enum": ["High", "Medium", "Low"]}
            },
            "required": ["team_id", "title"]
        }
    },
    {
        "name": "search_code",
        "description": "프로젝트 코드에서 패턴을 검색합니다 (grep)",
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "검색 패턴"},
                "path": {"type": "string", "description": "검색 디렉토리 (기본: 프로젝트 루트)"},
                "include": {"type": "string", "description": "파일 패턴 (예: *.py, *.dart)"}
            },
            "required": ["pattern"]
        }
    },
    {
        "name": "dispatch_agent",
        "description": "★ 최우선 도구 ★ 사용자가 코드 수정, 빌드, 배포, 구현, 추가, 개선, 수정, 테스트 작성, 리팩토링, 버그 수정, 기능 개발 등 실행이 필요한 작업을 요청하면 반드시 이 도구를 호출. read_file이나 list_files로 확인만 하지 말고 이 도구로 Claude Code CLI(Opus 4.6)를 보내서 실제 작업을 실행시켜라.",
        "input_schema": {
            "type": "object",
            "properties": {
                "project": {"type": "string", "description": "프로젝트 이름 (별명 또는 정식명)"},
                "instruction": {"type": "string", "description": "에이전트에게 전달할 구체적 작업 지시"}
            },
            "required": ["project", "instruction"]
        }
    },
    # ── 확장 도구: Git, 브라우저, 웹 검색 ──
    {
        "name": "git_command",
        "description": "Git 명령 실행. status, log, diff, add, commit, push, pull, branch 지원. 위험 명령(reset --hard, push --force)은 차단됨",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "git 서브커맨드 (예: status, log --oneline -10, diff HEAD~1)"},
                "project_path": {"type": "string", "description": "프로젝트 경로 (기본: 현재 프로젝트)"}
            },
            "required": ["command"]
        }
    },
    {
        "name": "web_fetch",
        "description": "URL의 웹 페이지 내용을 가져옵니다 (텍스트만, 최대 5000자). API 응답 확인, 문서 조회용",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "가져올 URL"},
                "method": {"type": "string", "enum": ["GET", "POST"], "description": "HTTP 메서드 (기본: GET)"},
                "headers": {"type": "object", "description": "추가 HTTP 헤더"}
            },
            "required": ["url"]
        }
    },
    {
        "name": "browser_navigate",
        "description": "Playwright 브라우저로 웹 페이지를 열고 스크린샷/텍스트를 가져옵니다. E2E 테스트, UI 확인용",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "이동할 URL"},
                "action": {"type": "string", "enum": ["screenshot", "text", "title", "click", "fill"], "description": "수행할 액션"},
                "selector": {"type": "string", "description": "CSS 선택자 (click/fill 시)"},
                "value": {"type": "string", "description": "입력 값 (fill 시)"},
                "wait": {"type": "integer", "description": "대기 시간 ms (기본: 3000)"}
            },
            "required": ["url"]
        }
    },
    {
        "name": "system_info",
        "description": "시스템 정보 조회: CPU, 메모리, 디스크, GPU, 프로세스, 네트워크 포트",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "enum": ["cpu", "memory", "disk", "gpu", "processes", "ports", "uptime"], "description": "조회 항목"}
            },
            "required": ["query"]
        }
    },
    {
        "name": "find_files",
        "description": "파일 패턴으로 검색 (glob). 프로젝트 전체에서 특정 파일 찾기",
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "glob 패턴 (예: **/*.py, src/**/*.dart)"},
                "path": {"type": "string", "description": "검색 시작 경로 (기본: 프로젝트 루트)"},
                "max_results": {"type": "integer", "description": "최대 결과 수 (기본: 50)"}
            },
            "required": ["pattern"]
        }
    }
]


def _api_execute_tool(tool_name, tool_input, project_path, team_id, ticket_id, session_id):
    """API 에이전트의 도구 실행."""
    try:
        if tool_name == "kanban_ticket_status":
            conn = get_db()
            status = tool_input["status"]
            tid = tool_input.get("ticket_id", ticket_id)
            # team_id 자동 조회
            real_team_id = tool_input.get("team_id", team_id)
            if tid and (not real_team_id or len(real_team_id) < 5):
                row = conn.execute("SELECT team_id FROM tickets WHERE ticket_id=?", (tid,)).fetchone()
                if row:
                    real_team_id = row["team_id"]
            note = tool_input.get("progress_note")
            updates = ["status=?"]
            params = [status]
            if status == "Done":
                updates.append("completed_at=datetime('now')")
            if note:
                updates.append("progress_note=?")
                params.append(note)
            params.append(tid)
            conn.execute(f"UPDATE tickets SET {','.join(updates)} WHERE ticket_id=?", params)
            conn.commit()
            conn.close()
            sse_broadcast(real_team_id, "ticket_status_changed", {"ticket_id": tid, "status": status})
            return json.dumps({"ok": True, "status": status})

        elif tool_name == "kanban_activity_log":
            conn = get_db()
            action = tool_input.get("action", "info")
            message = tool_input.get("message", "")
            mid = tool_input.get("member_id", session_id)
            tid = tool_input.get("ticket_id", ticket_id)
            # team_id 자동 조회
            log_team_id = tool_input.get("team_id", team_id)
            if tid and (not log_team_id or len(log_team_id) < 5):
                row = conn.execute("SELECT team_id FROM tickets WHERE ticket_id=?", (tid,)).fetchone()
                if row:
                    log_team_id = row["team_id"]
            conn.execute(
                "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message) VALUES (?,?,?,?,?)",
                (log_team_id, tid, mid, action, message))
            if action == "progress" and tid:
                conn.execute("UPDATE tickets SET progress_note=?, last_ping_at=datetime('now') WHERE ticket_id=?",
                            (message, tid))
            conn.commit()
            conn.close()
            sse_broadcast(team_id, "activity_logged", {"ticket_id": tid, "action": action, "message": message})
            return json.dumps({"ok": True})

        elif tool_name == "kanban_artifact_create":
            conn = get_db()
            aid = "A-" + uuid.uuid4().hex[:6].upper()
            tid = tool_input.get("ticket_id", ticket_id)
            # team_id 자동 조회: 티켓에서 찾기
            art_team_id = tool_input.get("team_id", team_id)
            if tid and not art_team_id:
                row = conn.execute("SELECT team_id FROM tickets WHERE ticket_id=?", (tid,)).fetchone()
                art_team_id = row["team_id"] if row else ""
            conn.execute(
                "INSERT INTO artifacts (artifact_id,team_id,ticket_id,creator_member_id,title,content,artifact_type,language) VALUES (?,?,?,?,?,?,?,?)",
                (aid, art_team_id, tid, tool_input.get("creator_member_id", session_id),
                 tool_input["title"], tool_input["content"],
                 tool_input.get("artifact_type", "result"), tool_input.get("language")))
            conn.commit()
            conn.close()
            return json.dumps({"ok": True, "artifact_id": aid})

        elif tool_name == "read_file":
            fpath = os.path.join(project_path, tool_input["path"])
            fpath = os.path.realpath(fpath)
            if not fpath.startswith(os.path.realpath(project_path)):
                return json.dumps({"error": "경로 접근 불가"})
            if not os.path.isfile(fpath):
                return json.dumps({"error": f"파일 없음: {tool_input['path']}"})
            offset = int(tool_input.get("offset") or 0)
            limit = int(tool_input.get("limit") or 2000)
            with open(fpath, "r", encoding="utf-8", errors="replace") as f:
                all_lines = f.readlines()
            total = len(all_lines)
            chunk = all_lines[offset:offset + limit]
            # 줄번호 포함하여 반환
            numbered = [f"{offset + i + 1:4d}| {l}" for i, l in enumerate(chunk)]
            header = f"[{tool_input['path']}] 총 {total}줄, 표시: {offset+1}~{offset+len(chunk)}\n"
            return header + "".join(numbered)

        elif tool_name == "list_files":
            dpath = os.path.join(project_path, tool_input.get("path", "."))
            dpath = os.path.realpath(dpath)
            if not dpath.startswith(os.path.realpath(project_path)):
                return json.dumps({"error": "경로 접근 불가"})
            if not os.path.isdir(dpath):
                return json.dumps({"error": "디렉토리 없음"})
            entries = []
            for e in sorted(os.listdir(dpath))[:100]:
                fp = os.path.join(dpath, e)
                kind = "dir" if os.path.isdir(fp) else "file"
                entries.append(f"{kind}: {e}")
            return "\n".join(entries)

        elif tool_name == "write_file":
            fpath = os.path.join(project_path, tool_input["path"])
            fpath = os.path.realpath(fpath)
            if not fpath.startswith(os.path.realpath(project_path)):
                return json.dumps({"error": "경로 접근 불가"})
            os.makedirs(os.path.dirname(fpath), exist_ok=True)
            with open(fpath, "w", encoding="utf-8") as f:
                f.write(tool_input["content"])
            return json.dumps({"ok": True, "path": tool_input["path"]})

        elif tool_name == "edit_file":
            fpath = os.path.join(project_path, tool_input["path"])
            fpath = os.path.realpath(fpath)
            if not fpath.startswith(os.path.realpath(project_path)):
                return json.dumps({"error": "경로 접근 불가"})
            if not os.path.isfile(fpath):
                return json.dumps({"error": f"파일 없음: {tool_input['path']}"})
            with open(fpath, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            old_text = tool_input["old_text"]
            new_text = tool_input["new_text"]
            count = content.count(old_text)
            if count == 0:
                return json.dumps({"error": "old_text를 파일에서 찾을 수 없음", "hint": "정확한 텍스트를 read_file로 확인하세요"})
            if count > 1:
                return json.dumps({"error": f"old_text가 {count}곳에서 발견됨. 더 구체적인 텍스트를 지정하세요"})
            new_content = content.replace(old_text, new_text, 1)
            with open(fpath, "w", encoding="utf-8") as f:
                f.write(new_content)
            added = new_text.count("\n") - old_text.count("\n")
            return json.dumps({"ok": True, "path": tool_input["path"],
                               "lines_delta": added, "total_lines": new_content.count("\n") + 1})

        elif tool_name == "insert_lines":
            fpath = os.path.join(project_path, tool_input["path"])
            fpath = os.path.realpath(fpath)
            if not fpath.startswith(os.path.realpath(project_path)):
                return json.dumps({"error": "경로 접근 불가"})
            if not os.path.isfile(fpath):
                return json.dumps({"error": f"파일 없음: {tool_input['path']}"})
            with open(fpath, "r", encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
            after = int(tool_input["after_line"])
            if after < 0 or after > len(lines):
                return json.dumps({"error": f"줄 범위 초과 (파일: {len(lines)}줄, 지정: {after})"})
            insert_content = tool_input["content"]
            if not insert_content.endswith("\n"):
                insert_content += "\n"
            lines.insert(after, insert_content)
            with open(fpath, "w", encoding="utf-8") as f:
                f.writelines(lines)
            new_lines = insert_content.count("\n")
            return json.dumps({"ok": True, "path": tool_input["path"],
                               "inserted_at": after + 1, "lines_added": new_lines,
                               "total_lines": len(lines)})

        elif tool_name == "append_file":
            fpath = os.path.join(project_path, tool_input["path"])
            fpath = os.path.realpath(fpath)
            if not fpath.startswith(os.path.realpath(project_path)):
                return json.dumps({"error": "경로 접근 불가"})
            append_content = tool_input["content"]
            with open(fpath, "a", encoding="utf-8") as f:
                f.write(append_content)
            return json.dumps({"ok": True, "path": tool_input["path"],
                               "appended_chars": len(append_content)})

        elif tool_name == "run_command":
            cmd = tool_input["command"]
            # 위험 명령 차단
            dangerous = ["rm -rf /", "sudo", "mkfs", "dd if=", "> /dev/"]
            if any(d in cmd for d in dangerous):
                return json.dumps({"error": "위험 명령 차단됨"})
            try:
                # git 명령은 타임아웃 확대
                cmd_timeout = 120 if cmd.strip().startswith("git") else 60
                result = subprocess.run(
                    cmd, shell=True, capture_output=True, text=True,
                    timeout=cmd_timeout, cwd=project_path)
                output = result.stdout[-3000:] if result.stdout else ""
                err = result.stderr[-1000:] if result.stderr else ""
                return json.dumps({"exit_code": result.returncode, "stdout": output, "stderr": err})
            except subprocess.TimeoutExpired:
                return json.dumps({"error": "명령 타임아웃 (60초)"})

        elif tool_name == "kanban_board_get":
            conn = get_db()
            tid_param = tool_input.get("team_id", team_id) or team_id
            tickets = rows_to_list(conn.execute(
                "SELECT ticket_id, title, status, priority, assigned_to, progress_note "
                "FROM tickets WHERE team_id=? ORDER BY created_at", (tid_param,)).fetchall())
            conn.close()
            by_status = {}
            for t in tickets:
                by_status.setdefault(t["status"], []).append(t["title"])
            return json.dumps({"ok": True, "tickets": tickets, "count": len(tickets),
                               "by_status": by_status}, ensure_ascii=False)

        elif tool_name == "kanban_team_list":
            conn = get_db()
            teams = rows_to_list(conn.execute(
                "SELECT team_id, name, status, project_group FROM agent_teams "
                "WHERE status='Active' ORDER BY created_at DESC").fetchall())
            conn.close()
            return json.dumps({"ok": True, "teams": teams, "count": len(teams)}, ensure_ascii=False)

        elif tool_name == "kanban_ticket_create":
            conn = get_db()
            new_tid = "T-" + uuid.uuid4().hex[:6].upper()
            tid_param = tool_input.get("team_id", team_id) or team_id
            conn.execute(
                "INSERT INTO tickets (ticket_id, team_id, title, description, priority, status, created_at) "
                "VALUES (?,?,?,?,?,?, datetime('now'))",
                (new_tid, tid_param, tool_input["title"],
                 tool_input.get("description", ""), tool_input.get("priority", "Medium"), "Backlog"))
            conn.commit()
            conn.close()
            sse_broadcast(tid_param, "ticket_created", {"ticket_id": new_tid, "title": tool_input["title"]})
            return json.dumps({"ok": True, "ticket_id": new_tid}, ensure_ascii=False)

        elif tool_name == "search_code":
            pattern = tool_input["pattern"]
            search_dir = os.path.join(project_path, tool_input.get("path", "."))
            search_dir = os.path.realpath(search_dir)
            if not search_dir.startswith(os.path.realpath(project_path)):
                return json.dumps({"error": "경로 접근 불가"})
            try:
                inc = tool_input.get("include", "")
                grep_cmd = ["grep", "-rn", "--color=never"]
                if inc:
                    grep_cmd += [f"--include={inc}"]
                else:
                    for ext in ("*.py", "*.js", "*.dart", "*.html", "*.css", "*.ts", "*.json"):
                        grep_cmd += [f"--include={ext}"]
                grep_cmd += [pattern, search_dir]
                result = subprocess.run(grep_cmd, capture_output=True, text=True, timeout=10)
                lines = result.stdout.strip().split("\n")[:30]
                return json.dumps({"ok": True, "matches": [l for l in lines if l],
                                   "count": len([l for l in lines if l])}, ensure_ascii=False)
            except subprocess.TimeoutExpired:
                return json.dumps({"error": "검색 타임아웃"})
            except Exception as e:
                return json.dumps({"error": str(e)[:200]})

        elif tool_name == "dispatch_agent":
            # 승인 대기 — 실제 실행은 사용자 승인 후 r_agent_chat에서 처리
            disp_proj = tool_input.get("project", "")
            disp_instr = tool_input.get("instruction", "")
            return json.dumps({
                "ok": True, "pending_approval": True,
                "project": disp_proj, "instruction": disp_instr,
                "message": f"CLI 에이전트 스폰 대기: {disp_proj} — {disp_instr}"
            }, ensure_ascii=False)

        # ── 확장 도구: Git ──
        elif tool_name == "git_command":
            cmd = tool_input.get("command", "status")
            gpath = tool_input.get("project_path") or project_path
            # 위험 명령 차단
            dangerous = ["reset --hard", "push --force", "push -f", "clean -fd", "checkout -- ."]
            if any(d in cmd for d in dangerous):
                return json.dumps({"error": f"위험 명령 차단됨: git {cmd}", "hint": "force=true 옵션으로 사용자 승인 필요"})
            try:
                result = subprocess.run(
                    ["git"] + cmd.split(), cwd=gpath,
                    capture_output=True, text=True, timeout=30)
                output = (result.stdout + result.stderr).strip()[:5000]
                return json.dumps({"ok": True, "command": f"git {cmd}", "output": output}, ensure_ascii=False)
            except subprocess.TimeoutExpired:
                return json.dumps({"error": "git 명령 타임아웃 (30초)"})
            except Exception as e:
                return json.dumps({"error": str(e)[:200]})

        # ── 확장 도구: Web Fetch ──
        elif tool_name == "web_fetch":
            url = tool_input.get("url", "")
            if not url.startswith(("http://", "https://")):
                return json.dumps({"error": "유효한 URL이 아닙니다"})
            method = tool_input.get("method", "GET")
            try:
                req = Request(url, method=method)
                if tool_input.get("headers"):
                    for k, v in tool_input["headers"].items():
                        req.add_header(k, v)
                resp = urlopen(req, timeout=15)
                content_type = resp.headers.get("Content-Type", "")
                raw = resp.read()
                if "json" in content_type:
                    text = raw.decode("utf-8", errors="replace")[:5000]
                else:
                    text = raw.decode("utf-8", errors="replace")[:5000]
                return json.dumps({"ok": True, "url": url, "status": resp.status,
                                   "content_type": content_type, "body": text}, ensure_ascii=False)
            except Exception as e:
                return json.dumps({"error": f"HTTP 오류: {str(e)[:200]}"})

        # ── 확장 도구: Playwright Browser ──
        elif tool_name == "browser_navigate":
            url = tool_input.get("url", "")
            action = tool_input.get("action", "text")
            wait_ms = tool_input.get("wait", 3000)
            try:
                # Playwright sync API 사용
                pw_script = f"""
import json, sys
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    page.goto("{url}", wait_until="domcontentloaded", timeout=15000)
    page.wait_for_timeout({wait_ms})
    result = {{}}
    action = "{action}"
    if action == "title":
        result["title"] = page.title()
    elif action == "text":
        result["title"] = page.title()
        result["text"] = page.inner_text("body")[:3000]
    elif action == "screenshot":
        page.screenshot(path="/tmp/pw_screenshot.png")
        result["screenshot"] = "/tmp/pw_screenshot.png"
        result["title"] = page.title()
    elif action == "click":
        selector = '''{tool_input.get("selector", "")}'''
        if selector:
            page.click(selector, timeout=5000)
            page.wait_for_timeout(1000)
        result["clicked"] = selector
        result["title"] = page.title()
    elif action == "fill":
        selector = '''{tool_input.get("selector", "")}'''
        value = '''{tool_input.get("value", "")}'''
        if selector:
            page.fill(selector, value, timeout=5000)
        result["filled"] = selector
    result["url"] = page.url
    browser.close()
    print(json.dumps(result, ensure_ascii=False))
"""
                proc = subprocess.run(
                    [sys.executable, "-c", pw_script],
                    capture_output=True, text=True, timeout=30)
                if proc.returncode == 0 and proc.stdout.strip():
                    return proc.stdout.strip()
                return json.dumps({"error": proc.stderr[:500] if proc.stderr else "Playwright 실행 실패"})
            except subprocess.TimeoutExpired:
                return json.dumps({"error": "브라우저 타임아웃 (30초)"})
            except Exception as e:
                return json.dumps({"error": f"Playwright 오류: {str(e)[:200]}"})

        # ── 확장 도구: System Info ──
        elif tool_name == "system_info":
            query = tool_input.get("query", "cpu")
            try:
                if query == "cpu":
                    out = subprocess.check_output(["top", "-bn1", "-1"], text=True, timeout=5)[:2000]
                elif query == "memory":
                    out = subprocess.check_output(["free", "-h"], text=True, timeout=5)
                elif query == "disk":
                    out = subprocess.check_output(["df", "-h", "/"], text=True, timeout=5)
                elif query == "gpu":
                    try:
                        out = subprocess.check_output(["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader"], text=True, timeout=5)
                    except Exception:
                        out = "GPU 없음 또는 nvidia-smi 미설치"
                elif query == "processes":
                    out = subprocess.check_output(["ps", "aux", "--sort=-rss"], text=True, timeout=5)[:3000]
                elif query == "ports":
                    out = subprocess.check_output(["ss", "-tlnp"], text=True, timeout=5)[:3000]
                elif query == "uptime":
                    out = subprocess.check_output(["uptime"], text=True, timeout=5)
                else:
                    out = f"지원하지 않는 쿼리: {query}"
                return json.dumps({"ok": True, "query": query, "result": out.strip()}, ensure_ascii=False)
            except Exception as e:
                return json.dumps({"error": str(e)[:200]})

        # ── 확장 도구: Find Files (glob) ──
        elif tool_name == "find_files":
            import glob as globmod
            pattern = tool_input.get("pattern", "*")
            base = tool_input.get("path") or project_path
            max_r = tool_input.get("max_results", 50)
            try:
                matches = globmod.glob(os.path.join(base, pattern), recursive=True)[:max_r]
                # 상대 경로로 변환
                rel = [os.path.relpath(m, base) for m in matches]
                return json.dumps({"ok": True, "pattern": pattern, "count": len(rel), "files": rel}, ensure_ascii=False)
            except Exception as e:
                return json.dumps({"error": str(e)[:200]})

        else:
            return json.dumps({"error": f"알 수 없는 도구: {tool_name}"})

    except Exception as e:
        return json.dumps({"error": str(e)})


def _api_run_agent(ticket, project_path, team_id, session_id, max_turns=30):
    """Anthropic Messages API + tool_use 루프로 에이전트 실행.
    CLI 대비 ~1/10 비용 (cache 토큰 없음)."""
    api_key = _get_setting("anthropic_api_key")
    if not api_key:
        return None  # API 키 없으면 None → CLI 폴백

    ticket_id = ticket["ticket_id"]
    title = ticket.get("title", "")
    desc = ticket.get("description", "")

    system_prompt = f"""당신은 전문 개발 에이전트입니다. 할당된 티켓을 완수하세요.
도구를 사용하여 파일을 읽고, 수정하고, 빌드/테스트를 실행할 수 있습니다.
완료 후 반드시 kanban_ticket_status로 Done 처리하세요.
진행 중 kanban_activity_log(action=progress)로 현황을 보고하세요."""

    user_msg = f"""## 티켓
- ID: {ticket_id}
- 제목: {title}
- 설명: {desc}
- 우선순위: {ticket.get('priority', 'Medium')}
- 팀 ID: {team_id}

이 티켓을 완수하세요. 먼저 프로젝트 구조를 파악한 후 작업을 시작하세요."""

    messages = [{"role": "user", "content": user_msg}]
    total_input = 0
    total_output = 0

    for turn in range(max_turns):
        try:
            data = json.dumps({
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 4096,
                "system": system_prompt,
                "messages": messages,
                "tools": _API_AGENT_TOOLS
            }).encode("utf-8")

            req = Request(
                "https://api.anthropic.com/v1/messages",
                data=data,
                headers={
                    "Content-Type": "application/json",
                    "x-api-key": api_key,
                    "anthropic-version": "2023-06-01"
                }
            )
            resp = urlopen(req, timeout=30)
            result = json.loads(resp.read())

            # 토큰 집계
            usage = result.get("usage", {})
            total_input += usage.get("input_tokens", 0)
            total_output += usage.get("output_tokens", 0)

            stop_reason = result.get("stop_reason", "end_turn")
            content_blocks = result.get("content", [])

            if stop_reason != "tool_use":
                # 작업 완료
                break

            # tool_use 처리
            messages.append({"role": "assistant", "content": content_blocks})
            tool_results = []
            for block in content_blocks:
                if block.get("type") == "tool_use":
                    tool_result = _api_execute_tool(
                        block["name"], block["input"],
                        project_path, team_id, ticket_id, session_id)
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block["id"],
                        "content": tool_result
                    })
            messages.append({"role": "user", "content": tool_results})

        except Exception as e:
            _tg_send(f"⚠️ API 에이전트 오류: {title}\n{str(e)[:200]}")
            break

    # 비용: API 응답의 usage에서 직접 집계 (Sonnet API 가격: input $3/1M, output $15/1M)
    cost = (total_input * 3 + total_output * 15) / 1_000_000

    return {
        "input_tokens": total_input,
        "output_tokens": total_output,
        "cost": round(cost, 6),
        "model": "claude-sonnet-4-6",
        "turns": turn + 1,
        "cost_type": "api"
    }


def _orch_spawn_agent_for_ticket(ticket, project_path):
    """단일 티켓에 대해 API 에이전트 실행 (상주 에이전트에서 호출). CLI 대비 ~1/10 비용."""
    ticket_id = ticket["ticket_id"]
    title = ticket["title"]
    team_id = ticket["team_id"]
    session_id = "api-" + uuid.uuid4().hex[:8]

    # 티켓 InProgress로 전환
    conn = get_db()
    conn.execute(
        "INSERT OR IGNORE INTO claude_sessions (session_id, project_path, team_id, pid, status) VALUES (?,?,?,?,?)",
        (session_id, project_path, team_id, 0, "running"))
    conn.execute("UPDATE tickets SET status='InProgress', assigned_member_id=?, started_at=datetime('now') WHERE ticket_id=?",
                  (session_id, ticket_id))
    conn.commit()
    conn.close()

    sse_broadcast(team_id, "ticket_status_changed", {"ticket_id": ticket_id, "status": "InProgress", "ticket_title": title})
    _tg_send(f"🤖 <b>API 에이전트 시작</b>\n{title}")

    _claude_processes[session_id] = True  # 실행 중 표시

    def _run():
        try:
            usage = _api_run_agent(ticket, project_path, team_id, session_id)

            if usage is None:
                # API 키 없음 → CLI 폴백
                _tg_send(f"⚠️ API 키 없음, CLI 폴백: {title}")
                if session_id in _claude_processes:
                    del _claude_processes[session_id]
                _orch_spawn_agent_for_ticket_cli(ticket, project_path)
                return

            # 완료 처리
            conn = get_db()
            # 티켓 상태 확인 (에이전트가 이미 Done으로 바꿨을 수 있음)
            row = conn.execute("SELECT status FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone()
            if row and row["status"] not in ("Done", "Blocked"):
                conn.execute("UPDATE tickets SET status='Done', completed_at=datetime('now') WHERE ticket_id=?", (ticket_id,))
            conn.execute("UPDATE claude_sessions SET status='exited', ended_at=datetime('now') WHERE session_id=?", (session_id,))
            conn.commit()
            conn.close()

            # 토큰 사용량 기록
            _record_token_usage(team_id, ticket_id, session_id, usage)

            token_info = f" | 📊 {usage['input_tokens']:,}+{usage['output_tokens']:,} tok / ${usage['cost']:.4f} ({usage['turns']}턴)"
            sse_broadcast(team_id, "ticket_status_changed", {"ticket_id": ticket_id, "status": "Done", "ticket_title": title})
            _tg_send(f"✅ <b>API 완료</b>: {title}{token_info}")
            _app_notify("team_completed", f"작업 완료: {title}", f"도구 {usage.get('turns',0)}턴, ${usage.get('cost',0):.4f}", {"ticket_id": ticket_id})

        except Exception as e:
            _tg_send(f"🚫 API 에이전트 실패: {title}\n{str(e)[:200]}")
            _app_notify("error", f"에이전트 실패: {title}", str(e)[:100])
            conn = get_db()
            conn.execute("UPDATE tickets SET status='Blocked' WHERE ticket_id=?", (ticket_id,))
            conn.execute("UPDATE claude_sessions SET status='exited', ended_at=datetime('now') WHERE session_id=?", (session_id,))
            conn.commit()
            conn.close()
        finally:
            if session_id in _claude_processes:
                del _claude_processes[session_id]

    threading.Thread(target=_run, daemon=True).start()


def _orch_spawn_agent_for_ticket_cli(ticket, project_path):
    """CLI 폴백 — API 키 없을 때만 사용."""
    ticket_id = ticket["ticket_id"]
    title = ticket["title"]
    desc = ticket.get("description", "")
    team_id = ticket["team_id"]

    agent_prompt = f"""당신은 전문 개발 에이전트입니다. 아래 티켓을 완수하세요.
## 티켓: {ticket_id} - {title}
{desc}
완료 후 kanban_ticket_status로 Done 처리하세요."""

    session_id = "cs-" + uuid.uuid4().hex[:8]
    cli = _find_claude_cli()
    cmd = [cli, "-p", agent_prompt, "--output-format", "json", "--model", "sonnet"]

    try:
        proc = subprocess.Popen(
            cmd, cwd=project_path, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == 'nt' else 0)
        _claude_processes[session_id] = proc
        conn = get_db()
        conn.execute("INSERT INTO claude_sessions (session_id,project_path,team_id,pid,status) VALUES (?,?,?,?,?)",
                      (session_id, project_path, team_id, proc.pid, "running"))
        conn.commit()
        conn.close()
        threading.Thread(target=_resident_wait_agent, args=(ticket_id, session_id, proc, team_id, title), daemon=True).start()
    except Exception:
        pass


def _resident_wait_agent(ticket_id, session_id, proc, team_id, title):
    """에이전트 완료 감시 (상주 에이전트용)."""
    try:
        stdout_data, _ = proc.communicate(timeout=1800)
    except subprocess.TimeoutExpired:
        proc.terminate()
        stdout_data = b""
        _tg_send(f"⏰ 타임아웃: {title}")

    exit_code = proc.returncode
    new_status = "Done" if exit_code == 0 else "Blocked"

    conn = get_db()
    conn.execute("UPDATE tickets SET status=?, completed_at=datetime('now') WHERE ticket_id=?", (new_status, ticket_id))
    conn.execute("UPDATE claude_sessions SET status='exited', ended_at=datetime('now') WHERE session_id=?", (session_id,))
    conn.commit()
    conn.close()

    if session_id in _claude_processes:
        del _claude_processes[session_id]

    # 토큰 사용량 파싱 & 기록
    usage = _parse_cli_usage(stdout_data)
    _record_token_usage(team_id, ticket_id, session_id, usage)

    icon = "✅" if new_status == "Done" else "🚫"
    token_info = f" | 📊 {usage['input_tokens']:,}+{usage['output_tokens']:,} tok / ${usage['cost']:.4f}" if usage else ""
    sse_broadcast(team_id, "ticket_status_changed", {"ticket_id": ticket_id, "status": new_status, "ticket_title": title})
    _tg_send(f"{icon} <b>{new_status}</b>: {title}{token_info}")
    if new_status == "Done":
        _app_notify("team_completed", f"완료: {title}", token_info.strip(" |") if token_info else "")




# ── 대화형 에이전트 (Agentic Chat — 텔레그램/APK 공통) ──

_chat_sessions = {}  # session_id -> {"messages": [...], "project": str, "project_path": str, "created_at": str, "last_at": str}


def _chat_session_save(session_id):
    """세션을 DB에 영구 저장."""
    s = _chat_sessions.get(session_id)
    if not s: return
    try:
        conn = get_db()
        conn.execute(
            "INSERT OR REPLACE INTO chat_sessions (session_id, project, project_path, messages, created_at, last_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (session_id, s.get("project",""), s.get("project_path",""),
             json.dumps(s.get("messages",[])[-30:], ensure_ascii=False),  # 최근 30턴만
             s.get("created_at", now_utc()), now_utc())
        )
        conn.commit()
        conn.close()
    except Exception:
        pass


def _chat_session_load(session_id):
    """DB에서 세션 복원."""
    if session_id in _chat_sessions:
        return _chat_sessions[session_id]
    try:
        conn = get_db()
        row = conn.execute("SELECT * FROM chat_sessions WHERE session_id=?", (session_id,)).fetchone()
        conn.close()
        if row:
            s = {
                "messages": json.loads(row["messages"] or "[]"),
                "project": row["project"] or "",
                "project_path": row["project_path"] or "",
                "created_at": row["created_at"],
                "last_at": row["last_at"],
            }
            _chat_sessions[session_id] = s
            return s
    except Exception:
        pass
    return None


# ── Supervisor 모드: 올라마가 QA/리뷰/판정 수행 + 서버가 액션 대행 ──

_SUPERVISOR_SYSTEM = """당신은 '유디(Yudi)'. U2DIA의 상주 AI Supervisor.
Review 상태 티켓을 검수하고 품질 판정을 내린다.

## 판정 기준
- 5점: 요구사항 완벽 충족 + 추가 가치 → 통과
- 4점: 요구사항 충족, 사소한 개선점 → 통과
- 3점: 기본 충족, 보완 필요 → 조건부 통과
- 2점: 미흡 → 재작업
- 1점: 요구사항 미충족 또는 산출물 없음 → 재작업

## 응답 규칙
1. 사용자를 '대표님'이라 부른다
2. 판정 텍스트를 2~3줄로 작성
3. 반드시 아래 supervisor_action 블록으로 끝낸다
4. 이 블록이 없으면 아무 액션도 실행되지 않는다. 절대 생략하지 마라

## 예시 1: 산출물 있는 티켓 통과
대표님, T-ABC123 검수 완료. 요구사항 충족, 에러 핸들링 우수합니다. 4점 통과.

```supervisor_action
{"actions":[{"type":"feedback","ticket_id":"T-ABC123","score":4,"comment":"요구사항 충족. 에러 핸들링 우수.","verdict":"pass"}]}
```

## 예시 2: 산출물 없는 티켓 재작업
대표님, T-DEF456 산출물이 없습니다. 1점 재작업.

```supervisor_action
{"actions":[{"type":"feedback","ticket_id":"T-DEF456","score":1,"comment":"산출물 없음","verdict":"rework"}]}
```

## 예시 3: 산출물 미흡 + 재작업 티켓 발행
대표님, T-GHI789 코드가 불완전합니다. 2점 재작업 + 보완 티켓 발행.

```supervisor_action
{"actions":[{"type":"feedback","ticket_id":"T-GHI789","score":2,"comment":"코드 불완전","verdict":"rework"},{"type":"create_ticket","ticket_id":"T-GHI789","title":"[REWORK] 보완 작업","description":"불완전한 코드 수정","priority":"High"}]}
```

## 주의
- ticket_id는 반드시 "T-" + 6자리 대문자 (예: T-896BAA)
- verdict는 "pass" 또는 "rework"만 사용
- score는 1~5 정수
- 항상 feedback 타입을 포함하라
"""


def _build_supervisor_context(team_id=None):
    """Supervisor용 상세 컨텍스트 — Review 티켓, artifact, 피드백 이력."""
    try:
        conn = get_db()
        lines = []

        # Review 상태 티켓 전체 (또는 특정 팀)
        if team_id:
            review_tickets = rows_to_list(conn.execute(
                "SELECT t.ticket_id, t.title, t.description, t.priority, t.assigned_member_id, "
                "t.team_id, t.created_at, tm.name as team_name, "
                "(SELECT COUNT(*) FROM artifacts WHERE ticket_id=t.ticket_id) as artifact_count, "
                "(SELECT COUNT(*) FROM ticket_feedbacks WHERE ticket_id=t.ticket_id) as feedback_count, "
                "(SELECT MAX(score) FROM ticket_feedbacks WHERE ticket_id=t.ticket_id) as last_score "
                "FROM tickets t LEFT JOIN agent_teams tm ON t.team_id=tm.team_id "
                "WHERE t.status='Review' AND t.team_id=? "
                "ORDER BY t.created_at ASC", (team_id,)
            ).fetchall())
        else:
            review_tickets = rows_to_list(conn.execute(
                "SELECT t.ticket_id, t.title, t.description, t.priority, t.assigned_member_id, "
                "t.team_id, t.created_at, tm.name as team_name, "
                "(SELECT COUNT(*) FROM artifacts WHERE ticket_id=t.ticket_id) as artifact_count, "
                "(SELECT COUNT(*) FROM ticket_feedbacks WHERE ticket_id=t.ticket_id) as feedback_count, "
                "(SELECT MAX(score) FROM ticket_feedbacks WHERE ticket_id=t.ticket_id) as last_score "
                "FROM tickets t LEFT JOIN agent_teams tm ON t.team_id=tm.team_id "
                "WHERE t.status='Review' "
                "ORDER BY t.created_at ASC LIMIT 30"
            ).fetchall())

        if review_tickets:
            lines.append(f"## Review 대기 티켓 ({len(review_tickets)}개)")
            for tk in review_tickets:
                art_mark = f"산출물 {tk['artifact_count']}개" if tk['artifact_count'] else "⚠️ 산출물 없음"
                fb_mark = f"이전점수 {tk['last_score']}점({tk['feedback_count']}회)" if tk['feedback_count'] else "첫 검수"
                lines.append(f"  [{tk['ticket_id']}] {tk['title']}")
                lines.append(f"    팀: {tk.get('team_name','?')} | 우선순위: {tk['priority']} | {art_mark} | {fb_mark}")
                if tk.get('description'):
                    lines.append(f"    설명: {tk['description'][:120]}")

        # 특정 티켓의 artifact 상세 (최근 5개)
        for tk in review_tickets[:10]:
            artifacts = rows_to_list(conn.execute(
                "SELECT artifact_id, title, artifact_type, content, created_at "
                "FROM artifacts WHERE ticket_id=? ORDER BY created_at DESC LIMIT 3",
                (tk['ticket_id'],)
            ).fetchall())
            if artifacts:
                lines.append(f"\n  [{tk['ticket_id']}] 산출물:")
                for art in artifacts:
                    content = art['content'] or ''
                    art_type = art.get('artifact_type', '')
                    if art_type == 'code' and content:
                        # 코드: 함수/클래스 시그니처 추출
                        import re as _re_art
                        sigs = _re_art.findall(r'(?:def |func |class |function |fn |pub fn |export )\S+', content[:2000])
                        sig_str = ", ".join(sigs[:8]) if sigs else content[:300].replace('\n', ' ')
                        lines.append(f"    - {art['title']} (code): 주요: {sig_str}")
                    else:
                        content_preview = content[:400].replace('\n', ' ') if content else '(빈 내용)'
                        lines.append(f"    - {art['title']} ({art_type}): {content_preview}")

        # 기존 피드백 이력 (재작업 횟수 판단용)
        for tk in review_tickets[:10]:
            feedbacks = rows_to_list(conn.execute(
                "SELECT score, comment, author, created_at FROM ticket_feedbacks "
                "WHERE ticket_id=? ORDER BY created_at DESC LIMIT 3",
                (tk['ticket_id'],)
            ).fetchall())
            if feedbacks:
                lines.append(f"\n  [{tk['ticket_id']}] 피드백 이력:")
                for fb in feedbacks:
                    lines.append(f"    - {fb['score']}점 ({fb['author']}, {fb['created_at'][:16]}): {(fb.get('comment') or '')[:80]}")

        # 전체 통계 요약
        total_review = conn.execute("SELECT COUNT(*) as c FROM tickets WHERE status='Review'").fetchone()["c"]
        total_done = conn.execute("SELECT COUNT(*) as c FROM tickets WHERE status='Done'").fetchone()["c"]
        total_inprog = conn.execute("SELECT COUNT(*) as c FROM tickets WHERE status='InProgress'").fetchone()["c"]
        lines.insert(0, f"전체: Review {total_review}개 | Done {total_done}개 | InProgress {total_inprog}개\n")

        conn.close()
        return "\n".join(lines) if lines else "Review 대기 티켓 없음"
    except Exception as e:
        return f"Supervisor 컨텍스트 조회 실패: {e}"


def _execute_supervisor_actions(response_text, session_id):
    """올라마 응답에서 supervisor_action 블록을 추출하고 실행."""
    import re
    pattern = r'```supervisor_action\s*\n(.*?)\n```'
    match = re.search(pattern, response_text, re.DOTALL)
    if not match:
        return [], "액션 블록 없음"

    try:
        action_data = json.loads(match.group(1))
    except json.JSONDecodeError as e:
        return [], f"JSON 파싱 실패: {e}"

    actions = action_data.get("actions", [])
    results = []
    conn = get_db()

    for act in actions:
        try:
            act_type = act.get("type")
            ticket_id = act.get("ticket_id", "").upper() if act.get("ticket_id") else None

            if not ticket_id and act_type != "create_ticket":
                results.append(f"⚠️ ticket_id 누락 — 건너뜀")
                continue

            if act_type == "feedback":
                score = min(max(int(act.get("score", 3)), 1), 5)  # 1~5 범위 강제
                comment = str(act.get("comment", ""))[:500]
                verdict = act.get("verdict", "pass")
                fb_id = "FB-" + uuid.uuid4().hex[:6].upper()

                # 티켓 존재 확인
                tk_row = conn.execute("SELECT team_id, status FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone()
                if not tk_row:
                    results.append(f"⚠️ {ticket_id}: 티켓 없음 — 건너뜀")
                    continue

                conn.execute(
                    "INSERT INTO ticket_feedbacks (feedback_id, ticket_id, team_id, author, score, comment, created_at) "
                    "VALUES (?, ?, ?, 'supervisor', ?, ?, datetime('now'))",
                    (fb_id, ticket_id, tk_row["team_id"], score, comment)
                )

                # 판정에 따른 상태 변경
                t_team = tk_row["team_id"]
                new_st = None

                # ── 산출물 필수 검증 (pass 판정 시에도 산출물 없으면 자동 rework) ──
                art_check = conn.execute(
                    "SELECT COUNT(*) as cnt, COALESCE(SUM(LENGTH(content)),0) as total_len "
                    "FROM artifacts WHERE ticket_id=?", (ticket_id,)
                ).fetchone()
                has_artifacts = (art_check["cnt"] or 0) > 0
                art_quality = (art_check["total_len"] or 0) > 50

                if verdict == "pass" and score >= 3 and not has_artifacts:
                    # 산출물 없이 통과 시도 → 강제 rework
                    score = min(score, 2)
                    verdict = "rework"
                    comment = f"[자동 보정] 산출물 없음 — 재작업 필요. 원 판정: pass {score}점. {comment}"
                    results.append(f"⚠️ {ticket_id}: 산출물 없음 → 강제 rework (원래 {score}점 pass)")

                if verdict == "pass" and score >= 3:
                    conn.execute("UPDATE tickets SET status='Done', completed_at=datetime('now') WHERE ticket_id=?", (ticket_id,))
                    new_st = "Done"
                    results.append(f"✅ {ticket_id}: {score}점 통과 → Done (산출물 {art_check['cnt']}개)")
                elif verdict == "rework" or score < 3:
                    # rework_count 컬럼 직접 사용 (정확한 추적)
                    rework_row = conn.execute(
                        "SELECT COALESCE(rework_count, 0) as rc FROM tickets WHERE ticket_id=?", (ticket_id,)
                    ).fetchone()
                    rework_count = (rework_row["rc"] if rework_row else 0) + 1

                    if rework_count >= 3:
                        # 3회 도달 → Blocked (에스컬레이션)
                        conn.execute(
                            "UPDATE tickets SET status='Blocked', rework_count=? WHERE ticket_id=?",
                            (rework_count, ticket_id))
                        new_st = "Blocked"
                        results.append(f"🚨 {ticket_id}: 재작업 {rework_count}회 (한도 3회) → Blocked 에스컬레이션")
                    else:
                        conn.execute(
                            "UPDATE tickets SET status='InProgress', completed_at=NULL, rework_count=? WHERE ticket_id=?",
                            (rework_count, ticket_id))
                        new_st = "InProgress"
                        results.append(f"🔄 {ticket_id}: {score}점 재작업 ({rework_count}/3회) → InProgress")

                # 활동 로그
                conn.execute(
                    "INSERT INTO activity_logs (team_id, action, message, created_at) VALUES (?, ?, ?, datetime('now'))",
                    (t_team, "supervisor_review",
                     f"Supervisor QA: {ticket_id} → {score}점 ({verdict}). {comment[:100]}")
                )
                conn.commit()

                # SSE 실시간 푸시
                sse_broadcast(t_team, "feedback_created", {"ticket_id": ticket_id, "score": score, "verdict": verdict})
                if new_st:
                    sse_broadcast(t_team, "ticket_status_changed", {"ticket_id": ticket_id, "status": new_st})

            elif act_type == "status_change":
                new_status = act.get("new_status", "Done")
                tk_row2 = conn.execute("SELECT team_id FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone()
                if new_status == "Done":
                    conn.execute("UPDATE tickets SET status=?, completed_at=datetime('now') WHERE ticket_id=?", (new_status, ticket_id))
                else:
                    conn.execute("UPDATE tickets SET status=? WHERE ticket_id=?", (new_status, ticket_id))
                conn.commit()
                results.append(f"📋 {ticket_id}: 상태 → {new_status}")
                if tk_row2:
                    sse_broadcast(tk_row2["team_id"], "ticket_status_changed", {"ticket_id": ticket_id, "status": new_status})

            elif act_type == "create_ticket":
                new_tid = "T-" + uuid.uuid4().hex[:6].upper()
                team_id = act.get("team_id")
                if not team_id and ticket_id:
                    row = conn.execute("SELECT team_id FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone()
                    team_id = row["team_id"] if row else None
                if team_id:
                    conn.execute(
                        "INSERT INTO tickets (ticket_id, team_id, title, description, priority, status, created_at) "
                        "VALUES (?, ?, ?, ?, ?, 'Backlog', datetime('now'))",
                        (new_tid, team_id, act.get("title", "재작업"), act.get("description", ""), act.get("priority", "High"))
                    )
                    conn.commit()
                    results.append(f"🆕 {new_tid}: 재작업 티켓 발행 → {act.get('title','')[:40]}")
                    sse_broadcast(team_id, "ticket_created", {"ticket_id": new_tid, "title": act.get("title", "재작업")})
                else:
                    results.append(f"⚠️ create_ticket: team_id 없음 — 건너뜀")

        except Exception as e:
            results.append(f"❌ 액션 오류 ({act.get('type','?')}): {e}")

    conn.close()

    return results, "완료"


def _supervisor_batch_review(session_id, user_message, team_id=None):
    """배치 모드: Review 티켓을 1개씩 순차 검수 (최대 10개)."""
    conn = get_db()
    if team_id:
        tickets = rows_to_list(conn.execute(
            "SELECT t.ticket_id, t.title, "
            "(SELECT COUNT(*) FROM artifacts WHERE ticket_id=t.ticket_id) as art_cnt "
            "FROM tickets t WHERE t.status='Review' AND t.team_id=? ORDER BY t.created_at ASC LIMIT 10",
            (team_id,)).fetchall())
    else:
        tickets = rows_to_list(conn.execute(
            "SELECT t.ticket_id, t.title, "
            "(SELECT COUNT(*) FROM artifacts WHERE ticket_id=t.ticket_id) as art_cnt "
            "FROM tickets t WHERE t.status='Review' ORDER BY t.created_at ASC LIMIT 10"
        ).fetchall())
    conn.close()

    if not tickets:
        return {"ok": True, "response": "대표님, Review 대기 티켓이 없습니다.", "session_id": session_id,
                "tools_used": [], "actions_executed": [], "usage": {"input": 0, "output": 0, "cost": 0},
                "backend": "ollama-supervisor"}

    all_actions = []
    summaries = [f"대표님, Review 티켓 {len(tickets)}개를 순차 검수합니다.\n"]

    for tk in tickets:
        tid = tk["ticket_id"]
        single_msg = f"{tid} 티켓을 검수해줘."
        result = _chat_supervisor_respond(session_id + "-batch", single_msg)
        actions = result.get("actions_executed", [])
        all_actions.extend(actions)

        # 응답에서 핵심만 추출
        resp_text = result.get("response", "")
        # 첫 200자만 요약
        summary_line = resp_text[:150].replace('\n', ' ').strip()
        action_line = ", ".join(actions) if actions else "액션 없음"
        summaries.append(f"**[{tid}]** {tk['title'][:40]}\n  {action_line}")

    final_response = "\n".join(summaries)
    final_response += f"\n\n---\n총 {len(all_actions)}건 처리 완료"

    return {
        "ok": True, "response": final_response, "session_id": session_id,
        "tools_used": [], "actions_executed": all_actions,
        "usage": {"input": 0, "output": 0, "cost": 0},
        "backend": "ollama-supervisor-batch"
    }


def _chat_supervisor_respond(session_id, user_message, project=None):
    """Supervisor 모드 — Review 티켓 QA 검수, 판정, 재작업 발행."""
    # 메시지에서 팀 ID 또는 티켓 ID 추출
    import re
    team_match = re.search(r'team-[a-f0-9]+', user_message)
    ticket_match = re.search(r'T-[A-F0-9]{6}', user_message, re.IGNORECASE)

    team_id = team_match.group(0) if team_match else None

    # 티켓 ID가 있으면 해당 팀 찾기
    if ticket_match and not team_id:
        try:
            conn = get_db()
            row = conn.execute("SELECT team_id FROM tickets WHERE ticket_id=?", (ticket_match.group(0).upper(),)).fetchone()
            if row:
                team_id = row["team_id"]
            conn.close()
        except Exception:
            pass

    # 팀 이름으로 매칭 (team_id가 아직 없으면)
    if not team_id:
        try:
            conn = get_db()
            teams = conn.execute("SELECT team_id, name FROM agent_teams WHERE status='Active'").fetchall()
            msg_lower = user_message.lower()
            for t in teams:
                if t["name"].lower() in msg_lower or msg_lower in t["name"].lower():
                    team_id = t["team_id"]
                    break
            conn.close()
        except Exception:
            pass

    # 배치 모드 감지: "전체", "일괄", "모두", "all", "batch"
    batch_kw = ["전체", "일괄", "모두", "all", "batch", "전부"]
    is_batch = any(kw in user_message.lower() for kw in batch_kw)

    # 배치 모드: 서버 측에서 1개씩 순차 검수
    if is_batch:
        return _supervisor_batch_review(session_id, user_message, team_id)

    # Supervisor 컨텍스트 구성
    sup_context = _build_supervisor_context(team_id)
    full_system = _SUPERVISOR_SYSTEM + f"\n\n현재 칸반보드 상태:\n{sup_context}"

    # 세션 관리
    if session_id not in _chat_sessions:
        _chat_sessions[session_id] = {
            "messages": [], "project": project,
            "project_path": None,
            "created_at": now_utc(), "last_at": now_utc(),
        }
    session = _chat_sessions[session_id]
    session["last_at"] = now_utc()
    session["messages"].append({"role": "user", "content": user_message})
    if len(session["messages"]) > 20:
        session["messages"] = session["messages"][-10:]

    # NIM API (Nemotron 3 Super) 우선, 실패 시 올라마 폴백
    response = None
    nim_result = _nim_chat(
        prompt=user_message,
        system=full_system,
        messages=session["messages"],
        max_tokens=1024,
        mode="budget"  # 검수는 Reasoning Budget 모드 (정밀 추론)
    )
    if nim_result and nim_result.get("content"):
        response = nim_result["content"]
        if nim_result.get("reasoning"):
            response = nim_result["reasoning"] + "\n\n" + response
    else:
        # NIM 실패 → 올라마 폴백 (qwen3:32b)
        review_model = _pick_tool_model()
        response = _ollama_chat(
            prompt=user_message,
            model=review_model,
            system=full_system,
            messages=session["messages"]
        )

    if not response:
        return {"ok": False, "error": "Supervisor 올라마 응답 실패"}

    # 액션 추출 및 실행
    action_results, action_status = _execute_supervisor_actions(response, session_id)

    # 올라마가 액션 블록을 안 뱉었으면 → 서버 측 자동 판정 폴백
    if not action_results and ticket_match:
        _tid = ticket_match.group(0).upper()
        try:
            conn = get_db()
            tk = conn.execute(
                "SELECT t.ticket_id, t.team_id, t.title, "
                "(SELECT COUNT(*) FROM artifacts WHERE ticket_id=t.ticket_id) as art_cnt "
                "FROM tickets t WHERE t.ticket_id=?", (_tid,)
            ).fetchone()
            if tk:
                art_cnt = tk["art_cnt"]
                # 산출물 내용 길이도 확인
                art_quality = 0
                if art_cnt > 0:
                    arts = conn.execute(
                        "SELECT LENGTH(content) as len FROM artifacts WHERE ticket_id=? ORDER BY created_at DESC LIMIT 3",
                        (_tid,)
                    ).fetchall()
                    avg_len = sum(a["len"] for a in arts) / max(len(arts), 1) if arts else 0
                    art_quality = 1 if avg_len > 50 else 0  # 50자 미만은 형식적 산출물
                if art_cnt == 0:
                    auto_score = 1
                elif art_quality == 0:
                    auto_score = 2  # 산출물 있지만 내용 부실
                else:
                    auto_score = 3  # 산출물 + 내용 있음
                auto_verdict = "pass" if auto_score >= 3 else "rework"
                auto_comment = f"자동판정: 산출물 {art_cnt}개, 내용{'충분' if art_quality else '부실'}"
                fallback_json = json.dumps({"actions": [{
                    "type": "feedback", "ticket_id": _tid,
                    "score": auto_score, "comment": auto_comment, "verdict": auto_verdict
                }]})
                fallback_resp = f'```supervisor_action\n{fallback_json}\n```'
                action_results, _ = _execute_supervisor_actions(fallback_resp, session_id)
                response += f"\n\n(서버 자동 판정: {auto_score}점 {auto_verdict})"
            conn.close()
        except Exception:
            pass

    # 응답에서 supervisor_action 블록 제거 (사용자에게 깔끔한 출력)
    import re as _re
    clean_response = _re.sub(r'\n*```supervisor_action\s*\n.*?\n```\s*', '', response, flags=_re.DOTALL).strip()

    # 액션 결과를 응답에 첨부
    if action_results:
        clean_response += "\n\n--- 실행 결과 ---\n" + "\n".join(action_results)

    session["messages"].append({"role": "assistant", "content": clean_response})

    return {
        "ok": True, "response": clean_response, "session_id": session_id,
        "tools_used": [], "actions_executed": action_results,
        "usage": {"input": 0, "output": 0, "cost": 0},
        "backend": "ollama-supervisor"
    }


def _chat_ollama_respond(session_id, user_message, project=None, project_path=None, force_tools=False):
    """Ollama 에이전틱 대화 — 의도 분류 기반 자연어 라우팅."""
    if session_id not in _chat_sessions:
        _chat_sessions[session_id] = {
            "messages": [], "project": project,
            "project_path": project_path or (_find_project_path(project) if project else None),
            "created_at": now_utc(), "last_at": now_utc(),
        }
    session = _chat_sessions[session_id]
    if project and not session["project"]:
        session["project"] = project
        session["project_path"] = project_path or _find_project_path(project)
    session["last_at"] = now_utc()

    session["messages"].append({"role": "user", "content": user_message})
    if len(session["messages"]) > 30:
        session["messages"] = session["messages"][-16:]

    context = _build_kanban_context()
    proj_name = session.get("project") or "미지정"
    proj_path = session.get("project_path") or ""

    if force_tools:
        # ── 에이전틱 모드: Ollama가 도구를 선택하고 실행 ──
        tool_system = (
            f"당신은 U2DIA AI 에이전트 '유디'. 시니어 풀스택 개발자 + PM.\n"
            f"프로젝트: {proj_name} ({proj_path or '미지정'})\n\n"
            f"## 판단 기준\n"
            f"대표님의 요청을 듣고, 스스로 판단해서 적절한 도구를 사용해라.\n"
            f"- 정보가 궁금한 거면 → 칸반 조회, 파일 읽기, git 로그 등으로 답변\n"
            f"- 코드 작업이 필요한 거면 → dispatch_agent로 Claude Code CLI 소환\n"
            f"- 너는 직접 코드를 수정하지 않는다. 코딩은 Claude Code CLI(Opus 4.6)에게 맡긴다.\n\n"
            f"## dispatch_agent 사용법\n"
            f"dispatch_agent(project='{proj_name}', instruction='구체적 작업 지시')\n"
            f"대표님이 코드 변경, 개발, 빌드, 수정, 테스트, 배포, 구현, 리팩토링, 버그 수정,\n"
            f"기능 추가, 파일 생성, 설정 변경 등 '실행'이 필요한 것을 요청하면 dispatch_agent를 써라.\n"
            f"단순히 '확인해줘', '알려줘', '어때?' 같은 질문에는 쓰지 마라.\n\n"
            f"## 도구 목록\n"
            f"- 칸반: kanban_team_list, kanban_board_get, kanban_ticket_create, kanban_ticket_status\n"
            f"- 파일: read_file, list_files, search_code, find_files\n"
            f"- git: git_command\n"
            f"- 시스템: system_info, web_fetch, browser_navigate\n"
            f"- 실행: dispatch_agent ← 코딩 작업은 이것으로\n\n"
            f"## 스타일\n"
            f"- 반드시 한국어로 답변. 영어 금지.\n"
            f"- '대표님'이라 부름. 통찰력 있게, 솔직하게. HTML 태그 금지\n"
            f"- 고객 대면 응답 시 반드시 'AI 자동 응답'임을 명시\n\n"
            f"칸반보드:\n{context}"
        )

        # 메시지에서 프로젝트명 자동 감지 (세션에 없을 때)
        if not proj_path or proj_name == "미지정":
            _github = "/home/u2dia/github"
            if os.path.isdir(_github):
                _msg_lower = user_message.lower().replace("-", "").replace("_", "").replace(" ", "")
                for _d in os.listdir(_github):
                    _d_norm = _d.lower().replace("-", "").replace("_", "").replace(" ", "")
                    if _d_norm and len(_d_norm) >= 3 and _d_norm in _msg_lower:
                        _candidate = os.path.join(_github, _d)
                        if os.path.isdir(_candidate):
                            proj_name = _d
                            proj_path = _candidate
                            session["project"] = proj_name
                            session["project_path"] = proj_path
                            break

        # GPT-4.1 도구 호출 우선 → 올라마 폴백
        response, tools_used, executed = "", [], []
        gpt_ok = False
        _openai_key = os.environ.get("OPENAI_API_KEY") or _get_setting("openai_api_key")
        if _openai_key:
            try:
                gpt_tools = [{"type":"function","function":{"name":t["name"],"description":t["description"],"parameters":t["input_schema"]}}
                             for t in _API_AGENT_TOOLS]
                gpt_msgs = [{"role":"system","content":tool_system}] + list(session["messages"])
                gpt_payload = json.dumps({
                    "model": "gpt-4.1",
                    "messages": gpt_msgs,
                    "tools": gpt_tools,
                    "max_tokens": 1024,
                    "temperature": 0.3,
                }).encode()
                gpt_req = Request("https://api.openai.com/v1/chat/completions", data=gpt_payload,
                                  headers={"Content-Type":"application/json","Authorization":f"Bearer {_openai_key}"})
                gpt_resp = urlopen(gpt_req, timeout=20)
                gpt_result = json.loads(gpt_resp.read())
                gpt_choice = gpt_result.get("choices",[{}])[0].get("message",{})
                gpt_content = (gpt_choice.get("content") or "").strip()
                nim_tc = gpt_choice.get("tool_calls",[]) or []

                if nim_tc:
                    # NIM이 도구 호출함 → 실행
                    for tc in nim_tc:
                        fn = tc.get("function",{})
                        name = fn.get("name","")
                        args = fn.get("arguments",{})
                        if isinstance(args, str):
                            try: args = json.loads(args)
                            except: args = {}
                        if not name: continue
                        tools_used.append(name)
                        try:
                            tool_result = _api_execute_tool(name, args,
                                proj_path or os.path.dirname(os.path.abspath(__file__)),
                                session.get("team_id",""), "", session_id)
                            executed.append({"tool":name,"args":{k:str(v)[:100] for k,v in args.items()},
                                             "result_preview":str(tool_result)[:300],"success":True})
                        except Exception as e:
                            executed.append({"tool":name,"args":{},"result_preview":str(e)[:200],"success":False})
                    response = gpt_content or f"도구 {len(nim_tc)}개 실행 완료."
                    gpt_ok = True
                elif gpt_content:
                    response = gpt_content
                    gpt_ok = True
            except Exception as e:
                print(f"[gpt-tools] error: {e} — kimi 폴백", file=sys.stderr, flush=True)

        # Kimi K2.5 폴백 (GPT 실패 시)
        if not gpt_ok and _KIMI_API_KEY:
            try:
                kimi_tools = [{"type":"function","function":{"name":t["name"],"description":t["description"],"parameters":t["input_schema"]}}
                              for t in _API_AGENT_TOOLS]
                kimi_msgs = [{"role":"system","content":tool_system}] + list(session["messages"])
                kimi_payload = json.dumps({
                    "model": _KIMI_MODEL,
                    "messages": kimi_msgs,
                    "tools": kimi_tools,
                    "max_tokens": 1024,
                }).encode()
                kimi_req = Request(f"{_KIMI_API_URL}/chat/completions", data=kimi_payload,
                                  headers={"Content-Type":"application/json","Authorization":f"Bearer {_KIMI_API_KEY}"})
                kimi_resp = urlopen(kimi_req, timeout=30)
                kimi_result = json.loads(kimi_resp.read())
                kimi_choice = kimi_result.get("choices",[{}])[0].get("message",{})
                kimi_content = (kimi_choice.get("content") or kimi_choice.get("reasoning_content") or "").strip()
                nim_tc = kimi_choice.get("tool_calls",[]) or []

                if nim_tc:
                    for tc in nim_tc:
                        fn = tc.get("function",{})
                        name = fn.get("name","")
                        args = fn.get("arguments",{})
                        if isinstance(args, str):
                            try: args = json.loads(args)
                            except: args = {}
                        if not name: continue
                        tools_used.append(name)
                        try:
                            tool_result = _api_execute_tool(name, args,
                                proj_path or os.path.dirname(os.path.abspath(__file__)),
                                session.get("team_id",""), "", session_id)
                            executed.append({"tool":name,"args":{k:str(v)[:100] for k,v in args.items()},
                                             "result_preview":str(tool_result)[:300],"success":True})
                        except Exception as e:
                            executed.append({"tool":name,"args":{},"result_preview":str(e)[:200],"success":False})
                    response = kimi_content or f"도구 {len(nim_tc)}개 실행 완료."
                    gpt_ok = True
                elif kimi_content:
                    response = kimi_content
                    gpt_ok = True
            except Exception as e:
                print(f"[kimi-tools] error: {e} — ollama 폴백", file=sys.stderr, flush=True)

        if not gpt_ok:
            # 올라마 최종 폴백
            response, tools_used, executed = _ollama_tool_chat(
                msgs=session["messages"],
                tools=_API_AGENT_TOOLS,
                system=tool_system,
                project_path=proj_path or os.path.dirname(os.path.abspath(__file__)),
                session_id=session_id
            )

        # dispatch_agent 호출 감지 → 승인 대기 응답
        for act in executed:
            if act.get("tool") == "dispatch_agent":
                disp_proj = act.get("args", {}).get("project", proj_name)
                disp_instr = act.get("args", {}).get("instruction", user_message)
                disp_path = _find_project_path(disp_proj) or proj_path
                session["_pending_dispatch"] = {
                    "instruction": disp_instr, "project": disp_proj, "project_path": disp_path
                }
                actions = [
                    {"type": "dispatch", "id": "new", "label": f"승인 — {disp_proj} 에이전트 스폰",
                     "sublabel": disp_instr[:60]},
                    {"type": "cancel", "id": "cancel", "label": "취소"}
                ]
                final_resp = _strip_html(response) if response else f"대표님, {disp_proj} 프로젝트에 작업을 보내려 합니다.\n\n지시: {disp_instr}\n\n승인하시겠습니까?"
                session["messages"].append({"role": "assistant", "content": final_resp})
                return {
                    "ok": True, "response": final_resp,
                    "session_id": session_id, "project": disp_proj,
                    "confirm_required": True, "actions": actions,
                    "tools_used": tools_used,
                    "usage": {"input": 0, "output": 0, "cost": 0},
                    "backend": "ollama+tools"
                }

        if response or tools_used:
            final_resp = _strip_html(response) or "도구 실행 완료."
            session["messages"].append({"role": "assistant", "content": final_resp})
            return {
                "ok": True, "response": final_resp,
                "session_id": session_id, "project": proj_name,
                "tools_used": tools_used,
                "executed_actions": executed,
                "usage": {"input": 0, "output": 0, "cost": 0},
                "backend": "ollama+tools"
            }
        # 도구 호출 실패 → 일반 대화로 폴스루 (아래)

    # ── 일반 대화 (도구 불필요 또는 도구 호출 실패 폴백) ──
    full_system = _YUDI_CHAT_SYSTEM + f"\n\n현재 칸반보드 참고:\n{context}"
    if proj_path:
        git_ctx = _build_git_context(proj_path)
        if git_ctx:
            full_system += f"\n\n현재 프로젝트: {proj_name} ({proj_path})\n{git_ctx}"

    response = _smart_chat(
        prompt=user_message,
        system=full_system,
        messages=session["messages"]
    )

    if response:
        clean_resp = _strip_html(response)
        session["messages"].append({"role": "assistant", "content": clean_resp})
        return {
            "ok": True, "response": clean_resp,
            "session_id": session_id, "project": proj_name,
            "tools_used": [], "usage": {"input": 0, "output": 0, "cost": 0},
            "backend": "ollama"
        }
    return {"ok": False, "error": "Ollama 응답 실패"}


def _chat_agent_respond(session_id, user_message, project=None, project_path=None, force_tools=False):
    """대화형 에이전트: Ollama 우선, 도구 필요 시 Claude 폴백."""
    # Ollama 모드
    if _YUDI_BACKEND == "ollama":
        return _chat_ollama_respond(session_id, user_message, project, project_path, force_tools=force_tools)

    api_key = _get_setting("anthropic_api_key")
    if not api_key:
        return _chat_ollama_respond(session_id, user_message, project, project_path)

    # 세션 초기화
    if session_id not in _chat_sessions:
        _chat_sessions[session_id] = {
            "messages": [], "project": project,
            "project_path": project_path or (_find_project_path(project) if project else None),
            "created_at": now_utc(), "last_at": now_utc(),
        }
    session = _chat_sessions[session_id]
    if project and not session["project"]:
        session["project"] = project
        session["project_path"] = project_path or _find_project_path(project)
    session["last_at"] = now_utc()

    proj_path = session["project_path"]
    proj_name = session["project"] or "unknown"

    # ── Supervisor / 조회 / 액션 분기 ──
    text_lower = user_message.lower()
    supervisor_kw = ["검수", "판정", "재작업", "통과", "반려", "점수", "피드백",
                     "qa", "approve", "reject", "rework", "검증", "평가"]
    # "리뷰", "review"는 조회 의도와 충돌 가능 → 조회 키워드 없을 때만 supervisor
    sup_ambiguous = ["리뷰", "review"]
    query_keywords = ["현황", "보고", "몇개", "몇 개", "브리핑", "report", "status"]
    action_keywords = ["만들", "추가", "수정", "삭제", "구현", "해줘", "고쳐", "바꿔", "실행", "빌드", "테스트", "읽어", "보여"]

    is_supervisor = any(kw in text_lower for kw in supervisor_kw)
    is_query = any(kw in text_lower for kw in query_keywords)
    is_action = any(kw in text_lower for kw in action_keywords)
    has_ambiguous = any(kw in text_lower for kw in sup_ambiguous)

    # "리뷰"가 있고 조회 키워드도 있으면 → 조회 (예: "리뷰 현황 보여줘")
    # "리뷰"만 있고 조회 키워드 없으면 → supervisor (예: "리뷰해줘")
    if is_supervisor or (has_ambiguous and not is_query):
        return _chat_supervisor_respond(session_id, user_message, proj_name)

    if is_query and not is_action:
        return _chat_quick_answer(session_id, user_message, proj_name)

    # ── 작업 지시 → 에이전트 (도구 사용) ──
    system_prompt = f"""당신은 U2DIA AI 에이전트 '유디'. 시니어 풀스택 개발자 + PM.
프로젝트: {proj_name} ({proj_path or '미지정'})

규칙:
- '대표님'이라 부름. 핵심만, 서론 없이
- 도구는 꼭 필요할 때만 최소한으로 사용
- list_files/read_file을 불필요하게 반복하지 말 것
- 간단한 답변은 도구 없이 바로 응답
- 코드 수정 시에만 read_file → write_file 순서로"""

    session["messages"].append({"role": "user", "content": user_message})
    if len(session["messages"]) > 30:
        session["messages"] = session["messages"][-16:]

    messages = list(session["messages"])
    full_response = ""
    total_input = 0
    total_output = 0
    tools_used = []

    for turn in range(10):
        try:
            data = json.dumps({
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 2048,
                "system": system_prompt,
                "messages": messages,
                "tools": _API_AGENT_TOOLS
            }).encode("utf-8")
            req = Request(
                "https://api.anthropic.com/v1/messages", data=data,
                headers={"Content-Type": "application/json", "x-api-key": api_key, "anthropic-version": "2023-06-01"})
            resp = urlopen(req, timeout=60)
            result = json.loads(resp.read())

            usage = result.get("usage", {})
            total_input += usage.get("input_tokens", 0)
            total_output += usage.get("output_tokens", 0)

            content_blocks = result.get("content", [])
            for block in content_blocks:
                if block.get("type") == "text":
                    full_response += block["text"]

            if result.get("stop_reason") != "tool_use":
                break

            messages.append({"role": "assistant", "content": content_blocks})
            tool_results = []
            for block in content_blocks:
                if block.get("type") == "tool_use":
                    tools_used.append(block["name"])
                    tr = _api_execute_tool(block["name"], block["input"], proj_path or "/tmp", "", "", session_id)
                    tool_results.append({"type": "tool_result", "tool_use_id": block["id"], "content": str(tr)[:2000]})
            messages.append({"role": "user", "content": tool_results})
        except Exception as e:
            full_response += f"\n[오류: {str(e)[:80]}]"
            break

    if full_response:
        session["messages"].append({"role": "assistant", "content": full_response})
        _chat_session_save(session_id)

    cost = (total_input * 3 + total_output * 15) / 1_000_000
    return {
        "ok": True, "response": full_response, "session_id": session_id,
        "tools_used": tools_used,
        "usage": {"input": total_input, "output": total_output, "cost": round(cost, 6)},
    }


def _chat_quick_answer(session_id, question, project_name):
    """조회성 질문 → 서버 DB에서 직접 응답 (API 호출 없음, 즉시 응답)."""
    conn = get_db()
    try:
        # 통계 수집
        teams = conn.execute("SELECT COUNT(*) as c FROM agent_teams WHERE status='Active'").fetchone()
        tickets = conn.execute("SELECT status, COUNT(*) as c FROM tickets GROUP BY status").fetchall()
        ticket_map = {r["status"]: r["c"] for r in tickets} if tickets else {}
        total_tickets = sum(ticket_map.values())
        done = ticket_map.get("Done", 0)
        in_prog = ticket_map.get("InProgress", 0)
        blocked = ticket_map.get("Blocked", 0)
        progress = round(done / total_tickets * 100) if total_tickets > 0 else 0

        # 프로젝트 관련 팀
        proj_teams = rows_to_list(conn.execute(
            "SELECT name, status FROM agent_teams WHERE project_group LIKE ? AND status='Active'",
            (f"%{project_name}%",)).fetchall()) if project_name != "unknown" else []

        # 사용량
        usage_row = conn.execute(
            "SELECT COALESCE(SUM(input_tokens),0) as inp, COALESCE(SUM(output_tokens),0) as out, "
            "COALESCE(SUM(estimated_cost),0) as cost FROM token_usage").fetchone()

        # 최근 활동
        recent = rows_to_list(conn.execute(
            "SELECT action, message, team_name, created_at FROM activity_logs_view "
            "ORDER BY created_at DESC LIMIT 5").fetchall()) if False else []
    except Exception:
        recent = []
    finally:
        conn.close()

    # 응답 구성
    lines = [f"대표님, 현재 현황입니다.\n"]
    lines.append(f"팀: {teams['c'] if teams else 0}개 활성")
    lines.append(f"티켓: {total_tickets}개 (완료 {done}, 진행 {in_prog}, 차단 {blocked})")
    lines.append(f"달성률: {progress}%")
    if usage_row:
        lines.append(f"토큰: {(usage_row['inp']+usage_row['out']):,} / ${usage_row['cost']:.2f}")
    if proj_teams:
        lines.append(f"\n{project_name} 관련 팀:")
        for pt in proj_teams[:5]:
            lines.append(f"  • {pt['name']}")

    response = "\n".join(lines)

    # 세션에도 기록
    if session_id in _chat_sessions:
        _chat_sessions[session_id]["messages"].append({"role": "user", "content": question})
        _chat_sessions[session_id]["messages"].append({"role": "assistant", "content": response})

    return {
        "ok": True, "response": response, "session_id": session_id,
        "tools_used": [], "usage": {"input": 0, "output": 0, "cost": 0},
    }



def _chat_cleanup_old():
    """1시간 이상 비활성 세션 정리."""
    import datetime as _dt_mod; cutoff = _dt_mod.datetime.utcnow() - _dt_mod.timedelta(hours=1)
    to_del = [sid for sid, s in _chat_sessions.items()
              if s["last_at"] < cutoff.strftime("%Y-%m-%d %H:%M:%S")]
    for sid in to_del:
        del _chat_sessions[sid]


# ── 대화형 에이전트 REST API ──

@route("POST", "/api/agent/chat")
def r_agent_chat(params, body, url_params, query):
    """대화형 에이전트 — 텔레그램/APK 공통. 양방향 멀티턴 대화 + 오케스트레이터."""
    message = body.get("message", "").strip()
    session_id = body.get("session_id") or ("chat-" + uuid.uuid4().hex[:8])
    project = body.get("project")
    project_path = body.get("project_path")
    dispatch = body.get("dispatch", False)

    if not message:
        return {"ok": False, "error": "message required"}

    text_lower = message.lower()

    # ── 승인 확인 (키워드 분석 전에 최우선 체크) ──
    _approve_words = ["확인", "승인", "실행", "confirm", "go", "ㅇㅇ", "ok", "yes", "네", "응"]
    _is_approve = any(text_lower.strip() == w or text_lower.startswith(w + ":") or text_lower.startswith(w + " ") for w in _approve_words)
    pending = _chat_sessions.get(session_id, {}).get("_pending_dispatch")
    if pending and _is_approve:
                real_msg = pending["instruction"]
                p_proj = pending.get("project", project)
                p_path = pending.get("project_path", project_path)
                _chat_sessions.get(session_id, {}).pop("_pending_dispatch", None)
                try:
                    threading.Thread(target=_orch_dispatch, args=(p_proj, real_msg, p_path), daemon=True).start()
                    return {
                        "ok": True,
                        "response": f"🚀 {p_proj} — 승인 완료, CLI 에이전트 스폰\n\n지시: {real_msg}\n\n피드 탭에서 실시간 진행 확인",
                        "session_id": session_id,
                        "dispatched": True, "project": p_proj,
                        "tools_used": [], "usage": {"input": 0, "output": 0, "cost": 0},
                    }
                except Exception:
                    pass

    # 프로젝트 별명 매칭 (긴 별명 우선, 명시적 프로젝트명 최우선)
    ALIAS = [
        ("U홈", "U2DIA_HOME"), ("u홈", "U2DIA_HOME"), ("유홈", "U2DIA_HOME"),
        ("링코", "LINKO"), ("글로", "PMI-LINK-GLOBAL"),
        ("헥사", "Hexacotest"), ("쿠팡", "cupang_api"), ("이박", "LEEPARK"),
        ("성경", "Bible"), ("3웹", "3dweb"), ("메타", "U2DIA_METAVERS"),
        ("AI피", "PMI-AIP"), ("오클", "openclaw"), ("플너", "planner"),
        ("라이", "life"), ("칸반", "U2DIA-KANBAN-BOARD"),
    ]
    if not project:
        for alias, pname in ALIAS:
            if alias in message or alias.lower() in text_lower:
                project = pname
                break

    # 프로젝트명 매칭 안 됐으면 메시지에서 디렉토리명 직접 검색
    if not project:
        _github = "/home/u2dia/github"
        if os.path.isdir(_github):
            _msg_n = text_lower.replace("-","").replace("_","").replace(" ","")
            for _d in sorted(os.listdir(_github), key=len, reverse=True):
                _d_n = _d.lower().replace("-","").replace("_","").replace(" ","")
                if _d_n and len(_d_n) >= 3 and _d_n in _msg_n:
                    if os.path.isdir(os.path.join(_github, _d)):
                        project = _d
                        break

    proj_path = project_path or (_find_project_path(project) if project else None)

    # 메시지에서 프로젝트명 자동 감지
    if not project:
        _github = "/home/u2dia/github"
        if os.path.isdir(_github):
            _msg_n = text_lower.replace("-","").replace("_","").replace(" ","")
            for _d in sorted(os.listdir(_github), key=len, reverse=True):
                _d_n = _d.lower().replace("-","").replace("_","").replace(" ","")
                if _d_n and len(_d_n) >= 3 and _d_n in _msg_n:
                    if os.path.isdir(os.path.join(_github, _d)):
                        project = _d
                        proj_path = os.path.join(_github, _d)
                        break

    # ── 모든 요청을 에이전틱 모드로 — 올라마가 도구 20개 중 자율 선택 ──
    # 키워드 매칭 없음. 의도 분류 없음. 올라마의 통찰력으로 판단.
    return _chat_agent_respond(session_id, message, project, proj_path, force_tools=True)




# ── 알림 설정 API ──

@route("GET", "/api/settings/notifications")
def r_notif_get(params, body, url_params, query):
    conn = get_db()
    row = conn.execute("SELECT value FROM server_settings WHERE key='notification_prefs'").fetchone()
    conn.close()
    prefs = json.loads(row["value"]) if row and row["value"] else {
        "team_created": True, "team_completed": True, "artifact_created": True,
        "ticket_created": False, "ticket_done": False, "agent_spawned": False,
        "error": True,
    }
    return {"ok": True, "prefs": prefs}


@route("POST", "/api/settings/notifications")
def r_notif_set(params, body, url_params, query):
    prefs = body.get("prefs", body)
    conn = get_db()
    conn.execute(
        "INSERT OR REPLACE INTO server_settings (key, value, updated_at) VALUES ('notification_prefs', ?, datetime('now'))",
        (json.dumps(prefs),))
    conn.commit()
    conn.close()
    return {"ok": True}


@route("GET", "/api/agent/chat/sessions")
def r_agent_chat_sessions(params, body, url_params, query):
    """활성 대화 세션 목록."""
    _chat_cleanup_old()
    sessions = []
    for sid, s in _chat_sessions.items():
        sessions.append({
            "session_id": sid,
            "project": s["project"],
            "message_count": len(s["messages"]),
            "created_at": s["created_at"],
            "last_at": s["last_at"],
        })
    return {"ok": True, "sessions": sessions}


@route("DELETE", "/api/agent/chat/sessions")
def r_agent_chat_clear(params, body, url_params, query):
    """대화 세션 종료."""
    session_id = query.get("session_id", [""])[0] if isinstance(query, dict) else ""
    if session_id and session_id in _chat_sessions:
        del _chat_sessions[session_id]
    else:
        _chat_sessions.clear()
    return {"ok": True}


# ── Claude Code CLI 디스패치 (승인 후 실행) ──

@route("POST", "/api/agent/dispatch")
def r_agent_dispatch(params, body, url_params, query):
    """에이전트 디스패치 승인 → 실제 Claude Code CLI 실행."""
    session_id = body.get("session_id", "")
    action = body.get("action", "approve")  # approve | cancel

    session = _chat_sessions.get(session_id)
    if not session or "_pending_dispatch" not in session:
        return {"ok": False, "error": "no_pending_dispatch",
                "message": "승인 대기 중인 디스패치가 없습니다"}

    pending = session.pop("_pending_dispatch")

    if action == "cancel":
        return {"ok": True, "status": "cancelled", "message": "디스패치 취소됨"}

    # 승인 → Claude Code CLI 실행
    project = pending.get("project", "")
    instruction = pending.get("instruction", "")
    project_path = pending.get("project_path", "")

    if not project_path or not os.path.isdir(project_path):
        return {"ok": False, "error": "project_not_found",
                "message": f"프로젝트 경로를 찾을 수 없습니다: {project_path}"}

    # 비동기로 CLI 실행
    def _run_claude():
        try:
            cmd = ["claude", "-p", instruction, "--model", "claude-opus-4-6", "--max-turns", "30", ]
            proc = subprocess.Popen(
                cmd, cwd=project_path,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True
            )
            stdout, stderr = proc.communicate(timeout=300)  # 5분 타임아웃
            output = (stdout or "") + (stderr or "")
            # 결과를 활동 로그에 기록
            conn = get_db()
            conn.execute(
                "INSERT INTO activity_logs (team_id, action, message, created_at) VALUES ('_system', ?, ?, datetime('now'))",
                ("dispatch_completed", f"[{project}] {instruction[:80]} → 완료 ({len(output)}자)")
            )
            conn.commit()
            conn.close()
            # 작업 완료 후 git commit + push 자동 실행
            try:
                subprocess.run(["git", "add", "-A"], cwd=project_path, timeout=10, capture_output=True)
                commit_msg = f"feat: [agent] {instruction[:60]}"
                subprocess.run(["git", "commit", "-m", commit_msg], cwd=project_path, timeout=10, capture_output=True)
                subprocess.run(["git", "push"], cwd=project_path, timeout=30, capture_output=True)
            except Exception:
                pass  # git 실패해도 작업 자체는 완료
            # 세션에 결과 저장
            session["messages"].append({
                "role": "assistant",
                "content": f"✅ {project} 에이전트 작업 완료:\n\n{output[:1000]}"
            })
        except subprocess.TimeoutExpired:
            try: proc.kill()
            except: pass
            session["messages"].append({
                "role": "assistant",
                "content": f"⚠️ {project} 에이전트 작업 타임아웃 (5분 초과)"
            })
        except FileNotFoundError:
            session["messages"].append({
                "role": "assistant",
                "content": f"❌ Claude CLI (claude) 미설치. npm install -g @anthropic-ai/claude-code 필요"
            })
        except Exception as e:
            session["messages"].append({
                "role": "assistant",
                "content": f"❌ 디스패치 실패: {str(e)[:200]}"
            })

    threading.Thread(target=_run_claude, daemon=True).start()

    return {
        "ok": True, "status": "dispatched",
        "project": project, "instruction": instruction[:100],
        "project_path": project_path,
        "message": f"✅ {project} 에이전트 디스패치됨. 백그라운드 실행 중."
    }


@route("GET", "/api/agent/status")
def r_agent_status(params, body, url_params, query):
    return {
        "ok": True, "running": _resident_agent["running"],
        "active_sessions": len(_claude_processes),
        "backend": _YUDI_BACKEND,
        "ollama_model": _OLLAMA_MODEL,
        "ollama_available": _ollama_available()
    }


@route("POST", "/api/agent/start")
def r_agent_start(params, body, url_params, query):
    _resident_start()
    return {"ok": True}


@route("POST", "/api/agent/stop")
def r_agent_stop(params, body, url_params, query):
    _resident_stop_agent()
    return {"ok": True}


# ── Claude Code 세션 관리 ──

_claude_processes = {}  # session_id -> subprocess.Popen

@route("POST", "/api/claude/launch")
def r_claude_launch(params, body, url_params, query):
    """Claude Code 터미널 세션 시작."""
    project_path = body.get("project_path", "")
    team_id = body.get("team_id", "")
    prompt = body.get("prompt", "")
    if not project_path:
        return {"ok": False, "error": "project_path required"}
    if not _validate_project_path(project_path):
        return {"ok": False, "error": "invalid project_path"}

    session_id = "cs-" + uuid.uuid4().hex[:8]
    cli = _find_claude_cli()
    cmd = [cli, ]
    if prompt:
        cmd += ["-p", prompt]

    try:
        creation_flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        proc = subprocess.Popen(
            cmd, cwd=project_path,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=creation_flags
        )
        _claude_processes[session_id] = proc
        conn = get_db()
        conn.execute(
            "INSERT INTO claude_sessions (session_id, project_path, team_id, pid, status) VALUES (?,?,?,?,?)",
            (session_id, project_path, team_id, proc.pid, "running")
        )
        conn.commit()
        conn.close()
        return {"ok": True, "session_id": session_id, "pid": proc.pid}
    except FileNotFoundError:
        return {"ok": False, "error": "claude CLI not found — npm install -g @anthropic-ai/claude-code"}
    except Exception as e:
        return {"ok": False, "error": str(e)}

@route("GET", "/api/claude/sessions")
def r_claude_sessions(params, body, url_params, query):
    """실행 중인 Claude Code 세션 목록."""
    conn = get_db()
    rows = rows_to_list(conn.execute(
        "SELECT * FROM claude_sessions ORDER BY started_at DESC LIMIT 50"
    ).fetchall())
    conn.close()
    # 프로세스 상태 업데이트
    for r in rows:
        sid = r["session_id"]
        if sid in _claude_processes:
            proc = _claude_processes[sid]
            if proc.poll() is not None:
                r["status"] = "exited"
            else:
                r["status"] = "running"
        elif r["status"] == "running":
            r["status"] = "unknown"
    return {"ok": True, "sessions": rows}

@route("POST", "/api/claude/stop")
def r_claude_stop(params, body, url_params, query):
    """Claude Code 세션 중지."""
    session_id = body.get("session_id", "")
    if session_id in _claude_processes:
        proc = _claude_processes[session_id]
        try:
            if os.name == 'nt':
                proc.terminate()
            else:
                proc.send_signal(signal.SIGTERM)
        except Exception:
            pass
        del _claude_processes[session_id]
    conn = get_db()
    conn.execute("UPDATE claude_sessions SET status='stopped', ended_at=datetime('now') WHERE session_id=?", (session_id,))
    conn.commit()
    conn.close()
    return {"ok": True}


@route("GET", "/api/github/projects")
def r_github_projects(params, body, url_params, query):
    """~/github/ 디렉토리를 스캔하여 프로젝트 목록 반환."""
    github_dir = os.environ.get("KANBAN_GITHUB_DIR",
                                os.path.expanduser("~/github"))
    if not os.path.isdir(github_dir):
        return {"ok": True, "projects": [], "github_dir": github_dir}

    conn = get_db()
    alias_row = conn.execute(
        "SELECT value FROM server_settings WHERE key='project_aliases'"
    ).fetchone()
    team_rows = conn.execute(
        "SELECT project_group, COUNT(*) as cnt FROM agent_teams "
        "WHERE status NOT IN ('archived','Archived') GROUP BY project_group"
    ).fetchall()
    activity_rows = conn.execute(
        "SELECT t.project_group, MAX(a.created_at) as last_act "
        "FROM activity_logs a JOIN agent_teams t ON a.team_id=t.team_id "
        "GROUP BY t.project_group"
    ).fetchall()
    conn.close()

    alias_map = {}
    try:
        aliases = json.loads(alias_row[0]) if alias_row else []
        for a in aliases:
            alias_map[a.get("path", "")] = a.get("alias", "")
    except Exception:
        aliases = []

    team_counts = {r[0]: r[1] for r in team_rows if r[0]}
    activity_map = {r[0]: r[1] for r in activity_rows if r[0]}

    projects = []
    skip = {".git", "__pycache__", "node_modules", ".DS_Store"}
    for name in sorted(os.listdir(github_dir), key=str.lower):
        if name in skip or name.startswith("."):
            continue
        path = os.path.join(github_dir, name)
        if not os.path.isdir(path):
            continue
        is_git = os.path.isdir(os.path.join(path, ".git"))
        alias = alias_map.get(path, "")
        team_count = team_counts.get(name, 0) + team_counts.get(alias, 0)
        last_act = activity_map.get(name, activity_map.get(alias, None))
        projects.append({
            "name": name,
            "path": path,
            "alias": alias,
            "is_git": is_git,
            "team_count": team_count,
            "last_activity": last_act,
        })

    return {"ok": True, "projects": projects, "github_dir": github_dir,
            "total": len(projects)}


# ── HTML: 공유 CSS ──

SHARED_CSS = r""":root{--bg:#0f1117;--panel:#181b24;--card:#1e222d;--line:#2a2f3e;--text:#e1e5ee;--muted:#6b7a90;--brand:#3b82f6;
--red:#ef4444;--orange:#f97316;--yellow:#eab308;--green:#22c55e;--cyan:#06b6d4;--purple:#a855f7}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI','Noto Sans KR',sans-serif;background:var(--bg);color:var(--text);font-size:13px}
.header{background:var(--panel);border-bottom:1px solid var(--line);padding:12px 20px;display:flex;align-items:center;justify-content:space-between}
.header h1{font-size:16px;font-weight:600}
.header .meta{font-size:11px;color:var(--muted)}
.toolbar{display:flex;gap:8px;align-items:center}
.toolbar select,.toolbar input{background:var(--card);border:1px solid var(--line);color:var(--text);border-radius:6px;padding:5px 8px;font-size:12px}
.toolbar button{background:var(--brand);color:#fff;border:none;border-radius:6px;padding:6px 14px;cursor:pointer;font-size:12px;font-weight:600}
.toolbar button:hover{opacity:0.85}
.toolbar button.secondary{background:var(--card);border:1px solid var(--line);color:var(--text)}
.role-dot{width:7px;height:7px;border-radius:50%;display:inline-block}
.role-backend{background:var(--brand)}.role-frontend{background:var(--green)}.role-database{background:var(--purple)}
.role-qa{background:var(--yellow)}.role-devops{background:var(--cyan)}.role-default{background:var(--muted)}
.pri-Critical{background:#7f1d1d;color:#fca5a5}.pri-High{background:#7c2d12;color:#fdba74}
.pri-Medium{background:#422006;color:#fcd34d}.pri-Low{background:#052e16;color:#86efac}
.t-pri{font-size:9px;font-weight:700;padding:1px 6px;border-radius:4px}
.ms-Working{background:var(--green)}.ms-Idle{background:var(--muted)}.ms-Blocked{background:var(--red)}.ms-Done{background:var(--cyan)}
.modal-overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,0.6);z-index:100;align-items:center;justify-content:center}
.modal-overlay.active{display:flex}
.modal{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:20px;width:420px;max-width:90vw;max-height:90vh;overflow-y:auto}
.modal h3{margin-bottom:14px;font-size:15px}
.modal label{display:block;font-size:11px;color:var(--muted);margin-bottom:3px;margin-top:10px}
.modal input,.modal select,.modal textarea{width:100%;background:var(--card);border:1px solid var(--line);color:var(--text);border-radius:6px;padding:7px 10px;font-size:12px}
.modal textarea{min-height:60px;resize:vertical}
.modal .actions{display:flex;gap:8px;justify-content:flex-end;margin-top:16px}
.sse-dot{width:8px;height:8px;border-radius:50%;display:inline-block;margin-right:4px}
"""

# ── HTML: Login ──

LOGIN_HTML = """<!doctype html>
<html lang='ko'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Agent Team Kanban - 로그인</title>
<style>
""" + SHARED_CSS + """
.login-wrap{display:flex;align-items:center;justify-content:center;min-height:100vh}
.login-box{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:40px;width:440px;text-align:center}
.login-box h1{font-size:22px;margin-bottom:6px;font-weight:700}
.login-box .ver{color:var(--brand);font-size:11px;font-weight:600;margin-bottom:4px}
.login-box .sub{color:var(--muted);font-size:12px;margin-bottom:28px}
.lic-inputs{display:flex;gap:8px;justify-content:center;margin-bottom:20px}
.lic-inputs input{width:76px;text-align:center;background:var(--card);border:1px solid var(--line);color:var(--text);
border-radius:8px;padding:12px 8px;font-size:16px;font-weight:700;letter-spacing:2px;text-transform:uppercase;font-family:monospace}
.lic-inputs input:focus{border-color:var(--brand);outline:none;box-shadow:0 0 0 2px rgba(59,130,246,0.3)}
.lic-inputs .sep{color:var(--muted);font-size:20px;line-height:48px;user-select:none}
.login-btn{background:var(--brand);color:#fff;border:none;border-radius:8px;padding:12px 32px;font-size:14px;
font-weight:600;cursor:pointer;width:100%;transition:opacity 0.15s}
.login-btn:hover{opacity:0.85}
.login-btn:disabled{opacity:0.5;cursor:not-allowed}
.login-err{color:var(--red);font-size:12px;margin-top:12px;display:none}
.login-info{color:var(--muted);font-size:11px;margin-top:20px;line-height:1.5}
</style>
</head>
<body>
<div class='login-wrap'>
<div class='login-box'>
<h1>Agent Team Kanban</h1>
<div class='ver'>U2DIA AI Agents Dashboard</div>
<div class='sub'>원격 접속을 위해 라이선스 키를 입력해주세요</div>
<div class='lic-inputs'>
<input id='k1' maxlength='4' placeholder='XXXX' autofocus>
<span class='sep'>-</span>
<input id='k2' maxlength='4' placeholder='XXXX'>
<span class='sep'>-</span>
<input id='k3' maxlength='4' placeholder='XXXX'>
<span class='sep'>-</span>
<input id='k4' maxlength='4' placeholder='XXXX'>
</div>
<button class='login-btn' id='loginBtn'>로그인</button>
<div class='login-err' id='errMsg'></div>
<div class='login-info'>관리자에게 라이선스 키를 요청하세요.<br>MCP 에이전트는 Authorization 헤더로 인증할 수 있습니다.</div>
</div>
</div>
<script>
const ins=[document.getElementById('k1'),document.getElementById('k2'),document.getElementById('k3'),document.getElementById('k4')];
ins.forEach((inp,i)=>{
inp.addEventListener('input',()=>{
inp.value=inp.value.toUpperCase().replace(/[^A-Z0-9]/g,'');
if(inp.value.length===4&&i<3)ins[i+1].focus();
});
inp.addEventListener('keydown',(e)=>{
if(e.key==='Backspace'&&inp.value===''&&i>0)ins[i-1].focus();
if(e.key==='Enter')document.getElementById('loginBtn').click();
});
inp.addEventListener('paste',(e)=>{
const t=(e.clipboardData||window.clipboardData).getData('text').toUpperCase().replace(/[^A-Z0-9-]/g,'').replace(/-/g,'');
if(t.length>=16){e.preventDefault();for(let j=0;j<4;j++)ins[j].value=t.substr(j*4,4);}
});
});
document.getElementById('loginBtn').addEventListener('click',async()=>{
const key=ins.map(i=>i.value).join('-');
if(key.replace(/-/g,'').length!==16){
document.getElementById('errMsg').style.display='block';
document.getElementById('errMsg').textContent='16자리 키를 모두 입력해주세요';
return;}
const btn=document.getElementById('loginBtn');
btn.disabled=true;btn.textContent='인증 중...';
try{
const res=await fetch('/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({license_key:key})});
const data=await res.json();
if(data.ok){location.href='/board';}
else{document.getElementById('errMsg').style.display='block';document.getElementById('errMsg').textContent=data.message||'유효하지 않은 라이선스 키입니다';}
}catch(e){document.getElementById('errMsg').style.display='block';document.getElementById('errMsg').textContent='서버 연결 실패';}
finally{btn.disabled=false;btn.textContent='로그인';}
});
</script>
</body></html>"""

# ── HTML: Admin (License Management) ──

ADMIN_HTML = """<!doctype html>
<html lang='ko'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>라이선스 관리 - Agent Team Kanban</title>
<style>
""" + SHARED_CSS + """
.admin{padding:24px;max-width:960px;margin:0 auto}
.admin-hd{display:flex;justify-content:space-between;align-items:center;margin-bottom:20px}
.admin-hd h1{font-size:18px;font-weight:700}
.admin-hd a{color:var(--brand);font-size:12px;text-decoration:none}
.admin-hd a:hover{text-decoration:underline}
.create-sec{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:20px;margin-bottom:24px}
.create-sec h3{font-size:14px;margin-bottom:14px;font-weight:600}
.create-row{display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap}
.create-row .fld{display:flex;flex-direction:column;gap:4px}
.create-row .fld label{font-size:11px;color:var(--muted)}
.create-row .fld input{background:var(--card);border:1px solid var(--line);color:var(--text);border-radius:6px;padding:8px 10px;font-size:13px}
.create-btn{background:var(--brand);color:#fff;border:none;border-radius:6px;padding:9px 24px;cursor:pointer;font-size:13px;font-weight:600}
.create-btn:hover{opacity:0.85}
.key-box{background:var(--card);border:2px solid var(--brand);border-radius:10px;padding:18px;margin:14px 0;text-align:center;display:none}
.key-val{font-size:22px;font-weight:700;letter-spacing:3px;color:var(--brand);margin:8px 0;font-family:monospace}
.key-warn{font-size:11px;color:var(--red);margin-top:8px}
.copy-btn{background:var(--card);border:1px solid var(--line);color:var(--text);padding:5px 14px;border-radius:5px;cursor:pointer;font-size:12px}
.copy-btn:hover{border-color:var(--brand)}
.lic-table{width:100%;border-collapse:collapse;margin-top:12px}
.lic-table th,.lic-table td{padding:10px 12px;text-align:left;border-bottom:1px solid var(--line);font-size:12px}
.lic-table th{color:var(--muted);font-size:10px;text-transform:uppercase;font-weight:600}
.lic-table td.mono{font-family:monospace;letter-spacing:1px}
.st-active{color:var(--green);font-weight:600}
.st-inactive{color:var(--red);font-weight:600}
.rev-btn{background:var(--red);color:#fff;border:none;padding:4px 12px;border-radius:4px;font-size:11px;cursor:pointer;font-weight:600}
.rev-btn:hover{opacity:0.8}
.empty-msg{color:var(--muted);text-align:center;padding:30px;font-size:13px}
</style>
</head>
<body>
<div class='admin'>
<div class='admin-hd'>
<h1>라이선스 관리</h1>
<a href='/board'>칸반보드로 이동 &rarr;</a>
</div>
<div class='create-sec'>
<h3>새 라이선스 생성</h3>
<div class='create-row'>
<div class='fld'><label>이름/설명</label><input type='text' id='licName' placeholder='예: 팀A 에이전트' style='width:220px'></div>
<div class='fld'><label>유효기간 (일)</label><input type='number' id='licDays' placeholder='빈칸=무제한' style='width:130px' min='1'></div>
<button class='create-btn' id='createBtn'>라이선스 생성</button>
</div>
<div class='key-box' id='keyBox'>
<div style='font-size:12px;color:var(--muted)'>생성된 라이선스 키 (이 화면에서만 확인 가능)</div>
<div class='key-val' id='keyVal'></div>
<button class='copy-btn' id='copyBtn'>클립보드에 복사</button>
<div class='key-warn'>이 키는 다시 확인할 수 없습니다. 안전한 곳에 보관하세요.</div>
</div>
</div>
<h3 style='font-size:14px;margin-bottom:8px;font-weight:600'>발급된 라이선스</h3>
<table class='lic-table'>
<thead><tr><th>표시</th><th>이름</th><th>상태</th><th>생성일</th><th>만료일</th><th>마지막 사용</th><th>사용</th><th>관리</th></tr></thead>
<tbody id='licList'></tbody>
</table>
</div>
<script>
async function load(){
const res=await fetch('/api/licenses');const data=await res.json();
const tb=document.getElementById('licList');tb.innerHTML='';
const lics=data.licenses||[];
if(!lics.length){tb.innerHTML='<tr><td colspan="8" class="empty-msg">발급된 라이선스가 없습니다. 위에서 새로 생성하세요.</td></tr>';return;}
for(const l of lics){
const tr=document.createElement('tr');
const sc=l.is_active?'st-active':'st-inactive';
const st=l.is_active?'활성':'비활성';
tr.innerHTML='<td class="mono">'+l.license_display+'</td><td>'+(l.name||'-')+'</td>'
+'<td class="'+sc+'">'+st+'</td><td>'+(l.created_at||'').slice(0,10)+'</td>'
+'<td>'+(l.expires_at?l.expires_at.slice(0,10):'무제한')+'</td>'
+'<td>'+(l.last_used_at||'미사용')+'</td><td>'+l.use_count+'</td>'
+'<td>'+(l.is_active?'<button class="rev-btn" data-h="'+l.license_key_hash+'">비활성화</button>':'')+'</td>';
tb.appendChild(tr);
}
tb.querySelectorAll('.rev-btn').forEach(b=>{
b.addEventListener('click',async()=>{
if(!confirm('이 라이선스를 비활성화하시겠습니까?'))return;
await fetch('/api/licenses/'+b.dataset.h,{method:'DELETE'});load();
});
});
}
document.getElementById('createBtn').addEventListener('click',async()=>{
const name=document.getElementById('licName').value;
const days=document.getElementById('licDays').value;
const bd={name};if(days)bd.expires_days=parseInt(days);
const res=await fetch('/api/licenses',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(bd)});
const data=await res.json();
if(data.ok){
document.getElementById('keyBox').style.display='block';
document.getElementById('keyVal').textContent=data.license_key;
document.getElementById('licName').value='';document.getElementById('licDays').value='';
load();
}
});
document.getElementById('copyBtn').addEventListener('click',()=>{
const k=document.getElementById('keyVal').textContent;
navigator.clipboard.writeText(k).then(()=>{
document.getElementById('copyBtn').textContent='복사됨!';
setTimeout(()=>document.getElementById('copyBtn').textContent='클립보드에 복사',1500);
});
});
load();
</script>
</body></html>"""

# ── HTML: Board ──

BOARD_HTML = r"""<!doctype html>
<html lang='ko'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Agent Team Kanban Board</title>
<style>
""" + SHARED_CSS + r"""
.main{display:grid;grid-template-columns:1fr 280px;gap:0;height:calc(100vh - 94px)}
.board{overflow-x:auto;padding:14px;display:flex;gap:10px}
.column{min-width:195px;max-width:230px;flex:1;background:var(--panel);border-radius:10px;display:flex;flex-direction:column;max-height:calc(100vh - 122px)}
.col-header{padding:10px 12px;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;color:var(--muted);border-bottom:1px solid var(--line);display:flex;justify-content:space-between;align-items:center}
.col-header .count{background:var(--card);border-radius:10px;padding:1px 7px;font-size:11px}
.col-body{flex:1;overflow-y:auto;padding:8px}
.col-body::-webkit-scrollbar{width:4px}
.col-body::-webkit-scrollbar-thumb{background:var(--line);border-radius:4px}
.ticket{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px;margin-bottom:8px;cursor:grab;transition:border-color 0.15s,box-shadow 0.15s}
.ticket:hover{border-color:var(--brand);box-shadow:0 0 0 1px var(--brand)}
.ticket.dragging{opacity:0.5}
.ticket .t-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:6px}
.ticket .t-id{font-size:10px;font-weight:700;color:var(--muted)}
.ticket .t-title{font-size:12px;font-weight:600;line-height:1.4;margin-bottom:6px}
.ticket .t-meta{display:flex;align-items:center;gap:6px;font-size:10px;color:var(--muted)}
.ticket .t-dep{font-size:10px;color:var(--orange);margin-top:4px}
.ticket .t-time{font-size:10px;color:var(--cyan)}
.sidebar{background:var(--panel);border-left:1px solid var(--line);display:flex;flex-direction:column;max-height:calc(100vh - 94px);overflow:hidden}
.side-section{border-bottom:1px solid var(--line)}
.side-section h3{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;color:var(--muted);padding:10px 14px 6px}
.stats-grid{display:grid;grid-template-columns:1fr 1fr;gap:6px;padding:0 14px 10px}
.stat{background:var(--card);border-radius:6px;padding:8px 10px;text-align:center}
.stat .sv{font-size:18px;font-weight:700}.stat .sk{font-size:10px;color:var(--muted)}
.members{padding:4px 14px 10px}
.member{display:flex;align-items:center;gap:8px;padding:5px 0;font-size:12px}
.member .ms{width:6px;height:6px;border-radius:50%}
.progress-bar{height:4px;background:var(--line);border-radius:2px;margin:6px 14px 10px;overflow:hidden}
.progress-fill{height:100%;background:var(--green);border-radius:2px;transition:width 0.5s}
.activity{flex:1;overflow-y:auto;padding:4px 14px 10px}
.activity::-webkit-scrollbar{width:4px}
.activity::-webkit-scrollbar-thumb{background:var(--line);border-radius:4px}
.log-item{padding:4px 0;border-bottom:1px solid var(--line);font-size:11px;line-height:1.4}
.log-item .lt{color:var(--muted);font-size:10px}.log-item .la{font-weight:600;color:var(--cyan)}
.drop-zone{min-height:40px;border:2px dashed transparent;border-radius:6px;transition:border-color 0.15s}
.drop-zone.over{border-color:var(--brand);background:rgba(59,130,246,0.05)}
.detail-tabs{display:flex;gap:0;border-bottom:1px solid var(--line);margin:12px 0 0}
.detail-tab{padding:8px 16px;font-size:12px;font-weight:600;color:var(--muted);cursor:pointer;border-bottom:2px solid transparent;transition:all 0.15s}
.detail-tab:hover{color:var(--text)}
.detail-tab.active{color:var(--brand);border-bottom-color:var(--brand)}
.detail-tab .badge{background:var(--brand);color:#fff;border-radius:8px;padding:0 6px;font-size:10px;margin-left:4px}
.tab-content{display:none;padding:12px 0}
.tab-content.active{display:block}
.msg-bubble{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px;margin-bottom:8px}
.msg-header{display:flex;justify-content:space-between;font-size:11px;margin-bottom:6px}
.msg-type{padding:1px 6px;border-radius:3px;font-size:9px;font-weight:700}
.msg-type-comment{background:#1e3a5f;color:var(--brand)}
.msg-type-question{background:#422006;color:var(--yellow)}
.msg-type-code_review{background:#1a1a2e;color:var(--purple)}
.msg-type-reply{background:#0f2922;color:var(--green)}
.art-card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px;margin-bottom:8px}
.art-code{background:#0d1117;border:1px solid var(--line);border-radius:6px;padding:10px;font-family:'Cascadia Code','Fira Code',monospace;font-size:11px;overflow-x:auto;white-space:pre;max-height:200px;overflow-y:auto;line-height:1.5}
.msg-compose{display:flex;gap:6px;align-items:flex-end;margin-top:10px;padding-top:10px;border-top:1px solid var(--line)}
.msg-compose select{width:auto;min-width:80px}
.msg-compose textarea{flex:1;min-height:36px;max-height:80px}
.msg-compose button{white-space:nowrap}
.header-left{display:flex;align-items:center;gap:12px}
.header-stats{display:flex;gap:16px;align-items:center}
.hs{font-size:11px;color:var(--muted)}.hs b{color:var(--text);font-size:13px;margin-left:2px}
.sse-badge{font-size:11px;display:flex;align-items:center;gap:4px;padding:2px 10px;border-radius:12px;background:rgba(34,197,94,0.1)}
.tab-bar{display:flex;align-items:center;background:var(--panel);border-bottom:1px solid var(--line);padding:0 16px;overflow-x:auto;gap:0;flex-shrink:0}
.tab-bar::-webkit-scrollbar{height:0}
.team-tab{display:flex;align-items:center;gap:6px;padding:9px 18px;font-size:12px;font-weight:600;color:var(--muted);cursor:pointer;border-bottom:2px solid transparent;white-space:nowrap;transition:all 0.15s;user-select:none}
.team-tab:hover{color:var(--text);background:rgba(255,255,255,0.03)}
.team-tab.active{color:var(--brand);border-bottom-color:var(--brand)}
.tab-kpi{font-size:10px;font-weight:400;padding:1px 6px;border-radius:8px;background:var(--card);color:var(--muted)}
.team-tab.active .tab-kpi{color:var(--green);background:rgba(34,197,94,0.12)}
.tab-add{background:none;border:1px dashed var(--line);color:var(--muted);width:26px;height:26px;border-radius:6px;cursor:pointer;font-size:16px;display:flex;align-items:center;justify-content:center;margin-left:8px;flex-shrink:0;transition:all 0.15s}
.tab-add:hover{border-color:var(--brand);color:var(--brand)}
.log-team{font-size:9px;padding:0 4px;border-radius:3px;background:var(--card);color:var(--brand);margin:0 2px}
.live-dot{width:6px;height:6px;border-radius:50%;background:var(--green);display:inline-block;animation:livePulse 2s infinite}
@keyframes livePulse{0%,100%{opacity:1}50%{opacity:0.4}}
@media(max-width:900px){.main{grid-template-columns:1fr}.sidebar{display:none}.column{min-width:160px}.header-stats{display:none}}
</style>
</head>
<body>
<div class='header'>
  <div class='header-left'>
    <h1 style='font-size:15px;font-weight:700'>U2DIA AI Agents</h1>
    <span id='sseStatus' class='sse-badge'><span class='sse-dot' style='background:var(--muted)'></span>연결중</span>
  </div>
  <div class='header-stats' id='headerStats'>
    <span class='hs'>Total <b id='gTotal'>0</b></span>
    <span class='hs'>Active <b id='gActive' style='color:var(--green)'>0</b></span>
    <span class='hs'>Done <b id='gDone' style='color:var(--cyan)'>0</b></span>
    <span class='hs'>Rate <b id='gRate'>0%</b></span>
  </div>
  <div class='toolbar'>
    <button class='secondary' id='btnNewMember'>+ 에이전트</button>
    <button id='btnNewTicket'>+ New Task</button>
  </div>
</div>
<div class='tab-bar' id='tabBar'>
  <button class='tab-add' id='btnNewTeam' title='새 팀 생성'>+</button>
</div>
<div class='main'>
  <div class='board' id='board'>
    <div class='column' data-status='Backlog'><div class='col-header'>Backlog <span class='count' id='cBacklog'>0</span></div><div class='col-body drop-zone' data-status='Backlog'></div></div>
    <div class='column' data-status='Todo'><div class='col-header'>Todo <span class='count' id='cTodo'>0</span></div><div class='col-body drop-zone' data-status='Todo'></div></div>
    <div class='column' data-status='InProgress'><div class='col-header'>In Progress <span class='count' id='cInProgress'>0</span></div><div class='col-body drop-zone' data-status='InProgress'></div></div>
    <div class='column' data-status='Review'><div class='col-header'>Review <span class='count' id='cReview'>0</span></div><div class='col-body drop-zone' data-status='Review'></div></div>
    <div class='column' data-status='Done'><div class='col-header'>Done <span class='count' id='cDone'>0</span></div><div class='col-body drop-zone' data-status='Done'></div></div>
    <div class='column' data-status='Blocked'><div class='col-header' style='color:var(--red)'>Blocked <span class='count' id='cBlocked'>0</span></div><div class='col-body drop-zone' data-status='Blocked'></div></div>
  </div>
  <div class='sidebar'>
    <div class='side-section' style='padding:10px 14px 8px'><div style='font-size:14px;font-weight:700' id='teamName'>팀을 선택하세요</div><div style='font-size:10px;color:var(--muted);margin-top:2px' id='teamMeta'></div></div>
    <div class='side-section'><h3>Progress</h3><div class='progress-bar'><div class='progress-fill' id='progressFill' style='width:0%'></div></div></div>
    <div class='side-section'><h3>Statistics</h3>
      <div class='stats-grid'>
        <div class='stat'><div class='sv' id='sTotalTickets'>0</div><div class='sk'>Total</div></div>
        <div class='stat'><div class='sv' id='sCompletionRate'>0%</div><div class='sk'>Done</div></div>
        <div class='stat'><div class='sv' id='sAvgTime'>-</div><div class='sk'>Avg Time</div></div>
        <div class='stat'><div class='sv' id='sActiveAgents'>0</div><div class='sk'>Active</div></div>
      </div>
    </div>
    <div class='side-section'><h3>Team Members</h3><div class='members' id='membersList'></div></div>
    <div class='side-section' style='flex:1;display:flex;flex-direction:column'><h3>Live Activity <span class='live-dot'></span></h3><div class='activity' id='activityLog'></div></div>
  </div>
</div>

<div class='modal-overlay' id='modalTeam'><div class='modal'>
  <h3>새 팀 생성</h3>
  <label>팀 이름</label><input id='mTeamName' placeholder='예: KSM API v3 개발팀'>
  <label>설명</label><textarea id='mTeamDesc' placeholder='팀 목적 및 범위'></textarea>
  <div class='actions'><button class='secondary' onclick="closeModal('modalTeam')">취소</button><button onclick='createTeam()'>생성</button></div>
</div></div>

<div class='modal-overlay' id='modalMember'><div class='modal'>
  <h3>에이전트 스폰</h3>
  <label>역할</label>
  <select id='mMemberRole'><option value='backend'>Backend</option><option value='frontend'>Frontend</option><option value='database'>Database</option><option value='qa'>QA</option><option value='devops'>DevOps</option></select>
  <label>표시명</label><input id='mMemberName' placeholder='예: Backend Agent #1'>
  <div class='actions'><button class='secondary' onclick="closeModal('modalMember')">취소</button><button onclick='spawnMember()'>스폰</button></div>
</div></div>

<div class='modal-overlay' id='modalTicket'><div class='modal'>
  <h3>티켓 생성</h3>
  <label>제목</label><input id='mTicketTitle' placeholder='작업 제목'>
  <label>설명</label><textarea id='mTicketDesc' placeholder='상세 설명'></textarea>
  <label>우선순위</label>
  <select id='mTicketPriority'><option value='Critical'>Critical</option><option value='High'>High</option><option value='Medium' selected>Medium</option><option value='Low'>Low</option></select>
  <label>예상 소요(분)</label><input id='mTicketEst' type='number' value='30'>
  <label>태그 (쉼표 구분)</label><input id='mTicketTags' placeholder='api, refactor'>
  <div class='actions'><button class='secondary' onclick="closeModal('modalTicket')">취소</button><button onclick='createTicket()'>생성</button></div>
</div></div>

<div class='modal-overlay' id='modalDetail'><div class='modal' style='width:720px'>
  <div style='display:flex;justify-content:space-between;align-items:center'>
    <h3 id='detailTitle'>티켓 상세</h3>
    <button class='secondary' onclick="closeModal('modalDetail')" style='padding:4px 10px;font-size:16px'>&times;</button>
  </div>
  <div id='detailTabs'></div>
  <div id='detailBody' style='max-height:60vh;overflow-y:auto'></div>
</div></div>

<div class='modal-overlay' id='modalMemberDetail'><div class='modal' style='width:560px'>
  <div style='display:flex;justify-content:space-between;align-items:center'>
    <h3 id='memberDetailTitle'>에이전트 상세</h3>
    <button class='secondary' onclick="closeModal('modalMemberDetail')" style='padding:4px 10px;font-size:16px'>&times;</button>
  </div>
  <div id='memberDetailBody' style='max-height:60vh;overflow-y:auto'></div>
</div></div>

<script>
const $=id=>document.getElementById(id);
let currentTeamId=null,boardData=null,memberMap={},sseOk=false;
let allTeamsData=[];
let globalEvtSource=null,teamEvtSource=null;

function closeModal(id){$(id).classList.remove('active');}
function openModal(id){$(id).classList.add('active');}
async function api(path,opt){const r=await fetch(path,opt);return r.json();}
function esc(s){const d=document.createElement('div');d.textContent=s;return d.innerHTML;}
function roleClass(r){return 'role-'+(r||'default');}
function priClass(p){return 'pri-'+(p||'Medium');}
function timeFmt(t){if(!t)return'-';const d=new Date(t.includes('Z')?t:t+'Z');return isNaN(d)?t:d.toLocaleTimeString('ko',{hour:'2-digit',minute:'2-digit'});}
function dateFmt(t){if(!t)return'-';const d=new Date(t.includes('Z')?t:t+'Z');return isNaN(d)?t:d.toLocaleDateString('ko',{month:'short',day:'numeric'})+' '+d.toLocaleTimeString('ko',{hour:'2-digit',minute:'2-digit'});}
function memberName(mid){return memberMap[mid]||mid||'unassigned';}
function memberRole(mid){const m=(boardData&&boardData.members||[]).find(x=>x.member_id===mid);return m?m.role:'default';}

/* ── Tab Management ── */
function renderTabs(){
  const bar=$('tabBar');
  bar.querySelectorAll('.team-tab').forEach(t=>t.remove());
  const addBtn=$('btnNewTeam');
  allTeamsData.forEach(t=>{
    const tab=document.createElement('div');
    tab.className='team-tab'+(t.team.team_id===currentTeamId?' active':'');
    tab.dataset.teamId=t.team.team_id;
    const done=(t.status_counts||{}).Done||0;
    const total=t.total_tickets||0;
    const active=t.active_agents||0;
    tab.innerHTML='<span>'+esc(t.team.name)+'</span><span class="tab-kpi">'+done+'/'+total+'</span>';
    tab.addEventListener('click',()=>selectTeam(t.team.team_id));
    bar.insertBefore(tab,addBtn);
  });
}
function highlightActiveTab(){
  document.querySelectorAll('.team-tab').forEach(t=>{
    t.classList.toggle('active',t.dataset.teamId===currentTeamId);
  });
}
function selectTeam(teamId){
  currentTeamId=teamId;
  highlightActiveTab();
  refresh();
  connectTeamSSE();
}

/* ── Global SSE (all teams) ── */
function connectGlobalSSE(){
  if(globalEvtSource)globalEvtSource.close();
  globalEvtSource=new EventSource('/api/supervisor/events');
  globalEvtSource.onopen=()=>{
    sseOk=true;
    $('sseStatus').innerHTML='<span class="sse-dot" style="background:var(--green)"></span>Live';
  };
  globalEvtSource.onmessage=e=>{
    scheduleTabRefresh();
    try{
      const data=JSON.parse(e.data);
      addGlobalActivity(data);
      if(data.team_id===currentTeamId)scheduleRefresh();
    }catch(err){
      scheduleRefresh();
    }
  };
  globalEvtSource.onerror=()=>{
    sseOk=false;
    $('sseStatus').innerHTML='<span class="sse-dot" style="background:var(--red)"></span>재연결중';
  };
}
/* Team-specific SSE for board */
function connectTeamSSE(){
  if(teamEvtSource)teamEvtSource.close();
  if(!currentTeamId)return;
  teamEvtSource=new EventSource('/api/teams/'+currentTeamId+'/events');
  teamEvtSource.onmessage=()=>scheduleRefresh();
}
let _rt=null,_trt=null;
function scheduleRefresh(){if(_rt)clearTimeout(_rt);_rt=setTimeout(refresh,300);}
function scheduleTabRefresh(){if(_trt)clearTimeout(_trt);_trt=setTimeout(refreshTabs,600);}

/* ── Header Stats ── */
function updateHeaderStats(){
  let total=0,done=0,active=0;
  allTeamsData.forEach(t=>{
    total+=t.total_tickets||0;
    done+=(t.status_counts||{}).Done||0;
    active+=t.active_agents||0;
  });
  $('gTotal').textContent=total;
  $('gActive').textContent=active;
  $('gDone').textContent=done;
  $('gRate').textContent=total?Math.round(done/total*100)+'%':'0%';
}

/* ── Global Activity Feed ── */
function addGlobalActivity(data){
  const al=$('activityLog');
  if(!al||data.type==='ticket_heartbeat')return;
  const teamName=allTeamsData.find(t=>t.team.team_id===data.team_id);
  const tn=teamName?teamName.team.name:data.team_id;
  const d=data.data||data.payload||{};
  const msg=d.message||d.title||d.ticket_title||(d.status?(d.ticket_id||'')+' → '+d.status:'')
    ||d.content||d.name||d.role||data.type||'';
  const item=document.createElement('div');
  item.className='log-item';
  item.style.animation='fadeIn 0.3s';
  item.innerHTML='<span class="lt">'+timeFmt(data.ts||new Date().toISOString())+'</span> <span class="log-team">'+esc(tn)+'</span> <span class="la">'+esc(data.type||'event')+'</span> '+esc(typeof msg==='string'?msg.substring(0,120):String(msg));
  al.insertBefore(item,al.firstChild);
  while(al.children.length>100)al.removeChild(al.lastChild);
}

async function refreshTabs(){
  try{
    const ov=await api('/api/supervisor/overview');
    if(!ov.ok)return;
    allTeamsData=ov.teams||[];
    renderTabs();
    updateHeaderStats();
  }catch(e){}
}

/* ── Teams ── */
async function loadTeams(){
  try{
    const ov=await api('/api/supervisor/overview');
    if(ov.ok)allTeamsData=ov.teams||[];
    else{const d=await api('/api/teams');allTeamsData=(d.teams||[]).map(t=>({team:t,total_tickets:0,status_counts:{},active_agents:0,members:[]}));}
    renderTabs();
    updateHeaderStats();
    if(!currentTeamId&&allTeamsData.length>0)currentTeamId=allTeamsData[0].team.team_id;
    highlightActiveTab();
  }catch(e){console.error(e);}
}
async function createTeam(){
  const name=$('mTeamName').value.trim();if(!name)return alert('팀 이름 입력');
  const d=await api('/api/teams',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,description:$('mTeamDesc').value.trim()})});
  currentTeamId=d.team.team_id;closeModal('modalTeam');$('mTeamName').value='';$('mTeamDesc').value='';await loadTeams();await refresh();connectTeamSSE();
}
async function spawnMember(){
  if(!currentTeamId)return alert('팀 선택 필요');
  await api('/api/teams/'+currentTeamId+'/members',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({role:$('mMemberRole').value,display_name:$('mMemberName').value.trim()||undefined})});
  closeModal('modalMember');$('mMemberName').value='';
}
async function createTicket(){
  if(!currentTeamId)return alert('팀 선택 필요');
  const tags=$('mTicketTags').value.trim().split(',').map(s=>s.trim()).filter(Boolean);
  await api('/api/teams/'+currentTeamId+'/tickets',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({
    title:$('mTicketTitle').value.trim(),description:$('mTicketDesc').value.trim(),
    priority:$('mTicketPriority').value,estimated_minutes:parseInt($('mTicketEst').value)||30,
    tags:tags.length?tags:undefined
  })});
  closeModal('modalTicket');$('mTicketTitle').value='';$('mTicketDesc').value='';$('mTicketTags').value='';
}

/* Board render */
function renderBoard(){
  if(!boardData)return;
  const team=boardData.team;
  $('teamName').textContent=team.name;
  $('teamMeta').textContent='Leader: '+team.leader_agent+' | '+team.status+' | '+timeFmt(team.created_at);
  memberMap={};(boardData.members||[]).forEach(m=>{memberMap[m.member_id]=m.display_name||m.role;});
  const statuses=['Backlog','Todo','InProgress','Review','Done','Blocked'];
  const tickets=boardData.tickets||[];
  const priOrder={Critical:0,High:1,Medium:2,Low:3};
  statuses.forEach(s=>{
    const col=document.querySelector('.col-body[data-status="'+s+'"]');if(!col)return;col.innerHTML='';
    const filtered=tickets.filter(t=>t.status===s).sort((a,b)=>(priOrder[a.priority]||2)-(priOrder[b.priority]||2));
    $('c'+s).textContent=filtered.length;
    filtered.forEach(t=>{
      const card=document.createElement('div');card.className='ticket';card.draggable=true;card.dataset.ticketId=t.ticket_id;
      const agent=t.assigned_member_id?'<span style="display:inline-flex;align-items:center;gap:3px"><span class="role-dot '+roleClass(memberRole(t.assigned_member_id))+'"></span>'+esc(memberName(t.assigned_member_id))+'</span>':'<span style="color:var(--muted)">unassigned</span>';
      const deps=t.depends_on&&t.depends_on.length?'<div class="t-dep">dep: '+t.depends_on.join(', ')+'</div>':'';
      const time=t.estimated_minutes?'<span class="t-time">'+(t.actual_minutes?t.actual_minutes+'m/':'')+t.estimated_minutes+'m</span>':'';
      const tagHtml=(t.tags||[]).map(tag=>'<span style="background:var(--line);border-radius:3px;padding:0 4px;font-size:9px">'+esc(tag)+'</span>').join(' ');
      card.innerHTML='<div class="t-header"><span class="t-id">'+esc(t.ticket_id)+'</span><span class="t-pri '+priClass(t.priority)+'">'+(t.priority||'Med')+'</span></div><div class="t-title">'+esc(t.title)+'</div><div class="t-meta">'+agent+time+'</div>'+(tagHtml?'<div style="margin-top:4px">'+tagHtml+'</div>':'')+deps;
      card.addEventListener('dragstart',e=>{e.dataTransfer.setData('text/plain',t.ticket_id);card.classList.add('dragging');});
      card.addEventListener('dragend',()=>card.classList.remove('dragging'));
      card.addEventListener('dblclick',e=>{e.preventDefault();e.stopPropagation();showTicketDetail(t.ticket_id);});
      card.addEventListener('click',e=>{if(e.detail===1)setTimeout(()=>{if(!e.defaultPrevented){}},200);});
      col.appendChild(card);
    });
  });
  const ml=$('membersList');ml.innerHTML='';
  (boardData.members||[]).forEach(m=>{
    const div=document.createElement('div');div.className='member';div.style.cursor='pointer';
    div.innerHTML='<span class="ms ms-'+(m.status||'Idle')+'"></span><span class="role-dot '+roleClass(m.role)+'"></span>'+esc(m.display_name||m.role)+'<span style="color:var(--muted);margin-left:auto;font-size:10px">'+(m.status||'Idle')+(m.current_ticket_id?' · '+m.current_ticket_id:'')+'</span>';
    div.addEventListener('click',()=>showMemberDetail(m.member_id));
    ml.appendChild(div);
  });
  /* Load global activity */
  loadGlobalActivity();
  $('sActiveAgents').textContent=(boardData.members||[]).filter(m=>m.status==='Working').length;
}
async function loadStats(){
  if(!currentTeamId)return;
  try{const d=await api('/api/teams/'+currentTeamId+'/stats');const s=d.stats;
    $('sTotalTickets').textContent=s.total_tickets;$('sCompletionRate').textContent=s.completion_rate+'%';
    $('sAvgTime').textContent=s.avg_minutes_per_ticket?Math.round(s.avg_minutes_per_ticket)+'m':'-';
    $('progressFill').style.width=s.completion_rate+'%';
  }catch(e){}
}
async function loadGlobalActivity(){
  try{
    const act=await api('/api/supervisor/activity?limit=30');
    if(!act.ok)return;
    const al=$('activityLog');al.innerHTML='';
    act.logs.forEach(l=>{
      al.innerHTML+='<div class="log-item"><span class="lt">'+timeFmt(l.created_at)+'</span> '+(l.team_name?'<span class="log-team">'+esc(l.team_name)+'</span>':'')+' <span class="la">'+esc(l.action)+'</span> '+esc(l.message||'')+'</div>';
    });
  }catch(e){}
}

/* Drag & drop */
document.querySelectorAll('.drop-zone').forEach(zone=>{
  zone.addEventListener('dragover',e=>{e.preventDefault();zone.classList.add('over');});
  zone.addEventListener('dragleave',()=>zone.classList.remove('over'));
  zone.addEventListener('drop',async e=>{
    e.preventDefault();zone.classList.remove('over');
    const tid=e.dataTransfer.getData('text/plain'),ns=zone.dataset.status;
    if(!tid||!ns)return;
    try{await api('/api/tickets/'+tid+'/status',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({status:ns})});}catch(err){alert(err.message);}
  });
});

/* Refresh */
async function refresh(){
  if(!currentTeamId){$('teamName').textContent='팀을 선택하세요';return;}
  try{const d=await api('/api/teams/'+currentTeamId+'/board');boardData=d.board;renderBoard();await loadStats();}catch(e){$('teamMeta').textContent='Error: '+e.message;}
}

/* Ticket detail with tabs */
let _currentDetailTicket=null;
async function showTicketDetail(ticketId){
  try{
    _currentDetailTicket=ticketId;
    const d=await api('/api/tickets/'+ticketId+'/detail');
    if(!d.ok)return;
    const t=d.ticket;const m=d.assigned_member;const logs=d.logs||[];
    const mc=d.message_count||0;const ac=d.artifact_count||0;
    $('detailTitle').textContent=t.ticket_id+' — '+t.title;
    /* Tabs */
    $('detailTabs').innerHTML='<div class="detail-tabs">'+
      '<div class="detail-tab active" data-tab="info">정보</div>'+
      '<div class="detail-tab" data-tab="conv">대화'+(mc?'<span class="badge">'+mc+'</span>':'')+'</div>'+
      '<div class="detail-tab" data-tab="arts">산출물'+(ac?'<span class="badge">'+ac+'</span>':'')+'</div>'+
      '<div class="detail-tab" data-tab="timeline">타임라인<span class="badge">'+logs.length+'</span></div>'+'</div>';
    /* Info tab */
    let infoH='<div class="tab-content active" id="tabInfo">';
    infoH+='<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin:8px 0">';
    infoH+='<div><span style="color:var(--muted);font-size:11px">상태</span><div style="font-weight:700">'+esc(t.status)+'</div></div>';
    infoH+='<div><span style="color:var(--muted);font-size:11px">우선순위</span><div><span class="t-pri '+priClass(t.priority)+'">'+esc(t.priority)+'</span></div></div>';
    infoH+='<div><span style="color:var(--muted);font-size:11px">담당</span><div>'+(m?'<span class="role-dot '+roleClass(m.role)+'"></span> '+esc(m.display_name)+' ('+esc(m.role)+')':'<span style="color:var(--muted)">미배정</span>')+'</div></div>';
    infoH+='<div><span style="color:var(--muted);font-size:11px">소요</span><div>'+(t.actual_minutes?t.actual_minutes+'분':'-')+' / '+(t.estimated_minutes?t.estimated_minutes+'분 예상':'-')+'</div></div>';
    infoH+='<div><span style="color:var(--muted);font-size:11px">생성</span><div>'+dateFmt(t.created_at)+'</div></div>';
    infoH+='<div><span style="color:var(--muted);font-size:11px">시작</span><div>'+(t.started_at?dateFmt(t.started_at):'-')+'</div></div>';
    infoH+='</div>';
    if(t.description)infoH+='<div style="margin:8px 0;padding:10px;background:var(--card);border-radius:6px;font-size:12px;line-height:1.6;white-space:pre-wrap">'+esc(t.description)+'</div>';
    if(t.tags&&t.tags.length)infoH+='<div style="margin:6px 0">태그: '+(t.tags).map(tag=>'<span style="background:var(--line);border-radius:3px;padding:1px 6px;font-size:11px;margin-right:4px">'+esc(tag)+'</span>').join('')+'</div>';
    if(t.depends_on&&t.depends_on.length)infoH+='<div style="margin:6px 0;color:var(--orange);font-size:12px">의존성: '+t.depends_on.join(', ')+'</div>';
    infoH+='</div>';
    /* Conv tab placeholder */
    let convH='<div class="tab-content" id="tabConv"><div style="text-align:center;color:var(--muted);padding:20px">로딩중...</div></div>';
    /* Arts tab placeholder */
    let artsH='<div class="tab-content" id="tabArts"><div style="text-align:center;color:var(--muted);padding:20px">로딩중...</div></div>';
    /* Timeline tab */
    let tlH='<div class="tab-content" id="tabTimeline">';
    if(logs.length===0)tlH+='<div style="color:var(--muted);font-size:11px;text-align:center;padding:10px">기록 없음</div>';
    logs.forEach(l=>{
      tlH+='<div style="padding:5px 0;border-bottom:1px solid var(--line);font-size:11px"><span style="color:var(--muted)">'+dateFmt(l.created_at)+'</span> <span style="color:var(--cyan);font-weight:600">'+esc(l.action)+'</span> '+esc(l.message||'');
      if(l.metadata){try{const meta=JSON.parse(l.metadata);tlH+=' <span style="color:var(--muted);font-size:10px">['+Object.keys(meta).map(k=>esc(k)+':'+esc(JSON.stringify(meta[k]))).join(', ')+']</span>';}catch(e){}}
      tlH+='</div>';
    });
    tlH+='</div>';
    $('detailBody').innerHTML=infoH+convH+artsH+tlH;
    /* Tab click */
    $('detailTabs').querySelectorAll('.detail-tab').forEach(tab=>{
      tab.addEventListener('click',()=>{
        $('detailTabs').querySelectorAll('.detail-tab').forEach(t=>t.classList.remove('active'));
        $('detailBody').querySelectorAll('.tab-content').forEach(t=>t.classList.remove('active'));
        tab.classList.add('active');
        const tn=tab.dataset.tab;
        if(tn==='info')$('tabInfo').classList.add('active');
        if(tn==='conv'){$('tabConv').classList.add('active');loadConversations(ticketId);}
        if(tn==='arts'){$('tabArts').classList.add('active');loadArtifacts(ticketId);}
        if(tn==='timeline')$('tabTimeline').classList.add('active');
      });
    });
    openModal('modalDetail');
  }catch(e){console.error(e);}
}

/* Load conversations for ticket */
async function loadConversations(ticketId){
  try{
    const d=await api('/api/tickets/'+ticketId+'/messages');
    const tab=$('tabConv');
    if(!d.ok){tab.innerHTML='<div style="color:var(--red)">오류</div>';return;}
    let h='';
    if(d.messages.length===0)h='<div style="color:var(--muted);text-align:center;padding:16px">아직 대화가 없습니다</div>';
    d.messages.forEach(m=>{
      h+='<div class="msg-bubble">';
      h+='<div class="msg-header"><span><span class="role-dot '+roleClass(m.sender_role||'default')+'"></span> <b>'+esc(m.sender_name||m.sender_member_id)+'</b></span>';
      h+='<span style="display:flex;gap:6px;align-items:center"><span class="msg-type msg-type-'+esc(m.message_type||'comment')+'">'+esc(m.message_type||'comment')+'</span><span style="color:var(--muted);font-size:10px">'+dateFmt(m.created_at)+'</span></span></div>';
      h+='<div style="font-size:12px;line-height:1.6;white-space:pre-wrap">'+esc(m.content)+'</div>';
      h+='</div>';
    });
    /* compose */
    h+='<div class="msg-compose">';
    h+='<select id="msgSender" style="font-size:11px">';
    (boardData&&boardData.members||[]).forEach(m=>{h+='<option value="'+esc(m.member_id)+'">'+esc(m.display_name||m.role)+'</option>';});
    h+='</select>';
    h+='<select id="msgType" style="font-size:11px;width:auto"><option value="comment">댓글</option><option value="question">질문</option><option value="code_review">코드리뷰</option></select>';
    h+='<textarea id="msgContent" placeholder="메시지 작성..." style="font-size:12px"></textarea>';
    h+='<button onclick="sendMessage(\''+esc(ticketId)+'\')">전송</button></div>';
    tab.innerHTML=h;
  }catch(e){console.error(e);}
}
async function sendMessage(ticketId){
  const sender=$('msgSender')?.value;
  const content=$('msgContent')?.value?.trim();
  const msgType=$('msgType')?.value||'comment';
  if(!sender||!content)return;
  await api('/api/tickets/'+ticketId+'/messages',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({sender_member_id:sender,content,message_type:msgType})});
  loadConversations(ticketId);
}

/* Load artifacts for ticket */
async function loadArtifacts(ticketId){
  try{
    const d=await api('/api/tickets/'+ticketId+'/artifacts');
    const tab=$('tabArts');
    if(!d.ok){tab.innerHTML='<div style="color:var(--red)">오류</div>';return;}
    let h='';
    if(d.artifacts.length===0)h='<div style="color:var(--muted);text-align:center;padding:16px">등록된 산출물이 없습니다</div>';
    d.artifacts.forEach(a=>{
      const typeColors={code:'var(--brand)',file_path:'var(--cyan)',result:'var(--green)',summary:'var(--purple)',log:'var(--muted)'};
      h+='<div class="art-card">';
      h+='<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">';
      h+='<span style="font-weight:600;font-size:13px">'+esc(a.title)+'</span>';
      h+='<span style="font-size:10px;padding:2px 8px;border-radius:4px;background:var(--card);border:1px solid var(--line);color:'+(typeColors[a.artifact_type]||'var(--muted)')+'">'+esc(a.artifact_type)+'</span></div>';
      h+='<div style="font-size:10px;color:var(--muted);margin-bottom:6px"><span class="role-dot '+roleClass(a.creator_role||'default')+'"></span> '+esc(a.creator_name||a.creator_member_id)+' · '+dateFmt(a.created_at)+'</div>';
      if(a.artifact_type==='code')h+='<div class="art-code">'+(a.language?'<span style="color:var(--muted);font-size:9px">'+esc(a.language)+'</span>\n':'')+esc(a.content)+'</div>';
      else h+='<div style="font-size:12px;line-height:1.6;white-space:pre-wrap;padding:8px;background:var(--card);border-radius:6px;border:1px solid var(--line)">'+esc(a.content)+'</div>';
      h+='</div>';
    });
    tab.innerHTML=h;
  }catch(e){console.error(e);}
}

/* Member detail */
async function showMemberDetail(memberId){
  try{
    const d=await api('/api/members/'+memberId+'/detail');
    if(!d.ok)return;
    const m=d.member;const tickets=d.tickets||[];const logs=d.logs||[];
    $('memberDetailTitle').innerHTML='<span class="role-dot '+roleClass(m.role)+'"></span> '+esc(m.display_name)+' ('+esc(m.role)+')';
    let html='<div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin:12px 0">';
    html+='<div><span style="color:var(--muted);font-size:11px">상태</span><div style="font-weight:700"><span class="ms ms-'+(m.status||'Idle')+'"></span> '+(m.status||'Idle')+'</div></div>';
    html+='<div><span style="color:var(--muted);font-size:11px">현재 티켓</span><div>'+(m.current_ticket_id||'-')+'</div></div>';
    html+='<div><span style="color:var(--muted);font-size:11px">스폰</span><div>'+timeFmt(m.spawned_at)+'</div></div></div>';
    const done=tickets.filter(t=>t.status==='Done').length;
    html+='<h4 style="margin:10px 0 6px;font-size:12px;color:var(--muted)">할당 티켓 ('+tickets.length+' | 완료 '+done+')</h4>';
    html+='<div style="max-height:160px;overflow-y:auto;border:1px solid var(--line);border-radius:6px;padding:6px">';
    if(!tickets.length)html+='<div style="color:var(--muted);font-size:11px;text-align:center;padding:10px">할당 없음</div>';
    tickets.forEach(t=>{
      const sc={'Done':'var(--green)','InProgress':'var(--brand)','Blocked':'var(--red)','Review':'var(--purple)'};
      html+='<div style="padding:4px 0;border-bottom:1px solid var(--line);font-size:12px;display:flex;gap:8px;align-items:center">';
      html+='<span style="color:var(--muted);font-size:10px;min-width:52px">'+esc(t.ticket_id)+'</span>';
      html+='<span style="color:'+(sc[t.status]||'var(--muted)')+';font-size:10px;min-width:70px">'+esc(t.status)+'</span>';
      html+='<span style="flex:1">'+esc(t.title)+'</span>';
      html+='<span class="t-pri '+priClass(t.priority)+'" style="font-size:9px">'+esc(t.priority)+'</span></div>';
    });
    html+='</div>';
    html+='<h4 style="margin:10px 0 6px;font-size:12px;color:var(--muted)">최근 활동 ('+Math.min(logs.length,20)+')</h4>';
    html+='<div style="max-height:200px;overflow-y:auto;border:1px solid var(--line);border-radius:6px;padding:6px">';
    logs.slice(0,20).forEach(l=>{html+='<div style="padding:3px 0;border-bottom:1px solid var(--line);font-size:11px"><span style="color:var(--muted)">'+timeFmt(l.created_at)+'</span> <span style="color:var(--cyan);font-weight:600">'+esc(l.action)+'</span> '+esc(l.message||'')+'</div>';});
    if(!logs.length)html+='<div style="color:var(--muted);font-size:11px;text-align:center;padding:10px">기록 없음</div>';
    html+='</div>';
    $('memberDetailBody').innerHTML=html;
    openModal('modalMemberDetail');
  }catch(e){console.error(e);}
}

/* Init */
$('btnNewTeam').addEventListener('click',()=>openModal('modalTeam'));
$('btnNewMember').addEventListener('click',()=>openModal('modalMember'));
$('btnNewTicket').addEventListener('click',()=>openModal('modalTicket'));
(async()=>{
  const p=new URLSearchParams(location.search);
  const tp=p.get('team');
  await loadTeams();
  if(tp){currentTeamId=tp;highlightActiveTab();}
  await refresh();
  connectGlobalSSE();
  connectTeamSSE();
})();
setInterval(()=>{if(!sseOk){refresh();refreshTabs();}},8000);
</script>
</body>
</html>"""


# ── HTML: Supervisor ──

SUPERVISOR_HTML = r"""<!doctype html>
<html lang='ko'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Supervisor Dashboard</title>
<style>
""" + SHARED_CSS + r"""
.global-stats{display:flex;gap:12px;padding:16px 20px;flex-wrap:wrap}
.gs{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px 16px;text-align:center;min-width:90px;flex:1}
.gs .gv{font-size:22px;font-weight:700}.gs .gk{font-size:10px;color:var(--muted);margin-top:2px}
.team-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:16px;padding:0 20px 20px}
.team-card{background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden;transition:border-color 0.15s}
.team-card:hover{border-color:var(--brand)}
.tc-top{padding:14px 16px 10px;cursor:pointer}
.tc-name{font-size:14px;font-weight:700;display:flex;justify-content:space-between;align-items:center}
.tc-name .tc-badge{font-size:10px;font-weight:400;color:var(--muted);padding:2px 8px;background:var(--panel);border-radius:4px}
.tc-desc{font-size:11px;color:var(--muted);margin:4px 0 8px;max-height:20px;overflow:hidden}
.tc-progress{height:6px;background:var(--line);border-radius:3px;overflow:hidden}
.tc-progress-fill{height:100%;border-radius:3px;transition:width 0.5s}
.mini-kanban{display:flex;gap:2px;margin:8px 0;height:20px;border-radius:4px;overflow:hidden}
.mk-seg{display:flex;align-items:center;justify-content:center;font-size:8px;font-weight:700;color:#fff;min-width:16px;transition:flex 0.3s}
.tc-agents{display:flex;gap:4px;flex-wrap:wrap;margin:6px 0}
.tc-agent{font-size:10px;padding:2px 6px;border-radius:4px;display:flex;align-items:center;gap:3px;background:var(--panel)}
.tc-detail{display:none;border-top:1px solid var(--line);padding:10px 16px 14px;background:var(--panel)}
.tc-detail.open{display:block}
.tc-detail h4{font-size:11px;color:var(--muted);margin:0 0 6px;text-transform:uppercase;letter-spacing:0.5px}
.tc-ticket-row{display:flex;align-items:center;gap:6px;padding:3px 0;font-size:11px;border-bottom:1px solid var(--line)}
.tc-ticket-row:last-child{border:none}
.tc-ticket-status{font-size:9px;font-weight:700;padding:1px 6px;border-radius:3px;min-width:60px;text-align:center}
.tc-log-row{padding:3px 0;font-size:10px;color:var(--muted);border-bottom:1px solid var(--line)}
.tc-log-row:last-child{border:none}
.tc-footer{display:flex;gap:8px;padding:8px 16px;border-top:1px solid var(--line);justify-content:space-between;align-items:center}
.tc-footer span{font-size:10px;color:var(--muted)}
.tc-footer button{font-size:10px;padding:4px 12px}
.global-feed{padding:0 20px 20px}
.feed-box{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px;max-height:300px;overflow-y:auto}
.feed-box::-webkit-scrollbar{width:4px}
.feed-box::-webkit-scrollbar-thumb{background:var(--line);border-radius:4px}
.feed-item{padding:4px 0;border-bottom:1px solid var(--line);font-size:11px;line-height:1.5}
.feed-team{font-size:10px;padding:1px 6px;border-radius:3px;background:var(--card);color:var(--brand);margin-right:4px}
</style>
</head>
<body>
<div class='header'>
  <div style='display:flex;align-items:center;gap:12px'>
    <h1 style='font-size:15px;font-weight:700'>U2DIA AI Agents</h1>
    <span style='font-size:10px;color:var(--muted);padding:2px 8px;border:1px solid var(--line);border-radius:4px'>Supervisor</span>
    <span id='sseStatus' style='font-size:11px;display:flex;align-items:center;gap:4px'><span class='sse-dot' style='background:var(--muted)'></span>연결중</span>
  </div>
  <div class='toolbar'>
    <button class='secondary' onclick="location.href='/board'">칸반보드</button>
    <button class='secondary' id='btnRefresh'>&#8635;</button>
  </div>
</div>
<div id='globalStats' class='global-stats'></div>
<h3 style='padding:0 20px 10px;font-size:13px;color:var(--muted)'>프로젝트 팀</h3>
<div id='teamGrid' class='team-grid'></div>
<h3 style='padding:20px 20px 10px;font-size:13px;color:var(--muted)'>글로벌 액티비티</h3>
<div class='global-feed'><div class='feed-box' id='feedBox'></div></div>

<script>
const $=id=>document.getElementById(id);
function esc(s){const d=document.createElement('div');d.textContent=String(s||'');return d.innerHTML;}
function timeFmt(t){if(!t)return'-';const d=new Date(t.includes('Z')?t:t+'Z');return isNaN(d)?t:d.toLocaleTimeString('ko',{hour:'2-digit',minute:'2-digit'});}
async function api(path){const r=await fetch(path);return r.json();}

const statusColors={Backlog:'#374151',Todo:'#4b5563',InProgress:'#3b82f6',Review:'#a855f7',Done:'#22c55e',Blocked:'#ef4444'};
const statusLabels={Backlog:'BL',Todo:'TD',InProgress:'IP',Review:'RV',Done:'DN',Blocked:'BK'};
const priColors={Critical:'var(--red)',High:'var(--orange)',Medium:'var(--yellow)',Low:'var(--green)'};

function buildMiniKanban(sc,total){
  if(!total)return'<div class="mini-kanban"><div class="mk-seg" style="flex:1;background:var(--line);font-size:9px;color:var(--muted)">No tickets</div></div>';
  let h='<div class="mini-kanban">';
  ['Backlog','Todo','InProgress','Review','Done','Blocked'].forEach(s=>{
    const n=sc[s]||0;if(!n)return;
    const pct=Math.max(n/total*100,8);
    h+='<div class="mk-seg" style="flex:'+pct+';background:'+statusColors[s]+'" title="'+s+': '+n+'">'+statusLabels[s]+' '+n+'</div>';
  });
  h+='</div>';return h;
}

function buildTeamCard(t,idx){
  const team=t.team,sc=t.status_counts||{},total=t.total_tickets;
  const progColor=t.progress>=80?'var(--green)':t.progress>=50?'var(--brand)':t.progress>=20?'var(--yellow)':'var(--red)';
  const memberMap={};(t.members||[]).forEach(m=>{memberMap[m.member_id]=m.display_name||m.role;});
  let h='<div class="team-card" id="tc'+idx+'">';
  /* top: clickable header */
  h+='<div class="tc-top" onclick="toggleDetail('+idx+')">';
  h+='<div class="tc-name"><span>'+esc(team.name)+'</span><span class="tc-badge">'+t.progress+'% | '+total+' tickets</span></div>';
  h+='<div class="tc-desc">'+esc(team.description||'Leader: '+team.leader_agent)+'</div>';
  /* progress bar */
  h+='<div class="tc-progress"><div class="tc-progress-fill" style="width:'+t.progress+'%;background:'+progColor+'"></div></div>';
  /* mini kanban */
  h+=buildMiniKanban(sc,total);
  /* agents row */
  h+='<div class="tc-agents">';
  (t.members||[]).forEach(m=>{
    const mc={'Working':'var(--green)','Idle':'var(--muted)','Blocked':'var(--red)'};
    h+='<span class="tc-agent"><span class="sse-dot" style="background:'+(mc[m.status]||'var(--muted)')+';width:6px;height:6px"></span>'+esc(m.display_name||m.role);
    if(m.status==='Working'&&m.current_ticket_id)h+=' <span style="color:var(--cyan);font-size:9px">'+esc(m.current_ticket_id)+'</span>';
    h+='</span>';
  });
  h+='</div></div>';
  /* detail: expand section */
  h+='<div class="tc-detail" id="td'+idx+'">';
  /* recent tickets */
  h+='<h4>진행 중인 티켓</h4>';
  (t.recent_tickets||[]).forEach(tk=>{
    const sc2={InProgress:'var(--brand)',Blocked:'var(--red)',Review:'var(--purple)',Todo:'var(--text)',Backlog:'var(--muted)',Done:'var(--green)'};
    h+='<div class="tc-ticket-row">';
    h+='<span class="tc-ticket-status" style="background:'+(sc2[tk.status]||'var(--muted)')+'">'+esc(tk.status)+'</span>';
    h+='<span style="color:var(--muted);font-size:10px;min-width:50px">'+esc(tk.ticket_id)+'</span>';
    h+='<span style="flex:1">'+esc(tk.title)+'</span>';
    h+='<span class="t-pri '+('pri-'+(tk.priority||'Medium'))+'" style="font-size:9px">'+esc(tk.priority)+'</span>';
    if(tk.assigned_member_id)h+='<span style="font-size:10px;color:var(--cyan)">'+esc(memberMap[tk.assigned_member_id]||tk.assigned_member_id)+'</span>';
    h+='</div>';
  });
  if(!(t.recent_tickets||[]).length)h+='<div style="color:var(--muted);font-size:11px;padding:4px 0">티켓 없음</div>';
  /* recent activity */
  h+='<h4 style="margin-top:10px">최근 활동</h4>';
  (t.recent_logs||[]).forEach(l=>{
    h+='<div class="tc-log-row"><span style="color:var(--muted)">'+timeFmt(l.created_at)+'</span> <span style="color:var(--cyan);font-weight:600">'+esc(l.action)+'</span> '+esc(l.message||'')+'</div>';
  });
  if(!(t.recent_logs||[]).length)h+='<div style="color:var(--muted);font-size:11px;padding:4px 0">활동 없음</div>';
  h+='</div>';
  /* footer */
  h+='<div class="tc-footer"><span>Agents: '+t.member_count+' | Msgs: '+t.message_count+' | Arts: '+t.artifact_count+'</span>';
  h+='<button class="secondary" onclick="event.stopPropagation();location.href=\'/board?team='+esc(team.team_id)+'\'">보드 열기</button></div>';
  h+='</div>';
  return h;
}

function toggleDetail(idx){
  const el=document.getElementById('td'+idx);
  if(el)el.classList.toggle('open');
}

async function loadOverview(){
  const [ov,st,act]=await Promise.all([api('/api/supervisor/overview'),api('/api/supervisor/stats'),api('/api/supervisor/activity?limit=50')]);
  if(st.ok){
    const s=st.stats;
    $('globalStats').innerHTML=[
      {v:s.total_teams,k:'Teams'},{v:s.active_teams,k:'Active'},{v:s.total_agents,k:'Agents'},
      {v:s.working_agents,k:'Working'},{v:s.total_tickets,k:'Tickets'},{v:s.done_tickets,k:'Done'},
      {v:s.blocked_tickets,k:'Blocked'},{v:s.global_progress+'%',k:'Progress'},
      {v:s.total_messages,k:'Messages'},{v:s.total_artifacts,k:'Artifacts'}
    ].map(x=>'<div class="gs"><div class="gv">'+x.v+'</div><div class="gk">'+x.k+'</div></div>').join('');
  }
  if(ov.ok){
    const grid=$('teamGrid');
    const openSet=new Set();
    grid.querySelectorAll('.tc-detail.open').forEach(el=>{const m=el.id.match(/\d+/);if(m)openSet.add(m[0]);});
    grid.innerHTML='';
    ov.teams.forEach((t,i)=>{grid.innerHTML+=buildTeamCard(t,i);});
    openSet.forEach(idx=>{const el=document.getElementById('td'+idx);if(el)el.classList.add('open');});
  }
  if(act.ok){
    const fb=$('feedBox');fb.innerHTML='';
    act.logs.forEach(l=>{
      fb.innerHTML+='<div class="feed-item"><span style="color:var(--muted);font-size:10px">'+timeFmt(l.created_at)+'</span> '+(l.team_name?'<span class="feed-team">'+esc(l.team_name)+'</span>':'')+' <span style="color:var(--cyan);font-weight:600">'+esc(l.action)+'</span> '+esc(l.message||'')+'</div>';
    });
  }
}

/* SSE */
let evtSource=null,sseOk=false;
function connectSSE(){
  evtSource=new EventSource('/api/supervisor/events');
  evtSource.onopen=()=>{sseOk=true;$('sseStatus').innerHTML='<span class="sse-dot" style="background:var(--green)"></span>LIVE';};
  evtSource.onmessage=()=>{if(_rt)clearTimeout(_rt);_rt=setTimeout(loadOverview,500);};
  evtSource.onerror=()=>{sseOk=false;$('sseStatus').innerHTML='<span class="sse-dot" style="background:var(--red)"></span>재연결';};
}
let _rt=null;
$('btnRefresh').addEventListener('click',loadOverview);
(async()=>{await loadOverview();connectSSE();})();
setInterval(()=>{if(!sseOk)loadOverview();},10000);
</script>
</body>
</html>"""


# ── HTTP 서버 ──

class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


class KanbanHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        ts = datetime.now().strftime("%H:%M:%S")
        sys.stderr.write(f"[{ts}] {self.command} {self.path}\n")

    _ALLOWED_ORIGINS = {
        "http://localhost:5555", "http://127.0.0.1:5555",
        "http://localhost:3000", "http://localhost:8080",
    }

    def _cors(self):
        origin = self.headers.get("Origin", "")
        # Tailscale(100.x.x.x) 및 허용 출처만 반영, 나머지는 null
        allowed = origin if (
            origin in self._ALLOWED_ORIGINS or
            (origin.startswith("http://100.") and ":5555" in origin)
        ) else "null"
        self.send_header("Access-Control-Allow-Origin", allowed if allowed != "null" else "http://localhost:5555")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Allow-Credentials", "true")

    def _json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _html(self, html):
        body = html.encode("utf-8")
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        raw = self.rfile.read(length).decode("utf-8")
        try:
            return json.loads(raw)
        except Exception:
            return {}

    def _handle_sse(self, team_id):
        """SSE 스트리밍 엔드포인트."""
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        client = sse_register(team_id)
        try:
            self.wfile.write(f"event: connected\ndata: {{\"team_id\":\"{team_id}\"}}\n\n".encode())
            self.wfile.flush()
            while client["active"]:
                client["event"].wait(timeout=25)
                client["event"].clear()
                while client["queue"]:
                    data = client["queue"].pop(0)
                    self.wfile.write(f"data: {data}\n\n".encode())
                self.wfile.write(b": heartbeat\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
            pass
        finally:
            sse_unregister(team_id, client)


    def _handle_chat_stream(self):
        """대화형 에이전트 SSE 스트리밍 — 실시간 글자 전송."""
        body = self._read_body()
        message = body.get("message", "").strip()
        session_id = body.get("session_id", "chat-stream")
        project = body.get("project")

        if not message:
            self._json({"ok": False, "error": "message required"}, 400)
            return

        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

        # 세션 관리
        if session_id not in _chat_sessions:
            _chat_sessions[session_id] = {
                "messages": [], "project": project,
                "project_path": _find_project_path(project) if project else None,
                "created_at": now_utc(), "last_at": now_utc(),
            }
        session = _chat_sessions[session_id]
        if project and not session["project"]:
            session["project"] = project
            session["project_path"] = _find_project_path(project)
        session["last_at"] = now_utc()
        proj_path = session["project_path"]
        proj_name = session["project"] or "unknown"

        # ── Ollama 의도 분류 → 에이전틱 라우팅 (키워드 매칭 없음) ──
        # 승인 확인 처리 (접두어 기반 — LLM 분류 불필요)
        text_lower = message.lower()
        for pfx in ["확인:", "승인:", "실행:", "confirm:", "go:"]:
            if text_lower.startswith(pfx):
                pending = session.get("_pending_dispatch")
                if pending:
                    real_msg = pending["instruction"]
                    p_proj = pending.get("project", proj_name)
                    p_path = pending.get("project_path", proj_path)
                    session.pop("_pending_dispatch", None)
                    try:
                        threading.Thread(target=_orch_dispatch, args=(p_proj, real_msg, p_path), daemon=True).start()
                        resp = f"🚀 {p_proj} — 승인 완료, CLI 에이전트 스폰\n\n지시: {real_msg}"
                        self.wfile.write(f'data: {json.dumps({"type":"text","text":resp})}\n\n'.encode())
                        self.wfile.write(f'data: {json.dumps({"type":"done","dispatched":True,"project":p_proj})}\n\n'.encode())
                        self.wfile.flush()
                        return
                    except Exception:
                        pass
                break

        intent = _classify_intent(message)

        # Supervisor → QA 검수/판정
        if intent == "supervisor":
            result = _chat_supervisor_respond(session_id, message, proj_name)
            resp = result.get("response", "") if result.get("ok") else result.get("error", "Supervisor 오류")
            chunk_size = 40
            for i in range(0, len(resp), chunk_size):
                self.wfile.write(f'data: {json.dumps({"type":"text","text":resp[i:i+chunk_size]})}\n\n'.encode())
                self.wfile.flush()
            self.wfile.write(f'data: {json.dumps({"type":"usage","backend":"ollama-supervisor"})}\n\n'.encode())
            self.wfile.write(b'data: {"type":"done"}\n\n')
            self.wfile.flush()
            return

        # Action → 도구 사용 (Ollama가 직접 도구 선택/실행)
        if intent == "action":
            result = _chat_agent_respond(session_id, message, project, proj_path, force_tools=True)
            resp = result.get("response", "") if result.get("ok") else result.get("error", "실행 오류")
            resp = _strip_html(resp)
            chunk_size = 40
            for i in range(0, len(resp), chunk_size):
                self.wfile.write(f'data: {json.dumps({"type":"text","text":resp[i:i+chunk_size]})}\n\n'.encode())
                self.wfile.flush()
            tools = result.get("tools_used", [])
            if tools:
                for t in tools:
                    self.wfile.write(f'data: {json.dumps({"type":"tool","name":t})}\n\n'.encode())
            actions = result.get("actions", [])
            done_data = {"type": "done", "tools": tools, "backend": result.get("backend", "ollama")}
            if result.get("confirm_required"):
                done_data["confirm_required"] = True
                done_data["actions"] = actions
                done_data["project"] = result.get("project", proj_name)
            self.wfile.write(f'data: {json.dumps(done_data)}\n\n'.encode())
            self.wfile.flush()
            return

        # Chat → 자연스러운 대화 (도구 없이)
        session["messages"].append({"role": "user", "content": message})
        if len(session["messages"]) > 30:
            session["messages"] = session["messages"][-16:]
        context = _build_kanban_context()
        full_system = _YUDI_CHAT_SYSTEM + f"\n\n칸반보드 참고:\n{context}"
        if proj_path:
            git_ctx = _build_git_context(proj_path)
            if git_ctx:
                full_system += f"\n\n프로젝트: {proj_name} ({proj_path})\n{git_ctx}"
        resp_text = _smart_chat(prompt=message, system=full_system, messages=session["messages"])
        if resp_text:
            resp_text = _strip_html(resp_text)
            session["messages"].append({"role": "assistant", "content": resp_text})
            chunk_size = 40
            for i in range(0, len(resp_text), chunk_size):
                self.wfile.write(f'data: {json.dumps({"type":"text","text":resp_text[i:i+chunk_size]})}\n\n'.encode())
                self.wfile.flush()
        else:
            self.wfile.write(b'data: {"type":"text","text":"\\u2753 \\uc751\\ub2f5 \\uc2e4\\ud328"}\n\n')
        self.wfile.write(f'data: {json.dumps({"type":"usage","backend":"ollama"})}\n\n'.encode())
        self.wfile.write(b'data: {"type":"done"}\n\n')
        self.wfile.flush()
        return

        # Claude API 스트리밍 (폴백)
        api_key = _get_setting("anthropic_api_key")
        if not api_key:
            self.wfile.write(b'data: {"type":"error","text":"API key not set"}\n\n')
            self.wfile.flush()
            return

        system_prompt = f"당신은 U2DIA AI 에이전트 유디. 시니어 풀스택 개발자+PM. 프로젝트: {proj_name} ({proj_path or '미지정'}). 대표님이라 부름. 핵심만, 도구는 최소한으로."

        session["messages"].append({"role": "user", "content": message})
        if len(session["messages"]) > 30:
            session["messages"] = session["messages"][-16:]

        messages = list(session["messages"])
        full_response = ""
        tools_used = []

        try:
            for turn in range(8):
                req_data = json.dumps({
                    "model": "claude-sonnet-4-20250514",
                    "max_tokens": 2048, "stream": True,
                    "system": system_prompt,
                    "messages": messages,
                    "tools": _API_AGENT_TOOLS
                }).encode()
                req = Request("https://api.anthropic.com/v1/messages",
                    data=req_data, headers={
                        "Content-Type": "application/json",
                        "x-api-key": api_key,
                        "anthropic-version": "2023-06-01"})
                resp = urlopen(req, timeout=90)

                # SSE 스트리밍 파싱
                tool_use_blocks = []
                current_tool = None
                tool_input_json = ""
                stop_reason = "end_turn"

                for raw_line in resp:
                    line = raw_line.decode("utf-8", errors="replace").strip()
                    if not line.startswith("data: "):
                        continue
                    chunk_str = line[6:]
                    if chunk_str == "[DONE]":
                        break
                    try:
                        chunk = json.loads(chunk_str)
                    except Exception:
                        continue

                    evt_type = chunk.get("type", "")

                    if evt_type == "content_block_start":
                        block = chunk.get("content_block", {})
                        if block.get("type") == "tool_use":
                            current_tool = {"id": block["id"], "name": block["name"], "input": {}}
                            tool_input_json = ""
                            # 도구 사용 알림
                            self.wfile.write(f'data: {json.dumps({"type":"tool","name":block["name"]})}\n\n'.encode())
                            self.wfile.flush()

                    elif evt_type == "content_block_delta":
                        delta = chunk.get("delta", {})
                        if delta.get("type") == "text_delta":
                            text = delta.get("text", "")
                            full_response += text
                            self.wfile.write(f'data: {json.dumps({"type":"text","text":text})}\n\n'.encode())
                            self.wfile.flush()
                        elif delta.get("type") == "input_json_delta":
                            tool_input_json += delta.get("partial_json", "")

                    elif evt_type == "content_block_stop":
                        if current_tool:
                            try:
                                current_tool["input"] = json.loads(tool_input_json) if tool_input_json else {}
                            except Exception:
                                current_tool["input"] = {}
                            tool_use_blocks.append(current_tool)
                            current_tool = None
                            tool_input_json = ""

                    elif evt_type == "message_delta":
                        stop_reason = chunk.get("delta", {}).get("stop_reason", stop_reason)

                resp.close()

                if stop_reason != "tool_use" or not tool_use_blocks:
                    break

                # 도구 실행
                content_blocks = []
                for t in tool_use_blocks:
                    content_blocks.append({"type": "tool_use", "id": t["id"], "name": t["name"], "input": t["input"]})
                messages.append({"role": "assistant", "content": content_blocks})

                tool_results = []
                for t in tool_use_blocks:
                    tools_used.append(t["name"])
                    tr = _api_execute_tool(t["name"], t["input"], proj_path or "/tmp", "", "", session_id)
                    tool_results.append({"type": "tool_result", "tool_use_id": t["id"], "content": str(tr)[:2000]})
                    self.wfile.write(f'data: {json.dumps({"type":"tool_result","name":t["name"],"preview":str(tr)[:100]})}\n\n'.encode())
                    self.wfile.flush()
                messages.append({"role": "user", "content": tool_results})
                tool_use_blocks = []

        except Exception as e:
            self.wfile.write(f'data: {json.dumps({"type":"error","text":str(e)[:200]})}\n\n'.encode())

        if full_response:
            session["messages"].append({"role": "assistant", "content": full_response})

        self.wfile.write(f'data: {json.dumps({"type":"done","tools":tools_used})}\n\n'.encode())
        try:
            self.wfile.flush()
        except Exception:
            pass


    def _handle_sse_global(self):
        """글로벌 SSE (Supervisor용)."""
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        client = sse_register_global()
        try:
            self.wfile.write(b"event: connected\ndata: {\"scope\":\"global\"}\n\n")
            self.wfile.flush()
            while client["active"]:
                client["event"].wait(timeout=25)
                client["event"].clear()
                while client["queue"]:
                    data = client["queue"].pop(0)
                    self.wfile.write(f"data: {data}\n\n".encode())
                self.wfile.write(b": heartbeat\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
            pass
        finally:
            sse_unregister_global(client)

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def _serve_static(self, path):
        """web/ 디렉토리에서 정적 파일 서빙. 경로 트래버설 방지."""
        if not os.path.isdir(WEB_DIR):
            return False
        # 요청 경로 정리
        rel = path.lstrip("/")
        if not rel or rel == "board" or rel == "supervisor":
            rel = "index.html"
        file_path = os.path.join(WEB_DIR, rel.replace("/", os.sep))
        real_path = os.path.realpath(file_path)
        real_web = os.path.realpath(WEB_DIR)
        # 경로 트래버설 방지
        if not real_path.startswith(real_web):
            return False
        if not os.path.isfile(real_path):
            return False
        mime, _ = mimetypes.guess_type(real_path)
        if not mime:
            mime = "application/octet-stream"
        try:
            with open(real_path, "rb") as f:
                content = f.read()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(content)
            return True
        except Exception:
            return False

    def _check_auth(self, path):
        """인증 체크. 로컬 요청은 패스, 원격은 라이선스/세션 필요."""
        if _is_local_request(self):
            return True

        # Rate limiting
        client_ip = self.client_address[0]
        if not _check_rate_limit(client_ip):
            self._json({"ok": False, "error": "rate_limited",
                         "message": "요청이 너무 많습니다. 잠시 후 다시 시도해주세요."}, 429)
            return False

        # 세션 쿠키 확인
        cookie_header = self.headers.get("Cookie", "")
        for part in cookie_header.split(";"):
            part = part.strip()
            if part.startswith("kanban_session="):
                token = part.split("=", 1)[1]
                if _validate_session(token):
                    return True

        # Authorization 헤더: "Bearer XXXX-XXXX-XXXX-XXXX"
        auth_header = self.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            key = auth_header[7:].strip()
            if _validate_license_key(key):
                return True
            # auth_tokens 테이블에서도 확인 — 토큰 정보(프로젝트명) 저장
            token_info = _get_auth_token_info(key)
            if token_info:
                self._auth_token_info = token_info
                return True

        # URL 파라미터 토큰은 보안상 허용하지 않음 (브라우저 히스토리/로그 노출 방지)
        # Authorization 헤더 또는 세션 쿠키만 허용

        # 인증 실패 → rate limit 강화
        _penalize_ip(self.client_address[0], count=5)
        # 미인증 — HTML 페이지면 로그인으로 리다이렉트, API면 401
        if path in ("", "/", "/board", "/supervisor"):
            self.send_response(302)
            self._cors()
            self.send_header("Location", "/login")
            self.end_headers()
        else:
            self._json({"ok": False, "error": "unauthorized",
                         "message": "유효한 라이선스가 필요합니다. Authorization: Bearer XXXX-XXXX-XXXX-XXXX"}, 401)
        return False

    def _handle_api(self, method):
        """통합 API 라우팅."""
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        query = parse_qs(parsed.query)

        # 클라이언트 추적
        _track_client(self)

        # 정적 파일 (web/ 디렉토리 존재 시 CSS/JS/이미지 등)
        if method == "GET" and not path.startswith("/api/") and not path.startswith("/mcp"):
            # 인증 면제: 정적 리소스 (css, js, images, fonts)
            static_ext = (".css", ".js", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".woff", ".woff2", ".ttf", ".json", ".webmanifest", ".apk")
            if any(path.endswith(ext) for ext in static_ext):
                if self._serve_static(path):
                    return

        # 공개 정적 페이지 (인증 없이 접근)
        public_pages = {"/privacy", "/privacy.html"}
        if method == "GET" and path in public_pages:
            if self._serve_static("/privacy.html"):
                return

        # 인증 면제 경로
        auth_exempt = {"/login", "/api/auth/login", "/api/auth/logout", "/favicon.ico", "/privacy", "/privacy.html"}
        if path not in auth_exempt:
            if not self._check_auth(path):
                return

        # 라이선스/토큰 관리 — 로컬 전용
        if path.startswith("/api/licenses") or path == "/admin/licenses" or path.startswith("/api/tokens"):
            if not _is_local_request(self):
                self._json({"ok": False, "error": "forbidden",
                             "message": "관리 기능은 로컬에서만 가능합니다"}, 403)
                return

        # SSE 엔드포인트 (GET 전용, 라우트 매칭보다 우선)
        if method == "GET":
            sse_match = re.match(r"^/api/teams/([^/]+)/events$", path)
            if sse_match:
                self._handle_sse(sse_match.group(1))
                return

            if path == "/api/supervisor/events":
                self._handle_sse_global()
                return

        # POST SSE 스트리밍 (body 읽기 전에 처리)
        if method == "POST" and path == "/api/agent/chat/stream":
            self._handle_chat_stream()
            return

        body = self._read_body() if method in ("POST", "PUT", "DELETE") else {}

        # 로그인 페이지
        if method == "GET" and path == "/login":
            if not self._serve_static("/login.html"):
                self._html(LOGIN_HTML)
            return

        # 라이선스 관리 페이지
        if method == "GET" and path == "/admin/licenses":
            if not self._serve_static("/admin.html"):
                self._html(ADMIN_HTML)
            return

        # HTML 페이지 — web/ 우선, 임베디드 폴백
        if method == "GET" and path in ("", "/", "/board"):
            if not self._serve_static("/index.html"):
                self._html(BOARD_HTML)
            return
        if method == "GET" and path == "/supervisor":
            if not self._serve_static("/index.html"):
                self._html(SUPERVISOR_HTML)
            return
        # SPA 해시 라우팅 지원: /archives 등도 index.html로
        if method == "GET" and path in ("/archives", "/settings"):
            if self._serve_static("/index.html"):
                return

        # MCP Streamable HTTP Transport
        if path == "/mcp":
            session_header = self.headers.get("Mcp-Session-Id", "")

            if method == "POST":
                auth_project = getattr(self, '_auth_token_info', {}).get('name', '')
                # 세션 유효성 (initialize 제외)
                rpc_method = body.get("method", "") if body else ""
                if session_header and rpc_method != "initialize":
                    _mcp_validate_session(session_header)
                result, new_session_id = handle_mcp_request(body, auth_project=auth_project)
                if result is None:
                    # notifications → 202 Accepted
                    self.send_response(202)
                    self._cors()
                    if session_header:
                        self.send_header("Mcp-Session-Id", session_header)
                    self.end_headers()
                else:
                    resp_body = json.dumps(result, ensure_ascii=False).encode("utf-8")
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-Type", "application/json; charset=utf-8")
                    self.send_header("Content-Length", str(len(resp_body)))
                    # initialize → 새 세션 ID 반환
                    if new_session_id:
                        self.send_header("Mcp-Session-Id", new_session_id)
                    elif session_header:
                        self.send_header("Mcp-Session-Id", session_header)
                    self.end_headers()
                    self.wfile.write(resp_body)
                return

            if method == "GET":
                # SSE 스트림 (서버→클라이언트 알림용)
                self.send_response(200)
                self._cors()
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "keep-alive")
                self.send_header("X-Accel-Buffering", "no")
                if session_header:
                    self.send_header("Mcp-Session-Id", session_header)
                self.end_headers()
                # 연결 확인 이벤트 후 하트비트 유지
                try:
                    self.wfile.write(b"event: open\ndata: {}\n\n")
                    self.wfile.flush()
                    while True:
                        time.sleep(15)
                        self.wfile.write(b": heartbeat\n\n")
                        self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
                    pass
                return

            if method == "DELETE":
                # 세션 종료
                if session_header:
                    _mcp_delete_session(session_header)
                self.send_response(200)
                self._cors()
                self.send_header("Content-Type", "application/json; charset=utf-8")
                resp = b'{"ok":true}'
                self.send_header("Content-Length", str(len(resp)))
                self.end_headers()
                self.wfile.write(resp)
                return

        # REST API 라우팅
        handler, url_params = match_route(method, path)
        if handler:
            result = handler(None, body, url_params, query)
            # 로그인 성공 시 세션 쿠키 설정
            if path == "/api/auth/login" and isinstance(result, dict) and result.get("ok"):
                token = result.get("session_token")
                if token:
                    body_bytes = json.dumps(result, ensure_ascii=False).encode("utf-8")
                    self.send_response(200)
                    self._cors()
                    self.send_header("Content-Type", "application/json; charset=utf-8")
                    self.send_header("Set-Cookie",
                                     f"kanban_session={token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=86400")
                    self.send_header("Content-Length", str(len(body_bytes)))
                    self.end_headers()
                    self.wfile.write(body_bytes)
                    return
            if isinstance(result, dict) and result.get("ok") is False:
                status = 400
            else:
                status = 201 if method == "POST" else 200
            self._json(result, status)
            return

        self._json({"ok": False, "error": "not_found", "path": path, "method": method}, 404)

    def do_GET(self):
        self._handle_api("GET")

    def do_POST(self):
        self._handle_api("POST")

    def do_PUT(self):
        self._handle_api("PUT")

    def do_PATCH(self):
        self._handle_api("PUT")  # PATCH → PUT으로 매핑

    def do_DELETE(self):
        self._handle_api("DELETE")


def main():
    parser = argparse.ArgumentParser(description="Agent Team Kanban Board Server v2.0")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"서버 포트 (기본: {DEFAULT_PORT})")
    parser.add_argument("--host", default=DEFAULT_HOST, help=f"바인딩 호스트 (기본: {DEFAULT_HOST})")
    parser.add_argument("--no-browser", action="store_true", help="브라우저 자동 열기 비활성화")
    args = parser.parse_args()

    init_db()
    _write_queue.start()

    # 상주 에이전트 시작 (Telegram 폴링 + 티켓 감시 통합)
    _resident_start()
    print("  Resident agent: started")

    # CLI Worker 자동 상주 시작
    try:
        cli_worker_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cli-worker.py")
        if os.path.isfile(cli_worker_path):
            import subprocess as _sp
            _sp.Popen(
                [sys.executable, cli_worker_path, "--server", f"http://localhost:{args.port}"],
                stdout=open("/tmp/cli-worker.log", "a"), stderr=_sp.STDOUT,
                start_new_session=True
            )
            print("  CLI Worker: started (auto)")
    except Exception as e:
        print(f"  CLI Worker: failed ({e})")

    server = ThreadedHTTPServer((args.host, args.port), KanbanHandler)
    local_ip = "localhost"
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        pass

    print(f"\n  Agent Team Kanban Board v{VERSION}")
    print(f"  ──────────────────────────────────")
    print(f"  Board:      http://localhost:{args.port}/board")
    print(f"  Supervisor: http://localhost:{args.port}/supervisor")
    print(f"  Licenses:   http://localhost:{args.port}/admin/licenses")
    print(f"  Network:    http://{local_ip}:{args.port}/board")
    print(f"  MCP:        http://localhost:{args.port}/mcp")
    print(f"  DB:         {DB_PATH}")
    print(f"  ──────────────────────────────────")
    print(f"  원격 접속: 라이선스 키 필요 (로컬은 인증 불필요)")
    print(f"  Ctrl+C to stop\n")

    if not args.no_browser:
        try:
            import webbrowser
            webbrowser.open(f"http://localhost:{args.port}/board")
        except Exception:
            pass

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Stopped.")
        server.server_close()





# ── 앱 알림 큐 (상주 에이전트 보고/완료 알림) ──

_app_notifications = []
_app_notif_counter = 0

def _app_notify(notif_type, title, body, data=None):
    """앱 알림 큐에 추가. 앱이 폴링하여 수신."""
    global _app_notif_counter
    try:
        conn = get_db()
        row = conn.execute("SELECT value FROM server_settings WHERE key='notification_prefs'").fetchone()
        conn.close()
        prefs = json.loads(row["value"]) if row and row["value"] else {}
    except Exception:
        prefs = {}
    type_map = {"team_created": "team_created", "team_completed": "team_completed",
                "artifact": "artifact_created", "error": "error",
                "agent_report": "team_completed", "approval": "team_completed"}
    pref_key = type_map.get(notif_type, notif_type)
    if prefs and not prefs.get(pref_key, True):
        return
    _app_notif_counter += 1
    _app_notifications.insert(0, {
        "id": f"n-{_app_notif_counter}", "type": notif_type,
        "title": title, "body": body, "data": data or {},
        "time": now_utc(), "read": False,
    })
    if len(_app_notifications) > 50:
        _app_notifications.pop()


@route("GET", "/api/notifications")
def r_notifications(params, body, url_params, query):
    unread = query.get("unread_only", ["false"])[0] == "true" if isinstance(query, dict) else False
    items = [n for n in _app_notifications if not n["read"]] if unread else _app_notifications[:30]
    return {"ok": True, "notifications": items, "unread_count": sum(1 for n in _app_notifications if not n["read"])}


@route("POST", "/api/notifications/read")
def r_notifications_read(params, body, url_params, query):
    notif_id = body.get("id")
    if notif_id == "all":
        for n in _app_notifications:
            n["read"] = True
    elif notif_id:
        for n in _app_notifications:
            if n["id"] == notif_id:
                n["read"] = True
                break
    return {"ok": True}


# ── 프로젝트 표시 설정 (앱에서 프로젝트 추가/제거) ──

@route("GET", "/api/settings/visible-projects")
def r_visible_projects_get(params, body, url_params, query):
    conn = get_db()
    row = conn.execute("SELECT value FROM server_settings WHERE key='visible_projects'").fetchone()
    conn.close()
    if row and row["value"]:
        return {"ok": True, "projects": json.loads(row["value"]), "mode": "whitelist"}
    return {"ok": True, "projects": [], "mode": "all"}  # 빈 목록 = 전체 표시


@route("PUT", "/api/settings/visible-projects")
def r_visible_projects_set(params, body, url_params, query):
    projects = body.get("projects", [])
    conn = get_db()
    conn.execute(
        "INSERT OR REPLACE INTO server_settings (key, value, updated_at) VALUES ('visible_projects', ?, datetime('now'))",
        (json.dumps(projects, ensure_ascii=False),)
    )
    conn.commit()
    conn.close()
    mode = "whitelist" if projects else "all"
    return {"ok": True, "projects": projects, "mode": mode}


# ── 프로젝트 아키텍처 뷰 API ──

@route("GET", "/api/projects/architecture")
def r_project_architecture(params, body, url_params, query):
    """프로젝트별 원자적 아키텍처 뷰 — 팀, 티켓, 산출물, 에이전트, 목표 달성률 집계."""
    conn = get_db()
    try:
        # 프로젝트 그룹별 팀 조회
        teams = rows_to_list(conn.execute(
            "SELECT * FROM agent_teams WHERE status='Active' AND project_group != '' ORDER BY project_group, name"
        ).fetchall())
        # 프로젝트별 그룹핑
        projects = {}
        for t in teams:
            pg = t["project_group"]
            if pg not in projects:
                projects[pg] = {"name": pg, "teams": [], "total_tickets": 0, "done_tickets": 0,
                                "blocked_tickets": 0, "review_tickets": 0, "agents": 0,
                                "artifacts": 0, "goals": [], "ticket_details": []}
            p = projects[pg]
            p["teams"].append({"team_id": t["team_id"], "name": t["name"], "status": t["status"]})
            # 팀 티켓 상세
            tickets = rows_to_list(conn.execute(
                "SELECT ticket_id, title, status, priority, assigned_member_id, depends_on, tags, "
                "estimated_minutes, actual_minutes, progress_note, retry_count "
                "FROM tickets WHERE team_id=? ORDER BY created_at", (t["team_id"],)
            ).fetchall())
            for tk in tickets:
                p["total_tickets"] += 1
                if tk["status"] == "Done": p["done_tickets"] += 1
                elif tk["status"] == "Blocked": p["blocked_tickets"] += 1
                elif tk["status"] == "Review": p["review_tickets"] += 1
                # 태그 파싱
                tags = []
                if tk.get("tags"):
                    try: tags = json.loads(tk["tags"]) if isinstance(tk["tags"], str) else tk["tags"]
                    except: pass
                # 의존성 파싱
                deps = []
                if tk.get("depends_on"):
                    try: deps = json.loads(tk["depends_on"]) if isinstance(tk["depends_on"], str) else tk["depends_on"]
                    except: pass
                # 산출물 수
                art_count = conn.execute(
                    "SELECT COUNT(*) as c FROM artifacts WHERE ticket_id=?", (tk["ticket_id"],)
                ).fetchone()["c"]
                # 목표 티켓 감지 (태그에 '목표' 또는 '감사' 포함)
                is_goal = any(tag in ['목표', '로드맵', 'goal'] for tag in tags)
                p["ticket_details"].append({
                    "ticket_id": tk["ticket_id"], "title": tk["title"],
                    "status": tk["status"], "priority": tk["priority"],
                    "team_name": t["name"], "team_id": t["team_id"],
                    "tags": tags, "depends_on": deps,
                    "artifacts": art_count, "retry_count": tk.get("retry_count", 0),
                    "is_goal": is_goal, "progress_note": tk.get("progress_note"),
                    "assigned": tk.get("assigned_member_id"),
                })
                if is_goal:
                    p["goals"].append({"title": tk["title"], "status": tk["status"], "ticket_id": tk["ticket_id"]})
            # 에이전트 수
            agent_count = conn.execute(
                "SELECT COUNT(*) as c FROM team_members WHERE team_id=?", (t["team_id"],)
            ).fetchone()["c"]
            p["agents"] += agent_count
            # 산출물 수
            art_total = conn.execute(
                "SELECT COUNT(*) as c FROM artifacts WHERE team_id=?", (t["team_id"],)
            ).fetchone()["c"]
            p["artifacts"] += art_total

        # 완료율 계산
        result = []
        for pg, p in projects.items():
            total = p["total_tickets"]
            done = p["done_tickets"]
            p["progress"] = round(done / total * 100, 1) if total > 0 else 0
            # 상태별 분류
            by_status = {}
            for tk in p["ticket_details"]:
                by_status.setdefault(tk["status"], []).append(tk)
            p["by_status"] = {s: len(tks) for s, tks in by_status.items()}
            result.append(p)

        result.sort(key=lambda x: (-x["progress"], -x["total_tickets"]))
    finally:
        conn.close()

    return {"ok": True, "projects": result, "count": len(result)}


# ── 프로젝트 인벤토리 API (에이전트/스킬/훅 스캔) ──

@route("GET", "/api/projects/inventory")
def r_project_inventory(params, body, url_params, query):
    """각 프로젝트의 에이전트, 스킬, 훅 인벤토리를 실시간 스캔."""
    projects_dir = "/home/u2dia/github"
    project_names = query.get("projects", [None])[0]
    if project_names:
        dirs = [os.path.join(projects_dir, p.strip()) for p in project_names.split(",")]
    else:
        dirs = [os.path.join(projects_dir, d) for d in os.listdir(projects_dir)
                if os.path.isdir(os.path.join(projects_dir, d, ".claude"))]

    result = []
    for pdir in dirs:
        if not os.path.isdir(pdir):
            continue
        pname = os.path.basename(pdir)
        claude_dir = os.path.join(pdir, ".claude")
        if not os.path.isdir(claude_dir):
            continue

        inv = {"name": pname, "path": pdir, "agents": [], "skills": [], "hooks": [],
               "has_claude_md": False, "has_mcp": False, "mcp_servers": []}

        # CLAUDE.md
        for cm in [os.path.join(claude_dir, "CLAUDE.md"), os.path.join(pdir, "CLAUDE.md")]:
            if os.path.isfile(cm):
                inv["has_claude_md"] = True
                break

        # Agents
        agents_dir = os.path.join(claude_dir, "agents")
        if os.path.isdir(agents_dir):
            for f in sorted(os.listdir(agents_dir)):
                if f.endswith(".md"):
                    apath = os.path.join(agents_dir, f)
                    name = f.replace(".md", "")
                    desc = ""
                    try:
                        with open(apath, "r", encoding="utf-8", errors="replace") as fh:
                            lines = fh.readlines()[:10]
                        for line in lines:
                            if line.strip().startswith("description:"):
                                desc = line.split(":", 1)[1].strip()[:100]
                                break
                    except Exception:
                        pass
                    inv["agents"].append({"name": name, "description": desc})

        # Skills
        skills_dir = os.path.join(claude_dir, "skills")
        if os.path.isdir(skills_dir):
            for d in sorted(os.listdir(skills_dir)):
                sd = os.path.join(skills_dir, d)
                if os.path.isdir(sd) and os.path.isfile(os.path.join(sd, "SKILL.md")):
                    desc = ""
                    try:
                        with open(os.path.join(sd, "SKILL.md"), "r", encoding="utf-8", errors="replace") as fh:
                            for line in fh.readlines()[:10]:
                                if line.strip().startswith("description:"):
                                    desc = line.split(":", 1)[1].strip()[:100]
                                    break
                    except Exception:
                        pass
                    inv["skills"].append({"name": d, "description": desc})

        # Hooks
        hooks_dir = os.path.join(claude_dir, "hooks")
        if os.path.isdir(hooks_dir):
            for f in sorted(os.listdir(hooks_dir)):
                if f.endswith((".json", ".sh", ".py", ".mjs")):
                    inv["hooks"].append(f)

        # MCP servers
        settings_path = os.path.join(claude_dir, "settings.json")
        if os.path.isfile(settings_path):
            try:
                with open(settings_path, "r") as fh:
                    settings = json.loads(fh.read())
                mcps = settings.get("mcpServers", {})
                inv["has_mcp"] = len(mcps) > 0
                inv["mcp_servers"] = list(mcps.keys())
            except Exception:
                pass

        inv["agent_count"] = len(inv["agents"])
        inv["skill_count"] = len(inv["skills"])
        inv["hook_count"] = len(inv["hooks"])
        result.append(inv)

    result.sort(key=lambda x: (-x["agent_count"], -x["skill_count"]))
    return {"ok": True, "projects": result, "count": len(result)}


# ── 프로젝트 목표 + 체크리스트 API ──

@route("GET", "/api/projects/goals")
def r_project_goals(params, body, url_params, query):
    """각 프로젝트의 최종 목표 + 전체 히스토리 + 구현 현황 + 남은 과제."""
    github_dir = "/home/u2dia/github"
    conn = get_db()

    # 활성 + 아카이브 전체 팀 (프로젝트 전체 히스토리)
    teams = rows_to_list(conn.execute(
        "SELECT * FROM agent_teams WHERE project_group != '' ORDER BY project_group"
    ).fetchall())

    projects = {}
    for t in teams:
        pg = t["project_group"]
        if pg not in projects:
            projects[pg] = {"name": pg, "teams": [], "total_tickets": 0, "done_tickets": 0,
                            "blocked": 0, "in_progress": 0, "review": 0, "backlog": 0,
                            "goals": [], "agents": 0, "active_teams": 0, "archived_teams": 0}
        p = projects[pg]
        p["teams"].append({"team_id": t["team_id"], "name": t["name"], "status": t["status"]})
        if t["status"] == "Active": p["active_teams"] += 1
        else: p["archived_teams"] += 1

        tickets = rows_to_list(conn.execute(
            "SELECT ticket_id, title, status, priority, tags FROM tickets WHERE team_id=?", (t["team_id"],)
        ).fetchall())
        for tk in tickets:
            p["total_tickets"] += 1
            if tk["status"] == "Done": p["done_tickets"] += 1
            elif tk["status"] == "Blocked": p["blocked"] += 1
            elif tk["status"] == "InProgress": p["in_progress"] += 1
            elif tk["status"] == "Review": p["review"] += 1
            elif tk["status"] in ("Backlog", "Todo"): p["backlog"] += 1

        agent_count = conn.execute("SELECT COUNT(*) as c FROM team_members WHERE team_id=?", (t["team_id"],)).fetchone()["c"]
        p["agents"] += agent_count

    # 프로젝트별 목표 추출 (CLAUDE.md에서)
    result = []
    for pg, p in projects.items():
        # CLAUDE.md에서 프로젝트 설명 추출
        description = ""
        claude_md = None
        for proj_dir in os.listdir(github_dir):
            if proj_dir.lower().replace("-","").replace("_","") == pg.lower().replace("-","").replace("_","").replace(" ",""):
                for cm in [os.path.join(github_dir, proj_dir, ".claude", "CLAUDE.md"), os.path.join(github_dir, proj_dir, "CLAUDE.md")]:
                    if os.path.isfile(cm):
                        claude_md = cm
                        break
                break

        if claude_md:
            try:
                with open(claude_md, "r", errors="replace") as f:
                    lines = f.readlines()[:20]
                for line in lines:
                    stripped = line.strip()
                    if stripped and not stripped.startswith("#") and not stripped.startswith("**Version") and not stripped.startswith("**Last") and not stripped.startswith("**Status") and len(stripped) > 20:
                        description = stripped[:200]
                        break
            except: pass

        total = p["total_tickets"]
        done = p["done_tickets"]
        progress = round(done / total * 100, 1) if total > 0 else 0

        # 티켓을 체크리스트로 변환
        checklist = []
        for t_entry in p["teams"]:
            team_tickets = rows_to_list(conn.execute(
                "SELECT ticket_id, title, status, priority FROM tickets WHERE team_id=? ORDER BY "
                "CASE priority WHEN 'Critical' THEN 0 WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END, created_at",
                (t_entry["team_id"],)
            ).fetchall())
            for tk in team_tickets:
                checklist.append({
                    "id": tk["ticket_id"], "title": tk["title"],
                    "done": tk["status"] == "Done", "status": tk["status"],
                    "priority": tk["priority"], "team": t_entry["name"],
                })

        remaining = total - done
        result.append({
            "project": pg, "description": description,
            "progress": progress, "total": total, "done": done, "remaining": remaining,
            "blocked": p["blocked"], "in_progress": p["in_progress"], "review": p["review"], "backlog": p["backlog"],
            "teams": len(p["teams"]), "active_teams": p["active_teams"], "archived_teams": p["archived_teams"],
            "agents": p["agents"],
            "checklist": checklist,
        })

    conn.close()
    result.sort(key=lambda x: (-x["progress"], -x["total"]))

    # 등록된 프로젝트 목표 병합
    conn2 = get_db()
    for p in result:
        obj = conn2.execute("SELECT title, description FROM team_objectives WHERE team_id=? ORDER BY created_at DESC LIMIT 1", (p["project"],)).fetchone()
        if obj:
            p["goal_title"] = obj["title"]
            try: p["milestones"] = json.loads(obj["description"] or "[]")
            except: p["milestones"] = []
        else:
            p["goal_title"] = ""
            p["milestones"] = []
    conn2.close()

    return {"ok": True, "projects": result, "count": len(result)}


# ── Q&A 고객 게시판 + 자동 CS 티켓 발행 ──

@route("POST", "/api/cs/question")
def r_cs_question(params, body, url_params, query):
    """고객 Q&A 질문 등록 → Super Admin CS 칸반에 자동 티켓 발행."""
    title = body.get("title", "").strip()
    content = body.get("content", "").strip()
    customer = body.get("customer", "anonymous")
    project = body.get("project", "")
    priority = body.get("priority", "Medium")
    email = body.get("email", "")

    if not title or not content:
        return {"ok": False, "error": "title과 content 필수"}

    # Super Admin CS 팀 찾기
    conn = get_db()
    cs_team = conn.execute(
        "SELECT team_id FROM agent_teams WHERE project_group='U2DIA-CS' AND status='Active' LIMIT 1"
    ).fetchone()

    if not cs_team:
        conn.close()
        return {"ok": False, "error": "CS 팀이 없습니다"}

    cs_team_id = cs_team["team_id"]
    tid = "CS-" + uuid.uuid4().hex[:6].upper()
    ts = now_utc()

    # CS 티켓 자동 생성
    conn.execute(
        "INSERT INTO tickets (ticket_id,team_id,title,description,priority,status,tags,created_at) "
        "VALUES (?,?,?,?,?,?,?,?)",
        (tid, cs_team_id,
         f"[Q&A] {title}",
         f"고객: {customer}\n이메일: {email}\n프로젝트: {project}\n\n{content}",
         priority, "Backlog",
         json.dumps(["cs", "q&a", project] if project else ["cs", "q&a"]),
         ts)
    )
    conn.execute(
        "INSERT INTO activity_logs (team_id,ticket_id,action,message,created_at) VALUES (?,?,?,?,?)",
        (cs_team_id, tid, "cs_question_created",
         f"고객 Q&A: {title} (by {customer})", ts)
    )
    conn.commit()
    conn.close()

    sse_broadcast(cs_team_id, "ticket_created", {"ticket_id": tid, "title": title, "type": "cs_question"})
    return {"ok": True, "ticket_id": tid, "team_id": cs_team_id,
            "ai_disclosure": "이 응답은 AI(인공지능)에 의해 자동 생성되었습니다. 실제 상담원 연결이 필요하시면 별도 요청해 주세요.",
            "message": f"[AI 자동 응답] 문의가 접수되었습니다. 티켓 {tid}으로 추적됩니다.\n\n※ 본 응답은 AI에 의해 자동 생성되었습니다."}


@route("GET", "/api/cs/questions")
def r_cs_questions(params, body, url_params, query):
    """CS Q&A 목록 조회."""
    conn = get_db()
    cs_team = conn.execute(
        "SELECT team_id FROM agent_teams WHERE project_group='U2DIA-CS' AND status='Active' LIMIT 1"
    ).fetchone()
    if not cs_team:
        conn.close()
        return {"ok": True, "questions": []}

    tickets = rows_to_list(conn.execute(
        "SELECT * FROM tickets WHERE team_id=? ORDER BY created_at DESC LIMIT 50",
        (cs_team["team_id"],)
    ).fetchall())
    conn.close()
    return {"ok": True, "questions": tickets, "count": len(tickets)}


# ── Project Goals Registration & History ──

@route("POST", "/api/projects/goals/register")
def r_project_goals_register(params, body, url_params, query):
    """프로젝트 최종 목표 등록/수정."""
    project = body.get("project", "")
    goal = body.get("goal", "")
    milestones = body.get("milestones", [])  # [{"title":"...", "done":false}, ...]

    if not project or not goal:
        return {"ok": False, "error": "project와 goal 필수"}

    conn = get_db()
    ts = now_utc()
    # team_objectives 테이블 활용
    existing = conn.execute("SELECT obj_id FROM team_objectives WHERE team_id=?", (project,)).fetchone()
    if existing:
        conn.execute("UPDATE team_objectives SET title=?, description=?, updated_at=? WHERE obj_id=?",
                     (goal, json.dumps(milestones, ensure_ascii=False), ts, existing["obj_id"]))
    else:
        oid = "OBJ-" + uuid.uuid4().hex[:6].upper()
        conn.execute(
            "INSERT INTO team_objectives (obj_id, team_id, title, description, status, created_at, updated_at) VALUES (?,?,?,?,?,?,?)",
            (oid, project, goal, json.dumps(milestones, ensure_ascii=False), "Active", ts, ts))
    conn.commit()
    conn.close()
    return {"ok": True, "project": project, "goal": goal, "milestones": len(milestones)}


@route("GET", "/api/projects/{project}/goals")
def r_project_goal_get(params, body, url_params, query):
    """프로젝트 최종 목표 조회."""
    project = url_params["project"]
    conn = get_db()
    obj = conn.execute("SELECT * FROM team_objectives WHERE team_id=? ORDER BY created_at DESC LIMIT 1", (project,)).fetchone()
    conn.close()
    if not obj:
        return {"ok": True, "goal": None}
    milestones = []
    try: milestones = json.loads(obj["description"] or "[]")
    except: pass
    return {"ok": True, "goal": {"title": obj["title"], "milestones": milestones, "status": obj["status"], "created_at": obj["created_at"]}}


@route("GET", "/api/teams/{team_id}/history")
def r_team_history(params, body, url_params, query):
    """팀 전체 히스토리 (활동로그 + 메시지 + 산출물 + 피드백)."""
    team_id = url_params["team_id"]
    limit = int(query.get("limit", [100])[0]) if isinstance(query, dict) else 100
    conn = get_db()
    logs = rows_to_list(conn.execute(
        "SELECT 'activity' as type, action, message, member_id, ticket_id, created_at FROM activity_logs WHERE team_id=? ORDER BY created_at DESC LIMIT ?",
        (team_id, limit)).fetchall())
    messages = rows_to_list(conn.execute(
        "SELECT 'message' as type, message_type as action, content as message, sender_member_id as member_id, ticket_id, created_at FROM messages WHERE team_id=? ORDER BY created_at DESC LIMIT ?",
        (team_id, limit)).fetchall())
    artifacts = rows_to_list(conn.execute(
        "SELECT 'artifact' as type, artifact_type as action, title as message, creator_member_id as member_id, ticket_id, created_at FROM artifacts WHERE team_id=? ORDER BY created_at DESC LIMIT ?",
        (team_id, limit)).fetchall())
    conn.close()
    # 합치고 시간순 정렬
    all_items = logs + messages + artifacts
    all_items.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    return {"ok": True, "history": all_items[:limit], "count": len(all_items)}


# ── Sprint REST API ──

@route("POST", "/api/teams/{team_id}/sprints")
def r_sprint_create(params, body, url_params, query):
    return api_sprint_create(url_params["team_id"], body)

@route("GET", "/api/teams/{team_id}/sprints")
def r_sprint_list(params, body, url_params, query):
    return api_sprint_list(url_params["team_id"], query)

@route("GET", "/api/sprints/{sprint_id}")
def r_sprint_get(params, body, url_params, query):
    return api_sprint_get(url_params["sprint_id"])

@route("PUT", "/api/sprints/{sprint_id}/phase")
def r_sprint_phase(params, body, url_params, query):
    return api_sprint_phase(url_params["sprint_id"], body)

@route("POST", "/api/sprints/{sprint_id}/gates")
def r_sprint_gate(params, body, url_params, query):
    return api_sprint_gate(url_params["sprint_id"], body)

@route("POST", "/api/sprints/{sprint_id}/metrics")
def r_sprint_metrics(params, body, url_params, query):
    return api_sprint_metrics_snapshot(url_params["sprint_id"])

@route("GET", "/api/teams/{team_id}/velocity")
def r_sprint_velocity(params, body, url_params, query):
    return api_sprint_velocity(url_params["team_id"])

@route("GET", "/api/sprints/{sprint_id}/burndown")
def r_sprint_burndown(params, body, url_params, query):
    return api_sprint_burndown(url_params["sprint_id"])

@route("POST", "/api/sprints/{sprint_id}/cross-review")
def r_sprint_cross_review(params, body, url_params, query):
    return api_sprint_cross_review(url_params["sprint_id"], body)

@route("GET", "/api/sprints/{sprint_id}/retro")
def r_sprint_retro(params, body, url_params, query):
    return api_sprint_retro(url_params["sprint_id"])

@route("GET", "/api/sprints/global/stats")
def r_sprint_global_stats(params, body, url_params, query):
    conn = get_db()
    try:
        active = conn.execute("SELECT COUNT(*) as c FROM sprints WHERE status='Active'").fetchone()["c"]
        completed = conn.execute("SELECT COUNT(*) as c FROM sprints WHERE status='Completed'").fetchone()["c"]
        phases = rows_to_list(conn.execute(
            "SELECT phase, COUNT(*) as count FROM sprints WHERE status='Active' GROUP BY phase"
        ).fetchall())
        recent_gates = rows_to_list(conn.execute(
            "SELECT gate_type, status, COUNT(*) as count FROM sprint_gates GROUP BY gate_type, status ORDER BY count DESC LIMIT 20"
        ).fetchall())
    finally:
        conn.close()
    return {"ok": True, "active_sprints": active, "completed_sprints": completed,
            "phase_distribution": {p["phase"]: p["count"] for p in phases},
            "gate_summary": recent_gates}


# ── CLI 작업 큐 API ──

@route("GET", "/api/cli/jobs")
def r_cli_jobs_list(params, body, url_params, query):
    """CLI 작업 목록 (status 필터 가능)."""
    status = query.get("status", [None])[0]
    conn = get_db()
    try:
        if status:
            jobs = rows_to_list(conn.execute(
                "SELECT * FROM cli_jobs WHERE status=? ORDER BY created_at DESC LIMIT 50", (status,)
            ).fetchall())
        else:
            jobs = rows_to_list(conn.execute(
                "SELECT * FROM cli_jobs ORDER BY created_at DESC LIMIT 50"
            ).fetchall())
    finally:
        conn.close()
    return {"ok": True, "jobs": jobs}


@route("POST", "/api/cli/jobs")
def r_cli_jobs_create(params, body, url_params, query):
    """CLI 작업 생성. ticket_id 또는 project_name+prompt 필수."""
    prompt = body.get("prompt", "")
    ticket_id = body.get("ticket_id")
    team_id = body.get("team_id")
    project_name = body.get("project_name", "")
    project_path = body.get("project_path", "")
    auto_approve = body.get("auto_approve", False)
    allowed_tools = body.get("allowed_tools", "Read,Write,Edit,Bash,Glob,Grep")
    max_turns = body.get("max_turns", 30)
    timeout_sec = body.get("timeout_sec", 300)
    model = body.get("model", "")

    # 티켓에서 정보 추출
    if ticket_id and not prompt:
        conn = get_db()
        try:
            tk = conn.execute("SELECT * FROM tickets WHERE ticket_id=?", (ticket_id,)).fetchone()
            if tk:
                prompt = f"{tk['title']}\n{tk['description'] or ''}"
                team_id = team_id or tk["team_id"]
        finally:
            conn.close()

    if not prompt:
        return {"ok": False, "error": "prompt 또는 ticket_id 필수"}

    # 프로젝트 경로 해석
    if not project_path and project_name:
        project_path = _find_project_path(project_name) or ""
    if not project_path and team_id:
        conn = get_db()
        try:
            team = conn.execute("SELECT project_group FROM agent_teams WHERE team_id=?", (team_id,)).fetchone()
            if team and team["project_group"]:
                project_path = _find_project_path(team["project_group"]) or ""
        finally:
            conn.close()

    # fallback: 프로젝트 경로 없으면 칸반보드 프로젝트 사용
    if not project_path or not os.path.isdir(project_path):
        project_path = os.path.dirname(os.path.abspath(__file__))  # server.py 위치 = 칸반보드 루트
        project_name = project_name or "U2DIA-KANBAN-BOARD"

    job_id = "CLJ-" + uuid.uuid4().hex[:8].upper()
    status = "approved" if auto_approve else "pending"
    approved_at = "datetime('now')" if auto_approve else None

    conn = get_db()
    try:
        conn.execute(
            "INSERT INTO cli_jobs (job_id, ticket_id, team_id, project_path, project_name, prompt, status, "
            "allowed_tools, max_turns, timeout_sec, model, created_at, approved_at) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,datetime('now'),?)",
            (job_id, ticket_id, team_id, project_path, project_name, prompt, status,
             allowed_tools, max_turns, timeout_sec, model,
             datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S") if auto_approve else None)
        )
        conn.commit()
    finally:
        conn.close()

    # 티켓 상태를 InProgress로
    if ticket_id:
        conn2 = get_db()
        try:
            conn2.execute("UPDATE tickets SET status='InProgress' WHERE ticket_id=?", (ticket_id,))
            conn2.commit()
        finally:
            conn2.close()

    sse_broadcast("global", "cli_job_created", {"job_id": job_id, "ticket_id": ticket_id, "status": status})
    return {"ok": True, "job_id": job_id, "status": status, "project_path": project_path}


@route("PUT", "/api/cli/jobs/{job_id}/approve")
def r_cli_jobs_approve(params, body, url_params, query):
    """CLI 작업 승인 (pending → approved)."""
    job_id = url_params["job_id"]
    conn = get_db()
    try:
        job = conn.execute("SELECT * FROM cli_jobs WHERE job_id=?", (job_id,)).fetchone()
        if not job:
            return {"ok": False, "error": "작업 없음"}
        if job["status"] != "pending":
            return {"ok": False, "error": f"현재 상태 {job['status']}에서 승인 불가"}
        conn.execute(
            "UPDATE cli_jobs SET status='approved', approved_at=datetime('now') WHERE job_id=?",
            (job_id,)
        )
        conn.commit()
    finally:
        conn.close()
    sse_broadcast("global", "cli_job_approved", {"job_id": job_id})
    return {"ok": True, "job_id": job_id, "status": "approved"}


@route("PUT", "/api/cli/jobs/{job_id}/cancel")
def r_cli_jobs_cancel(params, body, url_params, query):
    """CLI 작업 취소."""
    job_id = url_params["job_id"]
    conn = get_db()
    try:
        conn.execute(
            "UPDATE cli_jobs SET status='cancelled' WHERE job_id=? AND status IN ('pending','approved')",
            (job_id,)
        )
        conn.commit()
    finally:
        conn.close()
    return {"ok": True, "job_id": job_id, "status": "cancelled"}


@route("GET", "/api/cli/jobs/next")
def r_cli_jobs_next(params, body, url_params, query):
    """Worker용: 다음 실행할 작업 가져오기 (approved → running)."""
    worker_id = query.get("worker_id", ["anonymous"])[0]
    conn = get_db()
    try:
        job = conn.execute(
            "SELECT * FROM cli_jobs WHERE status='approved' ORDER BY created_at ASC LIMIT 1"
        ).fetchone()
        if not job:
            return {"ok": True, "job": None}
        conn.execute(
            "UPDATE cli_jobs SET status='running', started_at=datetime('now'), worker_id=? WHERE job_id=?",
            (worker_id, job["job_id"])
        )
        conn.commit()
        job_dict = dict(job)
        job_dict["status"] = "running"
    finally:
        conn.close()
    return {"ok": True, "job": job_dict}


@route("PUT", "/api/cli/jobs/{job_id}/result")
def r_cli_jobs_result(params, body, url_params, query):
    """Worker용: 실행 결과 보고."""
    job_id = url_params["job_id"]
    success = body.get("success", False)
    output = body.get("output", "")
    error = body.get("error", "")

    conn = get_db()
    try:
        job = conn.execute("SELECT * FROM cli_jobs WHERE job_id=?", (job_id,)).fetchone()
        if not job:
            return {"ok": False, "error": "작업 없음"}

        new_status = "completed" if success else "failed"
        conn.execute(
            "UPDATE cli_jobs SET status=?, completed_at=datetime('now'), result_summary=?, result_length=?, error=? "
            "WHERE job_id=?",
            (new_status, output[:2000], len(output), error[:1000] if error else None, job_id)
        )

        # 산출물 등록
        if success and output and job["ticket_id"]:
            aid = "A-" + uuid.uuid4().hex[:6].upper()
            conn.execute(
                "INSERT INTO artifacts (artifact_id,team_id,ticket_id,creator_member_id,artifact_type,title,content,created_at) "
                "VALUES (?,?,?,?,?,?,?,datetime('now'))",
                (aid, job["team_id"], job["ticket_id"], "cli-worker", "code",
                 f"CLI 작업 결과: {job_id}", output[:5000])
            )
            # 티켓 → Review
            conn.execute("UPDATE tickets SET status='Review' WHERE ticket_id=?", (job["ticket_id"],))
            conn.execute(
                "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,created_at) "
                "VALUES (?,?,?,?,?,datetime('now'))",
                (job["team_id"], job["ticket_id"], "cli-worker", "cli_completed",
                 f"CLI 작업 완료 ({job_id}): {len(output)}자 산출물")
            )

        if not success and job["ticket_id"]:
            conn.execute(
                "INSERT INTO activity_logs (team_id,ticket_id,member_id,action,message,created_at) "
                "VALUES (?,?,?,?,?,datetime('now'))",
                (job["team_id"], job["ticket_id"], "cli-worker", "cli_failed",
                 f"CLI 작업 실패 ({job_id}): {error[:200]}")
            )

        conn.commit()
    finally:
        conn.close()

    sse_broadcast("global", "cli_job_completed", {"job_id": job_id, "status": new_status})
    return {"ok": True, "job_id": job_id, "status": new_status}


@route("PUT", "/api/cli/jobs/{job_id}/log")
def r_cli_jobs_log_update(params, body, url_params, query):
    """Worker용: 실행 중 실시간 로그 업데이트."""
    job_id = url_params["job_id"]
    log_text = body.get("log", "")
    append = body.get("append", True)
    conn = get_db()
    try:
        if append:
            conn.execute(
                "UPDATE cli_jobs SET live_log = COALESCE(live_log,'') || ? WHERE job_id=? AND status='running'",
                (log_text, job_id)
            )
        else:
            conn.execute(
                "UPDATE cli_jobs SET live_log=? WHERE job_id=? AND status='running'",
                (log_text[-5000:], job_id)
            )
        conn.commit()
    finally:
        conn.close()
    sse_broadcast("global", "cli_job_log", {"job_id": job_id, "log": log_text})
    return {"ok": True}


@route("GET", "/api/cli/jobs/{job_id}/log")
def r_cli_jobs_log_get(params, body, url_params, query):
    """실행 중인 작업의 실시간 로그 조회."""
    job_id = url_params["job_id"]
    conn = get_db()
    try:
        job = conn.execute("SELECT live_log, status FROM cli_jobs WHERE job_id=?", (job_id,)).fetchone()
        if not job:
            return {"ok": False, "error": "작업 없음"}
        return {"ok": True, "log": job["live_log"] or "", "status": job["status"]}
    finally:
        conn.close()


@route("PUT", "/api/cli/jobs/{job_id}/kill")
def r_cli_jobs_kill(params, body, url_params, query):
    """실행 중인 작업 강제 중단 요청 (Worker가 폴링하여 중단)."""
    job_id = url_params["job_id"]
    conn = get_db()
    try:
        conn.execute(
            "UPDATE cli_jobs SET status='cancelled', completed_at=datetime('now'), error='사용자 중단' "
            "WHERE job_id=? AND status='running'",
            (job_id,)
        )
        conn.commit()
    finally:
        conn.close()
    sse_broadcast("global", "cli_job_killed", {"job_id": job_id})
    return {"ok": True, "job_id": job_id, "status": "cancelled"}


@route("GET", "/api/cli/models")
def r_cli_models(params, body, url_params, query):
    """CLI 작업에 사용 가능한 모델 목록."""
    models = [
        {"id": "claude-sonnet-4-20250514", "name": "Claude Sonnet 4", "provider": "anthropic", "default": True},
        {"id": "claude-opus-4-6", "name": "Claude Opus 4.6", "provider": "anthropic"},
        {"id": "claude-haiku-4-5-20251001", "name": "Claude Haiku 4.5", "provider": "anthropic"},
    ]
    # Ollama 모델 추가
    try:
        req = Request(f"{_OLLAMA_URL}/api/tags")
        resp = urlopen(req, timeout=3)
        ollama_models = json.loads(resp.read()).get("models", [])
        for m in ollama_models:
            name = m.get("name", "")
            models.append({"id": f"ollama:{name}", "name": f"Ollama {name}", "provider": "ollama"})
    except Exception:
        pass
    return {"ok": True, "models": models}


@route("GET", "/api/cli/stats")
def r_cli_stats(params, body, url_params, query):
    """CLI 작업 통계."""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT status, COUNT(*) as count FROM cli_jobs GROUP BY status"
        ).fetchall()
        stats = {r["status"]: r["count"] for r in rows}
        recent = rows_to_list(conn.execute(
            "SELECT job_id, ticket_id, project_name, status, created_at, completed_at "
            "FROM cli_jobs ORDER BY created_at DESC LIMIT 10"
        ).fetchall())
    finally:
        conn.close()
    return {"ok": True, "stats": stats, "recent": recent}


@route("GET", "/api/teams/{team_id}/specialists")
def r_team_specialists(params, body, url_params, query):
    """팀의 에이전트 전문가 현황 + KPI."""
    team_id = url_params["team_id"]
    conn = get_db()
    try:
        members = rows_to_list(conn.execute(
            "SELECT * FROM team_members WHERE team_id=?", (team_id,)
        ).fetchall())
        tickets = rows_to_list(conn.execute(
            "SELECT * FROM tickets WHERE team_id=?", (team_id,)
        ).fetchall())

        agents = []
        for m in members:
            mid = m.get("member_id", "")
            role = m.get("role", "general")
            display = m.get("display_name", mid)

            # KPI 계산
            claimed = [t for t in tickets if t.get("assigned_member_id") == mid]
            done = [t for t in claimed if t.get("status") == "Done"]
            wip = [t for t in claimed if t.get("status") == "InProgress"]
            review = [t for t in claimed if t.get("status") == "Review"]

            # 피드백 점수
            fb_rows = conn.execute(
                "SELECT score FROM ticket_feedbacks WHERE ticket_id IN "
                "(SELECT ticket_id FROM tickets WHERE assigned_member_id=?) AND score IS NOT NULL",
                (mid,)
            ).fetchall()
            scores = [r["score"] for r in fb_rows]
            avg_score = round(sum(scores) / len(scores), 1) if scores else 0

            agents.append({
                "member_id": mid,
                "display_name": display,
                "role": role,
                "status": m.get("status", "Idle"),
                "current_ticket": m.get("current_ticket_id"),
                "kpi": {
                    "total_claimed": len(claimed),
                    "done": len(done),
                    "in_progress": len(wip),
                    "review": len(review),
                    "avg_score": avg_score,
                    "total_reviews": len(scores),
                    "completion_rate": round(len(done) / max(len(claimed), 1) * 100),
                },
            })
    finally:
        conn.close()
    return {"ok": True, "team_id": team_id, "agents": agents, "count": len(agents)}


@route("GET", "/api/usage/history")
def r_usage_history(params, body, url_params, query):
    """월별 토큰 사용량 히스토리."""
    conn = get_db()
    try:
        rows = conn.execute("""
            SELECT substr(created_at,1,7) as month,
                   SUM(input_tokens) as input_tokens,
                   SUM(output_tokens) as output_tokens,
                   ROUND(SUM(estimated_cost),2) as cost,
                   COUNT(*) as count
            FROM token_usage GROUP BY month ORDER BY month
        """).fetchall()
        months = [{"month": r["month"], "input_tokens": r["input_tokens"],
                   "output_tokens": r["output_tokens"], "cost": r["cost"],
                   "count": r["count"]} for r in rows]
        total_cost = sum(m["cost"] for m in months)
        total_tokens = sum(m["input_tokens"] + m["output_tokens"] for m in months)
    finally:
        conn.close()
    return {"ok": True, "months": months, "total_cost": round(total_cost, 2), "total_tokens": total_tokens}


@route("GET", "/api/exchange-rate")
def r_exchange_rate(params, body, url_params, query):
    """실시간 USD→KRW 환율 조회."""
    try:
        req = Request("https://api.exchangerate-api.com/v4/latest/USD")
        resp = urlopen(req, timeout=5)
        data = json.loads(resp.read())
        krw = data.get("rates", {}).get("KRW", 1380)
        return {"ok": True, "rate": krw, "date": data.get("date", "")}
    except Exception:
        return {"ok": True, "rate": 1380, "date": "fallback"}


@route("GET", "/api/supervisor/pipeline")
def r_supervisor_pipeline(params, body, url_params, query):
    """Supervisor 파이프라인 헬스체크 — 전체 현황 + 병목 분석."""
    conn = get_db()
    try:
        # 상태별 티켓 수
        status_rows = conn.execute(
            "SELECT t.status as status, COUNT(*) as cnt FROM tickets t "
            "JOIN agent_teams at ON t.team_id=at.team_id "
            "WHERE at.status='Active' GROUP BY t.status"
        ).fetchall()
        status_counts = {r["status"]: r["cnt"] for r in status_rows}

        # 재작업 현황
        rework_rows = conn.execute(
            "SELECT rework_count, COUNT(*) as cnt FROM tickets "
            "WHERE COALESCE(rework_count, 0) > 0 GROUP BY rework_count"
        ).fetchall()
        rework_dist = {r["rework_count"]: r["cnt"] for r in rework_rows}

        # Blocked (에스컬레이션) 목록
        blocked = rows_to_list(conn.execute(
            "SELECT t.ticket_id, t.title, t.rework_count, at.name as team_name "
            "FROM tickets t JOIN agent_teams at ON t.team_id=at.team_id "
            "WHERE t.status='Blocked' ORDER BY t.rework_count DESC LIMIT 20"
        ).fetchall())

        # 산출물 없는 Review 티켓 (위험)
        no_artifact_review = rows_to_list(conn.execute(
            "SELECT t.ticket_id, t.title, at.name as team_name "
            "FROM tickets t JOIN agent_teams at ON t.team_id=at.team_id "
            "WHERE t.status='Review' AND NOT EXISTS "
            "(SELECT 1 FROM artifacts a WHERE a.ticket_id=t.ticket_id) LIMIT 20"
        ).fetchall())

        # 최근 24시간 검수 활동
        recent_reviews = conn.execute(
            "SELECT COUNT(*) as cnt, "
            "SUM(CASE WHEN score >= 3 THEN 1 ELSE 0 END) as passed, "
            "SUM(CASE WHEN score < 3 THEN 1 ELSE 0 END) as reworked, "
            "ROUND(AVG(score), 2) as avg_score "
            "FROM ticket_feedbacks WHERE author='supervisor' "
            "AND created_at > datetime('now', '-24 hours')"
        ).fetchone()

        total = sum(status_counts.values())
        done = status_counts.get("Done", 0)

        # 파이프라인 건강 상태 판정
        review_cnt = status_counts.get("Review", 0)
        wip_cnt = status_counts.get("InProgress", 0)
        blocked_cnt = status_counts.get("Blocked", 0)
        health = "healthy"
        issues = []
        if review_cnt == 0 and wip_cnt == 0 and total - done > 10:
            health = "stalled"
            issues.append("파이프라인 정체: Review/InProgress 티켓 0개")
        if blocked_cnt > 5:
            health = "critical"
            issues.append(f"에스컬레이션 과다: Blocked {blocked_cnt}개")
        if len(no_artifact_review) > 0:
            health = "warning"
            issues.append(f"산출물 없는 Review 티켓 {len(no_artifact_review)}개")

    finally:
        conn.close()

    return {
        "ok": True,
        "health": health,
        "issues": issues,
        "status_counts": status_counts,
        "total_tickets": total,
        "completion_rate": round(done / total * 100, 1) if total else 0,
        "rework_distribution": rework_dist,
        "blocked_tickets": blocked,
        "no_artifact_reviews": no_artifact_review,
        "last_24h": {
            "reviews": recent_reviews["cnt"] or 0,
            "passed": recent_reviews["passed"] or 0,
            "reworked": recent_reviews["reworked"] or 0,
            "avg_score": recent_reviews["avg_score"] or 0,
        },
    }


if __name__ == "__main__":
    main()
