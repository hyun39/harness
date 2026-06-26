# STD-05 — 인프라·CI/CD 구현 표준

> 전체 상세: [`detail/infra_cicd.md`](./detail/infra_cicd.md)

---

## Docker 멀티스테이지 빌드 (필수)

```dockerfile
# FastAPI
FROM python:3.11-slim AS builder
WORKDIR /app
RUN pip install pipenv && pipenv install --deploy --system

FROM python:3.11-slim AS runtime
RUN useradd -m -u 1000 appuser     # non-root 필수
COPY --from=builder /usr/local/lib/python3.11/site-packages .
COPY . .
USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## 이미지 태그 규칙

```
ghcr.io/{org}/{service}:{git-sha}   ← 배포 추적용 (불변)
ghcr.io/{org}/{service}:latest      ← main 브랜치 최신
ghcr.io/{org}/{service}:v1.2.3      ← 릴리스 태그
```

---

## K8s 필수 설정

```yaml
spec:
  containers:
    - resources:
        requests: { cpu: "250m", memory: "256Mi" }
        limits:   { cpu: "1000m", memory: "1Gi" }
      livenessProbe:
        httpGet: { path: /healthz, port: 8000 }
        initialDelaySeconds: 15
      readinessProbe:
        httpGet: { path: /ready, port: 8000 }
        initialDelaySeconds: 5
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
```

---

## CI 파이프라인 순서

```yaml
# .github/workflows/ci.yml
jobs:
  lint:    runs: ruff / black / isort
  test:    runs: pytest --cov --cov-fail-under=80 + BDD
  security: runs: trivy image (HIGH,CRITICAL → exit-code 1)
  build:   runs: docker buildx + push (main 브랜치만)
  # needs: [lint, test, security] → build
```

---

## 환경별 배포 전략

| 환경 | 트리거 | 승인 |
|------|--------|------|
| dev | main 머지 즉시 | 자동 |
| staging | dev 배포 성공 후 | 1인 수동 |
| prod | staging QA 완료 | 2인 수동 |

---

## 헬스체크 엔드포인트 (필수)

```python
@app.get("/healthz")   # Liveness — 항상 200
async def liveness(): return {"status": "ok"}

@app.get("/ready")     # Readiness — DB 연결 확인 후 200
async def readiness(db = Depends(get_db)):
    await db.execute("SELECT 1")
    return {"status": "ready"}
```

---

## BDD 환경 (로컬)

```yaml
# docker-compose.yml — BDD 테스트 실행 환경
services:
  postgres: { image: postgres:15, ports: ["5432:5432"] }
  redis:    { image: redis:7-alpine }
  api:      { build: ., depends_on: [postgres, redis] }
```

```bash
docker compose up -d postgres
pytest tests/bdd/ -v
```

---

## 패턴 적용 체크리스트

> 이 표준에 정의된 패턴을 실제 코드가 따르는지 audit. 각 항목은 yes/no.
> 식별자(`S05-NN-MM`)는 통합 인덱스(`specs/_methodology/CHECKLIST.md`)에서 참조.

### 카테고리 1: Docker 이미지
- [ ] S05-01-01: Dockerfile이 멀티스테이지 빌드(builder + runtime) 패턴인가
- [ ] S05-01-02: runtime stage에서 빌드 도구(gcc, npm 등)가 제거됐는가
- [ ] S05-01-03: USER non-root(UID ≥ 1000)로 실행하는가
- [ ] S05-01-04: HEALTHCHECK 또는 K8s livenessProbe가 정의됐는가
- [ ] S05-01-05: 이미지 크기가 합리적 수준인가 (slim base 사용)

### 카테고리 2: K8s SecurityContext
- [ ] S05-02-01: runAsNonRoot가 true로 설정됐는가
- [ ] S05-02-02: readOnlyRootFilesystem이 true로 설정됐는가
- [ ] S05-02-03: allowPrivilegeEscalation이 false인가
- [ ] S05-02-04: capabilities.drop이 ["ALL"]로 설정됐는가
- [ ] S05-02-05: HostPath/hostNetwork/hostPID가 사용되지 않았는가 (gov/04 연계)

### 카테고리 3: Compose·CI/CD
- [ ] S05-03-01: docker-compose 서비스가 단일 책임으로 분리됐는가 (`infra/compose/<service>.yml`)
- [ ] S05-03-02: depends_on에 condition: service_healthy가 적용됐는가
- [ ] S05-03-03: 환경별 compose override가 분리됐는가 (e2e용 등)
- [ ] S05-03-04: CI 파이프라인이 lint → unit → integration → E2E 순서인가
- [ ] S05-03-05: 이미지 빌드 후 Trivy scan이 적용되는가

### 카테고리 4: 리소스 관리
- [ ] S05-04-01: Pod resources.requests / resources.limits가 설정됐는가
- [ ] S05-04-02: HPA(Horizontal Pod Autoscaler)가 운영 서비스에 적용됐는가
- [ ] S05-04-03: PodDisruptionBudget이 설정됐는가
