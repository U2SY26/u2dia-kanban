# Deep Agent 2단계 구조 설계서

**티켓**: T-156D0F
**기반**: NVIDIA AI-Q 벤치마킹 (T-96C4E8)

---

## 1. 현재 구조 분석

```
r_agent_chat()
  ├─ 승인 확인 (pending_dispatch)
  ├─ 프로젝트 별명 매칭
  └─ _chat_agent_respond()
       ├─ _chat_supervisor_respond()  ← 검수/QA 키워드
       ├─ _chat_quick_answer()        ← 조회 키워드
       └─ 10턴 루프 (GPT→Kimi→Ollama) ← 작업 지시
```

**문제점**:
- 키워드 기반 의도 분류 (오분류 빈번)
- 단순 질문/복잡 작업 구분 없음 (동일한 10턴 루프)
- 서브에이전트 없음 (단일 LLM이 모든 작업 수행)
- 문맥격리 없음 (세션 히스토리 전체 전달)

---

## 2. AI-Q 적용 설계

```
r_agent_chat()
  ├─ 승인 확인 (기존 유지)
  ├─ 프로젝트 매칭 (기존 유지)
  └─ _chat_agent_respond()
       │
       ▼
  ┌─────────────────────────┐
  │  Intent Classifier       │  ← LLM 1회 호출 (분류만)
  │  (GPT-4.1 mini/Kimi)    │
  └────┬──────┬──────┬──────┘
       │      │      │
       ▼      ▼      ▼
  [shallow] [deep] [supervisor]
       │      │      │
       ▼      ▼      ▼
  ┌────────┐ ┌──────────────┐ ┌──────────┐
  │Shallow │ │ Deep Agent   │ │Supervisor│
  │Agent   │ │              │ │(기존)    │
  │        │ │ ┌──────────┐ │ │          │
  │10턴    │ │ │ Planner  │ │ │          │
  │5도구   │ │ │ (작업분해)│ │ │          │
  │빠른응답│ │ └─────┬────┘ │ │          │
  │        │ │       ▼      │ │          │
  │        │ │ ┌──────────┐ │ │          │
  │        │ │ │Researcher│ │ │          │
  │        │ │ │(실행+수집)│ │ │          │
  │        │ │ └─────┬────┘ │ │          │
  │        │ │       ▼      │ │          │
  │        │ │ 리포트 생성  │ │          │
  │        │ │ + CLI Job 큐 │ │          │
  └────────┘ └──────────────┘ └──────────┘
```

---

## 3. Intent Classifier 설계

**목적**: 사용자 메시지를 shallow/deep/supervisor로 분류.
**방법**: LLM 1회 호출 (JSON 출력), 200토큰 이내.

```python
_INTENT_PROMPT = """사용자 메시지를 분류하세요. JSON으로만 응답:
{"intent": "shallow|deep|supervisor", "reason": "한줄 이유"}

분류 기준:
- shallow: 간단한 질문, 현황 조회, 정보 검색, 코드 읽기
- deep: 복잡한 구현, 다단계 분석, 리포트 작성, 아키텍처 설계, 여러 파일 수정
- supervisor: 검수, QA, 리뷰, 판정, 평가

메시지: {message}"""
```

**폴백**: LLM 실패 시 기존 키워드 분류 유지.

---

## 4. Shallow Agent 설계

기존 `_chat_agent_respond`의 10턴 루프를 제한 강화.

| 항목 | 값 |
|------|---|
| 최대 LLM 턴 | 10 |
| 최대 도구 호출 | 5 |
| 응답 시간 목표 | 10초 |
| 토큰 버짓 | input 4K + output 2K |
| 도구 | 칸반 API 7개 (list_teams, get_board, get_stats, list_tickets, list_activity, list_artifacts, send_message) |

```python
def _shallow_agent(session_id, message, project, project_path):
    """AI-Q Shallow Agent: 빠른 도구 호출 기반 응답."""
    MAX_TURNS = 10
    MAX_TOOL_CALLS = 5
    tool_call_count = 0

    for turn in range(MAX_TURNS):
        response = _llm_call(messages, tools=_SHALLOW_TOOLS)
        if response.stop_reason == "end_turn":
            return response.text
        if response.stop_reason == "tool_use":
            tool_call_count += 1
            if tool_call_count > MAX_TOOL_CALLS:
                return response.text + "\n(도구 호출 한도 초과)"
            result = _execute_tool(response.tool)
            messages.append(tool_result(result))
    return final_text
```

---

## 5. Deep Agent 설계

### 5.1 Planner 서브에이전트

**역할**: 복잡한 지시를 구조화된 작업 계획으로 분해.
**입력**: 사용자 메시지 + 프로젝트 컨텍스트 (이름, 경로, 최근 팀/티켓)
**출력**: JSON 작업 계획

```python
_PLANNER_PROMPT = """당신은 작업 계획 전문가. 지시를 구조화된 계획으로 분해.
JSON으로만 응답:
{
  "summary": "전체 요약",
  "steps": [
    {
      "id": "S1",
      "task": "구체적 작업",
      "tools_needed": ["read_file", "write_file"],
      "depends_on": [],
      "estimated_turns": 3
    }
  ],
  "total_estimated_turns": 15,
  "needs_cli": true/false
}"""
```

**문맥격리**: Planner는 세션 히스토리 없이, 현재 메시지 + 프로젝트 메타만 수신.

### 5.2 Researcher 서브에이전트

**역할**: Planner의 계획을 순서대로 실행.
**입력**: Planner의 JSON 계획 (step별 실행)
**출력**: 각 step 결과 + 산출물

```python
def _deep_researcher(plan, project_path, session_id):
    """Planner 계획을 step별 실행."""
    results = []
    for step in plan["steps"]:
        # 문맥격리: 해당 step의 task + tools_needed만 전달
        context = {
            "task": step["task"],
            "tools": step["tools_needed"],
            "prior_results": [r["summary"] for r in results]  # 이전 결과 요약만
        }
        result = _execute_step(context, project_path)
        results.append({"step_id": step["id"], "summary": result[:500]})
    return results
```

### 5.3 CLI Job 연동

Deep Agent가 코딩 작업을 판단하면 → cli_jobs 큐에 작업 생성:

```python
if plan["needs_cli"]:
    for step in plan["steps"]:
        if "write_file" in step["tools_needed"]:
            _create_cli_job(project_path, step["task"])
```

---

## 6. 문맥격리 상세

| 에이전트 | 수신하는 컨텍스트 | 수신하지 않는 것 |
|---------|------------------|----------------|
| Classifier | 사용자 메시지 (원문) | 세션 히스토리, 도구 결과 |
| Planner | 메시지 + 프로젝트 메타 | 세션 히스토리, 이전 도구 결과 |
| Researcher | step JSON + 이전 결과 요약 | Planner 내부 추론, 전체 계획 |
| Report Generator | 전체 결과 배열 | 중간 LLM 대화, 도구 원시 출력 |

**토큰 절감 예측**: 현재 대비 40-60% 절감 (불필요한 컨텍스트 제거)

---

## 7. 도구 자동발견

현재 27개 MCP 도구를 역할별로 그룹화:

```python
_SHALLOW_TOOLS = [
    "list_teams", "get_board", "get_stats",
    "list_tickets", "list_activity",
    "list_artifacts", "send_message"
]  # 7개 — 조회 위주

_DEEP_TOOLS = _SHALLOW_TOOLS + [
    "create_ticket", "update_ticket_status",
    "create_artifact", "dispatch_agent",
    "read_file", "write_file", "list_files",
    "run_command", "git_log", "git_diff"
]  # 17개 — 실행 포함

_SUPERVISOR_TOOLS = [
    "supervisor_review", "supervisor_stats",
    "list_tickets", "get_board"
]  # 4개
```

---

## 8. 옵저버빌리티 데이터 모델

```sql
CREATE TABLE agent_traces (
    trace_id TEXT PRIMARY KEY,
    session_id TEXT,
    intent TEXT,           -- shallow/deep/supervisor
    agent_type TEXT,       -- classifier/planner/researcher/report
    step_index INTEGER,
    tool_name TEXT,
    input_tokens INTEGER,
    output_tokens INTEGER,
    latency_ms INTEGER,
    status TEXT,           -- success/error/timeout
    created_at TEXT
);
```

---

## 9. 구현 순서

1. Intent Classifier (r_agent_chat에 추가)
2. Shallow Agent (기존 코드에 제한 적용)
3. Deep Agent Planner (새 함수)
4. Deep Agent Researcher (새 함수)
5. CLI Job 연동 (기존 cli_jobs API 활용)
6. agent_traces 테이블 + 옵저버빌리티 API
7. 웹 대시보드 Agent Trace 뷰
