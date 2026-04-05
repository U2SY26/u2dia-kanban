/**
 * 사용자(User) 모델 — DB CRUD
 *
 * 인증 관련:
 *   - password_hash, salt 컬럼은 listUsers/getUserById 조회에서 제외 (보안)
 *   - getUserWithCredentials 만 password_hash, salt 포함 반환
 */
const { getDb } = require('../db');
const { randomUUID } = require('crypto');

// SELECT 기본 컬럼 (비밀번호 필드 제외)
const PUBLIC_COLS = 'id, name, email, role, avatar_url, created_at, updated_at';

function listUsers() {
  return getDb()
    .prepare(`SELECT ${PUBLIC_COLS} FROM kb_users ORDER BY created_at DESC`)
    .all();
}

function getUserById(id) {
  return getDb()
    .prepare(`SELECT ${PUBLIC_COLS} FROM kb_users WHERE id = ?`)
    .get(id);
}

function getUserByEmail(email) {
  return getDb()
    .prepare(`SELECT ${PUBLIC_COLS} FROM kb_users WHERE email = ?`)
    .get(email);
}

/** 인증용: password_hash + salt 포함 반환 (auth 라우트에서만 사용) */
function getUserWithCredentials(email) {
  return getDb()
    .prepare(`SELECT * FROM kb_users WHERE email = ?`)
    .get(email);
}

function createUser({ name, email, role = 'member', avatar_url = null, password_hash = null, salt = null }) {
  const id = randomUUID();
  const now = new Date().toISOString();
  getDb()
    .prepare(`
      INSERT INTO kb_users (id, name, email, role, avatar_url, password_hash, salt, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `)
    .run(id, name, email || null, role, avatar_url, password_hash, salt, now, now);
  return getUserById(id);
}

function updateUser(id, fields) {
  const allowed = ['name', 'email', 'role', 'avatar_url'];
  const updates = Object.keys(fields)
    .filter(k => allowed.includes(k))
    .map(k => `${k} = ?`);

  if (!updates.length) return getUserById(id);

  const values = updates.map(u => fields[u.split(' ')[0]]);
  values.push(new Date().toISOString(), id);

  getDb()
    .prepare(`UPDATE kb_users SET ${updates.join(', ')}, updated_at = ? WHERE id = ?`)
    .run(...values);
  return getUserById(id);
}

function setPassword(id, password_hash, salt) {
  const now = new Date().toISOString();
  getDb()
    .prepare(`UPDATE kb_users SET password_hash = ?, salt = ?, updated_at = ? WHERE id = ?`)
    .run(password_hash, salt, now, id);
}

function deleteUser(id) {
  return getDb()
    .prepare(`DELETE FROM kb_users WHERE id = ?`)
    .run(id);
}

module.exports = {
  listUsers,
  getUserById,
  getUserByEmail,
  getUserWithCredentials,
  createUser,
  updateUser,
  setPassword,
  deleteUser,
};
