# STD-08 — 데이터 파이프라인 (Airflow + ODS→DW→MART)

> 전체 상세: [`detail/data_pipeline_airflow.md`](./detail/data_pipeline_airflow.md)

---

## 레이어 구조 요약

```
수집 → Raw(S3) → ODS(PostgreSQL) → DW(fact/dim) → MART(mart_*)
          Airflow 오케스트레이션 + dbt SQL 변환
```

| 레이어 | 테이블 접두사 | dbt 구체화 | 갱신 방식 |
|--------|------------|-----------|---------|
| ODS | `ods_*` | `view` | UPSERT |
| DW | `fact_*`, `dim_*` | `incremental` | Merge |
| MART | `mart_*` | `table` | Replace |

---

## DAG 공통 패턴

```python
from datetime import datetime, timedelta

DEFAULT_ARGS = {
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "execution_timeout": timedelta(hours=2),
}

@dag(
    dag_id="{domain}_{layer}_{action}",   # 네이밍 규칙
    schedule="30 7 * * 1-5",              # 평일 실행
    catchup=False,
    max_active_runs=1,
    tags=["team:data", "domain:market"],
    default_args=DEFAULT_ARGS,
)
def my_dag(): ...
```

---

## ODS UPSERT 패턴 (멱등성)

```python
@task
def load_ods(logical_date=None):
    pg = PostgresHook(postgres_conn_id="app_db")
    pg.run("""
        INSERT INTO ods_stock_price_daily (ticker, trade_date, close_price)
        VALUES (%s, %s, %s)
        ON CONFLICT (ticker, trade_date)
        DO UPDATE SET
            close_price = EXCLUDED.close_price,
            loaded_at = NOW()
    """, parameters=rows)
```

---

## dbt 모델 구조

```
models/
├── staging/      stg_*  ← ODS 원본 정제 (view)
├── intermediate/ int_*  ← 집계 계산 (ephemeral/CTE)
├── dw/           fact_*, dim_*  ← 스타 스키마 (incremental)
└── marts/        mart_* ← 소비자 최종 (table)
```

```sql
-- MART 예시 (전체 재계산)
{{ config(materialized='table', tags=['mart']) }}

SELECT trade_date, sector,
       COUNT(*) AS ticker_count,
       AVG(daily_return_pct) AS avg_return
FROM {{ ref('fact_stock_daily_return') }} f
JOIN {{ ref('dim_date') }} d ON d.date_id = f.date_id
JOIN {{ ref('dim_ticker') }} t ON t.ticker_id = f.ticker_id
GROUP BY trade_date, sector
```

---

## DQ(데이터 품질) 체크 패턴

```python
@task
def dq_check(logical_date=None):
    pg = PostgresHook(postgres_conn_id="app_db")
    count = pg.get_first(
        "SELECT COUNT(DISTINCT ticker) FROM ods_stock_price_daily WHERE trade_date = %s",
        parameters=[logical_date.date()]
    )[0]
    assert count >= 480, f"종목 수 부족: {count}개"
```

---

## BDD 테스트 연결 포인트

```python
# BDD step — 파이프라인 완료 상태 시뮬레이션
@given(parsers.parse("{date} 거래일의 파이프라인이 완료된 상태이고"))
def pipeline_done(date: str, db_session):
    # Testcontainers DB에 직접 적재 (Airflow 실행 없이)
    seed_mart_data(db_session, trade_date=date)
    seed_pipeline_log(db_session, trade_date=date, status="completed")
```

---

## 재처리 원칙

| 원칙 | 내용 |
|------|------|
| 멱등성 | 같은 날짜 재실행 → 동일 결과 (UPSERT/Replace) |
| 파티션 단위 | 날짜 단위로 재처리 |
| DAG 의존성 | 수집 → ODS → DW → MART 순서 강제 (ExternalTaskSensor) |

---

## 패턴 적용 체크리스트

> 이 표준에 정의된 패턴을 실제 코드가 따르는지 audit. 각 항목은 yes/no.
> 식별자(`S08-NN-MM`)는 통합 인덱스(`specs/_methodology/CHECKLIST.md`)에서 참조.

### 카테고리 1: DAG 설계
- [ ] S08-01-01: 모든 DAG가 `@dag/@task` decorator를 사용하는가
- [ ] S08-01-02: catchup=False가 설정됐는가 (의도된 backfill만 별도 처리)
- [ ] S08-01-03: max_active_runs가 명시됐는가
- [ ] S08-01-04: retries·retry_delay·sla가 설정됐는가
- [ ] S08-01-05: DAG 태그(예: `pipeline`, `F-XX-XX`)가 부여됐는가

### 카테고리 2: 레이어 구조
- [ ] S08-02-01: 데이터가 Raw → ODS → DW → Mart 순서로 흐르는가
- [ ] S08-02-02: ODS 테이블이 `ods_*` prefix인가
- [ ] S08-02-03: DW 테이블이 `fact_*`, `dim_*` prefix인가
- [ ] S08-02-04: Mart 테이블이 `mart_*` prefix인가
- [ ] S08-02-05: 레이어 간 의존이 ExternalTaskSensor 또는 TriggerDagRunOperator로 표현되는가

### 카테고리 3: 데이터 신뢰성
- [ ] S08-03-01: ODS upsert가 멱등성을 보장하는가
- [ ] S08-03-02: 비거래일 자동 skip이 구현됐는가
- [ ] S08-03-03: 수집 coverage 게이트(예: 98% 이상)가 있는가
- [ ] S08-03-04: 품질 검증 task가 chain에 포함되는가
- [ ] S08-03-05: 실패 시 알림(Slack 등)이 발송되는가

### 카테고리 4: XCom·재현성
- [ ] S08-04-01: task 간 trade_date 등 식별자가 XCom으로 전파되는가
- [ ] S08-04-02: DAG가 동일 입력에 대해 동일 결과를 보장하는가
- [ ] S08-04-03: 도메인 로직이 task 외부 모듈(pipeline/*)로 분리되어 단위 테스트 가능한가

### 카테고리 5: 운영
- [ ] S08-05-01: DAG 구조 smoke test(ast 기반)가 CI에 있는가
- [ ] S08-05-02: DAG run 성공률이 모니터링되는가 (gov/09 연계)
