# STD-03 — 데이터베이스 구현 표준

> 전체 상세: [`detail/database.md`](./detail/database.md)

---

## 컬럼 타입 선택 기준

| 데이터 | 타입 | 이유 |
|--------|------|------|
| URL, 긴 텍스트 | `TEXT` | 길이 예측 불가 |
| 고정 코드 값 | `VARCHAR(N)` + `CHECK` | ENUM보다 값 추가 용이 |
| 외부 API 응답 | `JSONB` | 스키마 유동성 |
| 배열 (facts, ice_breakers) | `JSONB` | 검색 불필요 시 |
| 금액 | `NUMERIC(p,s)` | FLOAT 부동소수점 오류 방지 |
| 타임스탬프 | `TIMESTAMP WITH TIME ZONE` | 타임존 보존 |

---

## PK 전략

```sql
-- 내부 조인용: BIGSERIAL (성능)
id BIGSERIAL PRIMARY KEY

-- 외부 노출용: UUID v4 별도 컬럼
external_id UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE
```

---

## 인덱스 패턴

```sql
-- 단순 조회
CREATE INDEX idx_{table}_{col} ON {table} ({col});

-- 복합: 선택도 높은 컬럼을 앞에
CREATE INDEX idx_snapshot_person_source ON profile_snapshot (person_id, source);

-- Partial: 조건 고정일 때
CREATE INDEX idx_active ON profile_snapshot (expires_at)
    WHERE expires_at IS NOT NULL;

-- 운영 중 인덱스 추가
CREATE INDEX CONCURRENTLY idx_new ON table (col);  -- 락 없이
```

---

## 마이그레이션 필수 패턴

```sql
-- NOT NULL 컬럼 추가 (3단계 무중단)
-- 1단계
ALTER TABLE t ADD COLUMN new_col TEXT;
-- 2단계 (데이터 채우기)
UPDATE t SET new_col = 'default' WHERE new_col IS NULL;
-- 3단계
ALTER TABLE t ALTER COLUMN new_col SET NOT NULL;
```

```python
# Alembic revision
def upgrade():
    op.add_column("t", sa.Column("new_col", sa.TEXT, nullable=True))
    op.execute("UPDATE t SET new_col = 'default' WHERE new_col IS NULL")
    op.alter_column("t", "new_col", nullable=False)

def downgrade():
    op.drop_column("t", "new_col")
```

---

## BDD 테스트 연결 포인트

```python
# conftest.py — Testcontainers로 실제 DB
@pytest.fixture(scope="session")
def postgres():
    with PostgresContainer("postgres:15") as pg:
        # 마이그레이션 적용
        alembic_upgrade(pg.get_connection_url(), "head")
        yield pg

# Given step에서 DB 직접 적재
@given("분석 결과가 저장되어 있다")
def seed_analysis(db_session):
    db_session.add(AnalysisResult(person_id=1, summary="test"))
    db_session.flush()
```

---

## 참조 무결성 요약

| 관계 | ON DELETE | 언제 |
|------|-----------|------|
| 부모 삭제 시 자식 무의미 | `CASCADE` | profile_snapshot → person |
| 자식 존재 시 부모 삭제 차단 | `RESTRICT` | analysis_result → snapshot |
| 자식은 독립적으로 유효 | `SET NULL` | search_history → analysis_result |

---

## 패턴 적용 체크리스트

> 이 표준에 정의된 패턴을 실제 코드가 따르는지 audit. 각 항목은 yes/no.
> 식별자(`S03-NN-MM`)는 통합 인덱스(`specs/_methodology/CHECKLIST.md`)에서 참조.

### 카테고리 1: 컬럼 타입
- [ ] S03-01-01: URL·긴 텍스트가 TEXT인가 (VARCHAR 임의 길이 금지)
- [ ] S03-01-02: 외부 API 응답이 JSONB인가
- [ ] S03-01-03: 금액이 NUMERIC(p,s)인가 (FLOAT 금지)
- [ ] S03-01-04: 타임스탬프가 TIMESTAMP WITH TIME ZONE인가
- [ ] S03-01-05: 코드 값이 VARCHAR + CHECK constraint 방식인가 (ENUM 변경 비용 회피)

### 카테고리 2: PK·인덱스
- [ ] S03-02-01: 내부 조인 PK가 BIGSERIAL인가
- [ ] S03-02-02: 외부 노출 ID가 UUID 또는 별도 식별자인가
- [ ] S03-02-03: 자주 조회되는 외래 키에 인덱스가 있는가
- [ ] S03-02-04: 복합 인덱스 컬럼 순서가 cardinality 기준인가

### 카테고리 3: 마이그레이션
- [ ] S03-03-01: alembic 또는 Flyway 등 도구로 버전 관리되는가
- [ ] S03-03-02: 컬럼 추가가 NULLABLE→backfill→NOT NULL 단계인가 (gov/07 연계)
- [ ] S03-03-03: 운영 대형 테이블 인덱스가 CONCURRENTLY 적용되는가
- [ ] S03-03-04: 운영 환경 rollback 대신 forward-fix 정책이 적용되는가

### 카테고리 4: 운영
- [ ] S03-04-01: 애플리케이션 DB 계정에 DDL 권한이 없는가
- [ ] S03-04-02: 마이그레이션 전용 계정이 분리됐는가
- [ ] S03-04-03: L4(PII) 테이블에 RLS가 활성화됐는가 (gov/07 연계)
