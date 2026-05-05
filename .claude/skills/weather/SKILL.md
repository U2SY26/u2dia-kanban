---
description: "날씨 조회 — wttr.in으로 현재 날씨와 예보 확인. API 키 불필요."
---

# Weather Skill

curl + wttr.in으로 현재 날씨 및 예보 조회. API 키 불필요.

## 활용 시점

- "오늘 날씨 어때?"
- "내일 비 와?"
- "[도시] 기온"
- 주간 날씨 예보
- 여행 계획 시 날씨 확인

## 명령어

### 현재 날씨
```bash
curl "wttr.in/Seoul?format=3"
curl "wttr.in/Seoul?0"
curl "wttr.in/New+York?format=3"
```

### 예보
```bash
curl "wttr.in/Seoul"
curl "wttr.in/Seoul?format=v2"
curl "wttr.in/Seoul?1"        # 오늘만
```

### 포맷 코드
- `%c` 날씨 아이콘
- `%t` 기온
- `%f` 체감 온도
- `%w` 풍속
- `%h` 습도
- `%p` 강수량

### JSON 출력
```bash
curl "wttr.in/Seoul?format=j1"
```

## 참고
- 공항 코드 지원: `curl wttr.in/ICN`
- Rate limit 존재 — 반복 요청 자제
