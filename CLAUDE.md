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
