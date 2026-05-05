---
name: careful-mode
description: gstack /careful 패턴 — 위험한 명령 실행 전 경고 및 확인
metadata:
  bashPattern: ["careful", "주의", "위험", "rm\\s", "drop\\s", "force", "reset.*hard"]
  priority: 10
---

# Careful Mode (gstack /careful inspired)

## 개요
gstack의 /careful 패턴. 파괴적 명령 실행 전 경고하고 확인을 요청.

## 감지 대상

### 파일 시스템
- `rm -rf` (재귀 삭제)
- `chmod 777` (과도한 권한)
- 대량 파일 이동/덮어쓰기

### Git
- `git push --force` (강제 푸시)
- `git reset --hard` (하드 리셋)
- `git branch -D` (브랜치 강제 삭제)
- `git checkout -- .` (모든 변경 취소)

### 데이터베이스
- `DROP TABLE` / `DROP DATABASE`
- `TRUNCATE TABLE`
- `DELETE` without WHERE
- `ALTER TABLE DROP COLUMN`

### 프로세스
- `kill -9` (강제 종료)
- 서비스 중단 명령

## 동작
1. 위험 명령 감지
2. 경고 메시지 표시
3. 영향 범위 설명
4. 대안 제시 (가능한 경우)
5. 사용자 확인 후 실행

## 칸반 연동
- 위험 작업 실행 시 `kanban_activity_log`에 기록
- 팀 SSE로 경고 브로드캐스트
