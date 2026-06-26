# GOV-09 — 관찰성·SRE 거버넌스

> **강제 대상**: 모든 서비스 (api, agent, Airflow DAG) 및 인프라 컴포넌트
> **게이트**: SLO 위반 시 알람·Error Budget 차감, 미계측 서비스 배포 차단
> **원본 참조**: `enterprise/09.01_gov_observability_sre.md`, `common/observability.md`, 구현은 `std/06_observability.md` 참조

---

## SLI/SLO 정의 (MUST)

| 도메인 | SLI | SLO | 측정 윈도우 |
|--------|-----|-----|-----------|
| API 가용성 | 성공 응답 비율 (5xx 제외) | 99.9% | 30일 롤링 |
| API 지연 | 인증된 GET 요청 p95 latency | ≤ 500ms | 30일 롤링 |
| API 에러율 | 5xx / 전체 요청 | ≤ 0.1% | 1시간 |
| Airflow DAG | 일일 성공률 (휴일 제외) | ≥ 99% | 30일 롤링 |
| Airflow 시작 지연 | 스케줄 → 첫 task 시작 | ≤ 15분 | 일별 |
| LLM (agent) 지연 | end-to-end p95 | ≤ 8s | 7일 롤링 |
| LLM 응답 품질 | schema 검증 통과율 | ≥ 99% | 7일 롤링 |
| 데이터 신선도 | 거래일 마감 → mart 적재 완료 | ≤ 90분 | 거래일별 |

---

## Error Budget 정책

| 항목 | 내용 |
|------|------|
| 월간 가용성 예산 | 0.1% (약 43분/월) |
| 소진 50% 도달 | Warning — 신규 feature PR 리뷰에 SRE 동석 |
| 소진 100% 도달 | feature 배포 동결 (`feature-freeze` 라벨 자동 부여) |
| 동결 해제 조건 | 신뢰성 작업 우선 처리 + 다음 측정 윈도우 진입 |
| 면제 사유 | 외부 의존성 장애 (벤더 측 RCA 첨부 시 제외 가능) |

---

## OTel 계측 필수 항목 (MUST)

모든 서비스는 OpenTelemetry Collector (`sp500-otel-collector`) 로 telemetry 를 송출한다.

| 시그널 | 필수 항목 |
|--------|---------|
| Resource Attributes | `service.name`, `deployment.environment`, `service.version` |
| HTTP | 자동 계측 (FastAPI/Starlette instrumentor) — route, status, latency |
| DB | SQLAlchemy / psycopg span — query summary, duration |
| LLM 호출 | model, prompt_tokens, completion_tokens, latency (GOV-08 참조) |
| Airflow | `dag_id`, `task_id`, `run_id`, `try_number` 를 span/log attr 로 |
| Metrics | RED (Rate, Errors, Duration) + USE (Util, Sat, Errors) 핵심 시계열 |

- [ ] 모든 서비스는 기동 시 resource attributes 3종을 emit 한다
- [ ] 외부 호출 (DB·LLM·Tavily 등) 은 명시 span 으로 감싼다
- [ ] trace context 는 inbound→outbound 로 propagate 된다 (W3C traceparent)

---

## 로깅 표준 (MUST)

| 규칙 | 내용 |
|------|------|
| 형식 | JSON 구조화 1줄 = 1이벤트 (stdout) |
| 필수 필드 | `timestamp`, `level`, `service`, `trace_id`, `span_id`, `message` |
| 레벨 정책 | `ERROR` 는 알람 트리거 후보 — 정상 흐름에서 사용 금지 |
| PII 마스킹 | GOV-07 데이터 정책 따름 — 이메일·IP 등 마스킹 후 기록 |
| 보존 기간 | OpenSearch `sp500-osd` — Hot 7일 / Warm 30일 / Cold 90일 |

```json
{
  "timestamp": "2026-05-06T01:23:45Z",
  "level": "INFO",
  "service": "api",
  "trace_id": "...",
  "span_id": "...",
  "message": "GET /v1/index ok",
  "user_id_hash": "..."
}
```

---

## 알람·On-Call 정책

### 알람 임계 (MUST)

| 심각도 | 트리거 | 응답 SLA | 채널 |
|--------|--------|---------|------|
| Critical | API 가용성 < 99.5% (5분 윈도우) | 15분 내 acknowledge | PagerDuty + Slack `#sre-critical` |
| Critical | mart 적재 SLO 위반 (90분 초과) | 30분 내 acknowledge | PagerDuty + Slack |
| Warning | API p95 > 500ms (15분 지속) | 영업일 1시간 내 | Slack `#sre-warning` |
| Warning | Error Budget 50% 소진 | 영업일 4시간 내 | Slack |
| Info | DAG 1회 실패 (재시도 성공) | 추적만 | Slack `#data-ops` |

### On-Call 로테이션

- 주간 로테이션 (월요일 09:00 KST 교대), 1차 + 2차 백업 페어
- Critical 알람은 1차 무응답 15분 시 2차 자동 에스컬레이션 → 30분 시 팀 리드
- 비번 시간 Warning 알람은 익일 영업 시작 시 처리

---

## Incident Response 절차

### 심각도 분류

| 등급 | 정의 | 예시 |
|------|------|------|
| SEV1 | 핵심 서비스 전면 중단·데이터 손실 | API 전체 5xx, mart 데이터 손상 |
| SEV2 | 일부 기능 중단·SLO 위반 지속 | 특정 endpoint 불가, DAG 연속 실패 |
| SEV3 | 사용자 영향 제한적·우회 가능 | 단일 task 실패, 비핵심 latency 저하 |

### 단계

1. **인지 (Detect)** — 알람 또는 사용자 보고 → incident 채널 개설 (`#inc-YYYYMMDD-NN`)
2. **완화 (Mitigate)** — 영향 차단이 RCA 보다 우선 (rollback, feature flag, 트래픽 차단)
3. **복구 (Recover)** — 정상 상태 회복 확인 후 incident close
4. **학습 (Postmortem)** — SEV1/SEV2 는 5영업일 내 작성 의무

---

## Postmortem 템플릿

| 섹션 | 내용 |
|------|------|
| Summary | 발생 시각·영향 범위·총 소요 시간 |
| Timeline | UTC 기준 이벤트 타임라인 (탐지 → 복구) |
| Root Cause | 5-why 기법으로 근본 원인 도출 |
| What went well | 완화에 도움이 된 요소 |
| What went poorly | 개선 필요 영역 |
| Action Items | 담당자·기한·티켓 링크 (GitHub Issues) — 미이행 시 다음 회고에 escalation |

원칙: **Blameless** — 사람이 아닌 시스템·프로세스의 결함을 분석한다. 개인 책임 추궁 금지.

---

## 금지 사항 (MUST NOT)

| 항목 | 사유 |
|------|------|
| 운영 환경에서 `print()` / 비구조화 로그 | OpenSearch 인덱싱 불가, trace 연계 불가 |
| 알람 임계를 코드에 하드코딩 | 변경 추적 불가 — 설정 파일 또는 IaC 로 관리 |
| 로그에 raw PII (이메일·전화·주민번호) 기록 | GOV-07 위반 |
| Prometheus metric label 에 user_id 등 고-cardinality 값 사용 | TSDB 폭증 |
| Critical 알람 > 5분 acknowledge 지연 | On-Call SLA 위반 |
| Postmortem 없이 SEV1/SEV2 close | 재발 방지 학습 불가 |
| "잠시 끄기" 식 알람 영구 silence | 회귀 탐지 불능 — 기한부 silence 만 허용 |

---

## 추적성

```
GOV-09 (본 문서, 정책)
  │
  ├─► std/06_observability.md       (구현 표준·코드 패턴)
  ├─► GOV-07 데이터 정책            (PII 마스킹 규칙)
  ├─► GOV-08 AI 거버넌스            (LLM 계측 메트릭 정의)
  ├─► GOV-05 품질 게이트            (성능 테스트·E2E 의 SLO 검증)
  └─► GOV-04 보안                   (감사 로그 형식 일관)

구현 매핑
  api / agent          ──► OTel SDK + structlog ──► sp500-otel-collector
  Airflow DAG (6종)    ──► OTel exporter task    ──► sp500-otel-collector
  sp500-otel-collector ──► OpenSearch (sp500-opensearch / sp500-osd 대시보드)
```

---

## 검증 체크리스트

> 이 가이드 기준으로 application을 audit할 때 사용. 각 항목은 yes/no.
> 통합 인덱스: [`specs/_methodology/CHECKLIST.md`](../CHECKLIST.md)

### 카테고리 1: SLI/SLO (G09-01)
- [ ] G09-01-01: API 가용성 SLO(성공 응답 비율 99.9%, 30일 롤링)가 정의·측정되는가?
- [ ] G09-01-02: API 지연 SLO(인증 GET p95 ≤ 500ms)가 정의·측정되는가?
- [ ] G09-01-03: API 에러율 SLO(5xx ≤ 0.1%, 1시간 윈도우)가 정의·측정되는가?
- [ ] G09-01-04: Airflow DAG 일일 성공률(≥ 99%) 및 시작 지연(≤ 15분)이 측정되는가?
- [ ] G09-01-05: LLM agent end-to-end p95 latency(≤ 8s) 및 schema 검증 통과율(≥ 99%)이 측정되는가?
- [ ] G09-01-06: 데이터 신선도 SLO(거래일 마감 → mart 적재 ≤ 90분)가 측정되는가?
- [ ] G09-01-07: 모든 서비스가 OTel resource attributes 3종(`service.name`, `deployment.environment`, `service.version`)을 emit 하는가?
- [ ] G09-01-08: 외부 호출(DB·LLM·Tavily 등)이 명시 span 으로 감싸지는가?
- [ ] G09-01-09: trace context 가 inbound→outbound 로 W3C traceparent 로 propagate 되는가?

### 카테고리 2: Error Budget (G09-02)
- [ ] G09-02-01: 월간 가용성 예산(0.1%, 약 43분/월)이 명시·측정되는가?
- [ ] G09-02-02: 50% 소진 시 Warning(SRE PR 리뷰 동석)이 트리거되는가?
- [ ] G09-02-03: 100% 소진 시 feature 배포 동결(`feature-freeze` 라벨 자동 부여)이 동작하는가?
- [ ] G09-02-04: 동결 해제 조건(신뢰성 작업 우선 + 다음 윈도우)이 문서화되어 있는가?

### 카테고리 3: 알람·On-Call (G09-03)
- [ ] G09-03-01: Critical 알람 임계(API 가용성 < 99.5%, mart 적재 90분 초과)가 PagerDuty + Slack `#sre-critical` 로 라우팅되는가?
- [ ] G09-03-02: Warning 알람(API p95 > 500ms 15분 지속, Error Budget 50% 소진)이 Slack `#sre-warning` 으로 라우팅되는가?
- [ ] G09-03-03: 주간 On-Call 로테이션(월요일 09:00 KST 교대) 1차+2차 백업 페어가 운영되는가?
- [ ] G09-03-04: Critical 1차 무응답 15분 시 2차 자동 에스컬레이션, 30분 시 팀 리드 에스컬레이션이 설정되어 있는가?
- [ ] G09-03-05: 알람 임계가 코드 하드코딩이 아닌 설정 파일 또는 IaC 로 관리되는가?

### 카테고리 4: Incident Response (G09-04)
- [ ] G09-04-01: 심각도 분류(SEV1/SEV2/SEV3) 정의가 운영되는가?
- [ ] G09-04-02: 인시던트 인지 시 incident 채널(`#inc-YYYYMMDD-NN`)이 자동·즉시 개설되는가?
- [ ] G09-04-03: 완화(Mitigate) 가 RCA 보다 우선되는 절차(rollback, feature flag, 트래픽 차단)가 문서화되어 있는가?
- [ ] G09-04-04: SEV1/SEV2 인시던트는 5영업일 내 Postmortem 작성이 의무화되어 있는가?
- [ ] G09-04-05: Postmortem 6 섹션(Summary, Timeline, Root Cause, What went well, What went poorly, Action Items)이 템플릿화되어 있는가?
- [ ] G09-04-06: Postmortem 이 Blameless 원칙(시스템·프로세스 결함 분석, 개인 책임 추궁 금지)을 따르는가?
- [ ] G09-04-07: 운영 환경에서 `print()` 또는 비구조화 로그가 사용되지 않는가? (OpenSearch 인덱싱 가능)
- [ ] G09-04-08: Prometheus metric label 에 user_id 등 고-cardinality 값이 사용되지 않는가?

