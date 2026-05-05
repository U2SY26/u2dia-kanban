---
name: tax-compliance
description: 글로벌 SaaS 세무 컴플라이언스 — 14개국 세금, 사업자정보, 세금계산서, VAT/GST, 인보이스, 개인정보 페이지 국가별 분기, 세무 방어 체계
metadata:
  bashPattern: ["세금", "tax", "세무", "VAT", "사업자", "세금계산서", "invoice", "부가세", "GST", "Sales Tax"]
  priority: 10
---

# Global Tax Compliance (14개국 SaaS 세무 방어 체계)

> 해외 SaaS 제공 시 **사업자 등록(법인 설립) 없이 세금 등록만으로 운영 가능**한 경우가 대부분.
> 핵심: 매출 임계치 초과 시 해당국에 **세금 등록(VAT/GST)** 필요.

---

## 1. 국가별 세금 규정 (14개국)

### 🇰🇷 한국 — VAT 10%
- [ ] 사업자등록번호 표시 (000-00-00000)
- [ ] 통신판매업 신고번호
- [ ] 전자세금계산서 발행 (연매출 1억+ 의무)
- [ ] 홈택스 연동 또는 발행 API (바로빌, 팝빌)
- [ ] B2C: 부가세 포함 가격 / B2B: 별도 표기
- [ ] 원천징수 3.3% (프리랜서)
- [ ] 사업자정보 페이지: 상호, 대표자, 사업자번호, 통판번호, 주소, 전화, 개인정보책임자

### 🇯🇵 일본 — 소비세 10%
- [ ] 적격청구서 (適格請求書) T번호 표기
- [ ] 인보이스 제도 등록 (2023~)
- [ ] B2C: 국외사업자 소비세 등록 (매출 ¥10M/년 초과 시)
- [ ] B2B: 역과세 (Reverse Charge) → 등록 면제
- [ ] 개인정보보호법 준수

### 🇩🇪 독일 — VAT 19%
- [ ] EU VAT 번호 취득 (DE + 9자리)
- [ ] VIES 시스템 VAT ID 실시간 검증
- [ ] B2B: 역과세 적용 / B2C: 현지 세율 적용
- [ ] Reverse Charge 인보이스 기재

### 🇫🇷 프랑스 — VAT 20%
- [ ] EU VAT 등록 (FR + 11자리)
- [ ] VIES 검증
- [ ] 디지털 서비스 VAT 적용

### 🇬🇧 영국 — VAT 20%
- [ ] Non-resident VAT 등록 (디지털 서비스는 매출 £0부터 즉시)
- [ ] GB VAT 번호 (GB + 9자리)
- [ ] MTD (Making Tax Digital) 디지털 보고
- [ ] Brexit 후 EU와 별도 등록 필요

### 🇺🇸 미국 — Sales Tax (주별 상이)
- [ ] Economic Nexus 판단 (연 $100K 또는 200건+)
- [ ] 15개 주 SaaS 과세: CT, DC, HI, IA, KY, MA, MS, NM, NY, OH, PA, RI, SC, SD, TN, TX, WA, WV
- [ ] Tax Exempt 고객 처리 (Resale Certificate)
- [ ] 자동화: Avalara, TaxJar 연동
- [ ] W-9/1099-NEC (미국 계약자 $600+)

### 🇸🇬 싱가포르 — GST 9%
- [ ] Overseas Vendor Registration (매출 S$100K/년 초과)
- [ ] 임계치 이하 면제
- [ ] GST 번호 등록

### 🇦🇺 호주 — GST 10%
- [ ] Non-resident GST 등록 (매출 A$75K/년 초과)
- [ ] ABN (Australian Business Number) 취득
- [ ] 온라인 등록 가능

### 🇨🇦 캐나다 — GST 5% + PST/HST
- [ ] Non-resident GST/HST 등록 (매출 C$30K/년 초과)
- [ ] 주별 PST 추가 (BC 7%, QC 9.975%)
- [ ] BN (Business Number) 취득

### 🇮🇳 인도 — GST 18%
- [ ] OIDAR (Online Information and Database Access or Retrieval) GST 등록
- [ ] 매출 ₹20L/년 초과 시 등록
- [ ] GSTIN 번호 취득

### 🇹🇼 대만 — VAT 5%
- [ ] 비거주자 VAT 등록 (매출 NT$480K/년 초과)
- [ ] 전자 인보이스 시스템

### 🇹🇭 태국 — VAT 7%
- [ ] 비거주자 VAT 등록 (매출 THB 1.8M/년 초과)
- [ ] e-Service VAT 신고

### 🇻🇳 베트남 — VAT 10%
- [ ] 외국 공급자 등록 포털
- [ ] 분기별 신고

### 🇪🇺 EU 공통 — OSS (One-Stop-Shop)
- [ ] EU OSS 등록 (1개국만 등록 → 27개국 커버)
- [ ] 아일랜드 등록 추천 (영어 + 낮은 법인세)
- [ ] 임계치: €10K/년 (B2C 크로스보더)
- [ ] VIES VAT ID 실시간 검증 API
- [ ] 분기별 OSS 신고

---

## 2. 사업자 등록 vs 세금 등록

| 구분 | 사업자 등록 (법인 설립) | 세금 등록 (VAT/GST) |
|------|----------------------|-------------------|
| 필요 여부 | 대부분 불필요 | 매출 임계치 초과 시 필요 |
| 비용 | 수백~수천만원 | 무료~수십만원 |
| 절차 | 현지 법인/지사 설립 | 온라인 등록 |

> **핵심**: 대부분의 국가에서 **사업자 등록 없이 세금 등록만으로 SaaS 운영 가능**

---

## 3. 구현 가이드 — API & 프론트엔드

### 3.1 세금 계산 API
```
GET  /api/tax/rate?country=KR&type=b2c        → { rate: 0.10, name: "VAT" }
GET  /api/tax/rate?country=US&state=CA&type=b2c → { rate: 0.0725, name: "Sales Tax" }
POST /api/tax/calculate                        → { subtotal, tax, total }
```

### 3.2 인보이스 API (CRUD)
```
POST   /api/invoices          → 인보이스 생성
GET    /api/invoices/:id      → 조회
PUT    /api/invoices/:id      → 수정
DELETE /api/invoices/:id      → 삭제
GET    /api/invoices/:id/pdf  → PDF 다운로드
```

### 3.3 사업자정보 API
```
GET  /api/profile/business-info         → 사업자정보 조회
PUT  /api/profile/business-info         → 사업자정보 수정
POST /api/tax/validate-id?country=EU&id=DE123456789  → 세금 ID 검증 (VIES 등)
```

### 3.4 국가별 개인정보/사업자정보 페이지 분기
```
/privacy?region=kr → 한국 (사업자정보 + 세금계산서 안내)
/privacy?region=us → 미국 (CCPA + Do Not Sell)
/privacy?region=eu → EU (GDPR + DPO + 쿠키동의)
/privacy?region=jp → 일본 (적격청구서 T번호)
/privacy?region=gb → 영국 (UK GDPR + VAT)
/privacy?region=sg → 싱가포르 (PDPA + GST)
/privacy?region=au → 호주 (Privacy Act + GST)
/privacy (기본)   → 영문 글로벌 버전
```

### 3.5 세금 ID 실시간 검증
- EU: VIES API (`https://ec.europa.eu/taxation_customs/vies/`)
- 한국: 국세청 사업자 진위확인 API
- 일본: 국세청 적격청구서 발행사업자 공표 API
- 인도: GSTIN 검증 API

---

## 4. 세무 방어 체계 (4-Phase 로드맵)

### Phase 1: 기본 (즉시)
- [ ] 국가별 세율 테이블 구현
- [ ] 인보이스 자동 발행
- [ ] 한국 사업자정보 페이지

### Phase 2: 확장 (1개월)
- [ ] VIES VAT 검증 연동
- [ ] US Sales Tax 주별 자동 계산
- [ ] 일본 적격청구서 지원

### Phase 3: 자동화 (3개월)
- [ ] Stripe Tax / Avalara 연동
- [ ] 국가별 자동 세금 신고 준비
- [ ] Tax Exempt 처리 워크플로우

### Phase 4: 글로벌 (6개월)
- [ ] 14개국 전체 지원
- [ ] 이전가격 문서화 (TP Documentation)
- [ ] 조세조약 자동 적용

---

## 5. 칸반 연동

```
/tax-compliance check --project PROJECT_NAME --region all
kanban_ticket_create(team_id, title="[세무] 한국 전자세금계산서 연동", priority="High", tags=["tax","kr"])
kanban_ticket_create(team_id, title="[세무] EU OSS 등록", priority="Critical", tags=["tax","eu"])
kanban_ticket_create(team_id, title="[세무] US Sales Tax 15주 구현", priority="High", tags=["tax","us"])
```
