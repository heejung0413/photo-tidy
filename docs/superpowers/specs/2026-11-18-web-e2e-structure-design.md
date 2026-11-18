# 웹 화면 테스트 구조 정리 설계

2026-11-18. 사용자 승인: 구조 정리(추천안), 잘못된 좌표 문제는 `test.fail()`로만 남긴다.

## 왜

- 화면 테스트 25개가 `web/e2e/timeline.spec.ts` 한 파일(522줄)에 있고, 도우미 함수가 테스트 사이사이에 흩어져 있다.
- 가짜 응답 상태(`tileDelay`, `nameRequests`)가 파일 전역 변수다. 테스트끼리 상태를 나눠 쓰므로 동시에 돌릴 수 없다.
- 같은 코드가 복사돼 있다: 내려받은 PNG의 픽셀 읽기 3곳, 가짜 끌어다 놓기 3곳.
- `e2e/`와 `playwright.config.ts`는 타입 검사 대상이 아니다(`tsconfig`가 `src`와 `vite.config.ts`만 본다).

## 무엇을

```
web/e2e/
  fixtures/              샘플 사진 (그대로)
  support/
    test.ts              test.extend: 가짜 서비스 설치와 첫 화면 열기를 테스트마다 자동으로
    services.ts          가짜 지도 타일·장소 이름 응답. 상태는 테스트마다 새로 만든다
    timelinePage.ts      화면 조작과 자주 찾는 요소
    image.ts             내려받은 PNG의 크기·픽셀 읽기
    browserHooks.ts      느린 썸네일, 캔버스 글자 기록, 내려받기 주소 기록
    samples.ts           샘플 경로, 복사본·위치 없는 사진·잘못된 좌표 사진 만들기
  upload.spec.ts         올리기·중복·사진 아닌 파일·끌어다 놓기·폴더·읽는 중 지우기
  place-names.spec.ts    이름 받기·요청 간격·실패 후 다시 묻기·이름 고치기
  map.spec.ts            핀·창 크기·좁은 화면
  share-image.spec.ts    이미지 저장
  thumbnails.spec.ts     썸네일
```

### 준비물 (`support/test.ts`)

테스트는 `@playwright/test` 대신 `./support/test`에서 `test`, `expect`를 가져온다.

| 이름 | 내용 |
| --- | --- |
| `services` | `FakeServices`. 자동으로 설치된다. `tileDelay`(타일 응답 지연), `nameRequests`(이름 요청이 온 시각), `nameReply`(이름 요청에 줄 답을 정하는 함수) |
| `timeline` | `TimelinePage`. 가짜 서비스를 설치한 뒤 `/`를 연다. 자동 |

`nameReply`의 기본값은 지금과 같다: 남산 근처만 `가짜 남산동`, 나머지는 이름 없는 응답.
답은 `{ address }`, `'abort'`(연결 실패), `{ status }`(서비스가 거절) 중 하나다.

### 옮기는 규칙

- 기존 25개의 **이름과 검증 내용은 그대로** 둔다. 바뀌는 것은 파일 위치와, 흩어진 코드를 도우미 호출로 바꾸는 것뿐이다.
- "기다려도 일어나지 않는다"를 확인하는 고정 대기(`waitForTimeout`)는 그대로 둔다.

### 새 시나리오 3개

| 테스트 | 파일 | 비고 |
| --- | --- | --- |
| 위치 없는 사진만 올리면 지도 대신 안내가 나온다 | `upload.spec.ts` | 정보 없는 PNG를 테스트가 만든다 |
| 촬영 시각이 없는 사진은 파일 시각을 썼다고 알린다 | `upload.spec.ts` | 같은 PNG |
| 잘못된 좌표의 머문 곳이 있어도 다른 장소는 이름을 받는다 | `place-names.spec.ts` | 2026-11-18 검토 2번. 아직 안 고친 문제라 `test.fail()`. 샘플의 위도를 200도로 고친 사본을 테스트가 만든다 |

### 타입 검사

`tsconfig.e2e.json`(`e2e`, `playwright.config.ts`, DOM 타입 포함)을 추가하고 `tsconfig.json`의 references에 넣는다. `npm run build`(`tsc -b`)가 화면 테스트의 타입도 본다.

## 하지 않는 것

- 사파리·모바일 브라우저 추가.
- 동시 실행 켜기. 전역 상태를 없애 가능해지지만, 요청 간격을 재는 테스트가 있어 따로 판단한다(`workers: 1` 유지).
- 머문 곳 40곳 초과 시나리오(샘플을 새로 만들어야 한다).
- 잘못된 좌표 문제의 수정.

## 끝났다고 보는 기준

- `npx playwright test --list`의 이름이 기존 25개를 모두 포함하고 새 3개가 더해진다.
- `npm run e2e` 통과(예상된 실패 1개 포함), `npm test`, `npx tsc -b`, `npm run lint` 통과.
- 앱 코드를 표본으로 망가뜨렸을 때 옮긴 테스트가 여전히 실패한다.
