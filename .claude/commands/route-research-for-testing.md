---
allowed-tools: Bash(cat, awk, grep, sort, xargs, sed)
description: "API 라우트 자동 탐지 및 테스트 연구"
model: sonnet
---

# /route-research — 라우트 테스트 연구

수정된 API 라우트를 자동 탐지하고 테스트 시나리오를 생성합니다.

## 실행 절차

1. `.claude/logs/modified_files.log` 에서 수정된 라우트 파일 탐지
2. `/api/` 또는 `/routes/` 경로 패턴 필터링
3. 각 라우트에 대해 JSON 레코드 생성:
   - 경로, 메서드, 요청/응답 형태
   - 유효/무효 페이로드 예시
4. auth-route-tester 에이전트에 전달

## 출력 형식

```json
{
  "path": "/api/v1/products",
  "method": "GET",
  "auth_required": true,
  "request_shape": {},
  "response_shape": {},
  "valid_payload": {},
  "invalid_payload": {}
}
```
