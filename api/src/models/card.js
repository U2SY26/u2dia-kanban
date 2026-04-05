/**
 * 카드(Card) 모델 — DB CRUD
 */
const { getDb } = require('../db');
const { randomUUID } = require('crypto');

function listCards(columnId) {
  return getDb()
    .prepare(`SELECT * FROM kb_cards WHERE column_id = ? ORDER BY position ASC`)
    .all(columnId)
    .map(parseCard);
}

function listCardsByBoard(boardId) {
  return getDb()
    .prepare(`SELECT * FROM kb_cards WHERE board_id = ? ORDER BY column_id, position ASC`)
    .all(boardId)
    .map(parseCard);
}

function getCardById(id) {
  const row = getDb()
    .prepare(`SELECT * FROM kb_cards WHERE id = ?`)
    .get(id);
  return row ? parseCard(row) : null;
}

function parseCard(row) {
  return {
    ...row,
    labels: JSON.parse(row.labels || '[]'),
  };
}

function createCard({
  column_id, board_id, title, description = null,
  position, priority = 'medium', assignee_id = null,
  due_date = null, labels = [],
}) {
  const id = randomUUID();
  const now = new Date().toISOString();

  if (position === undefined || position === null) {
    const max = getDb()
      .prepare(`SELECT COALESCE(MAX(position), -1) as m FROM kb_cards WHERE column_id = ?`)
      .get(column_id);
    position = max.m + 1;
  }

  getDb()
    .prepare(`
      INSERT INTO kb_cards
        (id, column_id, board_id, title, description, position, priority,
         assignee_id, due_date, labels, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `)
    .run(
      id, column_id, board_id, title, description, position, priority,
      assignee_id, due_date, JSON.stringify(labels), now, now,
    );
  return getCardById(id);
}

function updateCard(id, fields) {
  const allowed = ['column_id', 'title', 'description', 'position', 'priority',
                   'assignee_id', 'due_date', 'labels'];
  const setClauses = [];
  const values = [];

  for (const k of allowed) {
    if (fields[k] !== undefined) {
      setClauses.push(`${k} = ?`);
      values.push(k === 'labels' ? JSON.stringify(fields[k]) : fields[k]);
    }
  }

  if (!setClauses.length) return getCardById(id);

  values.push(new Date().toISOString(), id);
  getDb()
    .prepare(`UPDATE kb_cards SET ${setClauses.join(', ')}, updated_at = ? WHERE id = ?`)
    .run(...values);
  return getCardById(id);
}

function deleteCard(id) {
  return getDb()
    .prepare(`DELETE FROM kb_cards WHERE id = ?`)
    .run(id);
}

/**
 * 카드 이동 (컬럼 간 이동 + 순서 변경)
 * @param {string} cardId
 * @param {string} targetColumnId
 * @param {number} position
 */
function moveCard(cardId, targetColumnId, position) {
  const db = getDb();
  const now = new Date().toISOString();
  db.prepare(`
    UPDATE kb_cards SET column_id = ?, position = ?, updated_at = ? WHERE id = ?
  `).run(targetColumnId, position, now, cardId);
  return getCardById(cardId);
}

/**
 * 카드 순서 일괄 변경 (Drag & Drop 지원)
 * @param {Array<{id: string, position: number, column_id?: string}>} orders
 */
function reorderCards(orders) {
  const db = getDb();
  const stmt = db.prepare(`
    UPDATE kb_cards SET position = ?, column_id = COALESCE(?, column_id), updated_at = ? WHERE id = ?
  `);
  const now = new Date().toISOString();
  const tx = db.transaction(() => {
    for (const { id, position, column_id = null } of orders) {
      stmt.run(position, column_id, now, id);
    }
  });
  tx();
}

module.exports = {
  listCards, listCardsByBoard, getCardById,
  createCard, updateCard, deleteCard, moveCard, reorderCards,
};
