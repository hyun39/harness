# Common Spec — Backend (Spring Boot)

---

## 프레임워크 특성

| 항목 | 내용 |
|------|------|
| 언어 | Java 21 |
| 서버 | Embedded Tomcat (기본) / Netty (WebFlux) |
| 동시성 모델 | Virtual Threads (Loom, Java 21) 또는 Reactive (WebFlux) |
| 타입 시스템 | Jakarta Bean Validation — `@Valid`, `@NotBlank` |
| API 문서 | SpringDoc OpenAPI → `/swagger-ui/index.html` 자동 생성 |
| DI 컨테이너 | Spring IoC — `@Component`, `@Service`, `@Repository` |

---

## 프로젝트 구조

```
src/main/java/com/icebreaker/
├── IceBreakerApplication.java
├── controller/
│   └── ProcessController.java      ← @RestController, 입력 검증
├── service/
│   └── IceBreakerService.java      ← @Service, 파이프라인 조합
├── client/                         ← 외부 API 클라이언트
│   ├── LinkedInClient.java
│   └── TwitterClient.java
├── dto/                            ← 요청·응답 record
│   ├── ProcessRequest.java
│   └── ProcessResponse.java
├── exception/
│   ├── AppException.java
│   └── GlobalExceptionHandler.java ← @RestControllerAdvice
└── config/
    ├── AppConfig.java              ← @Configuration 빈 등록
    └── WebClientConfig.java        ← WebClient 빈 설정

src/main/resources/
├── application.yml
├── application-local.yml
└── application-prod.yml
```

---

## 컨트롤러 패턴

```java
// controller/ProcessController.java
@RestController
@RequestMapping("/v1")
@RequiredArgsConstructor
public class ProcessController {

    private final IceBreakerService service;

    @PostMapping("/process")
    public ResponseEntity<ProcessResponse> process(
            @Valid @RequestBody ProcessRequest request) {
        return ResponseEntity.ok(service.run(request.name()));
    }
}
```

- `@Valid` — 진입 시 Bean Validation 자동 실행
- `@RequiredArgsConstructor` (Lombok) — 생성자 주입
- `ResponseEntity` — HTTP 상태코드 명시적 제어

---

## DTO (record)

```java
// dto/ProcessRequest.java
public record ProcessRequest(
    @NotBlank(message = "name은 필수입니다.")
    @Size(max = 100)
    String name
) {}

// dto/ProcessResponse.java
public record ProcessResponse(
    SummaryAndFacts summaryAndFacts,
    Interests interests,
    IceBreakers iceBreakers,
    @Nullable String pictureUrl
) {}

public record SummaryAndFacts(String summary, List<String> facts) {}
public record Interests(List<String> topicsOfInterest) {}
public record IceBreakers(List<String> iceBreakers) {}
```

- `record` — 불변 DTO, `equals`/`hashCode`/`toString` 자동 생성
- JSON 네이밍: Jackson 기본 camelCase → 프론트 snake_case 필요 시 `@JsonNaming` 또는 `@JsonProperty`

---

## 설정 관리 (application.yml)

```yaml
# application.yml
spring:
  application:
    name: ice-breaker

app:
  openai-api-key: ${OPENAI_API_KEY}
  scrapin-api-key: ${SCRAPIN_API_KEY}
  tavily-api-key: ${TAVILY_API_KEY}
  linkedin-mock: ${LINKEDIN_MOCK:false}

logging:
  level:
    com.icebreaker: INFO
  pattern:
    console: '{"timestamp":"%d","level":"%p","logger":"%c","message":"%m"}%n'
```

```java
// config/AppProperties.java
@ConfigurationProperties(prefix = "app")
public record AppProperties(
    String openaiApiKey,
    String scrapinApiKey,
    String tavilyApiKey,
    boolean linkedinMock
) {}
```

- `@ConfigurationProperties` — 타입 안전 바인딩, 누락 시 컨텍스트 로드 실패
- 프로파일별 오버라이드: `application-local.yml`, `application-prod.yml`

---

## 의존성 주입

```java
// @Service에 생성자 주입 (Lombok)
@Service
@RequiredArgsConstructor
public class IceBreakerService {

    private final LinkedInClient linkedInClient;
    private final TwitterClient twitterClient;
    private final SummaryChain summaryChain;

    public ProcessResponse run(String name) {
        var linkedInUrl  = linkedInClient.lookupUrl(name);
        var linkedInData = linkedInClient.fetchProfile(linkedInUrl);
        // ...
    }
}
```

- 필드 주입(`@Autowired`) 사용 금지 — 테스트 어려움
- 생성자 주입 → `final` 필드 + Lombok `@RequiredArgsConstructor`

---

## 비동기 / 동시성

### Virtual Threads (Java 21, 권장)
```yaml
# application.yml — Tomcat Virtual Thread 활성화
spring:
  threads:
    virtual:
      enabled: true
```
- 블로킹 I/O (RestClient, JDBC)를 Virtual Thread에서 실행 → 스레드 풀 고갈 없음
- 기존 동기 코드 변경 없이 적용

### CompletableFuture (병렬 외부 호출)
```java
var linkedInFuture = CompletableFuture.supplyAsync(
    () -> linkedInClient.fetchProfile(url), executor);
var tweetsFuture = CompletableFuture.supplyAsync(
    () -> twitterClient.fetchMock(username), executor);

CompletableFuture.allOf(linkedInFuture, tweetsFuture).join();
var linkedInData = linkedInFuture.get();
var tweets       = tweetsFuture.get();
```

### WebFlux (완전 반응형, 선택적)
- `Mono<T>` / `Flux<T>` 반환 타입
- LangChain4j Reactive 지원 여부 확인 후 도입 결정

---

## 외부 HTTP 클라이언트 (RestClient / WebClient)

```java
// config/WebClientConfig.java
@Configuration
public class WebClientConfig {

    @Bean
    public RestClient scrapinRestClient(AppProperties props) {
        return RestClient.builder()
            .baseUrl("https://api.scrapin.io")
            .defaultHeader("apikey", props.scrapinApiKey())
            .build();
    }
}

// client/LinkedInClient.java
@Component
@RequiredArgsConstructor
public class LinkedInClient {

    private final RestClient scrapinRestClient;

    @Retryable(retryFor = HttpServerErrorException.class,
               maxAttempts = 3,
               backoff = @Backoff(delay = 1000, multiplier = 2))
    public LinkedInData fetchProfile(String linkedInUrl) {
        return scrapinRestClient.get()
            .uri("/enrichment/profile?linkedInUrl={url}", linkedInUrl)
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError, (req, res) -> {
                throw new ExternalApiException("LinkedIn API 오류: " + res.getStatusCode());
            })
            .body(LinkedInData.class);
    }
}
```

- `RestClient` (Spring 6.1+) — 동기 HTTP 클라이언트 (Virtual Thread와 조합)
- `@Retryable` (spring-retry) — 지수 백오프 재시도

---

## 에러 처리

```java
// exception/AppException.java
public class AppException extends RuntimeException {
    private final int statusCode;
    private final String code;

    public AppException(int statusCode, String code, String message) {
        super(message);
        this.statusCode = statusCode;
        this.code = code;
    }
}

public class NotFoundException extends AppException {
    public NotFoundException(String message) {
        super(404, "NOT_FOUND", message);
    }
}

// exception/GlobalExceptionHandler.java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(AppException.class)
    public ResponseEntity<ErrorResponse> handleAppException(AppException ex) {
        return ResponseEntity
            .status(ex.getStatusCode())
            .body(new ErrorResponse(ex.getCode(), ex.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(
            MethodArgumentNotValidException ex) {
        var details = ex.getBindingResult().getFieldErrors().stream()
            .map(e -> new FieldError(e.getField(), e.getDefaultMessage()))
            .toList();
        return ResponseEntity.badRequest()
            .body(new ErrorResponse("VALIDATION_ERROR", "입력값 오류", details));
    }
}
```

---

## CORS 설정

```java
@Configuration
public class WebConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/v1/**")
            .allowedOrigins("http://localhost:5173")
            .allowedMethods("GET", "POST")
            .maxAge(3600);
    }
}
```

---

## 로깅 (Logback + structlog)

```java
// MDC로 요청 ID 전파
@Component
public class RequestIdFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain)
            throws ServletException, IOException {
        String requestId = UUID.randomUUID().toString();
        MDC.put("requestId", requestId);
        response.setHeader("X-Request-Id", requestId);
        try {
            chain.doFilter(request, response);
        } finally {
            MDC.clear();
        }
    }
}
```

`application.yml`의 log pattern에 `%X{requestId}` 포함 → 요청별 로그 추적

---

## 테스트

```java
// 단위 테스트 — Mockito
@ExtendWith(MockitoExtension.class)
class IceBreakerServiceTest {

    @Mock LinkedInClient linkedInClient;
    @Mock TwitterClient twitterClient;
    @InjectMocks IceBreakerService service;

    @Test
    void run_success() {
        when(linkedInClient.lookupUrl("Harrison Chase"))
            .thenReturn("https://linkedin.com/in/harrison-chase");
        // ...
        var result = service.run("Harrison Chase");
        assertThat(result.summaryAndFacts().summary()).isNotBlank();
    }
}

// 통합 테스트 — @SpringBootTest + TestContainers
@SpringBootTest(webEnvironment = RANDOM_PORT)
@Testcontainers
class ProcessControllerTest {

    @Container
    static PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:15");

    @Test
    void process_returns_200(@Autowired TestRestTemplate rest) {
        var response = rest.postForEntity(
            "/v1/process",
            new ProcessRequest("Harrison Chase"),
            ProcessResponse.class
        );
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }
}
```

| 레벨 | 도구 | 비고 |
|------|------|------|
| 단위 | JUnit 5 + Mockito | Service, 도메인 로직 |
| 슬라이스 | `@WebMvcTest` | Controller 검증만 격리 |
| 통합 | `@SpringBootTest` + Testcontainers | 실제 DB 포함 |

---

## 미결 기술 과제

- [ ] LangChain4j 버전 확정 — ReAct 에이전트 동기·비동기 지원 범위 검증
- [ ] Virtual Threads vs WebFlux 선택 기준 수립 (LangChain4j 호환성 확인)
- [ ] Spring Cache + Redis 적용 — `@Cacheable` 로 LLM 결과 캐싱
- [ ] `@Retryable` → Resilience4j Circuit Breaker 전환 시점 정의
- [ ] OpenTelemetry 연동 (`opentelemetry-spring-boot-starter`)
