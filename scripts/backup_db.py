#!/usr/bin/env python3
"""
U2DIA AI SERVER AGENT — DB 2시간 주기 백업 스크립트
원본: %APPDATA%/u2dia-server-manager/agent_teams.db
백업: E:/agents_team_backup/
SQLite online backup API 사용 (WAL 모드에서도 안전)
"""
import os
import sys
import time
import sqlite3
import shutil
from datetime import datetime

# ── 설정 ──
DB_SOURCE = os.path.join(os.environ.get("APPDATA", ""), "u2dia-server-manager", "agent_teams.db")
BACKUP_DIR = r"E:\agents_team_backup"
BACKUP_INTERVAL_SEC = 2 * 3600  # 2시간
MAX_BACKUPS = 72  # 최대 72개 보관 (6일분)

def ensure_dir(path):
    os.makedirs(path, exist_ok=True)

def backup_sqlite(src, dst):
    """SQLite online backup API로 안전하게 백업 (서버 실행 중에도 OK)"""
    src_conn = sqlite3.connect(src)
    dst_conn = sqlite3.connect(dst)
    try:
        src_conn.backup(dst_conn)
        dst_conn.close()
        src_conn.close()
        return True
    except Exception as e:
        dst_conn.close()
        src_conn.close()
        print(f"[ERROR] SQLite backup failed: {e}")
        return False

def cleanup_old_backups(backup_dir, max_count):
    """오래된 백업 정리 — 최신 max_count개만 유지"""
    files = sorted(
        [f for f in os.listdir(backup_dir) if f.startswith("agent_teams_") and f.endswith(".db")],
        reverse=True
    )
    for old in files[max_count:]:
        try:
            os.remove(os.path.join(backup_dir, old))
            print(f"[CLEANUP] 삭제: {old}")
        except Exception as e:
            print(f"[WARN] 삭제 실패: {old} — {e}")

def do_backup():
    """한 번 백업 실행"""
    if not os.path.exists(DB_SOURCE):
        print(f"[ERROR] DB 파일 없음: {DB_SOURCE}")
        return False

    ensure_dir(BACKUP_DIR)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = os.path.join(BACKUP_DIR, f"agent_teams_{ts}.db")
    latest_link = os.path.join(BACKUP_DIR, "agent_teams_latest.db")

    src_size = os.path.getsize(DB_SOURCE)
    print(f"[BACKUP] {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  원본: {DB_SOURCE} ({src_size / 1024:.1f} KB)")

    if backup_sqlite(DB_SOURCE, backup_file):
        dst_size = os.path.getsize(backup_file)
        print(f"  백업: {backup_file} ({dst_size / 1024:.1f} KB)")

        # latest 심볼릭 링크 (또는 복사)
        try:
            if os.path.exists(latest_link):
                os.remove(latest_link)
            shutil.copy2(backup_file, latest_link)
        except Exception:
            pass

        cleanup_old_backups(BACKUP_DIR, MAX_BACKUPS)
        print(f"  ✓ 완료")
        return True
    return False

def main():
    print("=" * 50)
    print("U2DIA DB Backup Service")
    print(f"  원본: {DB_SOURCE}")
    print(f"  백업: {BACKUP_DIR}")
    print(f"  주기: {BACKUP_INTERVAL_SEC // 3600}시간")
    print(f"  보관: 최대 {MAX_BACKUPS}개")
    print("=" * 50)

    # 즉시 1회 백업
    do_backup()

    if "--once" in sys.argv:
        print("[INFO] --once 모드: 1회 백업 후 종료")
        return

    # 2시간 주기 반복
    print(f"\n[INFO] {BACKUP_INTERVAL_SEC // 3600}시간 주기 백업 시작...")
    while True:
        time.sleep(BACKUP_INTERVAL_SEC)
        do_backup()

if __name__ == "__main__":
    main()
