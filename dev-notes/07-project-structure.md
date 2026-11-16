# 프로젝트 구조

## 세 덩어리

```
PhotoTidyCore/      로직 패키지 (화면·사진첩을 모름)
PhotoTidy/          앱 (사진첩·지도 접근 + 화면)
PhotoTidyUITests/   화면 자동 테스트
```

## 왜 로직을 따로 뗐나

"비슷한 사진을 어떻게 묶나", "어느 사진을 추천하나" 같은 **판단 규칙**은 화면이나 사진첩 없이도 성립합니다.
이걸 따로 떼어 두면:

- **테스트가 빠릅니다.** 시뮬레이터를 띄우지 않고 맥에서 0.5초 만에 74개를 돌립니다.
- **테스트가 쉽습니다.** 실제 사진 없이 "시각 0초, 60초, 120초인 사진 세 장" 같은 가짜 데이터로 확인합니다.
- **경계가 분명합니다.** 로직이 화면 코드에 섞이지 않습니다.

웹으로 치면 계산 함수를 React 컴포넌트 밖 `utils/`로 빼고 Jest로 테스트하는 것과 같습니다.

### 순수 함수

같은 입력에 항상 같은 결과를 주고, 바깥 상태를 바꾸지 않는 함수입니다.

```swift
TimelineBuilder.stops(photos, radius: 200)     // 사진 목록 → 머문 곳 목록
```

순수 함수는 테스트하기 가장 쉽습니다. 그래서 **"판단은 순수 함수로, 바깥과 닿는 부분은 얇게"** 가 좋은 구조의 기본입니다.

### 의존성 주입

`SegmentProcessor.process`는 사진을 직접 읽지 않고, "ID를 주면 이미지를 돌려주는 함수"를 **인자로 받습니다.**

```swift
process(segment, loadImage: { id in library.analysisImage(id: id) })   // 앱: 진짜 사진첩
process(segment, loadImage: { id in testImages[id] })                  // 테스트: 가짜 이미지
```

필요한 것을 안에서 만들지 않고 밖에서 넣어 주는 것을 **의존성 주입**이라고 합니다. 덕분에 테스트에서 가짜로 바꿔 끼울 수 있습니다.

## Swift Package

`Package.swift`가 있는 폴더가 패키지입니다. npm 패키지와 같은 개념이고, 이 프로젝트는 저장소 안에 두고 씁니다(로컬 패키지).

```bash
swift test --package-path PhotoTidyCore
```

## XcodeGen

Xcode 프로젝트 파일(`.xcodeproj`)은 사람이 읽기 어렵고, 파일 하나만 추가해도 크게 바뀌어 git 충돌이 잘 납니다.
그래서 짧은 설정 파일 `project.yml`만 관리하고, 프로젝트 파일은 그때그때 **생성**합니다.

```bash
xcodegen generate
```

- `project.yml`: git에 올림 (원본)
- `PhotoTidy.xcodeproj`, `Info.plist`: git에 안 올림 (생성물)

`package.json`은 올리고 `node_modules`는 안 올리는 것과 같습니다. **"생성할 수 있는 것은 저장소에 넣지 않는다"** 는 일반 원칙입니다.

## 타깃

타깃은 "빌드 결과물 하나"입니다. 이 프로젝트에는 두 개가 있습니다.

| 타깃 | 결과물 |
| --- | --- |
| `PhotoTidy` | 앱 |
| `PhotoTidyUITests` | 앱을 조작하는 테스트 묶음 |

## 조정값을 한곳에

```swift
public enum Tuning {
    public static let maxGap: TimeInterval = 60
    public static let distanceThreshold: Float = 0.5
    public static let stopRadius: Double = 200
}
```

코드 곳곳에 `60`, `0.5` 같은 숫자를 직접 쓰면(매직 넘버) 뜻을 알 수 없고 바꾸기도 어렵습니다. 이름을 붙여 한곳에 모읍니다.
색도 같은 이유로 `Theme.swift`에 모았습니다.

## 폴더 문서 지도

| 위치 | 내용 |
| --- | --- |
| `README.md` | 실행·테스트 방법 |
| `CLAUDE.md` | Claude가 작업할 때 지킬 규칙 |
| `docs/superpowers/specs/` | 기능별 설계 문서 |
| `llm-wiki/` | 프로젝트 지식(구조, 결정, 알려진 문제) |
| `dev-notes/` | 일반 개발 지식(이 폴더) |
