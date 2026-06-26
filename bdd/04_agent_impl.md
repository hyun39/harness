# BDD-04 — 에이전트(LLM·툴) 테스트 구현 가이드

> **목적**: ReAct·체인·구조화 출력 등 **에이전트 기능**을 Gherkin으로 고정하고, pytest-bdd에서 **LLM·외부 툴을 격리**해 안정적으로 Green을 만드는 패턴  
> **연계**: [`01_writing_guide.md`](./01_writing_guide.md) (시나리오 문장), [`02_fastapi_impl.md`](./02_fastapi_impl.md) (Step·conftest 기본), [`../std/07_ai.md`](../std/07_ai.md) · [`../std/detail/agent.md`](../std/detail/agent.md) (구현 표준)

---

## 테스트 레벨 구분

| 레벨 | 검증 대상 | LLM·툴 | 비고 |
|------|-----------|---------|------|
| 단위 | 툴 함수 1개, 파서, Pydantic 모델 | Mock 불필요 또는 입력만 고정 | 빠른 회귀 |
| 서비스 | `AgentExecutor` / 체인 호출 한 번 | LLM·툴 전부 Mock | 결정론적 출력 |
| BDD (API) | HTTP → 서비스 → 저장/응답 | 서비스 레이어에서 Mock (권장) | `02`와 동일 구조 |

BDD에서는 **비용·플레이크·속도** 때문에 실제 LLM 호출을 쓰지 않는다. 대신 **서비스 진입점 한 곳**을 패치해 고정된 구조화 결과를 돌려준다.

---

## Gherkin 작성 원칙 (에이전트)

| 하지 말 것 | 이유 |
|------------|------|
| `Tavily를 호출하면` / `ReAct 3회 반복 후` | 구현·툴 이름 노출, `01`의 비즈니스 언어 원칙 위반 |
| `gpt-4o-mini가 응답하면` | 모델명은 구현 디테일 |

| 권장 | 예시 |
|------|------|
| 사용자 가치·정책으로 서술 | `섹터 트렌드 분석이 생성된다`, `투자 면책 문구가 포함된다` |
| 예외는 정책 언어 | `외부 분석 생성이 제한되어 안내 메시지가 반환된다` |

---

## 예시 `.feature` (API가 에이전트를 트리거하는 경우)

```gherkin
# specs/features/analysis/sector_trend_agent.feature
# Spec: specs/sp500/business_spec.md
Feature: 섹터 트렌드 LLM 분석

  Background:
    Given 사용자가 analyst 권한으로 로그인되어 있다

  Scenario: Mart 데이터 기반 트렌드 분석이 저장된다
    Given 2026-05-01 거래일의 섹터 Mart 집계가 존재한다
    When 2026-05-01 섹터 트렌드 분석을 요청하면
    Then 분석 상태가 완료로 기록된다
    And 응답에 bullish, bearish, neutral 중 하나의 심리 지표가 포함된다
    And 한국어·영문 요약 필드가 비어 있지 않다
    And 면책 문구가 포함된다

  Scenario: LLM 처리 실패 시 재시도 가능한 오류로 표시된다
    Given 2026-05-02 거래일의 섹터 Mart 집계가 존재한다
    And LLM 분석이 일시 실패하도록 설정되어 있다
    When 2026-05-02 섹터 트렌드 분석을 요청하면
    Then 분석 실패 응답이 반환된다
    And 에러 코드는 AGENT_EXECUTION_FAILED이다
```

시나리오 문장은 프로젝트 도메인에 맞게 바꾸되, **Then**은 검증 가능한 필드·상태 위주로 유지한다.

---

## conftest.py — 에이전트 Mock 전략

### 전략 A: 서비스 함수 한 곳만 패치 (권장)

앱이 `app.services.trend_agent.run_sector_trend` 같은 **단일 진입점**을 두면, BDD는 그 함수만 `AsyncMock`으로 바꾼다.

```python
# tests/bdd/conftest.py
import pytest
from unittest.mock import AsyncMock, patch

from app.schemas.trend import TrendAnalysis  # Pydantic 응답 모델

@pytest.fixture
def fake_trend_analysis() -> TrendAnalysis:
    return TrendAnalysis(
        trend_summary_ko="테스트 요약 KO",
        trend_summary_en="Test summary EN",
        key_drivers=[],
        sentiment="neutral",
        risk_factors=[],
        recommendation_ko="참고용",
        recommendation_en="For reference",
        disclaimer_ko="본 분석은 투자 자문이 아닙니다.",
        disclaimer_en="Not investment advice.",
    )

@pytest.fixture
def agent_should_fail():
    """실패 시나리오용 — step에서 이 fixture를 읽어 분기"""
    return {"value": False}

@pytest.fixture(autouse=True)
def mock_sector_trend_agent(fake_trend_analysis, agent_should_fail):
    async def _run(*args, **kwargs):
        if agent_should_fail["value"]:
            raise RuntimeError("LLM timeout")
        return fake_trend_analysis

    with patch(
        "app.services.trend_agent.run_sector_trend",
        new=AsyncMock(side_effect=_run),
    ) as m:
        yield m
```

실패 시나리오 Step에서만 `agent_should_fail["value"] = True` 로 바꾼다 (아래 Step 예시).

### 전략 B: `AgentExecutor.ainvoke` 직접 패치

진입점이 여러 곳이면 executor 생성 모듈을 패치한다.

```python
@pytest.fixture(autouse=True)
def mock_executor(fake_trend_analysis):
    fake_output = {"output": fake_trend_analysis.model_dump_json()}

    async def _ainvoke(_input):
        return fake_output

    with patch("app.agents.sector.executor") as ex:
        ex.ainvoke = AsyncMock(side_effect=_ainvoke)
        yield ex
```

---

## Step 구현 예시 (pytest-bdd)

```python
# tests/bdd/steps/analysis/sector_trend_agent_steps.py
from pytest_bdd import given, when, then, parsers, scenario

# bdd_features_base_dir = specs/features 이면 feature 경로는 디렉터리 기준 상대
FEATURE = "analysis/sector_trend_agent.feature"


@scenario(FEATURE, "Mart 데이터 기반 트렌드 분석이 저장된다")
def test_sector_trend_saved():
    pass


@scenario(FEATURE, "LLM 처리 실패 시 재시도 가능한 오류로 표시된다")
def test_sector_trend_agent_fail():
    pass


@given(parsers.parse("{date} 거래일의 섹터 Mart 집계가 존재한다"))
def seed_sector_mart(date: str, db_session):
    ...  # factories로 Mart 적재


@given("LLM 분석이 일시 실패하도록 설정되어 있다")
def force_agent_fail(agent_should_fail):
    agent_should_fail["value"] = True


@when(parsers.parse("{date} 섹터 트렌드 분석을 요청하면"))
def request_trend(date: str, client, response_holder):
    response_holder["resp"] = client.post(
        f"/v1/analyses/sector-trend",
        json={"trade_date": date},
    )


@then("분석 상태가 완료로 기록된다")
def assert_completed(response_holder):
    assert response_holder["resp"].status_code == 200
    body = response_holder["resp"].json()
    assert body.get("status") == "completed"


@then(parsers.parse("에러 코드는 {code}이다"))
def assert_error_code(code: str, response_holder):
    body = response_holder["resp"].json()
    assert body["error"]["code"] == code
```

**Then**에서 가능하면 **`TrendAnalysis.model_validate(body["analysis"])`** 로 스키마 일관성까지 검증한다.

---

## 구조화 출력(Pydantic) 검증

```python
from app.schemas.trend import TrendAnalysis

@then("한국어·영문 요약 필드가 비어 있지 않다")
def assert_bilingual_summary(response_holder):
    raw = response_holder["resp"].json()["analysis"]
    model = TrendAnalysis.model_validate(raw)
    assert model.trend_summary_ko.strip()
    assert model.trend_summary_en.strip()


@then("면책 문구가 포함된다")
def assert_disclaimer(response_holder):
    raw = response_holder["resp"].json()["analysis"]
    model = TrendAnalysis.model_validate(raw)
    assert "투자 자문" in model.disclaimer_ko
    assert "investment advice" in model.disclaimer_en.lower()
```

이렇게 하면 **스펙의 필드 정의가 바뀌면 BDD가 함께 깨져** Living Spec에 가깝게 유지된다.

---

## 툴(Tool) 단위 테스트 (BDD 바깥)

ReAct 툴은 **pytest 단위 테스트**에서 입력→출력 포맷만 검증한다. BDD `.feature`에 툴 이름을 넣지 않는다.

```python
def test_search_tool_returns_url_shape():
    out = search_linkedin_profile.invoke({"name": "Jane Doe"})
    assert out.startswith("https://")
```

---

## Spring(Cucumber) — 요지

- `bdd/03_spring_impl.md` 의 **Mock LLM 빈 교체**와 동일하게, 에이전트를 호출하는 **Application Service** 인터페이스에 `@MockBean`을 두고 `willReturn` / `willThrow` 로 시나리오를 나눈다.
- 구조화 응답은 **DTO + Bean Validation assert** 로 검증한다.

---

## CI·품질

- 에이전트 BDD도 **동일 워크플로**에서 `pytest tests/bdd/` 로 실행한다 (`02` 참조).
- `gov/05_quality_gates.md` 에 맞춰, 에이전트 코드 경로에도 커버리지·SAST를 적용한다.
- 실제 LLM 스모크 테스트는 **별도 수동/야간 파이프라인**으로 분리하는 것을 권장한다.

---

## 체크리스트

- [ ] 시나리오에 툴·모델 이름이 노출되지 않는다.
- [ ] LLM·외부 검색은 기본적으로 Mock이며, 실패 시나리오가 있다.
- [ ] 응답은 Pydantic(또는 동등 스키마)으로 검증한다.
- [ ] `max_iterations`·타임아웃·면책 문구 등 **정책 Then**이 한 개 이상 있다.
