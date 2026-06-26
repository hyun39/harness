# harness — BDD/SDD 개발 방법론

> GOV(거버넌스 규칙) → BDD(행동 명세) → STD(구현 표준) 순서로  
> 실행 가능한 스펙을 중심에 두고 개발하는 방법론 키트.

---

## 구성

```
harness/
├── guides/                       사용 가이드 (읽는 순서대로 번호)
│   ├── 01_DEVELOPMENT_FLOW.md        전체 개발 흐름 (PHASE / LOOP / STEP 구조)  ← 뼈대
│   ├── 02_PROMPT_GUIDE.md            단계별 표준 프롬프트 & 산출물 가이드
│   ├── 03_EXECUTION_GUIDE.md         환경 설정 → 첫 BDD Green 실행 가이드
│   └── 04_CHECKLIST.md               감사·검증 체크리스트 (gov/std 항목 통합)
├── gov/              GOV — 강제 규칙·게이트       (무엇을 반드시 해야 하는가)
├── bdd/              BDD — 행동 명세 가이드        (어떻게 스펙을 실행 가능하게 만드는가)
│   └── templates/        비즈니스 스펙·.feature 템플릿
├── std/              STD — 구현 표준              (어떻게 코드를 작성하는가)
│   └── detail/           상세 원문 (std/0N_*.md 요약과 짝)
└── product/          PRODUCT — vision/domain/epics 작성 가이드
```

| 섹션 | 독자 | 핵심 질문 | 위반 시 |
|------|------|----------|--------|
| `gov/` | 전체 팀 | "이것을 안 하면 안 되는가?" | CI 차단·리뷰 거부 |
| `bdd/` | PO·개발자 | "어떻게 스펙을 테스트로 만드는가?" | 누락 시 스펙 미완성 |
| `std/` | 개발자 | "어떻게 구현하는가?" | 코드 리뷰 피드백 |

---

## 개발 흐름 요약

```
PHASE 1  제품 전략 (1회)
  STEP 1~3: vision → domain → epics

LOOP 1   Feature별 반복
  STEP 4: 비즈니스 스펙  →  STEP 5: .feature  →  STEP 6: Red  →  STEP 6a: Stub

MILESTONE  전체 Stub 완성 후 1회
  STEP 6b: UI/UX Mockup → 이해관계자 인수기준 확정

LOOP 2   Feature별 반복
  STEP 7a: Walking Skeleton  →  STEP 7b: Step 연결

MILESTONE 2  풀스택 E2E 검증
  STEP 8b: Mock-data E2E (Playwright)

LOOP 3   Feature별 반복
  STEP 7c: 세부 로직  →  STEP 8: Green

PHASE 3  CI / Living Docs  ·  PHASE 4  유지

PHASE 5  데이터 소스 교체 (Stub → Real)
  STEP 13: DB 어댑터  →  STEP 14: 외부 API  →  STEP 15: 인프라  →  STEP 16: E2E
```

상세 내용: **[guides/01_DEVELOPMENT_FLOW.md](./guides/01_DEVELOPMENT_FLOW.md)**

---

## 빠른 시작

### 새 프로젝트 시작 시

```bash
# 1. harness 복사
cp -r harness/ your-project/specs/_methodology

# 2. product 문서 작성 (guides/02_PROMPT_GUIDE.md PHASE 1 참조)
# specs/product/00_vision.md → 01_domain.md → 02_epics.md

# 3. 첫 Feature BDD 사이클 시작 (guides/03_EXECUTION_GUIDE.md 참조)
cp bdd/templates/business_spec.md specs/features/{domain}/{feature}_spec.md
cp bdd/templates/feature.feature  specs/features/{domain}/{feature}.feature
```

### 파일 선택 기준

```
"이것이 규칙인가?"          → gov/ 확인
"어떤 순서로 개발하는가?"   → guides/01_DEVELOPMENT_FLOW.md 확인
"Gherkin을 어떻게 쓰는가?" → bdd/01_writing_guide.md 확인
"Step을 어떻게 구현하는가?" → bdd/02_fastapi_impl.md 또는 bdd/03_spring_impl.md
"코드를 어떻게 짜는가?"     → std/ 확인
"AI 프롬프트가 필요한가?"   → guides/02_PROMPT_GUIDE.md 확인
```

---

## 샘플 구현체

이 방법론을 실제 프로젝트에 적용한 전체 구현 샘플:  
**[harness-sample-sp500](https://github.com/hyun39/harness-sample-sp500)**  
(S&P 500 데이터 파이프라인 + LLM 분석 + API + UI + Auth + OTel)
