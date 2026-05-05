---
name: security-audit
description: gstack /cso 패턴 — OWASP Top 10 + STRIDE 위협 모델링 기반 보안 감사
metadata:
  bashPattern: ["security", "보안", "audit", "감사", "cso", "owasp"]
  filePattern: ["**/*.py", "**/*.js", "**/*.env*"]
  priority: 9
---

# Security Audit (gstack /cso inspired)

## 개요
gstack의 /cso (Chief Security Officer) 패턴. OWASP Top 10 + STRIDE 위협 모델링으로 보안 감사.

## 감사 모드

### Daily Mode (신뢰도 8/10+만 보고)
- 빠른 스캔 (~5분)
- 높은 확신 취약점만 보고
- False positive 최소화

### Comprehensive Mode (신뢰도 2/10+ 보고)
- 전체 스캔 (~30분)
- OWASP Top 10 전항목 검사
- STRIDE 위협 모델링
- 의존성 감사

## OWASP Top 10 체크리스트
1. Broken Access Control
2. Cryptographic Failures
3. Injection (SQL, XSS, Command)
4. Insecure Design
5. Security Misconfiguration
6. Vulnerable Components
7. Authentication Failures
8. Data Integrity Failures
9. Logging Failures
10. SSRF

## STRIDE 위협 모델링
- **S**poofing (위장): 인증 우회
- **T**ampering (변조): 데이터 변조
- **R**epudiation (부인): 감사 로그 부재
- **I**nformation Disclosure (정보 누출): 민감 데이터 노출
- **D**enial of Service (서비스 거부): 리소스 고갈
- **E**levation of Privilege (권한 상승): 인가 우회

## False Positive 제외 목록 (17개)
1. 테스트 파일의 하드코딩된 값
2. 공개 API 키 (문서용)
3. localhost 바인딩
4. 개발 모드 디버그 출력
... (나머지는 컨텍스트에 따라 판단)

## MCP 연동
```
kanban_sprint_gate(sprint_id, gate_type="security", status="Passed", score=9,
  findings="OWASP 10/10 통과, STRIDE 위협 없음, 의존성 최신")
```


## 칸반 연동 (필수)

> 이 스킬 실행 시 반드시 칸반보드에 기록한다.

**실행 전:**
```bash
# 1. 팀/티켓이 없으면 생성
curl -X POST http://localhost:5555/api/teams/{team_id}/tickets -H "Content-Type: application/json" -d '{"title":"스킬 실행: security-audit","priority":"medium"}'
# 2. 클레임
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/claim -H "Content-Type: application/json" -d '{"member_id":"agent-xxx"}'
# 3. progress_note
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/progress -H "Content-Type: application/json" -d '{"note":"스킬 실행 시작"}'
```

**실행 후:**
```bash
# 4. 산출물 등록
curl -X POST http://localhost:5555/api/tickets/{ticket_id}/artifacts -H "Content-Type: application/json" -d '{"creator_member_id":"agent-xxx","title":"결과","content":"...","artifact_type":"result"}'
# 5. Review 전환
curl -X PUT http://localhost:5555/api/tickets/{ticket_id}/status -H "Content-Type: application/json" -d '{"status":"Review"}'
```
