# Common Spec — 데이터 파이프라인 (수집 → ODS → DW → MART / Airflow)

> 연관 Enterprise 스펙: `enterprise/05.02_std_data_platform_standards.md`  
> 이 파일은 개별 서비스 수준의 **구현 기술 기준**을 정의한다.  
> 조직 수준 Data Mesh·Data Contract·Data Catalog 정책은 enterprise 스펙을 참조한다.

---

## 전체 파이프라인 구조

```
[수집 (Ingestion)]
    외부 API / DB / 파일 / 스트림
        │  원본 그대로 보존
        ▼
[Raw Zone]  S3 / GCS / 로컬 Parquet      ← 불변 원본 저장
        │  정제·타입 변환
        ▼
[ODS]  PostgreSQL ods_* 테이블           ← 정규화된 원본 (1:1 대응)
        │  비즈니스 집계·계산
        ▼
[DW]   PostgreSQL fact_* / dim_* 테이블  ← 스타 스키마
        │  도메인 특화 요약
        ▼
[MART] PostgreSQL mart_* 테이블          ← 소비자(BI·API·AI) 최종 데이터

Airflow가 각 레이어 간 이동을 오케스트레이션
dbt가 ODS → DW → MART SQL 변환 담당
```

---

## 레이어별 정의

| 레이어 | 테이블 접두사 | 특성 | 갱신 방식 |
|--------|------------|------|----------|
| Raw | 파일 (Parquet/JSON) | 원본 불변 보존 | Append-only |
| ODS | `ods_` | 원천과 1:1, 최소 변환 | UPSERT (upsert_key 기준) |
| DW | `fact_`, `dim_` | 스타 스키마, 집계 | Insert (날짜 파티션) |
| MART | `mart_` | 도메인 특화, 역정규화 | Replace (전체 재계산) |

---

## Airflow 환경 구성

### Executor 선택

| Executor | 적합한 환경 | 특징 |
|----------|-----------|------|
| `KubernetesExecutor` | K8s 운영 환경 (권장) | Task별 Pod 격리, 리소스 유연 |
| `LocalExecutor` | 단일 서버 / 개발 | 설정 단순, 병렬 제한 |
| `CeleryExecutor` | 멀티 노드 VM | Redis·RabbitMQ 브로커 필요 |

```yaml
# airflow/values-prod.yaml (Helm)
executor: KubernetesExecutor
config:
  core:
    max_active_tasks_per_dag: 16
    max_active_runs_per_dag: 1
  kubernetes_executor:
    namespace: airflow-prod
    delete_worker_pods: true
    delete_worker_pods_on_failure: false   # 실패 Pod 디버깅 보존
  logging:
    remote_logging: true
    remote_base_log_folder: "s3://airflow-logs/"
```

### DAG 공통 기본값

```python
# apps/airflow/dags/_defaults.py
from datetime import datetime, timedelta

DAG_DEFAULT_ARGS = {
    "owner":            "data-team",
    "retries":          3,
    "retry_delay":      timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "max_retry_delay":  timedelta(minutes=60),
    "email_on_failure": True,
    "email":            ["data-alerts@example.com"],
    "execution_timeout": timedelta(hours=2),
}
```

---

## 레이어 1 — 수집 (Ingestion)

### 역할

외부 소스에서 원본 데이터를 **변환 없이** Raw Zone에 저장.  
실패 시 재처리가 가능하도록 **멱등성**을 보장한다.

### DAG 패턴

```python
# apps/airflow/dags/ingest_raw_stock_price.py
from airflow.decorators import dag, task
from airflow.providers.http.hooks.http import HttpHook
from datetime import datetime
import json, boto3

@dag(
    dag_id="ingest_raw_stock_price",
    schedule="30 7 * * 1-5",          # 미국 장마감 후 평일 실행
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=["ingestion", "market-data"],
    default_args=DAG_DEFAULT_ARGS,
)
def ingest_dag():

    @task
    def check_trading_day(logical_date=None) -> bool:
        """비거래일이면 skip"""
        import exchange_calendars as xcals
        cal = xcals.get_calendar("XNYS")
        return cal.is_session(logical_date.strftime("%Y-%m-%d"))

    @task
    def fetch_raw(logical_date=None) -> str:
        """외부 API에서 원본 데이터 수집"""
        hook = HttpHook(http_conn_id="market_data_api", method="GET")
        response = hook.run(
            endpoint=f"/prices?date={logical_date.strftime('%Y-%m-%d')}"
        )
        return response.text                   # 원본 그대로 반환

    @task
    def save_to_raw_zone(raw_data: str, logical_date=None):
        """S3에 날짜 파티션으로 Append-only 저장"""
        s3 = boto3.client("s3")
        key = f"raw/stock_price/dt={logical_date.strftime('%Y-%m-%d')}/data.json"
        s3.put_object(
            Bucket="data-lake-raw",
            Key=key,
            Body=raw_data.encode(),
        )

    is_trading = check_trading_day()
    raw = fetch_raw()
    save_to_raw_zone(raw)

    is_trading >> raw

ingest_dag()
```

### 수집 원칙

| 원칙 | 내용 |
|------|------|
| 원본 불변 | Raw Zone에는 변환 없이 저장 — 재처리 기반 |
| 날짜 파티셔닝 | `dt=YYYY-MM-DD` 파티션 키 — 재처리 단위 |
| 멱등성 | 같은 날짜 재실행 시 동일 결과 (overwrite) |
| 포맷 | Parquet (대용량) 또는 JSON (소용량) |

---

## 레이어 2 — ODS (Operational Data Store)

### 역할

Raw 데이터를 **정제·타입 변환**하여 관계형 DB에 적재.  
원천과 1:1 구조 유지 — 비즈니스 계산 금지.

### 테이블 설계 기준

```sql
-- ODS 테이블 공통 컬럼 패턴
CREATE TABLE ods_stock_price_daily (
    -- 비즈니스 키
    ticker          TEXT        NOT NULL,
    trade_date      DATE        NOT NULL,
    -- 데이터
    open_price      NUMERIC(12,4),
    high_price      NUMERIC(12,4),
    low_price       NUMERIC(12,4),
    close_price     NUMERIC(12,4) NOT NULL,
    volume          BIGINT,
    -- 파이프라인 메타
    source_system   TEXT        NOT NULL DEFAULT 'market_api',
    raw_file_path   TEXT,                          -- Raw Zone 역추적
    loaded_at       TIMESTAMP   NOT NULL DEFAULT NOW(),
    is_valid        BOOLEAN     NOT NULL DEFAULT TRUE,

    PRIMARY KEY (ticker, trade_date)
);

CREATE INDEX idx_ods_stock_trade_date ON ods_stock_price_daily (trade_date DESC);
```

### dbt staging 모델

```sql
-- dbt/models/staging/stg_stock_price_daily.sql
{{
    config(
        materialized='view',
        tags=['staging', 'market-data']
    )
}}

SELECT
    ticker::TEXT                            AS ticker,
    trade_date::DATE                        AS trade_date,
    NULLIF(open_price, 0)::NUMERIC(12,4)    AS open_price,
    NULLIF(close_price, 0)::NUMERIC(12,4)   AS close_price,
    volume::BIGINT                          AS volume,
    _loaded_at                              AS loaded_at
FROM {{ source('raw', 'ods_stock_price_daily') }}
WHERE close_price IS NOT NULL              -- 기본 품질 필터
```

### ODS 적재 DAG

```python
@dag(
    dag_id="load_raw_to_ods",
    schedule="45 7 * * 1-5",
    tags=["ods", "market-data"],
    default_args=DAG_DEFAULT_ARGS,
)
def ods_dag():

    @task
    def load_ods(logical_date=None):
        """Raw JSON → ODS UPSERT"""
        from airflow.providers.postgres.hooks.postgres import PostgresHook
        import json, boto3

        s3 = boto3.client("s3")
        key = f"raw/stock_price/dt={logical_date.strftime('%Y-%m-%d')}/data.json"
        raw = json.loads(s3.get_object(Bucket="data-lake-raw", Key=key)["Body"].read())

        pg = PostgresHook(postgres_conn_id="app_db")
        # UPSERT — 재실행 멱등성 보장
        pg.run("""
            INSERT INTO ods_stock_price_daily
                (ticker, trade_date, close_price, volume, raw_file_path)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (ticker, trade_date)
            DO UPDATE SET
                close_price = EXCLUDED.close_price,
                volume = EXCLUDED.volume,
                loaded_at = NOW()
        """, parameters=[
            (row["ticker"], row["date"], row["close"], row["volume"], key)
            for row in raw
        ])

    @task
    def dq_check_ods(logical_date=None):
        """ODS 데이터 품질 검증"""
        pg = PostgresHook(postgres_conn_id="app_db")
        result = pg.get_first("""
            SELECT
                COUNT(*) AS total_rows,
                COUNT(*) FILTER (WHERE close_price IS NULL) AS null_close,
                COUNT(DISTINCT ticker) AS ticker_count
            FROM ods_stock_price_daily
            WHERE trade_date = %s
        """, parameters=[logical_date.date()])

        total, null_close, ticker_count = result
        assert null_close == 0,        f"close_price NULL 발생: {null_close}건"
        assert ticker_count >= 480,    f"종목 수 부족: {ticker_count}개"

    load_ods() >> dq_check_ods()

ods_dag()
```

---

## 레이어 3 — DW (Data Warehouse)

### 역할

ODS에서 **비즈니스 집계·스타 스키마 변환**.  
날짜 파티션 단위로 Insert — 기존 데이터 불변 유지.

### 스타 스키마 설계

```
fact_stock_daily_return
  ├─ dim_ticker (ticker_id FK)
  ├─ dim_date   (date_id FK)
  └─ 측정값: daily_return, volume_ma20, rsi_14, ...
```

```sql
-- DW 팩트 테이블
CREATE TABLE fact_stock_daily_return (
    date_id         INT         NOT NULL REFERENCES dim_date(date_id),
    ticker_id       INT         NOT NULL REFERENCES dim_ticker(ticker_id),
    close_price     NUMERIC(12,4) NOT NULL,
    daily_return    NUMERIC(8,4),           -- (close - prev_close) / prev_close
    volume_ma20     BIGINT,
    rsi_14          NUMERIC(6,2),
    created_at      TIMESTAMP   NOT NULL DEFAULT NOW(),

    PRIMARY KEY (date_id, ticker_id)
) PARTITION BY RANGE (date_id);             -- 연도별 파티셔닝

-- 차원 테이블
CREATE TABLE dim_ticker (
    ticker_id       SERIAL      PRIMARY KEY,
    ticker          TEXT        NOT NULL UNIQUE,
    company_name    TEXT,
    sector          TEXT,
    market_cap_tier TEXT CHECK (market_cap_tier IN ('large','mid','small')),
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE
);
```

### dbt DW 모델

```sql
-- dbt/models/intermediate/int_stock_daily_calc.sql
{{
    config(
        materialized='ephemeral',
        tags=['intermediate', 'market-data']
    )
}}

WITH base AS (
    SELECT
        ticker,
        trade_date,
        close_price,
        LAG(close_price) OVER (PARTITION BY ticker ORDER BY trade_date)
            AS prev_close_price,
        AVG(volume) OVER (
            PARTITION BY ticker
            ORDER BY trade_date
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        )::BIGINT AS volume_ma20
    FROM {{ ref('stg_stock_price_daily') }}
)
SELECT
    ticker,
    trade_date,
    close_price,
    ROUND((close_price - prev_close_price) / NULLIF(prev_close_price, 0) * 100, 4)
        AS daily_return_pct,
    volume_ma20
FROM base
```

```sql
-- dbt/models/dw/fact_stock_daily_return.sql
{{
    config(
        materialized='incremental',
        unique_key=['date_id', 'ticker_id'],
        incremental_strategy='merge',
        tags=['dw', 'market-data']
    )
}}

SELECT
    d.date_id,
    t.ticker_id,
    c.close_price,
    c.daily_return_pct,
    c.volume_ma20
FROM {{ ref('int_stock_daily_calc') }} c
JOIN {{ ref('dim_date') }}   d ON d.full_date = c.trade_date
JOIN {{ ref('dim_ticker') }} t ON t.ticker = c.ticker

{% if is_incremental() %}
WHERE c.trade_date >= (SELECT MAX(d2.full_date) FROM {{ ref('dim_date') }} d2
                       JOIN {{ this }} f ON f.date_id = d2.date_id)
{% endif %}
```

---

## 레이어 4 — MART (Data Mart)

### 역할

도메인 소비자(BI·API·AI)에 맞게 **역정규화·사전 집계**.  
전체 재계산(Replace) — 복잡한 증분 관리 불필요.

### MART 테이블 패턴

```sql
-- Sector별 일별 핵심 지표 MART
CREATE TABLE mart_sector_daily_summary (
    trade_date          DATE        NOT NULL,
    sector              TEXT        NOT NULL,
    ticker_count        INT,
    avg_daily_return    NUMERIC(8,4),
    median_rsi_14       NUMERIC(6,2),
    up_ticker_count     INT,
    down_ticker_count   INT,
    refreshed_at        TIMESTAMP   NOT NULL DEFAULT NOW(),

    PRIMARY KEY (trade_date, sector)
);
```

### dbt MART 모델

```sql
-- dbt/models/marts/mart_sector_daily_summary.sql
{{
    config(
        materialized='table',
        tags=['mart', 'market-data'],
        post_hook="GRANT SELECT ON {{ this }} TO ROLE analyst"
    )
}}

SELECT
    d.full_date                             AS trade_date,
    t.sector,
    COUNT(*)                                AS ticker_count,
    ROUND(AVG(f.daily_return_pct), 4)       AS avg_daily_return,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY f.daily_return_pct
    )::NUMERIC(8,4)                         AS median_daily_return,
    COUNT(*) FILTER (WHERE f.daily_return_pct > 0) AS up_ticker_count,
    COUNT(*) FILTER (WHERE f.daily_return_pct < 0) AS down_ticker_count
FROM {{ ref('fact_stock_daily_return') }} f
JOIN {{ ref('dim_date') }}   d ON d.date_id   = f.date_id
JOIN {{ ref('dim_ticker') }} t ON t.ticker_id = f.ticker_id
GROUP BY d.full_date, t.sector
```

---

## 전체 파이프라인 오케스트레이션 DAG

```python
# apps/airflow/dags/pipeline_market_data_daily.py
from airflow.decorators import dag, task
from airflow.operators.trigger_dagrun import TriggerDagRunOperator
from airflow.sensors.external_task import ExternalTaskSensor

@dag(
    dag_id="pipeline_market_data_daily",
    schedule="0 8 * * 1-5",
    tags=["pipeline", "market-data"],
    default_args=DAG_DEFAULT_ARGS,
)
def pipeline_dag():

    # 1. 수집 DAG 완료 대기
    wait_ingest = ExternalTaskSensor(
        task_id="wait_ingest",
        external_dag_id="ingest_raw_stock_price",
        execution_delta=timedelta(minutes=30),
        timeout=3600,
    )

    # 2. ODS 적재
    trigger_ods = TriggerDagRunOperator(
        task_id="trigger_ods",
        trigger_dag_id="load_raw_to_ods",
        wait_for_completion=True,
    )

    # 3. dbt로 DW + MART 빌드
    @task
    def dbt_build():
        from airflow.operators.bash import BashOperator
        import subprocess
        result = subprocess.run([
            "dbt", "build",
            "--profiles-dir", "/opt/dbt/profiles",
            "--select", "staging+",        # staging 이후 모든 모델
            "--exclude", "tag:slow",
        ], capture_output=True, text=True)
        if result.returncode != 0:
            raise Exception(f"dbt build 실패:\n{result.stderr}")

    # 4. MART 데이터 품질 최종 검증
    @task
    def final_dq():
        from airflow.providers.postgres.hooks.postgres import PostgresHook
        pg = PostgresHook(postgres_conn_id="app_db")
        count = pg.get_first(
            "SELECT COUNT(*) FROM mart_sector_daily_summary WHERE trade_date = CURRENT_DATE"
        )[0]
        assert count > 0, "MART 데이터 없음 — 파이프라인 실패"

    wait_ingest >> trigger_ods >> dbt_build() >> final_dq()

pipeline_dag()
```

---

## 데이터 품질(DQ) 체크 표준

### 레이어별 DQ 항목

| 레이어 | 체크 항목 | 실패 시 |
|--------|---------|--------|
| ODS | NOT NULL, 레코드 수 범위, 날짜 정합성 | DAG fail + Slack 알림 |
| DW | 참조 무결성, 중복 키, 값 범위 (RSI 0~100) | dbt test fail → 하위 모델 실행 차단 |
| MART | 레코드 수 > 0, freshness 24h 이내 | DAG fail + PagerDuty |

### Great Expectations 통합 (선택)

```python
@task
def ge_checkpoint(layer: str, logical_date=None):
    """Great Expectations 품질 체크포인트 실행"""
    import great_expectations as ge

    context = ge.get_context()
    result = context.run_checkpoint(
        checkpoint_name=f"{layer}_daily_checkpoint",
        batch_request={
            "runtime_parameters": {"query": f"SELECT * FROM ods_stock_price_daily WHERE trade_date = '{logical_date.date()}'"},
        }
    )
    if not result["success"]:
        raise ValueError(f"GE 체크포인트 실패: {result}")
```

---

## 재처리 (Backfill) 전략

```bash
# 특정 날짜 재처리
airflow dags backfill \
    --start-date 2026-04-01 \
    --end-date   2026-04-05 \
    pipeline_market_data_daily

# dbt 특정 날짜 모델 재실행
dbt run \
    --select mart_sector_daily_summary \
    --vars '{"execution_date": "2026-04-01"}'
```

| 원칙 | 내용 |
|------|------|
| 멱등성 보장 | 동일 날짜 재실행 시 결과 동일 (UPSERT / Replace) |
| 파티션 단위 | 날짜 파티션 단위로 재처리 — 전체 재계산 방지 |
| 의존성 순서 | 수집 → ODS → DW → MART 순서 강제 |
| 재처리 알림 | 백필 실행 시 Slack #data-ops에 알림 |

---

## 파이프라인 모니터링

### DAG SLA 설정

```python
from airflow.models.slainfo import SLAMiss
from datetime import timedelta

@dag(
    sla_miss_callback=lambda context, sla_miss, ...: slack_alert(sla_miss),
    default_args={**DAG_DEFAULT_ARGS, "sla": timedelta(hours=2)},
)
def pipeline_dag():
    ...
```

### 핵심 메트릭

| 메트릭 | 수집 방법 | 알림 기준 |
|--------|---------|---------|
| DAG 성공률 | Airflow 메타 DB | 7일 평균 < 95% |
| 태스크 지연 | SLA Miss 콜백 | SLA 초과 즉시 |
| DQ 실패율 | dbt test 결과 | 1건 이상 실패 |
| 처리 소요시간 | Airflow Duration | 전주 대비 50% 초과 |

---

## 파일·디렉토리 구조

```
airflow/
├── dags/
│   ├── _defaults.py                    ← 공통 default_args
│   ├── ingest_raw_stock_price.py       ← 수집 DAG
│   ├── load_raw_to_ods.py              ← ODS 적재 DAG
│   └── pipeline_market_data_daily.py   ← 전체 파이프라인 오케스트레이션
├── plugins/
│   └── sensors/
│       └── trading_day_sensor.py
└── tests/
    └── test_dags.py                    ← DAG 구문·Import 검사

dbt/
├── models/
│   ├── staging/    ← stg_*
│   ├── intermediate/ ← int_*
│   ├── dw/         ← fact_*, dim_*
│   └── marts/      ← mart_*
├── tests/
├── seeds/
├── macros/
└── dbt_project.yml
```

---

## 미결 기술 과제

- [ ] Airflow Executor 확정 — KubernetesExecutor vs CeleryExecutor (인프라 환경 기준)
- [ ] dbt 증분(incremental) vs 전체 재계산 전략 — 팩트 테이블 크기 기준 수립
- [ ] Great Expectations vs dbt tests 병행 여부 결정
- [ ] Raw Zone 스토리지 확정 — S3 / GCS / HDFS / 로컬 NFS
- [ ] 스트리밍 수집 확장 — Kafka Connect + ODS 실시간 UPSERT 전략
- [ ] Cross-DAG 의존성 관리 — `ExternalTaskSensor` vs Airflow Dataset 방식 선택
