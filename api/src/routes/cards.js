/**
 * 카드 라우트
 *
 * 관계:
 *   Column (1) ── Card (N)  [column_id FK → kb_columns.id]
 *   Board  (1) ── Card (N)  [board_id  FK → kb_boards.id]
 *   User   (1) ── Card (N)  [assignee_id FK → kb_users.id, nullable]
 *
 * GET    /api/columns/:columnId/cards            — 컬럼의 카드 목록 (position ASC)
 * POST   /api/columns/:columnId/cards            — 카드 생성 (board_id는 컬럼에서 자동 추출)
 * PUT    /api/columns/:columnId/cards/reorder    — 순서 일괄 변경
 * GET    /api/boards/:boardId/cards              — 보드의 전체 카드
 * GET    /api/cards/:id                          — 단건 조회
 * PUT    /api/cards/:id                          — 수정
 * DELETE /api/cards/:id                          — 삭제
 * PUT    /api/cards/:id/move                     — 컬럼 간 이동
 */
const { Router } = require('express');
const {
  requireFields,
  validateIdParam,
  validateCardBody,
  validateReorderBody,
} = require('../middleware/validate');
const Card   = require('../models/card');
const Column = require('../models/column');
const User   = require('../models/user');

// ── 컬럼 하위 라우트 (/api/columns/:columnId/cards) ──
const columnCardRouter = Router({ mergeParams: true });

// GET /api/columns/:columnId/cards
columnCardRouter.get('/', validateIdParam, (req, res, next) => {
  try {
    res.json({ ok: true, data: Card.listCards(req.params.columnId) });
  } catch (e) { next(e); }
});

// POST /api/columns/:columnId/cards
columnCardRouter.post(
  '/',
  validateIdParam,
  requireFields(['title']),
  validateCardBody,
  (req, res, next) => {
    try {
      // 관계 검증: 컬럼 존재 확인
      const col = Column.getColumnById(req.params.columnId);
      if (!col) return res.status(404).json({ ok: false, error: '컬럼을 찾을 수 없습니다' });

      const { title, description, position, priority, assignee_id, due_date, labels } = req.body;

      // 관계 검증: 담당자(assignee) 존재 확인
      if (assignee_id) {
        const assignee = User.getUserById(assignee_id);
        if (!assignee) {
          return res.status(404).json({ ok: false, error: '담당자(assignee_id)를 찾을 수 없습니다' });
        }
      }

      const card = Card.createCard({
        column_id:   req.params.columnId,
        board_id:    col.board_id,   // 컬럼에서 board_id 자동 추출
        title,
        description,
        position,
        priority,
        assignee_id,
        due_date,
        labels: Array.isArray(labels) ? labels : [],
      });
      res.status(201).json({ ok: true, data: card });
    } catch (e) { next(e); }
  },
);

// PUT /api/columns/:columnId/cards/reorder
columnCardRouter.put('/reorder', validateIdParam, validateReorderBody, (req, res, next) => {
  try {
    Card.reorderCards(req.body.orders);
    res.json({ ok: true, data: Card.listCards(req.params.columnId) });
  } catch (e) { next(e); }
});

// ── 보드 하위 라우트 (/api/boards/:boardId/cards) ──
const boardCardRouter = Router({ mergeParams: true });

// GET /api/boards/:boardId/cards
boardCardRouter.get('/', validateIdParam, (req, res, next) => {
  try {
    res.json({ ok: true, data: Card.listCardsByBoard(req.params.boardId) });
  } catch (e) { next(e); }
});

// ── 단건 라우트 (/api/cards/:id) ──
const itemRouter = Router();

// GET /api/cards/:id
itemRouter.get('/:id', validateIdParam, (req, res, next) => {
  try {
    const card = Card.getCardById(req.params.id);
    if (!card) return res.status(404).json({ ok: false, error: '카드를 찾을 수 없습니다' });
    res.json({ ok: true, data: card });
  } catch (e) { next(e); }
});

// PUT /api/cards/:id
itemRouter.put('/:id', validateIdParam, validateCardBody, (req, res, next) => {
  try {
    const card = Card.getCardById(req.params.id);
    if (!card) return res.status(404).json({ ok: false, error: '카드를 찾을 수 없습니다' });

    // 관계 검증: column_id 변경 시 컬럼 존재 확인
    if (req.body.column_id) {
      const col = Column.getColumnById(req.body.column_id);
      if (!col) return res.status(404).json({ ok: false, error: '대상 컬럼을 찾을 수 없습니다' });
    }

    // 관계 검증: assignee_id 변경 시 사용자 존재 확인
    if (req.body.assignee_id) {
      const assignee = User.getUserById(req.body.assignee_id);
      if (!assignee) {
        return res.status(404).json({ ok: false, error: '담당자(assignee_id)를 찾을 수 없습니다' });
      }
    }

    const fields = {};
    const allowed = ['title', 'description', 'column_id', 'position', 'priority',
                     'assignee_id', 'due_date', 'labels'];
    for (const k of allowed) {
      if (req.body[k] !== undefined) fields[k] = req.body[k];
    }
    const updated = Card.updateCard(req.params.id, fields);
    res.json({ ok: true, data: updated });
  } catch (e) { next(e); }
});

// DELETE /api/cards/:id
itemRouter.delete('/:id', validateIdParam, (req, res, next) => {
  try {
    const card = Card.getCardById(req.params.id);
    if (!card) return res.status(404).json({ ok: false, error: '카드를 찾을 수 없습니다' });
    Card.deleteCard(req.params.id);
    res.json({ ok: true, message: '카드가 삭제되었습니다' });
  } catch (e) { next(e); }
});

// PUT /api/cards/:id/move
itemRouter.put(
  '/:id/move',
  validateIdParam,
  requireFields(['column_id', 'position']),
  (req, res, next) => {
    try {
      const card = Card.getCardById(req.params.id);
      if (!card) return res.status(404).json({ ok: false, error: '카드를 찾을 수 없습니다' });

      const { column_id, position } = req.body;

      // 관계 검증: 대상 컬럼 존재 확인
      const target = Column.getColumnById(column_id);
      if (!target) {
        return res.status(404).json({ ok: false, error: '대상 컬럼을 찾을 수 없습니다' });
      }

      const pos = Number(position);
      if (!Number.isInteger(pos) || pos < 0) {
        return res.status(400).json({ ok: false, error: 'position은 0 이상의 정수여야 합니다' });
      }

      const moved = Card.moveCard(req.params.id, column_id, pos);
      res.json({ ok: true, data: moved });
    } catch (e) { next(e); }
  },
);

module.exports = { columnCardRouter, boardCardRouter, itemRouter };
