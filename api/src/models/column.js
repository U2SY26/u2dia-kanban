/**
 * 컬럼(Column) 모델 — DB CRUD
 */
const { getDb } = require('../db');
const { randomUUID } = require('crypto');

function listColumns(boardId) {
  return getDb()
    .prepare(`SELECT * FROM kb_columns WHERE board_id = ? ORDER BY position ASC`)
    .all(boardId);
}

function getColumnById(id) {
  return getDb()
    .prepare(`SELECT * FROM kb_columns WHERE id = ?`)
    .get(id);
}

function createColumn({ board_id, title, position, wip_limit = null }) {
  const id = randomUUID();
  const now = new Date().toISOString();

  // position 미지정 시 마지막 순서 부여
  if (position === undefined || position === null) {
    const max = getDb()
      .prepare(`SELECT COALESCE(MAX(position), -1) as m FROM kb_columns WHERE board_id = ?`)
      .get(board_id);
    position = max.m + 1;
  }

  getDb()
    .prepare(`
      INSERT INTO kb_columns (id, board_id, title, position, wip_limit, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `)
    .run(id, board_id, title, position, wip_limit, now, now);
  return getColumnById(id);
}

function updateColumn(id, fields) {
  const allowed = ['title', 'position', 'wip_limit'];
  const updates = Object.keys(fields)
    .filter(k => allowed.includes(k))
    .map(k => `${k} = ?`);

  if (!updates.length) return getColumnById(id);

  const values = updates.map(u => fields[u.split(' ')[0]]);
  values.push(new Date().toISOString(), id);

  getDb()
    .prepare(`UPDATE kb_columns SET ${updates.join(', ')}, updated_at = ? WHERE id = ?`)
    .run(...values);
  return getColumnById(id);
}

function deleteColumn(id) {
  return getDb()
    .prepare(`DELETE FROM kb_columns WHERE id = ?`)
    .run(id);
}

/**
 * 컬럼 순서 일괄 변경 (Drag & Drop 지원)
 * @param {Array<{id: string, position: number}>} orders
 */
function reorderColumns(orders) {
  const db = getDb();
  const stmt = db.prepare(`UPDATE kb_columns SET position = ?, updated_at = ? WHERE id = ?`);
  const now = new Date().toISOString();
  const tx = db.transaction(() => {
    for (const { id, position } of orders) {
      stmt.run(position, now, id);
    }
  });
  tx();
}

module.exports = { listColumns, getColumnById, createColumn, updateColumn, deleteColumn, reorderColumns };
