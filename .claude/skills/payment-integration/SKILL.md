---
name: payment-integration
description: "결제/정산 API 통합 (참조용 — 금융 업무 제외)"
---

# Payment Integration — 결제 참조 가이드

## 사용 시기
- "결제", "PG", "정산", "매출 조회" 요청 시

## 주의사항

> 이 프로젝트에서 **금융 업무(결제 처리)는 직접 구현하지 않음**.
> 마켓플레이스 API를 통한 **정산 조회/매출 데이터 수집**만 해당.

## 지원 범위

### 포함
- 마켓플레이스별 정산 데이터 조회
- 매출/수수료/정산금 대시보드
- 정산 내역 다운로드 (XLSX)

### 제외 (직접 구현하지 않음)
- PG 결제 처리
- 결제 수단 등록
- 환불 처리
- 송금/이체

## 정산 데이터 모델

```
settlements
├── marketplace (출처)
├── period_start / period_end (정산 기간)
├── total_sales (총 매출)
├── commission (수수료)
├── shipping_fee (배송비)
├── net_amount (정산 금액)
├── status (대기/완료)
└── details (상세 내역 JSON)
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: payment-integration","priority":"medium"}'
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
