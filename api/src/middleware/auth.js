/**
 * JWT 인증/인가 미들웨어
 *
 * 외부 의존성 없이 Node.js 내장 `crypto` 모듈로 HS256 JWT 구현.
 *
 * 환경 변수:
 *   JWT_SECRET        — HMAC 서명 비밀키 (필수: 운영 환경에서 반드시 변경)
 *   JWT_EXPIRES_IN    — 액세스 토큰 유효 시간(초), 기본 86400 (24h)
 *   JWT_REFRESH_EXPIRES_IN — 리프레시 토큰 유효 시간(초), 기본 2592000 (30d)
 *   AUTH_REQUIRED     — 'true'이면 모든 쓰기 라우트에 인증 강제
 */
const crypto = require('crypto');
const { log } = require('./logger');

const SECRET         = process.env.JWT_SECRET || 'CHANGE_ME_IN_PRODUCTION_!@#';
const EXPIRES_IN     = parseInt(process.env.JWT_EXPIRES_IN || '86400', 10);
const REFRESH_EXPIRES = parseInt(process.env.JWT_REFRESH_EXPIRES_IN || '2592000', 10);

if (SECRET === 'CHANGE_ME_IN_PRODUCTION_!@#') {
  log('warn', 'JWT_SECRET이 기본값입니다 — 운영 환경에서는 반드시 변경하세요');
}

// ─────────────────────────────────────────────────────────
// Base64URL 유틸리티
// ─────────────────────────────────────────────────────────

function b64urlEncode(buf) {
  return (Buffer.isBuffer(buf) ? buf : Buffer.from(buf))
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function b64urlDecode(str) {
  // base64url → base64 패딩 복원
  const padded = str.replace(/-/g, '+').replace(/_/g, '/');
  const pad = padded.length % 4;
  return Buffer.from(pad ? padded + '='.repeat(4 - pad) : padded, 'base64');
}

// ─────────────────────────────────────────────────────────
// 토큰 생성 / 검증
// ─────────────────────────────────────────────────────────

/**
 * JWT 생성 (HS256)
 * @param {object} payload — 토큰에 담을 클레임 (sub, role, email 등)
 * @param {'access'|'refresh'} type
 * @returns {string} JWT 문자열
 */
function createToken(payload, type = 'access') {
  const exp = type === 'refresh' ? REFRESH_EXPIRES : EXPIRES_IN;
  const now = Math.floor(Date.now() / 1000);

  const header = b64urlEncode(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body   = b64urlEncode(JSON.stringify({
    ...payload,
    type,
    iat: now,
    exp: now + exp,
  }));

  const sig = b64urlEncode(
    crypto.createHmac('sha256', SECRET).update(`${header}.${body}`).digest(),
  );

  return `${header}.${body}.${sig}`;
}

/**
 * JWT 검증
 * @param {string} token
 * @returns {object} 검증된 payload
 * @throws {Error} 검증 실패 시 code 속성 포함
 */
function verifyToken(token) {
  const parts = token.split('.');
  if (parts.length !== 3) {
    throw Object.assign(new Error('토큰 형식이 올바르지 않습니다'), { code: 'INVALID_TOKEN', status: 401 });
  }

  const [header, body, sig] = parts;

  // 서명 검증 (timing-safe)
  const expectedSig = b64urlEncode(
    crypto.createHmac('sha256', SECRET).update(`${header}.${body}`).digest(),
  );

  if (sig.length !== expectedSig.length ||
      !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expectedSig))) {
    throw Object.assign(new Error('토큰 서명이 유효하지 않습니다'), { code: 'INVALID_SIGNATURE', status: 401 });
  }

  let payload;
  try {
    payload = JSON.parse(b64urlDecode(body).toString('utf8'));
  } catch {
    throw Object.assign(new Error('토큰 페이로드 파싱 실패'), { code: 'INVALID_PAYLOAD', status: 401 });
  }

  const now = Math.floor(Date.now() / 1000);
  if (payload.exp < now) {
    throw Object.assign(new Error('토큰이 만료되었습니다'), { code: 'TOKEN_EXPIRED', status: 401 });
  }

  return payload;
}

// ─────────────────────────────────────────────────────────
// 비밀번호 해시 (PBKDF2-SHA256)
// ─────────────────────────────────────────────────────────

const PBKDF2_ITERATIONS = 310_000; // NIST 2024 권장값
const PBKDF2_KEYLEN     = 32;
const PBKDF2_DIGEST     = 'sha256';

/**
 * 비밀번호 해시 생성
 * @returns {{ hash: string, salt: string }}
 */
function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(
    password, salt, PBKDF2_ITERATIONS, PBKDF2_KEYLEN, PBKDF2_DIGEST,
  ).toString('hex');
  return { hash, salt };
}

/**
 * 비밀번호 검증 (timing-safe)
 * @param {string} password — 입력된 평문 비밀번호
 * @param {string} storedHash — DB에 저장된 hash
 * @param {string} storedSalt — DB에 저장된 salt
 * @returns {boolean}
 */
function verifyPassword(password, storedHash, storedSalt) {
  const hash = crypto.pbkdf2Sync(
    password, storedSalt, PBKDF2_ITERATIONS, PBKDF2_KEYLEN, PBKDF2_DIGEST,
  ).toString('hex');
  return crypto.timingSafeEqual(Buffer.from(hash), Buffer.from(storedHash));
}

// ─────────────────────────────────────────────────────────
// Express 미들웨어
// ─────────────────────────────────────────────────────────

/**
 * 인증 미들웨어 — Authorization: Bearer <token> 검증
 * 검증 성공 시 req.user에 페이로드 주입
 */
function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      error: '인증이 필요합니다. Authorization: Bearer <token> 헤더를 포함하세요',
    });
  }

  const token = authHeader.slice(7).trim();
  try {
    req.user = verifyToken(token);
    next();
  } catch (err) {
    log('warn', '토큰 검증 실패', { code: err.code, path: req.path, ip: req.ip });
    return res.status(err.status || 401).json({
      ok: false,
      code: err.code || 'INVALID_TOKEN',
      error: err.message,
    });
  }
}

/**
 * 선택적 인증 미들웨어 — 토큰이 있으면 검증, 없어도 통과
 */
function optionalAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.slice(7).trim();
    try {
      req.user = verifyToken(token);
    } catch {
      // 선택적: 실패해도 통과
    }
  }
  next();
}

/**
 * 인가 미들웨어 — 특정 역할 이상만 허용
 * authenticate 미들웨어 이후에 사용
 *
 * @param {...string} roles — 허용할 역할 목록 ('admin', 'member', 'viewer')
 */
function authorize(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ ok: false, code: 'UNAUTHORIZED', error: '인증이 필요합니다' });
    }
    if (roles.length && !roles.includes(req.user.role)) {
      log('warn', '권한 부족', {
        userId: req.user.sub,
        userRole: req.user.role,
        requiredRoles: roles,
        path: req.path,
      });
      return res.status(403).json({
        ok: false,
        code: 'FORBIDDEN',
        error: `이 작업에는 ${roles.join(' 또는 ')} 역할이 필요합니다`,
      });
    }
    next();
  };
}

module.exports = {
  createToken,
  verifyToken,
  hashPassword,
  verifyPassword,
  authenticate,
  optionalAuth,
  authorize,
};
