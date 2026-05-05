---
description: "X(Twitter) API — xurl CLI로 포스트 작성, 검색, 타임라인 조회, DM 등 X 플랫폼 작업."
---

# X (Twitter) Skill

xurl CLI를 사용하여 X(Twitter) API와 상호작용.

## 활용 시점

- X 포스트 작성/삭제
- 검색, 타임라인 조회
- 좋아요, 리포스트, 북마크
- 팔로우/언팔로우, 차단/뮤트
- DM 전송

## 설치

```bash
brew install --cask xdevplatform/tap/xurl
# 또는
npm install -g @xdevplatform/xurl
```

## 인증
```bash
xurl auth status
```

## 주요 명령어

```bash
# 포스트 작성
xurl post "Hello, world!"

# 답글
xurl reply <tweet-id> "답글 내용"

# 인용
xurl quote <tweet-id> "인용 코멘트"

# 검색
xurl search "검색어" --max 10

# 타임라인
xurl timeline --max 20

# 내 정보
xurl whoami

# 좋아요
xurl like <tweet-id>
xurl unlike <tweet-id>

# 리포스트
xurl repost <tweet-id>

# 팔로우
xurl follow <username>
xurl unfollow <username>
```

## Raw API 접근

```bash
xurl /2/users/me
xurl -X POST /2/tweets -d '{"text":"Hello world!"}'
```

## 보안 주의
- `~/.xurl` 파일 내용 절대 출력 금지
- `--verbose` 플래그 에이전트 세션에서 사용 금지
- 인증 토큰 관련 플래그 사용 금지
