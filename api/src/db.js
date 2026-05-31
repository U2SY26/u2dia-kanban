/**
 * SQLite 데이터베이스 연결 (better-sqlite3)
 * 기존 agent_teams.db와 호환, WAL 모드
 */
const Database = require('better-sqlite3');
const path = require('path');

const DB_PATH = process.env.KANBAN_DB_PATH
  || path.join(__dirname, '../../agent_teams.db');

let _db = null;

function getDb() {
  if (!_db) {
    _db = new Database(DB_PATH);
    _db.pragma('journal_mode = WAL');
    _db.pragma('busy_timeout = 10000');
    _db.pragma('foreign_keys = ON');
    initSchema(_db);
  }
  return _db;
}

function initSchema(db) {
  db.exec(`
    -- 사용자 테이블
    CREATE TABLE IF NOT EXISTS kb_users (
      id            TEXT PRIMARY KEY,
      name          TEXT NOT NULL,
      email         TEXT UNIQUE,
      role          TEXT DEFAULT 'member',
      avatar_url    TEXT,
      password_hash TEXT,
      salt          TEXT,
      created_at    TEXT DEFAULT (datetime('now','utc')),
      updated_at    TEXT DEFAULT (datetime('now','utc'))
    );

    -- 보드 테이블
    CREATE TABLE IF NOT EXISTS kb_boards (
      id         TEXT PRIMARY KEY,
      title      TEXT NOT NULL,
      owner_id   TEXT REFERENCES kb_users(id) ON DELETE SET NULL,
      created_at TEXT DEFAULT (datetime('now','utc')),
      updated_at TEXT DEFAULT (datetime('now','utc'))
    );

    -- 컬럼 테이블
    CREATE TABLE IF NOT EXISTS kb_columns (
      id         TEXT PRIMARY KEY,
      board_id   TEXT NOT NULL REFERENCES kb_boards(id) ON DELETE CASCADE,
      title      TEXT NOT NULL,
      position   INTEGER NOT NULL DEFAULT 0,
      wip_limit  INTEGER,
      created_at TEXT DEFAULT (datetime('now','utc')),
      updated_at TEXT DEFAULT (datetime('now','utc'))
    );

    -- 카드 테이블
    CREATE TABLE IF NOT EXISTS kb_cards (
      id          TEXT PRIMARY KEY,
      column_id   TEXT NOT NULL REFERENCES kb_columns(id) ON DELETE CASCADE,
      board_id    TEXT NOT NULL REFERENCES kb_boards(id) ON DELETE CASCADE,
      title       TEXT NOT NULL,
      description TEXT,
      position    INTEGER NOT NULL DEFAULT 0,
      priority    TEXT DEFAULT 'medium' CHECK(priority IN ('low','medium','high','urgent')),
      assignee_id TEXT REFERENCES kb_users(id) ON DELETE SET NULL,
      due_date    TEXT,
      labels      TEXT DEFAULT '[]',
      created_at  TEXT DEFAULT (datetime('now','utc')),
      updated_at  TEXT DEFAULT (datetime('now','utc'))
    );

    -- 인덱스
    CREATE INDEX IF NOT EXISTS idx_columns_board ON kb_columns(board_id, position);
    CREATE INDEX IF NOT EXISTS idx_cards_column  ON kb_cards(column_id, position);
    CREATE INDEX IF NOT EXISTS idx_cards_board   ON kb_cards(board_id);
    CREATE INDEX IF NOT EXISTS idx_cards_assignee ON kb_cards(assignee_id);
  `);

  // 기존 DB 마이그레이션: password_hash, salt 컬럼 추가 (없는 경우)
  const columns = db.prepare(`PRAGMA table_info(kb_users)`).all().map(c => c.name);
  if (!columns.includes('password_hash')) {
    db.exec(`ALTER TABLE kb_users ADD COLUMN password_hash TEXT`);
  }
  if (!columns.includes('salt')) {
    db.exec(`ALTER TABLE kb_users ADD COLUMN salt TEXT`);
  }
}

module.exports = { getDb };
