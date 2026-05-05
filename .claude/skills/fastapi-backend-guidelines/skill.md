---
name: fastapi-backend-guidelines
description: "FastAPI 백엔드 개발 가이드라인"
---

# FastAPI Backend Guidelines

## 사용 시기
- FastAPI, Python 백엔드, AI 서비스 개발 요청 시

## 기술 스택
- Python 3.12+
- FastAPI (async/await)
- SQLAlchemy 2.0 / SQLModel
- PostgreSQL (asyncpg)
- Redis (aioredis)

## 디렉토리 구조

```
backend/
├── app/
│   ├── main.py           # FastAPI 앱 엔트리포인트
│   ├── config.py         # 설정 (Pydantic Settings)
│   ├── api/
│   │   └── v1/           # API v1 라우터
│   ├── core/             # 인증, 보안, DB 세션
│   ├── models/           # SQLAlchemy 모델
│   ├── schemas/          # Pydantic 스키마
│   ├── services/         # 비즈니스 로직
│   ├── repositories/     # DB 접근 계층
│   └── ai/               # AI/ML 서비스
├── tests/                # pytest 테스트
├── alembic/              # DB 마이그레이션
└── pyproject.toml        # 프로젝트 설정
```

## 원칙

1. **async 기본** — 모든 IO 작업에 async/await 사용
2. **의존성 주입** — FastAPI Depends() 활용
3. **타입 안전** — Pydantic 모델로 입출력 검증
4. **에러 처리** — HTTPException + 글로벌 핸들러
5. **로깅** — structlog로 구조화된 로그
