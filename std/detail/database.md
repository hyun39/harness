# Common Spec — Database

---

## 정규화 수준 기준

| 수준 | 조건 | 이탈 허용 조건 |
|------|------|--------------|
| 1NF | 원자값, 중복 컬럼 없음 | — |
| 2NF | 부분 함수 종속 제거 | — |
| 3NF | 이행 함수 종속 제거 | — |
| 의도적 비정규화 | — | 외부 API 응답처럼 스키마가 유동적인 경우, 집계 쿼리 성능 요건 |

비정규화 시 반드시 주석으로 이유 명시.

---

## 기본 키(PK) 설계

| 방식 | 장점 | 단점 | 권장 상황 |
|------|------|------|----------|
| `BIGSERIAL` (순번) | 인덱스 효율 높음, 정렬 자연스러움 | 외부 노출 시 순번 유추 가능 | 내부 조인 전용 키 |
| `UUID v4` | 외부 노출 안전, 분산 생성 가능 | 인덱스 단편화, 크기 16byte | 외부 API 응답에 포함되는 ID |
| `UUID v7` | 시간 정렬 가능 UUID | DB 지원 여부 확인 필요 | 정렬 필요한 UUID |

BIGSERIAL PK + UUID 별도 컬럼 조합 권장 (내부 조인은 BIGSERIAL, 외부 노출은 UUID).

---

## 컬럼 타입 선택 기준

| 데이터 | 타입 | 근거 |
|--------|------|------|
| 고정 길이 코드 (`'linkedin'`) | `VARCHAR(N)` + CHECK | ENUM보다 값 추가 용이 |
| 가변 길이 문자열 (URL, 긴 텍스트) | `TEXT` | VARCHAR 길이 제한 불필요 |
| 구조화된 외부 API 응답 | `JSONB` (PG) / `JSON` (MySQL) | 스키마 유동성, GIN 인덱스 가능 |
| 배열 데이터 (facts, ice_breakers) | `JSONB` 배열 또는 별도 자식 테이블 | 검색 필요 없으면 JSONB, 쿼리 필요하면 자식 테이블 |
| 금액 | `NUMERIC(precision, scale)` | FLOAT 부동소수점 오류 방지 |
| 타임스탬프 | `TIMESTAMP WITH TIME ZONE` | 타임존 정보 보존 |
| 불리언 플래그 | `BOOLEAN` | 1/0 정수 사용 금지 |

---

## 참조 무결성 정책

| ON DELETE | 사용 조건 |
|-----------|----------|
| `CASCADE` | 부모 삭제 시 자식이 독립적 의미 없을 때 |
| `RESTRICT` | 자식 존재 시 부모 삭제 차단 — 삭제 순서 강제 |
| `SET NULL` | 자식이 부모 없이도 의미 있을 때 (이력 테이블 등) |
| `NO ACTION` | 기본값 — RESTRICT와 동일하나 트랜잭션 끝에 검사 |

FK 없는 논리적 관계는 명시적 주석으로 문서화 (`-- logical FK: table.col`).

---

## 인덱스 설계 패턴

### B-Tree (기본)
```sql
-- 단일 컬럼
CREATE INDEX idx_person_normalized_name ON person (normalized_name);

-- 복합 컬럼 — 선택도 높은 컬럼을 앞에
CREATE INDEX idx_snapshot_person_source ON profile_snapshot (person_id, source);

-- 내림차순 정렬 조회
CREATE INDEX idx_history_searched_at ON search_history (searched_at DESC);
```

### Partial Index — 조건 필터가 고정인 경우
```sql
-- NULL이 아닌 행만 인덱싱 → 크기 절감
CREATE INDEX idx_snapshot_expires ON profile_snapshot (expires_at)
    WHERE expires_at IS NOT NULL;

-- 활성 상태만 인덱싱
CREATE INDEX idx_active_users ON users (email)
    WHERE deleted_at IS NULL;
```

### GIN Index — JSONB 검색
```sql
-- raw_data 내 특정 키 검색 시
CREATE INDEX idx_snapshot_raw_data ON profile_snapshot USING GIN (raw_data);
-- 사용: WHERE raw_data @> '{"key": "value"}'
```

### 인덱스 추가 전 체크리스트
- [ ] 해당 컬럼으로 실제 `WHERE` / `JOIN` / `ORDER BY` 쿼리가 존재하는가
- [ ] 테이블 쓰기 빈도가 높지 않은가 (인덱스는 쓰기 비용 증가)
- [ ] `EXPLAIN ANALYZE`로 Index Scan 확인

---

## TTL / 만료 데이터 관리

| 방식 | 장점 | 단점 |
|------|------|------|
| `expires_at` 컬럼 + 배치 DELETE | 구현 단순, 유연 | 삭제 전까지 행 존재 |
| 파티셔닝 + 파티션 DROP | 대용량 고속 삭제 | 설정 복잡 |
| Soft Delete (`deleted_at`) | 복구 가능 | 쿼리 조건 누락 위험 |

```sql
-- 만료 확인 쿼리 패턴
WHERE expires_at IS NULL OR expires_at > NOW()

-- 만료 배치 삭제 (분할 삭제 권장)
DELETE FROM profile_snapshot
WHERE expires_at < NOW() - INTERVAL '1 day'
  AND id IN (SELECT id FROM profile_snapshot
             WHERE expires_at < NOW() - INTERVAL '1 day'
             LIMIT 1000);
```

---

## 파티셔닝

| 종류 | 기준 컬럼 | 적합한 테이블 |
|------|----------|-------------|
| RANGE | `created_at`, `searched_at` (월별) | 이력·로그성 append-only 테이블 |
| LIST | `source` (`'linkedin'`, `'twitter'`) | 소수의 고정 분류 값 |
| HASH | PK | 균등 분산이 필요한 대용량 테이블 |

```sql
-- RANGE 파티셔닝 예시 (월별)
CREATE TABLE search_history (
    ...
    searched_at TIMESTAMP NOT NULL
) PARTITION BY RANGE (searched_at);

CREATE TABLE search_history_2026_05
    PARTITION OF search_history
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
```

---

## 마이그레이션 전략

| 원칙 | 내용 |
|------|------|
| 무중단 원칙 | 컬럼 추가는 NULLABLE로 먼저, 이후 NOT NULL로 전환 |
| 롤백 가능 설계 | 각 마이그레이션은 up + down 쌍으로 작성 |
| 대용량 테이블 변경 | `ADD COLUMN` 즉시 가능, `ADD INDEX CONCURRENTLY` 사용 |
| 네이밍 | `V{버전}__{설명}.sql` (Flyway 규칙) |

```sql
-- 안전한 컬럼 추가 순서
-- 1단계: NULLABLE로 추가
ALTER TABLE person ADD COLUMN department VARCHAR(100);
-- 2단계: 데이터 채우기
UPDATE person SET department = 'unknown' WHERE department IS NULL;
-- 3단계: NOT NULL 제약 추가
ALTER TABLE person ALTER COLUMN department SET NOT NULL;
```

---

## 트랜잭션 격리 수준

| 수준 | Dirty Read | Non-Repeatable Read | Phantom Read | 권장 상황 |
|------|-----------|---------------------|-------------|----------|
| READ COMMITTED (PG 기본) | 방지 | 발생 | 발생 | 대부분의 CRUD |
| REPEATABLE READ | 방지 | 방지 | 발생 | 집계·보고 쿼리 |
| SERIALIZABLE | 방지 | 방지 | 방지 | 금융 트랜잭션 |

---

## 커넥션 풀 설정 기준

```
max_connections (DB) = core 수 × 2 + 유효 스핀들 수  (경험치)
pool_size (앱)       = max_connections / 앱 인스턴스 수

예: DB max 100, 앱 2대 → pool_size = 40 (여유 20 확보)
```

| 파라미터 | 권장값 |
|---------|--------|
| `pool_size` | 10~20 |
| `max_overflow` | 5~10 |
| `pool_timeout` | 30s |
| `pool_recycle` | 1800s (커넥션 누수 방지) |

---

## 미결 기술 과제

- [ ] `TIMESTAMP` vs `TIMESTAMP WITH TIME ZONE` 통일 기준 수립
- [ ] JSONB 배열 vs 자식 테이블 선택 기준 문서화
- [ ] 대용량 테이블 `VACUUM`/`ANALYZE` 스케줄 정의
- [ ] 읽기 전용 레플리카 분리 기준 (쓰기:읽기 비율 임계값)
