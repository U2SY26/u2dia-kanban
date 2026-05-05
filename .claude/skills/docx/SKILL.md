---
name: docx
description: "Word 문서 생성 및 편집"
---

# DOCX — Word 문서 처리

## 사용 시기
- ".docx", "Word 문서", "문서 작성", "보고서 생성" 요청 시

## 역할

1. **생성** — python-docx 또는 동등 라이브러리로 .docx 생성
2. **편집** — 기존 문서 수정 (텍스트, 표, 스타일)
3. **분석** — 문서 내용 추출 및 구조 분석
4. **변환** — Markdown ↔ DOCX 변환

## 원칙

1. 문서 스타일은 프로젝트 브랜드에 맞춤
2. 표, 목차, 페이지 번호 등 전문적 서식 적용
3. 이미지/차트 삽입 시 해상도와 크기 적절히 조정
4. 기존 문서 편집 시 원본 스타일 보존


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: docx","priority":"medium"}'
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
