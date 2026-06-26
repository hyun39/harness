# Common Spec — 통합 로그 관리 (OpenTelemetry + OpenSearch)

---

## 전체 아키텍처

```
[앱 서버 (FastAPI / Spring Boot)]
    │  OTLP gRPC/HTTP (traces, metrics, logs)
    ▼
[OTel Collector]          ← 수집·가공·라우팅 허브
    ├─ traces  → Jaeger / Tempo          (분산 트레이싱)
    ├─ metrics → Prometheus + Grafana    (메트릭 시각화)
    └─ logs    → OpenSearch              (로그 저장·검색)

[OpenSearch Dashboards]   ← 로그 시각화·알림
```

---

## OpenTelemetry 핵심 개념

| 개념 | 설명 |
|------|------|
| Trace | 요청 하나의 전체 생애 — 여러 Span의 트리 |
| Span | 단일 작업 단위 (HTTP 핸들러, DB 쿼리, 외부 API 호출 등) |
| Metric | 수치형 측정값 — Counter, Gauge, Histogram |
| Log | 구조화된 이벤트 레코드 — Trace ID 연결 시 상관 분석 가능 |
| Context Propagation | 서비스 간 `traceparent` 헤더로 Trace ID 전파 |

---

## OTel SDK 계측 — FastAPI

```python
# requirements
# opentelemetry-sdk
# opentelemetry-instrumentation-fastapi
# opentelemetry-instrumentation-httpx
# opentelemetry-exporter-otlp

# main.py
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

def setup_otel(app: FastAPI):
    provider = TracerProvider(
        resource=Resource.create({
            SERVICE_NAME:    "ice-breaker-api",
            SERVICE_VERSION: "1.0.0",
            DEPLOYMENT_ENVIRONMENT: settings.env,
        })
    )
    provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(
            endpoint=settings.otel_endpoint,  # OTel Collector gRPC
        ))
    )
    trace.set_tracer_provider(provider)

    FastAPIInstrumentor.instrument_app(app)  # HTTP 요청 자동 계측
    HTTPXClientInstrumentor().instrument()   # 외부 API 호출 자동 계측
```

### 수동 Span 추가

```python
tracer = trace.get_tracer(__name__)

async def run_summary_chain(data: dict) -> Summary:
    with tracer.start_as_current_span("summary_chain") as span:
        span.set_attribute("llm.model", "gpt-3.5-turbo")
        span.set_attribute("llm.temperature", 0)
        result = await summary_chain.ainvoke(data)
        span.set_attribute("llm.output_tokens", result.usage.completion_tokens)
        return result
```

---

## OTel SDK 계측 — Spring Boot

```yaml
# build.gradle
implementation 'io.opentelemetry.instrumentation:opentelemetry-spring-boot-starter'

# application.yml
otel:
  service:
    name: ice-breaker-api
  exporter:
    otlp:
      endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:http://otel-collector:4317}
  traces:
    exporter: otlp
  metrics:
    exporter: otlp
  logs:
    exporter: otlp
```

```java
// 수동 Span 추가
@Autowired Tracer tracer;

public Summary runSummaryChain(Map<String, Object> data) {
    Span span = tracer.spanBuilder("summary_chain")
        .setAttribute("llm.model", "gpt-3.5-turbo")
        .startSpan();
    try (Scope scope = span.makeCurrent()) {
        var result = summaryChain.invoke(data);
        span.setAttribute("llm.output_tokens", result.getUsage().getCompletionTokens());
        return result;
    } catch (Exception e) {
        span.recordException(e);
        span.setStatus(StatusCode.ERROR);
        throw e;
    } finally {
        span.end();
    }
}
```

---

## OTel Collector 설정

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:  { endpoint: "0.0.0.0:4317" }
      http:  { endpoint: "0.0.0.0:4318" }

processors:
  batch:
    timeout: 5s
    send_batch_size: 1024
  resource:
    attributes:
      - action: insert
        key: environment
        value: ${ENV}
  filter/health:                          # 헬스체크 트레이스 제거
    traces:
      span:
        - 'attributes["http.target"] == "/actuator/health"'
        - 'attributes["http.target"] == "/healthz"'

exporters:
  otlphttp/opensearch:
    endpoint: "http://opensearch:9200"
    logs_endpoint: "http://opensearch:9200/_bulk"
  jaeger:
    endpoint: "http://jaeger:14250"
  prometheus:
    endpoint: "0.0.0.0:8889"

service:
  pipelines:
    traces:
      receivers:  [otlp]
      processors: [batch, resource, filter/health]
      exporters:  [jaeger]
    metrics:
      receivers:  [otlp]
      processors: [batch]
      exporters:  [prometheus]
    logs:
      receivers:  [otlp]
      processors: [batch, resource]
      exporters:  [otlphttp/opensearch]
```

---

## 구조화 로그 포맷

OpenSearch 색인을 위해 **JSON 구조화 로그** 필수.

```json
{
  "timestamp":   "2026-05-03T10:00:00.000Z",
  "level":       "INFO",
  "service":     "ice-breaker-api",
  "environment": "prod",
  "trace_id":    "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id":     "00f067aa0ba902b7",
  "message":     "external_api_call_completed",
  "attributes": {
    "api":         "scrapin",
    "duration_ms": 342,
    "status_code": 200
  }
}
```

### FastAPI 구조화 로그 (structlog)

```python
# core/logging.py
import structlog, logging

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
)

# trace_id 자동 주입 미들웨어
@app.middleware("http")
async def inject_trace_context(request: Request, call_next):
    span = trace.get_current_span()
    ctx  = span.get_span_context()
    structlog.contextvars.bind_contextvars(
        trace_id=format(ctx.trace_id, "032x"),
        span_id =format(ctx.span_id,  "016x"),
    )
    return await call_next(request)
```

### Spring Boot 구조화 로그 (Logback + logstash-logback-encoder)

```xml
<!-- logback-spring.xml -->
<appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
  <encoder class="net.logstash.logback.encoder.LogstashEncoder">
    <includeMdcKeyName>traceId</includeMdcKeyName>
    <includeMdcKeyName>spanId</includeMdcKeyName>
    <includeMdcKeyName>requestId</includeMdcKeyName>
  </encoder>
</appender>
```

OTel Java Agent 사용 시 `traceId`, `spanId` MDC 자동 주입.

---

## OpenSearch 인덱스 설계

### 인덱스 전략

| 패턴 | 형식 | 적합한 상황 |
|------|------|------------|
| 일별 롤링 | `logs-app-2026.05.03` | 로그량 많음, 보존 기간 관리 용이 |
| ILM (Index Lifecycle) | 자동 Hot→Warm→Cold→Delete | 운영 자동화 권장 |
| 단일 인덱스 | `logs-app` | 소규모, 개발 환경 |

### 인덱스 매핑 (주요 필드)

```json
{
  "mappings": {
    "properties": {
      "timestamp":    { "type": "date" },
      "level":        { "type": "keyword" },
      "service":      { "type": "keyword" },
      "environment":  { "type": "keyword" },
      "trace_id":     { "type": "keyword" },
      "span_id":      { "type": "keyword" },
      "message":      { "type": "text", "analyzer": "standard" },
      "attributes":   { "type": "object", "dynamic": true }
    }
  }
}
```

- `keyword` — 집계·필터에 사용 (exact match)
- `text` — 전문 검색에 사용 (분석기 적용)
- `attributes.*` — 동적 매핑 허용 (단, 매핑 폭발 주의 → `dynamic: strict` 전환 검토)

### ILM 정책 예시

```json
{
  "policy": {
    "phases": {
      "hot":  { "actions": { "rollover": { "max_size": "10gb", "max_age": "1d" } } },
      "warm": { "min_age": "7d",  "actions": { "shrink": { "num_shards": 1 } } },
      "cold": { "min_age": "30d", "actions": { "freeze": {} } },
      "delete": { "min_age": "90d", "actions": { "delete": {} } }
    }
  }
}
```

---

## OpenSearch Dashboards 활용

### 권장 대시보드 구성

| 대시보드 | 주요 패널 |
|---------|----------|
| 서비스 개요 | 초당 요청 수, 에러율, p50/p95/p99 응답시간 |
| LLM 모니터링 | 모델별 호출 수, 토큰 사용량, 체인별 지연 시간 |
| 에러 분석 | 에러 로그 타임라인, 스택트레이스 그룹핑 |
| 외부 API | Scrapin/Tavily 호출 성공률, 응답시간 분포 |

### 알림(Alerting) 설정

```json
// 에러율 5% 초과 시 알림
{
  "name": "high-error-rate",
  "type": "monitor",
  "schedule": { "period": { "interval": 1, "unit": "MINUTES" } },
  "inputs": [{
    "search": {
      "query": {
        "bool": {
          "filter": [
            { "range": { "timestamp": { "gte": "now-5m" } } },
            { "term": { "level": "ERROR" } }
          ]
        }
      }
    }
  }],
  "triggers": [{
    "condition": { "script": { "source": "ctx.results[0].hits.total.value > 10" } },
    "actions": [{ "destination_id": "slack-webhook", "message_template": "..." }]
  }]
}
```

---

## Trace-Log 상관 분석

```
1. 에러 발생 → OpenSearch에서 level:ERROR 로그 조회
2. trace_id 확인 → Jaeger/Tempo에서 해당 트레이스 열기
3. 문제 Span 특정 → 해당 Span의 span_id로 로그 재조회
4. 원인 분석 → 전체 요청 흐름 + 상세 로그 동시 확인
```

---

## 보안 설정

| 항목 | 설정 |
|------|------|
| OpenSearch TLS | 클러스터 간 통신 TLS 필수 |
| 인증 | OpenSearch Security 플러그인 — 사용자·역할 기반 |
| Keycloak 연동 | SAML/OIDC → OpenSearch Dashboards SSO |
| 민감 정보 필터 | OTel Collector `attributes/redact` 프로세서로 PII 제거 |

```yaml
# OTel Collector — PII 제거 예시
processors:
  redaction:
    allow_all_keys: true
    blocked_values:
      - "[0-9]{6}-[0-9]{7}"   # 주민등록번호 패턴
      - "Bearer [A-Za-z0-9]+" # 토큰 노출 방지
```

---

## 미결 기술 과제

- [ ] OpenSearch 샤드 수 결정 — 일별 로그 볼륨 추정 후 설정 (`샤드 크기 10~50GB 권장`)
- [ ] OTel Collector HA 구성 — 단일 장애점 제거 (2대 이상 + 로드밸런서)
- [ ] LLM 토큰 비용 메트릭 — 모델·체인별 토큰 사용량 Prometheus 커스텀 메트릭
- [ ] 샘플링 전략 — 운영 환경 100% 트레이싱은 과부하 → Tail Sampling 적용
- [ ] OpenSearch Dashboards + Keycloak SSO 연동 (`openid_connect` 설정)
