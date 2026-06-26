# spec_new 실행 가이드

> **목표**: `gov/` → `bdd/` → `std/` 순서로 BDD/SDD 사이클을 실제로 돌리는 방법  
> **예시 프로젝트**: S&P 500 Daily 주가 분석 서비스  
> **소요 시간**: 환경 설정 1~2일 + 기능당 BDD 사이클 2~4시간

---

## 전체 흐름 한눈에 보기

```
[1회 설정]                        [매 기능마다]
────────────────                   ─────────────────────────────────────
환경 구성                           비즈니스 스펙 작성    (30분)
  └─ Docker Compose                  └─ gov/01 규칙 준수
  └─ 의존성 설치                     └─ templates/business_spec.md 복사
  └─ CI 파이프라인                    ↓
  └─ 브랜치 보호                    .feature 작성          (30분)
                                     └─ bdd/01 가이드 참조
                                     └─ templates/feature.feature 복사
                                     ↓
                                    BDD 실행 → Red        (즉시)
                                     ↓
                                    Step 구현              (1~2시간)
                                     └─ bdd/02 or bdd/03
                                     ↓
                                    코드 구현              (2~8시간)
                                     └─ std/ 참조
                                     ↓
                                    BDD 실행 → Green
                                     ↓
                                    PR → CI 게이트 통과
```

---

## PART 1 — 환경 설정 (1회)

### 1-1. 전제 조건 확인

```bash
# 버전 확인
python --version          # 3.11+
docker --version          # 24+
docker compose version    # v2+
node --version            # 20 LTS (프론트엔드 있을 때)
git --version             # 2.40+

# Kubernetes 로컬 개발 시 (선택)
kubectl version --client  # 1.28+
# kind / minikube / k3d 중 하나

# 없으면 설치
pip install uv            # Python 패키지 관리자 (pipenv 대안)
```

---

### 1-2. 프로젝트 디렉토리 구조 생성

```bash
# 프로젝트 루트 생성 (예: sp500-platform)
mkdir -p sp500-platform && cd sp500-platform

# 표준 디렉토리 구조 (specs/methodology/std/05_infra.md 참조)
mkdir -p \
  apps/api/app/{routers,services,schemas,core,clients} \
  apps/api/tests/bdd/{features/analysis,steps/analysis} \
  apps/api/migrations \
  apps/airflow/dags \
  apps/frontend/src \
  docs/adr \
  specs \
  .github/workflows

# spec_new 연결 (심링크 또는 복사)
ln -s /path/to/spec_new ./spec_new
```

---

### 1-3. 컨테이너 런타임 (Docker Compose 또는 Kubernetes)

로컬에서 **Compose 한 벌**로도 되고, **로컬 Kubernetes(kind / minikube / k3d)** 로도 같은 구성을 올릴 수 있다. 팀 표준·플랫폼 엔지니어링 정책에 맞게 하나를 고른다. 운영·GitOps 배포는 `specs/methodology/std/05_infra.md` · `specs/edit/enterprise` GitOps 문서를 따른다.

#### A. Docker Compose (로컬 기본)

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: sp500
      POSTGRES_USER: app
      POSTGRES_PASSWORD: localpass
    ports: ["5432:5432"]
    volumes: ["postgres_data:/var/lib/postgresql/data"]

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

  api:
    build: ./api
    ports: ["8000:8000"]
    environment:
      DATABASE_URL: postgresql+asyncpg://app:localpass@postgres:5432/sp500
      REDIS_URL: redis://redis:6379
    env_file: [.env.local]
    depends_on: [postgres, redis]
    volumes: ["./api:/app"]    # 핫리로드

volumes:
  postgres_data:
```

```bash
# .env.local (git에 커밋하지 않음)
OPENAI_API_KEY=sk-...
TAVILY_API_KEY=tvly-...
```

#### B. Kubernetes — 로컬 클러스터

**용도**: Compose와 동일한 역할(PostgreSQL, Redis, API)을 **파드/서비스**로 검증하거나, Helm·Kustomize·GitOps 연습용 최소 스케치.

**전제**: `kubectl` + 로컬 클러스터 1개(kind 권장). API 이미지는 로컬 빌드 후 클러스터에 로드한다.

```bash
# 예: kind
kind create cluster --name sp500

cd apps/api && docker build -t sp500-api:local . && cd ..
kind load docker-image sp500-api:local --name sp500

kubectl apply -f k8s/local/
kubectl -n sp500-dev wait --for=condition=available deployment/api --timeout=120s
kubectl -n sp500-dev port-forward svc/api 8000:8000
```

**매니페스트 예시** (`k8s/local/` — 레포에 두고 `.gitignore`로 시크릿만 제외):

```yaml
# k8s/local/00-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: sp500-dev
---
# k8s/local/01-secrets.yaml  ← 실제 키는 로컬에서만 채우고 커밋하지 않음
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: sp500-dev
type: Opaque
stringData:
  password: localpass
---
apiVersion: v1
kind: Secret
metadata:
  name: api-secrets
  namespace: sp500-dev
type: Opaque
stringData:
  OPENAI_API_KEY: "sk-replace-me"
  TAVILY_API_KEY: "tvly-replace-me"
---
# k8s/local/02-postgres.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: sp500-dev
spec:
  replicas: 1
  selector:
    matchLabels: { app: postgres }
  template:
    metadata:
      labels: { app: postgres }
    spec:
      containers:
        - name: postgres
          image: postgres:15
          ports: [{ containerPort: 5432 }]
          env:
            - { name: POSTGRES_DB, value: sp500 }
            - { name: POSTGRES_USER, value: app }
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef: { name: postgres-secret, key: password }
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: sp500-dev
spec:
  selector: { app: postgres }
  ports: [{ port: 5432, targetPort: 5432 }]
---
# k8s/local/03-redis.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: sp500-dev
spec:
  replicas: 1
  selector:
    matchLabels: { app: redis }
  template:
    metadata:
      labels: { app: redis }
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports: [{ containerPort: 6379 }]
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: sp500-dev
spec:
  selector: { app: redis }
  ports: [{ port: 6379, targetPort: 6379 }]
---
# k8s/local/04-api.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: sp500-dev
spec:
  replicas: 1
  selector:
    matchLabels: { app: api }
  template:
    metadata:
      labels: { app: api }
    spec:
      containers:
        - name: api
          image: sp500-api:local
          imagePullPolicy: IfNotPresent
          ports: [{ containerPort: 8000 }]
          env:
            - name: DATABASE_URL
              value: postgresql+asyncpg://app:localpass@postgres.sp500-dev.svc.cluster.local:5432/sp500
            - name: REDIS_URL
              value: redis://redis.sp500-dev.svc.cluster.local:6379
            - name: OPENAI_API_KEY
              valueFrom:
                secretKeyRef: { name: api-secrets, key: OPENAI_API_KEY }
            - name: TAVILY_API_KEY
              valueFrom:
                secretKeyRef: { name: api-secrets, key: TAVILY_API_KEY }
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: sp500-dev
spec:
  selector: { app: api }
  ports: [{ port: 8000, targetPort: 8000 }]
```

| 항목 | 참고 |
|------|------|
| 데이터 영속성 | 위 PostgreSQL은 **로컬 검증용**. PVC·백업·고가용은 운영 가이드대로 별도 설계한다. |
| 시크릿 | `01-secrets.yaml` 은 예시이며, 실무에서는 Sealed Secrets / External Secrets / 클라우드 Secret Manager를 쓴다. |
| minikube / k3d | `kind load` 대신 `minikube image load` · `k3d image import` 등 클러스터별 이미지 로드 명령을 쓴다. |

---

### 1-4. Python 의존성 설치 (FastAPI 기준)

```bash
cd apps/api

# uv 사용
uv init
uv add fastapi uvicorn sqlalchemy asyncpg alembic pydantic-settings
uv add --dev pytest pytest-bdd pytest-asyncio httpx \
              testcontainers coverage pytest-cov

# 또는 pipenv
pipenv install fastapi uvicorn sqlalchemy asyncpg alembic
pipenv install --dev pytest pytest-bdd httpx testcontainers
```

```ini
# apps/api/pytest.ini
[pytest]
addopts = -v --tb=short
bdd_features_base_dir = specs/features
asyncio_mode = auto
```

---

### 1-5. CI 파이프라인 설정

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with: { python-version: "3.11" }

      - name: Install
        run: pip install uv && uv sync --dev

      - name: Lint
        run: uv run ruff check . && uv run black --check .

      - name: Unit + BDD Tests
        run: |
          uv run pytest tests/ \
            --cov=app \
            --cov-fail-under=80 \
            --junitxml=reports/test-results.xml
        env:
          DATABASE_URL: postgresql://app:localpass@localhost:5432/sp500

      - name: Security Scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          severity: HIGH,CRITICAL
          exit-code: 1

    services:
      postgres:
        image: postgres:15
        env: { POSTGRES_PASSWORD: localpass, POSTGRES_DB: sp500 }
        options: --health-cmd pg_isready
```

---

### 1-6. GOV 1회 설정: 브랜치 보호 + PR 템플릿

```bash
# GitHub 브랜치 보호는 UI에서 설정:
#   → 코드 변경이 반드시 리뷰 프로세스를 거치도록 강제한다.
#
# Settings → Branches → Add ruleset
#   → 저장소 Settings 탭 > Branches 메뉴 > "Add ruleset" 버튼 클릭.
#   → Ruleset name: "main protection" 등 이름 입력 후 저장.
#
# - Require pull request: on
#   → main 브랜치에 직접 push 금지. 반드시 PR을 통해서만 머지 가능.
#   → "Required approvals" 를 1 이상으로 설정하면 동료 리뷰도 강제된다.
#
# - Required status checks: CI / quality
#   → PR 머지 전 GitHub Actions의 "CI / quality" 잡이 반드시 green이어야 한다.
#   → lint, BDD 테스트, 커버리지 80%, 보안 스캔이 모두 통과해야 머지 버튼 활성화.
#   → 잡 이름은 ci.yml 의 `jobs:` 키(quality)와 일치해야 한다.
#
# - Restrict deletions: on
#   → main 브랜치 삭제 금지. 실수로 브랜치를 지우는 사고를 방지한다.
```

```markdown
<!-- .github/pull_request_template.md -->
## 변경 내용

## GOV 체크리스트 (gov/01_requirements.md)

- [ ] 비즈니스 스펙 작성됨 (`specs/` 내)
- [ ] .feature 파일 작성됨 (`specs/features/` 내)
- [ ] 모든 Scenario Step 구현됨
- [ ] 커버리지 80% 이상

## ADR 필요 여부 (gov/02_adr.md)

- [ ] 신규 기술 도입 없음 (필요 없음)
- [ ] ADR 작성됨: `docs/adr/ADR-NNNN-*.md`
```

---

## PART 2 — BDD/SDD 개발 사이클 (매 기능마다)

> **예시**: "거래일 트렌드 분석 조회" 기능 개발

---

### 2-1. 비즈니스 스펙 작성

**소요 시간**: 30분  
**참조**: `specs/methodology/gov/01_requirements.md`, `specs/methodology/bdd/templates/business_spec.md`

```bash
# 템플릿 복사
cp specs/methodology/bdd/templates/business_spec.md \
   specs/trend_analysis_spec.md
```

핵심 작성 항목:
```markdown
## 배경 및 목적
분석가가 매 거래일 Sector 트렌드를 파악하려고 할 때,
수작업으로 주가 데이터를 취합해야 하는 문제가 있다.
→ LLM이 자동 분석한 결과를 단일 화면에서 즉시 조회할 수 있게 한다.

## 기능 요건
- [ ] FR-01: 거래일 날짜로 11개 Sector 트렌드 분석 조회 가능
- [ ] FR-02: 비거래일 조회 시 명확한 에러 반환
- [ ] FR-03: 분석 미완료 시 진행 중 상태 반환

## 인수기준 (Gherkin — .feature에 그대로 복사)
Feature: 트렌드 분석 조회

  Scenario: 거래일 트렌드 분석 정상 조회        ← FR-01
    Given 2026-05-01 거래일의 분석이 완료된 상태이고
    And 사용자가 analyst 권한으로 로그인되어 있다
    When 2026-05-01 트렌드 분석을 조회하면
    Then 11개 Sector 결과가 반환된다
    And 각 결과에 sentiment 값이 포함된다

  Scenario: 비거래일 조회 시 에러 반환           ← FR-02
    Given 2026-05-03은 비거래일이다
    When 2026-05-03 트렌드 분석을 조회하면
    Then 요청이 거부된다
    And 에러 코드는 NON_TRADING_DAY이다
```

**DoR 체크**: `gov/01_requirements.md` 필수 항목 모두 충족했는가 확인

---

### 2-2. .feature 파일 작성

**소요 시간**: 15분  
**참조**: `specs/methodology/bdd/01_writing_guide.md`, `specs/methodology/bdd/templates/feature.feature`

```bash
cp specs/methodology/bdd/templates/feature.feature \
   specs/features/analysis/trend_analysis.feature
```

```gherkin
# specs/features/analysis/trend_analysis.feature

# Spec: specs/trend_analysis_spec.md
# AC:   FR-01, FR-02, FR-03
Feature: 트렌드 분석 조회

  Scenario: 거래일 트렌드 분석 정상 조회
    Given 2026-05-01 거래일의 분석이 완료된 상태이고
    And 사용자가 analyst 권한으로 로그인되어 있다
    When 2026-05-01 트렌드 분석을 조회하면
    Then 11개 Sector 결과가 반환된다
    And 각 결과에 sentiment 값이 포함된다

  Scenario: 비거래일 조회 시 에러 반환
    Given 2026-05-03은 비거래일이다
    When 2026-05-03 트렌드 분석을 조회하면
    Then 요청이 거부된다
    And 에러 코드는 NON_TRADING_DAY이다

  Scenario: 분석 미완료 시 진행 중 상태 반환
    Given 2026-05-01 거래일의 분석이 진행 중이다
    When 2026-05-01 트렌드 분석을 조회하면
    Then 처리 중 응답이 반환된다
    And is_complete 값은 false이다
```

---

### 2-3. BDD 테스트 실행 → Red 확인

**소요 시간**: 5분  
**목적**: Step이 없어서 실패하는 것을 확인 (정상)

```bash
cd apps/api
docker compose up -d postgres

uv run pytest tests/bdd/ -v
```

**예상 출력**:
```
FAILED specs/features/analysis/trend_analysis.feature
       :: 거래일 트렌드 분석 정상 조회
       StepDefinitionNotFoundError:
         Step "2026-05-01 거래일의 분석이 완료된 상태이고" 에 대한
         Step Definition을 찾을 수 없습니다.
```

이 실패가 **정상**입니다. Step을 만들러 이동합니다.

---

### 2-4. conftest.py 작성 (공유 Fixture)

**참조**: `specs/methodology/bdd/02_fastapi_impl.md`

```python
# apps/api/tests/bdd/conftest.py
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer
from unittest.mock import AsyncMock, patch

from app.main import app
from app.core.database import get_db, create_test_session, run_migrations

@pytest.fixture(scope="session")
def postgres():
    with PostgresContainer("postgres:15") as pg:
        run_migrations(pg.get_connection_url())   # Alembic 마이그레이션
        yield pg

@pytest.fixture(scope="function")
def db_session(postgres):
    session = create_test_session(postgres.get_connection_url())
    yield session
    session.rollback()
    session.close()

@pytest.fixture(scope="function")
def client(db_session):
    app.dependency_overrides[get_db] = lambda: db_session
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()

@pytest.fixture
def response_holder():
    return {}

# LLM 항상 Mock (비용·속도)
@pytest.fixture(autouse=True)
def mock_llm():
    with patch("app.services.analysis.run_analysis_chain") as m:
        m.return_value = AsyncMock(return_value={"sentiment": "bullish"})
        yield m
```

에이전트(ReAct·구조화 출력·실패 시나리오)까지 다루려면 **`specs/methodology/bdd/04_agent_impl.md`** 를 참조한다.

---

### 2-5. Step 구현

**소요 시간**: 1~2시간  
**참조**: `specs/methodology/bdd/02_fastapi_impl.md`

```python
# apps/api/tests/bdd/steps/analysis/trend_analysis_steps.py
from pytest_bdd import given, when, then, parsers
from tests.bdd.factories import seed_mart_analysis, seed_pipeline_status

# ── Given ──────────────────────────────────────────────────

@given(parsers.parse("{date} 거래일의 분석이 완료된 상태이고"))
def analysis_completed(date: str, db_session):
    seed_mart_analysis(db_session, trade_date=date, status="completed")

@given(parsers.parse("{date} 거래일의 분석이 진행 중이다"))
def analysis_in_progress(date: str, db_session):
    seed_pipeline_status(db_session, trade_date=date, status="running")

@given("사용자가 analyst 권한으로 로그인되어 있다")
def analyst_auth(client):
    client.headers.update({"Authorization": "Bearer test-analyst-token"})

@given(parsers.parse("{date}은 비거래일이다"))
def non_trading_day(date: str):
    pass  # 날짜 자체가 비거래일 — DB 데이터 없음으로 표현

# ── When ───────────────────────────────────────────────────

@when(parsers.parse("{date} 트렌드 분석을 조회하면"))
def call_trend_analysis(date: str, client, response_holder):
    response_holder["resp"] = client.get(
        f"/v1/analyses/trend?trade_date={date}"
    )

# ── Then ───────────────────────────────────────────────────

@then(parsers.parse("{count:d}개 Sector 결과가 반환된다"))
def check_sector_count(count: int, response_holder):
    assert response_holder["resp"].status_code == 200
    data = response_holder["resp"].json()
    assert len(data["analyses"]) == count

@then("각 결과에 sentiment 값이 포함된다")
def check_sentiment(response_holder):
    for analysis in response_holder["resp"].json()["analyses"]:
        assert analysis["sentiment"] in ["bullish", "bearish", "neutral"]

@then("요청이 거부된다")
def check_rejected(response_holder):
    assert response_holder["resp"].status_code == 404

@then(parsers.parse("에러 코드는 {code}이다"))
def check_error_code(code: str, response_holder):
    assert response_holder["resp"].json()["error"]["code"] == code

@then("처리 중 응답이 반환된다")
def check_processing(response_holder):
    assert response_holder["resp"].status_code == 202

@then("is_complete 값은 false이다")
def check_incomplete(response_holder):
    assert response_holder["resp"].json()["is_complete"] is False
```

**Step 작성 후 재실행**:
```bash
uv run pytest tests/bdd/ -v
```

**예상 출력** (코드 미구현이므로 다른 이유로 실패):
```
FAILED - 404 Not Found (엔드포인트 없음)
```

Step이 동작하기 시작했습니다. 이제 실제 코드를 작성합니다.

---

### 2-6. 코드 구현 (Green 만들기)

**소요 시간**: 2~8시간  
**참조**: `specs/methodology/std/01_backend.md`, `specs/methodology/std/03_database.md`

```python
# apps/api/app/routers/analysis.py  (std/01_backend.md 패턴)
from fastapi import APIRouter, Depends, Query
from app.schemas.analysis import TrendAnalysisResponse
from app.services.analysis import AnalysisService

router = APIRouter(prefix="/v1/analyses", tags=["analysis"])

@router.get("/trend", response_model=TrendAnalysisResponse)
async def get_trend_analysis(
    trade_date: str = Query(..., description="YYYY-MM-DD"),
    service: AnalysisService = Depends(),
):
    return await service.get_trend(trade_date)
```

```python
# apps/api/app/services/analysis.py
from app.core.exceptions import NotFoundException
from app.repositories.analysis import AnalysisRepository
import exchange_calendars as xcals

class AnalysisService:
    def __init__(self, repo: AnalysisRepository = Depends()):
        self.repo = repo

    async def get_trend(self, trade_date: str):
        # 비거래일 확인
        cal = xcals.get_calendar("XNYS")
        if not cal.is_session(trade_date):
            raise NotFoundException("NON_TRADING_DAY", "비거래일입니다.")

        result = await self.repo.find_by_date(trade_date)
        if result is None:
            return {"is_complete": False, "analyses": []}

        return result
```

```python
# apps/api/app/core/exceptions.py  (std/01_backend.md 에러 처리 패턴)
class AppException(Exception):
    def __init__(self, code: str, message: str, status_code: int = 400):
        self.code = code
        self.message = message
        self.status_code = status_code

class NotFoundException(AppException):
    def __init__(self, code: str, message: str):
        super().__init__(code, message, status_code=404)
```

```python
# apps/api/app/main.py — 전역 예외 핸들러 등록
from fastapi.responses import JSONResponse

@app.exception_handler(AppException)
async def app_exception_handler(_, exc: AppException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": exc.code, "message": exc.message}},
    )
```

---

### 2-7. BDD 테스트 재실행 → Green 확인

```bash
uv run pytest tests/bdd/ -v
```

**목표 출력**:
```
PASSED specs/features/analysis/trend_analysis.feature
       :: 거래일 트렌드 분석 정상 조회

PASSED specs/features/analysis/trend_analysis.feature
       :: 비거래일 조회 시 에러 반환

PASSED specs/features/analysis/trend_analysis.feature
       :: 분석 미완료 시 진행 중 상태 반환

3 passed in 2.43s
```

---

### 2-8. 커버리지 + 전체 테스트 확인

```bash
# 커버리지 포함 전체 테스트 (gov/05 게이트 기준: 80%)
uv run pytest tests/ \
  --cov=app \
  --cov-report=term-missing \
  --cov-fail-under=80

# 결과 예시
# TOTAL    320    42    87%    ← 80% 초과 → 게이트 통과
```

---

## PART 3 — PR 생성 및 CI 게이트 통과

### 3-1. 커밋 + PR 생성

```bash
# gov/03 Conventional Commits 규칙
git add .
git commit -m "feat(analysis): add trend analysis GET endpoint with BDD tests"

git push origin feature/ICE-01-trend-analysis
```

**PR 체크리스트 확인** (`.github/pull_request_template.md`):
```
[x] 비즈니스 스펙 작성됨 (specs/trend_analysis_spec.md)
[x] .feature 파일 작성됨 (specs/features/analysis/trend_analysis.feature)
[x] 모든 Scenario Step 구현됨 (3/3 PASSED)
[x] 커버리지 80% 이상 (87%)
```

---

### 3-2. CI 게이트 확인

```
GitHub Actions: CI / quality

✅ Lint                 ruff, black 통과
✅ Unit + BDD Tests     3 passed, coverage 87%
✅ Security Scan        HIGH/CRITICAL 없음
```

---

## PART 4 — 반복 사이클 요약

기능 하나가 완료되면 다음 기능으로:

```bash
# 다음 기능 시작
git checkout -b feature/ICE-02-next-feature

# 1. 스펙 작성
cp specs/methodology/bdd/templates/business_spec.md specs/next_feature_spec.md

# 2. .feature 작성
cp specs/methodology/bdd/templates/feature.feature \
   specs/features/{domain}/next_feature.feature

# 3. Red → Step → Code → Green 반복
uv run pytest tests/bdd/ -v --tb=short
```

---

## PART 5 — 자주 묻는 질문

### Q. Step을 찾지 못할 때

```
StepDefinitionNotFoundError
```

`conftest.py`에서 step 파일을 import하거나 `pytest_plugins` 등록 확인:

```python
# tests/bdd/conftest.py
pytest_plugins = [
    "tests.bdd.steps.analysis.trend_analysis_steps",
]
```

---

### Q. DB Testcontainers가 느릴 때

```python
# scope="session"으로 변경 — 전체 테스트에서 DB 1개만 사용
@pytest.fixture(scope="session")
def postgres(): ...
```

---

### Q. BDD 테스트만 빠르게 실행하고 싶을 때

```bash
# BDD만
uv run pytest tests/bdd/ -v

# 특정 feature만
uv run pytest specs/features/analysis/ -v

# 특정 Scenario만 (키워드)
uv run pytest tests/bdd/ -k "비거래일" -v
```

---

### Q. Step 여러 feature에서 재사용하고 싶을 때

```python
# tests/bdd/steps/common_steps.py
@given("사용자가 analyst 권한으로 로그인되어 있다")
def analyst_auth(client):
    client.headers.update({"Authorization": "Bearer test-analyst-token"})

# conftest.py에 등록
pytest_plugins = [
    "tests.bdd.steps.common_steps",          # 공통 먼저
    "tests.bdd.steps.analysis.trend_steps",
]
```

---

## 체크포인트 요약

| 단계 | 완료 기준 | 참조 파일 |
|------|---------|---------|
| 환경 설정 | `docker compose up -d` 성공 | `std/05_infra.md` |
| 비즈니스 스펙 | DoR 체크리스트 통과 | `gov/01_requirements.md` |
| .feature | Gherkin 규칙 준수 | `bdd/01_writing_guide.md` |
| Red 확인 | Step 없음 오류 발생 | `bdd/02_fastapi_impl.md` |
| Step 구현 | Step 오류 해결, 다른 오류 발생 | `bdd/02_fastapi_impl.md` |
| 에이전트(LLM) BDD | Mock·구조화 출력·실패 시나리오 | `bdd/04_agent_impl.md` |
| Green | `N passed` 출력 | |
| 커버리지 | 80% 이상 | `gov/05_quality_gates.md` |
| PR CI | 모든 게이트 녹색 | `std/05_infra.md` |
