/**
 * 사용자 라우트
 *
 * 관계:
 *   User (1) ─── Board.owner_id (N)  [보드 소유자]
 *   User (1) ─── Card.assignee_id (N) [카드 담당자]
 *
 * GET    /api/users          — 전체 목록
 * GET    /api/users/:id      — 단건 조회
 * POST   /api/users          — 생성
 * PUT    /api/users/:id      — 수정
 * DELETE /api/users/:id      — 삭제
 */
const { Router } = require('express');
const { requireFields, validateIdParam, validateUserBody } = require('../middleware/validate');
const User = require('../models/user');

const router = Router();

// GET /api/users
router.get('/', (req, res, next) => {
  try {
    res.json({ ok: true, data: User.listUsers() });
  } catch (e) { next(e); }
});

// GET /api/users/:id
router.get('/:id', validateIdParam, (req, res, next) => {
  try {
    const user = User.getUserById(req.params.id);
    if (!user) return res.status(404).json({ ok: false, error: '사용자를 찾을 수 없습니다' });
    res.json({ ok: true, data: user });
  } catch (e) { next(e); }
});

// POST /api/users
router.post('/', requireFields(['name']), validateUserBody, (req, res, next) => {
  try {
    const { name, email, role, avatar_url } = req.body;

    if (email && User.getUserByEmail(email)) {
      return res.status(409).json({ ok: false, error: '이미 사용 중인 이메일입니다' });
    }

    const user = User.createUser({ name, email, role, avatar_url });
    res.status(201).json({ ok: true, data: user });
  } catch (e) { next(e); }
});

// PUT /api/users/:id
router.put('/:id', validateIdParam, validateUserBody, (req, res, next) => {
  try {
    const user = User.getUserById(req.params.id);
    if (!user) return res.status(404).json({ ok: false, error: '사용자를 찾을 수 없습니다' });

    // 이메일 변경 시 중복 확인
    if (req.body.email && req.body.email !== user.email) {
      const existing = User.getUserByEmail(req.body.email);
      if (existing && existing.id !== req.params.id) {
        return res.status(409).json({ ok: false, error: '이미 사용 중인 이메일입니다' });
      }
    }

    const { name, email, role, avatar_url } = req.body;
    const updated = User.updateUser(req.params.id, { name, email, role, avatar_url });
    res.json({ ok: true, data: updated });
  } catch (e) { next(e); }
});

// DELETE /api/users/:id
router.delete('/:id', validateIdParam, (req, res, next) => {
  try {
    const user = User.getUserById(req.params.id);
    if (!user) return res.status(404).json({ ok: false, error: '사용자를 찾을 수 없습니다' });
    User.deleteUser(req.params.id);
    res.json({ ok: true, message: '사용자가 삭제되었습니다' });
  } catch (e) { next(e); }
});

module.exports = router;
