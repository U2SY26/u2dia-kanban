---
name: shipping-api
description: "배송/물류 API 통합"
---

# Shipping API — 배송/물류 통합

## 사용 시기
- "배송", "택배", "운송장", "물류", "배송 추적" 요청 시

## 지원 택배사

### 국내
| 택배사 | API | 기능 |
|--------|-----|------|
| CJ대한통운 | REST | 운송장 발급, 배송 추적 |
| 한진택배 | REST | 운송장, 추적 |
| 로젠택배 | REST | 운송장, 추적 |
| 우체국택배 | REST | 운송장, 추적 |
| 롯데택배 | REST | 운송장, 추적 |

### 통합 API
| 서비스 | 설명 |
|--------|------|
| 스마트택배 | 택배사 통합 API (추적) |
| 굿스플로 | 배송 관리 플랫폼 |
| 배송의민족 | 풀필먼트 통합 |

## 핵심 기능

1. **운송장 자동 발급** — 주문 확정 시 자동으로 운송장 번호 발급
2. **배송 추적** — 실시간 배송 상태 업데이트
3. **배송비 계산** — 무게/크기/지역별 자동 계산
4. **반품 처리** — 반품 접수 → 역물류 → 반품 완료

## 배송 상태 흐름

```
주문확정 → 상품준비 → 집하완료 → 배송중 → 배송완료
                                    ↓
                              배송지연 → 알림 발송
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: shipping-api","priority":"medium"}'
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
