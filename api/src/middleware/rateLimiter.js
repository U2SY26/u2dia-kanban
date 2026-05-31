/**
 * 인메모리 Rate Limiter 미들웨어
 *
 * 외부 의존성 없이 Map 기반으로 구현.
 * 슬라이딩 윈도우 방식 (고정 윈도우 카운터 변형).
 *
 * 주의: 다중 프로세스/인스턴스 환경에서는 Redis 기반 구현으로 교체 필요.
 */

// ─────────────────────────────────────────────────────────
// 스토어 정리 (메모리 누수 방지)
// ─────────────────────────────────────────────────────────

const store = new Map(); // key → { count, resetAt }

// 만료된 엔트리 주기적 정리 (5분마다)
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of store) {
    if (now > entry.resetAt) store.delete(key);
  }
}, 5 * 60 * 1000).unref(); // unref: 이 타이머가 프로세스 종료를 막지 않도록

// ─────────────────────────────────────────────────────────
// 팩토리
// ─────────────────────────────────────────────────────────

/**
 * Rate Limiter 미들웨어 생성
 *
 * @param {object} options
 * @param {number} options.windowMs   — 윈도우 길이(ms), 기본 60_000 (1분)
 * @param {number} options.max        — 윈도우 당 최대 요청 수, 기본 100
 * @param {string} options.message    — 초과 시 오류 메시지
 * @param {function} [options.keyFn] — 요청별 키 생성 함수 (기본: IP)
 */
function createRateLimiter({
  windowMs = 60_000,
  max      = 100,
  message  = '요청 횟수 제한을 초과했습니다. 잠시 후 다시 시도하세요',
  keyFn    = (req) => req.ip || req.socket?.remoteAddress || 'unknown',
} = {}) {
  return (req, res, next) => {
    const key = keyFn(req);
    const now = Date.now();

    let entry = store.get(key);

    if (!entry || now > entry.resetAt) {
      entry = { count: 1, resetAt: now + windowMs };
      store.set(key, entry);
    } else {
      entry.count++;
    }

    const remaining = Math.max(0, max - entry.count);
    const retryAfterSec = Math.ceil((entry.resetAt - now) / 1000);

    // 표준 Rate-Limit 응답 헤더 (RFC 6585 / draft-ietf-httpapi-ratelimit-headers)
    res.setHeader('X-RateLimit-Limit',     max);
    res.setHeader('X-RateLimit-Remaining', remaining);
    res.setHeader('X-RateLimit-Reset',     Math.ceil(entry.resetAt / 1000));

    if (entry.count > max) {
      res.setHeader('Retry-After', retryAfterSec);
      return res.status(429).json({
        ok:    false,
        code:  'RATE_LIMIT_EXCEEDED',
        error: message,
        retryAfter: retryAfterSec,
      });
    }

    next();
  };
}

// 사전 정의된 프리셋
const defaultLimiter  = createRateLimiter({ windowMs: 60_000, max: 200 });
const strictLimiter   = createRateLimiter({ windowMs: 60_000, max: 20 });   // 인증 엔드포인트용
const writeLimiter    = createRateLimiter({ windowMs: 60_000, max: 60 });   // 쓰기 작업용

module.exports = { createRateLimiter, defaultLimiter, strictLimiter, writeLimiter };
