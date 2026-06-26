# AI 보조 BDD 개발 — 표준 프롬프트 & 산출물 가이드

> **목적**: `_methodology` → `product` → `features` → 코드 → Living Docs 흐름을  
> Claude Code와 함께 재현할 수 있도록 단계별 표준 프롬프트와 예상 산출물을 정리한다.  
> **예시 프로젝트**: SP500 Daily Analysis Platform  
> **전제**: Claude Code CLI 또는 IDE 확장이 설치되어 있고, git 저장소가 초기화된 상태

---

## 사전 준비

```bash
# 프로젝트 구조 생성
mkdir -p sp500-platform && cd sp500-platform
git init

# _methodology 복사 (방법론 가이드)
cp -r /path/to/_methodology specs/_methodology

# 디렉터리 구조
mkdir -p specs/product specs/features
mkdir -p apps/api/app apps/airflow/dags apps/frontend/src
mkdir -p .github/workflows scripts doc-manure
```

---

## 전체 흐름 요약

```
PHASE 1 — 제품 전략 (1회)
  STEP 1~3: vision → domain → epics

PHASE 2 — Feature 개발
  ┌─ LOOP 1 (Feature별 반복) ──────────────────────────┐
  │  STEP 4: 비즈니스 스펙 작성                          │
  │  STEP 5: .feature 작성                              │
  │  STEP 6: Red 확인                                   │
  │  STEP 6a: Stub 코드 작성 (인메모리)                  │
  └─ 모든 Feature 완료까지 반복 ─────────────────────────┘
           ↓ 전체 Stub 완성
  ┌─ MILESTONE (1회) ───────────────────────────────────┐
  │  STEP 6b: UI/UX Mockup 작성 & 요구사항 검증          │
  │  → 인수기준 변경 시 Loop 1으로 돌아가 수정            │
  └─ 검증 완료 ─────────────────────────────────────────┘
           ↓ 인수기준 확정
  ┌─ LOOP 2 (Feature별 반복) ──────────────────────────┐
  │  STEP 7a: 실제 production 코드 뼈대 + stub 데이터    │
  │           (Walking Skeleton — real framework 구조)   │
  │  STEP 7b: 테스트 step skeleton 자동 생성 + 연결       │
  │           (pytest --generate-missing → stub 호출)    │
  └─ 모든 Feature 골격 통과까지 반복 ────────────────────┘
           ↓ 전체 Feature 골격 통과
  ┌─ MILESTONE 2 (1회 — STEP 8b) ────────────────────────┐
  │  Mock-data E2E (Walking Skeleton 풀스택 시각 검증)    │
  │  Frontend + Backend 동시 기동, Playwright 자동화      │
  │  외부 의존은 모두 mock — 실 인프라 검증은 PHASE 5     │
  │  → 세부 로직 구현 전, 풀스택이 시각적으로 동작하는지   │
  └─ E2E Green ─────────────────────────────────────────┘
           ↓ 풀스택 골격 통과
  ┌─ LOOP 3 (Feature별 반복) ──────────────────────────┐
  │  STEP 7c: Step 세부 로직 구현 (시나리오별 디테일)     │
  │  STEP 8: Green 확인                                  │
  └─ 모든 Feature 완료까지 반복 ─────────────────────────┘

PHASE 3 — CI / Living Docs (1회 설정)
  STEP 9~11: CI 구성 → Living Docs → PR

PHASE 4 — 유지 (지속/주기적)
  STEP 12: 스펙 일관성 검증

PHASE 5 — 데이터 소스 교체 (Stub Data → Real Data)
  STEP 13: DB 어댑터 구현       (_store dict → PostgreSQL/DW/Mart)
  STEP 14: 외부 API 어댑터       (mock_records → yfinance 등)
  STEP 15: 인프라 runtime 구축   (Airflow scheduler·executor, docker-compose)
  STEP 16: E2E 통합 테스트       (실제 인프라에서 BDD Green 유지)
```

---

## PHASE 1 — 제품 전략 정의

### STEP 1. vision.md 작성

**목적**: 제품이 존재하는 이유(WHY)를 OKR과 이해관계자로 구체화한다.

**표준 프롬프트**
```
다음 제품 개요를 바탕으로 specs/_methodology/product/README.md 가이드에 따라
specs/product/00_vision.md를 작성해줘.

제품 개요:
- 제품명: [제품명]
- 핵심 문제: [현재 사용자가 겪는 문제]
- 해결 방향: [제품이 제공하는 해결책]
- 주요 사용자: [페르소나]
- 기술 스택 힌트: [데이터 레이어, API, LLM 등]

필수 포함:
- 한 줄 비전, 배경 및 문제 정의
- 전체 아키텍처 다이어그램 (ASCII)
- 데이터 레이어 정의 (레이어별 역할·갱신 주기·보존 기간)
- OKR 테이블 + OKR→FR 매핑 섹션
- 이해관계자, 사용자 페르소나
- 핵심 원칙, 범위 외(Out of Scope), 미결 기술 과제
```

**SP500 예시 프롬프트**
```
다음 제품 개요를 바탕으로 specs/product/00_vision.md를 작성해줘.

제품 개요:
- 제품명: SP500 Daily Analysis Platform
- 핵심 문제: 내부 분석가가 S&P 500 주가 데이터를 매일 수작업으로 수집하고
  Sector 트렌드를 엑셀로 분석해 1인당 30분 이상 소요됨
- 해결 방향: 거래일마다 주가를 자동 수집·집계하고, LLM이 Sector 트렌드를
  해석해 한 화면에서 즉시 확인할 수 있게 함
- 주요 사용자: 투자 전략 담당자(analyst), 퀀트 분석가(analyst), 데이터 엔지니어(admin)
- 기술 스택: Airflow(파이프라인), PostgreSQL(ODS/DW/Mart), FastAPI(API),
  LangChain+Gemini(LLM), React(UI)
- NYSE 거래 캘린더 기준, 11개 GICS Sector
```

**예상 산출물**

| 파일 | 위치 |
|------|------|
| `00_vision.md` | `specs/product/` |

**검증 체크리스트**
- [ ] OKR → FR 매핑 섹션 포함
- [ ] 데이터 레이어 표에 보존 기간 명시
- [ ] 페르소나별 권한(analyst/admin) 구분

---

### STEP 2. domain.md 작성

**목적**: 팀 공통 언어(유비쿼터스 언어)와 도메인 규칙(DR)을 정의한다.

**표준 프롬프트**
```
specs/product/00_vision.md를 읽고
specs/_methodology/product/README.md 가이드에 따라
specs/product/01_domain.md를 작성해줘.

포함할 내용:
- Bounded Context 맵 (ASCII 다이어그램)
- 유비쿼터스 언어 테이블 (용어, 정의)
- 데이터 모델 (레이어별 테이블 스키마: 컬럼명, 타입, PK/FK)
- 도메인 규칙 (DR-01~NN): "시스템은 ~해야 한다" 형식, ID로 관리
```

**SP500 예시 프롬프트**
```
specs/product/00_vision.md를 읽고 specs/product/01_domain.md를 작성해줘.

추가 도메인 지식:
- 거래일 기준: NYSE(XNYS) 캘린더 단일 소스 사용
- Raw 데이터: append-only Parquet, 수정 금지
- Sector: 11개 GICS 분류 (Communication Services, IT, Financials 등)
- sentiment: bullish / bearish / neutral 세 가지만 허용
- 분석 완료 조건: 11개 Sector 모두 결과 존재
- 비거래일 접속 시: 최근 거래일 자동 선택
- LLM 분석: Mart Key Index 수치만 기반 (외부 뉴스 제외)

DR은 위 규칙들을 DR-01부터 번호 붙여 정의해줘.
```

**예상 산출물**

| 파일 | 위치 |
|------|------|
| `01_domain.md` | `specs/product/` |

**검증 체크리스트**
- [ ] DR에 ID(DR-NN) 부여
- [ ] 유비쿼터스 언어에 코드에서 쓸 변수명 힌트 포함
- [ ] 데이터 모델 PK/FK 명시

---

### STEP 3. epics.md 작성

**목적**: vision의 FR을 Epic > Feature 단위로 분해하고 DR과 연결한다.

**표준 프롬프트**
```
specs/product/00_vision.md와 specs/product/01_domain.md를 읽고
specs/product/02_epics.md를 작성해줘.

Feature 테이블 컬럼: Feature ID / Feature명 / FR / DR / 스펙 파일 / 상태
- 상태는 모두 ⬜ 미시작으로 시작
- FR-NN은 vision의 OKR→FR에서 파생
- DR-NN은 domain의 도메인 규칙에서 참조
- 마지막에 DR → Feature 추적 섹션 추가
- 상태 범례: 🟢 완료 / 🟡 진행 중 / 🔴 블로킹 / ⬜ 미시작
```

**SP500 예시 프롬프트**
```
specs/product/00_vision.md와 specs/product/01_domain.md를 읽고
specs/product/02_epics.md를 작성해줘.

Epic 구성:
- EP-01: 데이터 수집 파이프라인 (Raw → ODS)
- EP-02: 데이터 집계 파이프라인 (ODS → DW → Mart)
- EP-03: LLM Sector 트렌드 분석 (Mart → Agent → Mart)
- EP-04: 통합 조회 UI (ODS/DW/Mart/Trend 화면)
- EP-05: 인증 및 권한 관리 (JWT + RBAC)
- EP-06: 모니터링 및 운영 (알림 + 헬스체크)
```

**예상 산출물**

| 파일 | 위치 |
|------|------|
| `02_epics.md` | `specs/product/` |

**검증 체크리스트**
- [ ] Feature 테이블에 DR 컬럼 존재
- [ ] FR 전체 매핑 테이블 (FR-NN → Epic, Feature, Priority)
- [ ] DR → Feature 추적 섹션 존재
- [ ] 상태 범례 4종 모두 있음

---

## PHASE 2 — Feature 개발

---

## ◀ LOOP 1 — Feature별 반복 (STEP 4 ~ 6a)

> 에픽에 정의된 **모든 Feature**에 대해 STEP 4~6a를 반복한다.  
> 목표: 전체 Feature의 스펙·시나리오·Stub 코드 완성  
> 예시: F-01-01 (일별 주가 수집 DAG)

---

### STEP 4. 비즈니스 스펙 작성

**목적**: 해당 Feature의 WHY와 FR 상세, 인수기준 링크를 정의한다.

**표준 프롬프트**
```
specs/_methodology/bdd/templates/business_spec.md 템플릿을 참조해서
[Feature ID] [Feature명]의 비즈니스 스펙을 작성해줘.

파일 위치: specs/features/[도메인]/[feature명]_spec.md

입력 정보:
- 관련 FR: [FR-NN]
- 관련 Epic: [EP-NN / F-NN-NN]
- 관련 DR: [DR-NN, ...]
- 관련 OKR: [OKR Objective명]
- .feature 파일 경로: [컴포넌트]/specs/features/[도메인]/[feature명].feature

비즈니스 컨텍스트:
- 배경: [이 기능이 왜 필요한가]
- 기능 요건: [Must/Should/Nice 항목들]
- 비기능 요건: [응답시간, 가용성 등]
- 범위 외: [제외 항목]

주의: 스펙에 Gherkin 블록 포함 금지.
      인수기준은 .feature 링크로만 표현한다.
```

**SP500 예시 프롬프트 (F-01-01)**
```
specs/features/pipeline/price_ingest_spec.md를 작성해줘.

- 관련 FR: FR-01
- 관련 Epic: EP-01 / F-01-01
- 관련 DR: DR-01, DR-02
- 관련 OKR: 데이터 신뢰성 확보, 파이프라인 안정성
- .feature: specs/features/pipeline/price_ingest.feature

배경:
  매 거래일 장 마감 후 S&P 500 전 종목(503개) OHLCV를 자동 수집해야 한다.
  현재 수작업으로 데이터를 다운받는 방식이라 누락과 지연이 발생한다.

기능 요건:
  Must:
  - NYSE 거래일에 전 종목 OHLCV를 자동 수집해 Raw 레이어에 저장한다
  - 비거래일에는 DAG를 자동 스킵한다
  - 수집 종목이 전체의 98% 미만이면 실패 처리한다
  Should:
  - 수집 결과를 로그로 기록한다
```

**예상 산출물**

| 파일 | 위치 |
|------|------|
| `price_ingest_spec.md` | `specs/features/pipeline/` |

**검증 체크리스트**
- [ ] 문서 정보에 FR / Epic / DR / OKR 모두 기입
- [ ] 기능 요건에 체크박스(`- [ ]`) 없음
- [ ] `## 인수기준 (.feature)` 섹션에 .feature 링크만 존재
- [ ] Gherkin 블록 없음

---

### STEP 5. .feature 파일 작성

**목적**: 인수기준을 실행 가능한 Gherkin 시나리오로 표현한다 (단일 소스).

**표준 프롬프트**
```
specs/features/[도메인]/[feature명]_spec.md를 읽고
specs/_methodology/bdd/01_writing_guide.md 가이드에 따라
[컴포넌트]/specs/features/[도메인]/[feature명].feature를 작성해줘.

시나리오 구성:
- Happy Path (정상 케이스) 반드시 포함
- 예외 케이스 (에러, 경계값) 포함
- Given/When/Then 각 1문장 원칙
- 첫 줄에 # Spec: [스펙 파일 경로] 주석
```

**SP500 예시 프롬프트 (price_ingest)**
```
specs/features/pipeline/price_ingest_spec.md를 읽고
specs/features/pipeline/price_ingest.feature를 작성해줘.

시나리오:
1. 거래일에 전체 종목 정상 수집 (Happy Path)
2. 비거래일 DAG 자동 스킵
3. 수집 종목 수 미달 시 실패 처리 (98% 미만)
```

**예상 산출물**

| 파일 | 위치 |
|------|------|
| `price_ingest.feature` | `specs/features/pipeline/` |

**산출물 예시**
```gherkin
# Spec: specs/features/pipeline/price_ingest_spec.md
# AC:   FR-01
Feature: 일별 주가 수집 DAG

  Scenario: 거래일에 전체 종목 정상 수집
    Given 2026-05-01이 NYSE 거래일이다
    When ingest_sp500_daily DAG가 실행되면
    Then S&P 500 전 종목 OHLCV가 Raw 레이어에 저장된다
    And 수집 종목 수가 전체의 98% 이상이다

  Scenario: 비거래일 DAG 자동 스킵
    Given 2026-05-02이 NYSE 비거래일이다
    When ingest_sp500_daily DAG가 트리거되면
    Then DAG가 skipped 상태로 종료된다

  Scenario: 수집 종목 수 미달 시 실패 처리
    Given 2026-05-01이 거래일이다
    And API 오류로 수집된 종목이 전체의 50%이다
    When ingest_sp500_daily DAG가 실행되면
    Then DAG가 failed 상태로 종료된다
```

---

### STEP 6. Red 확인

**목적**: Step 없음 에러(StepDefinitionNotFoundError)를 확인해 Red 상태를 검증한다.

**명령어**
```bash
# airflow 예시
cd apps/airflow
uv run --project ../api pytest tests/ -v --tb=short 2>&1 | head -30
```

**예상 출력**
```
FAILED - StepDefinitionNotFoundError:
  Step "2026-05-01이 NYSE 거래일이다" not found.
```

> Red 확인이 목적이므로 실패가 정상이다.

---

### STEP 6a. Stub 코드 작성

**목적**: 시나리오가 일단 PASS만 하면 되는 가벼운 인메모리 stub 함수·dict를
작성한다. DR 로직(거래일 판단 등)은 이 단계에서 실제로 구현하지만,
production framework 구조(`@dag`, `APIRouter`, React 컴포넌트 등)는
**LOOP 2 STEP 7a에서** 이 stub을 호출하는 형태로 따로 작성한다.

**6a의 역할**: 데이터·도메인 로직 어댑터 — "데이터를 어디서 가져오는가"를 stub.  
**7a의 역할**: production framework 뼈대 — "이 데이터를 어떤 framework에 얹는가"를 실제 코드로.

**표준 프롬프트**
```
[feature명].feature의 시나리오를 분석해서
step이 호출할 프로덕션 코드의 stub을 [코드 경로]에 작성해줘.

조건:
- 실제 DB/외부 API 연동 없이 dict/dataclass 인메모리로 구현
- 도메인 규칙(DR)은 실제 로직으로 구현 (거래일 판단 등)
- step에서 테스트 데이터를 주입할 수 있는 인터페이스 설계
- PHASE 5(데이터 소스 교체) 시 인터페이스 변경이 최소화되도록 경계 설계
```

**SP500 예시 프롬프트 (price_ingest)**
```
specs/features/pipeline/price_ingest.feature를 읽고
apps/api/app/pipeline/price_ingest.py를 인메모리 stub으로 작성해줘.

설계 조건:
- exchange_calendars로 NYSE 거래일 실제 판단 (DR-01)
- OHLCVRecord: trade_date / ticker / open / high / low / close / volume
- IngestResult: status(completed|skipped|failed) / records / message
- run_ingest_dag(trade_date, mock_records=None): step에서 mock_records 주입
- SP500_TOTAL_COUNT = 503, COVERAGE_THRESHOLD = 0.98
- 실제 API 호출 없음 — mock_records 파라미터로 데이터 대체
```

**예상 산출물**

| 파일 | 위치 |
|------|------|
| `price_ingest.py` | `apps/api/app/pipeline/` |

**산출물 핵심 구조**
```python
SP500_TOTAL_COUNT = 503
COVERAGE_THRESHOLD = 0.98

@dataclass
class OHLCVRecord:
    trade_date: str
    ticker: str
    open: float; high: float; low: float; close: float
    volume: int

@dataclass
class IngestResult:
    status: str        # completed | skipped | failed
    trade_date: str
    records: List[OHLCVRecord] = field(default_factory=list)
    message: str = ""

def is_trading_day(trade_date: str) -> bool:
    cal = xcals.get_calendar("XNYS")   # DR-01
    return cal.is_session(trade_date)

def run_ingest_dag(trade_date: str, mock_records=None) -> IngestResult:
    if not is_trading_day(trade_date):
        return IngestResult(status="skipped", ...)
    if len(mock_records) / SP500_TOTAL_COUNT < COVERAGE_THRESHOLD:
        return IngestResult(status="failed", ...)
    return IngestResult(status="completed", ...)
```

**검증 체크리스트**
- [ ] DR 준수 로직이 실제로 구현됨 (거래일 판단 등)
- [ ] step에서 테스트 데이터 주입 가능한 인터페이스
- [ ] PHASE 5 데이터 소스 교체 시 인터페이스 변경 최소화 구조

> **다음 Feature로**: STEP 4로 돌아가 다음 Feature를 반복한다.  
> 모든 Feature의 stub 완성 후 → STEP 6b (Mockup)로 이동

---

## ◀ MILESTONE — 전체 Stub 완성 후 1회 (STEP 6b)

> **진입 조건**: 02_epics.md의 모든 Feature에 대해 STEP 4~6a 완료  
> **목적**: 전체 stub 기반으로 UI를 시각화해 이해관계자와 인수기준을 확정한다.

---

### STEP 6b. UI/UX Mockup 작성 & 요구사항 검증

**목적**: 모든 Feature의 stub이 완성된 시점에 단일 HTML 파일로  
전체 화면과 상태를 시각화해 요구사항을 최종 검증한다.

**표준 프롬프트**
```
specs/features/ 하위의 모든 .feature 파일을 읽고
apps/frontend/src/mockup.html 단일 파일 UI 목업을 만들어줘.

요구사항:
- 백엔드 없이 동작 (stub 구조 기반 하드코딩 mock 데이터)
- 모든 .feature의 시나리오별 화면 상태 표현
  (정상, 로딩, 에러, 비거래일, 분석 진행 중 등)
- 탭/화면 전환, 날짜 선택 등 인터랙션 포함
- Tailwind CSS CDN + Vanilla JS만 사용
- 한 파일로 완결 (외부 서버 불필요)
```

**SP500 예시 프롬프트**
```
specs/features/ui/ 하위 .feature 파일들을 읽고
apps/api/app/ 하위 stub 코드의 데이터 구조를 참고해서
apps/frontend/src/mockup.html을 만들어줘.

화면 구성:
- 날짜 선택기 (비거래일 비활성화, 변경 시 전체 탭 갱신)
- 탭 4개: ODS 원시 데이터 / DW Sector 집계 / Mart Key Index / Trend Analysis
- ODS: 종목 검색·Sector 필터 + 테이블 (503개 중 10개 표시)
- DW: 수익률 정렬 + 바 차트 컬럼 + 행 클릭 시 상세
- Mart: Sector 카드 (MA/RSI/거래량이상) + 클릭 시 60일 차트
- Trend: sentiment 배지 + 요약 + key_drivers 카드
  (분석 진행 중 배너 상태 포함)
- 비거래일 접속 시 자동 리다이렉트 배너

디자인: 다크 네이비 금융 대시보드, Tailwind CDN + Chart.js CDN
```

**예상 산출물**

| 파일 | 위치 |
|------|------|
| `mockup.html` | `apps/frontend/src/` |

**확인 방법**
```bash
open apps/frontend/src/mockup.html   # macOS
# 브라우저에서 직접 열어 각 탭과 상태 전환 확인
```

**검증 체크리스트**
- [ ] 모든 .feature 시나리오 상태가 목업에 표현됨
- [ ] 비거래일 / 로딩 / 에러 상태 데모 가능
- [ ] 이해관계자 확인 완료
- [ ] 인수기준 변경 사항 → .feature 수정 후 Loop 1 해당 Feature 재실행
- [ ] 인수기준 확정 후 Loop 2 진입

---

## ◀ LOOP 2 — Feature별 반복 (STEP 7a ~ 7b)

> **진입 조건**: STEP 6b 목업 검증 완료, 인수기준 확정  
> 에픽에 정의된 **모든 Feature**에 대해 STEP 7a~7b를 반복한다.  
> 목표: **실제 production 코드 뼈대(real framework + real architecture)** 를
>      먼저 갖추고, 데이터 소스만 6a stub으로 우회한 채 시나리오 골격을 PASS시킨다.
>      Walking Skeleton / Hexagonal 패턴.

---

### STEP 7a. 실제 production 코드 뼈대 작성 (Walking Skeleton)

**목적**: Airflow DAG, FastAPI 라우터, 프론트엔드 컴포넌트 등
**실제 production framework 구조**를 작성한다. 데이터 호출은
6a stub의 인터페이스(`mock_records`, `_store` 등)를 그대로 호출해
인메모리에서 동작한다. 이후 PHASE 5에서 데이터 소스만 교체된다.

**핵심 원칙**
- 실제 framework decorator·routing·컴포넌트 구조 사용 (가짜 wrapper 금지)
- 데이터 소스만 stub으로 우회 — 6a stub의 인터페이스 변경 없음
- LOOP 1 6a 코드는 그대로 유지 (이중 코드 아님 — 6a는 데이터 어댑터, 7a는 framework 구조)

**표준 프롬프트**
```
specs/features/[도메인]/[feature명]_spec.md 와
apps/api/app/[도메인]/[feature명].py (6a stub) 를 읽고
실제 production 코드 뼈대를 작성해줘.

조건:
- 영역별 실제 framework 사용:
  * pipeline → apps/airflow/dags/[dag명].py (@dag, @task TaskFlow)
  * API     → apps/api/app/routers/[도메인].py (FastAPI APIRouter)
  * UI      → apps/frontend/src/components/[Feature].(tsx|vue) (실제 컴포넌트)
- 데이터 호출은 6a stub 함수/dict 인터페이스 그대로 사용
- 비기능 요건(schedule·retries·routing path·layout) spec 반영
- 이 단계에서는 PHASE 5의 PostgreSQL/yfinance/Airflow runtime 미접속
```

**SP500 예시 프롬프트 (price_ingest)**
```
specs/features/pipeline/price_ingest_spec.md 와
apps/api/app/pipeline/price_ingest.py 를 읽고
apps/airflow/dags/ingest_sp500_daily.py 를 작성해줘.

- @dag(schedule="0 22 * * 1-5", catchup=False, ...)
- @task ingest(): run_ingest_dag(trade_date, mock_records=[]) 호출
- retries=3, retry_delay=10분
- 실제 데이터는 PHASE 5 STEP 14에서 yfinance로 교체될 mock_records 자리
```

**예상 산출물 (영역별)**

| 영역 | 파일 패턴 | 예시 |
|------|----------|------|
| Pipeline | `apps/airflow/dags/*.py` | `ingest_sp500_daily.py`, `raw_to_ods.py`, `dw_sector_aggregate.py`, `mart_key_index.py` |
| API | `apps/api/app/routers/*.py`, `apps/api/app/main.py` | (이미 LOOP 1에서 작성된 경우 유지) |
| Frontend | `apps/frontend/src/App.*`, `apps/frontend/src/components/*`, `apps/frontend/src/api/*` | `App.tsx`, `OdsTab.tsx`, `client.ts` |

**검증 체크리스트**
- [ ] Production framework decorator/구조가 실제로 사용됨 (`@dag`, `APIRouter`, React 컴포넌트)
- [ ] 데이터 호출이 6a stub 인터페이스를 그대로 사용 (인메모리)
- [ ] DAG 단독 import / API 단독 부팅 / Frontend 단독 빌드 성공
- [ ] 6a stub 인터페이스는 무수정 유지 (PHASE 5 교체 지점만 stub)

---

### STEP 7b. 테스트 step skeleton 자동 생성 + 연결

**목적**: `pytest --generate-missing`으로 BDD step 함수 뼈대를 자동 생성하고,
NotImplementedError를 7a 실제 production 코드 호출로 교체해
시나리오 골격이 통과하도록 한다.

**명령어 (skeleton 자동 생성)**
```bash
cd apps/airflow
uv run --project ../api pytest tests/ \
  --generate-missing \
  --feature specs/features/pipeline/price_ingest.feature
```

**자동 생성 예시**
```python
@given(parsers.parse("{date}이 NYSE 거래일이다"))
def step_impl(date):
    raise NotImplementedError(...)
```

**표준 프롬프트 (skeleton → 연결)**
```
[컴포넌트]/specs/features/[도메인]/[feature명].feature와
[7a 산출물 경로] (실제 production 코드)를 읽고
[컴포넌트]/tests/bdd/steps/[도메인]/[feature명]_steps.py의
Given/When/Then Step에 골격을 채워줘.

- 7a의 실제 production 코드를 호출 (DAG task, API endpoint, 컴포넌트 렌더 등)
- 데이터는 mock_records / fixture 등 stub 인터페이스로 주입
- context dict 패턴으로 상태 공유
- Then은 최소 assert (status 코드, 반환값 존재 정도)
- 시나리오별 입력 디테일·edge case는 STEP 7c에서 처리
- test_[feature명].py는 scenarios() 또는 explicit 함수로 작성
```

**예상 산출물**

| 파일 | 위치 |
|------|------|
| `*_steps.py` | `*/tests/bdd/steps/[도메인]/` |
| `test_*.py` | `*/tests/bdd/steps/[도메인]/` |

**골격 통과 확인**
```bash
cd apps/airflow
uv run --project ../api pytest tests/bdd/steps/pipeline/ -v
# 모든 시나리오가 7a 실제 코드 호출 + stub 데이터 기준으로 PASS
```

**검증 체크리스트**
- [ ] skeleton의 NotImplementedError가 모두 제거됨
- [ ] 7a 실제 production 코드를 호출 (가짜 helper 우회 금지)
- [ ] 시나리오 전체가 골격 수준에서 PASS
- [ ] 시나리오별 디테일·edge case는 의도적으로 미구현 (LOOP 3 대상)

> **다음 Feature로**: STEP 7a로 돌아가 다음 Feature를 반복한다.  
> 모든 Feature 골격 통과 후 → STEP 8b (Mock-data E2E)로 이동

---

## ◀ MILESTONE 2 — Mock-data E2E (1회, STEP 8b)

> **진입 조건**: 모든 Feature에 대해 LOOP 2 (7a Walking Skeleton + 7b 골격 연결) 통과  
> **목적**: 세부 로직 구현(LOOP 3) 전에 **Frontend + Backend 풀스택이 mock 데이터로
>          시각적으로 동작**하는지 Playwright로 검증한다. 인터페이스 미스매치·라우팅
>          누락·CORS·렌더 누락을 LOOP 3 전에 잡아 작업 비용을 줄인다.

**핵심 원칙**
- 외부 의존(yfinance/PostgreSQL/Airflow runtime)은 모두 mock 우회
- USE_INMEMORY=true (backend), USE_MOCK=true (frontend api client) 만으로 동작
- BDD 50/50 (서버사이드)과 별개로 브라우저-수준 회귀 차단

---

### STEP 8b. Mock-data E2E

**목적**: vite dev + uvicorn 두 서버를 띄운 상태에서 Playwright가
브라우저로 클릭·입력하며 시나리오를 검증한다. 실제 사용자 플로우를
시각적으로 통과시키는 첫 관문.

**전제 (이미 PHASE 5 진입 전이라도 동작해야 함)**
- `apps/frontend/src/api/client.ts`의 `USE_MOCK=true` 분기 → hardcoded mock JSON
- `apps/api/app/core/dependencies.py`의 `USE_INMEMORY=true` 기본값 → 인메모리 store
- `tests/bdd/factories.py`의 seed 함수로 mock 데이터를 일관되게 채우기 가능

**표준 프롬프트**
```
Frontend(@/pages/*.tsx)와 Backend(apps/api/app)에 대해
풀스택 Mock-data E2E 환경을 구성해줘.

조건:
- @playwright/test 설치, apps/frontend/playwright.config.ts 작성
- 두 서버 동시 기동 스크립트 (concurrently 또는 Make 타겟)
  * vite dev :5173 (USE_MOCK=true)
  * uvicorn :8000 (USE_INMEMORY=true)
- Playwright 시나리오: .feature와 1:1 매핑 권장
  * 각 탭 정상 렌더 / 비거래일 / 검색·필터 / 상태 전환
- 외부 API hit / 실 DB 연결 금지 — 모두 mock
- BDD 50/50과 별도 실행 — `npm run e2e` 등
```

**예상 산출물**

| 파일 | 위치 | 역할 |
|------|------|------|
| `playwright.config.ts` | `apps/frontend/` | Playwright 설정 (baseURL, devices) |
| `package.json` 갱신 | `apps/frontend/` | @playwright/test devDep + scripts |
| `tests/e2e/*.spec.ts` | `apps/frontend/` | 탭별·통합 시나리오 |
| 동시 기동 스크립트 | 루트 또는 apps/frontend/ | `make e2e` 또는 `npm run e2e:full` |

**검증 체크리스트**
- [ ] `npm run e2e` 한 명령으로 dev server 기동 + Playwright 실행 + 종료
- [ ] 모든 시나리오 PASS (정상 / 비거래일 / 필터 / 상태 전환)
- [ ] BDD 50/50 무영향
- [ ] CI에서 별도 job으로 분리 (PHASE 3 STEP 10 보강 시점)

> **다음**: 풀스택 Green 확인 후 → LOOP 3 (시나리오별 세부 로직)로 이동.

---

## ◀ LOOP 3 — Feature별 반복 (STEP 7c ~ 8)

> **진입 조건**: STEP 8b Mock-data E2E 통과 (풀스택 골격 시각 검증 완료)  
> 에픽에 정의된 **모든 Feature**에 대해 STEP 7c~8을 반복한다.  
> 목표: 시나리오별 도메인 규칙·edge case 검증 로직 채워 BDD Green 달성

---

### STEP 7c. Step 세부 로직 구현

**목적**: 골격이 통과한 step에 시나리오별 입력 데이터·도메인 규칙
검증 로직을 채워 .feature가 의도한 인수기준을 실제로 검증한다.

**표준 프롬프트**
```
[컴포넌트]/specs/features/[도메인]/[feature명].feature와
[코드 경로]/[feature명].py (stub 코드)와
[컴포넌트]/tests/bdd/steps/[도메인]/[feature명]_steps.py (7b 골격)를 읽고
시나리오별 세부 로직을 채워줘.

- 시나리오별 mock_records / 입력 파라미터 구성
- error path / edge case 검증 (비거래일·미달·인증 실패 등)
- Then은 stub 반환값의 도메인 규칙(DR) 준수 여부까지 assert
- 골격 단계의 최소 assert는 도메인 규칙 검증으로 강화
```

**SP500 예시 프롬프트**
```
specs/features/pipeline/price_ingest.feature와
apps/api/app/pipeline/price_ingest.py와
apps/airflow/tests/bdd/steps/pipeline/price_ingest_steps.py(7b 골격)를 읽고
아래 시나리오별 세부 로직을 추가해줘:

- 거래일에 전체 종목 정상 수집:
    503개 mock_records 주입 → result.status == "completed", coverage >= 0.98
- 비거래일 DAG 자동 스킵:
    토요일 trade_date → result.status == "skipped", records 비어 있음
- 수집 종목 수 미달:
    490개 mock_records → result.status == "failed", coverage < 0.98
```

**예상 산출물**

| 파일 | 위치 | 변경 내용 |
|------|------|----------|
| `price_ingest_steps.py` | `apps/airflow/tests/bdd/steps/pipeline/` | 시나리오별 입력·도메인 규칙 assert 강화 |

---

### STEP 8. Green 확인

**목적**: 모든 시나리오가 도메인 규칙 검증까지 통과함을 확인한다.

**명령어**
```bash
cd apps/airflow
uv run --project ../api pytest tests/bdd/steps/pipeline/test_price_ingest.py -v
```

**예상 출력**
```
PASSED  거래일에 전체 종목 정상 수집
PASSED  비거래일 DAG 자동 스킵
PASSED  수집 종목 수 미달 시 실패 처리

3 passed in 0.42s
```

> **다음 Feature로**: STEP 7c로 돌아가 다음 Feature를 반복한다.  
> 모든 Feature Green 확인 후 → PHASE 3으로 이동

---

## PHASE 3 — CI / Living Docs

### STEP 9. PR 생성

**목적**: Green 코드를 develop 브랜치로 병합 요청한다.

**표준 프롬프트**
```
현재 브랜치의 변경사항으로 develop 브랜치에 PR을 생성해줘.

PR 내용에 포함:
- 구현한 Feature ID와 시나리오 목록
- 테스트 통과 수
- 관련 스펙 파일 링크
```

**명령어 예시**
```bash
git checkout -b feature/F-01-01-price-ingest
git add .
git commit -m "feat(pipeline): F-01-01 일별 주가 수집 DAG BDD Green"
gh pr create --base develop --title "feat(pipeline): F-01-01 일별 주가 수집 DAG"
```

---

### STEP 10. CI 자동 실행

**목적**: Lint, 테스트, 커버리지, 보안 스캔이 자동 통과됨을 확인한다.

**CI 구성 프롬프트** (최초 1회)
```
.github/workflows/ci.yml을 작성해줘.

요구사항:
- Lint: ruff + black
- 테스트: api / airflow / frontend 컴포넌트별 실행
- 각 테스트에 --json-report로 JSON 리포트 생성
- coverage 합산 80% 이상 게이트
- Living Docs: scripts/gen_living_docs.py 실행 후 자동 커밋
- 보안 스캔: Trivy HIGH/CRITICAL
- permissions: contents: write (Living Docs 커밋용)
```

**예상 CI 단계**
```
✅ Lint (ruff, black)
✅ API Tests          → .report_api.json
✅ Airflow Tests      → .report_airflow.json
✅ Frontend Tests     → .report_frontend.json
✅ Coverage ≥ 80%
✅ Living Docs 생성   → docs/LIVING_DOCS.md 자동 커밋
✅ Security Scan (Trivy)
```

---

### STEP 11. Living Documentation 설정

**목적**: .feature + 테스트 결과 → LIVING_DOCS.md 자동 생성 파이프라인을 구성한다.

**표준 프롬프트** (최초 1회)
```
scripts/gen_living_docs.py를 작성해줘.

기능:
- api/airflow/frontend 3개 컴포넌트의 .feature 파일 파싱
- .report_api.json / .report_airflow.json / .report_frontend.json 읽어 결과 합산
- 시나리오 이름 정규화 (한국어 조사 제거, 언더스코어→공백)
- api/airflow: 시나리오 이름 매칭
- frontend: 파일명 매핑 (test_X.py → X.feature)
- 결과: docs/LIVING_DOCS.md 생성

출력 형식:
# Living Documentation
> 자동 생성 · {날짜}
## 요약 (total/passed/failed)
## API / Pipeline / Frontend 섹션별 시나리오 목록 (✅/❌/⬜)
```

**예상 산출물**

| 파일 | 위치 | 갱신 |
|------|------|------|
| `gen_living_docs.py` | `scripts/` | 최초 1회 |
| `LIVING_DOCS.md` | `docs/` | CI 완료마다 🤖 자동 |

**실행 확인**
```bash
cd apps/api && uv run pytest tests/ --json-report --json-report-file=../.report_api.json -q
cd apps/airflow && uv run --project ../api pytest tests/ --json-report --json-report-file=../.report_airflow.json -q
cd apps/frontend && uv run --project ../api pytest tests/ --json-report --json-report-file=../.report_frontend.json -q
python scripts/gen_living_docs.py
# ✅ 생성 완료: docs/LIVING_DOCS.md
# 시나리오 50개 · ✅ 50 · ❌ 0 · ⬜ 0
```

---

## PHASE 4 — 유지

### STEP 12. 스펙 구조 검증

**표준 프롬프트** (PR 머지 전 주기적 실행)
```
specs/features/ 하위 모든 *_spec.md와
specs/product/00_vision.md / 01_domain.md / 02_epics.md의
일관성을 점검해줘.

확인 항목:
- spec 파일마다 관련 FR/Epic/DR/OKR 필드 존재
- Gherkin 블록(```gherkin) 잔존 여부
- FR 체크박스(- [ ]) 잔존 여부
- .feature 링크 섹션 존재
- epics.md DR 컬럼 및 DR→Feature 추적 섹션 존재
- vision.md OKR→FR 매핑 섹션 존재
```

**예상 출력**
```
✅ 전체 이상 없음
또는
❌ [누락 필드] specs/features/auth/rbac_spec.md — '관련 DR' 없음
```

---

## PHASE 5 — 데이터 소스 교체 (Stub Data → Real Data)

> **진입 조건**: PHASE 2 완료 (BDD 50/50 Green) — 7a Walking Skeleton과
>               6a stub data가 모두 갖춰져 있음.
> **목표**: 6a stub 데이터(`_store` dict, `mock_records`, 하드코딩 mock JSON)를
>          실제 데이터 소스(PostgreSQL, yfinance, 실 API)로 교체하면서
>          BDD Green을 그대로 유지한다. **production 코드 뼈대는 LOOP 2 7a에서
>          이미 작성되어 있으므로 PHASE 5에서는 데이터 어댑터·런타임만 다룬다.**

**핵심 원칙**
- 6a stub 인터페이스를 경계로 유지 → 기존 BDD 테스트 무수정
- 실제 구현은 dependency injection / repository 패턴으로 주입
- 데이터 소스 영역 단위로 순차 교체 — 영역 종료마다 통합 검증

---

### STEP 13. DB 어댑터 구현

**목적**: `apps/api/app/core/dependencies.py`의 인메모리 `_store` dict를
PostgreSQL/DW/Mart 실제 DB로 교체한다. 6a stub 인터페이스(get_*_store)는
그대로 두고 repository 패턴으로 구현체를 주입한다.

**표준 프롬프트**
```
apps/api/app/core/dependencies.py의 _store 사용 패턴과
specs/_methodology/std/03_database.md를 읽고
실제 DB 연동 어댑터를 구현해줘.

조건:
- repository 패턴 — get_*_store() 인터페이스는 유지
- 구현체: SQLAlchemy 또는 asyncpg 기반
- 테이블 스키마는 specs/product/01_domain.md DR과 일치
- 테스트 환경은 dependency_overrides로 인메모리 유지 (BDD 무수정)
- 마이그레이션 도구: alembic
```

**예상 산출물**

| 파일 | 위치 | 역할 |
|------|------|------|
| `repositories/ods_repo.py` | `apps/api/app/` | ODS 테이블 CRUD |
| `repositories/dw_repo.py` | `apps/api/app/` | DW Sector 집계 CRUD |
| `repositories/mart_repo.py` | `apps/api/app/` | Mart Key Index CRUD |
| `db/session.py` | `apps/api/app/` | SQLAlchemy 세션 |
| `db/models.py` | `apps/api/app/` | ORM 모델 (DR 반영) |
| `alembic/versions/*.py` | `apps/api/` | 마이그레이션 스크립트 |

**검증 체크리스트**
- [ ] `dependency_overrides[get_*_store] = get_store` 테스트 패턴 유지
- [ ] BDD 50/50 Green 유지 (인메모리로 동작)
- [ ] 통합 테스트에서 실제 DB 연동 동작 확인
- [ ] alembic upgrade head 성공

> **⚠️ Airflow 공유 DB 주의**: Airflow도 같은 Postgres DB에 alembic을 사용한다.
> `alembic_version` 테이블이 Airflow 버전 ID로 채워진 상태에서 앱 마이그레이션을 실행하면
> `Can't locate revision` 오류가 발생한다.
> `alembic/env.py`의 `context.configure()`에 반드시 `version_table="sp500_alembic_version"`을
> 추가해 앱 전용 버전 테이블을 분리해야 한다.

---

### STEP 14. 외부 API 어댑터 구현

**목적**: `mock_records` 주입으로 우회되던 외부 시세 수집을
yfinance 등 실제 API 호출로 교체한다. 6a stub 함수의
`mock_records=None` 분기 인터페이스는 그대로 둔다.

**표준 프롬프트**
```
apps/api/app/pipeline/price_ingest.py의 mock_records 분기 패턴과
specs/_methodology/std/08_data_pipeline.md를 읽고
실제 외부 시세 API 어댑터를 구현해줘.

조건:
- 어댑터 클래스 (PriceFeedAdapter 등) — 인터페이스 정의 후 구현
- stub의 mock_records=None 분기에서 어댑터 호출
- 재시도/타임아웃/Rate-limit 처리
- 테스트는 mock_records 주입으로 어댑터 우회 (BDD 무수정)
- 자격 증명은 환경변수 (.env, secret manager)
```

**예상 산출물**

| 파일 | 위치 | 역할 |
|------|------|------|
| `adapters/price_feed.py` | `apps/api/app/` | yfinance/Alpha Vantage 등 |
| `adapters/calendar_feed.py` | `apps/api/app/` | NYSE 거래일 (있으면) |
| `core/config.py` | `apps/api/app/` | 외부 API 키 환경변수 |

**검증 체크리스트**
- [ ] `mock_records` 주입 시 어댑터 호출 안 됨 (테스트 격리)
- [ ] BDD 50/50 Green 유지
- [ ] 실제 호출 통합 테스트 (별도 marker, CI 분리)
- [ ] Rate-limit / retry / timeout 동작 검증

---

### STEP 15. 인프라 runtime 구축

**목적**: LOOP 2 STEP 7a에서 작성된 실제 DAG·API·프론트엔드 코드를
실행할 수 있는 **인프라 환경**을 구축한다. (DAG 파일 자체는 7a에서 이미 존재)

**표준 프롬프트**
```
apps/airflow/dags/*.py 와 apps/api/app/main.py 를 읽고
아래 6개 서비스를 포함한 docker-compose 스택을 작성해줘.

서비스:
- Postgres 16 (Airflow·API·Keycloak 공용 DB, 로컬 포트 충돌 시 5433 매핑)
- Keycloak 24 (sp500, admin/analyst 역할, realm-export.json import)
- OpenSearch 2.x (로그·트레이스 인덱싱, security 비활성)
- OpenSearch Dashboards 2.x
- OpenTelemetry Collector (OTLP gRPC 4317 / HTTP 4318, OpenSearch exporter)
- Airflow 2.10 (LocalExecutor, scheduler + webserver, PYTHONPATH=/opt/airflow/api_src)

구조 조건:
- docker-compose.yml (루트 entry) → include: infra/compose/<service>.yml 분리
- x-airflow-common YAML 앵커로 scheduler/webserver/init 공통 설정 통합
- airflow-init: DB upgrade + admin 계정 생성 (command는 YAML >- 스칼라 one-liner 사용)
- apps/api 코드를 volume mount로 Airflow에 공유 (PYTHONPATH 주입)
- 7a Walking Skeleton 코드 무수정 — runtime만 추가

운영(K8s):
- infra/helm/<service>-values.yaml (upstream chart values)
- infra/k8s/base/ (kustomize, apps/api·airflow·frontend deployment)
```

**예상 산출물**

| 파일 | 위치 | 역할 |
|------|------|------|
| `docker-compose.yml` | 루트 | `include:` entry point |
| `infra/compose/postgres.yml` | `infra/compose/` | Postgres 서비스 |
| `infra/compose/keycloak.yml` | `infra/compose/` | Keycloak 서비스 |
| `infra/compose/opensearch.yml` | `infra/compose/` | OpenSearch 서비스 |
| `infra/compose/opensearch-dashboards.yml` | `infra/compose/` | OSD 서비스 |
| `infra/compose/otel-collector.yml` | `infra/compose/` | OTel Collector 서비스 |
| `infra/compose/airflow.yml` | `infra/compose/` | Airflow 3-service (init/scheduler/webserver) |
| `apps/airflow/Dockerfile` | `apps/airflow/` | Airflow 이미지 (requirements 포함) |
| `apps/airflow/requirements.txt` | `apps/airflow/` | exchange-calendars, yfinance 등 |
| `infra/airflow/webserver_config.py` | `infra/airflow/` | dev AUTH_DB 설정 |
| `infra/keycloak/realm-export.json` | `infra/keycloak/` | sp500 정의 |
| `infra/helm/*.yaml` | `infra/helm/` | K8s upstream chart values |
| `infra/k8s/base/` | `infra/k8s/` | kustomize base manifests |

**검증 체크리스트**
- [ ] `docker compose ps` — 7개 서비스 모두 healthy (또는 running)
- [ ] Keycloak: `GET /realms/sp500/.well-known/openid-configuration` → issuer 반환
- [ ] Keycloak: admin token 취득 → sp500 역할(admin/analyst) 확인
- [ ] OpenSearch: `GET /_cluster/health` → status yellow 이상 (단일 노드는 yellow 정상)
- [ ] OpenSearch: 문서 POST → `result=created`
- [ ] OpenSearch Dashboards: `GET /api/status` → `state=green`
- [ ] OTel Collector: `GET localhost:13133` → `Server available`
- [ ] OTel OTLP: HTTP POST 4318/v1/traces → 200
- [ ] Airflow: `GET localhost:8081/health` → scheduler=healthy, metadatabase=healthy
- [ ] Airflow: `airflow dags list` → ingest_sp500_daily 확인
- [ ] BDD Green 유지 (인메모리 모드, e2e 제외)

> 전체 일괄 검증 스크립트: `doc-manure/INFRA_VALIDATION.md` § 4 참조

**알려진 함정 (Pitfalls)**

| 증상 | 원인 | 해결 |
|------|------|------|
| Keycloak healthcheck 실패 (`curl not found`) | distroless 이미지 | `test: ["CMD-SHELL", "grep -q 1F90 /proc/net/tcp6"]` |
| OTel Collector unhealthy (`wget not found`) | distroless 이미지 | `healthcheck: disable: true`, 호스트에서 `curl localhost:13133` 확인 |
| Keycloak admin 로그인 실패 (`user_not_found`) | 기존 DB 볼륨에서 bootstrap admin 미생성 | `docker compose down -v` 후 재기동 |
| airflow-init 명령 인자 파싱 오류 | YAML `>` folded scalar가 줄바꿈을 공백으로 접어 인자를 분리 | `command: >-` (strip + fold) + one-liner 또는 `|` (literal) |
| Postgres 포트 충돌 | 로컬 postgres가 5432 점유 | `infra/compose/postgres.yml`에서 `"5433:5432"` 매핑 |
| OpenSearch start_period 타임아웃 | 초기화 90초 이상 소요 | `start_period: 90s`, `retries: 18` |

---

### STEP 16. E2E 통합 테스트

**목적**: 실제 Airflow runtime + DB + 외부 API + Frontend가 조합된 환경에서
BDD 시나리오가 Green을 유지하는지 확인하고, 인프라 레이어 통합 시나리오를 추가한다.

**표준 프롬프트**
```
docker-compose 또는 testcontainers로 STEP 15 환경을 띄운 뒤
specs/features/**/*.feature의 시나리오를 실제 인프라에서 실행해줘.

조건:
- pytest marker `@pytest.mark.e2e` 로 분리
- BDD 시나리오는 무수정 — fixture만 실제 인프라용으로 교체
- 실제 호출 시나리오 (외부 API hit / DB persist / DAG trigger / UI render) 추가
- CI에서는 별도 job으로 분리 (느린 테스트)
```

**예상 산출물**

| 파일 | 위치 | 역할 |
|------|------|------|
| `tests/e2e/__init__.py` | `apps/api/` | 패키지 선언 |
| `tests/e2e/conftest.py` | `apps/api/` | testcontainers PostgresContainer fixture |
| `tests/e2e/test_pipeline_e2e.py` | `apps/api/` | `@pytest.mark.e2e` BDD 시나리오 + Repository round-trip |
| `.github/workflows/e2e.yml` | `.github/` | E2E 별도 CI job (develop push + 수동) |
| `pytest.ini` markers 추가 | `apps/api/` | `e2e` marker 등록 (미등록 시 경고) |

**검증 체크리스트**
- [ ] `uv run pytest tests/e2e/ -m e2e` — 모든 E2E 테스트 Green
- [ ] `uv run pytest tests/ --ignore=tests/e2e` — 기존 BDD Green 유지
- [ ] Repository round-trip (upsert → get_by_date) 정합성 확인
- [ ] upsert 멱등성 확인 (같은 거래일 재실행 시 중복 없음)
- [ ] CI: `ci.yml`에 `--ignore=tests/e2e`, `e2e.yml`에 `-m e2e` 분리

> **⚠️ testcontainers 격리**: E2E 테스트는 **운영 DB(sp500-postgres)가 아닌**
> testcontainers가 세션마다 기동·소멸하는 임시 PostgreSQL 컨테이너에 쓴다.
> 테스트 종료 후 운영 DB에 데이터가 없는 것은 정상이다.
> 운영 DB에 실제 데이터를 채우려면 Airflow DAG를 트리거해야 한다.
>
> **⚠️ psycopg2-binary**: testcontainers PostgresContainer의 기본 드라이버는 psycopg2.
> `pyproject.toml` dev deps에 `psycopg2-binary` 추가 필요 (asyncpg만으로는 부족).
>
> **⚠️ pytest.ini vs pyproject.toml**: `pytest.ini`가 존재하면 `pyproject.toml`의
> `[tool.pytest.ini_options]`가 무시된다. marker는 `pytest.ini`에 등록해야 경고가 사라진다.

> **PHASE 5 완료 기준**: 인메모리 stub 모드와 실제 인프라 모드가
> **둘 다 Green** — 어느 쪽으로도 배포 가능한 상태.

---

## 전체 진행 체크리스트

```
PHASE 1 — 제품 전략 (1회)
  [ ] STEP 1: specs/product/00_vision.md
  [ ] STEP 2: specs/product/01_domain.md
  [ ] STEP 3: specs/product/02_epics.md

PHASE 2 — Feature 개발
  LOOP 1 (Feature별 반복 — STEP 4~6a)
    [ ] STEP 4: specs/features/{domain}/{feature}_spec.md
    [ ] STEP 5: specs/features/{domain}/{feature}.feature
    [ ] STEP 6: Red 확인 (StepDefinitionNotFoundError)
    [ ] STEP 6a: app/ stub 코드 작성 (인메모리, DR 로직 포함)
    → 다음 Feature로 반복

  MILESTONE (전체 Stub 완성 후 1회)
    [ ] STEP 6b: apps/frontend/src/mockup.html 작성
    [ ] 이해관계자 요구사항 검증 완료
    [ ] 인수기준 변경 시 Loop 1 해당 Feature 재실행
    [ ] 인수기준 확정

  LOOP 2 (Feature별 반복 — STEP 7a~7b)
    [ ] STEP 7a: 실제 production 코드 뼈대 (Walking Skeleton)
                apps/airflow/dags/*.py · apps/frontend/src/* · 실제 framework 구조
                데이터는 6a stub 인터페이스 호출
    [ ] STEP 7b: pytest --generate-missing → step skeleton
                + 실제 production 코드 호출로 연결 (시나리오 골격 PASS)
    → 다음 Feature로 반복

  MILESTONE 2 (전체 Walking Skeleton 완성 후 1회)
    [ ] STEP 8b: Mock-data E2E (Playwright)
                frontend + backend 동시 기동, 외부 의존 모두 mock
                풀스택 시각 검증 후 LOOP 3 진입

  LOOP 3 (Feature별 반복 — STEP 7c~8)
    [ ] STEP 7c: 시나리오별 세부 로직 (mock_records · DR assert 강화)
    [ ] STEP 8: Green 확인 (N passed)
    → 다음 Feature로 반복

PHASE 3 — CI / Living Docs (1회 설정)
  [ ] STEP 9: PR 생성
  [ ] STEP 10: CI 파이프라인 구성 (.github/workflows/ci.yml)
  [ ] STEP 11: Living Docs 설정 (scripts/gen_living_docs.py)

PHASE 4 — 유지 (지속/주기적)
  [ ] STEP 12: 스펙 일관성 검증 (주기적)

PHASE 5 — 데이터 소스 교체 (Stub Data → Real Data)
  [ ] STEP 13: apps/api/app/repositories + db/ — DB 어댑터 (_store → PostgreSQL)
  [ ] STEP 14: apps/api/app/adapters/*.py — 외부 API 어댑터 (mock_records → yfinance)
  [ ] STEP 15: docker-compose / Helm — 인프라 runtime (Airflow scheduler, API/Front 컨테이너)
  [ ] STEP 16: tests/e2e/ — 실제 인프라 BDD Green 확인
  → 인메모리 모드 + 실제 인프라 모드 둘 다 Green이면 배포 준비 완료
```

---

## 산출물 유형 요약

| 산출물 | 파일 패턴 | 생성 방식 | 생성 시점 |
|--------|----------|----------|----------|
| 제품 비전 | `00_vision.md` | 🤖 AI 초안 → 👤 검증 | STEP 1 |
| 도메인 모델 | `01_domain.md` | 🤖 AI 초안 → 👤 검증 | STEP 2 |
| Epic 목록 | `02_epics.md` | 🤖 AI 초안 → 👤 검증 | STEP 3 |
| 비즈니스 스펙 | `*_spec.md` | 🤖 AI 초안 → 👤 검증 | STEP 4 (Loop 1) |
| Gherkin 시나리오 | `*.feature` | 🤖 AI 초안 → 👤 검증 | STEP 5 (Loop 1) |
| Stub 코드 (인메모리) | `apps/api/app/pipeline/*.py`, `apps/api/app/core/dependencies.py` | 🤖 AI 초안 → 👤 DR 준수 확인 | STEP 6a (Loop 1) |
| UI/UX 목업 | `mockup.html` | 🤖 AI 초안 → 👤 요구사항 검증 | STEP 6b (Milestone) |
| Walking Skeleton (Pipeline) | `apps/airflow/dags/*.py` | 🤖 AI 초안 → 👤 검증 | STEP 7a (Loop 2) |
| Walking Skeleton (API) | `apps/api/app/routers/*.py`, `apps/api/app/main.py` | 🤖 AI 초안 → 👤 검증 | STEP 7a (Loop 2) |
| Walking Skeleton (Frontend) | `apps/frontend/src/App.*`, `apps/frontend/src/components/*` | 🤖 AI 초안 → 👤 검증 | STEP 7a (Loop 2) |
| Test Step skeleton | `*_steps.py` | 🤖 pytest --generate-missing | STEP 7b (Loop 2) |
| Test Step 골격 | `*_steps.py`, `test_*.py` | 🤖 AI 초안 → 👤 골격 통과 확인 | STEP 7b (Loop 2) |
| Test Step 세부 로직 | `*_steps.py` | 🤖 AI 초안 → 👤 DR 검증 | STEP 7c (Loop 3) |
| Mock-data E2E (Playwright) | `apps/frontend/playwright.config.ts`, `apps/frontend/tests/e2e/*.spec.ts` | 🤖 AI 초안 → 👤 검증 | STEP 8b (Milestone 2) |
| CI 파이프라인 | `ci.yml` | 🤖 AI 초안 → 👤 검증 | STEP 10 (1회) |
| Living Docs 생성기 | `gen_living_docs.py` | 🤖 AI 초안 → 👤 검증 | STEP 11 (1회) |
| Living Documentation | `LIVING_DOCS.md` | 🤖 CI 완전 자동 | CI 완료마다 |
| DB 어댑터 | `apps/api/app/repositories/`, `apps/api/app/db/` | 🤖 AI 초안 → 👤 검증 | STEP 13 (Phase 5) |
| 외부 API 어댑터 | `apps/api/app/adapters/*.py` | 🤖 AI 초안 → 👤 검증 | STEP 14 (Phase 5) |
| 인프라 runtime | `docker-compose.yml`, `infra/compose/*.yml`, `apps/airflow/Dockerfile`, `infra/helm/`, `infra/k8s/` | 🤖 AI 초안 → 👤 검증 | STEP 15 (Phase 5) |
| E2E 통합 테스트 | `tests/e2e/conftest.py`, `tests/e2e/test_*.py`, `.github/workflows/e2e.yml` | 🤖 AI 초안 → 👤 검증 | STEP 16 (Phase 5) |
