# Common Spec — 인프라 및 CI/CD

---

## 전체 구조

```
[개발자 Push]
    │
    ▼
[CI Pipeline]  lint → test → build → image push
    │
    ▼
[CD Pipeline]  dev 자동 배포 → staging 수동 승인 → prod 수동 승인
    │
    ▼
[Kubernetes Cluster]
    ├─ Namespace: dev
    ├─ Namespace: staging
    └─ Namespace: prod
```

---

## Docker

### 멀티스테이지 빌드 (FastAPI)

```dockerfile
# Dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app
COPY Pipfile Pipfile.lock ./
RUN pip install pipenv && pipenv install --deploy --system

FROM python:3.11-slim AS runtime
WORKDIR /app
# 보안: non-root 사용자
RUN useradd -m -u 1000 appuser
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY . .
RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 멀티스테이지 빌드 (Spring Boot)

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY gradlew build.gradle.kts settings.gradle.kts ./
COPY gradle ./gradle
RUN ./gradlew dependencies --no-daemon
COPY src ./src
RUN ./gradlew bootJar --no-daemon

FROM eclipse-temurin:21-jre-alpine AS runtime
RUN adduser -D -u 1000 appuser
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
RUN chown appuser:appuser app.jar
USER appuser

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 이미지 네이밍 규칙

```
{registry}/{service-name}:{tag}

tag 형식:
  - latest          → main 브랜치 최신
  - {git-sha}       → 불변 태그 (배포 추적용)
  - {version}       → 릴리스 태그 (예: v1.2.3)

예: ghcr.io/org/ice-breaker-api:a1b2c3d
```

---

## Kubernetes 리소스

### Namespace 분리

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ice-breaker-prod
  labels:
    environment: prod
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: ice-breaker-prod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0       # 무중단 배포
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: ghcr.io/org/ice-breaker-api:${GIT_SHA}
          ports:
            - containerPort: 8000
          envFrom:
            - secretRef:
                name: api-secrets
            - configMapRef:
                name: api-config
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8000
            initialDelaySeconds: 15
            periodSeconds: 20
          readinessProbe:
            httpGet:
              path: /ready
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 10
      terminationGracePeriodSeconds: 30
```

### ConfigMap / Secret 분리

```yaml
# configmap.yaml — 비민감 설정
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
data:
  LOG_LEVEL: "INFO"
  ENV: "prod"

# secret.yaml — 민감 설정 (Vault 또는 Sealed Secrets 권장)
apiVersion: v1
kind: Secret
metadata:
  name: api-secrets
type: Opaque
stringData:
  OPENAI_API_KEY: ""        # 실제값은 CI/CD에서 주입
  SCRAPIN_API_KEY: ""
  TAVILY_API_KEY: ""
```

### HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## CI 파이프라인 (GitHub Actions)

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.11" }
      - run: pip install black isort pylint
      - run: black --check . && isort --check . && pylint app/

  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: test
        options: >-
          --health-cmd pg_isready
          --health-interval 5s
    steps:
      - uses: actions/checkout@v4
      - run: pip install pipenv && pipenv install --dev
      - run: pipenv run pytest --cov=app --cov-report=xml
      - uses: codecov/codecov-action@v4

  build:
    needs: [lint, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v5
        with:
          push: ${{ github.ref == 'refs/heads/main' }}
          tags: ghcr.io/org/ice-breaker-api:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## CD 파이프라인

### 환경별 배포 전략

| 환경 | 트리거 | 승인 | 배포 방식 |
|------|--------|------|----------|
| dev | main 머지 즉시 자동 | 불필요 | Rolling Update |
| staging | dev 배포 성공 후 수동 | 1인 승인 | Rolling Update |
| prod | staging QA 완료 후 수동 | 2인 승인 | Rolling Update → Canary |

### Canary 배포 (prod)

```
1단계: 트래픽 10% → 신버전
         5분 대기 → 에러율 < 1% 확인
2단계: 트래픽 50% → 신버전
         10분 대기 → 에러율 < 1% 확인
3단계: 트래픽 100% → 신버전
         구버전 파드 종료
```

### 롤백

```bash
# 즉시 롤백
kubectl rollout undo deployment/api -n ice-breaker-prod

# 특정 리비전으로 롤백
kubectl rollout undo deployment/api --to-revision=3 -n ice-breaker-prod

# 상태 확인
kubectl rollout status deployment/api -n ice-breaker-prod
```

---

## Helm Chart 구조

```
helm/
└── ice-breaker/
    ├── Chart.yaml
    ├── values.yaml           ← 공통 기본값
    ├── values-dev.yaml
    ├── values-staging.yaml
    ├── values-prod.yaml
    └── templates/
        ├── deployment.yaml
        ├── service.yaml
        ├── ingress.yaml
        ├── configmap.yaml
        ├── hpa.yaml
        └── _helpers.tpl
```

---

## 헬스체크 엔드포인트

| 엔드포인트 | 용도 | 응답 조건 |
|-----------|------|----------|
| `GET /healthz` | Liveness — 프로세스 살아있는가 | 항상 200 |
| `GET /ready` | Readiness — 트래픽 받을 준비됐는가 | DB·외부 의존성 정상 시 200 |
| `GET /metrics` | Prometheus 메트릭 스크래핑 | Prometheus 포맷 텍스트 |

---

## 미결 기술 과제

- [ ] Secrets 관리 도구 확정 — HashiCorp Vault vs Kubernetes Sealed Secrets vs AWS Secrets Manager
- [ ] Ingress Controller 선택 — nginx-ingress vs Traefik vs AWS ALB
- [ ] Canary 배포 자동화 — Argo Rollouts vs Flagger 도입 검토
- [ ] 멀티 클러스터 전략 — 단일 클러스터 vs 환경별 분리 클러스터
- [ ] 이미지 취약점 스캔 — CI에 Trivy 통합 (`trivy image ghcr.io/...`)
