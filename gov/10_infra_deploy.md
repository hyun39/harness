# GOV-10 — 인프라·배포 거버넌스

> **강제 대상**: 모든 인프라 변경 및 운영 환경 배포
> **게이트**: PR 리뷰 + 변경 승인 + 자동 rollback 트리거
> **원본 참조**: `enterprise/04.01_gov_infra_deployment.md`, `common/deployment_strategy.md`
> **연계 규칙**: GOV-04(보안), GOV-07(데이터), GOV-09(SLO)

---

## 환경 분리 원칙 (MUST)

| 환경 | 용도 | 격리 수준 | 데이터 |
|------|------|----------|--------|
| `dev` | 개발자 로컬·통합 | Compose / 단일 K8s namespace | Mock·Seed 데이터만 |
| `staging` | 출시 전 검증 | 별도 namespace, prod 동일 토폴로지 | 익명화된 prod 스냅샷 |
| `production` | 실서비스 | **별도 K8s 클러스터 또는 격리 namespace** | 실데이터 |

- 각 환경의 secrets·DB credential·외부 API key는 **완전히 분리**되어야 한다.
- dev·staging에서 production DB 접근은 **금지** — 어떤 우회도 불가.
- 환경 식별자는 모든 서비스에 `ENVIRONMENT={dev|staging|production}` 환경변수로 주입.
- production 트래픽은 staging을 거친 이미지만 받을 수 있다.

---

## IaC (Infrastructure as Code) 정책 (MUST)

- 모든 인프라 변경은 git에 추적되며 **수동 콘솔 변경은 금지**한다.
- Docker Compose 파일은 `infra/compose/<service>.yml` — 서비스 단일 책임 원칙.
- 루트 `docker-compose.yml`은 `include` 디렉티브로만 결합 (서비스 정의 직접 작성 금지).
- K8s manifest는 `infra/k8s/{base,overlays}/` (kustomize 패턴) — 환경별 차이는 `overlays/{env}/`에서만.
- Terraform/Pulumi 등 state 파일은 **원격 저장소(S3·GCS) + state lock 활성화** 필수.
- 모든 IaC 변경은 PR을 통해야 하며 `infra/*` 경로는 SRE 팀 CODEOWNERS 자동 지정.
- 구현 표준(Dockerfile·K8s 코드 패턴)은 `std/05_infra.md` 참조 — 본 문서는 정책만 다룬다.

---

## 변경 승인 프로세스 (MUST)

| 변경 종류 | 필수 승인자 | 사전 절차 |
|----------|------------|----------|
| dev compose 파일 수정 | 리뷰어 1인 | — |
| staging manifest 변경 | SRE 1인 + 서비스 오너 | PR + CI 통과 |
| production manifest 변경 | SRE 2인 + 서비스 오너 | PR + 변경 윈도우 사전 공지 (24시간) |
| DB 스키마 변경 (prod) | SRE + DBA + 서비스 오너 | GOV-07 마이그레이션 절차 |
| 신규 외부 의존 추가 | SRE + 보안 담당 | GOV-04 보안 검토 |
| 시크릿 회전 | SRE 1인 | 회전 일정 ChangeLog 기록 |
| 긴급 hotfix | SRE 1인 (사후 2인 승인) | 사후 24시간 내 RCA |

production 변경은 변경 윈도우 외 시간 적용을 금지하며, Slack `#deploy-prod` 사전 공지를 의무화한다.

---

## 배포 전략 (MUST)

- **Canary 배포 권장**: `5% → 25% → 100%` 단계별 트래픽 전환.
  - 각 단계 최소 관찰 시간 10분, 자동 메트릭 수집 후 진행.
- **자동 rollback 트리거**:
  - 에러율 > 1% (5분 이동 평균)
  - latency p95 직전 안정 버전 대비 +30% 이상
  - 헬스체크 실패율 > 5%
- **DB 마이그레이션 무중단 패턴** (GOV-07 연계):
  1. NULLABLE 컬럼 추가 + 기본값 없이 배포
  2. 이중 쓰기 + backfill
  3. 신·구 코드 모두 동작 확인
  4. NOT NULL 제약·인덱스 추가
  5. 구 컬럼 제거 (필요 시)
- DROP·RENAME 등 파괴적 변경은 **최소 1회 릴리스 간격** 후 진행.

---

## Feature Flag 정책 (SHOULD)

- 점진적 활성화 및 즉시 차단(kill switch)이 가능해야 한다.
- 30일 이상 활성 상태로 남은 flag는 **정리 의무** — 분기별 리뷰에서 제거 또는 유지 사유 기록.
- 명명 규칙:

```
feature_*       신기능 점진 출시        예: feature_rag_v2_enable
kill_*          긴급 차단 스위치         예: kill_external_llm_calls
experiment_*    A/B 테스트              예: experiment_ranker_variant_b
```

- 모든 flag는 등록 시 owner·만료 예정일·해제 조건을 메타데이터에 명시.
- 운영 환경의 flag 변경도 git PR을 통해 audit trail을 남긴다 (수동 콘솔 토글 금지).

---

## 배포 동결 윈도우 (MUST)

다음 기간에는 **production 배포를 금지**한다 (긴급 hotfix 제외):

| 기간 | 사유 |
|------|------|
| 금요일 14:00 이후 ~ 월요일 오전 | 주말 장애 대응 인력 부족 |
| 공휴일 전일 14:00 ~ 공휴일 다음 영업일 | 휴일 대응 어려움 |
| 분기 마감 D-3 ~ D+1 | 회계·리포팅 안정성 |
| Error Budget 소진 시 (GOV-09 연계) | 신뢰성 회복 우선 |
| 외부 의존 서비스 점검 윈도우와 중복 | 진단 어려움 회피 |

긴급 hotfix는 SRE 온콜 승인 후 진행하며, 사후 RCA를 24시간 내 작성한다.

---

## 롤백 정책 (MUST)

- **RTO**: production 장애 감지 후 **15분 내 롤백 완료**가 목표.
- 롤백 절차는 서비스별 runbook에 문서화되어 있어야 하며 분기별 dry-run으로 검증.
- 직전 안정 이미지 태그는 항상 `:last-stable`로 유지하여 즉시 재배포 가능해야 한다.
- DB 스키마 변경 후 장애 발생 시 **forward-fix 우선** — schema rollback은 최후 수단.
  - 무중단 마이그레이션 패턴을 따랐다면 신·구 코드 모두 동작하므로 코드만 롤백 가능.
- 롤백 직후 incident ticket 생성 및 GOV-09 SLO 영향도 기록.

---

## 컨테이너 이미지 정책 (MUST)

- 이미지 태깅 규칙: `{service}:{semver}-{git-sha}` (예: `api:2.1.3-a1b2c3d`).
- `:latest` 태그는 dev 환경에서만 허용 — staging·production은 immutable tag 필수.
- 레지스트리는 사내 private registry 또는 GHCR로 한정, public registry 직접 pull 금지.
- 모든 이미지는 push 시점에 **Trivy 스캔**(GOV-04 연계) — HIGH/CRITICAL 발견 시 차단.
- Base image는 distroless 또는 alpine-slim 권장, root 사용자 실행 금지.
- 이미지 SBOM(Software Bill of Materials)을 빌드 산출물에 포함 (cyclonedx 형식).

---

## 시크릿 관리 (MUST)

- production 시크릿은 **Vault 또는 K8s Secret(External Secrets Operator)** 으로 관리.
- 평문 시크릿의 git 커밋은 절대 금지 — `gitleaks` 사전 스캔(GOV-04).
- GitHub Secrets는 **CI/CD 파이프라인 전용**으로만 사용, 런타임 시크릿 보관 금지.
- 정기 회전 주기:
  - DB credential: 90일
  - 외부 API key: 180일 (제공자가 더 짧게 권장 시 그에 따름)
  - JWT 서명키: 365일 (compromise 의심 시 즉시)
- 회전 작업은 ChangeLog와 audit log에 기록한다.

---

## 금지 사항 (MUST NOT)

| 금지 행위 | 이유 |
|----------|------|
| production 환경 직접 SSH로 변경 | audit trail 부재, 재현 불가 |
| dev 코드에서 production DB 접근 | 데이터 유출·오염 위험 |
| 수동 K8s `kubectl apply` (운영 환경) | IaC 원칙 위배 |
| 동결 윈도우 중 일반 배포 | 장애 대응 리스크 |
| `:latest` 태그로 production 배포 | 재현·롤백 불가 |
| 시크릿을 환경변수로 평문 노출(로그 포함) | 유출 위험 |
| state 파일 로컬 보관 | 동시 변경 충돌·유실 |
| Feature flag 무기한 방치 | 코드 복잡도·dead code 누적 |

---

## 추적성

- 모든 인프라 변경은 `CHANGELOG-INFRA.md`에 날짜·작성자·PR 링크와 함께 기록한다.
- 운영 환경 자원은 CMDB(또는 `infra/inventory.yml`)와 1:1 매핑되어야 하며, drift 감지 시 분기별 reconciliation을 수행한다.
- 배포 이벤트는 OpenTelemetry deployment marker로 기록되어 GOV-09 SLO 대시보드와 연계된다.
- incident 발생 시 변경 이력을 5분 단위로 추적 가능해야 한다 (deploy + flag + config 통합 타임라인).

---

## 검증 체크리스트

> 이 가이드 기준으로 application을 audit할 때 사용. 각 항목은 yes/no로 평가.
> 식별자(`G10-NN-MM`)는 통합 인덱스(`specs/_methodology/CHECKLIST.md`)에서 참조.

### 카테고리 1: 환경 분리
- [ ] G10-01-01: dev / staging / production이 각각 분리된 namespace 또는 cluster인가
- [ ] G10-01-02: 각 환경별 secrets·DB·외부 API 키가 완전히 분리됐는가
- [ ] G10-01-03: dev 환경에서 production DB·secrets 접근이 차단됐는가
- [ ] G10-01-04: 환경별 설정이 IaC로 추적되는가 (수동 콘솔 변경 흔적이 없는가)

### 카테고리 2: IaC
- [ ] G10-02-01: 모든 인프라 변경이 git에 추적되는가
- [ ] G10-02-02: Docker Compose 파일이 단일 책임 분리(`infra/compose/<service>.yml`) 패턴을 따르는가
- [ ] G10-02-03: K8s manifest가 base + overlays(kustomize 또는 helm) 패턴을 따르는가
- [ ] G10-02-04: terraform.tfstate 등 state 파일이 원격 저장소 + lock 활성화 상태인가

### 카테고리 3: 변경·승인
- [ ] G10-03-01: 운영 환경 변경이 SRE 또는 인프라 팀 승인을 거치는가
- [ ] G10-03-02: 변경 윈도우가 사전 공지되는가
- [ ] G10-03-03: 변경 후 모니터링 검증 절차가 있는가

### 카테고리 4: 배포 전략
- [ ] G10-04-01: Canary 또는 Blue-Green 등 점진 배포가 적용되는가
- [ ] G10-04-02: 자동 rollback 트리거(에러율·latency 임계 초과)가 설정됐는가
- [ ] G10-04-03: DB 마이그레이션 무중단 패턴(NULLABLE → backfill → NOT NULL)이 적용되는가
- [ ] G10-04-04: Feature flag로 점진 활성화 가능한가
- [ ] G10-04-05: 30일 이상된 stale flag가 정리됐는가

### 카테고리 5: 동결 윈도우
- [ ] G10-05-01: 금요일 오후·휴일·분기말에 배포 동결 정책이 있는가
- [ ] G10-05-02: Error Budget 소진 시 feature 배포가 자동 동결되는가 (gov/09 연계)

### 카테고리 6: 컨테이너·시크릿
- [ ] G10-06-01: 이미지 태깅이 `{service}:{semver}-{git-sha}` 규칙인가
- [ ] G10-06-02: 이미지가 신뢰 가능한 레지스트리에서 pull되는가
- [ ] G10-06-03: 이미지 scan(Trivy 등)이 통과한 이미지만 배포되는가 (gov/04 연계)
- [ ] G10-06-04: 시크릿이 Vault 또는 K8s Secret에 저장됐는가
- [ ] G10-06-05: 시크릿이 정기 회전되는가

### 카테고리 7: 롤백
- [ ] G10-07-01: 롤백 RTO가 정의되고 측정되는가
- [ ] G10-07-02: 롤백 절차가 문서화·테스트됐는가
- [ ] G10-07-03: DB 스키마 변경 시 forward-fix 우선 정책이 명시됐는가
