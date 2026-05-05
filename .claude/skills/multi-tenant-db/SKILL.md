---
name: multi-tenant-db
description: "멀티 테넌트 DB 아키텍처 가이드"
---

# Multi-Tenant DB — 멀티 테넌트 데이터베이스

## 사용 시기
- "멀티 테넌트", "업체별 DB", "스키마 분리", "테넌트 격리" 요청 시

## 전략: Schema-per-Tenant (PostgreSQL)

3만개 업체를 지원하기 위한 스키마 분리 전략.

### 왜 Schema-per-Tenant?

| 전략 | 격리 | 비용 | 3만개 확장성 | 선택 |
|------|------|------|-------------|------|
| DB-per-Tenant | 최고 | 매우 높음 | 불가능 | X |
| Schema-per-Tenant | 높음 | 중간 | 가능 | O |
| Row-level (RLS) | 낮음 | 낮음 | 가능 | 보조 |

### 구조

```sql
-- 공통 스키마
CREATE SCHEMA public;
-- companies, users, roles, platform_configs, dev_requests

-- 업체별 스키마 (자동 생성)
CREATE SCHEMA tenant_{company_id};
-- products, inventory, orders, shipments, api_connections, analytics

-- 분석 전용 스키마
CREATE SCHEMA analytics;
-- market_trends, price_history, sales_predictions
```

### 연결 관리

```
                 PgBouncer (연결 풀링)
                /          |          \
       Pool A          Pool B         Pool C
      (tenant_1)     (tenant_2)    (tenant_N)
```

- PgBouncer: Transaction Pooling 모드
- 기본 풀 사이즈: 업체당 2 연결
- 최대: 업체당 10 연결 (버스트)
- Read Replica: 분석/조회 전용

### 테넌트 라우팅

```typescript
// 미들웨어에서 테넌트 결정
async function tenantMiddleware(req, res, next) {
  const companyId = extractCompanyId(req); // JWT에서 추출
  req.schema = `tenant_${companyId}`;
  req.db = await getPoolForTenant(companyId);
  next();
}
```

### 마이그레이션

- 공통 스키마: 일반 마이그레이션
- 테넌트 스키마: 모든 테넌트에 일괄 적용 (배치 스크립트)
- 멱등성: `IF NOT EXISTS` 필수

## 성능 최적화

1. **인덱싱**: 테넌트별 최적 인덱스 (자동 생성)
2. **파티셔닝**: 대용량 테이블 (orders, analytics) 날짜별 파티션
3. **캐싱**: Redis — 자주 조회되는 상품/재고 정보
4. **샤딩**: 10만 이상 업체 시 수평 샤딩 준비


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: multi-tenant-db","priority":"medium"}'
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
