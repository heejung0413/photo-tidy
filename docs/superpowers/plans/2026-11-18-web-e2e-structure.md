# 웹 화면 테스트 구조 정리 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `web/e2e/timeline.spec.ts` 한 파일의 화면 테스트 25개를 공용 도우미와 기능별 파일로 나누고, 빠진 시나리오 3개와 타입 검사를 더한다.

**Architecture:** Playwright `test.extend`로 가짜 서비스(`FakeServices`)와 화면 조작 객체(`TimelinePage`)를 테스트마다 새로 만들어 준다. 테스트 본문은 기존 이름·검증을 유지한 채 기능별 spec 파일로 옮긴다.

**Tech Stack:** Playwright 1.65(시스템 크롬), TypeScript(`erasableSyntaxOnly`), Vite.

설계: `docs/superpowers/specs/2026-11-18-web-e2e-structure-design.md`. 모든 명령은 `web/`에서 실행한다.

---

### Task 1: 기준선

- [ ] `npx playwright test --list`의 테스트 이름 25개를 스크래치 파일에 저장한다(옮긴 뒤 대조용).
- [ ] `npm run e2e`가 25개 통과하는지 확인한다.

### Task 2: 공용 도우미 (`e2e/support/`)

**Files:** Create `samples.ts`, `services.ts`, `timelinePage.ts`, `image.ts`, `browserHooks.ts`, `test.ts`

- [ ] `samples.ts`: `samples`(6장), `sydney`, `notAPhoto`, `blankPNG`, `manyCopies(directory, count)`, `plainPhoto(directory)`(정보 없는 PNG), `withLatitudeDegrees(source, destination, degrees)`(EXIF 위도의 도 값을 바꾼 사본).
- [ ] `services.ts`: `FakeServices` — `tileDelay`, `nameRequests`, `nameReply`, `install(page)`. 답의 모양은 `{ address } | 'abort' | { status }`.
- [ ] `timelinePage.ts`: `TimelinePage` — 요소(`cards`, `card(i)`, `summary`, `dayDividers`, `pins`, `thumbnails`, `map`, `emptyMessage`, `readingStatus`)와 조작(`upload`, `clear`, `saveImage`, `dropFile`, `dragThumbnailOntoPage`, `dropFolder`, `pinSpacing`).
- [ ] `image.ts`: `inspectPNG(page, path, { points, region })` → `{ width, height, points, matches }`.
- [ ] `browserHooks.ts`: `slowThumbnails`, `recordCanvasText`/`drawnTexts`, `recordDownloadHref`/`downloadStillAlive`.
- [ ] `test.ts`: `test.extend`로 `services`(auto), `timeline`(auto, `/` 열기)을 내보낸다.

### Task 3: 기능별 파일로 옮기기

**Files:** Create `upload.spec.ts`(10), `place-names.spec.ts`(4), `map.spec.ts`(4), `share-image.spec.ts`(5), `thumbnails.spec.ts`(2). Delete `timeline.spec.ts`.

- [ ] 이름과 검증을 그대로 옮긴다. 전역 변수 대신 `services`, 흩어진 조작 대신 `timeline`을 쓴다.
- [ ] `npx playwright test --list`의 이름을 Task 1의 목록과 대조한다(25개 모두 있어야 한다).
- [ ] `npm run e2e` → 25개 통과.

### Task 4: 새 시나리오 3개

- [ ] `upload.spec.ts`: "위치 없는 사진만 올리면 지도 대신 안내가 나온다", "촬영 시각이 없는 사진은 파일 시각을 썼다고 알린다".
- [ ] `place-names.spec.ts`: "잘못된 좌표의 머문 곳이 있어도 다른 장소는 이름을 받는다" — `test.fail()`. 표시를 잠깐 떼고 돌려 **실제로 실패하는지**(이름이 안 붙는지) 확인한 뒤 다시 붙인다.
- [ ] 앞의 두 테스트는 기존 동작을 굳히는 테스트라 처음부터 통과한다. 앱의 안내 조건을 망가뜨려 실패하는지 확인한다.

### Task 5: 타입 검사

**Files:** Create `tsconfig.e2e.json`. Modify `tsconfig.json`.

- [ ] `tsconfig.node.json`을 본떠 `include: ["e2e", "playwright.config.ts"]`, `lib`에 DOM 추가, `tsBuildInfoFile`은 다른 이름.
- [ ] `npx tsc -b` 통과(드러난 타입 오류는 테스트 코드에서 고친다).

### Task 6: 검증과 문서

- [ ] `npm test`, `npx tsc -b`, `npm run lint`, `npm run e2e` 모두 통과.
- [ ] 앱 코드 표본 망가뜨리기(원본은 스크래치에 복사, 끝나면 `cmp`로 복구 확인): 읽는 중 지우기 보호, 영역 밖 떨어뜨리기, 늦게 온 이름, 위치 없음 안내, 파일 시각 안내.
- [ ] `web/README.md`, `llm-wiki/web.md`, `llm-wiki/log.md`, 프로젝트 `CLAUDE.md`에 구조와 쓰는 법을 반영한다.
