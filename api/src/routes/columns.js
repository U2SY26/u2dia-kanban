/**
 * 컬럼 라우트
 *
 * 관계:
 *   Board (1) ─── Column (N)   [board_id FK → kb_boards.id]
 *   Column (1) ── Card (N)     [column_id FK → kb_columns.id]
 *
 * GET    /api/boards/:boardId/columns         — 보드의 컬럼 목록 (position ASC)
 * POST   /api/boards/:boardId/columns         — 컬럼 생성
 * PUT    /api/boards/:boardId/columns/reorder — 순서 일괄 변경 (Drag & Drop)
 * GET    /api/columns/:id                     — 단건 조회
 * PUT    /api/columns/:id                     — 수정
 * DELETE /api/columns/:id                     — 삭제 (소속 카드 CASCADE 삭제)
 */
const { Router } = require('express');
const {
  requireFields,
  validateIdParam,
  validateColumnBody,
  validateReorderBody,
} = require('../middleware/validate');
const Column = require('../models/column');

const router = Router({ mergeParams: true });

// GET /api/boards/:boardId/columns
router.get('/', validateIdParam, (req, res, next) => {
  try {
    const columns = Column.listColumns(req.params.boardId);
    res.json({ ok: true, data: columns });
  } catch (e) { next(e); }
});

// POST /api/boards/:boardId/columns
router.post('/', validateIdParam, requireFields(['title']), validateColumnBody, (req, res, next) => {
  try {
    const { title, position, wip_limit } = req.body;
    const column = Column.createColumn({
      board_id: req.params.boardId,
      title,
      position,
      wip_limit: wip_limit != null ? Number(wip_limit) : null,
    });
    res.status(201).json({ ok: true, data: column });
  } catch (e) { next(e); }
});

// PUT /api/boards/:boardId/columns/reorder  (반드시 /:id 앞에 등록)
router.put('/reorder', validateIdParam, validateReorderBody, (req, res, next) => {
  try {
    Column.reorderColumns(req.body.orders);
    res.json({ ok: true, data: Column.listColumns(req.params.boardId) });
  } catch (e) { next(e); }
});

module.exports = router;

// ── 단건 라우트 (boardId 없이 /api/columns/:id) ──

const itemRouter = Router();

// GET /api/columns/:id
itemRouter.get('/:id', validateIdParam, (req, res, next) => {
  try {
    const col = Column.getColumnById(req.params.id);
    if (!col) return res.status(404).json({ ok: false, error: '컬럼을 찾을 수 없습니다' });
    res.json({ ok: true, data: col });
  } catch (e) { next(e); }
});

// PUT /api/columns/:id
itemRouter.put('/:id', validateIdParam, validateColumnBody, (req, res, next) => {
  try {
    const col = Column.getColumnById(req.params.id);
    if (!col) return res.status(404).json({ ok: false, error: '컬럼을 찾을 수 없습니다' });

    const fields = {};
    if (req.body.title    !== undefined) fields.title    = req.body.title;
    if (req.body.position !== undefined) fields.position = req.body.position;
    if (req.body.wip_limit !== undefined) fields.wip_limit = req.body.wip_limit;

    const updated = Column.updateColumn(req.params.id, fields);
    res.json({ ok: true, data: updated });
  } catch (e) { next(e); }
});

// DELETE /api/columns/:id
itemRouter.delete('/:id', validateIdParam, (req, res, next) => {
  try {
    const col = Column.getColumnById(req.params.id);
    if (!col) return res.status(404).json({ ok: false, error: '컬럼을 찾을 수 없습니다' });
    Column.deleteColumn(req.params.id);
    res.json({ ok: true, message: '컬럼이 삭제되었습니다' });
  } catch (e) { next(e); }
});

module.exports.itemRouter = itemRouter;
