---
description: "비디오 프레임 추출 — ffmpeg로 영상에서 프레임/썸네일/클립 추출."
---

# Video Frames Skill

ffmpeg를 사용하여 비디오에서 프레임 추출 및 썸네일 생성.

## 활용 시점

- 영상에서 특정 시점 프레임 캡처
- 썸네일 이미지 생성
- 영상 미리보기 이미지 추출
- 영상 분석을 위한 프레임 샘플링

## 명령어

### 첫 프레임 추출
```bash
ffmpeg -i input.mp4 -vframes 1 -q:v 2 output.jpg
```

### 특정 시점 프레임
```bash
ffmpeg -i input.mp4 -ss 00:00:10 -vframes 1 -q:v 2 frame-10s.jpg
```

### 일정 간격 프레임 추출
```bash
ffmpeg -i input.mp4 -vf "fps=1" frames/frame_%04d.jpg        # 1초당 1프레임
ffmpeg -i input.mp4 -vf "fps=1/10" frames/frame_%04d.jpg     # 10초당 1프레임
```

### GIF 생성
```bash
ffmpeg -i input.mp4 -ss 5 -t 3 -vf "fps=10,scale=320:-1" output.gif
```

## 참고
- JPG: 빠른 공유용, PNG: 선명한 UI 캡처용
- `-q:v 2` 가 높은 품질 (1=최상, 31=최저)
- ffmpeg 설치 필요: `choco install ffmpeg` (Windows) / `brew install ffmpeg` (macOS)
