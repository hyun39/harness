# BDD-01 — Gherkin 작성 가이드

> **목적**: 비즈니스 스펙의 인수기준을 실행 가능한 `.feature` 파일로 만드는 방법  
> **원본 참조**: `enterprise/01.03_std_executable_specification.md`

---

## Gherkin 3원칙

| 원칙 | 내용 |
|------|------|
| 비즈니스 언어 | 기술 용어 금지 — "HTTP 200"이 아니라 "정상 조회됨" |
| 선언적 | What(무엇이 되어야 하는가) — How(어떻게 구현하는가) 금지 |
| 독립적 | Scenario 간 상태 공유 금지 — 각자 Given으로 초기화 |

---

## 파일 구조

```gherkin
# specs/features/{domain}/{feature_name}.feature

Feature: {기능명} — 한 줄 설명

  Background:          # 모든 Scenario 공통 전제 조건
    Given ...

  Scenario: {Happy Path 설명}
    Given ...
    When  ...
    Then  ...

  Scenario: {예외 상황 설명}
    Given ...
    When  ...
    Then  ...

  Scenario Outline: {경계값·다중 입력 테스트}
    Given ...
    When  ...
    Then  ...
    Examples:
      | input | expected |
      | ...   | ...      |
```

---

## Given / When / Then 작성 기준

| 키워드 | 역할 | 작성 기준 |
|--------|------|---------|
| `Given` | 전제 조건 (상태) | 시스템이 어떤 상태인지 — 과거 시제 |
| `When` | 행동 (이벤트) | 사용자 또는 시스템이 무엇을 하는지 — 능동 |
| `Then` | 기대 결과 | 어떤 상태가 되어야 하는지 — 검증 가능한 사실 |
| `And` | 이전 키워드 연장 | Given/When/Then 반복 시 And 사용 |

---

## 좋은 예시 vs 나쁜 예시

### 나쁜 예시 — 기술 구현 노출
```gherkin
Scenario: 주가 데이터 조회
  Given PostgreSQL의 ods_stock_price_daily 테이블에 데이터가 있고
  When GET /api/v1/analyses?trade_date=2026-05-01 HTTP 요청을 보내면
  Then JSON 응답의 status_code가 200이고 body에 analyses 배열이 있다
```

### 좋은 예시 — 비즈니스 언어
```gherkin
Scenario: 거래일 트렌드 분석 정상 조회
  Given 2026-05-01 거래일의 데이터 수집이 완료된 상태이고
  And 사용자가 분석가 권한으로 로그인되어 있다
  When 2026-05-01 트렌드 분석을 조회하면
  Then 11개 Sector의 분석 결과가 반환된다
  And 각 결과에 bullish/bearish/neutral 중 하나의 심리 지표가 포함된다
```

---

## 시나리오 분류 기준

| 유형 | 설명 | 예시 |
|------|------|------|
| Happy Path | 정상 조건 모두 충족 | 거래일 정상 조회 |
| Exception | 예상 가능한 오류 | 비거래일 404, 권한 없음 403 |
| Edge Case | 경계값·동시성 | 빈 결과, 날짜 범위 한계 |
| Outline | 여러 입력값 반복 | 다양한 날짜 형식 검증 |

---

## Scenario Outline 사용 기준

같은 행동·결과 패턴에 다른 입력값이 3개 이상일 때 사용.

```gherkin
Scenario Outline: 잘못된 날짜 형식은 거부된다
  When <date_input> 형식으로 트렌드 분석을 조회하면
  Then 요청이 거부된다
  And 에러 코드는 VALIDATION_ERROR이다

  Examples:
    | date_input  |
    | 2026/05/01  |
    | 05-01-2026  |
    | 20260501    |
    | not-a-date  |
```

---

## 파일 네이밍·위치 규칙

```
tests/bdd/
├── features/
│   ├── {domain}/
│   │   ├── {feature_name}.feature
│   │   └── ...
└── steps/
    ├── {domain}/
    │   ├── {feature_name}_steps.py  (FastAPI)
    │   └── ...
    └── conftest.py
```

---

## .feature 파일 ↔ 비즈니스 스펙 연결

`.feature` 파일 상단에 비즈니스 스펙 참조를 추가한다.

```gherkin
# Spec: specs/{project}/business_spec.md
# AC: FR-01 (거래일 트렌드 분석 조회)
Feature: 트렌드 분석 조회
  ...
```
