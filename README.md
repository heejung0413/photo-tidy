# Photo Tidy

아이폰 사진첩에서 연달아 찍은 비슷한 사진을 묶고, 잘 나온 한 장을 추천해 나머지를 지우는 개인용 앱.
사진은 기기 밖으로 나가지 않는다(서버 없음).

## 준비

- Xcode 26 이상, XcodeGen(`brew install xcodegen`)

## 실행

```bash
xcodegen generate          # PhotoTidy.xcodeproj 생성 (project.yml을 고칠 때마다 다시 실행)
open PhotoTidy.xcodeproj
```

Xcode 상단에서 실행 대상(시뮬레이터 또는 연결한 아이폰)을 고르고 ▶ 를 누른다.

### 내 아이폰에 설치

1. Xcode > Settings > Accounts에 Apple 계정을 추가한다.
2. 프로젝트 > PhotoTidy 타깃 > Signing & Capabilities에서 Team을 고른다.
   `xcodegen generate`를 다시 돌리면 이 선택이 지워지므로, `project.yml`의 PhotoTidy `settings.base`에 `DEVELOPMENT_TEAM: <팀 ID>`를 적어 두면 편하다.
3. 아이폰을 연결하고 실행한다. 처음에는 아이폰 설정 > 일반 > VPN 및 기기 관리에서 개발자를 신뢰해야 한다.

무료 계정은 7일마다 다시 설치해야 한다.

## 테스트

로직 테스트(맥에서 바로 실행):

```bash
swift test --package-path PhotoTidyCore
```

시뮬레이터 스모크 테스트(권한 허용 → 분석 → 묶음 상세 → 삭제까지 자동 조작). 시뮬레이터 사진첩에 같은 사진 2장이 연달아 들어 있어야 하고, 실제로 1장을 삭제한다:

```bash
xcrun simctl list devices available | grep iPhone      # 기기 ID 확인
xcrun simctl boot <기기 ID>
xcrun simctl addmedia <기기 ID> a.jpg a-copy.jpg       # 같은 사진 두 장
xcrun simctl uninstall <기기 ID> com.heejung.phototidy # 이전 분석 결과·권한 초기화
xcodebuild test -project PhotoTidy.xcodeproj -scheme PhotoTidy \
  -destination "platform=iOS Simulator,id=<기기 ID>" -derivedDataPath build
```

## 조정할 수 있는 값

`PhotoTidyCore/Sources/PhotoTidyCore/Tuning.swift`

- `maxGap`: 연달아 찍은 사진으로 보는 시간 간격(초)
- `distanceThreshold`: 비슷하다고 보는 정도. 다른 사진이 같이 묶이면 낮추고, 비슷한 사진이 안 묶이면 높인다.

## 구조

- `PhotoTidyCore/`: 묶기·추천·저장 로직(화면과 사진첩에 의존하지 않음)
- `PhotoTidy/`: 사진첩 접근, 화면
- `PhotoTidyUITests/`: 시뮬레이터 스모크 테스트
- 설계: `docs/superpowers/specs/2026-11-16-photo-tidy-design.md`
