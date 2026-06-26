# BDD-03 — Spring Boot Cucumber 구현 가이드

> **목적**: `.feature` 파일의 Step을 Spring Boot + Cucumber로 구현하는 패턴  
> **원본 참조**: `enterprise/01.03_std_executable_specification.md`, `common/backend_springboot.md`

---

## 의존성 (build.gradle.kts)

```kotlin
dependencies {
    // Cucumber
    testImplementation("io.cucumber:cucumber-java:7.+")
    testImplementation("io.cucumber:cucumber-spring:7.+")
    testImplementation("io.cucumber:cucumber-junit-platform-engine:7.+")

    // Spring Test
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.testcontainers:postgresql")
    testImplementation("org.testcontainers:junit-jupiter")
}
```

---

## 프로젝트 구조

```
src/test/
├── java/com/icebreaker/bdd/
│   ├── CucumberRunnerTest.java      ← JUnit 5 진입점
│   ├── CucumberSpringConfig.java    ← Spring 컨텍스트 설정
│   ├── steps/
│   │   └── TrendAnalysisSteps.java  ← Step 구현
│   └── support/
│       ├── TestDataSeeder.java      ← 테스트 데이터 적재
│       └── ResponseHolder.java      ← Scenario 내 응답 공유
└── resources/
    └── features/
        └── analysis/
            └── trend_analysis.feature
```

---

## CucumberRunnerTest.java

```java
@Suite
@IncludeEngines("cucumber")
@ConfigurationParameter(
    key = GLUE_PROPERTY_NAME,
    value = "com.icebreaker.bdd"
)
@ConfigurationParameter(
    key = FEATURES_PROPERTY_NAME,
    value = "src/test/resources/features"
)
@ConfigurationParameter(
    key = PLUGIN_PROPERTY_NAME,
    value = "pretty, junit:target/cucumber-reports/cucumber.xml"
)
public class CucumberRunnerTest {}
```

---

## CucumberSpringConfig.java

```java
@CucumberContextConfiguration
@SpringBootTest(webEnvironment = RANDOM_PORT)
@Testcontainers
public class CucumberSpringConfig {

    @Container
    static PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:15");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }
}
```

---

## Step 구현 패턴

```java
// steps/TrendAnalysisSteps.java
@Component
public class TrendAnalysisSteps {

    @Autowired private TestRestTemplate restTemplate;
    @Autowired private TestDataSeeder seeder;
    @Autowired private ResponseHolder responseHolder;

    // --- Given ---

    @Given("{string} 거래일의 데이터 수집이 완료된 상태이고")
    public void pipelineCompleted(String date) {
        seeder.seedMartData(LocalDate.parse(date));
        seeder.seedPipelineStatus(LocalDate.parse(date), "completed");
    }

    @Given("사용자가 분석가 권한으로 로그인되어 있다")
    public void analystLoggedIn() {
        responseHolder.setAuthHeader("Bearer test-analyst-token");
    }

    // --- When ---

    @When("{string} 트렌드 분석을 조회하면")
    public void callTrendAnalysis(String date) {
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", responseHolder.getAuthHeader());

        ResponseEntity<TrendAnalysisResponse> response = restTemplate.exchange(
            "/v1/analyses/trend?trade_date=" + date,
            HttpMethod.GET,
            new HttpEntity<>(headers),
            TrendAnalysisResponse.class
        );
        responseHolder.setResponse(response);
    }

    // --- Then ---

    @Then("{int}개 Sector의 분석 결과가 반환된다")
    public void checkSectorCount(int count) {
        assertThat(responseHolder.getResponse().getStatusCode())
            .isEqualTo(HttpStatus.OK);
        assertThat(responseHolder.getBody().analyses())
            .hasSize(count);
    }

    @Then("응답 코드는 {int}이어야 한다")
    public void checkStatusCode(int code) {
        assertThat(responseHolder.getResponse().getStatusCodeValue())
            .isEqualTo(code);
    }

    @Then("에러 코드는 {string}이어야 한다")
    public void checkErrorCode(String errorCode) {
        assertThat(responseHolder.getErrorBody().error().code())
            .isEqualTo(errorCode);
    }
}
```

---

## ResponseHolder (Scenario 내 상태 공유)

```java
@Component
@ScenarioScope                        // Scenario 단위 빈 생성
public class ResponseHolder {

    private ResponseEntity<?> response;
    private String authHeader;

    public void setResponse(ResponseEntity<?> response) {
        this.response = response;
    }

    public <T> T getBody(Class<T> type) {
        return type.cast(response.getBody());
    }

    // getter/setter...
}
```

---

## Mock LLM 빈 교체 (외부 LLM 격리)

```java
// CucumberSpringConfig.java 에 추가
@MockBean SummaryChain summaryChain;
@MockBean InterestsChain interestsChain;

@Before  // Cucumber @Before Hook
public void setupMocks() {
    given(summaryChain.invoke(any()))
        .willReturn(new Summary("Test summary", List.of("fact1", "fact2")));
}
```

---

## CI 연동

```yaml
# .github/workflows/ci.yml
- name: BDD Tests (Cucumber)
  run: ./gradlew cucumber --no-daemon
  
- name: Upload Cucumber Report
  uses: actions/upload-artifact@v4
  with:
    name: cucumber-report
    path: target/cucumber-reports/
```

---

## 공통 Step 재사용 패턴

공통 인증·헬스체크 Step은 별도 파일로 분리한다.

```java
// steps/CommonSteps.java
public class CommonSteps {

    @Given("시스템이 정상 동작 중이다")
    public void systemIsRunning() {
        // 헬스체크 확인
    }

    @Given("사용자가 {string} 역할로 로그인되어 있다")
    public void userLoggedInWithRole(String role) {
        // 역할별 토큰 설정
    }
}
```
