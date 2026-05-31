/**
 * 구조적 로깅 미들웨어
 *
 * 외부 의존성 없이 Node.js console만 사용.
 * JSON Lines 형식으로 출력 — 운영 환경에서 로그 수집기와 호환.
 *
 * 환경 변수:
 *   LOG_LEVEL  — 'debug'|'info'|'warn'|'error', 기본 'info'
 *   LOG_FORMAT — 'json'|'pretty', 기본 운영=json, 개발=pretty
 */

const LEVELS = { debug: 0, info: 1, warn: 2, error: 3 };

const LOG_LEVEL  = process.env.LOG_LEVEL || 'info';
const LOG_FORMAT = process.env.LOG_FORMAT
  || (process.env.NODE_ENV === 'production' ? 'json' : 'pretty');

const currentLevel = LEVELS[LOG_LEVEL] ?? LEVELS.info;

// ─────────────────────────────────────────────────────────
// 핵심 로그 함수
// ─────────────────────────────────────────────────────────

/**
 * 구조적 로그 출력
 * @param {'debug'|'info'|'warn'|'error'} level
 * @param {string} message
 * @param {object} [meta]
 */
function log(level, message, meta = {}) {
  if ((LEVELS[level] ?? 0) < currentLevel) return;

  const entry = {
    ts:  new Date().toISOString(),
    lvl: level.toUpperCase(),
    msg: message,
    ...meta,
  };

  const output = LOG_FORMAT === 'json'
    ? JSON.stringify(entry)
    : formatPretty(entry);

  if (level === 'error') {
    process.stderr.write(output + '\n');
  } else {
    process.stdout.write(output + '\n');
  }
}

function formatPretty({ ts, lvl, msg, ...meta }) {
  const COLORS = { DEBUG: '\x1b[36m', INFO: '\x1b[32m', WARN: '\x1b[33m', ERROR: '\x1b[31m' };
  const RESET  = '\x1b[0m';
  const color  = COLORS[lvl] || '';
  const time   = ts.slice(11, 23); // HH:MM:SS.mmm

  const metaStr = Object.keys(meta).length
    ? ' ' + JSON.stringify(meta)
    : '';

  return `${color}[${lvl.padEnd(5)}]${RESET} ${time} ${msg}${metaStr}`;
}

// ─────────────────────────────────────────────────────────
// Express 요청/응답 로깅 미들웨어
// ─────────────────────────────────────────────────────────

/**
 * HTTP 요청·응답 로깅 미들웨어
 * 응답 완료 시 status, duration, content-length 포함
 */
function requestLogger(req, res, next) {
  const startAt = process.hrtime.bigint();
  const { method, originalUrl, ip } = req;

  // 응답 완료 훅
  res.on('finish', () => {
    const durationMs = Number(process.hrtime.bigint() - startAt) / 1_000_000;
    const { statusCode } = res;
    const contentLength = res.getHeader('content-length') || '-';

    const level = statusCode >= 500 ? 'error'
      : statusCode >= 400 ? 'warn'
      : 'info';

    log(level, `${method} ${originalUrl}`, {
      status: statusCode,
      ms: Math.round(durationMs * 100) / 100,
      bytes: contentLength,
      ip: ip || req.socket?.remoteAddress,
      uid: req.user?.sub,
    });
  });

  next();
}

/**
 * 에러 로깅 미들웨어 (Express 에러 핸들러 앞에 삽입 불필요 — errorHandler 내부에서 사용)
 * @param {Error} err
 * @param {object} req
 */
function logError(err, req) {
  log('error', err.message || 'Internal Server Error', {
    code:   err.code,
    status: err.status || 500,
    path:   req?.path,
    method: req?.method,
    uid:    req?.user?.sub,
    stack:  process.env.NODE_ENV !== 'production' ? err.stack : undefined,
  });
}

module.exports = { log, requestLogger, logError };
