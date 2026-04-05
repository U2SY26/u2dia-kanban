/**
 * 요청 파라미터 유효성 검사 헬퍼
 *
 * 보안 처리:
 *  - HTML 태그 제거 (XSS 방지)
 *  - Parameterized query 사용 (SQL Injection은 DB 레이어에서 처리됨)
 *  - 타입·포맷·길이 검증으로 비정상 입력 차단
 */

const UUID_RE    = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_RE   = /^[^\s@]{1,64}@[^\s@]{1,255}\.[^\s@]{2,10}$/;
const DATE_RE    = /^\d{4}-\d{2}-\d{2}$/;
const ROLES      = ['member', 'admin', 'viewer'];
const PRIORITIES = ['low', 'medium', 'high', 'urgent'];

/**
 * HTML 태그 및 스크립트 관련 문자 제거 (XSS 방지)
 * REST API JSON 응답 컨텍스트에서 사용
 */
function sanitize(str) {
  if (typeof str !== 'string') return str;
  return str
    .replace(/<[^>]*>/g, '')   // HTML 태그 제거
    .replace(/&[a-z]+;/gi, '') // HTML 엔티티 제거 (&lt; &gt; &amp; 등)
    .trim();
}

// ────────────────────────────────────────────────────────────
// 기본 미들웨어
// ────────────────────────────────────────────────────────────

/**
 * 필수 필드 존재 확인
 * @param {string[]} fields
 */
function requireFields(fields) {
  return (req, res, next) => {
    const missing = fields.filter(f => {
      const v = req.body[f];
      return v === undefined || v === null || v === '';
    });
    if (missing.length) {
      const err = new Error(`필수 필드 누락: ${missing.join(', ')}`);
      err.status = 400;
      return next(err);
    }
    next();
  };
}

/**
 * UUID 형식 path param 검증
 * :id, :boardId, :columnId, :cardId 지원
 */
function validateIdParam(req, res, next) {
  const keys = ['id', 'boardId', 'columnId', 'cardId'];
  for (const key of keys) {
    const val = req.params[key];
    if (val !== undefined && !UUID_RE.test(val)) {
      return res.status(400).json({ ok: false, error: `유효하지 않은 ID 형식: ${key}` });
    }
  }
  next();
}

/**
 * priority 열거형 검증 (기존 라우트 호환)
 */
function validatePriority(req, res, next) {
  if (req.body.priority && !PRIORITIES.includes(req.body.priority)) {
    const err = new Error(`priority는 ${PRIORITIES.join('|')} 중 하나여야 합니다`);
    err.status = 400;
    return next(err);
  }
  next();
}

// ────────────────────────────────────────────────────────────
// 리소스별 body 검증 미들웨어
// ────────────────────────────────────────────────────────────

/**
 * 사용자 body 검증 + sanitize
 * POST/PUT /api/users
 */
function validateUserBody(req, res, next) {
  const { name, email, role, avatar_url } = req.body;

  if (name !== undefined) {
    if (typeof name !== 'string' || name.trim().length === 0 || name.length > 100) {
      return res.status(400).json({ ok: false, error: 'name은 1~100자 문자열이어야 합니다' });
    }
    req.body.name = sanitize(name);
  }

  if (email !== undefined && email !== null && email !== '') {
    if (!EMAIL_RE.test(email) || email.length > 320) {
      return res.status(400).json({ ok: false, error: '유효하지 않은 이메일 형식입니다' });
    }
    req.body.email = sanitize(email).toLowerCase();
  }

  if (role !== undefined && !ROLES.includes(role)) {
    return res.status(400).json({
      ok: false,
      error: `role은 ${ROLES.join('|')} 중 하나여야 합니다`,
    });
  }

  if (avatar_url !== undefined && avatar_url !== null) {
    if (typeof avatar_url !== 'string' || avatar_url.length > 500) {
      return res.status(400).json({ ok: false, error: 'avatar_url은 500자 이하여야 합니다' });
    }
    // http(s):// 또는 빈 값만 허용
    if (avatar_url !== '' && !/^https?:\/\//i.test(avatar_url)) {
      return res.status(400).json({ ok: false, error: 'avatar_url은 http(s):// 로 시작해야 합니다' });
    }
  }

  next();
}

/**
 * 컬럼 body 검증 + sanitize
 * POST/PUT /api/boards/:boardId/columns, PUT /api/columns/:id
 */
function validateColumnBody(req, res, next) {
  const { title, wip_limit, position } = req.body;

  if (title !== undefined) {
    if (typeof title !== 'string' || title.trim().length === 0 || title.length > 100) {
      return res.status(400).json({ ok: false, error: 'title은 1~100자 문자열이어야 합니다' });
    }
    req.body.title = sanitize(title);
  }

  if (wip_limit !== undefined && wip_limit !== null) {
    const n = Number(wip_limit);
    if (!Number.isInteger(n) || n < 1 || n > 9999) {
      return res.status(400).json({ ok: false, error: 'wip_limit은 1~9999 범위의 정수여야 합니다' });
    }
    req.body.wip_limit = n;
  }

  if (position !== undefined && position !== null) {
    const n = Number(position);
    if (!Number.isInteger(n) || n < 0) {
      return res.status(400).json({ ok: false, error: 'position은 0 이상의 정수여야 합니다' });
    }
    req.body.position = n;
  }

  next();
}

/**
 * 카드 body 검증 + sanitize
 * POST /api/columns/:columnId/cards, PUT /api/cards/:id
 */
function validateCardBody(req, res, next) {
  const { title, description, priority, due_date, labels, position, assignee_id } = req.body;

  if (title !== undefined) {
    if (typeof title !== 'string' || title.trim().length === 0 || title.length > 200) {
      return res.status(400).json({ ok: false, error: 'title은 1~200자 문자열이어야 합니다' });
    }
    req.body.title = sanitize(title);
  }

  if (description !== undefined && description !== null) {
    if (typeof description !== 'string' || description.length > 5000) {
      return res.status(400).json({ ok: false, error: 'description은 5000자 이하여야 합니다' });
    }
    req.body.description = sanitize(description);
  }

  if (priority !== undefined && !PRIORITIES.includes(priority)) {
    return res.status(400).json({
      ok: false,
      error: `priority는 ${PRIORITIES.join('|')} 중 하나여야 합니다`,
    });
  }

  if (due_date !== undefined && due_date !== null) {
    if (!DATE_RE.test(due_date) || isNaN(Date.parse(due_date))) {
      return res.status(400).json({ ok: false, error: 'due_date는 YYYY-MM-DD 형식이어야 합니다' });
    }
  }

  if (labels !== undefined) {
    if (!Array.isArray(labels)) {
      return res.status(400).json({ ok: false, error: 'labels는 문자열 배열이어야 합니다' });
    }
    if (labels.length > 20) {
      return res.status(400).json({ ok: false, error: 'labels는 최대 20개까지 허용됩니다' });
    }
    req.body.labels = labels.map(l => sanitize(String(l)).substring(0, 50));
  }

  if (position !== undefined && position !== null) {
    const n = Number(position);
    if (!Number.isInteger(n) || n < 0) {
      return res.status(400).json({ ok: false, error: 'position은 0 이상의 정수여야 합니다' });
    }
    req.body.position = n;
  }

  if (assignee_id !== undefined && assignee_id !== null) {
    if (!UUID_RE.test(assignee_id)) {
      return res.status(400).json({ ok: false, error: '유효하지 않은 assignee_id 형식입니다' });
    }
  }

  next();
}

/**
 * reorder body 검증
 * PUT /api/boards/:boardId/columns/reorder
 * PUT /api/columns/:columnId/cards/reorder
 */
function validateReorderBody(req, res, next) {
  const { orders } = req.body;
  if (!Array.isArray(orders) || orders.length === 0) {
    return res.status(400).json({ ok: false, error: 'orders 배열이 필요합니다' });
  }
  for (const item of orders) {
    if (!item || typeof item !== 'object') {
      return res.status(400).json({ ok: false, error: 'orders 각 항목은 객체여야 합니다' });
    }
    if (!UUID_RE.test(item.id)) {
      return res.status(400).json({ ok: false, error: `orders[].id가 유효한 UUID가 아닙니다: ${item.id}` });
    }
    const pos = Number(item.position);
    if (!Number.isInteger(pos) || pos < 0) {
      return res.status(400).json({ ok: false, error: `orders[].position은 0 이상의 정수여야 합니다` });
    }
  }
  next();
}

module.exports = {
  sanitize,
  requireFields,
  validateIdParam,
  validatePriority,
  validateUserBody,
  validateColumnBody,
  validateCardBody,
  validateReorderBody,
};
