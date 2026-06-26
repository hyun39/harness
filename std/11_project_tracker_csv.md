# STD-11 — PROJECT_TRACKER.csv 재생성 표준 (재프롬프트)

> **목적**: `doc-manure/PROJECT_TRACKER.csv` 를 현재 코드베이스에서 읽어  
> Vision→OKR→FR→Epic→Feature 계층을 행으로 풀어 재생성하는 표준 프롬프트.  
> 이 CSV는 STD-09(Excel) · STD-10(ARCHITECTURE.md) 의 원천 파일이다.

---

## 1. 사전 준비 — 읽어야 할 파일

| 파일 | 추출 정보 |
|------|---------|
| `specs/product/00_vision.md` | OKR ID·목표·FR 연결 |
| `specs/product/02_epics.md` | Epic ID·Feature ID·FR·DR·구현상태 |
| `specs/features/**/*_spec.md` | Feature별 spec 파일 경로 확인 |
| `specs/features/**/*.feature` | feature 파일 경로 확인 |
| `apps/*/tests/bdd/steps/**/*.py` | step 파일 실제 경로 확인 |
| `apps/api/pytest.ini` | bdd_features_base_dir 경로 규칙 |

---

## 2. CSV 열 정의 (10열 고정)

| 열 번호 | 열명 | 설명 | 예시 |
|--------|------|------|------|
| 1 | `계층` | VISION / OKR / FR / EPIC / FEATURE / AGGREGATE | `FEATURE` |
| 2 | `ID` | 계층별 고유 식별자 | `F-03-01` |
| 3 | `이름_설명` | 한 줄 설명 | `전체 트렌드 분석 조회` |
| 4 | `FR연결` | 쉼표 구분 FR ID | `FR-04,FR-07` |
| 5 | `DR연결` | 쉼표 구분 DR ID | `DR-04,DR-05` |
| 6 | `구현상태` | ✅ 완료 / ⚠️ 부분 / ❌ 미구현 / — | `✅ 완료` |
| 7 | `spec_파일` | 루트 기준 상대 경로 | `specs/features/analysis/trend_analysis_spec.md` |
| 8 | `feature_파일` | 루트 기준 상대 경로, 없으면 — | `specs/features/analysis/trend_analysis.feature` |
| 9 | `step_파일` | 루트 기준 상대 경로, 없으면 — | `apps/api/tests/bdd/steps/analysis/test_trend_analysis.py` |
| 10 | `테스트_실행_명령어` | 프로젝트 루트 기준 실행 명령, 없으면 — | `uv run --project apps/api pytest apps/api/tests/bdd/steps/analysis/test_trend_analysis.py -v` |

**구분자**: 쉼표(`,`). 값에 쉼표가 포함되면 `"` 로 감싼다.

---

## 3. 행 순서 및 계층 규칙

```
1행: VISION (1개)
2~N행: OKR (OKR-01, OKR-02, ... 오름차순)
다음 N행: FR (FR-01, FR-02, ... 오름차순)
이후: EPIC + 하위 FEATURE 묶음 반복
  - EPIC 행: spec_파일/feature_파일/step_파일/명령어 = —
  - FEATURE 행: Epic ID 순서 오름차순, Feature ID 오름차순
마지막: AGGREGATE 행 (컴포넌트별 전체 + ALL-BDD)
```

**AGGREGATE 행 필수 포함:**

| ID | 설명 | 실행 명령어 |
|----|------|-----------|
| ALL-API | API BDD 전체 | `uv run --project apps/api pytest apps/api/tests/bdd/ -v` |
| ALL-AIRFLOW | Airflow BDD 전체 | `uv run --project apps/api pytest apps/airflow/tests/bdd/ -v` |
| ALL-AGENT | Agent BDD 전체 | `uv run --project apps/api pytest apps/agent/tests/bdd/ -v` |
| ALL-FRONTEND | Frontend BDD 전체 | `uv run --project apps/api pytest apps/frontend/tests/bdd/ -v` |
| ALL-BDD | 전체 통합 | `uv run --project apps/api pytest apps/api/tests/bdd/ apps/airflow/tests/bdd/ apps/agent/tests/bdd/ apps/frontend/tests/bdd/ -v --tb=short` |

---

## 4. 재생성 프롬프트

````
다음 파일들을 읽고 doc-manure/PROJECT_TRACKER.csv 를 재생성해줘.
Vision→OKR→FR→Epic→Feature 계층을 빠짐없이 행으로 풀어서 작성해.

**읽어야 할 파일:**
- specs/product/00_vision.md
- specs/product/02_epics.md
- find specs/features -name "*_spec.md" | sort
- find specs/features -name "*.feature" | sort
- find apps -name "test_*.py" -path "*/bdd/*" | sort
  (grep -v ".venv\|__pycache__")

**열 구성 (헤더 포함 10열, 구분자: 쉼표):**
계층,ID,이름_설명,FR연결,DR연결,구현상태,spec_파일,feature_파일,step_파일,테스트_실행_명령어(프로젝트_루트_기준)

**행 순서 (반드시 이 순서로):**
1. VISION 1행 — 플랫폼 전체 설명, FR연결=FR-01~FR-N
2. OKR 행들 — 00_vision.md에서 OKR ID·목표·FR 추출
3. FR 행들 — FR-01부터 순서대로, 연결 Epic·DR·구현상태 포함
4. EPIC+FEATURE 묶음 — 각 Epic 1행 + 하위 Feature 행들
5. AGGREGATE 행들 — ALL-API/ALL-AIRFLOW/ALL-AGENT/ALL-FRONTEND/ALL-BDD

**구현상태 판단 기준:**
- ✅ 완료: spec 파일·step 파일 모두 존재 + 최근 커밋에서 PASS 확인
- ⚠️ 부분: 구현됐지만 일부 시나리오 미완성 또는 테스트 조건부
- ❌ 미구현: spec은 있으나 step 파일 없음 또는 기능 미구현
- step 파일이 없으면 feature_파일·step_파일·명령어 열을 — 로 표기

**테스트 명령어 형식 (프로젝트 루트에서):**
uv run --project apps/api pytest <step_파일_경로> -v
(feature 파일이 없는 F-04-06 류는 — 로 표기)

**마지막 AGGREGATE 행 5개는 고정:**
AGGREGATE,ALL-API,"API BDD 전체 (analysis+auth+ops)",—,—,✅,—,—,apps/api/tests/bdd/,"uv run --project apps/api pytest apps/api/tests/bdd/ -v"
AGGREGATE,ALL-AIRFLOW,"Airflow BDD 전체 (pipeline)",—,—,✅,—,—,apps/airflow/tests/bdd/,"uv run --project apps/api pytest apps/airflow/tests/bdd/ -v"
AGGREGATE,ALL-AGENT,"Agent BDD 전체 (RAG)",—,—,✅,—,—,apps/agent/tests/bdd/,"uv run --project apps/api pytest apps/agent/tests/bdd/ -v"
AGGREGATE,ALL-FRONTEND,"Frontend BDD 전체 (UI)",—,—,✅,—,—,apps/frontend/tests/bdd/,"uv run --project apps/api pytest apps/frontend/tests/bdd/ -v"
AGGREGATE,ALL-BDD,"전체 BDD 통합",—,—,✅,—,—,"apps/api apps/airflow apps/agent apps/frontend","uv run --project apps/api pytest apps/api/tests/bdd/ apps/airflow/tests/bdd/ apps/agent/tests/bdd/ apps/frontend/tests/bdd/ -v --tb=short"
````

---

## 5. 업데이트 트리거

| 변경 종류 | 재생성 필요 여부 |
|---------|--------------|
| 새 Feature spec 파일 추가 | 필수 |
| step 파일 추가·경로 변경 | 필수 |
| 구현상태 변경 (미구현→완료) | 필수 |
| Epic 추가·Feature ID 재번호 | 필수 |
| FR 추가·삭제 | 필수 |
| 스프린트 종료 | 권장 |

---

## 6. 검증 체크리스트

```
□ find apps -name "test_*.py" -path "*/bdd/*" 결과 수 = CSV FEATURE 행 수
□ step 파일 경로가 실제 파일로 존재하는지 확인
  find apps -name "test_*.py" -path "*/bdd/*" | while read f; do
    [ -f "$f" ] || echo "MISSING: $f"
  done
□ AGGREGATE 5행이 마지막에 존재
□ 헤더 포함 행 수 = 1 + OKR수 + FR수 + EPIC수 + FEATURE수 + 5
□ CSV 파일이 Excel에서 열렸을 때 열 깨짐 없음 (인코딩 UTF-8-BOM 권장)
```
