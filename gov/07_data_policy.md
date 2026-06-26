# GOV-07 — 데이터 분류·보존·접근 정책

> **강제 대상**: 데이터를 저장·처리·전송하는 모든 컴포넌트  
> **게이트**: 마이그레이션 PR → DBA·보안 리뷰 필수  
> **원본 참조**: `common/data_governance.md`, `enterprise/05.02_std_data_platform_standards.md`

---

## 데이터 민감도 등급 (MUST)

| 등급 | 정의 | 처리 기준 |
|------|------|---------|
| **L1 공개** | 누구나 접근 가능 | 별도 보호 불필요 |
| **L2 내부** | 내부 직원만 접근 | 접근 제어·암호화 전송 |
| **L3 기밀** | 특정 역할만 접근 | 암호화 저장·접근 로그 필수 |
| **L4 PII** | 최소 권한 | 암호화+마스킹+보존 기간 강제 |

모든 테이블·필드는 등급을 주석 또는 Data Catalog에 명시한다.

---

## 데이터 보존 기간 규칙 (MUST)

| 데이터 유형 | 보존 기간 | 삭제 방식 |
|-----------|---------|---------|
| 프로필 스냅샷 (L3) | 90일 | `expires_at` 배치 삭제 |
| LLM 분석 결과 (L3) | 90일 | `expires_at` 배치 삭제 |
| 검색 이력 (L3) | 1년 | 연간 배치 삭제 |
| 감사 로그 (L2) | 3년 | 콜드 스토리지 아카이빙 |
| OTel 로그 (L2) | 90일 | ILM 자동 삭제 |

---

## PII 처리 필수 규칙 (MUST)

- [ ] 로그에 이름·이메일·LinkedIn URL 평문 출력 금지
- [ ] `raw_data` (외부 API 응답) 전체 로그 출력 금지
- [ ] PII 필드는 응답에서 필요한 것만 반환 (최소화)
- [ ] OTel Collector `redaction` 프로세서로 로그 자동 마스킹

```python
# structlog PII 마스킹 필수
structlog.contextvars.bind_contextvars(
    name="[MASKED]",           # 이름 마스킹
    linkedin_url="[MASKED]",   # URL 마스킹
)
```

---

## 마이그레이션 규칙 (MUST)

| 규칙 | 내용 |
|------|------|
| 파일 네이밍 | `V{N}__{설명}.sql` (Flyway) 또는 Alembic 버전 |
| 컬럼 추가 | NULLABLE로 먼저 추가 → 데이터 채우기 → NOT NULL 제약 |
| 운영 대형 테이블 인덱스 | `CREATE INDEX CONCURRENTLY` 사용 |
| 롤백 | 운영 환경 rollback 금지 — 새 마이그레이션으로 수정 |
| 리뷰 | 대용량 테이블 DDL은 DBA 리뷰 필수 |

---

## 접근 제어 최소 기준 (MUST)

```sql
-- PostgreSQL RLS 활성화 (L4 테이블 필수)
ALTER TABLE profile_snapshot ENABLE ROW LEVEL SECURITY;

-- 역할별 접근 정책 명시
CREATE POLICY analyst_select ON profile_snapshot
    FOR SELECT TO analyst_role USING (true);
```

- 애플리케이션 DB 계정은 읽기·쓰기만 — DDL 권한 금지
- 마이그레이션 전용 계정 분리
- DB 접속 자격증명은 Vault 또는 K8s Secret 관리

---

## Data Contract 규칙 (팀 간 데이터 공유 시)

팀 간 데이터 공유는 반드시 `contracts/` 디렉토리의 YAML 계약으로 정의한다.

```yaml
# contracts/{domain}/{dataset}_v{N}.yaml 필수 항목
id:      "{domain}.{dataset}.v{N}"
status:  active
owner:   { team: "...", slack: "#..." }
schema:  { fields: [...] }
quality: { completeness: ">=98%", freshness: "..." }
sla:     { delivery_time: "...", retention: "..." }
```

계약 없이 타 팀 DB/테이블 직접 접근 금지.

---

## 검증 체크리스트

> 이 가이드 기준으로 application을 audit할 때 사용. 각 항목은 yes/no.
> 통합 인덱스: [`specs/_methodology/CHECKLIST.md`](../CHECKLIST.md)

### 카테고리 1: 데이터 분류 (G07-01)
- [ ] G07-01-01: 모든 테이블·필드에 민감도 등급(L1 공개 / L2 내부 / L3 기밀 / L4 PII)이 주석 또는 Data Catalog 에 명시되어 있는가?
- [ ] G07-01-02: L2 데이터에 접근 제어·암호화 전송이 적용되어 있는가?
- [ ] G07-01-03: L3 데이터에 암호화 저장 및 접근 로그가 기록되는가?
- [ ] G07-01-04: L4(PII) 데이터에 암호화+마스킹+보존 기간이 모두 강제되어 있는가?

### 카테고리 2: 보존·삭제 (G07-02)
- [ ] G07-02-01: 프로필 스냅샷(L3)이 90일 보존, `expires_at` 배치 삭제로 운영되는가?
- [ ] G07-02-02: LLM 분석 결과(L3)가 90일 보존, `expires_at` 배치 삭제로 운영되는가?
- [ ] G07-02-03: 검색 이력(L3)이 1년 보존, 연간 배치 삭제로 운영되는가?
- [ ] G07-02-04: 감사 로그(L2)가 3년 보존, 콜드 스토리지 아카이빙되는가?
- [ ] G07-02-05: OTel 로그(L2)가 90일 보존, ILM 자동 삭제되는가?

### 카테고리 3: PII·접근 제어 (G07-03)
- [ ] G07-03-01: 로그에 이름·이메일·LinkedIn URL 평문 출력이 금지되었는가?
- [ ] G07-03-02: `raw_data`(외부 API 응답) 전체 로그 출력이 금지되었는가?
- [ ] G07-03-03: PII 필드는 응답에서 필요한 것만 반환하는가? (최소화 원칙)
- [ ] G07-03-04: OTel Collector `redaction` 프로세서로 로그 자동 마스킹이 적용되는가?
- [ ] G07-03-05: structlog 등 로깅 컨텍스트에 PII 필드(`name`, `linkedin_url` 등)가 `[MASKED]`로 바인딩되는가?
- [ ] G07-03-06: PostgreSQL RLS 가 L4 테이블에 활성화되어 있는가?
- [ ] G07-03-07: 역할별 접근 정책(예: `analyst_select`)이 명시되어 있는가?
- [ ] G07-03-08: 애플리케이션 DB 계정에 DDL 권한이 없고 읽기·쓰기만 부여되었는가?
- [ ] G07-03-09: 마이그레이션 전용 계정이 분리되어 있는가?
- [ ] G07-03-10: DB 접속 자격증명이 Vault 또는 K8s Secret 으로 관리되는가?

### 카테고리 4: 마이그레이션 (G07-04)
- [ ] G07-04-01: 마이그레이션 파일이 `V{N}__{설명}.sql` (Flyway) 또는 Alembic 버전 네이밍을 따르는가?
- [ ] G07-04-02: 컬럼 추가가 NULLABLE 추가 → 데이터 채우기 → NOT NULL 제약 순으로 진행되는가?
- [ ] G07-04-03: 운영 대형 테이블 인덱스가 `CREATE INDEX CONCURRENTLY` 로 생성되는가?
- [ ] G07-04-04: 운영 환경 rollback 이 금지되어 있고 새 마이그레이션으로 수정되는가?
- [ ] G07-04-05: 대용량 테이블 DDL 마이그레이션 PR이 DBA·보안 리뷰를 통과했는가?

### 카테고리 5: Data Contract (G07-05)
- [ ] G07-05-01: 팀 간 데이터 공유가 `contracts/` YAML 계약으로 정의되어 있는가?
- [ ] G07-05-02: 계약 YAML에 `id`, `status`, `owner`, `schema`, `quality`, `sla` 6 필드가 모두 포함되어 있는가?
- [ ] G07-05-03: 계약 없이 타 팀 DB/테이블에 직접 접근하는 코드가 없는가?
- [ ] G07-05-04: 데이터 품질 기준(예: `completeness >=98%`, `freshness`)이 계약에 명시되어 있는가?
- [ ] G07-05-05: SLA(`delivery_time`, `retention`)이 계약에 명시되어 있는가?
