---
name: pptx
description: "PowerPoint 프레젠테이션 생성 및 편집"
---

# PPTX — 프레젠테이션 처리

## 사용 시기
- "프레젠테이션", "PPT", "발표자료", "슬라이드" 요청 시

## 역할

1. **생성** — python-pptx 또는 동등 라이브러리로 .pptx 생성
2. **편집** — 기존 프레젠테이션 수정
3. **분석** — 슬라이드 내용 추출 및 요약
4. **디자인** — 레이아웃, 색상, 폰트 등 시각적 품질 확보

## 원칙

1. 슬라이드당 핵심 메시지 1개 — 간결함 우선
2. 시각적 일관성 — 색상/폰트/레이아웃 통일
3. 데이터는 차트/그래프로 시각화
4. 발표 노트 포함 권장


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: pptx","priority":"medium"}'
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
