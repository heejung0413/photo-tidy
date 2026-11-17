# 웹 타임라인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 사진 파일을 올리면 지도·날짜별 머문 곳 목록·공유 이미지를 만드는 웹 페이지를 `web/` 폴더에 만든다.

**Architecture:** 서버 없는 정적 사이트. 판단 규칙은 `web/src/core/`(브라우저 기능 없음)에 두고 Swift `PhotoTidyCore`의 로직과 테스트를 TypeScript로 옮긴다. 브라우저·외부 서비스와 이야기하는 코드는 `web/src/services/`, 화면은 `web/src/components/`. 아이폰 앱 코드는 건드리지 않는다.

**Tech Stack:** Vite, React, TypeScript, Leaflet(오픈스트리트맵), exifr, Nominatim, Vitest, Playwright(시스템 크롬 사용).

**설계 문서:** `docs/superpowers/specs/2026-11-17-web-timeline-design.md`

모든 명령은 `web/` 기준. 로직은 테스트를 먼저 쓰고(실패 확인) 구현한다. 이 문서는 파일·함수 모양·테스트 목록까지 정하고, 코드 본문은 실행 단계에서 테스트와 함께 쓴다(이전 계획 문서들과 달리 전체 코드를 미리 싣지 않았다. 옮겨 올 원본이 `PhotoTidyCore`에 이미 있기 때문이다).

## Swift와 달라지는 표현

| Swift | TypeScript |
| --- | --- |
| `Date` | 숫자(1970년부터의 밀리초). 비교와 테스트가 쉽다 |
| `TimelineDay.day: Date`(그날 0시) | `day: string`(`"2026-11-14"`). 시간대 이름으로 계산한다 |
| `Calendar` 인자 | `timeZone: string`(`"Asia/Seoul"`), 기본값은 브라우저 시간대 |
| `struct`의 계산 속성(`stop.id`) | 함수(`stopId(stop)`) |
| `mutating func rename` | 새 값을 돌려주는 함수(React 상태에 넣기 위해) |
| `CustomPlaceNames`의 옛 저장 형식 읽기 | 옮기지 않는다(웹에는 옛 형식이 없다) |

---

### Task 1: 뼈대

**Files:** Create `web/`(Vite `react-ts` 템플릿), `web/vitest` 설정, 루트 `.gitignore`에 `web/node_modules`·`web/dist`·`web/test-results`·`web/playwright-report`.

- [ ] `npm create vite@latest web -- --template react-ts`, `npm install`
- [ ] `npm install leaflet exifr`, `npm install -D vitest @types/leaflet @playwright/test`
- [ ] 템플릿 예제(로고, 카운터, 기본 CSS)를 지우고 빈 `App`으로
- [ ] `package.json` scripts: `dev`, `build`, `test`(vitest run), `e2e`(playwright test)
- [ ] `npm run build`, `npm test`(테스트 0개) 통과 확인 후 커밋

### Task 2: 머문 곳 만들기 (`core/types.ts`, `core/tuning.ts`, `core/timeline.ts`)

```ts
export interface Coordinate { latitude: number; longitude: number }
export interface TimelinePhoto { id: string; takenAt: number; coordinate: Coordinate | null }
export interface TimelineStop { photos: TimelinePhoto[]; center: Coordinate | null }
export interface TimelineDay { day: string; stops: TimelineStop[] }
export const stopId, stopStart, stopEnd, dayRoute
export function distance(a, b): number
export function stops(photos, radius = Tuning.stopRadius): TimelineStop[]
export function dayKey(ms, timeZone): string
export function days(photos, timeZone = 브라우저 시간대, radius): TimelineDay[]
```

- [ ] `timeline.test.ts`: `TimelineBuilderTests.swift`의 18개를 옮긴다(거리, 반경 안팎, 되돌아오기, 위치 없는 사진, 정렬, 날짜 나누기, 시간대, 경계값, 평균 중심, 경로). 실패 확인
- [ ] 구현, 통과 확인, 커밋

### Task 3: 글자와 캐시 열쇠 (`core/timelineText.ts`, `core/placeKey.ts`)

```ts
export function timeRange(stop, locale?, timeZone?): string      // "오전 9:10" 또는 "오전 9:10–오전 11:20"
export function period(firstDay, lastDay, locale?): string        // 날짜 하나 또는 "첫날 – 마지막 날"
export function dayLabel(day, locale?, withYear?): string         // "11월 14일 (토)"
export function placeKey(coordinate): string                      // "37.545,127.056"
```

- [ ] `TimelineTextTests.swift` 6개 + `dayLabel` 2개 + `placeKey` 1개. 실패 확인 → 구현 → 커밋

### Task 4: 이름 요청 줄 세우기 (`core/placeNameLookup.ts`)

```ts
export class PlaceNameLookup {
  constructor(options: {
    cache: Record<string, string>
    lookup: (c: Coordinate) => Promise<string | null>
    onChange?: (cache: Record<string, string>) => void
    minInterval?: number            // 요청 시작 사이 최소 간격(ms). 기본 0
    now?: () => number
    sleep?: (ms: number) => Promise<void>
  })
  cachedName(c): string | null
  name(c): Promise<string | null>
}
```

- [ ] `PlaceNameLookupTests.swift` 5개 + 최소 간격 2개(연속 요청 사이를 기다린다 / 캐시에 있으면 기다리지 않는다). 가짜 시계 사용. 실패 확인 → 구현 → 커밋

### Task 5: 직접 붙인 이름 (`core/customNames.ts`)

```ts
export interface NameEntry { photoIDs: string[]; coordinate: Coordinate | null; name: string | null }
export class CustomPlaceNames {
  constructor(entries?: NameEntry[])
  readonly entries: NameEntry[]
  name(stop, radius?): string | null
  rename(stop, text, radius?): CustomPlaceNames
}
```

- [ ] `PlaceNamesTests.swift` 중 이름 규칙 14개와 JSON 왕복 1개(옛 형식·파일 테스트 제외). 실패 확인 → 구현 → 커밋

### Task 6: 공유 내용 (`core/shareOutline.ts`)

```ts
export function makeShareOutline(days, options: { maxStops; thumbnailsPerStop; title: (stop) => string }): ShareOutline
export function retitled(outline, title: (stop) => string | null): ShareOutline
```

- [ ] `ShareOutlineTests.swift` 9개. 실패 확인 → 구현 → 커밋

### Task 7: 지도 계산 (`core/mercator.ts`)

```ts
export function project(c: Coordinate, zoom: number): { x: number; y: number }   // 256px 타일 기준 세계 픽셀
export function fitView(coords, width, height, padding, maxZoom): { center: Coordinate; zoom: number }
export function tilesFor(center, zoom, width, height): { x; y; z; left; top }[]
```

- [ ] 테스트: 적도·본초자오선의 투영값, 줌이 1 오르면 픽셀이 2배, 좌표 하나면 `maxZoom`, 모든 좌표가 여백 안에 들어가는 가장 큰 줌, 타일 목록이 화면을 덮고 범위를 벗어난 타일은 뺀다. 실패 확인 → 구현 → 커밋

### Task 8: 장소 이름 서비스와 저장 (`core/pickPlaceName.ts`, `services/nominatim.ts`, `services/storage.ts`)

```ts
export function pickPlaceName(json: unknown): string | null   // 동 → 구 → 시 → 이름 순
export async function reverseGeocode(c: Coordinate): Promise<string | null>
export function loadJSON<T>(key, fallback): T ; export function saveJSON(key, value): void   // 실패해도 던지지 않는다
```

- [ ] `pickPlaceName` 테스트(동이 있으면 동, 없으면 다음 단계, 주소가 없으면 null, 이상한 값이면 null). 실패 확인 → 구현
- [ ] `nominatim.ts`, `storage.ts` 구현(네트워크·`localStorage`라 화면 테스트에서 확인) → 커밋

### Task 9: 사진 읽기 (`services/readPhoto.ts`)

```ts
export interface ReadResult { photo: TimelinePhoto; usedFileTime: boolean }
export function photoId(file: File): string                  // "이름|크기|수정시각"
export async function readPhoto(file: File): Promise<ReadResult | null>   // 사진이 아니거나 못 읽으면 null
```

- [ ] `swift scripts/make-timeline-samples.swift web/e2e/fixtures`로 샘플 6장을 만들어 커밋
- [ ] 테스트(Vitest, 노드): 샘플의 좌표·시각을 읽는다 / 위치 없는 JPEG는 좌표 null / 텍스트 파일은 null / 시각 없는 사진은 파일 시각 + `usedFileTime`. 실패 확인 → 구현 → 커밋

### Task 10: 화면 (`components/`, `App.tsx`, `App.css`)

- [ ] `useTimeline.ts`: 사진 더하기(중복 제거), 날짜별 머문 곳, 이름(직접 → 받은 것 → "장소 N" → "위치 정보 없음"), 이름 받기 시작, 고치기, 전부 지우기, 읽지 못한 파일 수·파일 시각을 쓴 사진 수
- [ ] `DropZone.tsx`, `StopCard.tsx`, `StopList.tsx`, `TimelineMap.tsx`(Leaflet을 `useEffect`로 직접 사용, 번호 핀은 `divIcon`, 날짜별 `polyline`)
- [ ] `App.tsx`: 머리말(요약, 이미지로 저장, 전부 지우기), 놓는 영역, 지도, 목록, 안내 글. 넓은 화면은 지도 왼쪽 고정
- [ ] `npm run dev`로 띄워 샘플 6장을 올려 눈으로 확인(스크린샷) → 커밋

### Task 11: 공유 이미지 (`services/shareImage.ts`)

```ts
export async function makeShareImage(outline, options: { title; subtitle; thumbnail: (photoId) => string | undefined }): Promise<Blob>
```

- [ ] 캔버스에 머리말, 지도(타일 + 날짜별 선 + 번호 핀), 날짜 구분 줄, 머문 곳 줄(번호·이름·시간·썸네일)을 그린다. 타일을 못 받으면 지도를 뺀다
- [ ] "이미지로 저장" 버튼에 연결. 누른 순간의 내용으로 `makeShareOutline`, 썸네일을 그린 뒤 `retitled`로 늦게 온 이름 반영 → 커밋

### Task 12: 화면 테스트 (`e2e/timeline.spec.ts`, `playwright.config.ts`)

- [ ] 설정: 시스템 크롬(`channel: 'chrome'`), `webServer`로 `npm run dev`, 시간대 `Asia/Seoul`, 언어 `ko-KR`
- [ ] 장소 이름 요청과 지도 타일 요청은 가짜 응답으로 바꾼다
- [ ] 테스트: 샘플 6장을 올리면 날짜 구분 줄 2개·머문 곳 5곳·"6장" / 받아 온 이름이 보인다 / 이름을 고치면 바뀌고 새로고침 후 다시 올려도 남는다 / "이미지로 저장"이 PNG를 내려받는다 / 텍스트 파일은 "읽지 못한 파일 1개"
- [ ] 통과 확인 → 커밋

### Task 13: 마무리

- [ ] 변이 확인: `timeline.ts`·`placeNameLookup.ts`·`customNames.ts`·`mercator.ts`를 한 줄씩 망가뜨려 테스트가 실패하는지 본다
- [ ] 문서: `README.md`(웹 버전 실행법, 폴더 구조), `llm-wiki/`(새 페이지 `web.md`, `index.md`, `log.md`), `CLAUDE.md` 규칙, `dev-notes/`(Swift ↔ TypeScript 옮기기 메모)
- [ ] `npm run build`, `npm test`, `npm run e2e` 전부 통과한 출력을 확인하고 커밋
