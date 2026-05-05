---
name: project-health-check
description: 프로젝트 건강 상태 자동 진단 — git 상태, 의존성 취약점, 빌드 가능 여부, 미해결 TODO/FIXME, 코드 품질 점수
triggers:
  - "프로젝트 상태"
  - "건강 진단"
  - "health check"
  - "코드 점검"
  - "프로젝트 점검"
---

# Project Health Check

프로젝트의 전반적 건강 상태를 자동 진단합니다.

## 진단 항목

1. **Git 상태** — 미커밋 변경, 브랜치 수, 최근 커밋 날짜
2. **의존성** — outdated 패키지, 보안 취약점 (`npm audit` / `pip audit`)
3. **빌드 가능 여부** — `npm run build` 또는 `python -m py_compile`
4. **코드 품질** — TODO/FIXME 개수, 빈 catch 블록, console.log 잔재
5. **테스트 커버리지** — 테스트 파일 존재 여부, 최근 실행 결과

## 실행 방법

```bash
# Node.js 프로젝트
cd <project_path>
git status --short | wc -l          # 미커밋 파일 수
git log -1 --format="%cr"           # 마지막 커밋 시각
npm audit --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'취약점: {d.get(\"metadata\",{}).get(\"vulnerabilities\",{})}')"
grep -rn "TODO\|FIXME\|HACK" --include="*.ts" --include="*.tsx" --include="*.js" | wc -l

# Python 프로젝트
find . -name "*.py" | head -20 | xargs python3 -m py_compile 2>&1 | head -5
grep -rn "TODO\|FIXME\|HACK" --include="*.py" | wc -l
```

## 보고 형식

```
📊 프로젝트 건강 리포트: <project_name>
├── Git: ✅ 클린 | ⚠️ 미커밋 3개
├── 의존성: ✅ 안전 | 🔴 취약점 2개
├── 빌드: ✅ 성공 | ❌ 실패
├── 코드품질: TODO 15개, FIXME 3개
└── 테스트: ✅ 통과 | ⚠️ 테스트 없음
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: project-health-check","priority":"medium"}'
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
