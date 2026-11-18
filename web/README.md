# Photo Tidy 웹 타임라인

사진 파일을 끌어다 놓으면 지도에 머문 곳과 경로를 그리고, 날짜별 목록과 공유 이미지를 만드는 웹 페이지.
아이폰 앱의 타임라인 기능을 브라우저로 옮긴 것이다. 정리(비슷한 사진 묶기·삭제) 기능은 없다.

사진은 브라우저 밖으로 나가지 않는다. 장소 이름을 받을 때 머문 곳의 좌표가, 지도를 그릴 때 보고 있는 지역이 오픈스트리트맵 서버로 전송된다.

공개 주소: https://photo-tidy-timeline.vercel.app

## 실행

Node.js 22 이상.

```bash
npm install
npm run dev        # http://localhost:5173
```

## 테스트

```bash
npm test           # 로직 테스트 (Vitest)
npm run e2e        # 화면 테스트 (Playwright, 컴퓨터에 설치된 크롬 사용)
npm run build      # 타입 검사 + 배포용 파일(dist/)
```

화면 테스트는 `e2e/fixtures/`의 샘플 사진 6장(위치·시각 포함, 이틀 치)을 올린다.
지도 타일과 장소 이름 요청은 가짜 응답으로 바꿔서 인터넷 없이도 돈다.
샘플은 저장소 루트에서 `swift scripts/make-timeline-samples.swift web/e2e/fixtures`로 다시 만들 수 있다.

## 배포

Vercel(개인 계정의 `photo-tidy-timeline` 프로젝트)에 터미널에서 올린다. GitHub와 연결하지 않았으므로 푸시해도 자동으로 배포되지 않는다.

```bash
vercel deploy --prod      # web/ 폴더에서. 로그인이 풀렸으면 먼저 vercel login
```

## 구조

| 폴더 | 내용 |
| --- | --- |
| `src/core/` | 판단 규칙. 브라우저 기능을 쓰지 않는다. Swift `PhotoTidyCore`에서 옮겼다 |
| `src/services/` | 사진 정보 읽기, 장소 이름 받기, 저장, 공유 이미지 그리기 |
| `src/components/` | React 화면과 상태 훅(`useTimeline`) |
| `e2e/` | 화면 테스트와 샘플 사진 |

### 화면 테스트 (`e2e/`)

| 파일 | 내용 |
| --- | --- |
| `upload.spec.ts` | 올리기, 중복, 사진 아닌 파일, 끌어다 놓기, 폴더째, 읽는 중 지우기 |
| `place-names.spec.ts` | 장소 이름 받기, 요청 간격, 실패 후 다시 묻기, 이름 고치기 |
| `map.spec.ts` | 핀, 창 크기가 바뀔 때의 범위, 좁은 화면 |
| `share-image.spec.ts` | 이미지로 저장 |
| `thumbnails.spec.ts` | 썸네일 |
| `support/test.ts` | 테스트가 가져다 쓰는 `test`, `expect`. 가짜 서비스 설치와 첫 화면 열기를 자동으로 한다 |
| `support/services.ts` | 가짜 지도 타일·장소 이름 응답(`FakeServices`) |
| `support/timelinePage.ts` | 화면 조작과 자주 찾는 요소(`TimelinePage`) |
| `support/image.ts` | 저장한 PNG의 크기·픽셀 읽기 |
| `support/browserHooks.ts` | 느린 썸네일, 캔버스 글자 기록, 내려받기 주소 기록 |
| `support/samples.ts` | 샘플 경로, 복사본·위치 없는 사진·잘못된 좌표 사진 만들기 |

새 테스트는 이렇게 시작한다.

```ts
import { samples } from './support/samples.ts'
import { expect, test } from './support/test.ts'

test('사진을 올리면 머문 곳이 나온다', async ({ timeline, services }) => {
  services.nameReply = () => ({ address: { suburb: '우리 동네' } }) // 이름 서비스의 답을 바꾸고 싶을 때만
  await timeline.upload(samples)
  await expect(timeline.cards).toHaveCount(5)
})
```

```bash
npx playwright test upload            # 파일 하나만
npx playwright test -g "폴더"          # 이름에 "폴더"가 든 테스트만
npx playwright test --ui              # 화면을 보면서
```

아직 고치지 않은 문제를 재현하는 테스트는 `test.fail()`로 표시한다(실패해야 통과). 문제를 고치면 그 테스트가 "Expected to fail, but passed"로 실패하니 표시를 지운다.

## 한계

- 크롬은 HEIC 사진을 그리지 못해 썸네일이 빈 칸으로 나온다(타임라인에는 포함된다). 사파리는 그린다.
- 썸네일은 사진을 올린 뒤 하나씩 만들어져 잠시 뒤에 채워진다.
- 장소 이름은 무료 서비스 제한 때문에 약 1초에 하나씩 받는다.
- 오픈스트리트맵의 무료 지도·이름 서비스는 개인이 가끔 쓰는 정도만 허용한다.
- 아이폰 브라우저에서 사진을 고르면 위치 정보가 지워져 넘어올 수 있다(미확인).
