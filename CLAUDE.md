# CLAUDE.md

Photo Tidy: 아이폰 사진첩의 비슷한 사진 정리 + 하루 타임라인. 구조·실행법은 `README.md`, 설계는 `docs/superpowers/specs/`.

## Learned Rules

- **GitHub 저장소는 `heejung0413/photo-tidy`(비공개)**. 이 맥의 전역 git 인증은 gh의 "활성 계정"(평소 `jiran-heejung0413`)을 쓰므로 그대로면 push/pull이 "Repository not found". 2026-11-16부터 이 저장소 로컬 config(`credential.https://github.com.helper`)가 `gh auth token --user heejung0413`으로 인증하게 해 두어, 계정 전환 없이 터미널·Fork 앱 모두에서 push 된다(토큰은 config에 저장되지 않음). 저장소를 새로 clone하면 이 설정이 없으니 다시 넣을 것. 푸시는 사용자가 요청할 때만.
- `PhotoTidy.xcodeproj`와 `PhotoTidy/Info.plist`는 XcodeGen 산출물(gitignore). 파일을 추가·삭제하거나 `project.yml`을 고치면 `xcodegen generate`를 다시 돌릴 것. 다시 생성하면 Xcode에서 고른 Team이 지워지므로, Team ID를 알게 되면 `project.yml`의 `DEVELOPMENT_TEAM`에 적을 것.
- 로직은 `PhotoTidyCore`(화면·사진첩·네트워크 의존 없음)에 두고 `swift test --package-path PhotoTidyCore`로 검증. 앱 타깃에는 Photos/MapKit 래퍼와 화면만.
- xcodebuild 시뮬레이터 지정은 이름이 아니라 ID로: `-destination "platform=iOS Simulator,id=08B467F7-DA62-4748-A245-33434F9B4D87"`(iPhone 15 Pro, iOS 17.5). 이름으로 주면 `OS:latest`(26.x)에서 찾다가 "Unable to find a device"로 실패한다.
- 시뮬레이터에서는 Vision 요청에 `usesCPUOnly = true`가 필요하다(`ImageAnalyzer`의 `#if targetEnvironment(simulator)`). 없으면 지문 생성이 전부 실패해 "건너뛴 사진"으로만 집계된다.
- SwiftUI `NavigationStack`에서 `NavigationLink { 화면 }`과 `NavigationLink(value:)`를 섞지 말 것. 섞었더니 상세 화면이 목록 아래에 끼워져 화면이 안 넘어갔다. 값 기반으로 통일하고 `navigationDestination`은 스택 루트(`HomeView`)에 둔다.
- 화면 조작 확인은 XCUITest(`PhotoTidyUITests/SmokeTests`)로 한다. 이 맥은 osascript 보조 접근이 꺼져 있어 시뮬레이터를 클릭으로 조작할 수 없다. 시스템 알림 버튼은 순번이 아니라 이름(`전체 접근 허용`/`Allow Full Access`, `삭제`/`Delete`)으로 찾을 것.
- 스모크 테스트 전 준비: 권한·분석 결과 초기화는 `xcrun simctl uninstall <ID> com.heejung.phototidy`. `simctl privacy grant photos`는 기대대로 동작하지 않았고, `photos-add`를 주면 권한 창이 "추가 접근" 형태로 바뀐다. 정리 테스트는 같은 사진 2장(`build/samples/a1.jpg`, `a2.jpg`)을 다시 `addmedia` 해야 하고 실제로 1장을 지운다. 타임라인 샘플은 `swift scripts/make-timeline-samples.swift build/timeline-samples`(2026-11-14, 3곳 4장).
- 테스트에서 찍은 화면은 `build.log`의 `SHOT:` 경로(시뮬레이터 앱 컨테이너 tmp)에 있다. README용은 `sips -Z 1400`으로 줄여 `docs/screenshots/`에 둔다.
- 앨범 타임라인 확인: 시뮬레이터에는 공유 앨범이 없으므로 디버그 실행 인자 `-sampleAlbum`(사진첩 전체를 담은 일반 앨범 "샘플 앨범" 생성, `PhotoLibrary+Albums`)으로 `SmokeTests/testAlbumTimeline`을 돌린다. 앨범은 앱을 지워도 사진첩에 남고, 이미 있으면 다시 채우지 않는다. 공유 앨범 읽기(`.albumCloudShared`, `includeAssetSourceTypes`에 `.typeCloudShared`)와 위치 정보 보존 여부는 실제 아이폰에서만 확인 가능(미확인).
- 앨범 타임라인은 하루 화면과 달리 사진·머문 곳이 수백~수천 개가 될 수 있다. 하루 화면 코드를 재사용할 때 "전부 한꺼번에" 하는 부분(비지연 `VStack`, 모든 머문 곳 지오코딩, `stops.firstIndex` 반복, 날짜를 넘는 `MapPolyline`)을 점검할 것. 2026-11-16 `/code-review`에서 이 유형 10건이 나왔고 일부만 고쳤다(`llm-wiki/known-issues.md`).
- 커밋 작성자는 이 저장소 로컬 config로 `heejung0413`(GitHub noreply 주소)에 맞춰 둠(2026-11-16). 그 전 커밋 11개는 전역 신원 `ni-heejung`으로 남아 있고, 다시 쓰려면 강제 푸시가 필요해 사용자 답을 기다리는 중.
- 색·카드 모양·순번 배지는 `PhotoTidy/Views/Theme.swift` 한 곳(`Theme.accent`, `.card()`, `NumberBadge`)에서 쓴다. 화면에 `.blue` 같은 색을 직접 쓰지 말 것. 공유 이미지(`TimelineShare`)도 같은 색을 쓴다.
- 화면을 고칠 때 스모크 테스트가 찾는 글자·이름을 유지할 것: `분석 시작`/`새 사진 분석`, `비슷한 사진 묶음`으로 시작하는 글자, `묶음 보기`, 목록의 List 셀, `나머지`로 시작하는 버튼, `정리할 묶음이 없어요`, `이전 날`/`다음 날`, `범위 선택`, `사진 크게 보기`, `장소 이름 바꾸기`, `타임라인 공유`.
- 화면의 SwiftUI `Map`은 `ImageRenderer`로 그림이 되지 않는다. 이미지로 내보낼 때는 `MKMapSnapshotter`로 지도 그림을 받아 핀·선을 직접 그린다(`TimelineShare.mapImage`). 만들어진 공유 이미지는 `xcrun simctl get_app_container <ID> com.heejung.phototidy data` 아래 `tmp/타임라인.jpg`.
- 2026-11-16 코드 리뷰 지적 중 분석 누락·장소 이름 키·공유 내용 섞임·날짜를 넘는 지도 선, 이어서 긴 구간 취소·`CLGeocoder` 동시 요청·앨범 화면 지연 그리기·묶기 계산 백그라운드화까지 같은 날 수정함. 앨범 목록 새로고침과 앨범 id 비교도 같은 날 수정. 남은 것(큰 앨범의 이름 요청 제한, 쌍 비교 n², 실패한 이름 재시도)은 `llm-wiki/known-issues.md`.
- 타임라인은 사진첩 변경 알림(`LibraryChangeWatcher`, 권한을 받은 뒤 `loadDays`에서 등록)으로 다시 읽는다. 보던 앨범은 `PhotoAlbum` 값이 아니라 id(`TimelineModel.albumID`)로 비교할 것 — 값에는 사진 수가 들어 있어 사진이 더해지면 달라진다.
- 실행 중 사진첩이 바뀌는 상황은 디버그 인자 `-growSampleAlbumAfter <초>`로 만든다(샘플 앨범에 없는 사진을 앨범에 넣음, `testAlbumFollowsLibraryChanges`). 앨범에 없는 사진이 1장 이상 있어야 하므로 화면 테스트 전에 `a1.jpg`·`a2.jpg`를 매번 새로 `addmedia` 할 것. 샘플 앨범은 돌릴 때마다 2장씩 늘어난다.
- 앨범 화면은 `LazyVStack`이라 화면 밖 줄은 접근성 트리에 없다. 화면 테스트에서 아래쪽 줄을 찾을 때는 `swipeUp`으로 내려가며 찾을 것(`testAlbumTimeline`).
- `CLGeocoder`는 요청이 겹치면 뒤 요청에 답하지 않는다(맥에서 3개 동시 요청 → 첫 번째만 응답, 2026-11-16 확인). 장소 이름은 반드시 `PlaceNameLookup`을 거쳐 한 줄로 요청할 것. 지오코더를 직접 부르는 코드를 새로 만들지 말 것.
- 웹 버전은 `web/`(Vite + React + TypeScript, 타임라인만). 판단 규칙은 `web/src/core/`에 두고 브라우저 기능을 쓰지 않는다. 확인은 `web/`에서 `npm test`(Vitest) · `npm run e2e`(Playwright, 시스템 크롬, 타일·이름 요청은 가짜 응답) · `npm run build`(타입 검사 포함). 타임라인 규칙을 고치면 Swift(`PhotoTidyCore`)와 TypeScript(`web/src/core`) 양쪽을 같이 고칠 것 — 대응표는 `llm-wiki/web.md`.
- 웹 프로젝트는 `erasableSyntaxOnly`라 `enum`과 생성자 매개변수 속성(`constructor(private x)`)을 쓸 수 없다. Vitest는 타입 검사를 하지 않으므로 테스트가 통과해도 `npx tsc -b`를 따로 돌릴 것.
- 웹(React)에서 오래 걸리는 작업(사진 읽기, 공유 이미지 만들기)이 끝난 뒤에 쓰는 값은 버튼을 누른 때의 값이 아니라 부르는 순간의 값이어야 한다. 2026-11-17 검토에서 "읽는 중 지우면 사진이 되살아남"과 "늦게 온 이름이 이미지에 안 들어감"이 이 유형이었다(`useTimeline`의 `generation`, `latestName`). 캔버스에 쓴 글자는 화면 테스트에서 `fillText`를 감싸 기록해 확인한다.
- 웹의 이름 받기 함수(`reverseGeocode`)는 "이름 없음"이면 `null`을 돌려주고 "요청 실패"면 오류를 던진다. 둘을 섞지 말 것 — `PlaceNameLookup`이 이름 없는 곳은 다시 묻지 않고, 실패가 3번 이어지면 1분 쉬는 데 이 구분을 쓴다.
- 웹 화면과 공유 이미지에는 원본 사진이 아니라 작게 줄인 썸네일(`makeThumbnail`, 짧은 변 264px)만 올린다. 원본 `File`로 `createObjectURL`을 만들어 `<img>`에 넣지 말 것.
- 웹의 HEIC(2026-11-17 확인, `sips -s format heic`로 바꾼 샘플): 위치·촬영 시각은 읽혀 타임라인·지도는 정상, 크롬은 그림을 못 그려 썸네일만 빈 칸. 아이폰이 직접 찍은 HEIC와 사파리는 미확인. 크롬용 변환(heic 변환 라이브러리)은 사용자가 실제 사진을 올려 보고 결정하기로 함.
- 웹 배포 계획(2026-11-17): Vercel에 터미널로 올리기(`web/`에서 `vercel`), 프로젝트 이름 `photo-tidy-timeline`(→ `photo-tidy-timeline.vercel.app`, 사용자 확정). 이 맥의 Vercel 로그인이 만료돼 사용자가 `vercel login`(브라우저에서 `vercel.com/device`에 코드 입력) 중. 올리기 전에 `vercel whoami`로 **개인 계정인지** 사용자에게 확인받을 것. 개발 서버는 5173 포트로 백그라운드 실행해 둠.
- 장소 이름 서비스(Nominatim)는 1초에 1번만 허용한다. `PlaceNameLookup`의 `minInterval`을 거치지 않고 직접 부르지 말 것. 실제 응답에서 동 이름은 `address.suburb`에 온다(2026-11-17 확인).
- 실제 아이폰 설치 진행 상태(2026-11-17): Xcode에 Apple 계정 로그인됨(Personal Team), `project.yml`에 `DEVELOPMENT_TEAM`을 넣었으나 **미커밋**(설치 성공을 확인한 뒤 커밋하기로 함). 아이폰(iPhone 15, iOS 26.6.1)은 연결·페어링됐지만 **개발자 모드가 꺼져 있어** 빌드가 기기를 못 쓴다 — 사용자가 설정 > 개인정보 보호 및 보안 > 개발자 모드를 켜야 한다. 기기 지정은 `xcrun devicectl list devices`의 Identifier가 아니라 xcodebuild가 보여 주는 id(`xcodebuild -showdestinations`의 `platform:iOS` 줄)를 `-destination "id=..."`에 쓸 것. Xcode는 26.2라 iOS 26.6 지원 여부는 미확인.
- 배경 지식은 `llm-wiki/`(시작은 `llm-wiki/index.md`, 운영 규칙은 `llm-wiki/README.md`)에 있다. 기능·결정이 바뀌면 관련 페이지를 고치고 `llm-wiki/log.md`에 한 줄 추가할 것.
- 앱 기본 언어는 한국어(`project.yml`의 `developmentLanguage: ko`) — 없으면 '뒤로'·공유 창 등 시스템 글자가 영어로 나온다. 화면 테스트는 `setUp`에서 한국어 지역 인자로 앱을 띄우므로, 테스트에서 글자를 찾을 때 시각은 `9:10`처럼 숫자 부분만 맞출 것(`오전 9:10`).
- 새 테스트는 통과만 보지 말고, 대상 로직을 `sed`로 한 줄 망가뜨린 뒤 `swift test`가 실패하는지 확인할 것(원본은 스크래치에 복사해 두고 되돌림). 2026-11-16에 `이전 날` 테스트가 망가진 코드를 못 잡는 것을 이 방법으로 찾았다.
- `dev-notes/`는 사용자가 읽는 학습 노트(웹 프론트엔드 개발자 기준, JS·React에 빗대어 설명, 예시는 이 프로젝트 코드). 새 개념이 등장하는 기능을 만들면 관련 노트에 짧게 보태고, 코드 예시가 실제 코드와 어긋나지 않게 할 것. `llm-wiki/`(프로젝트 지식)와 역할이 다르다.
- **이 프로젝트의 작업은 superpowers 플러그인 흐름으로 진행할 것**(2026-11-16 사용자 지시 "superpower 플러그인 쓰게 해"). 새 기능·화면 변경은 `brainstorming` → 설계 승인 → `docs/superpowers/specs/` 설계 문서 → `writing-plans`(`docs/superpowers/plans/`) → 실행. 코드는 `test-driven-development`(실패하는 테스트 먼저), 버그는 `systematic-debugging`, 리뷰 지적 반영은 `receiving-code-review`, 완료 보고 전에는 `verification-before-completion`. "구현해줘"라는 말만으로 이 단계를 건너뛰지 말 것 — 앞서 장소 이름·이미지 공유·UI 다듬기·테스트 추가를 건너뛰고 만들었던 것이 이 지시의 배경이다.
- 분석 진행 상태는 "분석한 사진 id"(`StoreState.analyzedIDs`)로 관리한다. 촬영 시각 기준(예전 `watermark`)으로 되돌리지 말 것 — 나중에 사진첩에 들어온 옛 사진과 읽지 못한 사진이 영영 빠진다. 읽지 못한 사진은 `markAnalyzed`에 넣지 않는다.
- 리뷰 지적은 고치기 전에 재현부터 할 것. 2026-11-16 "날짜를 넘기면 지도에 앞 날짜 선이 남는다"는 지적은 이틀 치 샘플로 재현해 보니 사실이 아니어서 고치지 않았다(`testRouteFollowsDayWhenSwitching`). 반대로 내 수정이 새 문제를 만든 적도 있다(공유 내용을 고정하면서 늦게 오는 장소 이름을 놓침, 거리 기준 이름이 옆 장소까지 바꿈) — 고친 뒤에는 `/code-review`를 다시 돌릴 가치가 있다.
- 직접 붙인 장소 이름은 머문 곳의 **사진 id**에 붙인다(`CustomPlaceNames`). 좌표·반경을 이름의 주인으로 쓰지 말 것(중심은 사진이 더해지면 움직이고, 옆 장소와 구분되지 않는다). 좌표는 이름 붙인 적 없는 머문 곳이 물려받을 때만 쓴다.
- 타임라인 샘플은 이틀 치(2026-11-14 3곳 4장, 11-15 2곳 2장). 시뮬레이터 "샘플 앨범"은 처음 만들 때의 사진만 담고 있어 나중에 넣은 샘플은 없다.
