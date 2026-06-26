# Spec: specs/{project}/business_spec.md
# AC:   {FR-NN} — {요건 설명}
# Owner: {팀명}
# Updated: YYYY-MM-DD

Feature: {기능명 — 비즈니스 언어로}
  {기능 한 줄 설명 — 사용자 관점}

  Background:
    # 모든 Scenario에 공통으로 적용되는 전제 조건
    # 없으면 삭제
    Given 시스템이 정상 동작 중이다

  # ──────────────────────────────────────────────
  # Happy Path — 정상 조건
  # ──────────────────────────────────────────────

  Scenario: {정상 조건 한 줄 설명}
    Given {초기 상태 — 기술 용어 금지}
    And   {추가 전제 조건 — 필요 시}
    When  {사용자 또는 시스템의 행동}
    Then  {기대 결과 — 검증 가능한 사실}
    And   {추가 기대 결과 — 필요 시}

  # ──────────────────────────────────────────────
  # Exception — 예상 가능한 오류
  # ──────────────────────────────────────────────

  Scenario: {오류 상황 한 줄 설명}
    Given {오류 유발 초기 상태}
    When  {동일한 행동}
    Then  {오류 응답 기대 결과}
    And   {에러 코드 또는 메시지 확인}

  # ──────────────────────────────────────────────
  # Edge Case — 경계값 (선택)
  # ──────────────────────────────────────────────

  Scenario: {경계 조건 한 줄 설명}
    Given ...
    When  ...
    Then  ...

  # ──────────────────────────────────────────────
  # Scenario Outline — 다중 입력값 (선택)
  # ──────────────────────────────────────────────

  Scenario Outline: {반복 패턴 설명}
    Given ...
    When  <input> 으로 요청하면
    Then  <expected_result> 이어야 한다

    Examples:
      | input   | expected_result |
      | value1  | result1         |
      | value2  | result2         |
      | value3  | result3         |
