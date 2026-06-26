# harness — 개발 전체 흐름 가이드

> **목적**: 기능 하나가 vision에서 출발해 살아있는 문서 + 실제 인프라까지 도달하는
> 전 과정을 사람이 할 일 / 자동 실행으로 구분해 한눈에 파악할 수 있게 정리한 참조 문서.
>
> **STEP 번호·표준 프롬프트 상세**: [`02_PROMPT_GUIDE.md`](./02_PROMPT_GUIDE.md) 참조.

---

## 1. 전체 흐름 다이어그램

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 PHASE / LOOP                                         담당
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 [PHASE 1 — 제품 전략 (1회)]
  ┌────────────────────────────────────────────┐
  │  STEP 1  00_vision.md                      │  👤 비즈니스 컨텍스트
  │  WHY — OKR, 이해관계자, 페르소나, 핵심 원칙  │  🤖 AI 구조화·초안
  │                                            │  👤 내용 검증
  └────────────────┬───────────────────────────┘
                   │ OKR → FR 매핑
                   ▼
  ┌────────────────────────────────────────────┐
  │  STEP 2  01_domain.md                      │  👤 도메인 지식
  │  WHAT — Bounded Context, 유비쿼터스 언어,   │  🤖 AI 초안 (모델·규칙)
  │          데이터 모델, 도메인 규칙(DR)         │  👤 DR 정확성 검증
  └────────────────┬───────────────────────────┘
                   │ DR → Feature 추적
                   ▼
  ┌────────────────────────────────────────────┐
  │  STEP 3  02_epics.md                       │  🤖 AI 초안 (Epic 분해)
  │  HOW — Epic > Feature > FR > DR 매핑        │  👤 우선순위·범위 검증
  └────────────────┬───────────────────────────┘
                   │ Feature 단위로 분해
                   ▼

 [PHASE 2 — Feature 개발]

 ┌─ LOOP 1 (Feature별 반복 — STEP 4 ~ 6a) ───────────────────────────────┐
 │                                                                       │
 │  STEP 4   비즈니스 스펙                       🤖 AI 초안 → 👤 검증     │
 │  ┌──────────────────────────────────────────┐                         │
 │  │  specs/features/**/*_spec.md             │                         │
 │  │  - 배경 및 목적 / 기능 요건 (FR 상세)     │                         │
 │  │  - 문서 정보: OKR ↑ DR ↑ Epic ↑ FR ↑     │                         │
 │  └──────────────────┬───────────────────────┘                         │
 │                     │ 인수기준 도출                                    │
 │                     ▼                                                 │
 │  STEP 5   .feature 작성                     🤖 AI 초안 → 👤 검증     │
 │  ┌──────────────────────────────────────────┐                         │
 │  │  specs/features/**/*.feature       │                         │
 │  │  실행 가능한 스펙 (Gherkin)               │                         │
 │  └──────────────────┬───────────────────────┘                         │
 │                     ▼                                                 │
 │  STEP 6   pytest 실행 → Red 확인             🤖 자동 (로컬/CI)         │
 │           └─ StepDefinitionNotFoundError 확인                         │
 │                     ▼                                                 │
 │  STEP 6a  Stub 코드                          🤖 AI 초안 → 👤 DR 확인  │
 │  ┌──────────────────────────────────────────┐                         │
 │  │  apps/api/app/**/*.py (인메모리 stub)          │                         │
 │  │  step이 호출할 인터페이스 + DR 로직 실제 구현                       │
 │  │  DB/외부 API 연동 없이 dict/dataclass     │                         │
 │  └──────────────────┬───────────────────────┘                         │
 │                                                                       │
 └─ 모든 Feature 완료까지 반복 ──────────────────────────────────────────┘
                       │ 전체 stub 완성
                       ▼

 ┌─ MILESTONE (1회 — STEP 6b) ──────────────────────────────────────────┐
 │                                                                       │
 │  STEP 6b  UI/UX Mockup                        🤖 AI 초안 → 👤 인수기준 │
 │  ┌──────────────────────────────────────────┐                         │
 │  │  apps/frontend/src/mockup.html                │                         │
 │  │  stub 데이터 기반 단일 HTML — 시나리오별   │                         │
 │  │  화면 상태 시각화 → 이해관계자 검증         │                         │
 │  └──────────────────────────────────────────┘                         │
 │                                                                       │
 └─ 인수기준 확정 ───────────────────────────────────────────────────────┘
                       │
                       ▼

 ┌─ LOOP 2 (Feature별 반복 — STEP 7a ~ 7b) ──────────────────────────────┐
 │                                                                       │
 │  STEP 7a  실제 production 코드 뼈대            🤖 AI 초안 → 👤 검증    │
 │           (Walking Skeleton)                                          │
 │  ┌──────────────────────────────────────────┐                         │
 │  │  apps/airflow/dags/*.py        — @dag, @task  │                         │
 │  │  apps/api/app/routers/*.py     — FastAPI 실제  │                         │
 │  │  apps/frontend/src/App.*       — React/Vue 실제│                         │
 │  │  데이터는 6a stub 인터페이스 호출 (인메모리)│                         │
 │  └──────────────────┬───────────────────────┘                         │
 │                     ▼                                                 │
 │  STEP 7b  test step skeleton 자동 생성 + 연결  🤖 AI 초안 → 👤 검증    │
 │  ┌──────────────────────────────────────────┐                         │
 │  │  pytest --generate-missing → skeleton    │                         │
 │  │  → 7a 실제 production 코드 호출로 연결    │                         │
 │  │  → 시나리오 골격 PASS (smoke level)      │                         │
 │  │  *_steps.py + test_*.py                  │                         │
 │  └──────────────────────────────────────────┘                         │
 │                                                                       │
 └─ 모든 Feature 골격 통과까지 반복 ─────────────────────────────────────┘
                       │ 전체 골격 PASS
                       ▼

 ┌─ MILESTONE 2 (1회 — STEP 8b) ─────────────────────────────────────────┐
 │                                                                       │
 │  STEP 8b  Mock-data E2E                       🤖 AI 초안 → 👤 검증    │
 │  ┌──────────────────────────────────────────┐                         │
 │  │  apps/frontend/playwright.config.ts           │                         │
 │  │  apps/frontend/tests/e2e/*.spec.ts            │                         │
 │  │  frontend(USE_MOCK=true) + backend       │                         │
 │  │  (USE_INMEMORY=true) 동시 기동, 풀스택    │                         │
 │  │  시각 검증 — 외부 의존 모두 mock          │                         │
 │  └──────────────────────────────────────────┘                         │
 │                                                                       │
 └─ E2E Green 후 LOOP 3 (세부 로직)으로 ─────────────────────────────────┘
                       │ 풀스택 골격 통과
                       ▼

 ┌─ LOOP 3 (Feature별 반복 — STEP 7c ~ 8) ───────────────────────────────┐
 │                                                                       │
 │  STEP 7c  Step 세부 로직                     🤖 AI 초안 → 👤 DR 검증  │
 │  ┌──────────────────────────────────────────┐                         │
 │  │  *_steps.py 시나리오별 mock_records 구성  │                         │
 │  │  도메인 규칙(DR) 준수 assert 강화         │                         │
 │  └──────────────────┬───────────────────────┘                         │
 │                     ▼                                                 │
 │  STEP 8   pytest 실행 → Green 확인           🤖 자동 (로컬/CI)         │
 │           └─ N passed                                                 │
 │                                                                       │
 └─ 모든 Feature Green까지 반복 ─────────────────────────────────────────┘
                       │ PR 생성
                       ▼

 [PHASE 3 — CI / Living Docs (1회 설정)]
  ┌────────────────────────────────────────────┐
  │  STEP 9   PR 생성                          │  👤 개발자
  │  STEP 10  CI 자동 실행                      │  🤖 GitHub Actions
  │           ① Lint (ruff, black)             │
  │           ② API/Airflow/Frontend Tests     │
  │           ③ Coverage 합산 ≥ 80%             │
  │           ④ Living Docs 자동 커밋           │
  │           ⑤ 보안 스캔 (Trivy)               │
  │  STEP 11  Living Docs 설정                 │  🤖 gen_living_docs.py
  │           docs/LIVING_DOCS.md             │
  └────────────────┬───────────────────────────┘
                   │
                   ▼

 [PHASE 4 — 유지 (지속/주기적)]
  ┌────────────────────────────────────────────┐
  │  STEP 12  스펙 일관성 검증                   │  🤖 AI → 👤 검증
  │  - FR/Epic/DR/OKR 필드, 잔존 Gherkin 등     │
  └────────────────┬───────────────────────────┘
                   │
                   ▼

 [PHASE 5 — 데이터 소스 교체 (Stub Data → Real Data)]
  ┌────────────────────────────────────────────┐
  │  STEP 13  DB 어댑터 구현                    │  🤖 AI 초안 → 👤 검증
  │  - _store dict → PostgreSQL/DW/Mart        │
  │           ▼                                │
  │  STEP 14  외부 API 어댑터 구현              │  🤖 AI 초안 → 👤 검증
  │  - mock_records → 실제 외부 API            │
  │           ▼                                │
  │  STEP 15  인프라 runtime 구축               │  🤖 AI 초안 → 👤 검증
  │  - infra/compose/*.yml (프로젝트 서비스 구성)│
  │    DB / 인증 / 관측 / 스케줄러 등            │
  │  - infra/helm/ + infra/k8s/ (운영)         │
  │           ▼                                │
  │  STEP 16  E2E 통합 테스트                   │  🤖 AI 초안 → 👤 검증
  │  - testcontainers PostgreSQL               │
  │  - @pytest.mark.e2e + CI e2e.yml 분리      │
  └────────────────────────────────────────────┘
                   │ 인메모리 + 실제 인프라 모두 Green
                   ▼

 [완료 — 배포 가능 상태]
  ┌────────────────────────────────────────────┐
  │  docs/LIVING_DOCS.md (CI 자동 갱신)        │  🤖 자동
  │  ✅ 시나리오별 결과 반영                     │
  └────────────────────────────────────────────┘
```

---

## 2. 단계별 상세

| PHASE | LOOP | STEP | 단계 | 담당 | 출력물 | 위치 |
|-------|------|------|------|------|--------|------|
| 1 | — | 1 | vision 작성 | 🤖 AI → 👤 검증 | `00_vision.md` | `specs/product/` |
| 1 | — | 2 | domain 정의 | 🤖 AI → 👤 검증 | `01_domain.md` | `specs/product/` |
| 1 | — | 3 | Epic/Feature 목록 | 🤖 AI → 👤 검증 | `02_epics.md` | `specs/product/` |
| 2 | LOOP 1 | 4 | 비즈니스 스펙 | 🤖 AI → 👤 검증 | `*_spec.md` | `specs/features/{domain}/` |
| 2 | LOOP 1 | 5 | .feature 작성 | 🤖 AI → 👤 검증 | `*.feature` | `specs/features/{domain}/` |
| 2 | LOOP 1 | 6 | Red 확인 | 🤖 pytest | 실패 리포트 | 로컬/CI |
| 2 | LOOP 1 | 6a | Stub 코드 (인메모리, 가벼운 pass-through + DR 로직) | 🤖 AI → 👤 DR 확인 | `{domain}/*.py`, `core/dependencies.py` | `apps/{service}/app/` |
| 2 | MILESTONE | 6b | UI/UX Mockup | 🤖 AI → 👤 인수기준 확정 | `mockup.html` | `apps/frontend/src/` |
| 2 | LOOP 2 | 7a | **실제 production 코드 뼈대** (Walking Skeleton) | 🤖 AI → 👤 검증 | `apps/airflow/dags/*.py`, `apps/api/app/routers/*.py`, `apps/frontend/src/components/*` | 영역별 |
| 2 | LOOP 2 | 7b | test step skeleton 자동 생성 + 7a 호출로 연결 | 🤖 `--generate-missing` + AI → 👤 검증 | `*_steps.py`, `test_*.py` | `*/tests/bdd/steps/` |
| 2 | MILESTONE 2 | 8b | Mock-data E2E (Playwright 풀스택) | 🤖 AI → 👤 검증 | `playwright.config.ts`, `tests/e2e/*.spec.ts` | `apps/frontend/` |
| 2 | LOOP 3 | 7c | Step 세부 로직 | 🤖 AI → 👤 DR 검증 | `*_steps.py` (강화) | `*/tests/bdd/steps/` |
| 2 | LOOP 3 | 8 | Green 확인 | 🤖 pytest | 통과 리포트 | 로컬/CI |
| 3 | — | 9 | PR 생성 | 👤 개발자 | Pull Request | GitHub |
| 3 | — | 10 | CI 자동 실행 | 🤖 GitHub Actions | CI 결과 | GitHub Actions |
| 3 | — | 11 | Living Docs 설정 | 🤖 gen_living_docs.py | `LIVING_DOCS.md` | `docs/` |
| 4 | — | 12 | 스펙 일관성 검증 | 🤖 AI → 👤 검증 | 검증 리포트 | (주기적) |
| 5 | — | 13 | DB 어댑터 (`_store` → PostgreSQL) | 🤖 AI → 👤 검증 | `repositories/`, `db/` | `apps/api/app/` |
| 5 | — | 14 | 외부 API 어댑터 (`mock_records` → 실제 API) | 🤖 AI → 👤 검증 | `adapters/*.py` | `apps/{service}/app/` |
| 5 | — | 15 | 인프라 runtime 구축 | 🤖 AI → 👤 검증 | `infra/compose/*.yml`, `infra/helm/`, `infra/k8s/` | `infra/` |
| 5 | — | 16 | E2E 통합 테스트 (testcontainers) | 🤖 AI → 👤 검증 | `tests/e2e/conftest.py`, `test_pipeline_e2e.py`, `.github/workflows/e2e.yml` | `apps/api/tests/e2e/`, `.github/` |

---

## 3. 출력물 유형 정의

### 📄 문서 (Document) — 사람이 작성·관리

| 출력물 | 파일 | 갱신 시점 | STEP |
|--------|------|----------|------|
| 제품 비전 | `specs/product/00_vision.md` | 제품 방향 변경 시 | 1 |
| 도메인 모델 | `specs/product/01_domain.md` | 도메인 규칙 변경 시 | 2 |
| Epic/Feature 목록 | `specs/product/02_epics.md` | Feature 추가/완료 시 | 3 |
| 비즈니스 스펙 | `specs/features/**/*_spec.md` | Feature 개발 시작 시 | 4 |
| 요구사항 검증 목업 | `apps/frontend/src/mockup.html` | UI 요건 변경 시 | 6b |

### ⚙️ 실행 스펙 (Executable Spec) — 사람이 작성, pytest가 실행

| 출력물 | 파일 | 갱신 시점 | STEP |
|--------|------|----------|------|
| Gherkin 시나리오 | `specs/features/**/*.feature` | 인수기준 변경 시 | 5 |

### 🧪 테스트 코드 (Test Code) — 🤖 skeleton 자동 → AI 초안 → 👤 검증

| 출력물 | 파일 | 생성 방식 | STEP |
|--------|------|----------|------|
| BDD Step skeleton | `*/tests/bdd/steps/**/*_steps.py` | 🤖 `pytest --generate-missing` | 7b |
| Step 골격 (실제 코드 호출) | `*/tests/bdd/steps/**/*_steps.py` | 🤖 AI 초안 → 👤 골격 통과 확인 | 7b |
| 시나리오 등록 | `*/tests/bdd/steps/**/test_*.py` | 🤖 AI 초안 → 👤 검증 | 7b |
| Step 세부 로직 | `*/tests/bdd/steps/**/*_steps.py` | 🤖 AI 초안 → 👤 DR 검증 | 7c |
| Test Fixture | `*/conftest.py`, `*/factories.py` | 👤 사람 (공유 상태 설계) | — |
| E2E 테스트 | `apps/api/tests/e2e/` | 🤖 AI 초안 → 👤 검증 | 16 |

### 💻 프로덕션 코드 (Production Code) — 🤖 AI 초안 → 👤 검증

| 출력물 | 파일 | 생성 방식 | STEP |
|--------|------|----------|------|
| Stub 데이터 어댑터 | `apps/api/app/pipeline/*.py`, `apps/api/app/core/dependencies.py` | 🤖 AI 초안 → 👤 DR 준수 확인 | 6a |
| Walking Skeleton (Pipeline) | `apps/airflow/dags/*.py` (real `@dag/@task`) | 🤖 AI 초안 → 👤 검증 | 7a |
| Walking Skeleton (API) | `apps/api/app/main.py`, `apps/api/app/routers/*.py` | 🤖 AI 초안 → 👤 비즈니스 로직 확인 | 7a |
| Walking Skeleton (Frontend) | `apps/frontend/src/App.*`, `apps/frontend/src/components/*` | 🤖 AI 초안 → 👤 검증 | 7a |
| 스키마 | `apps/api/app/schemas/*.py` | 🤖 AI 초안 → 👤 API 계약 확인 | 7a |
| DB 어댑터 | `apps/api/app/repositories/`, `apps/api/app/db/` | 🤖 AI 초안 → 👤 검증 | 13 |
| 외부 API 어댑터 | `apps/api/app/adapters/*.py` | 🤖 AI 초안 → 👤 검증 | 14 |

> **AI가 보장하지 못하는 것**: 비즈니스 로직의 정확성, 도메인 규칙(DR) 준수 여부는
> 반드시 사람이 확인한다.

### 🛠️ 인프라 설정 (Infra Config) — 🤖 AI 초안 → 👤 검증

> 구체적인 서비스 구성은 프로젝트 기술 스택에 따라 결정된다.  
> 아래는 일반적인 패턴이며, 적용 예시는 [harness-sample-sp500](https://github.com/hyun39/harness-sample-sp500)을 참조.

| 출력물 | 파일 패턴 | 갱신 시점 | STEP |
|--------|----------|----------|------|
| DB 서비스 | `infra/compose/{db}.yml` | DB 버전·포트 변경 시 | 15 |
| 인증 서비스 | `infra/compose/{auth}.yml`, `infra/{auth}/` | 인증 정책 변경 시 | 15 |
| 로그·관측 서비스 | `infra/compose/{observability}.yml` | 파이프라인 변경 시 | 15 |
| 파이프라인 스케줄러 | `infra/compose/{scheduler}.yml`, `apps/{scheduler}/Dockerfile` | 이미지·의존성 변경 시 | 15 |
| Helm values | `infra/helm/*.yaml` | 운영 배포 시 | 15 |
| K8s kustomize | `infra/k8s/` (base + overlays) | 운영 배포 시 | 15 |

### 🤖 자동 생성 산출물 (CI Artifact) — CI가 생성

| 출력물 | 파일 | 생성 시점 | 생성 도구 |
|--------|------|----------|----------|
| 살아있는 문서 | `docs/LIVING_DOCS.md` | CI 완료 시 | `scripts/gen_living_docs.py` |
| JSON 테스트 리포트 | `.report_*.json` | CI 테스트 실행 시 | `pytest-json-report` |
| 커버리지 XML | `apps/api/reports/coverage.xml` | CI 완료 시 | `pytest-cov` |

---

## 4. 추적성 구조 (Traceability)

```
vision (OKR)
  │  관련 FR 목록 → 02_epics.md OKR→FR 매핑 섹션
  ▼
domain (DR)
  │  DR-01~NN → 02_epics.md DR→Feature 추적 섹션
  ▼
epics (Feature)
  │  스펙 파일 링크 → specs/features/**/*_spec.md
  ▼
spec (문서 정보)
  │  관련 OKR ↑ / DR ↑ / FR ↑ / Epic ↑
  │  인수기준 → .feature 파일 링크
  ▼
.feature
  ▼
stub 데이터 (LOOP 1 6a) + Walking Skeleton (LOOP 2 7a)
  │      → BDD step (LOOP 2 7b 골격 → LOOP 3 7c 세부)
  ▼
LIVING_DOCS.md   ← 시나리오별 ✅ / ❌ 자동 반영 (PHASE 3)
  │
  ▼ (PHASE 5)
실제 데이터 어댑터 (DB / 외부 API) + 인프라 runtime
  - Walking Skeleton 코드는 무수정, 데이터 소스만 교체
  ▼
E2E Living Docs ← 실제 인프라 환경 BDD Green
```

---

## 5. 담당별 역할 요약

### 👤 사람이 반드시 제공해야 할 것 (AI가 대신할 수 없음)

```
  - 비즈니스 목표와 맥락 (vision의 WHY)
  - 도메인 전문 지식 (DR이 실제 업무 규칙과 맞는지)
  - 인수기준 확정 (시나리오 + STEP 6b 목업이 실제 요건을 표현하는지)
  - AI 생성 결과물 전체 검증
  - PR 코드 리뷰 + 승인
  - LOOP 2 7a Walking Skeleton의 framework 선택 (FastAPI vs Spring, React vs Vue 등)
  - PHASE 5 실제 데이터 소스 결정 (DB 종류, 시세 API 선택, 인증 정책 등)
```

### 🤖 AI/도구가 초안을 생성하는 것

```
  - AI (Claude Code)           → vision / domain / epics 구조화 및 초안 (1~3)
  - AI (Claude Code)           → *_spec.md 초안 (4)
  - AI (Claude Code)           → .feature 시나리오 초안 (5)
  - AI (Claude Code)           → 인메모리 stub 데이터 어댑터 초안 (6a, DR 로직 포함)
  - AI (Claude Code)           → UI/UX mockup.html 초안 (6b, stub 기반)
  - AI (Claude Code)           → Walking Skeleton 초안 (7a — DAG / API / Frontend)
  - pytest --generate-missing  → BDD Step 함수 skeleton 생성 (7b)
  - AI (Claude Code)           → Step 골격 + 7a 호출 연결 (7b) 및 세부 로직 (7c) 초안
  - pytest                     → Red/Green 자동 검증 (6, 8)
  - CI (GitHub Actions)        → Lint, 테스트, 커버리지, 보안 스캔 (10)
  - gen_living_docs.py         → LIVING_DOCS.md 자동 커밋 (11)
  - AI (Claude Code)           → DB 어댑터 / 외부 API 어댑터 / 인프라 runtime 초안 (13~15)
  - AI (Claude Code)           → E2E testcontainers fixture 초안 (16)
```

### ⚠️ AI가 보장하지 못하는 것 (반드시 사람이 확인)

```
  - 비즈니스 목표가 문서에 정확히 반영됐는가  (1~4 단계)
  - 시나리오가 실제 비즈니스 흐름을 표현하는가  (5 단계)
  - 비즈니스 로직이 실제 요건과 일치하는가  (6a, 7c 단계)
  - 도메인 규칙(DR)이 코드에 올바르게 반영됐는가  (6a, 7c 단계)
  - LOOP 2 7a Walking Skeleton이 실제 framework을 사용하는지 (가짜 wrapper 금지)  (7a)
  - PHASE 5 stub data → 실제 데이터 소스 교체 시 인터페이스 경계 유지 여부  (13~16)
  - 외부 API 자격 증명·rate-limit·실패 처리 정책  (14)
  - distroless 컨테이너 healthcheck 문법 (curl/wget 없음 — /proc/net/tcp6 grep 등 우회 필요)  (15)
  - alembic version_table 충돌 (스케줄러와 DB 공유 시 앱 전용 version_table 분리 필수)  (13, 15)
  - testcontainers 데이터 격리 (ephemeral DB — 운영 DB에 데이터가 남지 않음)  (16)
```

---

## 6. 파일 위치 한눈에 보기

> 아래는 권장 프로젝트 구조다. 기술 스택(API 프레임워크, 스케줄러 등)에 따라 `apps/` 하위는 달라진다.  
> 적용 예시: [harness-sample-sp500](https://github.com/hyun39/harness-sample-sp500)

```
{your-project}/
│
├── specs/
│   ├── product/
│   │   ├── 00_vision.md           📄 STEP 1
│   │   ├── 01_domain.md           📄 STEP 2
│   │   └── 02_epics.md            📄 STEP 3
│   │
│   └── features/                  📄 STEP 4~5 — Feature별 비즈니스 스펙 + Gherkin
│       └── {domain}/
│           ├── {feature}_spec.md
│           └── {feature}.feature
│
├── docs/                          📄 아키텍처·ADR·Living Docs
│   ├── adr/                       📄 Architecture Decision Records (gov/02 기준)
│   └── LIVING_DOCS.md             🤖 STEP 11 — CI 자동 생성
│
├── apps/
│   ├── api/                       (FastAPI / Spring Boot 등)
│   │   ├── app/
│   │   │   ├── {domain}/          💻 STEP 6a — stub 데이터 어댑터 (DR 포함)
│   │   │   ├── core/              💻 STEP 6a — 인메모리 _store, 인증 stub
│   │   │   ├── main.py            💻 STEP 7a — Walking Skeleton (앱 진입점)
│   │   │   ├── routers/           💻 STEP 7a — Walking Skeleton (엔드포인트)
│   │   │   ├── schemas/           💻 STEP 7a — 응답 스키마
│   │   │   ├── repositories/      💻 STEP 13 — DB 어댑터 (PHASE 5)
│   │   │   ├── db/                💻 STEP 13 — ORM 세션·모델 (PHASE 5)
│   │   │   └── adapters/          💻 STEP 14 — 외부 API 어댑터 (PHASE 5)
│   │   └── tests/
│   │       ├── bdd/steps/         🧪 STEP 7b~7c
│   │       └── e2e/               🧪 STEP 16 (PHASE 5)
│   │
│   ├── {scheduler}/               (Airflow / Celery / cron 등, 선택)
│   │   ├── dags/                  💻 STEP 7a — Walking Skeleton (파이프라인)
│   │   └── tests/bdd/steps/       🧪 STEP 7b~7c
│   │
│   ├── frontend/                  (React / Vue 등, 선택)
│   │   ├── src/
│   │   │   ├── mockup.html        📄 STEP 6b — 요구사항 검증 목업
│   │   │   ├── App.*              💻 STEP 7a — Walking Skeleton
│   │   │   └── components/        💻 STEP 7a — 실제 컴포넌트
│   │   └── tests/
│   │       ├── bdd/steps/         🧪 STEP 7b~7c
│   │       └── e2e/               🧪 STEP 8b (Playwright, MILESTONE 2)
│   │
│   └── {agent}/                   (LLM Agent, 선택)
│
├── scripts/
│   └── gen_living_docs.py         🤖 STEP 11
│
├── infra/                         🛠️ PHASE 5 STEP 15 — 인프라 런타임
│   ├── compose/                   🛠️ Docker Compose 서비스 정의
│   │   └── {service}.yml          (DB, 인증, 관측, 스케줄러 등 프로젝트별)
│   ├── helm/                      🛠️ K8s upstream chart values (운영)
│   └── k8s/                       🛠️ kustomize base + overlays (운영)
│
├── docker-compose.yml             🛠️ 루트 entry point (`include: infra/compose/*.yml`)
├── docker-compose.e2e.yml         🛠️ MILESTONE 2 STEP 8b — Mock-data E2E
└── .github/workflows/
    ├── ci.yml                     🤖 STEP 10
    └── e2e.yml                    🤖 STEP 16 (PHASE 5)
```

---

## 7. 출력물 유형 아이콘 범례

| 아이콘 | 유형 | 담당 |
|--------|------|------|
| 📄 | 문서 (Document) | 👤 사람 작성·관리 |
| ⚙️ | 실행 스펙 (Executable Spec) | 👤 사람 작성 / 🤖 pytest 실행 |
| 🧪 | 테스트 코드 (Test Code) | 🤖 skeleton 자동 + AI 초안 → 👤 검증 |
| 💻 | 프로덕션 코드 (Production Code) | 🤖 AI 초안 → 👤 검증 |
| 🤖 | 자동 생성 산출물 (CI Artifact) | 🤖 CI 완전 자동 |
| 🛠️ | 인프라 설정 (Infra Config) | 🤖 AI 초안 → 👤 검증 |
