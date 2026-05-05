# Contributing to U2DIA Kanban Board

U2DIA 칸반보드에 기여해주셔서 감사합니다!

## 기여 방법

### 이슈 리포트
- [GitHub Issues](https://github.com/U2SY26/U2DIA-KANBAN-BOARD/issues)에서 버그 리포트나 기능 요청을 올려주세요
- 이슈 템플릿을 사용해주세요

### Pull Request
1. Fork 후 feature 브랜치 생성: `git checkout -b feat/my-feature`
2. 변경사항 커밋: `git commit -m "feat: 기능 설명"`
3. Push: `git push origin feat/my-feature`
4. Pull Request 생성

### 커밋 컨벤션
```
feat: 새로운 기능
fix: 버그 수정
docs: 문서 수정
style: 코드 스타일 (동작 변경 없음)
refactor: 리팩토링
test: 테스트
chore: 빌드/설정 변경
```

## 개발 환경

### 서버
```bash
python3 server.py              # Python 3.8+, 외부 패키지 불필요
```

### 프론트엔드 (웹)
```bash
# 순수 JS/CSS — 빌드 도구 불필요
# server.py가 web/ 디렉토리를 정적 서빙
```

### 모바일 앱
```bash
cd flutter_app
flutter pub get
flutter run
```

### 데스크톱 앱
```bash
cd desktop/server-manager-app
npm install
npm start
```

## 아키텍처 원칙

1. **server.py**: 외부 패키지 금지 — Python 표준 라이브러리만 사용
2. **web/**: 외부 CDN/패키지 없이 순수 JS/CSS
3. **flutter_app/**: 최소 의존성
4. **desktop/**: Electron + 최소 의존성

## 보안

보안 취약점을 발견하시면 이슈 대신 이메일로 보내주세요.
