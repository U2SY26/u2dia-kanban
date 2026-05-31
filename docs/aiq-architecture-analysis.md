# NVIDIA AI-Q Deep Agent 아키텍처 분석 보고서

**작성일**: 2026-04-01
**티켓**: T-96C4E8
**출처**: https://developer.nvidia.com/blog/how-to-build-deep-agents-for-enterprise-search-with-nvidia-ai-q-and-langchain/
**GitHub**: https://github.com/NVIDIA-AI-Blueprints/aiq

---

## 1. AI-Q 개요

NVIDIA AI-Q Blueprint는 기업 내부 데이터를 통합 검색하는 오픈소스 에이전트 플랫폼.
LangChain Deep Agents + NeMo Agent Toolkit 기반.

**핵심 가치**: 빠른 인용 답변(Shallow) + 심층 분석 보고서(Deep) 자동 라우팅.

---

## 2. 아키텍처 구조

```
사용자 질문
    │
    ▼
┌──────────────────┐
│  Orchestrator    │  ← 의도 분류 (shallow vs deep)
│  (LangGraph)     │
└────┬────────┬────┘
     │        │
     ▼        ▼
┌─────────┐ ┌──────────────────────────┐
│ Shallow │ │      Deep Agent          │
│ Agent   │ │  ┌──────────┐            │
│         │ │  │ Planner  │→ JSON Plan │
│ 10턴    │ │  └──────────┘            │
│ 5도구   │ │       │                  │
│ 빠른응답│ │       ▼                  │
│         │ │  ┌──────────┐            │
│         │ │  │Researcher│→ 실행+수집 │
│         │ │  └──────────┘            │
│         │ │       │                  │
│         │ │       ▼                  │
│         │ │  리포트 생성             │
└─────────┘ └──────────────────────────┘
```

---

## 3. Shallow vs Deep Agent 비교

| 항목 | Shallow Agent | Deep Agent |
|------|--------------|-----------|
| LLM 턴 제한 | 최대 10회 | 무제한 (recursion_limit: 1000) |
| 도구 호출 제한 | 최대 5회 | 무제한 |
| 아키텍처 | 단일 루프 도구 호출 | 오케스트레이터+플래너+리서처 |
| 응답 속도 | 초 단위 | 분 단위 (장문 리포트) |
| 사용 사례 | "CUDA란?" 간단한 질문 | "RAG vs Long-Context 비교 분석" |
| 출력 형태 | 짧은 인용 답변 | 구조화된 리포트 (목차+섹션+인용) |

---

## 4. create_deep_agent Factory

```python
create_deep_agent(
    model=orchestrator_llm,        # 오케스트레이터 LLM
    system_prompt=orchestrator_prompt,
    tools=tools_list,              # 사용 가능한 도구 목록
    subagents=subagents_array,     # 서브에이전트 배열
    middleware=custom_middleware,
    skills=skills_list
).with_config({"recursion_limit": 1000})
```

---

## 5. 문맥격리 (Context Isolation)

**핵심 원칙**: 서브에이전트는 구조화된 JSON 페이로드만 수신.
오케스트레이터의 사고 토큰이나 플래너의 내부 추론을 받지 않음.

### Planner 출력 (JSON)

```json
{
  "report_title": "보고서 제목",
  "report_toc": [
    {"id": "1", "title": "섹션명", "subsections": [...]}
  ],
  "queries": [
    {
      "id": "q1",
      "query": "검색어",
      "target_sections": ["섹션명"],
      "rationale": "이 검색이 필요한 이유"
    }
  ]
}
```

**효과**:
- "Lost in the Middle" 현상 방지
- 토큰 비용 최적화 (불필요한 컨텍스트 제거)
- 서브에이전트 독립성 보장

---

## 6. NeMo Agent Toolkit 도구 등록

```python
from nat.builder.builder import Builder
from nat.builder.function_info import FunctionInfo
from nat.cli.register_workflow import register_function
from nat.data_models.function import FunctionBaseConfig

class InternalKBConfig(FunctionBaseConfig, name="internal_kb"):
    api_url: str = Field(description="KB API URL")
    api_key: SecretStr = Field(description="API Key")
    max_results: int = Field(default=5)

@register_function(config_type=InternalKBConfig)
async def internal_kb(config: InternalKBConfig, builder: Builder):
    async def search(query: str) -> str:
        """내부 KB 검색"""
        results = await call_kb_api(config.api_url, query)
        return format_results(results)
    yield FunctionInfo.from_fn(search, description=search.__doc__)
```

### YAML 설정

```yaml
functions:
  internal_kb_tool:
    _type: internal_kb
    api_url: "https://kb.internal.company.com/api/v1"
    api_key: ${INTERNAL_KB_API_KEY}
    max_results: 10

  shallow_research_agent:
    _type: shallow_research_agent
    llm: nemotron_llm
    tools: [web_search_tool]
    max_llm_turns: 10
    max_tool_calls: 5

  deep_research_agent:
    _type: deep_research_agent
    orchestrator_llm: gpt-5
    planner_llm: nemotron_llm
    researcher_llm: nemotron_llm
    max_loops: 2
    tools: [advanced_web_search_tool]
```

**도구 발견**: LLM이 함수 docstring으로 도구 호출 시점 자동 판단.

---

## 7. 인프라 구성

| 서비스 | 포트 | 역할 |
|--------|------|------|
| aiq-research-assistant | 8000 | FastAPI 백엔드 |
| postgres | 5432 | 상태/체크포인트 저장 |
| frontend | 3000 | Next.js 웹 UI |

```bash
docker compose -f deploy/compose/docker-compose.yaml up --build
```

**요구사항**: Python 3.11+, NVIDIA API Key, uv, Docker

---

## 8. 옵저버빌리티 (LangSmith)

```yaml
general:
  telemetry:
    tracing:
      langsmith:
        _type: langsmith
        project: aiq-demo
        api_key: ${LANGSMITH_API_KEY}
```

- 에이전트 실행 경로 시각화
- per-step 토큰 사용량 추적
- 지연 시간/에러율 모니터링

---

## 9. 칸반 시스템 적용 계획

### 9.1 현재 → AI-Q 적용 매핑

| 현재 칸반 시스템 | AI-Q 적용 후 |
|-----------------|-------------|
| 유디 1단계 응답 (r_agent_chat) | Shallow Agent (10턴, 5도구) |
| 복잡한 작업 → CLI 수동 실행 | Deep Agent (플래너→리서처→리포트) |
| MCP 27개 도구 수동 호출 | 도구 자동발견 (docstring 기반) |
| 토큰 총합만 추적 | per-step 옵저버빌리티 |
| 서브에이전트 전체 컨텍스트 전달 | 문맥격리 (JSON payload) |
| GPT→Kimi→Ollama 단순 폴백 | 의도 분류 → 적절한 에이전트 라우팅 |

### 9.2 구현 우선순위

1. **의도 분류기** — 사용자 질문 → shallow/deep 자동 분류
2. **Shallow Agent 리팩터링** — 기존 채팅에 턴/도구 제한 적용
3. **Deep Agent 신규 구현** — 플래너+리서처+리포트 생성기
4. **도구 자동발견** — MCP 도구를 docstring 기반으로 LLM에 자동 제공
5. **옵저버빌리티** — 실행 경로 + 토큰 breakdown 대시보드

### 9.3 기술적 차이점 (적용 시 조정 필요)

| AI-Q (원본) | 칸반 (적용) |
|------------|-----------|
| LangChain/LangGraph | 순수 Python (표준 라이브러리) |
| PostgreSQL | SQLite WAL |
| NeMo Agent Toolkit | 자체 MCP 도구 시스템 |
| Docker Compose | 단일 server.py |
| NVIDIA NIM API | GPT-4.1 + Kimi K2.5 + Ollama |
| FastAPI | 내장 HTTP Server |

---

## 10. 결론

AI-Q의 핵심 패턴(의도 분류, shallow/deep 라우팅, 문맥격리, 도구 자동발견)은
외부 의존성 없이 server.py 단일 파일 내에서 구현 가능.
LangChain 프레임워크를 사용하지 않고, 동일한 아키텍처 패턴만 차용하여 적용.
