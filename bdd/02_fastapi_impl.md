# BDD-02 — FastAPI pytest-bdd 구현 가이드

> **목적**: `.feature` 파일의 Step을 FastAPI + pytest-bdd로 구현하는 패턴  
> **원본 참조**: `enterprise/01.03_std_executable_specification.md`

---

## 의존성 설치

```bash
uv add --dev pytest-bdd pytest-asyncio httpx testcontainers
# 또는
pip install pytest-bdd pytest-asyncio httpx testcontainers
```

---

## 프로젝트 구조

```
tests/bdd/
├── conftest.py               ← 공유 fixtures (DB, 클라이언트, 토큰)
├── features/
│   └── analysis/
│       └── trend_analysis.feature
└── steps/
    └── analysis/
        └── trend_analysis_steps.py
```

---

## conftest.py — 공유 Fixtures

```python
# tests/bdd/conftest.py
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer
from app.main import app
from app.core.database import get_db, create_test_session

@pytest.fixture(scope="session")
def postgres():
    with PostgresContainer("postgres:15") as pg:
        yield pg

@pytest.fixture(scope="function")
def db_session(postgres):
    """테스트마다 독립적인 DB 세션 (트랜잭션 롤백)"""
    session = create_test_session(postgres.get_connection_url())
    yield session
    session.rollback()
    session.close()

@pytest.fixture(scope="function")
def client(db_session):
    """DB 의존성 오버라이드된 테스트 클라이언트"""
    app.dependency_overrides[get_db] = lambda: db_session
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()

@pytest.fixture
def analyst_token():
    """analyst 역할 JWT (테스트용 고정 토큰)"""
    return "test-analyst-token"

@pytest.fixture
def response_holder():
    """Scenario 내 응답 공유용 딕셔너리"""
    return {}
```

---

## Step 구현 패턴

```python
# tests/bdd/steps/analysis/trend_analysis_steps.py
from pytest_bdd import given, when, then, parsers, scenario
from app.tests.factories import seed_mart_data, seed_pipeline_status

# --- Given ---

@given(parsers.parse("{date} 거래일의 데이터 수집이 완료된 상태이고"))
def pipeline_completed(date: str, db_session):
    seed_mart_data(db_session, trade_date=date)
    seed_pipeline_status(db_session, trade_date=date, status="completed")

@given("사용자가 분석가 권한으로 로그인되어 있다")
def analyst_logged_in(client, analyst_token):
    client.headers.update({"Authorization": f"Bearer {analyst_token}"})

# --- When ---

@when(parsers.parse("{date} 트렌드 분석을 조회하면"))
def call_trend_analysis(date: str, client, response_holder):
    response_holder["resp"] = client.get(
        f"/v1/analyses/trend?trade_date={date}"
    )

# --- Then ---

@then(parsers.parse("{count:d}개 Sector의 분석 결과가 반환된다"))
def check_sector_count(count: int, response_holder):
    data = response_holder["resp"].json()
    assert response_holder["resp"].status_code == 200
    assert len(data["analyses"]) == count

@then(parsers.parse("응답 코드는 {code:d}이어야 한다"))
def check_status_code(code: int, response_holder):
    assert response_holder["resp"].status_code == code

@then(parsers.parse("에러 코드는 {error_code}이어야 한다"))
def check_error_code(error_code: str, response_holder):
    data = response_holder["resp"].json()
    assert data["error"]["code"] == error_code
```

---

## pytest.ini 설정

```ini
# pytest.ini
[pytest]
addopts = -v --tb=short
bdd_features_base_dir = specs/features
asyncio_mode = auto
```

---

## CI 연동

```yaml
# .github/workflows/ci.yml
- name: BDD Tests
  run: |
    pytest tests/bdd/ \
      --tb=short \
      -q \
      --junitxml=reports/bdd-results.xml
  env:
    DATABASE_URL: ${{ env.TEST_DATABASE_URL }}

- name: Upload BDD Report
  uses: actions/upload-artifact@v4
  with:
    name: bdd-report
    path: reports/bdd-results.xml
```

---

## Scenario 연결 방법

각 `.feature` 파일의 Scenario를 step 파일에서 `@scenario` 데코레이터로 연결.

```python
# 방법 1: 파일 레벨 자동 수집 (권장)
# pytest-bdd가 feature 파일을 자동으로 수집

# 방법 2: 명시적 연결
from pytest_bdd import scenario

@scenario("features/analysis/trend_analysis.feature",
          "거래일 트렌드 분석 정상 조회")
def test_trend_analysis_happy_path():
    pass
```

---

## Mock LLM 패턴 (외부 LLM 격리)

```python
# conftest.py — LLM 호출 Mock
from unittest.mock import patch, AsyncMock

@pytest.fixture(autouse=True)
def mock_llm_chain():
    with patch("app.chains.custom_chains.get_summary_chain") as mock:
        mock.return_value.ainvoke = AsyncMock(return_value=MockSummary(
            summary="Test summary",
            facts=["fact1", "fact2"]
        ))
        yield mock
```

ReAct·구조화 출력·툴 격리까지 포함한 **에이전트 전용 BDD**는 [`04_agent_impl.md`](./04_agent_impl.md) 를 참조한다.
