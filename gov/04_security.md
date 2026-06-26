# GOV-04 — 보안 필수 규칙

> **강제 대상**: 모든 서비스·코드·배포  
> **게이트**: SAST HIGH/CRITICAL 발견 시 CI 차단, 컨테이너 보안 체크  
> **원본 참조**: `enterprise/04.02_gov_zero_trust_security.md`, `common/security.md`

---

## Zero Trust 원칙 (MUST)

| 원칙 | 강제 방법 |
|------|---------|
| 암묵적 신뢰 없음 | 모든 요청은 JWT 검증 (Keycloak) |
| 최소 권한 | Kubernetes SecurityContext — non-root, readOnlyRootFilesystem |
| 지속 검증 | JWKS 캐시 TTL 1시간, 만료 토큰 즉시 거부 |
| 암호화 전송 | TLS 1.3 필수 — HTTP 리다이렉트 강제 |

---

## 필수 보안 체크리스트

### 코드 레벨
- [ ] 모든 입력값에 Pydantic / Bean Validation 적용
- [ ] SQL은 ORM 파라미터 바인딩만 사용 (raw SQL 금지)
- [ ] 응답에 보안 헤더 포함 (`HSTS`, `X-Frame-Options`, `CSP`)
- [ ] CORS `allow_origins=["*"]` 운영 환경 금지

### Secrets 관리
- [ ] `.env` 파일 `.gitignore` 등록 확인
- [ ] API 키·비밀번호 코드·주석·로그에 절대 노출 금지
- [ ] CI/CD: GitHub Secrets 또는 Vault 사용

### 컨테이너 (Pod Security Standard "Restricted" 준수)
- [ ] non-root user 실행 (UID ≥ 1000)
- [ ] read-only root filesystem
- [ ] privilege escalation 금지
- [ ] capabilities ALL drop (필요 시 명시 추가)
- [ ] HostPath / hostNetwork / hostPID 금지

> 구현 패턴(Dockerfile USER, K8s SecurityContext YAML)은
> [`std/05_infra.md`](../std/05_infra.md) 참조.

### 의존성
- [ ] PR마다 `trivy` 또는 `pip audit` / OWASP Dependency Check 실행
- [ ] HIGH/CRITICAL CVE 발견 시 즉시 업데이트 또는 예외 등록

---

## OWASP Top 10 필수 대응

| 순위 | 항목 | 최소 대응 |
|------|------|---------|
| A01 | Broken Access Control | Keycloak RBAC + 메서드 레벨 권한 |
| A02 | Cryptographic Failures | TLS 1.3, AES-256 저장 암호화 |
| A03 | Injection | ORM·Pydantic 필수 |
| A05 | Security Misconfiguration | 보안 헤더·기본 자격증명 제거 |
| A06 | Vulnerable Components | CI 취약점 스캔 필수 |
| A07 | Auth Failures | Keycloak Brute Force 활성화 |
| A09 | Logging Failures | PII 마스킹 후 로그, 감사 로그 필수 |
| A10 | SSRF | 외부 URL 화이트리스트 |

---

## 감사 로그 필수 항목

다음 이벤트는 반드시 구조화 로그로 기록한다:
- 로그인 성공·실패
- 권한 없는 접근 시도
- PII 데이터 조회
- 관리자 작업

```json
{
  "timestamp": "ISO8601",
  "event_type": "AUTH_FAILURE",
  "user_id": "...",
  "ip_address": "...",
  "resource": "POST /v1/process",
  "result": "DENIED"
}
```

---

## CI 보안 게이트

```yaml
# .github/workflows/security.yml
- name: Trivy 이미지 스캔
  uses: aquasecurity/trivy-action@master
  with:
    severity: HIGH,CRITICAL
    exit-code: 1           # 발견 시 빌드 실패

- name: Secrets 스캔
  uses: gitleaks/gitleaks-action@v2
  # 코드에 하드코딩된 비밀값 감지 시 차단
```

---

## 검증 체크리스트

> 이 가이드 기준으로 application을 audit할 때 사용. 각 항목은 yes/no.
> 통합 인덱스: [`specs/_methodology/CHECKLIST.md`](../CHECKLIST.md)

### 카테고리 1: Zero Trust 원칙 (G04-01)
- [ ] G04-01-01: 모든 요청이 JWT 검증(Keycloak)을 거치는가? (암묵적 신뢰 없음)
- [ ] G04-01-02: Kubernetes SecurityContext가 non-root + readOnlyRootFilesystem 으로 설정되어 있는가? (최소 권한)
- [ ] G04-01-03: JWKS 캐시 TTL 1시간, 만료 토큰 즉시 거부가 적용되어 있는가? (지속 검증)
- [ ] G04-01-04: TLS 1.3 필수, HTTP→HTTPS 리다이렉트가 강제되는가? (암호화 전송)

### 카테고리 2: 코드 레벨 보안 (G04-02)
- [ ] G04-02-01: 모든 입력값에 Pydantic 또는 Bean Validation 이 적용되어 있는가?
- [ ] G04-02-02: SQL은 ORM 파라미터 바인딩만 사용하는가? (raw SQL 금지)
- [ ] G04-02-03: 응답에 보안 헤더(`HSTS`, `X-Frame-Options`, `CSP`)가 포함되어 있는가?
- [ ] G04-02-04: 운영 환경에서 CORS `allow_origins=["*"]` 사용이 금지되었는가?

### 카테고리 3: Secrets 관리 (G04-03)
- [ ] G04-03-01: `.env` 파일이 `.gitignore` 에 등록되어 있는가?
- [ ] G04-03-02: API 키·비밀번호가 코드·주석·로그에 노출되어 있지 않은가?
- [ ] G04-03-03: CI/CD 가 GitHub Secrets 또는 Vault 를 사용하는가?

### 카테고리 4: 컨테이너 (G04-04)
- [ ] G04-04-01: 컨테이너가 non-root user(UID ≥ 1000)로 실행되는가?
- [ ] G04-04-02: read-only root filesystem 이 적용되어 있는가?
- [ ] G04-04-03: privilege escalation 이 금지되어 있는가? (`allowPrivilegeEscalation: false`)
- [ ] G04-04-04: capabilities ALL drop 이 적용되었는가? (필요 시 명시 추가)
- [ ] G04-04-05: HostPath / hostNetwork / hostPID 사용이 금지되었는가?

### 카테고리 5: 의존성·OWASP (G04-05)
- [ ] G04-05-01: PR 마다 `trivy` 또는 `pip audit` / OWASP Dependency Check 가 실행되는가?
- [ ] G04-05-02: HIGH/CRITICAL CVE 발견 시 즉시 업데이트 또는 예외 등록이 운영되는가?
- [ ] G04-05-03: A01 Broken Access Control — Keycloak RBAC + 메서드 레벨 권한이 적용되는가?
- [ ] G04-05-04: A02 Cryptographic Failures — TLS 1.3, AES-256 저장 암호화가 적용되는가?
- [ ] G04-05-05: A07 Auth Failures — Keycloak Brute Force 보호가 활성화되어 있는가?
- [ ] G04-05-06: A10 SSRF — 외부 URL 화이트리스트가 적용되는가?

### 카테고리 6: 감사 로그·CI 게이트 (G04-06)
- [ ] G04-06-01: 로그인 성공·실패가 구조화 로그(JSON)로 기록되는가?
- [ ] G04-06-02: 권한 없는 접근 시도가 구조화 로그로 기록되는가?
- [ ] G04-06-03: PII 데이터 조회가 구조화 로그로 기록되는가?
- [ ] G04-06-04: 관리자 작업이 구조화 로그로 기록되는가?
- [ ] G04-06-05: 감사 로그에 `timestamp`, `event_type`, `user_id`, `ip_address`, `resource`, `result` 필드가 포함되는가?
- [ ] G04-06-06: CI에 Trivy 이미지 스캔(severity HIGH/CRITICAL → exit-code 1)이 설정되어 있는가?
- [ ] G04-06-07: CI에 Secrets 스캔(gitleaks)이 설정되어 있는가?

