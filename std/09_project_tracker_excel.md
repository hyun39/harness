# STD-09 — 프로젝트 추적 Excel 생성 표준 (재프롬프트)

> **목적**: `SP500_Platform_Tracker.xlsx` 와 동일한 구조의 Excel을 어떤 BDD 프로젝트에도  
> 재현할 수 있도록 입력 조건·시트 구조·생성 프롬프트를 표준화한다.

---

## 1. 사전 준비 — 수집해야 할 파일

Excel 생성 전에 아래 파일을 최신 상태로 유지해야 한다.

| 파일 | 역할 | 위치 |
|------|------|------|
| `specs/product/00_vision.md` | OKR·FR 목록 | Vision/OKR/FR 시트 원천 |
| `specs/product/02_epics.md` | Epic·Feature 매핑 | Epic/Feature 시트 원천 |
| `docs/ARCHITECTURE.md` | 컴포넌트·인프라·엔드포인트 | 아키텍처·인프라 시트 원천 |
| `doc-manure/PROJECT_TRACKER.csv` | Feature별 파일 경로·명령어 | BDD 테스트 시트 원천 |
| `docs/adr/` (전체) | ADR 목록 | ADR 거버넌스 시트 원천 |

> **CSV 선행 생성**: PROJECT_TRACKER.csv가 없으면 아래 명령으로 먼저 생성한다.  
> → STD-09 하단 [부록 A — CSV 생성 프롬프트] 참조

---

## 2. Excel 시트 구조 (10개 고정)

| 순서 | 시트명 | 원천 파일 | 핵심 내용 |
|------|--------|---------|---------|
| 1 | `00_프로젝트_개요` | ARCHITECTURE.md | 아키텍처 흐름·기술스택·토글·계정 |
| 2 | `01_Vision_OKR` | 00_vision.md | Vision Statement + OKR N개 |
| 3 | `02_FR_기능요건` | 00_vision.md + 02_epics.md | FR 전체 (ID·설명·Epic·DR·구현상태) |
| 4 | `03_Epic_Feature_Map` | 02_epics.md + PROJECT_TRACKER.csv | Epic × Feature × 테스트 명령어 |
| 5 | `04_데이터_아키텍처` | ARCHITECTURE.md | 데이터 레이어·Repository·DAG 체인 |
| 6 | `05_API_엔드포인트` | ARCHITECTURE.md | 엔드포인트 전체·인증 정책 |
| 7 | `06_BDD_테스트_현황` | PROJECT_TRACKER.csv | 테스트 수·ad-hoc 실행 명령어 |
| 8 | `07_인프라_컨테이너` | ARCHITECTURE.md + compose/*.yml | 컨테이너 목록·OTel 파이프라인·기동 명령 |
| 9 | `08_ADR_거버넌스` | docs/adr/ + specs/_methodology/ | ADR N개·GOV·STD 목록 |
| 10 | `09_미구현_백로그` | PROJECT_TRACKER.csv + 기억 | 미구현 Feature·거버넌스 과제 |

---

## 3. 재생성 프롬프트

아래 프롬프트를 Claude Code에 그대로 붙여넣으면 Excel이 재생성된다.  
`{{ }}` 표시 부분만 프로젝트에 맞게 교체한다.

---

````
다음 파일들을 읽고 프로젝트 전체를 Excel 한 파일로 정리해줘.
Excel만 보고 프로젝트 전체를 이해할 수 있도록 자기 완결적으로 작성해.

**읽어야 할 파일:**
- {{ specs/product/00_vision.md }}
- {{ specs/product/02_epics.md }}
- {{ docs/ARCHITECTURE.md }}
- {{ doc-manure/PROJECT_TRACKER.csv }}
- {{ docs/adr/ }} 전체

**출력 파일:** {{ doc-manure/SP500_Platform_Tracker.xlsx }}

---

**시트 1 — 00_프로젝트_개요**
- 플랫폼 한 줄 설명 (ARCHITECTURE.md §1에서 추출)
- 아키텍처 흐름 다이어그램 (텍스트 박스 형태)
- 기술 스택 표: 컴포넌트|기술|버전|포트|역할
- 환경변수 토글 표: 변수명|기본값|운영값|의미
- 개발 환경 계정 정보 표: 시스템|URL|ID|PW|비고

**시트 2 — 01_Vision_OKR**
- Vision Statement (인용 블록)
- OKR 표: OKR ID|목표|핵심결과|연결 FR|구현상태|비고

**시트 3 — 02_FR_기능요건**
- FR 전체 표: FR ID|설명|연결 Epic|연결 DR|구현상태|구현방식/위치|비고

**시트 4 — 03_Epic_Feature_Map**
- Epic별 섹션 헤더 (색상 구분) 아래 Feature 행
- 열: Feature ID|Feature명|FR|DR|상태|spec 파일|feature 파일|테스트 실행 명령어
- 테스트 명령어는 프로젝트 루트 기준 uv run 형식

**시트 5 — 04_데이터_아키텍처**
- 데이터 레이어 표: 레이어|테이블명|PK|갱신주기|보존|담당 DAG|DR
- Repository Pattern 표: Protocol|InMemory 구현|Postgres 구현|토글
- DAG 체인 표: DAG ID|역할|스케줄|upstream|XCom 키|Epic|비고

**시트 6 — 05_API_엔드포인트**
- API 서버 엔드포인트 표: 메서드|경로|인증|역할|연결 FR|구현 위치|비고
- Agent/Worker 서버 엔드포인트 표 (있으면)
- 인증 정책 설명 (텍스트 행)

**시트 7 — 06_BDD_테스트_현황**
- 전체 테스트 요약 표: 컴포넌트|테스트 수|상태|실행 명령어|비고
- 자주 쓰는 명령어 박스 (커버리지·재실행·키워드 검색)
- Feature별 ad-hoc 명령어 표: Feature ID|Feature명|step 파일|상태|실행 명령어

**시트 8 — 07_인프라_컨테이너**
- 컨테이너 목록 표: 컨테이너명|이미지|포트|역할|compose 파일|네트워크|비고
- 관찰성 파이프라인 흐름 (텍스트 다이어그램)
- 기동 명령어 표: 명령어|설명

**시트 9 — 08_ADR_거버넌스**
- ADR 목록 표: ADR ID|제목|날짜|상태|핵심 결정|관련 파일
- GOV 문서 표: GOV ID|제목|파일|주요 내용
- STD 문서 표: STD ID|제목|파일

**시트 10 — 09_미구현_백로그**
- 미구현 Feature 표: Feature ID|Feature명|FR|이유/메모|우선순위|담당 Epic
- 거버넌스 후속 과제 표: 항목|분류|설명|우선순위|참조 GOV
- ADR 집행 현황 표: 항목|ADR|완료일|상태|비고

---

**서식 규칙:**
- 시트 제목: 네이비(1F3864) 배경, 흰색 굵은 글씨, 14pt, 36px 높이
- 최종 갱신 행: 회색 배경 이탤릭, 우측 정렬
- 섹션 헤더: 파랑(2E75B6) 배경, 흰색 굵은 글씨 11pt
- 테이블 헤더: 연파랑(BDD7EE) 배경, 검은 굵은 글씨
- 테이블 행: 흰색/연파랑(D6E4F0) 교번
- 셀 테두리: 전체 테두리 thin(CCCCCC)
- 상단 행 고정 (freeze_panes)
- 그리드 라인 숨김

**구현 상태 기호:** ✅ 완료 / ⚠️ 부분 / ❌ 미구현

**명령어 기준:** 프로젝트 루트(sp500-platform/)에서 실행
````

---

## 4. 생성 후 검증 체크리스트

Excel 파일 생성 후 아래 항목을 확인한다.

```
□ 시트 10개 모두 존재
□ 각 시트 제목 행 색상·글씨 정상
□ 테이블 행 교번 색상 적용됨
□ Feature 수 = PROJECT_TRACKER.csv의 FEATURE 행 수와 일치
□ 테스트 명령어 경로에 실제 파일 존재 확인
□ 미구현 항목(❌)이 09_미구현_백로그에 반영됨
□ 최종 갱신일이 오늘 날짜로 기재됨
```

---

## 5. 업데이트 트리거

아래 변경 발생 시 Excel을 재생성한다.

| 변경 종류 | 영향 시트 |
|---------|---------|
| 새 Epic·Feature 추가 | 03, 04, 07, 10 |
| FR 추가·상태 변경 | 02, 03 |
| 새 컨테이너·compose 파일 추가 | 01, 08 |
| 새 API 엔드포인트 추가 | 06 |
| ADR 신규 작성 | 09 |
| 미구현 항목 완료 | 10 |
| 스프린트 종료 시 | 전체 |

---

## 부록 A — PROJECT_TRACKER.csv 생성 프롬프트

Excel 생성 전에 CSV가 없거나 오래된 경우 먼저 실행한다.

````
다음 파일들을 읽고 프로젝트 전체를 추적할 수 있는 CSV를 생성해줘.
저장 위치: {{ doc-manure/PROJECT_TRACKER.csv }}

**읽을 파일:** specs/product/00_vision.md, specs/product/02_epics.md,
  docs/ARCHITECTURE.md, apps/*/tests/bdd/ 디렉터리 구조

**열 구성 (10열, 구분자: 쉼표):**
계층, ID, 이름_설명, FR연결, DR연결, 구현상태,
spec_파일, feature_파일, step_파일, 테스트_실행_명령어

**계층 종류:** VISION | OKR | FR | EPIC | FEATURE | AGGREGATE

**행 순서:**
1. VISION 1행
2. OKR 행 (OKR-01 ~ OKR-N)
3. FR 행 (FR-01 ~ FR-N)
4. EPIC 행 + 하위 FEATURE 행 (Epic별 묶음)
5. AGGREGATE 행 (컴포넌트별 + 전체 실행)

**테스트 명령어 형식:**
uv run --project apps/api pytest <step_파일_경로> -v
(프로젝트 루트 기준, .feature 파일이 없으면 — 로 표기)
````

---

## 부록 B — Python 생성 스크립트 재사용 패턴

openpyxl 기반 Excel 생성 시 아래 헬퍼 함수 패턴을 재사용한다.

```python
# 색상 상수 (변경 가능)
NAVY, BLUE_H, BLUE_L = "1F3864", "2E75B6", "D6E4F0"

def title_row(ws, text, row=1, cols=10, size=14):
    ws.merge_cells(start_row=row, start_column=1,
                   end_row=row, end_column=cols)
    c = ws.cell(row=row, column=1, value=text)
    c.font = Font(bold=True, size=size, color="FFFFFF")
    c.fill = PatternFill("solid", fgColor=NAVY)
    c.alignment = Alignment(horizontal="center", vertical="center")
    ws.row_dimensions[row].height = 36

def write_table(ws, start_row, headers, rows, col_widths=None, start_col=1):
    """헤더 + 교번 색상 데이터 행 자동 생성. 다음 빈 행 번호 반환."""
    for i, h in enumerate(headers):
        # 헤더 셀 작성
        ...
    for ri, row in enumerate(rows):
        bg = BLUE_L if ri % 2 == 0 else "FFFFFF"
        # 데이터 셀 작성
        ...
    return start_row + 1 + len(rows)
```

전체 구현 코드는 `doc-manure/SP500_Platform_Tracker.xlsx` 를 생성한  
Claude Code 세션 기록을 참조한다.
