# GOV-06 — API 설계 규칙

> **강제 대상**: 모든 REST API 엔드포인트  
> **게이트**: Spectral OpenAPI 린트 — 위반 시 CI 차단  
> **원본 참조**: `enterprise/06.02_gov_api_governance.md`, `common/backend_fastapi.md`

---

## REST 설계 필수 규칙 (MUST)

### URL 규칙
```
/v{N}/{resource-plural}/{id}/{sub-resource}

예:
  GET  /v1/analyses                    목록
  GET  /v1/analyses/{id}               단건
  POST /v1/analyses                    생성
  GET  /v1/analyses/{id}/ice-breakers  하위 리소스

금지:
  /getAnalysis     (동사 금지)
  /analysis        (단수 금지)
  /v1/Analysis     (대문자 금지)
```

### HTTP 메서드·상태 코드

| 메서드 | 용도 | 성공 코드 |
|--------|------|---------|
| GET | 조회 | 200 |
| POST | 생성 | 201 |
| PUT | 전체 수정 | 200 |
| PATCH | 부분 수정 | 200 |
| DELETE | 삭제 | 204 |

### 에러 응답 포맷 (통일 필수)

```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "분석 결과를 찾을 수 없습니다.",
    "details": [
      { "field": "trade_date", "issue": "비거래일입니다." }
    ],
    "request_id": "uuid-v4"
  }
}
```

| 상황 | 코드 | error.code |
|------|------|-----------|
| 입력 검증 실패 | 422 | `VALIDATION_ERROR` |
| 리소스 없음 | 404 | `NOT_FOUND` |
| 권한 없음 | 403 | `FORBIDDEN` |
| 인증 실패 | 401 | `UNAUTHORIZED` |
| 서버 오류 | 500 | `INTERNAL_ERROR` |
| 외부 API 오류 | 502 | `EXTERNAL_API_ERROR` |

---

## API 버전 관리 규칙

- URL prefix 방식: `/v1/`, `/v2/`
- Breaking change 시 새 버전 생성
- 구버전 최소 6개월 운영 후 Deprecation 공지
- `Deprecation: date=YYYY-MM-DD` 헤더 추가

---

## OpenAPI 스펙 필수 항목 (MUST)

| 항목 | 규칙 |
|------|------|
| summary | 모든 endpoint에 작성 |
| operationId | camelCase, 전역 유일 |
| tags | 도메인별 분류 |
| requestBody.required | 명시 필수 |
| responses | 성공/에러 코드 모두 정의 |
| security | 인증 명시 |

> 구현 예시(YAML 작성 패턴)는 [`std/01_backend.md` — OpenAPI 작성 패턴](../std/01_backend.md) 참조.

---

## CI Spectral 린트 설정

```yaml
# .spectral.yaml
extends: ["spectral:oas"]
rules:
  operation-operationId: error       # operationId 필수
  operation-tags: error              # tags 필수
  operation-summary: error           # summary 필수
  oas3-valid-media-example: warn
```

```yaml
# GitHub Actions
- name: API Lint
  run: spectral lint docs/api/openapi.yaml --fail-severity=error
```

---

## 하위 호환성 규칙

Breaking Change 금지 (기존 버전에서):
- 필드 삭제
- 필드 타입 변경
- 필수 필드 추가
- 상태 코드 변경

허용 (하위 호환):
- 선택적 필드 추가
- 새 상태 코드 추가 (기존 유지)
- 새 엔드포인트 추가

---

## 검증 체크리스트

> 이 가이드 기준으로 application을 audit할 때 사용. 각 항목은 yes/no로 평가.
> 식별자(`G06-NN-MM`)는 통합 인덱스(`specs/_methodology/CHECKLIST.md`)에서 참조.

### 카테고리 1: URL·메서드 규칙
- [ ] G06-01-01: 모든 endpoint가 `/v{N}/{resource-plural}` 패턴을 따르는가
- [ ] G06-01-02: URL에 동사(getX, processY)가 사용되지 않았는가
- [ ] G06-01-03: URL이 모두 소문자·복수형 명사인가
- [ ] G06-01-04: HTTP 메서드와 의미(GET/POST/PUT/PATCH/DELETE)가 일치하는가
- [ ] G06-01-05: 성공 상태 코드가 의미별로 정확한가 (POST 201, DELETE 204 등)

### 카테고리 2: 에러 응답 통일
- [ ] G06-02-01: 모든 에러 응답이 통일 포맷(`error.code`, `error.message`, `error.details`, `error.request_id`)을 따르는가
- [ ] G06-02-02: 정의된 error.code(`VALIDATION_ERROR`, `NOT_FOUND`, `FORBIDDEN`, `UNAUTHORIZED`, `INTERNAL_ERROR`, `EXTERNAL_API_ERROR`) 외의 임의 코드가 없는가
- [ ] G06-02-03: 422/404/403/401/500/502 외 비표준 코드가 사용되지 않았는가

### 카테고리 3: OpenAPI 스펙
- [ ] G06-03-01: 모든 endpoint에 summary가 있는가
- [ ] G06-03-02: operationId가 camelCase·전역 유일한가
- [ ] G06-03-03: tags가 도메인별로 분류됐는가
- [ ] G06-03-04: requestBody.required 명시가 있는가
- [ ] G06-03-05: 성공·에러 응답 schema가 모두 정의됐는가
- [ ] G06-03-06: security 항목이 명시됐는가
- [ ] G06-03-07: Spectral 린트가 CI에서 실행되며 fail-severity=error로 강제되는가

### 카테고리 4: 버전·하위 호환
- [ ] G06-04-01: API 버전이 URL prefix(`/v1/`, `/v2/`) 방식인가
- [ ] G06-04-02: Breaking change 시 새 버전이 생성됐는가
- [ ] G06-04-03: 구버전 deprecation 시 `Deprecation: date=YYYY-MM-DD` 헤더가 있는가
- [ ] G06-04-04: 기존 버전에서 필드 삭제·타입 변경·필수 필드 추가가 없는가
