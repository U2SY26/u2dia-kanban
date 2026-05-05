---
name: data-visualization
description: "전문적 데이터 시각화 — 도표/그래프 구현"
---

# Data Visualization — 전문적 시각화

## 사용 시기
- "차트", "그래프", "대시보드", "시각화", "도표" 요청 시

## 핵심 원칙

> 모든 서비스의 디자인은 **전문적이고 아름다운 도표와 그래프** 로 구현해야 함.

### 차트 라이브러리

| 라이브러리 | 용도 | 강점 |
|-----------|------|------|
| Recharts | 일반 차트 | React 네이티브, 간편 |
| D3.js | 커스텀 시각화 | 완전한 자유도 |
| Chart.js | 간단 차트 | 경량, 빠른 렌더링 |
| Nivo | 인터랙티브 | 풍부한 애니메이션 |

### 차트 유형별 가이드

| 데이터 유형 | 추천 차트 | 예시 |
|------------|----------|------|
| 시간 추이 | Area/Line Chart | 매출 추이, 트래픽 |
| 비교 | Bar Chart | 카테고리별 매출, 업체 비교 |
| 비율/구성 | Pie/Donut Chart | 채널별 매출 비중 |
| 상관관계 | Scatter Plot | 가격 vs 판매량 |
| 분포 | Heatmap | 시간대별 주문 분포 |
| 순위 | Horizontal Bar | TOP 10 상품 |
| 지표 | KPI Card | 오늘 매출, 주문 수, 반품률 |

### 디자인 규칙

1. **컬러 팔레트**: 일관된 브랜드 컬러 (최대 8색)
2. **그리드**: 명확한 그리드 라인 (연한 회색)
3. **레이블**: 축 레이블 항상 표시, 단위 명시
4. **툴팁**: 호버 시 상세 정보 표시
5. **반응형**: 모바일에서도 읽기 쉬운 크기
6. **애니메이션**: 부드러운 전환 효과 (과하지 않게)
7. **접근성**: 색맹 대응 팔레트, 패턴 병행 사용

### 대시보드 레이아웃

```
┌────────────┬────────────┬────────────┬────────────┐
│  오늘 매출  │   주문 수   │  신규 회원   │   반품률    │ ← KPI Cards
├────────────┴────────────┴────────────┴────────────┤
│                매출 추이 (Area Chart)                │ ← 메인 차트
├─────────────────────┬────────────────────────────────┤
│  채널별 매출 (Donut) │    TOP 10 상품 (Bar Chart)    │ ← 서브 차트
├─────────────────────┴────────────────────────────────┤
│              최근 주문 (Data Table)                    │ ← 상세 데이터
└──────────────────────────────────────────────────────┘
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: data-visualization","priority":"medium"}'
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
