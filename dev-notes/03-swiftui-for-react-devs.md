# React 개발자를 위한 SwiftUI

SwiftUI는 React와 생각하는 방식이 거의 같습니다. **상태가 바뀌면 화면을 다시 그린다.**

## 대응표

| React | SwiftUI | 이 프로젝트의 예 |
| --- | --- | --- |
| 컴포넌트 | `View` (struct) | `HomeView`, `TimelineView` |
| JSX의 `return` | `var body: some View` | 모든 화면 |
| `useState` | `@State` | `@State private var viewing: TimelinePhoto?` |
| 전역 스토어(Zustand 등) | `@Observable` 클래스 | `AppModel`, `TimelineModel` |
| Context | `@Environment` | `@Environment(TimelineModel.self) private var model` |
| `useEffect(() => {...}, [dep])` | `.task(id: dep) { ... }` | `.task(id: hasAccess) { await model.loadDays() }` |
| `props` | struct의 속성 | `AssetImage(id:targetSize:)` |
| CSS / className | 수식어(modifier) | `.font(.headline).padding()` |
| React Router | `NavigationStack` | `HomeView` |
| 조건부 렌더링 `{a && <X/>}` | `if a { X() }` | `if !pins.isEmpty { map }` |
| `list.map(x => <Row key=.../>)` | `ForEach(list) { Row($0) }` | 머문 곳 목록 |

## 화면 하나의 모양

```swift
struct GroupListView: View {
    @Environment(AppModel.self) private var model     // 스토어에서 꺼내기

    var body: some View {                              // 화면 내용
        List(model.visibleGroups) { group in
            Text("비슷한 사진 \(group.photos.count)장")
        }
        .navigationTitle("비슷한 사진 묶음")            // 수식어
    }
}
```

## 수식어는 CSS가 아니라 "감싸기"

```swift
Text("1")
    .padding(8)
    .background(.blue)     // 여백까지 파랗게

Text("1")
    .background(.blue)
    .padding(8)            // 글자만 파랗고 바깥에 여백
```

수식어는 뷰를 한 겹씩 감쌉니다. 그래서 **순서가 결과를 바꿉니다.** CSS 속성처럼 순서와 무관하지 않습니다.

## 레이아웃

| SwiftUI | CSS로 치면 |
| --- | --- |
| `VStack` | `flex-direction: column` |
| `HStack` | `flex-direction: row` |
| `ZStack` | 겹쳐 놓기 (`position: absolute`) |
| `Spacer()` | `flex: 1`인 빈 칸 |
| `ScrollView` | `overflow: auto` |
| `List` | 기본 스타일이 있는 스크롤 목록 |

### Lazy가 붙은 것과 아닌 것

- `VStack`: 안의 것을 **전부** 한 번에 만듭니다.
- `LazyVStack`, `List`: **화면에 보이는 것만** 만듭니다.

항목이 수백 개면 차이가 큽니다. 이 프로젝트의 앨범 타임라인이 `VStack`이라 큰 앨범에서 느려질 수 있다는 지적을 코드 리뷰에서 받아 `LazyVStack`으로 바꿨습니다. 웹의 "가상 스크롤"과 같은 개념입니다.

## 상태 관리

### `@State` — 그 화면만 아는 상태

```swift
@State private var isPickingDate = false      // 달력 창이 열렸는지
```

### `@Observable` — 여러 화면이 같이 보는 상태

```swift
@Observable
final class TimelineModel {
    private(set) var stops: [TimelineStop] = []    // 바뀌면 이걸 읽는 화면이 다시 그려짐
}
```

`private(set)`은 "밖에서 읽을 수는 있지만 고칠 수는 없다"는 뜻입니다. 상태는 모델의 함수로만 바꾸게 합니다(Redux의 "액션으로만 바꾼다"와 같은 생각).

### 앱 시작점에서 주입

```swift
TabView { HomeView(); TimelineView() }
    .environment(model)          // Context.Provider
    .environment(timeline)
```

## 화면 이동

```swift
NavigationStack {
    NavigationLink("묶음 보기", value: Route.groupList)       // 링크: "이 값으로 가라"
        .navigationDestination(for: Route.self) { _ in       // 라우트 등록: "이 값이 오면 이 화면"
            GroupListView()
        }
}
```

값을 넘기는 방식과 화면을 직접 넣는 방식(`NavigationLink { 화면 }`)이 있는데, **한 스택에서 섞으면 화면 순서가 꼬입니다.** 실제로 이 프로젝트에서 "눌러도 안 넘어가는" 버그가 났고, 값 방식으로 통일해 고쳤습니다.

## 창 띄우기

| 종류 | 수식어 |
| --- | --- |
| 아래에서 올라오는 창 | `.sheet(item: $viewing) { ... }` |
| 알림 창 | `.alert("장소 이름", isPresented: ...) { ... }` |
| 메뉴 | `Menu { Button... } label: { ... }` |

`$viewing`의 `$`는 "값을 읽고 쓸 수 있는 연결(바인딩)"을 넘긴다는 뜻입니다. React에서 `value`와 `onChange`를 같이 넘기는 것과 같습니다.

## 접근성 이름

```swift
Image(systemName: "pencil")
    .accessibilityLabel("장소 이름 바꾸기")
```

웹의 `aria-label`입니다. 화면 읽기 기능이 읽어 주고, **화면 자동 테스트도 이 이름으로 버튼을 찾습니다.** 그래서 이름을 바꾸면 테스트가 깨집니다.
