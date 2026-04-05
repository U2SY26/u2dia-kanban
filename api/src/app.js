/**
 * U2DIA Kanban Board — Node.js/Express RESTful API
 * 로컬 서버 전용 (표준 Express 구성)
 *
 * 엔드포인트 요약:
 *   인증:   POST /api/auth/register|login|refresh, GET /api/auth/me
 *   사용자:  GET|POST /api/users, GET|PUT|DELETE /api/users/:id
 *   컬럼:   GET|POST /api/boards/:boardId/columns
 *           PUT|DELETE /api/columns/:id
 *           PUT /api/boards/:boardId/columns/reorder
 *   카드:   GET|POST /api/columns/:columnId/cards
 *           GET /api/boards/:boardId/cards
 *           GET|PUT|DELETE /api/cards/:id
 *           PUT /api/cards/:id/move
 *           PUT /api/columns/:columnId/cards/reorder
 *   문서:   GET /api-docs  (Swagger UI)
 *           GET /api-docs/openapi.yaml
 */
const path    = require('path');
const express = require('express');
const cors    = require('cors');
const yaml    = require('js-yaml');
const fs      = require('fs');
const swaggerUi = require('swagger-ui-express');

const authRouter                                     = require('./routes/auth');
const usersRouter                                    = require('./routes/users');
const columnsRouter                                  = require('./routes/columns');
const { itemRouter: columnsItemRouter }              = require('./routes/columns');
const { columnCardRouter, boardCardRouter,
        itemRouter: cardsItemRouter }                = require('./routes/cards');
const { errorHandler, notFound }                     = require('./middleware/errorHandler');
const { requestLogger, log }                         = require('./middleware/logger');
const { defaultLimiter, writeLimiter }               = require('./middleware/rateLimiter');
const { authenticate, authorize }                    = require('./middleware/auth');

const app = express();

// ── 글로벌 미들웨어 ──────────────────────────────────────
app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use(requestLogger);            // 요청/응답 구조적 로깅
app.use(defaultLimiter);           // 글로벌 Rate Limit (분당 200)

// ── Swagger UI (/api-docs) ───────────────────────────────
const OPENAPI_PATH = path.join(__dirname, '..', 'openapi.yaml');

try {
  const spec = yaml.load(fs.readFileSync(OPENAPI_PATH, 'utf8'));
  app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(spec, {
    customSiteTitle: 'U2DIA Kanban API Docs',
    swaggerOptions: { persistAuthorization: true },
  }));
  // 원본 YAML 파일도 서빙 (외부 도구 연동용)
  app.get('/api-docs/openapi.yaml', (req, res) => {
    res.setHeader('Content-Type', 'text/yaml; charset=utf-8');
    res.sendFile(OPENAPI_PATH);
  });
  log('info', 'Swagger UI 활성화', { url: '/api-docs' });
} catch (err) {
  log('warn', 'openapi.yaml 로드 실패 — Swagger UI 비활성화', { error: err.message });
}

// ── 헬스체크 ─────────────────────────────────────────────
app.get('/health', (req, res) => {
  res.json({
    ok: true,
    service: 'u2dia-kanban-api',
    version: '2.0.0',
    uptime: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
  });
});

// ── 라우트 등록 ──────────────────────────────────────────

// 인증 (Rate Limit: strictLimiter가 내부에서 적용)
app.use('/api/auth', authRouter);

// 사용자
//   읽기: 인증 선택 (optionalAuth), 쓰기: admin 필수
app.use('/api/users', usersRouter);

// 컬럼 (보드 하위)
app.use('/api/boards/:boardId/columns', columnsRouter);
// 컬럼 단건 (boardId 없이)
app.use('/api/columns', columnsItemRouter);

// 카드 (컬럼 하위)
app.use('/api/columns/:columnId/cards', columnCardRouter);
// 카드 (보드 전체 조회)
app.use('/api/boards/:boardId/cards', boardCardRouter);
// 카드 단건
app.use('/api/cards', cardsItemRouter);

// ── 404 / 에러 핸들러 ────────────────────────────────────
app.use(notFound);
app.use(errorHandler);

// ── 서버 시작 ────────────────────────────────────────────
const PORT = process.env.PORT || 3001;
const HOST = process.env.HOST || '0.0.0.0';

if (require.main === module) {
  app.listen(PORT, HOST, () => {
    const base = `http://${HOST === '0.0.0.0' ? 'localhost' : HOST}:${PORT}`;
    log('info', `[kanban-api] 서버 시작`, {
      url:     base,
      docs:    `${base}/api-docs`,
      db:      process.env.KANBAN_DB_PATH || 'agent_teams.db (기본값)',
      env:     process.env.NODE_ENV || 'development',
    });
  });
}

module.exports = app;
