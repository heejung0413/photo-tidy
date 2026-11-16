# 구조

## 큰 그림

```
PhotoTidyCore (Swift 패키지)   화면·사진첩·네트워크를 모르는 순수 로직. swift test로 검증
PhotoTidy (앱)                 사진첩/지도 래퍼 + 상태 모델 + SwiftUI 화면
PhotoTidyUITests               시뮬레이터 화면 자동 조작 테스트
```

원칙: 판단 규칙은 Core에, 앱에는 애플 API 래퍼와 화면만 둔다.

## Core (`PhotoTidyCore/Sources/PhotoTidyCore/`)

| 파일 | 역할 |
| --- | --- |
| `Models.swift` | `PhotoItem`, `PhotoMetrics`, `StoredPhoto`, `StoredGroup` |
| `Tuning.swift` | 조정값: `maxGap` 60초, `distanceThreshold` 0.5, `stopRadius` 200m, `estimatedBytesPerPixel` 0.2 |
| `SimilarityGrouper.swift` | 구간 나누기, 지문 거리로 묶기(union-find) |
| `BestShotPicker.swift` | 묶음에서 추천 사진 고르기 |
| `ImageAnalyzer.swift` | Vision으로 지문·얼굴 품질, 선명도 계산 |
| `SegmentProcessor.swift` | 구간 하나를 읽어 묶음으로 |
| `GroupStore.swift` | 분석 결과 JSON 저장·병합·정리 |
| `TimelineBuilder.swift` | 거리 계산, 머문 곳 만들기(`stops`), 날짜별로 나누기(`days`) |
| `Summary.swift` | 보이는 묶음, 지울 수 있는 장수, 확보 용량(`StoreState` 확장) |
| `PlaceNames.swift` | 장소 이름 저장 키(`PlaceKey`), 직접 붙인 이름(`CustomPlaceNames`) |
| `DayNavigator.swift` | 이전·다음·가장 가까운 날 고르기 |
| `TimelineText.swift` | 머문 시각 범위, 앨범 기간 글자 |
| `AnalysisPlanner.swift` | 다음에 분석할 구간 고르기 |
| `ShareOutline.swift` | 공유 이미지에 담을 내용(번호, 제목, 썸네일, 날짜별 경로) |

## 앱 (`PhotoTidy/`)

| 파일 | 역할 |
| --- | --- |
| `PhotoTidyApp.swift` | 탭 2개(정리, 타임라인), 모델 주입, 전체 색 지정 |
| `PhotoLibrary.swift` | 권한, 사진 목록, 분석용·표시용 이미지, 삭제 |
| `PhotoLibrary+Timeline.swift` | 특정 날 사진, 사진 있는 날짜 목록 |
| `PhotoLibrary+Albums.swift` | 앨범 목록(공유·일반), 앨범 안 사진, 디버그용 샘플 앨범 |
| `AppModel.swift` | 정리 탭 상태: 권한, 분석 진행, 묶음, 삭제 |
| `TimelineModel.swift` | 타임라인 상태: 범위, 날짜, 머문 곳, 장소 이름, 직접 붙인 이름 |
| `PlaceNamer.swift` | 좌표 → 장소 이름(CLGeocoder), 캐시 |
| `TimelineShare.swift` | 타임라인을 JPEG 한 장으로, 공유 창 |
| `Views/` | `HomeView`, `GroupListView`, `GroupDetailView`, `TimelineView`, `AssetImage`, `Theme` |

## 기기에 저장하는 파일 (앱의 Application Support)

| 파일 | 내용 |
| --- | --- |
| `groups.json` (`GroupStore`) | 묶음 목록, 분석한 사진 id |
| `place-names.json` | 자동으로 받은 장소 이름 캐시 (좌표 소수 셋째 자리 키) |
| `custom-place-names.json` | 사용자가 직접 붙인 장소 이름 |

## 프로젝트 파일

`project.yml`(XcodeGen)이 원본이고 `PhotoTidy.xcodeproj`·`Info.plist`는 생성물이라 git에 없다. 파일을 추가·삭제하면 `xcodegen generate`.
