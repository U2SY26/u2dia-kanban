---
description: "이미지 생성 — OpenAI Images API (DALL-E, GPT Image)로 이미지 생성. 프롬프트 기반 이미지 제작."
---

# OpenAI Image Generation Skill

OpenAI Images API를 사용하여 프롬프트 기반 이미지 생성.

## 활용 시점

- "이미지 생성해줘"
- "로고/배너/일러스트 만들어줘"
- 프로토타입 목업 이미지
- 콘텐츠용 비주얼 생성

## API 사용 (curl)

```bash
curl https://api.openai.com/v1/images/generations \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-image-1",
    "prompt": "A futuristic dashboard UI with dark theme",
    "n": 1,
    "size": "1024x1024"
  }'
```

## 모델별 파라미터

### 크기 옵션
- **GPT Image**: 1024x1024, 1536x1024, 1024x1536, auto
- **DALL-E 3**: 1024x1024, 1792x1024, 1024x1792
- **DALL-E 2**: 256x256, 512x512, 1024x1024

### 품질 옵션
- **GPT Image**: auto, high, medium, low
- **DALL-E 3**: hd, standard
- **DALL-E 2**: standard

### 추가 옵션
- GPT Image: `background` (transparent 지원), `output_format` (webp 지원)
- DALL-E 3: `style` (vivid / natural), n=1만 지원

## 참고
- `OPENAI_API_KEY` 환경변수 필요
- 대량 생성 시 rate limit 주의
- 생성된 이미지 URL은 일시적 — 필요시 즉시 다운로드
