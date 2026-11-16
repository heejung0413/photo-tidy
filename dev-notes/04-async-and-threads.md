# 비동기와 스레드

## async/await는 JS와 거의 같다

```swift
func loadDays() async {
    days = await library.photoDays()
}
```

오래 걸리는 일을 기다리는 동안 다른 일을 할 수 있게 해 줍니다. 문법도 뜻도 JS와 같습니다.

## 다른 점: 스레드가 여러 개다

JS는 일하는 사람이 한 명(싱글 스레드)이라, `await` 중에는 화면이 멈추지 않습니다.
Swift는 일하는 사람이 여러 명이고, 그중 **화면 담당(메인 스레드)** 이 따로 있습니다.

| | 하는 일 |
| --- | --- |
| 메인 스레드 | 화면 그리기, 터치 받기 |
| 백그라운드 스레드 | 오래 걸리는 계산, 파일·사진 읽기 |

**규칙 두 가지**

1. 화면은 메인 스레드에서만 바꾼다.
2. 오래 걸리는 일을 메인 스레드에서 하면 화면이 멈춘다(스크롤이 끊기고 버튼이 안 눌림).

## `@MainActor` — "이건 화면 담당이 한다"

```swift
@MainActor
@Observable
final class TimelineModel { ... }
```

이 클래스의 코드는 전부 메인 스레드에서 돕니다. 화면이 읽는 상태라서 그렇습니다.

## `Task.detached` — "이건 다른 사람에게 맡긴다"

```swift
let photos = await Task.detached(priority: .userInitiated) {
    library.timelinePhotos(on: newDay)      // 사진첩 읽기: 오래 걸림
}.value
stops = TimelineBuilder.stops(photos)       // 결과를 받아 화면 상태에 넣기
```

사진첩을 읽는 무거운 일은 백그라운드로 보내고, 끝나면 결과만 받아 옵니다.
웹의 Web Worker와 같은 생각입니다.

코드 리뷰에서 받은 지적 하나가 정확히 이 문제였습니다. 위 코드의 둘째 줄(`TimelineBuilder.stops`)은 메인 스레드에서 돌기 때문에, 사진이 만 장쯤 되면 화면이 잠깐 멈춥니다.

## 작업 취소

사용자가 "이전 날"을 빠르게 여러 번 누르면, 앞 날짜를 읽던 작업은 쓸모가 없어집니다.

```swift
loadTask?.cancel()              // 앞 작업에 "그만해" 신호
loadTask = Task {
    let photos = await ...
    if Task.isCancelled { return }   // 신호가 왔으면 결과를 버림
    stops = ...
}
```

중요한 점: **취소는 강제 종료가 아니라 "신호"입니다.** 작업 쪽에서 `Task.isCancelled`를 확인해야 실제로 멈춥니다.
확인을 안 하면 늦게 끝난 옛 작업이 새 결과를 덮어씁니다. 웹에서 "늦게 온 응답이 최신 화면을 덮어쓰는" 문제와 같습니다(`AbortController`로 푸는 그 문제).

## 경쟁 상태(race condition)

두 작업이 같은 것을 동시에 건드려서, 순서에 따라 결과가 달라지는 문제입니다. 이 프로젝트의 실제 사례입니다.

- **공유 이미지 만들기 도중 날짜 바꾸기**: 이미지를 만드는 데 몇 초 걸리는데, 그 사이 날짜를 바꾸면 A날 사진에 B날 제목이 붙습니다.
- **장소 이름 요청 겹치기**: 앞 요청이 안 끝났는데 새 요청을 보내 실패합니다.

해결 방향은 대체로 셋 중 하나입니다.

1. 시작할 때 필요한 값을 **복사해 두고** 그 값만 쓴다.
2. 진행 중에는 버튼을 **막는다**.
3. 끝났을 때 "아직 내가 최신 작업인지" **확인한다**.

## `AsyncStream` — 값이 여러 번 오는 비동기

사진 한 장을 요청하면 **흐린 미리보기가 먼저, 선명한 원본이 나중에** 옵니다. 값이 두 번 오므로 `await` 한 번으로는 못 받습니다.

```swift
for await image in library.displayImages(id: id, targetSize: size) {
    self.image = image        // 올 때마다 화면 갱신
}
```

JS의 `for await (const x of stream)`과 같습니다.

## 콜백을 async로 바꾸기

애플의 오래된 API는 콜백 방식입니다. JS에서 콜백을 `new Promise`로 감싸듯, Swift는 `AsyncStream`이나 `withCheckedContinuation`으로 감쌉니다(`PhotoLibrary.displayImages`).
