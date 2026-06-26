# Common Spec — RAG Agent

---

## RAG 파이프라인 구조

```
문서 준비 (오프라인)
  → 문서 로드 → 청킹 → 임베딩 → 벡터 스토어 저장

질의 처리 (온라인)
  → 질의 임베딩 → 유사도 검색 → 컨텍스트 조합 → LLM 생성
```

---

## 청킹(Chunking) 전략

| 전략 | 방법 | 적합한 문서 |
|------|------|------------|
| Fixed-size | 고정 토큰/문자 수로 분할 | 구조 없는 긴 텍스트 |
| Recursive | 단락 → 문장 → 단어 순 재귀 분할 | 일반 문서 (기본 선택) |
| Semantic | 의미 경계(문단, 섹션)로 분할 | 구조화된 문서 (Markdown, HTML) |
| Document-aware | 문서 타입별 파서 사용 | PDF, 코드, JSON |

```python
# LangChain Recursive 청킹 예시
from langchain.text_splitter import RecursiveCharacterTextSplitter

splitter = RecursiveCharacterTextSplitter(
    chunk_size=512,
    chunk_overlap=50,       # 경계 맥락 보존
    separators=["\n\n", "\n", ".", " "],
)
```

**chunk_size 선택 기준**

| 상황 | chunk_size | chunk_overlap |
|------|-----------|---------------|
| 짧은 사실 검색 | 256~512 토큰 | 20~50 |
| 문서 요약 | 1024~2048 토큰 | 100~200 |
| 코드 블록 | 함수 단위 | 0 (경계 명확) |

---

## 임베딩 모델 선택

| 모델 | 차원 | 특징 |
|------|------|------|
| `text-embedding-3-small` | 1536 | 비용 낮음, 다국어 지원 |
| `text-embedding-3-large` | 3072 | 정확도 높음, 비용 높음 |
| `text-embedding-ada-002` | 1536 | 구형, 레거시 호환용 |
| `bge-m3` (오픈소스) | 1024 | 로컬 실행 가능, 다국어 강점 |

**선택 기준**: 한국어 포함 → 다국어 모델. 비용 민감 → `small`. 정확도 우선 → `large`.

---

## 벡터 스토어 비교

| 스토어 | 배포 형태 | 장점 | 단점 |
|--------|----------|------|------|
| Chroma | 로컬 / 서버 | 설정 간단, Python 네이티브 | 대용량 성능 한계 |
| Pinecone | 클라우드 완전관리형 | 수평 확장, 관리 불필요 | 비용, 벤더 의존 |
| Weaviate | 자체 호스팅 / 클라우드 | 하이브리드 검색 내장 | 설정 복잡 |
| pgvector | PostgreSQL 확장 | 기존 DB 통합, 트랜잭션 지원 | 수백만 벡터 이상에서 성능 저하 |
| Qdrant | 자체 호스팅 / 클라우드 | Rust 기반 고성능, 필터링 강점 | 비교적 신규 |

**소규모 개발**: Chroma → **프로덕션 확장**: Pinecone 또는 Qdrant → **기존 PG 사용 중**: pgvector

---

## 검색(Retrieval) 전략

| 전략 | 설명 | 적합한 상황 |
|------|------|------------|
| Similarity Search | 코사인 유사도 상위 k개 | 기본 시맨틱 검색 |
| MMR (Maximal Marginal Relevance) | 유사도 + 다양성 균형 | 결과 중복 방지 |
| Hybrid Search | 벡터 + 키워드(BM25) 결합 | 고유명사·전문용어 포함 |
| Self-Query | LLM이 메타데이터 필터 자동 생성 | 구조화된 메타데이터 있을 때 |
| Multi-Query | 질의를 여러 관점으로 확장 후 검색 | 질의 표현이 다양할 때 |

```python
# Hybrid Search 예시 (LangChain + Weaviate)
retriever = vectorstore.as_retriever(
    search_type="mmr",
    search_kwargs={"k": 5, "fetch_k": 20, "lambda_mult": 0.7}
)
```

---

## 컨텍스트 조합 패턴

```
검색된 청크 → 컨텍스트 구성 → LLM 프롬프트 삽입

프롬프트 구조:
  [System]  역할 + 출력 포맷 지시
  [Context] 검색된 문서 청크 (번호 붙여 명확히 구분)
  [User]    실제 질의
```

**컨텍스트 창 관리**:
- 최대 컨텍스트 = 모델 컨텍스트 창 × 0.7 (출력 여유 확보)
- 청크 수 k는 `chunk_size × k < 최대 컨텍스트`로 계산

---

## 리랭킹(Reranking)

초기 검색(벡터 유사도) 결과를 교차 인코더로 재평가하여 정밀도 향상.

```
벡터 검색 (k=20, 빠름, 재현율 높음)
  → Reranker (상위 5개 선별, 정밀도 높음)
  → LLM 입력
```

| 리랭커 | 특징 |
|--------|------|
| Cohere Rerank | API 방식, 간단 통합 |
| `cross-encoder/ms-marco-MiniLM` | 오픈소스, 로컬 실행 |
| BGE-Reranker | 다국어, 한국어 성능 양호 |

---

## RAG 평가 지표

| 지표 | 측정 대상 | 도구 |
|------|----------|------|
| Faithfulness | 답변이 컨텍스트에 근거했는가 | RAGAS |
| Answer Relevancy | 답변이 질의에 관련됐는가 | RAGAS |
| Context Precision | 검색된 청크 중 관련 비율 | RAGAS |
| Context Recall | 관련 청크를 빠뜨리지 않았는가 | RAGAS |
| MRR / NDCG | 검색 순위 품질 | 커스텀 |

```python
# RAGAS 평가 예시
from ragas import evaluate
from ragas.metrics import faithfulness, answer_relevancy

result = evaluate(
    dataset,
    metrics=[faithfulness, answer_relevancy],
)
```

---

## 문서 메타데이터 설계

벡터 스토어에 저장할 메타데이터 — 필터링·출처 추적에 사용.

```python
Document(
    page_content="청크 텍스트",
    metadata={
        "source": "linkedin",       # 출처 소스
        "person_id": 42,            # 연결 엔티티 ID
        "chunk_index": 3,           # 청크 순번 (재조합용)
        "fetched_at": "2026-05-03", # 수집 시각
        "is_mock": False,
    }
)
```

---

## 미결 기술 과제

- [ ] 청크 크기 최적값 실험 — 512 vs 1024 토큰 정밀도 비교
- [ ] 한국어 임베딩 모델 성능 벤치마크 (OpenAI vs BGE-M3)
- [ ] 벡터 스토어 선택 확정 — Chroma(개발) → pgvector(운영) 전환 전략
- [ ] RAGAS 평가 데이터셋 구축 방법 (Golden QA 셋 확보)
- [ ] 청크 업데이트 전략 — 소스 문서 변경 시 벡터 재생성 범위 결정
