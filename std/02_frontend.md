# STD-02 — 프론트엔드 구현 표준 (React)

> 전체 상세: [`detail/frontend.md`](./detail/frontend.md)

---

## 상태 머신 패턴 (비동기 API 호출)

```typescript
type Status = 'idle' | 'loading' | 'success' | 'error';

const [status, setStatus]   = useState<Status>('idle');
const [data, setData]       = useState<Result | null>(null);
const [error, setError]     = useState<string | null>(null);

// 렌더링
{status === 'loading' && <LoadingSpinner />}
{status === 'error'   && <ErrorBanner message={error} />}
{status === 'success' && <ResultView data={data} />}
```

---

## API 클라이언트 패턴

```typescript
// api/icebreaker.ts — 관심사 분리
async function fetchAnalysis(
  name: string,
  signal?: AbortSignal,          // 취소 지원
): Promise<AnalysisResponse> {
  const res = await fetch('/v1/analyses', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name }),
    signal,
  });
  if (!res.ok) throw new ApiError(res.status, await res.text());
  return res.json();
}

// 컴포넌트에서 AbortController 사용
useEffect(() => {
  const controller = new AbortController();
  fetchAnalysis(name, controller.signal)
    .then(setData)
    .catch(err => { if (!err.name.includes('Abort')) setError(err) });
  return () => controller.abort();
}, [name]);
```

---

## 타입 정의

```typescript
// types/analysis.ts
interface AnalysisResponse {
  summary_and_facts: { summary: string; facts: string[] };
  interests:         { topics_of_interest: string[] };
  ice_breakers:      { ice_breakers: string[] };
  picture_url:       string | null;
}
```

---

## 에러 처리 계층

| 계층 | 처리 |
|------|------|
| API 오류 (4xx/5xx) | `catch` → `status: 'error'` → ErrorBanner |
| 네트워크 오류 | `catch(NetworkError)` → 재시도 안내 |
| 이미지 로딩 실패 | `<img onError>` → placeholder |
| 런타임 오류 | `<ErrorBoundary>` → 폴백 UI |

---

## 접근성 필수 항목

```tsx
// 스피너
<div role="status" aria-label="로딩 중">
  <LoadingSpinner />
</div>

// 폼 연결
<label htmlFor="name-input">이름</label>
<input id="name-input" name="name" ... />

// 에러 알림
<div role="alert" aria-live="polite">
  {error}
</div>
```

---

## BDD E2E 연결 (Playwright)

```typescript
// tests/e2e/analysis.spec.ts
test('이름 입력 후 결과가 표시된다', async ({ page }) => {
  await page.goto('/');
  await page.fill('input[name="name"]', 'Harrison Chase');
  await page.click('button[type="submit"]');

  await expect(page.locator('[role="status"]')).toBeVisible();         // 스피너
  await expect(page.locator('#result')).toBeVisible({ timeout: 30000 }); // 결과
  await expect(page.locator('#summary')).not.toBeEmpty();
});
```

---

## 패턴 적용 체크리스트

> 이 표준에 정의된 패턴을 실제 코드가 따르는지 audit. 각 항목은 yes/no.
> 식별자(`S02-NN-MM`)는 통합 인덱스(`specs/_methodology/CHECKLIST.md`)에서 참조.

### 카테고리 1: 상태 머신
- [ ] S02-01-01: 비동기 API 호출이 4단계(idle/loading/success/error) 상태머신으로 표현되는가
- [ ] S02-01-02: 각 상태별 UI 컴포넌트(LoadingSpinner, ErrorBanner, ResultView)가 분기되는가
- [ ] S02-01-03: 에러 메시지가 사용자 친화적으로 표시되는가

### 카테고리 2: API 클라이언트
- [ ] S02-02-01: API 호출이 단일 client 모듈에 집약됐는가
- [ ] S02-02-02: BASE_URL·USE_MOCK 등이 환경변수(`VITE_*`)로 주입되는가
- [ ] S02-02-03: mock 데이터가 client 안에서 분기되어 테스트 격리 가능한가
- [ ] S02-02-04: fetch 에러가 일관되게 처리되는가 (401/404/500 등)

### 카테고리 3: 컴포넌트 분리
- [ ] S02-03-01: pages / components / hooks / api / types 디렉터리가 분리됐는가
- [ ] S02-03-02: 비즈니스 로직이 hooks에 집약되고 view 컴포넌트에 누수되지 않는가
- [ ] S02-03-03: TypeScript 타입이 api/types에 정의되고 컴포넌트가 그 타입에 의존하는가

### 카테고리 4: 빌드·테스트
- [ ] S02-04-01: npm run build가 type-check 통과하는가
- [ ] S02-04-02: E2E 테스트(Playwright)가 USE_MOCK=true 모드로 실행되는가
