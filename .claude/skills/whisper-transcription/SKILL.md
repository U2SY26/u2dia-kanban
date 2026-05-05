---
description: "음성 텍스트 변환 — OpenAI Whisper API 또는 로컬 Whisper로 오디오/비디오 트랜스크립션."
---

# Whisper Transcription Skill

OpenAI Whisper를 사용한 음성-텍스트 변환 (STT).

## 활용 시점

- 오디오/비디오 파일 트랜스크립션
- 회의 녹음 텍스트 변환
- 자막(SRT) 생성
- 다국어 음성 번역

## API 사용 (Whisper API)

```bash
curl https://api.openai.com/v1/audio/transcriptions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F file="@audio.mp3" \
  -F model="whisper-1" \
  -F language="ko"
```

### 번역 (영어로)
```bash
curl https://api.openai.com/v1/audio/translations \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F file="@audio.mp3" \
  -F model="whisper-1"
```

## 로컬 Whisper CLI

```bash
whisper audio.mp3 --model medium --output_format txt --output_dir .
whisper audio.m4a --task translate --output_format srt
whisper audio.wav --model large --language ko
```

### 모델 선택
- `tiny` / `base` — 빠르지만 낮은 정확도
- `small` / `medium` — 균형
- `large` — 높은 정확도, 느린 속도

## 출력 형식
- `txt` — 순수 텍스트
- `srt` — 자막 (타임스탬프 포함)
- `vtt` — WebVTT 자막
- `json` — 구조화된 JSON

## 참고
- API: `OPENAI_API_KEY` 필요, 파일 크기 25MB 제한
- 로컬: `pip install openai-whisper` 또는 `brew install openai-whisper`
- 모델은 `~/.cache/whisper`에 자동 다운로드
