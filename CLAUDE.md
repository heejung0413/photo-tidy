# CLAUDE.md

Photo Tidy: 아이폰 사진첩의 비슷한 사진 정리 + 하루 타임라인. 구조·실행법은 `README.md`, 설계는 `docs/superpowers/specs/`.

## Learned Rules

- **GitHub 저장소는 `heejung0413/photo-tidy`(비공개)**. gh 활성 계정은 평소 `jiran-heejung0413`이라 그대로 push/pull 하면 "Repository not found". `gh auth switch --user heejung0413` → push → `gh auth switch --user jiran-heejung0413`으로 되돌릴 것. 푸시는 사용자가 요청할 때만.
- `PhotoTidy.xcodeproj`와 `PhotoTidy/Info.plist`는 XcodeGen 산출물(gitignore). 파일을 추가·삭제하거나 `project.yml`을 고치면 `xcodegen generate`를 다시 돌릴 것. 다시 생성하면 Xcode에서 고른 Team이 지워지므로, Team ID를 알게 되면 `project.yml`의 `DEVELOPMENT_TEAM`에 적을 것.
- 로직은 `PhotoTidyCore`(화면·사진첩·네트워크 의존 없음)에 두고 `swift test --package-path PhotoTidyCore`로 검증. 앱 타깃에는 Photos/MapKit 래퍼와 화면만.
- xcodebuild 시뮬레이터 지정은 이름이 아니라 ID로: `-destination "platform=iOS Simulator,id=08B467F7-DA62-4748-A245-33434F9B4D87"`(iPhone 15 Pro, iOS 17.5). 이름으로 주면 `OS:latest`(26.x)에서 찾다가 "Unable to find a device"로 실패한다.
- 시뮬레이터에서는 Vision 요청에 `usesCPUOnly = true`가 필요하다(`ImageAnalyzer`의 `#if targetEnvironment(simulator)`). 없으면 지문 생성이 전부 실패해 "건너뛴 사진"으로만 집계된다.
- SwiftUI `NavigationStack`에서 `NavigationLink { 화면 }`과 `NavigationLink(value:)`를 섞지 말 것. 섞었더니 상세 화면이 목록 아래에 끼워져 화면이 안 넘어갔다. 값 기반으로 통일하고 `navigationDestination`은 스택 루트(`HomeView`)에 둔다.
- 화면 조작 확인은 XCUITest(`PhotoTidyUITests/SmokeTests`)로 한다. 이 맥은 osascript 보조 접근이 꺼져 있어 시뮬레이터를 클릭으로 조작할 수 없다. 시스템 알림 버튼은 순번이 아니라 이름(`전체 접근 허용`/`Allow Full Access`, `삭제`/`Delete`)으로 찾을 것.
- 스모크 테스트 전 준비: 권한·분석 결과 초기화는 `xcrun simctl uninstall <ID> com.heejung.phototidy`. `simctl privacy grant photos`는 기대대로 동작하지 않았고, `photos-add`를 주면 권한 창이 "추가 접근" 형태로 바뀐다. 정리 테스트는 같은 사진 2장(`build/samples/a1.jpg`, `a2.jpg`)을 다시 `addmedia` 해야 하고 실제로 1장을 지운다. 타임라인 샘플은 `swift scripts/make-timeline-samples.swift build/timeline-samples`(2026-11-14, 3곳 4장).
- 테스트에서 찍은 화면은 `build.log`의 `SHOT:` 경로(시뮬레이터 앱 컨테이너 tmp)에 있다. README용은 `sips -Z 1400`으로 줄여 `docs/screenshots/`에 둔다.
- 앨범 타임라인 확인: 시뮬레이터에는 공유 앨범이 없으므로 디버그 실행 인자 `-sampleAlbum`(사진첩 전체를 담은 일반 앨범 "샘플 앨범" 생성, `PhotoLibrary+Albums`)으로 `SmokeTests/testAlbumTimeline`을 돌린다. 앨범은 앱을 지워도 사진첩에 남고, 이미 있으면 다시 채우지 않는다. 공유 앨범 읽기(`.albumCloudShared`, `includeAssetSourceTypes`에 `.typeCloudShared`)와 위치 정보 보존 여부는 실제 아이폰에서만 확인 가능(미확인).
- 앨범 타임라인은 하루 화면과 달리 사진·머문 곳이 수백~수천 개가 될 수 있다. 하루 화면 코드를 재사용할 때 "전부 한꺼번에" 하는 부분(비지연 `VStack`, 모든 머문 곳 지오코딩, `stops.firstIndex` 반복, 날짜를 넘는 `MapPolyline`)을 점검할 것. 2026-11-16 `/code-review`에서 이 유형 10건이 나왔고 `20af01c` 기준 미수정(사용자 결정 대기).
- 커밋 작성자는 이 저장소 로컬 config로 `heejung0413`(GitHub noreply 주소)에 맞춰 둠(2026-11-16). 그 전 커밋 11개는 전역 신원 `ni-heejung`으로 남아 있고, 다시 쓰려면 강제 푸시가 필요해 사용자 답을 기다리는 중.
- 색·카드 모양·순번 배지는 `PhotoTidy/Views/Theme.swift` 한 곳(`Theme.accent`, `.card()`, `NumberBadge`)에서 쓴다. 화면에 `.blue` 같은 색을 직접 쓰지 말 것. 공유 이미지(`TimelineShare`)도 같은 색을 쓴다.
- 화면을 고칠 때 스모크 테스트가 찾는 글자·이름을 유지할 것: `분석 시작`/`새 사진 분석`, `비슷한 사진 묶음`으로 시작하는 글자, `묶음 보기`, 목록의 List 셀, `나머지`로 시작하는 버튼, `정리할 묶음이 없어요`, `이전 날`/`다음 날`, `범위 선택`, `사진 크게 보기`, `장소 이름 바꾸기`, `타임라인 공유`.
- 화면의 SwiftUI `Map`은 `ImageRenderer`로 그림이 되지 않는다. 이미지로 내보낼 때는 `MKMapSnapshotter`로 지도 그림을 받아 핀·선을 직접 그린다(`TimelineShare.mapImage`). 만들어진 공유 이미지는 `xcrun simctl get_app_container <ID> com.heejung.phototidy data` 아래 `tmp/타임라인.jpg`.
- 2026-11-16 전체 코드 리뷰 결과 미수정(사용자 결정 대기): 분석 기준 시각 때문에 나중에 들어온 옛 사진·건너뛴 사진이 다시 분석되지 않음(`AppModel.startAnalysis`), 공유 준비 중 날짜를 바꾸면 내용이 섞임, 직접 붙인 장소 이름 키(좌표 반올림)가 불안정, `CLGeocoder` 동시 요청 실패.
- 배경 지식은 `llm-wiki/`(시작은 `llm-wiki/index.md`, 운영 규칙은 `llm-wiki/README.md`)에 있다. 기능·결정이 바뀌면 관련 페이지를 고치고 `llm-wiki/log.md`에 한 줄 추가할 것.
