---
allowed-tools: Read, Glob, Grep, Write, Edit
description: "컨텍스트 리셋 전 작업 상태 문서화"
---

# /dev-docs-update — 작업 상태 저장

컨텍스트 압축/리셋 전에 현재 작업 진행 상태를 문서화합니다.

## 실행 절차

1. 현재 진행 중인 작업 상태 파악
2. 완료/미완료 항목 정리
3. `docs/active/{task-name}/` 문서 업데이트

### 업데이트 항목

- tasks.md: 체크박스 상태 업데이트
- context.md: 새로 발견된 의존성/이슈 추가
- plan.md: 변경된 계획 반영

## 원칙

- 다음 세션에서 바로 이어서 작업 가능한 수준으로 기록
- 미완료 항목의 차단 원인 명시
- 임시 해결책(workaround) 기록
