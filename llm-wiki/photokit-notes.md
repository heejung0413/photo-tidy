# 애플 API에서 겪은 것

## 사진첩 (PhotoKit)

- 권한은 "전체", "일부 사진만", "거부"가 있다. 일부만 허용이면 그 사진만 보인다.
- 삭제는 `PHPhotoLibrary.performChanges`로 요청하고, 아이폰이 확인 창을 띄운다. 지운 사진은 "최근 삭제된 항목"으로 간다.
- 분석용 이미지는 512px로 받고 네트워크를 끈다. iCloud에만 원본이 있는 사진은 못 읽을 수 있고 "건너뛴 사진"으로 센다.
- 공유 앨범 사진을 id로 찾으려면 `PHFetchOptions.includeAssetSourceTypes`에 `.typeCloudShared`를 넣어야 한다고 보고 넣어 두었다(`displayImages`, `albumPhotoOptions`). 기본값만으로 되는지는 미확인.
- 시뮬레이터에는 공유 앨범이 없다(iCloud 로그인 필요). 그래서 디버그 실행 인자 `-sampleAlbum`으로 일반 앨범을 만들어 화면만 확인한다.
- `simctl privacy grant photos`는 기대대로 동작하지 않았다. 권한 초기화는 앱 삭제로 한다.

## Vision

- 시뮬레이터에서는 요청에 `usesCPUOnly = true`가 필요하다. 없으면 지문 생성이 전부 실패한다(`ImageAnalyzer`의 `#if targetEnvironment(simulator)`).

## 지도·장소

- `CLGeocoder`는 한 번에 요청 하나, 짧은 시간에 많이 보내면 막힌다.
- SwiftUI `Map`은 `ImageRenderer`로 그림이 되지 않는다 → `MKMapSnapshotter`.
- 지도 핀 글자가 늦게 온 이름으로 안 바뀌어서, 핀 id에 제목을 포함시켰다(`TimelineView.pins`).

## SwiftUI

- `NavigationStack`에서 `NavigationLink { 화면 }`과 `NavigationLink(value:)`를 섞으면 화면 순서가 꼬였다. 값 기반으로 통일하고 `navigationDestination`은 `HomeView` 루트에 둔다.
- Core 패키지의 struct를 앱에서 만들려면 `public init`이 필요하다(자동 생성 init은 패키지 밖에서 안 보임).
