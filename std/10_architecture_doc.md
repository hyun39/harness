# STD-10 — ARCHITECTURE.md 재생성 표준 (재프롬프트)

> **목적**: `docs/ARCHITECTURE.md` 를 현재 코드베이스와 완전히 정합한 상태로  
> 재작성·현행화할 수 있는 표준 프롬프트를 정의한다.  
> 관련 정책: [GOV-02 ADR](../gov/02_adr.md) · [GOV-09 관찰성](../gov/09_observability.md)

---

## 1. 사전 준비 — 코드에서 읽어야 할 위치

| 확인 대상 | 명령 / 경로 | 추출 정보 |
|----------|-----------|---------|
| 컴포넌트 목록 | `ls apps/` | 서비스 수 |
| compose 파일 | `ls infra/compose/` | 컨테이너 전체·포트 |
| API 엔드포인트 | `grep -rn "@router\." apps/*/app/routers/` | 경로·메서드 |
| Agent 엔드포인트 | `grep -n "@router\." apps/agent/app/routers/` | 경로·메서드 |
| 인증 정책 | `apps/api/app/core/auth.py` 상단 docstring | USE_AUTH 분기 |
| 환경변수 토글 | `grep -rn "USE_INMEMORY\|USE_AUTH\|USE_STUB" infra/compose/` | 운영값 |
| OTel 파이프라인 | `infra/otel/collector-config.yaml` | exporter·파이프라인 |
| DAG 목록 | `ls apps/airflow/dags/*.py` | DAG ID·역할 |
| ADR 목록 | `ls docs/adr/*.md` | 번호·제목 |

---

## 2. ARCHITECTURE.md 고정 섹션 구조

| 섹션 | 제목 | 필수 포함 내용 |
|------|------|-------------|
| §1 | 시스템 개요 | 한 줄 설명 + 텍스트 다이어그램 + 핵심 원칙 3개 |
| §2 | 컴포넌트 구성 | 컴포넌트 표 (컴포넌트\|디렉터리\|기술\|역할) |
| §3 | 데이터 레이어 | Raw→ODS→DW→Mart→Analysis 흐름 표 |
| §4 | 데이터 액세스 패턴 | Repository Protocol 다이어그램 + 토글 설명 |
| §5 | API 엔드포인트/인증 | 인증 정책 표 + 엔드포인트 전체 표 |
| §6 | Agent 파이프라인 | LangGraph 그래프 흐름 + async to_thread 이유 |
| §7 | 프런트엔드 구조 | src/ 디렉터리 트리 + 토글 설명 |
| §8 | 배포/인프라 | 컨테이너 토폴로지 + OTel 파이프라인 + compose 표 + 토글 표 |
| §9 | 외부 의존성 현황 | 의존성별 상태 표 (✅/⚠️/❌) |
| §10 | 갱신 가이드 | 트리거→섹션 표 + 정합성 체크 명령 + 관련 문서 |

---

## 3. 재생성 프롬프트

````
현재 코드베이스를 읽고 docs/ARCHITECTURE.md 를 전면 재작성해줘.
아래 명령들을 실행해서 현재 상태를 파악한 뒤 작성해.

**파악해야 할 현재 상태:**
```bash
ls infra/compose/
grep -rn "@router\.(get\|post\|put\|delete\)" apps/api/app/routers/ apps/agent/app/routers/
grep -rn "USE_INMEMORY\|USE_AUTH\|VITE_USE_AUTH\|USE_STUB" infra/compose/
cat apps/api/app/core/auth.py   # 인증 정책 docstring
cat infra/otel/collector-config.yaml   # OTel 파이프라인
ls apps/airflow/dags/*.py
ls docs/adr/ | grep -v README
```

**고정 섹션 10개 (순서 유지):**

§1 시스템 개요
- 한 줄 플랫폼 설명
- 텍스트 다이어그램: 주요 컴포넌트와 데이터 흐름
- 핵심 원칙 3개 (토글 가능 모드 / Repository Protocol / BDD 단일 진실원)

§2 컴포넌트 구성
- 표: 컴포넌트|디렉터리|기술|역할
- apps/ 아래 모든 서비스 + 인프라 컴포넌트(DB/Auth/OTel 등) 포함
- "BDD 테스트는 apps/api/.venv 공유" 패턴 명시

§3 데이터 레이어
- ASCII 흐름도: Raw→ODS→DW→Mart→Analysis + 벡터DB 분기
- 표: 레이어|갱신주기|보존|담당 DAG|DR
- ORM 모델 파일 경로 명시

§4 데이터 액세스 패턴 — Repository
- ASCII 다이어그램: router→Protocol→(InMemory|Postgres)
- repositories/ 파일별 역할 (protocols/inmemory/postgres)
- 테스트 격리 패턴: dependency_overrides

§5 API 엔드포인트 / 인증
- §5.1 인증 정책 표: USE_AUTH 값|동작 + 엔드포인트별 인증 의존성 규칙
- §5.2 API 서버 엔드포인트 표: 메서드|경로|인증|역할|FR|비고
- §5.3 Agent 서버 엔드포인트 표 (있으면)

§6 Agent — LangGraph 파이프라인
- ASCII 흐름도: POST /agent/analyze 진입 → asyncio.to_thread × 2 → graph nodes
- async + to_thread 이중 offload 이유 한 줄 (deadlock 방지)
- HttpxAgentClient와 traceparent 자동 주입 설명

§7 프런트엔드 구조
- apps/frontend/src/ 디렉터리 트리 (파일명 + 역할 한 줄)
- VITE_USE_AUTH / VITE_USE_MOCK 토글 설명

§8 배포 / 인프라
- §8.1 컨테이너 네트워크 토폴로지 (ASCII 트리, 포트 포함)
- §8.2 관찰성 파이프라인 흐름 (collector → 복수 exporter)
- §8.3 compose 파일 표: 파일|서비스
- §8.4 환경변수 토글 표: 변수|기본값|운영값|의미
- §8.5 Keycloak 개발 계정 표

§9 외부 의존성 현황
- 표: 항목|상태|비고 (✅/⚠️/❌ 구분)

§10 갱신 가이드
- §10.1 트리거→섹션 표
- §10.2 정합성 체크 bash 명령어 블록
- §10.3 관련 문서 목록

**형식 규칙:**
- 최상단에 "마지막 갱신: YYYY-MM-DD" 명시
- 코드·명령어는 반드시 ` ``` ` 블록 사용
- 엔드포인트 표는 코드베이스에서 실제 읽은 값만 기재 (추정 금지)
````

---

## 4. 현행화 트리거 (언제 재실행할지)

| 변경 종류 | 갱신 섹션 |
|---------|---------|
| 새 컴포넌트 추가 (apps/ 하위) | §1 다이어그램 + §2 표 |
| 새 API 엔드포인트 | §5 표 |
| Agent 그래프 노드 변경 | §6 |
| compose 파일 추가·포트 변경 | §8.1~8.3 |
| 환경변수 토글 추가 | §8.4 |
| 외부 서비스 도입·제거 | §9 |
| ADR 신규 작성 | §2 (기술 변경 시) |

---

## 5. 검증 체크리스트

```
□ ls infra/compose/ 결과와 §8.3 표가 일치
□ grep @router 결과와 §5 표가 일치
□ 환경변수 실제 운영값(infra/compose/*.yml)과 §8.4 일치
□ 마지막 갱신일 = 오늘 날짜
□ §9에 ❌/⚠️ 항목이 있으면 09_미구현_백로그에도 반영
```
