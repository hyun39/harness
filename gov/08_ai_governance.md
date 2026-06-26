# GOV-08 — AI/LLM 거버넌스

> **강제 대상**: LLM·Embedding 모델을 호출하는 모든 코드 (`apps/agent/`, `apps/api/` 등)
> **게이트**: 프롬프트 변경 PR 리뷰 / 모델 응답 schema 검증 테스트 / 월간 비용 한도 알람
> **연관 컴포넌트**: EP-09 RAG 에이전트 (Gemini, Qdrant), DR-16 (투자 자문 아님 명시)

---

## 필수 규칙 (MUST)

### LLM 호출 단일 채널 (ADR-0018)
- [ ] **모든 LLM·Embedding 호출은 `apps/agent` 서비스를 경유**한다
- [ ] api·airflow·frontend 등 다른 컴포넌트는 `langchain_google_genai`·`openai`·`anthropic` 등 LLM SDK를 직접 import 금지
- [ ] agent는 **LangServe + LangGraph + LangChain Core** 스택으로 구성된다 (`/invoke`, `/batch`, `/stream`, `/playground` 표준 endpoint 노출)
- [ ] 다른 서비스는 LangServe 클라이언트 SDK 또는 httpx로 agent를 호출한다
- [ ] CI 또는 린트로 비-agent 컴포넌트의 LLM SDK import를 차단한다

### 프롬프트 관리
- [ ] 시스템 프롬프트는 **코드 또는 별도 파일(`prompts/*.txt`)에 보관**한다 — DB·환경변수에 인라인 금지
- [ ] 프롬프트 변경은 **별도 커밋**으로 분리하고 커밋 메시지에 변경 의도를 명시한다 (`prompt(agent): adjust system role for sector context`)
- [ ] 프롬프트에 사용자 입력을 직접 포맷팅하지 않는다 — 별도 메시지 필드 또는 escape 처리
- [ ] **Few-shot 예시를 포함한 프롬프트는 PR 리뷰에서 의도된 응답 예시 함께 검토**한다

### 모델 응답 검증
- [ ] LLM 응답은 **반드시 schema로 파싱·검증**한다 (Pydantic, JSON schema)
- [ ] 검증 실패 시 fallback 응답 또는 명시적 에러를 반환한다 — 빈 응답·null 노출 금지
- [ ] 사용자에게 노출되는 모든 LLM 결과에는 **모델 버전·생성 시각이 메타데이터로 포함**된다
- [ ] 응답 길이·토큰 사용량을 로그로 기록한다 (비용·이상 감지용)

### 면책 및 책임 표시 (DR-16 강제)
- [ ] 분석·자문 성격의 LLM 응답은 **"투자 자문이 아님" 면책 문구**를 응답 본문 또는 헤더에 포함한다
- [ ] 사용자 UI에는 **"AI 생성 콘텐츠"임을 명시**한다 (배지 또는 푸터)
- [ ] LLM 응답을 자동 의사결정·자동 거래에 사용하지 않는다

### PII·민감정보 보호 (GOV-07 L4 연계)
- [ ] LLM 입력에 PII(이름, 이메일, 전화번호, 계좌)를 보내기 전 **마스킹·해시 처리** 필수
- [ ] 외부 LLM API(Gemini, OpenAI 등)에 보낸 데이터는 **감사 로그**로 기록 (해시값만)
- [ ] 시스템 프롬프트에 비밀값(API 키, 내부 endpoint URL)을 포함하지 않는다

---

## 비용 거버넌스 (MUST)

### 한도 정책
| 환경 | 월간 토큰 한도 | 일일 한도 | 위반 시 동작 |
|------|---------------|----------|------------|
| dev | 1M tokens | 50K | 경고 로그 |
| staging | 5M tokens | 200K | 경고 + Slack 알림 |
| production | 50M tokens | 2M | 자동 차단 (rate limiter) |

### 측정 항목 (OTel metrics)
- `llm.tokens.input.total` (모델·환경별)
- `llm.tokens.output.total`
- `llm.cost.usd.total`
- `llm.latency.p95`
- `llm.errors.rate`

### 비용 알람
```yaml
# 월간 예산 80% 도달 시 Slack #cost-alerts
alert: LLMBudgetWarning
expr: sum(llm_cost_usd_total) > 0.8 * monthly_budget
action: slack_notify(#cost-alerts)

# 95% 도달 시 자동 차단
alert: LLMBudgetCritical
expr: sum(llm_cost_usd_total) > 0.95 * monthly_budget
action: rate_limiter.disable_endpoint(/agent/analyze)
```

---

## 모델·임베딩 변경 정책 (MUST)

| 변경 유형 | 절차 |
|----------|------|
| 모델 교체 (Gemini 2.0 → 2.5) | **ADR 필수** + 평가 데이터셋 정량 비교 |
| 임베딩 모델 교체 | **ADR 필수** + Qdrant 컬렉션 재구축 계획 포함 |
| Temperature·max_tokens 등 hyperparameter | PR 리뷰만 (ADR 불필요) |
| 시스템 프롬프트 textual 변경 | PR 리뷰 + 회귀 테스트 통과 |

ADR 양식: `docs/adr/ADR-NNNN-llm-model-{model-name}.md` (GOV-02 형식 준수)

---

## 평가 (Evaluation) 게이트 (SHOULD → MUST 전환 예정)

### Eval 데이터셋
- 위치: `apps/agent/evals/{feature}/dataset.jsonl`
- 형식: `{"input": ..., "expected_keywords": [...], "must_not_contain": [...]}`
- 최소 30 케이스 / 핵심 시나리오

### CI 통합
```bash
# 핵심 응답 품질 회귀 방지
pytest apps/agent/evals/ --eval-threshold=0.85
# 통과율 85% 미만 시 PR 차단
```

### 평가 항목
- 사실성 (factuality) — 응답에 hallucination 키워드 미포함
- 일관성 (consistency) — 동일 입력 5회 호출 결과 의미 유사도 ≥ 0.8
- 형식 (format) — schema 검증 통과율 100%
- 면책 (safety) — DR-16 면책 문구 포함률 100%

---

## Hallucination 모니터링

### 런타임 검증
- 사실성 검증: 응답에서 추출한 통계치·날짜·티커가 실제 DB 값과 일치하는지 cross-check
- 출처 검증: RAG retrieval된 컨텍스트가 응답 근거로 인용되었는지 확인
- 명시적 거부 체크: 모델이 "정보 없음"을 응답해야 할 케이스에 임의 답변 생성 여부

### 측정 지표
| 지표 | 목표 | 측정 |
|------|------|------|
| Cross-check 통과율 | ≥ 95% | 일별 batch 검증 |
| 인용 누락률 | ≤ 5% | retrieval 메타데이터 vs 응답 |
| 임의 답변 생성률 | ≤ 1% | 골드셋 비교 |

---

## 금지 사항 (MUST NOT)

| 금지 | 이유 |
|------|------|
| 평가·검증 없이 모델 교체 | 응답 품질 회귀 감지 불가 |
| 시스템 프롬프트에 사용자 데이터 직접 삽입 | Prompt injection 취약 |
| LLM 응답을 직접 SQL·코드 실행에 사용 | RCE 위험 |
| 외부 LLM에 PII 평문 전송 | GOV-07 위반 |
| LLM 응답을 캐시 키 없이 재사용 | 입력별 결과 다름·일관성 저하 |
| 모델 응답 100% 수용 (검증 없음) | hallucination 노출 |
| 비용·토큰 사용량 로그 미수집 | 이상 사용 탐지 불가 |

---

## 추적성

```
specs/features/agent/*_spec.md (FR-22~25)
    ↓
prompts/*.txt (시스템 프롬프트 단일 소스)
    ↓
apps/agent/app/services/llm.py (모델 호출 + schema 검증)
    ↓
apps/agent/evals/*.jsonl (회귀 테스트)
    ↓
OTel metrics (cost, latency, errors)
    ↓
LIVING_DOCS.md / cost dashboard
```

---

## 검증 체크리스트

> 이 가이드 기준으로 application을 audit할 때 사용. 각 항목은 yes/no.
> 통합 인덱스: [`specs/_methodology/CHECKLIST.md`](../CHECKLIST.md)

### 카테고리 0: LLM 호출 단일 채널 (G08-00, ADR-0018)
- [ ] G08-00-01: 모든 LLM·Embedding 호출이 `apps/agent` 서비스를 경유하는가?
- [ ] G08-00-02: api·airflow·frontend 등 다른 컴포넌트의 의존성에 LLM SDK(`langchain_google_genai`, `openai`, `anthropic` 등)가 없는가?
- [ ] G08-00-03: agent가 LangServe + LangGraph + LangChain Core 스택으로 구성되어 있는가?
- [ ] G08-00-04: agent가 LangServe 표준 endpoint(`/invoke`, `/batch`, `/stream`, `/playground`)를 노출하는가?
- [ ] G08-00-05: 다른 서비스가 LangServe 클라이언트 SDK 또는 httpx로만 agent를 호출하는가?
- [ ] G08-00-06: CI 또는 린트로 비-agent 컴포넌트의 LLM SDK import가 차단되는가?

### 카테고리 1: 프롬프트 관리 (G08-01)
- [ ] G08-01-01: 시스템 프롬프트가 코드 또는 별도 파일(`prompts/*.txt`)에 보관되어 있는가? (DB·환경변수에 인라인 금지)
- [ ] G08-01-02: 프롬프트 변경이 별도 커밋으로 분리되어 있는가? (커밋 메시지에 변경 의도 명시)
- [ ] G08-01-03: 사용자 입력을 시스템 프롬프트에 직접 포맷팅하지 않는가? (별도 메시지 필드 또는 escape 처리)
- [ ] G08-01-04: Few-shot 예시 포함 프롬프트는 PR 리뷰에서 의도된 응답 예시와 함께 검토되었는가?

### 카테고리 2: 모델 응답 검증 (G08-02)
- [ ] G08-02-01: LLM 응답이 schema(Pydantic, JSON schema)로 파싱·검증되는가?
- [ ] G08-02-02: schema 검증 실패 시 fallback 응답 또는 명시적 에러를 반환하는가? (빈 응답·null 노출 금지)
- [ ] G08-02-03: 사용자에게 노출되는 LLM 결과에 모델 버전·생성 시각 메타데이터가 포함되어 있는가?
- [ ] G08-02-04: 응답 길이·토큰 사용량을 로그로 기록하는가?

### 카테고리 3: 면책·책임 (G08-03)
- [ ] G08-03-01: 분석·자문 성격 LLM 응답에 "투자 자문이 아님" 면책 문구가 포함되어 있는가? (DR-16)
- [ ] G08-03-02: 사용자 UI에 "AI 생성 콘텐츠"임이 배지·푸터로 명시되어 있는가?
- [ ] G08-03-03: LLM 응답을 자동 의사결정·자동 거래에 사용하지 않는가?

### 카테고리 4: PII·민감정보 (G08-04)
- [ ] G08-04-01: LLM 입력에 PII(이름·이메일·전화·계좌)를 보내기 전 마스킹·해시 처리하는가?
- [ ] G08-04-02: 외부 LLM API에 보낸 데이터를 감사 로그(해시값만)로 기록하는가?
- [ ] G08-04-03: 시스템 프롬프트에 비밀값(API 키, 내부 endpoint URL)이 포함되어 있지 않은가?

### 카테고리 5: 비용 거버넌스 (G08-05)
- [ ] G08-05-01: 환경별 월간·일일 토큰 한도가 정의되어 있는가? (dev/staging/production)
- [ ] G08-05-02: OTel 측정 항목 5종(input·output tokens, cost USD, latency p95, errors rate)이 emit 되는가?
- [ ] G08-05-03: 월간 예산 80% 도달 시 Slack 알람이 트리거되는가?
- [ ] G08-05-04: 95% 도달 시 자동 차단(rate limiter)이 동작하는가?

### 카테고리 6: 모델 변경·평가 (G08-06)
- [ ] G08-06-01: 모델 교체 시 ADR이 작성되어 있는가? (`docs/adr/ADR-NNNN-llm-model-*.md`)
- [ ] G08-06-02: 임베딩 모델 교체 시 Qdrant 컬렉션 재구축 계획이 ADR에 포함되었는가?
- [ ] G08-06-03: 시스템 프롬프트 textual 변경에 회귀 테스트가 통과되었는가?
- [ ] G08-06-04: Eval 데이터셋이 `apps/agent/evals/{feature}/dataset.jsonl`에 최소 30 케이스 이상 존재하는가?
- [ ] G08-06-05: CI에 `--eval-threshold=0.85` 게이트가 설정되어 있는가?

### 카테고리 7: Hallucination 모니터링 (G08-07)
- [ ] G08-07-01: 응답에서 추출한 통계치·날짜·티커가 실제 DB 값과 cross-check 되는가?
- [ ] G08-07-02: RAG retrieval된 컨텍스트가 응답 근거로 인용되었는지 검증되는가?
- [ ] G08-07-03: "정보 없음"을 응답해야 할 케이스에 임의 답변 생성률이 측정되는가? (≤ 1%)
- [ ] G08-07-04: Cross-check 통과율(≥ 95%)이 일별 batch 검증으로 추적되는가?

