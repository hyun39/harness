# Common Spec — Backend (FastAPI)

---

## 프레임워크 특성

| 항목 | 내용 |
|------|------|
| 언어 | Python 3.11+ |
| 서버 | Uvicorn (ASGI) — `uvicorn main:app --reload` |
| 동시성 모델 | asyncio 이벤트 루프 (단일 스레드 + 코루틴) |
| 타입 시스템 | Pydantic v2 — 요청·응답 자동 검증·직렬화 |
| API 문서 | `/docs` (Swagger UI), `/redoc` 자동 생성 |

---

## 프로젝트 구조

```
app/
├── main.py               ← FastAPI 앱 생성, 미들웨어·라우터 등록
├── routers/              ← 엔드포인트 정의 (APIRouter)
│   └── process.py
├── services/             ← 비즈니스 로직
│   └── ice_breaker.py
├── schemas/              ← Pydantic 요청·응답 모델
│   └── process.py
├── clients/              ← 외부 API 클라이언트
│   ├── linkedin.py
│   └── twitter.py
├── core/
│   ├── config.py         ← pydantic-settings 환경변수 로드
│   └── exceptions.py     ← 커스텀 예외 클래스
└── dependencies.py       ← FastAPI Depends 의존성 함수
```

---

## 라우터 패턴

```python
# routers/process.py
from fastapi import APIRouter, Depends, HTTPException
from schemas.process import ProcessRequest, ProcessResponse
from services.ice_breaker import IceBreakerService

router = APIRouter(prefix="/v1", tags=["icebreaker"])

@router.post("/process", response_model=ProcessResponse)
async def process(
    body: ProcessRequest,
    service: IceBreakerService = Depends(),
):
    return await service.run(body.name)
```

- `response_model` 지정 → 응답 자동 필터링·직렬화
- `Depends()` 로 서비스 주입 → 테스트 시 오버라이드 가능

---

## Pydantic 스키마

```python
# schemas/process.py
from pydantic import BaseModel, Field

class ProcessRequest(BaseModel):
    name: str = Field(min_length=1, max_length=100)

class SummaryAndFacts(BaseModel):
    summary: str
    facts: list[str]

class ProcessResponse(BaseModel):
    summary_and_facts: SummaryAndFacts
    interests: dict[str, list[str]]
    ice_breakers: dict[str, list[str]]
    picture_url: str | None = None
```

- `Field(min_length, max_length)` — 컨트롤러 레이어 검증
- `str | None = None` — 선택 필드 (Python 3.10+ union 문법)

---

## 설정 관리 (pydantic-settings)

```python
# core/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    openai_api_key: str
    scrapin_api_key: str
    tavily_api_key: str
    debug: bool = False
    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
    )

settings = Settings()  # 앱 시작 시 1회 생성
```

- 누락된 필수 환경변수 → 앱 시작 시 즉시 `ValidationError`
- `@lru_cache` 로 싱글턴 보장 가능

---

## 의존성 주입 (Depends)

```python
# dependencies.py
from functools import lru_cache
from core.config import Settings

@lru_cache
def get_settings() -> Settings:
    return Settings()

# 서비스에 설정 주입
def get_service(settings: Settings = Depends(get_settings)):
    return IceBreakerService(settings)
```

- 테스트 시 `app.dependency_overrides[get_settings] = lambda: mock_settings`

---

## 비동기 처리

| 상황 | 패턴 |
|------|------|
| LangChain LLM 체인 | `await chain.ainvoke()` |
| 동기 라이브러리 | `await asyncio.get_event_loop().run_in_executor(None, sync_fn)` |
| 병렬 외부 호출 | `await asyncio.gather(task1, task2)` |
| 장시간 작업 (> 30s) | Background Tasks 또는 ARQ Worker Queue |

```python
# 병렬 LinkedIn + Twitter 동시 조회
linkedin_data, tweets = await asyncio.gather(
    linkedin_client.fetch(url),
    twitter_client.fetch_mock(username),
)
```

---

## 에러 처리

```python
# core/exceptions.py
class AppException(Exception):
    def __init__(self, status_code: int, code: str, message: str):
        self.status_code = status_code
        self.code = code
        self.message = message

class NotFoundException(AppException):
    def __init__(self, message: str):
        super().__init__(404, "NOT_FOUND", message)

class ExternalApiException(AppException):
    def __init__(self, message: str):
        super().__init__(502, "EXTERNAL_API_ERROR", message)

# main.py — 전역 핸들러 등록
@app.exception_handler(AppException)
async def app_exception_handler(request, exc: AppException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": exc.code, "message": exc.message}},
    )
```

---

## 미들웨어

```python
# main.py
from fastapi.middleware.cors import CORSMiddleware
import uuid, time

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# 요청 ID + 소요 시간 로깅
@app.middleware("http")
async def logging_middleware(request: Request, call_next):
    request_id = str(uuid.uuid4())
    start = time.monotonic()
    response = await call_next(request)
    elapsed = (time.monotonic() - start) * 1000
    logger.info(f"[{request_id}] {request.method} {request.url.path} "
                f"{response.status_code} {elapsed:.1f}ms")
    response.headers["X-Request-Id"] = request_id
    return response
```

---

## 외부 HTTP 클라이언트 (httpx)

```python
# clients/linkedin.py
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

class LinkedInClient:
    def __init__(self, api_key: str):
        self._client = httpx.AsyncClient(
            base_url="https://api.scrapin.io",
            timeout=httpx.Timeout(connect=5.0, read=30.0),
        )
        self._api_key = api_key

    @retry(stop=stop_after_attempt(3),
           wait=wait_exponential(multiplier=1, min=1, max=8))
    async def fetch_profile(self, linkedin_url: str) -> dict:
        response = await self._client.get(
            "/enrichment/profile",
            params={"apikey": self._api_key, "linkedInUrl": linkedin_url},
        )
        response.raise_for_status()
        return response.json()
```

- `httpx.AsyncClient` 재사용 (커넥션 풀 활용)
- `tenacity` 로 지수 백오프 재시도

---

## 로깅

```python
# core/logging.py — structlog 사용 예시
import structlog

logger = structlog.get_logger()

# 구조화 로그 출력
logger.info("external_api_call", service="scrapin", url=linkedin_url)
logger.error("chain_failed", error=str(e), model="gpt-3.5-turbo")
```

---

## 테스트

```python
# tests/test_process.py
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, patch

def test_process_success(client: TestClient):
    with patch("services.ice_breaker.IceBreakerService.run",
               new_callable=AsyncMock) as mock_run:
        mock_run.return_value = ProcessResponse(...)
        response = client.post("/v1/process", json={"name": "Harrison Chase"})
    assert response.status_code == 200

# conftest.py — 의존성 오버라이드
@pytest.fixture
def client():
    app.dependency_overrides[get_settings] = lambda: mock_settings
    return TestClient(app)
```

| 레벨 | 도구 | 비고 |
|------|------|------|
| 단위 | pytest + unittest.mock | Service 격리 |
| 통합 | pytest + TestClient | 실제 Pydantic 검증 포함 |
| DB 통합 | pytest + testcontainers-python | PostgreSQL 컨테이너 |

---

## 미결 기술 과제

- [ ] `httpx.AsyncClient` 생명주기 관리 — `lifespan` 이벤트로 시작·종료
- [ ] Rate Limiting — `slowapi` (ASGI용 rate limiter) 적용
- [ ] 응답 캐싱 — `fastapi-cache2` + Redis 백엔드
- [ ] LLM 호출 타임아웃 — `asyncio.wait_for(chain.ainvoke(), timeout=60)`
- [ ] OpenTelemetry 트레이싱 연동 (`opentelemetry-instrumentation-fastapi`)
