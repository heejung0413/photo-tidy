# JS 개발자를 위한 Swift

## 변수

```swift
let name = "카페"      // const — 바꿀 수 없음
var count = 0          // let   — 바꿀 수 있음
```

이름이 JS와 엇갈립니다. Swift의 `let`이 JS의 `const`입니다. 기본은 `let`을 쓰고, 바꿔야 할 때만 `var`.

## 타입

TypeScript처럼 타입이 있고, 대부분 자동으로 추론됩니다.

```swift
let radius: Double = 200      // 직접 적기
let radius = 200.0            // 추론 (Double)
let ids: [String] = []        // 배열
let names: [String: String] = [:]   // 딕셔너리 (JS의 객체/Map)
```

## 옵셔널 — `null`을 타입으로 다루기

Swift에는 `undefined`가 없고 `nil`만 있습니다. 그리고 **nil이 될 수 있는 값은 타입에 `?`를 붙여 표시**해야 합니다.

```swift
let center: Coordinate?       // 좌표가 없을 수도 있음
```

`?`가 붙은 값은 그냥 쓸 수 없고, 꺼내는 절차가 필요합니다.

| 하고 싶은 것 | Swift | JS로 치면 |
| --- | --- | --- |
| 있으면 쓰기 | `if let center = stop.center { ... }` | `if (stop.center != null) { ... }` |
| 없으면 함수 끝내기 | `guard let center = stop.center else { return }` | `if (stop.center == null) return` |
| 없으면 기본값 | `names[id] ?? "장소 1"` | `names[id] ?? "장소 1"` |
| 있을 때만 이어 가기 | `days.first?.day` | `days[0]?.day` |

`guard`는 "조건이 안 맞으면 일찍 나가기" 전용 문법입니다. 이 프로젝트 곳곳에 있습니다.

```swift
guard !located.isEmpty else { return nil }
```

덕분에 "null인 줄 모르고 썼다가 터지는" 실수를 컴파일 단계에서 막습니다.

## struct와 class

| | struct | class |
| --- | --- | --- |
| 넘길 때 | **복사**됨 | 같은 것을 가리킴(참조) |
| 쓰는 곳 | 데이터(사진 정보, 좌표, 묶음) | 상태를 오래 들고 있는 것(모델) |

```swift
struct Coordinate { let latitude: Double; let longitude: Double }   // 값
final class TimelineModel { ... }                                    // 상태 보관
```

JS 객체는 항상 참조라서 "한 곳에서 고쳤더니 다른 곳도 바뀌는" 일이 생기는데, struct는 복사라서 그런 일이 없습니다. Swift는 struct를 기본으로 씁니다.

## enum — 경우의 수를 타입으로

```swift
enum Source: Hashable {
    case daily                 // 하루씩 보기
    case album(PhotoAlbum)     // 앨범 보기 (어느 앨범인지 값을 들고 있음)
}
```

TypeScript의 `type Source = { kind: 'daily' } | { kind: 'album', album: PhotoAlbum }`과 같습니다.
`switch`로 나눠 처리하고, 빠뜨린 경우가 있으면 컴파일 오류가 납니다.

## 함수와 인자 이름

```swift
func distance(_ a: Coordinate, _ b: Coordinate) -> Double
func show(_ newDay: Date)
func rename(_ stop: TimelineStop, to text: String)

rename(stop, to: "우리 카페")     // 부를 때 인자 이름을 적는다
```

- 부를 때 인자 이름을 적는 게 기본입니다. 문장처럼 읽히게 하려는 것입니다.
- 앞에 `_`를 쓰면 이름을 생략할 수 있습니다.

## 클로저 — 화살표 함수

```swift
photos.sorted { $0.takenAt < $1.takenAt }        // (a, b) => a.takenAt < b.takenAt
stops.map { $0.photos.count }                    // s => s.photos.length
albums.filter(\.isShared)                        // a => a.isShared
```

- `$0`, `$1`은 첫째, 둘째 인자를 가리키는 줄임말입니다.
- `\.isShared`는 "그 속성을 꺼내라"는 줄임말(키 경로)입니다.

## extension — 나중에 기능 덧붙이기

이미 있는 타입에 함수를 추가합니다. 파일을 주제별로 나눌 때 씁니다.

```swift
extension PhotoLibrary {            // PhotoLibrary+Albums.swift
    func albums() -> [PhotoAlbum] { ... }
}
```

## 접근 범위

| 키워드 | 보이는 범위 |
| --- | --- |
| `private` | 그 타입(파일) 안에서만 |
| (안 적음) | 같은 모듈 안 |
| `public` | 다른 모듈에서도 |

이 프로젝트는 로직을 별도 패키지(`PhotoTidyCore`)로 나눴기 때문에, 앱에서 쓰려면 `public`을 붙여야 합니다. JS의 `export`와 같습니다.
한 번은 `public init`을 빠뜨려서 앱이 빌드되지 않았습니다.

## 자주 보이는 프로토콜

프로토콜은 TypeScript의 `interface`입니다. "이 타입은 이런 걸 할 수 있다"는 약속입니다.

| 프로토콜 | 뜻 |
| --- | --- |
| `Identifiable` | `id`가 있다 (목록에 쓸 때 필요, React의 `key`) |
| `Hashable` / `Equatable` | 서로 같은지 비교할 수 있다 |
| `Codable` | JSON으로 저장하고 읽을 수 있다 |
| `Sendable` | 여러 스레드에 넘겨도 안전하다 |
