/**
 * 인증 라우트
 *
 * POST /api/auth/register — 회원가입 + 액세스 토큰 발급
 * POST /api/auth/login    — 로그인 + 액세스/리프레시 토큰 발급
 * POST /api/auth/refresh  — 리프레시 토큰으로 액세스 토큰 갱신
 * GET  /api/auth/me       — 현재 사용자 정보 조회 (인증 필요)
 */
const { Router } = require('express');
const { requireFields, validateUserBody } = require('../middleware/validate');
const { createToken, verifyToken, hashPassword, verifyPassword, authenticate } = require('../middleware/auth');
const { strictLimiter } = require('../middleware/rateLimiter');
const { log } = require('../middleware/logger');
const User = require('../models/user');

const router = Router();

// 인증 엔드포인트에는 엄격한 Rate Limit 적용
router.use(strictLimiter);

// ─────────────────────────────────────────────────────────
// POST /api/auth/register
// ─────────────────────────────────────────────────────────
router.post('/register',
  requireFields(['name', 'email', 'password']),
  validateUserBody,
  (req, res, next) => {
    try {
      const { name, email, role = 'member', avatar_url } = req.body;
      let { password } = req.body;

      // 비밀번호 정책 검증
      if (typeof password !== 'string' || password.length < 8 || password.length > 128) {
        return res.status(400).json({
          ok: false, code: 'VALIDATION_ERROR',
          error: '비밀번호는 8~128자여야 합니다',
        });
      }

      // 이메일 중복 확인
      if (User.getUserByEmail(email)) {
        return res.status(409).json({
          ok: false, code: 'CONFLICT',
          error: '이미 사용 중인 이메일입니다',
        });
      }

      const { hash, salt } = hashPassword(password);
      password = undefined; // 메모리에서 평문 제거

      const user = User.createUser({ name, email, role, avatar_url, password_hash: hash, salt });

      const accessToken  = createToken({ sub: user.id, email: user.email, role: user.role }, 'access');
      const refreshToken = createToken({ sub: user.id, role: user.role }, 'refresh');

      log('info', '사용자 등록 완료', { userId: user.id, email: user.email });

      res.status(201).json({
        ok: true,
        data: {
          user,
          accessToken,
          refreshToken,
        },
      });
    } catch (e) { next(e); }
  },
);

// ─────────────────────────────────────────────────────────
// POST /api/auth/login
// ─────────────────────────────────────────────────────────
router.post('/login',
  requireFields(['email', 'password']),
  (req, res, next) => {
    try {
      const { email } = req.body;
      let { password } = req.body;

      if (typeof email !== 'string' || typeof password !== 'string') {
        return res.status(400).json({ ok: false, code: 'VALIDATION_ERROR', error: '이메일과 비밀번호를 입력하세요' });
      }

      const user = User.getUserWithCredentials(email.toLowerCase().trim());

      // 사용자 없음 / 비밀번호 없음 / 비밀번호 불일치 — 동일한 에러 메시지 (열거 공격 방지)
      const GENERIC_ERROR = { ok: false, code: 'INVALID_CREDENTIALS', error: '이메일 또는 비밀번호가 올바르지 않습니다' };

      if (!user || !user.password_hash || !user.salt) {
        // timing attack 방지: 사용자 없어도 해시 연산 수행
        hashPassword(password);
        password = undefined;
        return res.status(401).json(GENERIC_ERROR);
      }

      const valid = verifyPassword(password, user.password_hash, user.salt);
      password = undefined; // 메모리에서 평문 제거

      if (!valid) {
        log('warn', '로그인 실패 (비밀번호 불일치)', { email, ip: req.ip });
        return res.status(401).json(GENERIC_ERROR);
      }

      const accessToken  = createToken({ sub: user.id, email: user.email, role: user.role }, 'access');
      const refreshToken = createToken({ sub: user.id, role: user.role }, 'refresh');

      log('info', '로그인 성공', { userId: user.id, ip: req.ip });

      res.json({
        ok: true,
        data: {
          user: {
            id: user.id, name: user.name, email: user.email,
            role: user.role, avatar_url: user.avatar_url,
          },
          accessToken,
          refreshToken,
        },
      });
    } catch (e) { next(e); }
  },
);

// ─────────────────────────────────────────────────────────
// POST /api/auth/refresh
// ─────────────────────────────────────────────────────────
router.post('/refresh',
  requireFields(['refreshToken']),
  (req, res, next) => {
    try {
      let payload;
      try {
        payload = verifyToken(req.body.refreshToken);
      } catch (err) {
        return res.status(401).json({ ok: false, code: err.code || 'INVALID_TOKEN', error: err.message });
      }

      if (payload.type !== 'refresh') {
        return res.status(401).json({ ok: false, code: 'INVALID_TOKEN', error: '리프레시 토큰이 아닙니다' });
      }

      const user = User.getUserById(payload.sub);
      if (!user) {
        return res.status(401).json({ ok: false, code: 'USER_NOT_FOUND', error: '사용자를 찾을 수 없습니다' });
      }

      const accessToken = createToken({ sub: user.id, email: user.email, role: user.role }, 'access');

      res.json({ ok: true, data: { accessToken } });
    } catch (e) { next(e); }
  },
);

// ─────────────────────────────────────────────────────────
// GET /api/auth/me
// ─────────────────────────────────────────────────────────
router.get('/me', authenticate, (req, res, next) => {
  try {
    const user = User.getUserById(req.user.sub);
    if (!user) {
      return res.status(404).json({ ok: false, code: 'USER_NOT_FOUND', error: '사용자를 찾을 수 없습니다' });
    }
    res.json({ ok: true, data: user });
  } catch (e) { next(e); }
});

module.exports = router;
