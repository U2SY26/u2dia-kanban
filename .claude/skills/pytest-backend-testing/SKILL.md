---
name: pytest-backend-testing
description: "FastAPI pytest 테스트 가이드"
---

# pytest Backend Testing

## 사용 시기
- "테스트", "pytest", "유닛 테스트", "통합 테스트" 요청 시

## 테스트 구조

```
tests/
├── conftest.py           # 공통 fixture (DB, 클라이언트)
├── unit/                 # 유닛 테스트
│   ├── test_services.py
│   └── test_utils.py
├── integration/          # 통합 테스트
│   ├── test_api.py
│   └── test_db.py
└── e2e/                  # E2E 테스트
```

## 실행

```bash
pytest                          # 전체 테스트
pytest tests/unit/              # 유닛만
pytest -x                       # 첫 실패 시 중단
pytest --cov=app                # 커버리지 포함
pytest -k "test_product"        # 특정 테스트만
```

## fixture 패턴

```python
@pytest.fixture
async def db_session():
    async with async_session() as session:
        yield session
        await session.rollback()

@pytest.fixture
async def client(db_session):
    app.dependency_overrides[get_db] = lambda: db_session
    async with AsyncClient(app=app) as client:
        yield client
```

## 원칙

1. **격리** — 각 테스트는 독립적, 순서 의존성 없음
2. **커버리지 80%+** — 핵심 비즈니스 로직 우선
3. **빠른 피드백** — 유닛 테스트 1초 이내
4. **실제 데이터 유사** — factory_boy로 테스트 데이터 생성


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: pytest-backend-testing","priority":"medium"}'
# 2. 클레임
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/claim -H "Content-Type: application/json" -d '{"member_id":"agent-xxx"}'
# 3. progress_note
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/progress -H "Content-Type: application/json" -d '{"note":"스킬 실행 시작"}'
```

**실행 후:**
```bash
# 4. 산출물 등록
curl -X POST http://localhost:5555/api/tickets/{ticket_id}/artifacts -H "Content-Type: application/json" -d '{"creator_member_id":"agent-xxx","title":"결과","content":"...","artifact_type":"result"}'
# 5. Review 전환
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/status -H "Content-Type: application/json" -d '{"status":"Review"}'
```
