---
name: ecommerce-api
description: "e커머스 마켓플레이스 API 통합 가이드"
---

# e-Commerce API — 마켓플레이스 API 통합

## 사용 시기
- "쿠팡 API", "네이버 API", "아마존 API", "쇼피파이", "마켓플레이스 연동" 요청 시

## 지원 마켓플레이스

### 국내
| 플랫폼 | API 유형 | 인증 | 주요 기능 |
|--------|----------|------|-----------|
| 쿠팡 (WING) | REST | HMAC-SHA256 | 상품등록, 주문관리, 배송, 정산 |
| 네이버 스마트스토어 | REST | OAuth 2.0 | 상품, 주문, 정산, 톡톡 |
| 11번가 | REST | API Key | 상품, 주문, 배송 |
| G마켓/옥션 | REST | API Key | ESM+ 통합 API |
| 카카오 쇼핑 | REST | OAuth 2.0 | 톡스토어 연동 |
| 위메프/티몬/인터파크 | REST | API Key | 상품/주문 |

### 해외
| 플랫폼 | API 유형 | 인증 | 주요 기능 |
|--------|----------|------|-----------|
| Amazon (SP-API) | REST | OAuth 2.0 + IAM | 글로벌 셀링 전체 |
| Shopify | GraphQL/REST | OAuth 2.0 | 독립몰 완전 통합 |
| eBay | REST | OAuth 2.0 | 글로벌 셀링 |
| Shopee | REST | HMAC | 동남아 |
| Lazada | REST | Token | 동남아 |
| AliExpress | REST | Token | 글로벌 소싱 |

## API 통합 원칙

1. **어댑터 패턴** — 각 마켓플레이스 API를 통일된 인터페이스로 래핑
2. **Rate Limiting** — 각 API의 호출 제한 준수 (큐 기반 처리)
3. **웹훅 우선** — 폴링 대신 웹훅으로 실시간 동기화
4. **재시도 전략** — 지수 백오프 + 최대 재시도 횟수 설정
5. **토큰 관리** — 자동 갱신, 만료 전 사전 갱신, 안전한 저장

## 통합 API 인터페이스 (예시)

```typescript
interface MarketplaceAdapter {
  // 상품
  listProducts(params: ListParams): Promise<Product[]>
  createProduct(product: ProductInput): Promise<Product>
  updateProduct(id: string, product: Partial<ProductInput>): Promise<Product>

  // 주문
  listOrders(params: OrderListParams): Promise<Order[]>
  getOrder(orderId: string): Promise<Order>
  updateOrderStatus(orderId: string, status: OrderStatus): Promise<void>

  // 재고
  updateStock(sku: string, quantity: number): Promise<void>
  getStock(sku: string): Promise<StockInfo>

  // 배송
  registerShipment(orderId: string, shipment: ShipmentInput): Promise<void>
}
```

## 에러 처리

- API별 에러 코드 매핑 → 통일된 에러 코드 체계
- 일시적 에러(429, 5xx) → 자동 재시도
- 영구적 에러(4xx) → 즉시 실패 + 알림


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: ecommerce-api","priority":"medium"}'
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
