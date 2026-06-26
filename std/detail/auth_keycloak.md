# Common Spec — 통합 인증·인가 (Keycloak)

---

## Keycloak 구성 요소

```
Keycloak Server
  └─ Realm (서비스 단위 격리 공간)
       ├─ Client (앱 등록 단위)
       │    ├─ frontend-app   (Public Client — PKCE)
       │    └─ backend-api    (Bearer-only Client)
       ├─ User (사용자 계정)
       ├─ Role (권한 단위)
       └─ Group (Role 묶음)
```

| 용어 | 설명 |
|------|------|
| Realm | 독립된 인증 도메인. 서비스별 1개 권장 |
| Client | 인증을 위임하는 앱 단위 (프론트, 백엔드 각각 등록) |
| Access Token | JWT — 요청마다 `Authorization: Bearer <token>` 전송 |
| Refresh Token | Access Token 재발급용. 서버에 저장하지 않음 |
| ID Token | 사용자 정보 포함 JWT (OIDC) |

---

## 인증 흐름 선택

| 흐름 | 적합한 클라이언트 | 특징 |
|------|----------------|------|
| **Authorization Code + PKCE** | SPA, 모바일 | 권장. 브라우저에 secret 노출 없음 |
| Client Credentials | 서버 간 M2M | 사용자 없는 백엔드·배치 |
| Resource Owner Password | 레거시 통합만 | 비권장 — Keycloak 22+ 기본 비활성 |
| Device Authorization | IoT, CLI | 브라우저 없는 환경 |

---

## Authorization Code + PKCE 흐름

```
[브라우저]
  1. /login → Keycloak 로그인 페이지 리다이렉트
              (code_challenge = SHA256(code_verifier) 포함)
  2. 사용자 로그인
  3. Keycloak → /callback?code=AUTH_CODE 리다이렉트
  4. 브라우저 → Keycloak: code + code_verifier 교환
  5. Keycloak → Access Token + Refresh Token 반환
  6. 브라우저 → Backend API: Authorization: Bearer <access_token>
  7. Backend: Keycloak 공개키로 JWT 서명 검증 (네트워크 호출 없음)
```

---

## JWT 토큰 구조

```json
// Access Token 페이로드 (주요 클레임)
{
  "sub":                "user-uuid",
  "preferred_username": "john.doe",
  "email":              "john@example.com",
  "realm_access": {
    "roles": ["user", "admin"]
  },
  "resource_access": {
    "backend-api": {
      "roles": ["read:profiles", "write:profiles"]
    }
  },
  "exp": 1746000000,
  "iat": 1745996400
}
```

| 클레임 | 설명 |
|--------|------|
| `sub` | 사용자 고유 ID — DB FK로 사용 |
| `realm_access.roles` | Realm 전역 역할 |
| `resource_access.<client>.roles` | 클라이언트별 역할 (세밀한 권한 제어) |
| `exp` | 만료 시각 — 검증 필수 |

---

## 백엔드 토큰 검증

### FastAPI

```python
# core/security.py
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer
from jose import jwt, JWTError
import httpx

bearer_scheme = HTTPBearer()

async def get_jwks() -> dict:
    # Keycloak 공개키 — 앱 시작 시 캐싱, TTL 1시간
    url = f"{settings.keycloak_url}/realms/{settings.realm}/protocol/openid-connect/certs"
    async with httpx.AsyncClient() as client:
        return (await client.get(url)).json()

async def get_current_user(
    token: str = Depends(bearer_scheme),
    jwks: dict = Depends(get_jwks),
) -> dict:
    try:
        payload = jwt.decode(
            token.credentials,
            jwks,
            algorithms=["RS256"],
            audience=settings.client_id,
        )
        return payload
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="유효하지 않은 토큰")

# 엔드포인트에 적용
@router.get("/profile")
async def get_profile(user: dict = Depends(get_current_user)):
    return {"user_id": user["sub"]}
```

### Spring Boot

```java
// build.gradle
implementation 'org.springframework.boot:spring-boot-starter-oauth2-resource-server'

// application.yml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${KEYCLOAK_URL}/realms/${REALM}
          # JWKS URI 자동 탐색 — issuer-uri/.well-known/openid-configuration

// SecurityConfig.java
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health").permitAll()
                .anyRequest().authenticated()
            )
            .sessionManagement(s -> s.sessionCreationPolicy(STATELESS))
            .build();
    }

    @Bean
    public JwtAuthenticationConverter jwtAuthenticationConverter() {
        // realm_access.roles → Spring Security GrantedAuthority 변환
        var converter = new KeycloakRoleConverter();
        var jwtConverter = new JwtAuthenticationConverter();
        jwtConverter.setJwtGrantedAuthoritiesConverter(converter);
        return jwtConverter;
    }
}

// 메서드 레벨 권한 제어
@PreAuthorize("hasRole('admin')")
public void deleteProfile(String id) { ... }
```

---

## 역할(Role) 설계 패턴

```
Realm Role (전역)          Resource Role (클라이언트별)
  ├─ user                    ├─ read:profiles
  ├─ admin                   ├─ write:profiles
  └─ service-account         └─ delete:profiles
```

| 패턴 | 설명 | 적합한 상황 |
|------|------|------------|
| Realm Role | Realm 전역 적용 | 전체 서비스 공통 권한 |
| Client Role | 특정 클라이언트에만 적용 | 마이크로서비스별 세밀한 권한 |
| Composite Role | 역할 묶음 | 관리 편의 — 하나로 여러 역할 부여 |

---

## 토큰 갱신 전략

```
Access Token 만료 전 갱신 (Silent Refresh):

  [프론트]
    만료 N초 전 → POST /token (grant_type=refresh_token)
    → 새 Access Token + Refresh Token 수신
    → 메모리에 저장 (localStorage 지양 — XSS 위험)

  Refresh Token 만료 시:
    → 사용자 재로그인 유도
```

| 토큰 | 권장 저장 위치 | 이유 |
|------|--------------|------|
| Access Token | JS 메모리 변수 | 짧은 수명, 빠른 접근 |
| Refresh Token | HttpOnly Cookie | XSS 방어 — JS 접근 불가 |

---

## 서버 간 인증 (Client Credentials)

```python
# 백엔드 → 다른 내부 서비스 호출 시
async def get_service_token() -> str:
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{settings.keycloak_url}/realms/{settings.realm}"
            "/protocol/openid-connect/token",
            data={
                "grant_type":    "client_credentials",
                "client_id":     settings.service_client_id,
                "client_secret": settings.service_client_secret,
            },
        )
    return response.json()["access_token"]
```

---

## Keycloak 운영 설정

| 항목 | 권장값 | 근거 |
|------|--------|------|
| Access Token 유효기간 | 5분 | 탈취 피해 최소화 |
| Refresh Token 유효기간 | 30분 (세션 유지) | 사용자 경험 균형 |
| Refresh Token 단일 사용 | 활성화 | 리플레이 공격 방지 |
| Brute Force Protection | 활성화 | 로그인 실패 N회 → 계정 잠금 |
| SSL Required | `all` (운영) | HTTP 토큰 전송 차단 |
| JWKS 캐시 TTL | 1시간 | 잦은 키 조회 방지 |

---

## 미결 기술 과제

- [ ] JWKS 캐시 갱신 전략 — 키 롤링 시 캐시 무효화 처리
- [ ] Keycloak HA 구성 — DB(PostgreSQL) 기반 클러스터링
- [ ] 소셜 로그인 연동 — Keycloak Identity Provider (Google, GitHub)
- [ ] Fine-Grained Authorization — UMA 2.0 기반 리소스 단위 권한
- [ ] Service Mesh 환경 — mTLS와 JWT 검증 중복 제거 전략
