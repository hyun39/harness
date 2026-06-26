# SP500 Platform Audit Checklist — 통합 인덱스

> 이 문서는 `gov/`(거버넌스)·`std/`(표준)에 분산된 모든 audit 항목을 한 곳에서 보고
> 외부 application을 점수화·진척도 추적하기 위한 단일 인덱스다.
>
> 식별자 체계:
> - **G{NN}-{cat}-{seq}**: gov/`{NN}_*.md` 의 카테고리 cat 번 항목
> - **S{NN}-{cat}-{seq}**: std/`{NN}_*.md` 의 카테고리 cat 번 항목

---

## 점수화 가이드

각 영역은 다음 4단계로 평가한다:

| 단계 | 정의 |
|------|------|
| ✅ Pass | 모든 MUST 항목 충족 |
| 🟡 Partial | MUST 충족, 일부 SHOULD 미충족 |
| 🔴 Fail | MUST 1건 이상 미충족 |
| ⚪ N/A | 해당 영역이 application에 없음 |

총점: 영역별 가중치 적용 (보안·요건·품질 게이트는 ×2, 나머지 ×1)

---

## 영역별 인덱스

### 1. 비즈니스 요건 (G01)
> 상세: [`gov/01_requirements.md`](./gov/01_requirements.md#검증-체크리스트)

- 카테고리 1: 비즈니스 스펙 충실도 (G01-01-NN)
- 카테고리 2: .feature 파일 관리 (G01-02-NN)
- 카테고리 3: 추적성 (G01-03-NN)

### 2. ADR (G02)
> 상세: [`gov/02_adr.md`](./gov/02_adr.md#검증-체크리스트)

- 카테고리 1: ADR 작성 의무 (G02-01-NN)
- 카테고리 2: ADR 형식 준수 (G02-02-NN)
- 카테고리 3: ADR 수명 관리 (G02-03-NN)

### 3. Git 워크플로 (G03)
> 상세: [`gov/03_git_workflow.md`](./gov/03_git_workflow.md#검증-체크리스트)

- 카테고리 1: 브랜치 전략 (G03-01-NN)
- 카테고리 2: 커밋 메시지 (G03-02-NN)
- 카테고리 3: PR 품질 (G03-03-NN)
- 카테고리 4: 버전·릴리스 (G03-04-NN)

### 4. 보안 (G04, ×2)
> 상세: [`gov/04_security.md`](./gov/04_security.md#검증-체크리스트)

- 카테고리 1: Zero Trust 원칙 (G04-01-NN)
- 카테고리 2: 코드 레벨 보안 (G04-02-NN)
- 카테고리 3: Secrets 관리 (G04-03-NN)
- 카테고리 4: 컨테이너 (G04-04-NN)
- 카테고리 5: 의존성·OWASP (G04-05-NN)
- 카테고리 6: 감사 로그·CI 게이트 (G04-06-NN)

### 5. 품질 게이트 (G05, ×2)
> 상세: [`gov/05_quality_gates.md`](./gov/05_quality_gates.md#검증-체크리스트)

- 카테고리 1: 테스트 피라미드 (G05-01-NN)
- 카테고리 2: 커버리지 게이트 (G05-02-NN)
- 카테고리 3: BDD 게이트 (G05-03-NN)
- 카테고리 4: DoD (G05-04-NN)

### 6. API 설계 (G06)
> 상세: [`gov/06_api_design.md`](./gov/06_api_design.md#검증-체크리스트)

- 카테고리 1: URL·메서드 규칙 (G06-01-NN)
- 카테고리 2: 에러 응답 통일 (G06-02-NN)
- 카테고리 3: OpenAPI 스펙 (G06-03-NN)
- 카테고리 4: 버전·하위 호환 (G06-04-NN)

### 7. 데이터 정책 (G07)
> 상세: [`gov/07_data_policy.md`](./gov/07_data_policy.md#검증-체크리스트)

- 카테고리 1: 데이터 분류 (G07-01-NN)
- 카테고리 2: 보존·삭제 (G07-02-NN)
- 카테고리 3: PII·접근 제어 (G07-03-NN)
- 카테고리 4: 마이그레이션 (G07-04-NN)
- 카테고리 5: Data Contract (G07-05-NN)

### 8. AI/LLM 거버넌스 (G08)
> 상세: [`gov/08_ai_governance.md`](./gov/08_ai_governance.md#검증-체크리스트)

- 카테고리 1: 프롬프트 관리 (G08-01-NN)
- 카테고리 2: 모델 응답 검증 (G08-02-NN)
- 카테고리 3: 면책·책임 (G08-03-NN)
- 카테고리 4: PII·민감정보 (G08-04-NN)
- 카테고리 5: 비용 거버넌스 (G08-05-NN)
- 카테고리 6: 모델 변경·평가 (G08-06-NN)
- 카테고리 7: Hallucination 모니터링 (G08-07-NN)

### 9. 관찰성·SRE (G09)
> 상세: [`gov/09_observability.md`](./gov/09_observability.md#검증-체크리스트)

- 카테고리 1: SLI/SLO (G09-01-NN)
- 카테고리 2: Error Budget (G09-02-NN)
- 카테고리 3: 알람·On-Call (G09-03-NN)
- 카테고리 4: Incident Response (G09-04-NN)

### 10. 인프라·배포 (G10)
> 상세: [`gov/10_infra_deploy.md`](./gov/10_infra_deploy.md#검증-체크리스트)

- 카테고리 1: 환경 분리 (G10-01-NN)
- 카테고리 2: IaC (G10-02-NN)
- 카테고리 3: 변경·승인 (G10-03-NN)
- 카테고리 4: 배포 전략 (G10-04-NN)
- 카테고리 5: 동결 윈도우 (G10-05-NN)
- 카테고리 6: 컨테이너·시크릿 (G10-06-NN)
- 카테고리 7: 롤백 (G10-07-NN)

---

## 표준 패턴 적용 (S01~S08)

> 이 영역은 정책이 아닌 "구현이 표준 패턴을 따랐는가" 검증.

| 영역 | std 파일 | 식별자 |
|------|---------|--------|
| Backend (FastAPI/Spring) | [01_backend.md](./std/01_backend.md#패턴-적용-체크리스트) | S01 |
| Frontend (React) | [02_frontend.md](./std/02_frontend.md#패턴-적용-체크리스트) | S02 |
| Database | [03_database.md](./std/03_database.md#패턴-적용-체크리스트) | S03 |
| Auth (Keycloak) | [04_auth.md](./std/04_auth.md#패턴-적용-체크리스트) | S04 |
| Infra (Docker/K8s) | [05_infra.md](./std/05_infra.md#패턴-적용-체크리스트) | S05 |
| Observability (OTel) | [06_observability.md](./std/06_observability.md#패턴-적용-체크리스트) | S06 |
| AI/LLM | [07_ai.md](./std/07_ai.md#패턴-적용-체크리스트) | S07 |
| Data Pipeline | [08_data_pipeline.md](./std/08_data_pipeline.md#패턴-적용-체크리스트) | S08 |

---

## Audit 워크플로

1. **범위 결정** — 대상 application의 영역을 식별 (모든 영역 적용 안 될 수 있음)
2. **항목 평가** — 각 영역의 체크리스트를 yes/no로 평가
3. **점수 산출** — 영역별 단계 부여(✅🟡🔴⚪) + 가중치 적용
4. **gap 리포트** — 미충족 MUST 항목을 우선순위별로 정리
5. **개선 PR** — gap을 해소하는 변경 PR 생성, 다시 평가

---

## 향후 보강

- [ ] **G11 — Disaster Recovery** (RPO/RTO, 백업, DR 테스트)
- [ ] **G12 — Privacy & Compliance** (GDPR, DSAR, K-개인정보)
- [ ] **G13 — Cost / FinOps** (예산 한도, 리소스 태깅)
- [ ] **G14 — Dependency / Supply Chain** (SBOM, license)
