/**
 * 공통 에러 핸들러 미들웨어
 *
 * 에러 분류:
 *   4xx — 클라이언트 오류 (검증 실패, 인증 오류, 리소스 없음 등)
 *   5xx — 서버 오류 (DB 오류, 예기치 않은 예외 등)
 *
 * err 객체 관례:
 *   err.status  — HTTP 상태 코드 (없으면 500)
 *   err.code    — 에러 코드 문자열 (e.g. 'VALIDATION_ERROR', 'NOT_FOUND')
 *   err.message — 사람이 읽을 수 있는 메시지
 */
const { logError } = require('./logger');

// SQLite/better-sqlite3 에러 코드 → HTTP 상태 매핑
const SQLITE_ERROR_MAP = {
  SQLITE_CONSTRAINT_UNIQUE:      { status: 409, code: 'CONFLICT',          message: '중복된 데이터입니다' },
  SQLITE_CONSTRAINT_FOREIGNKEY:  { status: 422, code: 'CONSTRAINT_FAILED', message: '참조 무결성 위반입니다' },
  SQLITE_CONSTRAINT_NOTNULL:     { status: 400, code: 'VALIDATION_ERROR',  message: '필수 필드가 null입니다' },
  SQLITE_BUSY:                   { status: 503, code: 'SERVICE_UNAVAILABLE', message: '데이터베이스가 사용 중입니다. 잠시 후 재시도하세요' },
};

function errorHandler(err, req, res, next) { // eslint-disable-line no-unused-vars
  // SQLite 에러 변환
  if (err.code && err.code.startsWith('SQLITE_')) {
    const mapped = SQLITE_ERROR_MAP[err.code];
    if (mapped) {
      err.status  = mapped.status;
      err.code    = mapped.code;
      err.message = mapped.message;
    } else {
      err.status  = err.status || 500;
      err.code    = 'DATABASE_ERROR';
      err.message = '데이터베이스 오류가 발생했습니다';
    }
  }

  const status  = err.status  || 500;
  const code    = err.code    || (status >= 500 ? 'INTERNAL_ERROR' : 'CLIENT_ERROR');
  const message = err.message || 'Internal Server Error';

  // 5xx는 항상 로깅, 4xx는 warn 수준
  logError(err, req);

  const body = {
    ok:    false,
    code,
    error: message,
  };

  // 개발 환경에서는 스택 트레이스 포함
  if (process.env.NODE_ENV !== 'production' && err.stack) {
    body.stack = err.stack;
  }

  res.status(status).json(body);
}

function notFound(req, res) {
  res.status(404).json({
    ok:    false,
    code:  'NOT_FOUND',
    error: `엔드포인트를 찾을 수 없습니다: ${req.method} ${req.path}`,
  });
}

module.exports = { errorHandler, notFound };
