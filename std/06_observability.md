# STD-06 — 관찰성 (OTel + OpenSearch)

> 전체 상세: [`detail/observability_otel_opensearch.md`](./detail/observability_otel_opensearch.md)

---

## 계측 설정 (FastAPI)

```python
# main.py
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

def setup_otel(app):
    provider = TracerProvider(resource=Resource.create({
        SERVICE_NAME: "ice-breaker-api",
        DEPLOYMENT_ENVIRONMENT: settings.env,
    }))
    provider.add_span_processor(BatchSpanProcessor(
        OTLPSpanExporter(endpoint=settings.otel_endpoint)
    ))
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(app)   # HTTP 자동 계측
    HTTPXClientInstrumentor().instrument()    # 외부 API 자동 계측
```

---

## 수동 Span (LLM 체인 추적)

```python
tracer = trace.get_tracer(__name__)

async def run_summary_chain(data):
    with tracer.start_as_current_span("summary_chain") as span:
        span.set_attribute("llm.model", "gpt-3.5-turbo")
        result = await chain.ainvoke(data)
        span.set_attribute("llm.output_tokens",
                           result.usage.completion_tokens)
        return result
```

---

## 구조화 로그 필수 형식

```json
{
  "timestamp": "ISO8601",
  "level":     "INFO",
  "service":   "ice-breaker-api",
  "trace_id":  "4bf92f35...",
  "span_id":   "00f067aa...",
  "message":   "external_api_call_completed",
  "attributes": { "api": "scrapin", "duration_ms": 342 }
}
```

**`trace_id`와 `span_id`는 모든 로그에 포함** — OTel 미들웨어로 자동 주입.

---

## structlog 설정 (FastAPI)

```python
structlog.configure(processors=[
    structlog.contextvars.merge_contextvars,   # trace_id 자동 포함
    structlog.processors.add_log_level,
    structlog.processors.TimeStamper(fmt="iso"),
    structlog.processors.JSONRenderer(),
])

# PII 마스킹 (필수)
def mask_pii(_, __, event_dict):
    event_dict.pop("name", None)
    event_dict.pop("linkedin_url", None)
    return event_dict
```

---

## OpenSearch 인덱스 규칙

```
인덱스명: logs-{service}-YYYY.MM.DD  (ILM 일별 롤링)
보존: Hot 7일 → Warm 30일 → Cold 60일 → Delete 90일
```

---

## BDD 테스트에서 관찰성 검증

```python
# BDD에서 로그 출력 검증 (선택적)
@then("요청이 감사 로그에 기록된다")
def check_audit_log(caplog):
    assert any(
        "AUTH_SUCCESS" in record.message
        for record in caplog.records
    )
```

---

## 패턴 적용 체크리스트

> 이 표준에 정의된 패턴을 실제 코드가 따르는지 audit. 각 항목은 yes/no.
> 식별자(`S06-NN-MM`)는 통합 인덱스(`specs/_methodology/CHECKLIST.md`)에서 참조.

### 카테고리 1: OTel 계측
- [ ] S06-01-01: 모든 서비스가 OTel SDK로 초기화되는가
- [ ] S06-01-02: resource attributes(`service.name`, `deployment.environment`, `service.version`)가 설정됐는가
- [ ] S06-01-03: HTTP 자동 계측(FastAPIInstrumentor 등)이 적용되는가
- [ ] S06-01-04: 외부 API 호출(HTTPXClientInstrumentor)이 자동 계측되는가
- [ ] S06-01-05: DB 호출이 SQLAlchemyInstrumentor 등으로 계측되는가
- [ ] S06-01-06: LLM 호출이 별도 span으로 계측되는가 (gov/08 연계)

### 카테고리 2: 트레이싱·메트릭
- [ ] S06-02-01: OTLP exporter가 OTel Collector로 전송되는가
- [ ] S06-02-02: BatchSpanProcessor로 비동기 export되는가
- [ ] S06-02-03: 표준 메트릭(http_server_duration, db_client_operation_duration 등)이 수집되는가
- [ ] S06-02-04: 비즈니스 메트릭(예: pipeline_dag_success_rate)이 추가됐는가

### 카테고리 3: 로깅
- [ ] S06-03-01: 모든 로그가 JSON 구조화 포맷인가
- [ ] S06-03-02: 모든 로그에 trace_id가 포함되는가
- [ ] S06-03-03: PII가 마스킹된 후 로그에 출력되는가 (gov/07 연계)
- [ ] S06-03-04: 로그 레벨(INFO/WARN/ERROR)이 적절히 사용되는가
- [ ] S06-03-05: 외부 LLM·API 응답 raw_data가 로그에 그대로 노출되지 않는가

### 카테고리 4: 시각화·알람
- [ ] S06-04-01: OpenSearch Dashboard에 서비스별 트레이스·로그 대시보드가 있는가
- [ ] S06-04-02: SLO 위반(에러율·latency p95) 알람이 설정됐는가 (gov/09 연계)
- [ ] S06-04-03: 알람이 on-call 채널로 라우팅되는가
