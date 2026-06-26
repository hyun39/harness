# Common Spec — Frontend

---

## 렌더링 방식 비교

| 방식 | 설명 | 적합한 상황 |
|------|------|------------|
| CSR (Client-Side Rendering) | JS가 브라우저에서 DOM 구성 | 인증 필요한 대시보드, 높은 상호작용 |
| SSR (Server-Side Rendering) | 서버가 HTML 완성 후 전송 | SEO 필요, 초기 로딩 속도 중요 |
| SSG (Static Site Generation) | 빌드 타임에 HTML 생성 | 콘텐츠 변경 드문 페이지 |
| Hybrid (Next.js 등) | 페이지별 CSR/SSR/SSG 선택 | 대형 앱, 페이지 성격이 다양할 때 |
| Flask Jinja2 | 서버 템플릿 렌더링 | 간단한 폼 앱, Python 백엔드 통합 |

---

## 컴포넌트 설계 원칙

### 단일 책임
- 컴포넌트 1개 = 역할 1개
- "그리고"로 역할을 연결하게 되면 분리 신호

### Props / State 분리

| 종류 | 정의 | 예시 |
|------|------|------|
| Props | 부모로부터 받는 불변 입력 | `items: string[]`, `onSubmit: fn` |
| Local State | 컴포넌트 내부 상태 | 폼 입력값, 드롭다운 열림 여부 |
| Global State | 여러 컴포넌트가 공유하는 상태 | 사용자 인증 정보, 테마 |

### 상태 끌어올리기(Lifting State Up)
- 두 컴포넌트가 같은 상태를 공유해야 하면 공통 부모로 이동
- 과도한 props drilling(3단계 이상) → Context API 또는 상태 관리 라이브러리 검토

---

## 상태 관리 선택 기준

| 도구 | 적합한 규모 | 특징 |
|------|-----------|------|
| `useState` / `useReducer` | 단일 컴포넌트~소형 앱 | 추가 의존성 없음 |
| Context API | 중형 앱, 전역 상태 단순 | 잦은 업데이트 시 리렌더링 주의 |
| Zustand | 중형~대형 앱 | 보일러플레이트 최소 |
| Redux Toolkit | 대형 앱, 복잡한 상태 | DevTools 강력, 설정 복잡 |

```typescript
// 상태 머신 패턴 (복잡한 비동기 흐름)
type Status = 'idle' | 'loading' | 'success' | 'error';

const [status, setStatus] = useState<Status>('idle');
const [data, setData] = useState<Result | null>(null);
const [error, setError] = useState<string | null>(null);
```

---

## API 클라이언트 패턴

```typescript
// 관심사 분리: API 호출 → 상태 갱신 분리
// api/icebreaker.ts
async function fetchResult(
  name: string,
  signal?: AbortSignal
): Promise<IceBreakerResponse> {
  const res = await fetch('/process', {
    method: 'POST',
    body: new FormData(/* ... */),
    signal,
  });
  if (!res.ok) throw new ApiError(res.status, await res.text());
  return res.json();
}

// 컴포넌트에서 AbortController로 취소 지원
useEffect(() => {
  const controller = new AbortController();
  fetchResult(name, controller.signal).then(setData).catch(setError);
  return () => controller.abort();
}, [name]);
```

---

## 에러 처리 계층

| 계층 | 처리 방법 |
|------|----------|
| API 오류 (4xx/5xx) | `try/catch` → 에러 상태 → 에러 배너 표시 |
| 네트워크 오류 | `catch(NetworkError)` → 재시도 안내 |
| 이미지 로딩 실패 | `<img onError>` → placeholder 이미지 교체 |
| 예기치 못한 런타임 오류 | React Error Boundary → 폴백 UI |

```tsx
// Error Boundary 사용 예시
<ErrorBoundary fallback={<ErrorFallback />}>
  <ResultSection data={data} />
</ErrorBoundary>
```

---

## 로딩 상태 처리

| 패턴 | 사용 시점 |
|------|----------|
| Spinner / Skeleton | 첫 로딩 또는 전체 교체 |
| Inline loader | 버튼 내부 (제출 중) |
| Optimistic UI | 즉각 피드백이 중요한 상호작용 |
| Suspense + lazy | 코드 스플리팅 + 청크 로딩 |

```tsx
// 로딩/에러/성공 조건부 렌더링 패턴
{status === 'loading' && <LoadingSpinner />}
{status === 'error'   && <ErrorBanner message={error} />}
{status === 'success' && <ResultView data={data} />}
```

---

## 접근성(Accessibility) 기준

| 항목 | 구현 |
|------|------|
| 키보드 내비게이션 | 모든 인터랙티브 요소 Tab 접근 가능 |
| ARIA 레이블 | 아이콘 버튼에 `aria-label`, 동적 콘텐츠에 `aria-live` |
| 색상 대비 | WCAG 2.1 AA 기준 (4.5:1 이상) |
| 폼 연결 | `<label htmlFor>` + `<input id>` 명시적 연결 |
| 스피너 | `role="status"` + `aria-label="로딩 중"` |

---

## 빌드 및 번들링

| 도구 | 특징 | 권장 상황 |
|------|------|----------|
| Vite | 빠른 HMR, ESM 네이티브 | React/Vue 신규 프로젝트 |
| Next.js | SSR/SSG 통합, 파일 기반 라우팅 | SEO 필요 또는 풀스택 |
| Parcel | 설정 없이 시작 | 프로토타입 |
| Webpack | 고도 커스터마이징 | 레거시 통합 |

**코드 스플리팅 원칙**: 라우트 단위 lazy import, 초기 번들 < 200KB (gzip 기준)

---

## 성능 최적화 체크리스트

- [ ] 이미지: `loading="lazy"`, WebP 포맷, `srcset` 반응형
- [ ] 리스트: 1000개 이상 → 가상화(`react-window`)
- [ ] 불필요한 리렌더링: `React.memo`, `useMemo`, `useCallback` (측정 후 적용)
- [ ] 번들 분석: `vite-bundle-visualizer` 또는 `webpack-bundle-analyzer`
- [ ] 네트워크: API 응답 캐싱 (`stale-while-revalidate` 전략)

---

## 미결 기술 과제

- [ ] 컴포넌트 테스트 도구 선택 — Vitest + Testing Library vs Playwright CT
- [ ] 디자인 토큰 관리 방식 — CSS 변수 vs Tailwind 설정
- [ ] 폼 라이브러리 평가 — React Hook Form vs 네이티브 `useState`
- [ ] 번들 사이즈 예산(Budget) 수치 확정
