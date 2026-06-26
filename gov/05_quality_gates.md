# GOV-05 — 테스트·품질 게이트

> **강제 대상**: 모든 PR 및 배포  
> **게이트**: 각 단계 실패 시 다음 단계 진행 불가  
> **원본 참조**: `enterprise/06.01_gov_testing_strategy.md`, `common/testing_strategy.md`

---

## 테스트 피라미드 비율 기준

```
Unit (70%) ──► Integration (20%) ──► Contract (7%) ──► E2E (3%)
   PR 즉시          PR 머지 전           PR 머지 전      main 머지 후
```

| 레이어 | 커버리지 게이트 | 실패 시 |
|--------|-------------|--------|
| Unit | 전체 80% 이상, Service 90% 이상 | PR 차단 |
| Integration | 핵심 흐름 전체 통과 | PR 차단 |
| BDD (.feature) | 모든 Scenario 통과 | PR 차단 |
| Contract (Pact) | Provider 검증 통과 | PR 차단 |
| E2E | Happy Path + 주요 예외 통과 | 배포 차단 |

---

## BDD 게이트 규칙 (MUST)

- [ ] 모든 비즈니스 스펙의 Gherkin 인수기준은 `.feature` 파일로 존재한다
- [ ] 모든 `.feature` Scenario는 Step 구현이 완료되어 있다
- [ ] BDD 테스트는 PR CI에서 자동 실행된다
- [ ] 신규 기능 PR에는 대응하는 `.feature` 변경이 포함된다

```yaml
# CI BDD 게이트
- name: BDD Tests
  run: pytest tests/bdd/ --tb=short -q
  # 실패 시 PR 머지 차단
```

---

## 커버리지 게이트 설정

### Python (pytest-cov)
```bash
pytest --cov=app --cov-fail-under=80 --cov-report=xml
```

### Java (JaCoCo)
```xml
<limit>
  <counter>LINE</counter>
  <value>COVEREDRATIO</value>
  <minimum>0.80</minimum>
</limit>
```

### CI 통합
```yaml
- uses: codecov/codecov-action@v4
  with:
    fail_ci_if_error: true
    threshold: 80        # 전체 커버리지 80% 미만 시 실패
```

---

## 전체 CI 게이트 순서

```
PR 생성
  ├─ lint / type-check           (실패 → 즉시 차단)
  ├─ unit test + coverage        (80% 미만 → 차단)
  ├─ BDD test                    (실패 → 차단)
  └─ security scan (Trivy)       (HIGH+ → 차단)

PR 승인 후 머지 전
  └─ integration test            (실패 → 차단)

main 머지
  └─ E2E test (dev 환경)         (실패 → staging 차단)

릴리스 전 (수동)
  └─ performance test            (p95 기준 미달 → 배포 검토)
```

---

## 테스트 환경 격리 원칙

| 규칙 | 내용 |
|------|------|
| DB Mock 금지 | 통합 테스트는 실제 DB (Testcontainers) 사용 |
| LLM Mock 필수 | 비용·속도 이유로 외부 LLM은 Mock |
| 외부 API Mock | Scrapin·Twitter·Tavily 등 외부 API는 Mock |
| 테스트 격리 | 각 테스트는 독립적 — 순서 의존성 금지 |

---

## DoD (Definition of Done)

PR이 머지되기 전 반드시 충족해야 하는 기준:

```
[ ] 모든 CI 게이트 통과
[ ] 코드 리뷰 최소 1인 승인
[ ] 비즈니스 스펙의 모든 인수기준 BDD로 검증됨
[ ] 새 기능에 대한 unit test 포함
[ ] CHANGELOG.md 또는 PR 설명에 변경 내용 기록
[ ] 보안 취약점 없음 (HIGH/CRITICAL)
```

---

## 검증 체크리스트

> 이 가이드 기준으로 application을 audit할 때 사용. 각 항목은 yes/no.
> 통합 인덱스: [`specs/_methodology/CHECKLIST.md`](../CHECKLIST.md)

### 카테고리 1: 테스트 피라미드 (G05-01)
- [ ] G05-01-01: Unit 테스트가 전체의 약 70% 비중을 차지하는가? (PR 즉시 실행)
- [ ] G05-01-02: Integration 테스트가 약 20% 비중으로 PR 머지 전에 실행되는가?
- [ ] G05-01-03: Contract(Pact) 테스트가 약 7% 비중으로 PR 머지 전에 실행되는가?
- [ ] G05-01-04: E2E 테스트가 약 3% 비중으로 main 머지 후에 실행되는가?
- [ ] G05-01-05: 통합 테스트는 실제 DB(Testcontainers)를 사용하는가? (DB Mock 금지)
- [ ] G05-01-06: 외부 LLM은 비용·속도 이유로 Mock 처리되는가?
- [ ] G05-01-07: 외부 API(Scrapin·Twitter·Tavily 등)가 Mock 처리되는가?
- [ ] G05-01-08: 각 테스트가 독립적이며 순서 의존성이 없는가?

### 카테고리 2: 커버리지 게이트 (G05-02)
- [ ] G05-02-01: Unit 전체 커버리지가 80% 이상이며 미달 시 PR 차단되는가?
- [ ] G05-02-02: Service 레이어 커버리지가 90% 이상인가?
- [ ] G05-02-03: Python: `pytest --cov=app --cov-fail-under=80 --cov-report=xml` 형태로 게이트가 설정되었는가?
- [ ] G05-02-04: Java: JaCoCo `<minimum>0.80</minimum>` LINE COVEREDRATIO 가 설정되었는가?
- [ ] G05-02-05: codecov-action 에 `fail_ci_if_error: true`, `threshold: 80` 이 설정되었는가?

### 카테고리 3: BDD 게이트 (G05-03)
- [ ] G05-03-01: 모든 비즈니스 스펙의 Gherkin 인수기준이 `.feature` 파일로 존재하는가?
- [ ] G05-03-02: 모든 `.feature` Scenario에 Step 구현이 완료되어 있는가?
- [ ] G05-03-03: BDD 테스트가 PR CI에서 자동 실행되며 실패 시 머지 차단되는가?
- [ ] G05-03-04: 신규 기능 PR에 대응하는 `.feature` 변경이 포함되는가?

### 카테고리 4: DoD (G05-04)
- [ ] G05-04-01: 모든 CI 게이트(lint/type-check, unit+coverage, BDD, security scan)를 통과했는가?
- [ ] G05-04-02: 코드 리뷰 최소 1인 승인이 되었는가?
- [ ] G05-04-03: 비즈니스 스펙의 모든 인수기준이 BDD로 검증되었는가?
- [ ] G05-04-04: 새 기능에 대한 unit test가 포함되었는가?
- [ ] G05-04-05: CHANGELOG.md 또는 PR 설명에 변경 내용이 기록되었는가?
- [ ] G05-04-06: HIGH/CRITICAL 보안 취약점이 없는가?
- [ ] G05-04-07: integration test가 PR 머지 전 통과되었는가?
- [ ] G05-04-08: main 머지 후 dev 환경에서 E2E 테스트가 통과되었는가? (실패 시 staging 차단)

