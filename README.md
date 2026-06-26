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

**Step 1 — 프로젝트 생성 & harness 연결**

```bash
mkdir {your-project} && cd {your-project}
git init

# harness를 specs/_methodology/에 submodule로 추가
git submodule add https://github.com/hyun39/harness specs/_methodology
```

**Step 2 — 기본 디렉토리 구조 생성**

```bash
mkdir -p specs/product \
         specs/features \
         apps \
         infra \
         docs \
         scripts
```

**Step 3 — PHASE 1: 제품 스펙 작성 (AI 프롬프트 사용)**

```bash
# 02_PROMPT_GUIDE.md의 STEP 1~3 프롬프트를 AI에 붙여넣어 작성
# specs/product/00_vision.md  → STEP 1
# specs/product/01_domain.md  → STEP 2
# specs/product/02_epics.md   → STEP 3
open specs/_methodology/guides/02_PROMPT_GUIDE.md   # 또는 편집기로 열기
```

**Step 4 — 첫 Feature BDD 사이클 시작**

```bash
# 비즈니스 스펙·.feature 템플릿 복사
cp specs/_methodology/bdd/templates/business_spec.md \
   specs/features/{domain}/{feature}_spec.md
cp specs/_methodology/bdd/templates/feature.feature \
   specs/features/{domain}/{feature}.feature
```

**Step 5 — 환경 설정 (첫 BDD Green까지)**

```bash
# 03_EXECUTION_GUIDE.md 순서대로 진행
open specs/_methodology/guides/03_EXECUTION_GUIDE.md
```

> **submodule 사용 이유**: PROMPT_GUIDE의 모든 프롬프트가 `specs/_methodology/` 경로를 참조하므로,
> 이 위치에 submodule을 추가하면 경로 수정 없이 그대로 사용할 수 있다.

---

### 기존 프로젝트에서 clone 후 submodule 초기화

```bash
git clone {your-project-repo}
cd {your-project}
git submodule update --init --recursive
```

### Claude Code로 실행하기

harness의 STEP은 **Claude Code CLI** 를 프로젝트 루트에서 실행해 사용한다.  
Claude Code는 `specs/_methodology/` 파일을 직접 읽을 수 있어 경로 참조가 그대로 작동한다.

**1. 프로젝트 루트에서 Claude Code 시작**

```bash
cd {your-project}
claude          # Claude Code CLI 실행
```

**2. STEP 프롬프트 붙여넣기**

`specs/_methodology/guides/02_PROMPT_GUIDE.md` 에서 해당 STEP 프롬프트를 복사해
`{placeholder}` 부분만 채워 Claude에 전달한다.

```
# 예시 — STEP 1 (vision 작성)
다음 제품 개요를 바탕으로 specs/_methodology/product/README.md 가이드에 따라
specs/product/00_vision.md를 작성해줘.

[제품 개요]
제품명: {your-product}
도메인: {domain}
핵심 문제: {problem}
주요 사용자: {users}
```

Claude Code가 `specs/_methodology/` 내 가이드 파일을 직접 읽어 산출물을 생성하고 저장한다.

**3. 다음 STEP으로 이동**

산출물을 확인한 뒤 PROMPT_GUIDE의 다음 STEP 프롬프트를 이어서 전달한다.  
각 STEP의 입력·출력·체크포인트는 `guides/01_DEVELOPMENT_FLOW.md` 추적성 표를 참조한다.

> **주의**: `claude`는 반드시 `specs/`, `apps/` 가 있는 **프로젝트 루트**에서 실행해야  
> `specs/_methodology/` 경로 참조가 정상 작동한다.

---

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
