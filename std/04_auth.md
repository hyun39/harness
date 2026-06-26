# STD-04 — 인증·인가 구현 표준 (Keycloak)

> 전체 상세: [`detail/auth_keycloak.md`](./detail/auth_keycloak.md)

---

## 인증 흐름 요약

```
브라우저 → Keycloak (PKCE) → Access Token (JWT, 5분)
                            + Refresh Token (HttpOnly Cookie, 30분)

백엔드 → Keycloak JWKS → JWT 서명 검증 (네트워크 호출 없음)
```

---

## FastAPI JWT 검증

```python
from fastapi.security import HTTPBearer
from jose import jwt, JWTError

bearer = HTTPBearer()

async def get_current_user(token = Depends(bearer)) -> dict:
    try:
        payload = jwt.decode(
            token.credentials,
            jwks,                      # 앱 시작 시 캐싱 (TTL 1h)
            algorithms=["RS256"],
            audience=settings.client_id,
        )
        return payload
    except JWTError:
        raise HTTPException(401, "유효하지 않은 토큰")

# 엔드포인트에 적용
@router.get("/v1/analyses")
async def list_analyses(user: dict = Depends(get_current_user)):
    user_id = user["sub"]
    ...
```

---

## Spring Boot JWT 검증 (자동 설정)

```yaml
# application.yml
spring.security.oauth2.resourceserver.jwt:
  issuer-uri: ${KEYCLOAK_URL}/realms/${REALM}
```

```java
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain chain(HttpSecurity http) throws Exception {
        return http
            .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()))
            .authorizeHttpRequests(a -> a
                .requestMatchers("/healthz").permitAll()
                .anyRequest().authenticated())
            .sessionManagement(s -> s.sessionCreationPolicy(STATELESS))
            .build();
    }
}

// 메서드 레벨 권한
@PreAuthorize("hasRole('admin')")
public void deleteAnalysis(Long id) { ... }
```

---

## 역할 설계

| Realm Role | 용도 |
|-----------|------|
| `user` | 일반 조회 |
| `analyst` | 데이터 레이어 직접 조회 |
| `admin` | 전체 관리 |

JWT 클레임: `realm_access.roles[]` 또는 `resource_access.{client}.roles[]`

---

## BDD 테스트 연결 포인트

```python
# pytest-bdd step — 인증 Mock
@given("사용자가 analyst 역할로 로그인되어 있다")
def analyst_auth(client):
    # 테스트용 고정 JWT 사용 (실제 Keycloak 연동 불필요)
    client.headers["Authorization"] = "Bearer test-analyst-token"

# conftest.py — JWT 검증 Mock
@pytest.fixture(autouse=True)
def mock_jwt():
    with patch("app.core.security.get_current_user") as m:
        m.return_value = {"sub": "test-user", "realm_access": {"roles": ["analyst"]}}
        yield m
```

---

## 운영 필수 설정

| 항목 | 값 |
|------|-----|
| Access Token TTL | 5분 |
| Refresh Token TTL | 30분 |
| Refresh Token 단일 사용 | 활성화 |
| Brute Force Protection | 활성화 |
| SSL Required | `all` (운영) |

---

## 패턴 적용 체크리스트

> 이 표준에 정의된 패턴을 실제 코드가 따르는지 audit. 각 항목은 yes/no.
> 식별자(`S04-NN-MM`)는 통합 인덱스(`specs/_methodology/CHECKLIST.md`)에서 참조.

### 카테고리 1: 인증 흐름
- [ ] S04-01-01: 브라우저가 PKCE 흐름으로 Keycloak 인증하는가
- [ ] S04-01-02: Access Token이 JWT(5분 TTL)인가
- [ ] S04-01-03: Refresh Token이 HttpOnly Cookie로 저장되는가
- [ ] S04-01-04: TLS 1.3에서만 토큰이 전송되는가

### 카테고리 2: JWT 검증
- [ ] S04-02-01: 백엔드가 Keycloak JWKS로 서명 검증하는가
- [ ] S04-02-02: JWKS 캐시 TTL(약 1시간)이 설정됐는가
- [ ] S04-02-03: 만료 토큰이 즉시 거부되는가
- [ ] S04-02-04: 알고리즘이 RS256 또는 동등 비대칭 방식인가

### 카테고리 3: 인가
- [ ] S04-03-01: 역할 기반 접근(get_current_user, require_admin) 미들웨어가 적용되는가
- [ ] S04-03-02: 메서드 레벨 권한 체크가 있는가 (분석 GET·rerun POST 등 용도별)
- [ ] S04-03-03: 인증 미적용 endpoint(/health, /metrics)가 명시적으로 지정됐는가

### 카테고리 4: 보안 강화
- [ ] S04-04-01: Brute Force 방지가 Keycloak에서 활성화됐는가
- [ ] S04-04-02: 감사 로그(로그인·실패·권한 거부)가 기록되는가 (gov/04 연계)
