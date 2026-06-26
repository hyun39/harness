# PRODUCT 계층 작성 가이드

> 프로젝트 최초 착수 시 `_methodology`를 참조해 아래 순서로 작성한다.  
> 작성 완료된 파일은 `specs/product/`에 위치한다.

---

## 작성 순서

> 상세 단계와 표준 프롬프트는 `guides/02_PROMPT_GUIDE.md` 참조.

```
[PHASE 1 — 제품 전략 (1회)]
1. 00_vision.md        — WHY  (제품이 존재하는 이유)
      ↓
2. 01_domain.md        — WHAT (도메인 모델과 규칙)
      ↓
3. 02_epics.md         — HOW  (Epic > Feature > FR > DR 매핑)
      ↓
[PHASE 2 LOOP 1 — Feature별 반복]
4. *_spec.md           — EACH    (Feature별 비즈니스 스펙)
      ↓
5. *.feature           — SPEC    (Gherkin 단일 소스)
      ↓
6. Red 확인            — VERIFY  (StepDefinitionNotFoundError)
      ↓
6a. stub 코드          — STUB    (인터페이스·DR 로직 확정, 인메모리)
      ↓ 모든 Feature stub 완성
[PHASE 2 MILESTONE — 1회]
6b. mockup.html        — VALIDATE (stub 기반 mock 데이터로 UI 목업,
                                    이해관계자 인수기준 확정)
      ↓ 인수기준 확정
[PHASE 2 LOOP 2 — Feature별 반복]
7a. Walking Skeleton    — SKELETON (실제 production 코드 뼈대 + stub 데이터)
                                    apps/airflow/dags/, apps/frontend/src/, api routers
      ↓
7b. test step skeleton  — WIRE     (pytest --generate-missing → 7a 호출 연결)
      ↓ 모든 Feature 골격 통과
[PHASE 2 MILESTONE 2 — 1회]
8b. Mock-data E2E       — VERIFY   (frontend + backend 풀스택, Playwright,
                                    외부 의존 모두 mock)
      ↓ 풀스택 시각 통과
[PHASE 2 LOOP 3 — Feature별 반복]
7c. step 세부 로직      — DETAIL   (시나리오별 mock·DR assert)
      ↓
8. Green 확인          — IMPLEMENT (모든 시나리오 도메인 규칙 통과)
      ↓
[PHASE 3 — CI / Living Docs (1회)] · [PHASE 4 — 유지 (지속)]
      ↓
[PHASE 5 — 데이터 소스 교체 (Stub Data → Real Data)]
13. repositories + db/   — PERSIST   (_store → PostgreSQL/DW/Mart)
14. adapters/*.py        — INTEGRATE (mock_records → yfinance 등)
15. docker-compose / k8s — RUNTIME   (Airflow scheduler·executor, 컨테이너)
16. tests/e2e/           — E2E       (실제 인프라에서 BDD Green 유지)
```

---

## 00_vision.md 작성 요령

**목적**: 제품의 WHY를 한 문장으로 정의하고 OKR로 구체화한다.

**필수 섹션**

| 섹션 | 내용 |
|------|------|
| 한 줄 비전 | 제품이 누구를 위해 무엇을 해결하는지 한 문장 |
| 배경 및 문제 정의 | 현재 문제 + 해결 방향 |
| 전체 아키텍처 | 데이터/시스템 흐름 다이어그램 |
| 데이터 레이어 정의 | 레이어별 역할, 갱신 주기, 보존 기간 |
| 목표 (OKR) | Objective + Key Result + **OKR→FR 매핑** |
| 이해관계자 | 역할, 팀, 관심사 |
| 사용자 페르소나 | Primary/Secondary/Operator 구분 |
| 핵심 원칙 | 개발 전 반드시 합의된 원칙 |
| 범위 외 (Out of Scope) | v1에서 제외할 것 명시 |
| 미결 기술 과제 | 담당자 + 기한 명시 |

**OKR → FR 매핑 예시**
```markdown
### OKR → FR 추적
| Objective       | 관련 FR             |
|-----------------|---------------------|
| 분석 시간 단축  | FR-04, FR-05, FR-07 |
| 데이터 신뢰성   | FR-01, FR-02, FR-03 |
```

---

## 01_domain.md 작성 요령

**목적**: 팀 전체가 같은 언어로 소통하기 위한 도메인 모델을 정의한다.

**필수 섹션**

| 섹션 | 내용 |
|------|------|
| Bounded Context 맵 | 서브도메인 간 관계 다이어그램 |
| 유비쿼터스 언어 | 코드·스펙·대화에서 통일해서 쓸 용어 사전 |
| 데이터 모델 | 레이어별 테이블/엔티티 스키마 |
| 도메인 규칙 (DR) | `DR-NN` ID로 관리되는 불변 업무 규칙 |

**도메인 규칙 작성 기준**
- ID 형식: `DR-01`, `DR-02`, ...
- "시스템은 ~해야 한다" 형식
- 변경 시 영향받는 Feature가 많을수록 중요

---

## 02_epics.md 작성 요령

**목적**: vision의 FR을 Epic > Feature 단위로 분해하고 추적 가능하게 연결한다.

**필수 항목**

| 항목 | 설명 |
|------|------|
| Epic 전체 지도 | EP-NN별 담당 FR 한눈에 보기 |
| Feature 테이블 | `Feature ID / Feature명 / FR / DR / 스펙 파일 / 상태` |
| FR 전체 매핑 | FR-NN → Epic, Feature, Priority |
| DR → Feature 추적 | 각 DR이 어느 Feature에 적용되는지 |
| 상태 범례 | 🟢 완료 / 🟡 진행 중 / 🔴 블로킹 / ⬜ 미시작 |

**Feature 테이블 컬럼 설명**
```markdown
| Feature ID | Feature명 | FR | DR | 스펙 파일 | 상태 |
|-----------|-----------|----|----|----------|------|
```
- **DR**: 이 Feature에 적용되는 도메인 규칙 ID (01_domain.md 참조)
- **스펙 파일**: `specs/features/` 하위 경로

---

## 참조 파일

- `gov/01_requirements.md` — 비즈니스 스펙 작성 규칙
- `bdd/templates/business_spec.md` — Feature 스펙 템플릿
- `bdd/01_writing_guide.md` — .feature 파일 작성 가이드
