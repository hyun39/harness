# STD-01 — 백엔드 구현 표준

> 전체 상세: [`detail/backend_fastapi.md`](./detail/backend_fastapi.md), [`detail/backend_springboot.md`](./detail/backend_springboot.md)

---

## 계층 구조 (공통)

```
Router/Controller  ← HTTP 요청·응답, 입력 검증만
      ↓
Service            ← 비즈니스 로직, 트랜잭션 경계
      ↓
Repository/Client  ← DB 접근 또는 외부 API 호출
```

**규칙**: 계층을 건너뛰지 않는다. Controller에서 DB 직접 접근 금지.

---

## FastAPI 핵심 패턴

### 라우터
```python
@router.post("/v1/analyses", response_model=AnalysisResponse, status_code=201)
async def create_analysis(
    body: AnalysisRequest,          # Pydantic 자동 검증
    service: AnalysisService = Depends(),
):
    return await service.run(body.name)
```

### 에러 처리
```python
# 전역 핸들러 등록
@app.exception_handler(AppException)
async def handler(_, exc: AppException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": exc.code, "message": exc.message}},
    )
```

### 비동기 병렬 호출
```python
linkedin_data, tweets = await asyncio.gather(
    linkedin_client.fetch(url),
    twitter_client.fetch_mock(username),
)
```

---

## Spring Boot 핵심 패턴

### 컨트롤러
```java
@PostMapping("/v1/analyses")
public ResponseEntity<AnalysisResponse> create(
    @Valid @RequestBody AnalysisRequest request) {
    return ResponseEntity.status(201).body(service.run(request.name()));
}
```

### 에러 처리
```java
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(AppException.class)
    public ResponseEntity<ErrorResponse> handle(AppException ex) {
        return ResponseEntity.status(ex.getStatusCode())
            .body(new ErrorResponse(ex.getCode(), ex.getMessage()));
    }
}
```

### Virtual Threads (Java 21)
```yaml
spring.threads.virtual.enabled: true  # application.yml
```

---

## BDD 테스트 연결 포인트

| Step | 구현 위치 |
|------|---------|
| `When API를 호출하면` | TestClient / TestRestTemplate → Router |
| `Then 응답이 반환된다` | response_model / ResponseEntity 검증 |
| `Given 데이터가 있다` | Service→Repository → TestDB Fixture |

---

## 외부 API 연동 필수 패턴

```python
# timeout + retry 반드시 설정
client = httpx.AsyncClient(
    timeout=httpx.Timeout(connect=5.0, read=30.0)
)

@retry(stop=stop_after_attempt(3),
       wait=wait_exponential(min=1, max=8))
async def fetch(url: str): ...
```

---

## OpenAPI 스펙 작성 패턴

> 정책·필수 항목은 [`gov/06_api_design.md`](../gov/06_api_design.md) 참조.

### 표준 endpoint 정의 예시

```yaml
# 필수 항목
/v1/analyses:
  post:
    summary: "분석 요청 생성"          # 필수
    operationId: "createAnalysis"       # 필수 — camelCase
    tags: ["analysis"]                  # 필수
    requestBody:                        # 필수
      required: true
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/AnalysisRequest'
    responses:
      '201':                            # 성공 응답 필수
        description: "분석 생성됨"
      '422':                            # 에러 응답 필수
        $ref: '#/components/responses/ValidationError'
    security:                           # 인증 명시 필수
      - bearerAuth: []
```

### 자주 쓰는 components

- `securitySchemes`: bearerAuth (JWT)
- `responses`:
  - `ValidationError` (422)
  - `Unauthorized` (401)
  - `NotFound` (404)
- `schemas`: Pydantic 모델에서 `model_json_schema()` 자동 생성 권장

### FastAPI 자동 생성 활용

```python
# main.py에서 OpenAPI 스펙 자동 노출
app = FastAPI(
    title="SP500 Platform API",
    version="1.0.0",
    openapi_url="/openapi.json",
)
# /docs (Swagger UI), /redoc (ReDoc) 자동 제공
```

---

## 패턴 적용 체크리스트

> 이 표준에 정의된 패턴을 실제 코드가 따르는지 audit. 각 항목은 yes/no.
> 식별자(`S01-NN-MM`)는 통합 인덱스(`specs/_methodology/CHECKLIST.md`)에서 참조.

### 카테고리 1: 계층 구조
- [ ] S01-01-01: Router/Controller가 HTTP 입력 검증·응답만 담당하는가
- [ ] S01-01-02: Service가 비즈니스 로직과 트랜잭션 경계를 가지는가
- [ ] S01-01-03: Repository/Client가 DB·외부 API 접근을 담당하는가
- [ ] S01-01-04: Controller에서 DB 직접 접근이 없는가
- [ ] S01-01-05: 계층 건너뛰기(Controller→Repository 직접 호출)가 없는가

### 카테고리 2: FastAPI 라우터
- [ ] S01-02-01: response_model이 모든 endpoint에 설정됐는가
- [ ] S01-02-02: status_code가 명시적으로 지정됐는가 (POST 201 등)
- [ ] S01-02-03: Pydantic schema로 입출력 검증이 적용됐는가
- [ ] S01-02-04: 비동기 IO(DB·외부 API)에 async/await가 사용됐는가

### 카테고리 3: 에러 처리
- [ ] S01-03-01: 비즈니스 에러가 도메인 예외 클래스로 표현되는가
- [ ] S01-03-02: HTTPException이 router 레이어에서만 발생하는가
- [ ] S01-03-03: 통일 에러 응답(`error.code`, `error.message`)이 미들웨어로 처리되는가

### 카테고리 4: OpenAPI 작성
- [ ] S01-04-01: summary·operationId·tags가 모두 작성됐는가
- [ ] S01-04-02: requestBody·responses에 schema 참조가 있는가
- [ ] S01-04-03: security 항목이 명시됐는가

### 카테고리 5: 의존성 주입
- [ ] S01-05-01: Repository·Service가 Depends로 주입되는가
- [ ] S01-05-02: 환경 토글(USE_INMEMORY 등)이 dependencies 모듈에 격리됐는가
- [ ] S01-05-03: 테스트에서 dependency_overrides로 교체 가능한가
