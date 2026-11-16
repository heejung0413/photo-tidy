# 테스트

## 로직 테스트

```bash
swift test --package-path PhotoTidyCore
```

40개(2026-11-16). 묶기, 추천, 저장, 이미지 분석, 타임라인 머문 곳·날짜별 나누기.

## 시뮬레이터 화면 테스트 (`PhotoTidyUITests/SmokeTests.swift`)

| 테스트 | 확인하는 것 |
| --- | --- |
| `testAnalyzeAndDeleteDuplicates` | 권한 → 분석 → 목록 → 상세 → 삭제. **실제로 사진 1장을 지운다** |
| `testTimelineShowsStopsForSampleDay` | 샘플 날짜의 머문 곳 표시 |
| `testTimelineWalkthrough` | 이전 날, 달력, 지도 이동, 크게 보기 |
| `testAlbumTimeline` | `-sampleAlbum`으로 만든 앨범을 골라 앨범 화면 표시 |
| `testRenameStopAndShare` | 장소 이름 고치기 → 공유 창 표시 |

### 준비

```bash
SIM=08B467F7-DA62-4748-A245-33434F9B4D87          # iPhone 15 Pro, iOS 17.5. 이름이 아니라 ID로 지정
xcrun simctl uninstall $SIM com.heejung.phototidy   # 권한·분석 결과 초기화
xcrun simctl addmedia $SIM build/samples/a1.jpg build/samples/a2.jpg   # 같은 사진 2장(삭제 테스트용)
swift scripts/make-timeline-samples.swift build/timeline-samples       # 2026-11-14, 3곳 4장 (처음 한 번 addmedia)
xcodebuild test -project PhotoTidy.xcodeproj -scheme PhotoTidy \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath build > build.log 2>&1
```

- 테스트는 앱을 한국어 지역(`-AppleLanguages (ko) -AppleLocale ko_KR`)으로 띄운다. 캡처의 날짜·시각이 한국어로 나온다. 시스템 알림 창(권한, 삭제 확인)은 시뮬레이터 언어를 따른다.
- 화면 조작은 XCUITest로만 한다(이 맥은 클릭 자동화가 막혀 있음). 시스템 알림 버튼은 이름으로 찾는다.
- 테스트가 찍은 화면은 `build.log`의 `SHOT:` 경로. 공유 이미지는 앱 컨테이너 `tmp/타임라인.jpg`.
- "샘플 앨범"은 앱을 지워도 사진첩에 남고, 있으면 다시 채우지 않는다.

## 테스트가 못 잡는 것

실제 사진에서의 묶기 정확도, 수천 장 속도, 실제 공유 앨범, 큰 앨범 성능, [known-issues](known-issues.md)의 상황들.
