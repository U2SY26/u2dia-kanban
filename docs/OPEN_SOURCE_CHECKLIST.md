# 오픈소스 공개 체크리스트

> public 전환 전 반드시 수행할 작업 목록

## CRITICAL — 민감정보 제거

### 1. `.claude/CLAUDE.md` 토큰 제거
- [ ] 163~179행 "연동 프로젝트 및 토큰" 테이블에서 **실제 토큰값 제거**
- [ ] 토큰 컬럼을 `XXXX-XXXX-XXXX-XXXX` 플레이스홀더로 교체

### 2. `.claude/settings.json` MCP 토큰 제거
- [ ] `Authorization` 헤더의 Bearer 토큰 → 플레이스홀더로 교체

### 3. `.mcp.json` 토큰 제거
- [ ] Bearer 토큰 → 플레이스홀더로 교체

### 4. Flutter 앱 하드코딩 IP 제거
- [ ] `flutter_app/lib/services/api_service.dart` 7행
  - `http://100.65.106.26:5555` → `http://localhost:5555`

### 5. Git 히스토리 정리
- [ ] 위 파일들의 이전 커밋에도 토큰이 남아있으므로, public 전환 시:
  - 방법 A: `git filter-branch` 또는 `git filter-repo`로 히스토리 재작성
  - 방법 B: 새 레포 생성 후 현재 코드만 initial commit (추천)

### 6. API 키 로테이션
- [ ] 모든 노출된 키 즉시 재발급:
  - Telegram Bot Token
  - OpenAI API Key
  - GitHub PAT
  - Google Gemini API Key
  - Anthropic API Key
  - 칸반보드 인증 토큰 13개

## HIGH — 필수 파일

- [x] LICENSE (MIT)
- [x] README.md (오픈소스 수준)
- [x] CONTRIBUTING.md
- [ ] .github/ISSUE_TEMPLATE/ (이슈 템플릿)
- [ ] .github/PULL_REQUEST_TEMPLATE.md

## MEDIUM — 정리

- [ ] 바이너리 파일 제거 (APK, EXE — GitHub Releases로 이동)
- [ ] `web/u2dia-kanban.apk` git에서 제거 (releases에서만 배포)
- [ ] `desktop/*/dist/` git에서 제거
- [ ] `flutter_app/build/` git에서 제거
- [ ] 레포 크기 5.4GB → 목표 50MB 이하

## 공개 시 추천 전략

### 방법: 새 레포로 클린 스타트 (추천)
```bash
# 1. 현재 코드를 새 디렉토리에 복사 (git history 제외)
mkdir U2DIA-KANBAN-BOARD-public
cp -r U2DIA-KANBAN-BOARD/* U2DIA-KANBAN-BOARD-public/
# (바이너리, .env, 민감파일 제외)

# 2. 민감정보 정리 후 initial commit
cd U2DIA-KANBAN-BOARD-public
git init
git add .
git commit -m "Initial release: U2DIA AI Kanban Board v1.2.0"

# 3. GitHub에 public 레포 생성 후 push
git remote add origin https://github.com/U2SY26/U2DIA-KANBAN-BOARD.git
git push -u origin main
```

### APK/데스크톱 앱 배포
- GitHub Releases에만 바이너리 첨부
- git 레포에는 소스코드만 유지
