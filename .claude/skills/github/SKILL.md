---
name: github
description: "GitHub 작업 (PR, Issue, CI/CD)"
---

# GitHub — 코드 협업

## 사용 시기
- "PR", "Pull Request", "Issue", "CI/CD", "GitHub Actions" 요청 시

## 주요 작업

### PR 관리
```bash
gh pr create --title "제목" --body "설명"
gh pr list --state open
gh pr view 123
gh pr merge 123
```

### Issue 관리
```bash
gh issue create --title "버그: 설명" --label "bug"
gh issue list --state open
gh issue close 123
```

### CI/CD (GitHub Actions)
- `.github/workflows/` 에 워크플로우 정의
- Push/PR 이벤트 기반 자동 테스트/빌드/배포
- Vercel 자동 배포 연동

## 브랜치 전략

- `main` — 프로덕션 (보호됨)
- `develop` — 개발 통합
- `feature/*` — 기능 개발
- `fix/*` — 버그 수정
- `release/*` — 릴리스 준비


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: github","priority":"medium"}'
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
