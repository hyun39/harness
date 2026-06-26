# Common Spec — Agentic Agent

---

## 에이전트 패턴 분류

| 패턴 | 구조 | 적합한 상황 |
|------|------|------------|
| ReAct | Thought → Action → Observation 루프 | 웹 검색·API 호출 등 외부 툴이 필요한 단계적 추론 |
| Chain-of-Thought | 추론 체인만, 툴 없음 | 단순 텍스트 변환·분류 |
| Plan-and-Execute | 플래너 + 실행자 분리 | 장기 태스크, 단계 병렬 실행 |
| Multi-Agent | 에이전트 간 메시지 패싱 | 역할 분리가 명확한 복잡한 워크플로우 |

---

## ReAct 루프 구조

```
입력 프롬프트
  └─ Thought:  무엇을 해야 하는지 추론
  └─ Action:   툴 이름 + 입력값 결정
  └─ Observation: 툴 실행 결과 수신
  └─ (반복 또는) Final Answer
```

**종료 조건**: `Final Answer` 토큰 감지 또는 `max_iterations` 도달

---

## 툴(Tool) 설계 원칙

| 원칙 | 내용 |
|------|------|
| 단일 책임 | 툴 1개 = 기능 1개. 복합 동작은 별도 툴로 분리 |
| 명확한 description | LLM이 툴 선택 근거로 사용 — 언제 쓰는지 명시 |
| 결정론적 출력 | 같은 입력 → 같은 포맷 출력. 파싱 실패 방지 |
| 오류 반환 | 예외를 throw하지 않고 에러 메시지 문자열로 반환 → 에이전트가 재시도 가능 |

```python
# 툴 description 예시
Tool(
    name="search_linkedin_profile",
    func=search_fn,
    description=(
        "Use when you need to find a person's LinkedIn profile URL. "
        "Input: full name of the person. "
        "Output: LinkedIn profile URL string."
    ),
)
```

---

## 프롬프트 설계

### 시스템 프롬프트 핵심 요소
1. **역할 정의** — 에이전트가 무엇을 하는 존재인지
2. **출력 포맷 강제** — `Final Answer: <값만>` 형태로 지정
3. **제약 조건** — 허용되지 않는 동작 명시
4. **예시(Few-shot)** — 복잡한 추론이 필요한 경우

### 출력 제약 패턴
```
In your Final Answer, return ONLY the {output_type}.
Do not include any explanation or additional text.
```

---

## AgentExecutor 설정

| 파라미터 | 권장값 | 이유 |
|---------|--------|------|
| `max_iterations` | 5~10 | 무한 루프 방지 |
| `max_execution_time` | 30~60s | 타임아웃 보장 |
| `handle_parsing_errors` | `True` | 파싱 실패 시 자동 재시도 |
| `early_stopping_method` | `"generate"` | iterations 초과 시 강제 답변 생성 |
| `verbose` | 개발: True / 운영: False | |

---

## 에러 처리 계층

```
AgentExecutor
  ├─ handle_parsing_errors=True   → LLM 출력 파싱 실패 재시도
  ├─ max_iterations               → 루프 탈출
  └─ 호출자(서비스 레이어)
       └─ try/except OutputParserException  → Fallback 값 반환
       └─ try/except TimeoutError           → 사용자 에러 응답
```

---

## 관찰성(Observability)

| 항목 | 수집 대상 | 도구 |
|------|----------|------|
| 트레이싱 | Thought/Action/Observation 전체 | LangSmith, LangFuse |
| 지연 시간 | 툴 호출별 소요 시간 | 커스텀 콜백 |
| 토큰 수 | 입력/출력 토큰 | `on_llm_end` 콜백 |
| 툴 호출 횟수 | 에이전트 실행당 | `on_tool_end` 콜백 |

```python
# LangChain 콜백 예시
from langchain.callbacks import StdOutCallbackHandler
agent_executor = AgentExecutor(..., callbacks=[StdOutCallbackHandler()])
```

---

## 비동기 실행

| 메서드 | 용도 |
|--------|------|
| `agent.invoke()` | 동기 단일 실행 |
| `await agent.ainvoke()` | 비동기 단일 실행 |
| `agent.batch()` | 동기 병렬 (리스트 입력) |
| `await agent.abatch()` | 비동기 병렬 |

병렬 에이전트 실행 시 `asyncio.gather()` + `abatch()` 조합 권장

---

## 모델 선택 기준

| 모델 | 적합한 에이전트 역할 |
|------|-------------------|
| gpt-4o / claude-opus | 복잡한 다단계 추론, 툴 선택 정확도 중요 |
| gpt-4o-mini / claude-haiku | URL 탐색 등 단순 검색 반복 작업 |
| gpt-3.5-turbo | 단순 포맷 변환 체인 (에이전트보다 체인 사용 권장) |

---

## 미결 기술 과제

- [ ] ReAct vs Function Calling 방식 성능 비교 기준 수립
- [ ] 툴 실행 결과 크기 제한 전략 (토큰 초과 방지)
- [ ] 멀티 에이전트 간 공유 메모리(State) 설계 패턴
- [ ] 에이전트 실행 결과 캐싱 키 설계 (입력 동일성 판단 기준)
