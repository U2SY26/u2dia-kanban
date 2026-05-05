---
description: "Google Gemini AI — Gemini CLI 또는 API로 질문, 요약, 생성 작업. 대안 AI 모델 활용."
---

# Gemini Skill

Google Gemini를 one-shot 모드로 사용하여 질문, 요약, 콘텐츠 생성.

## 활용 시점

- Claude 외 대안 AI 모델 필요 시
- Google 생태계 연동
- 멀티모달 작업 (이미지+텍스트)
- 긴 컨텍스트 처리 (100만+ 토큰)

## CLI 사용

```bash
gemini "질문 내용..."
gemini --model gemini-2.5-pro "복잡한 분석 요청"
gemini --output-format json "JSON으로 결과 반환해줘"
```

## API 사용 (curl)

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key=$GEMINI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "contents": [{"parts": [{"text": "질문 내용"}]}]
  }'
```

## 확장 기능

```bash
gemini --list-extensions
gemini extensions <command>
```

## 참고
- 설정: `GEMINI_API_KEY` 환경변수
- CLI 설치: `brew install gemini-cli` 또는 `npm i -g @anthropic-ai/gemini-cli`
- 첫 실행 시 인증 플로우 안내
