# GOV-01 — 비즈니스 요건 정의 규칙

> **강제 대상**: 모든 신규 기능·서비스 착수 전  
> **게이트**: PR 템플릿 체크리스트 — 미완성 시 리뷰어 머지 거부

---

## 필수 규칙 (MUST)

- 비즈니스 스펙 문서가 작성되어 있다 (`bdd/templates/business_spec.md` 형식)
- 문서에 **배경 및 목적** 섹션이 있고, 기술 구현 방법을 언급하지 않는다
- **기능 요건**이 MoSCoW로 분류되어 있다 (Must / Should / Nice-to-have)
- **비기능 요건**이 측정 가능한 수치로 작성되어 있다
- **성공 기준**이 출시 후 측정 방법과 함께 정의되어 있다
- **`.feature` 파일이 작성되어 있다** — Gherkin 시나리오의 단일 소스 (spec에 중복 금지)
- 스펙 문서의 `## 인수기준` 섹션이 `.feature` 파일 링크로 연결되어 있다
- **문서 정보**에 관련 FR, Epic, DR, OKR이 모두 기입되어 있다

## 권장 규칙 (SHOULD)

- 문제 정의 문장 형식 준수: `"[사용자]는 [목표]를 위해 [현재 방법]을 사용하는데 [문제]가 있다"`
- 기능 요건에 `FR-NN` 식별자가 붙어 있다 (추적 가능성)
- 범위 외(Out of Scope) 항목이 명시되어 있다
- 관련 DR이 있으면 `01_domain.md`의 DR-NN과 연결되어 있다

---

## DoR (Definition of Ready) 체크리스트

개발 착수 전 반드시 통과해야 하는 기준.

```
[ ] specs/product/00_vision.md 에 관련 OKR이 정의되어 있다
[ ] specs/product/02_epics.md 에 Feature 행이 추가되어 있다
[ ] specs/features/*_spec.md 비즈니스 스펙이 작성·승인됐다
    - 문서 정보: 관련 FR / Epic / DR / OKR 모두 기입
[ ] specs/features/**/*.feature 파일이 작성됐다 (Gherkin 단일 소스)
[ ] app/ 인메모리 stub 코드가 작성됐다
    - DR 로직 실제 구현 포함
    - step에서 주입 가능한 인터페이스
[ ] apps/frontend/src/mockup.html UI/UX 목업이 작성됐다
    - stub 코드 기반 mock 데이터 사용
    - .feature의 모든 시나리오 상태 표현
    - 이해관계자 확인 후 인수기준 확정
[ ] API 계약 초안 작성됨 (gov/06 참조)
[ ] ADR 등록됨 (주요 기술 결정이 있는 경우, gov/02 참조)
[ ] 담당자·마감일 지정됨
```

---

## 금지 사항 (MUST NOT)

| 금지 | 이유 |
|------|------|
| 비즈니스 스펙에 기술 스택 명시 | 요건과 구현을 분리해야 함 |
| 측정 불가 비기능 요건 | "빠르게", "안정적으로" — 수치 없으면 검증 불가 |
| `.feature` 없는 기능 개발 시작 | 인수기준 없는 코드는 완료 기준 없음 |
| **스펙 문서 안에 Gherkin 블록** | `.feature`가 단일 소스 — 중복 시 불일치 발생 |
| **FR 항목에 체크박스** (`- [ ]`) | 구현 여부는 `LIVING_DOCS.md`가 자동 추적 |

---

## .feature 연결 규칙

비즈니스 스펙의 인수기준은 `.feature` 파일 링크로만 표현한다.

```
business_spec.md                      specs/features/*.feature
─────────────────                     ────────────────────────────
## 인수기준 (.feature)           →    Feature: 기능명
→ [링크]                                Scenario: Happy Path
                                        Scenario: 예외 케이스
```

구현 여부 확인은 `docs/LIVING_DOCS.md`에서 한다 (CI 자동 생성).

---

## 추적성 구조

```
00_vision.md (OKR)
    ↓ OKR → FR 매핑
01_domain.md (DR)
    ↓ DR → Feature 추적
02_epics.md (Feature)
    ↓ 스펙 파일 링크
*_spec.md (문서 정보: FR / Epic / DR / OKR)
    ↓ 인수기준 링크
*.feature (Gherkin 단일 소스)
    ↓ CI 실행
LIVING_DOCS.md (pass/fail 자동 반영)
```

---

## 검증 체크리스트

> 이 가이드 기준으로 application을 audit할 때 사용. 각 항목은 yes/no로 평가.
> 식별자(`G01-NN-MM`)는 통합 인덱스(`specs/_methodology/CHECKLIST.md`)에서 참조.

### 카테고리 1: 비즈니스 스펙 충실도

- [ ] G01-01-01: 모든 신규 Feature에 `*_spec.md` 파일이 존재하는가
- [ ] G01-01-02: spec에 배경 및 목적 섹션이 작성되어 있는가
- [ ] G01-01-03: spec에 기능 요건이 MoSCoW(Must/Should/Nice-to-have)로 분류되어 있는가
- [ ] G01-01-04: spec의 비기능 요건이 측정 가능한 수치(p95 latency, 가용성 등)로 작성되어 있는가
- [ ] G01-01-05: spec에 성공 기준(출시 후 측정 방법 포함)이 정의되어 있는가
- [ ] G01-01-06: spec에 범위 외(Out of Scope) 항목이 명시되어 있는가
- [ ] G01-01-07: spec 문서 정보에 관련 FR / Epic / DR / OKR이 모두 기입되어 있는가
- [ ] G01-01-08: spec 문서에 기술 스택·라이브러리 등 구현 세부가 노출되지 않는가

### 카테고리 2: .feature 파일 관리

- [ ] G01-02-01: 모든 spec의 `## 인수기준` 섹션이 `.feature` 파일 링크로 표시되어 있는가
- [ ] G01-02-02: spec 문서 안에 Gherkin 블록이 중복으로 포함되지 않았는가 (단일 소스 원칙)
- [ ] G01-02-03: 모든 `.feature` 시나리오에 대응하는 step 구현이 존재하는가
- [ ] G01-02-04: FR 항목에 체크박스(`- [ ]`) 표기가 사용되지 않았는가 (LIVING_DOCS로 추적)

### 카테고리 3: 추적성

- [ ] G01-03-01: `specs/product/00_vision.md`의 OKR과 FR 매핑이 정의되어 있는가
- [ ] G01-03-02: `specs/product/01_domain.md`의 DR과 Feature 매핑이 정의되어 있는가
- [ ] G01-03-03: `docs/LIVING_DOCS.md`가 CI 파이프라인에서 자동 생성되는가
