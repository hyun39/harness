# STD — 구현 표준 인덱스

> 각 `0N_*.md` 파일은 BDD/SDD 맥락에 맞게 정제한 **요약·실행 패턴**이다.  
> 같은 번호의 **전체 분량 명세**는 [`detail/`](./detail/) 아래에 두었으며, `specs/edit/` 를 열지 않아도 된다.

---

## 파일 목록

| 파일 | 핵심 내용 | 상세 (`std/detail/`) |
|------|---------|----------------------|
| `01_backend.md` | FastAPI·SpringBoot 계층·에러·비동기 패턴 | `backend_fastapi.md`, `backend_springboot.md` |
| `02_frontend.md` | React 상태·API 클라이언트·에러 처리 | `frontend.md` |
| `03_database.md` | 스키마 설계·인덱스·마이그레이션 | `database.md` |
| `04_auth.md` | Keycloak PKCE·JWT 검증·역할 | `auth_keycloak.md` |
| `05_infra.md` | Docker·K8s·CI/CD 핵심 패턴 | `infra_cicd.md` |
| `06_observability.md` | OTel 계측·구조화 로그·OpenSearch | `observability_otel_opensearch.md` |
| `07_ai.md` | ReAct Agent·RAG·LLM 체인 | `agent.md`, `rag.md` |
| `08_data_pipeline.md` | Airflow·ODS→DW→MART | `data_pipeline_airflow.md` |
| `09_project_tracker_excel.md` | 프로젝트 추적 Excel 재생성 표준 (재프롬프트) | — |
| `10_architecture_doc.md` | ARCHITECTURE.md 재작성 표준 (재프롬프트) | — |
| `11_project_tracker_csv.md` | PROJECT_TRACKER.csv 재생성 표준 (재프롬프트) | — |
| `12_adr_writing.md` | ADR 신규 작성 표준 (재프롬프트) | — |

> **STD ↔ GOV 분리 원칙**:
> - `std/`는 *어떻게 짤지* (구현 패턴, 코드 예시)
> - `gov/`는 *왜·언제·반드시* (정책, 강제 게이트)
> 두 디렉터리는 같은 영역을 다르게 다룬다 — 같이 보면 완성된 가이드가 된다.

---

## BDD와 STD의 연결

> std/ 패턴은 두 시점에 적용된다.
> **LOOP 2 7a Walking Skeleton**에서 실제 framework 구조·계층·에러·라우팅 등
> std/ 패턴 대부분이 적용되고, 데이터 의존만 6a stub으로 우회한다.
> **PHASE 5**에서는 데이터 어댑터(DB / 외부 API / runtime)만 교체된다.

```
.feature 파일 (bdd/)
    │  "사용자가 분석을 조회하면 결과가 반환된다"
    ▼
test step (bdd/02, bdd/03 — LOOP 2 7b → LOOP 3 7c)
    │  TestClient.get("/v1/analyses/trend") · context dict
    ▼
Stub 데이터 어댑터 (LOOP 1 6a — 인메모리, DR 로직만 std/ 참조)
    │  데이터 호출 인터페이스 + 도메인 규칙
    ▲
    │  호출
    ▼
Walking Skeleton (LOOP 2 7a — 실제 production 코드, std/ 패턴 본격 적용)
    ├─ FastAPI 라우터·계층     → std/01_backend.md
    ├─ Airflow DAG (@dag)      → std/08_data_pipeline.md
    ├─ Frontend 컴포넌트        → std/02_frontend.md
    ├─ 인증 검증               → std/04_auth.md
    └─ 로그 기록               → std/06_observability.md
    ▼ PHASE 5 — 데이터 소스 교체 (Stub Data → Real Data)
실제 데이터 어댑터 + runtime
    ├─ DB 어댑터               → std/03_database.md (STEP 13)
    ├─ 외부 API 어댑터          → (STEP 14)
    └─ 인프라 runtime           → std/05_infra.md  (STEP 15)
```

---

## STD ↔ GOV 사용 기준

| 상황 | STD (구현 패턴) | GOV (정책·게이트) |
|------|----------------|------------------|
| API 엔드포인트 작성 | `01_backend.md` | `gov/06_api_design.md` |
| OpenAPI 스펙 작성 | `01_backend.md` | `gov/06_api_design.md` |
| Frontend 컴포넌트 | `02_frontend.md` | — |
| DB 스키마 변경 | `03_database.md` | `gov/07_data_policy.md` |
| 인증 연동 | `04_auth.md` | `gov/04_security.md` |
| Docker 이미지 작성 | `05_infra.md` | `gov/04_security.md`, `gov/10_infra_deploy.md` |
| 배포 (Canary·Rollback) | `05_infra.md` | `gov/10_infra_deploy.md` |
| 로그·메트릭·트레이스 | `06_observability.md` | `gov/09_observability.md` |
| SLO·알람·incident | — | `gov/09_observability.md` |
| LLM·RAG 체인 작성 | `07_ai.md` | `gov/08_ai_governance.md` |
| Airflow DAG 작성 | `08_data_pipeline.md` | `gov/05_quality_gates.md` |
| 프로젝트 추적 Excel 재생성 | `09_project_tracker_excel.md` | `gov/01_requirements.md` |
| ARCHITECTURE.md 재작성 | `10_architecture_doc.md` | `gov/02_adr.md` |
| PROJECT_TRACKER.csv 재생성 | `11_project_tracker_csv.md` | `gov/01_requirements.md` |
| ADR 신규 작성 | `12_adr_writing.md` | `gov/02_adr.md` |
| 비즈니스 spec·.feature | — | `gov/01_requirements.md` |
| ADR 작성 | — | `gov/02_adr.md` |
| Git 브랜치·커밋 | — | `gov/03_git_workflow.md` |
| 테스트·커버리지 게이트 | — | `gov/05_quality_gates.md` |
