# Photo Tidy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰 사진첩에서 연달아 찍은 비슷한 사진을 묶고, 추천 한 장을 남기고 나머지를 지우는 개인용 iOS 앱을 만든다.

**Architecture:** 로직은 화면·사진첩에 의존하지 않는 로컬 Swift 패키지 `PhotoTidyCore`에 두고 맥에서 `swift test`로 검증한다. 앱 타깃 `PhotoTidy`는 Photos 래퍼(`PhotoLibrary`), 상태 저장소(`AppModel`), SwiftUI 화면 3개만 가진다. Xcode 프로젝트 파일은 `project.yml`에서 XcodeGen으로 생성한다.

**Tech Stack:** Swift 5 언어 모드(툴체인 6.2), SwiftUI, Photos, Vision, XCTest, XcodeGen. iOS 17 이상. 외부 라이브러리 없음.

**설계 문서:** `docs/superpowers/specs/2026-11-16-photo-tidy-design.md`

---

## 파일 구조

```
photo-tidy/
├── .gitignore
├── README.md
├── project.yml                          XcodeGen 설정(앱 타깃, Info.plist 값)
├── PhotoTidyCore/
│   ├── Package.swift
│   ├── Sources/PhotoTidyCore/
│   │   ├── Models.swift                 PhotoItem, PhotoMetrics, StoredPhoto, StoredGroup
│   │   ├── Tuning.swift                 조정 가능한 상수
│   │   ├── SimilarityGrouper.swift      시간 구간 나누기 + 묶기
│   │   ├── BestShotPicker.swift         추천 사진 고르기
│   │   ├── GroupStore.swift             StoreState(합치기·정리) + JSON 저장
│   │   ├── ImageAnalyzer.swift          Vision 지문·얼굴 품질 + 선명도
│   │   └── SegmentProcessor.swift       구간 하나: 분석 → 묶기 → 추천
│   └── Tests/PhotoTidyCoreTests/
│       ├── Fixtures.swift
│       ├── SimilarityGrouperTests.swift
│       ├── BestShotPickerTests.swift
│       ├── GroupStoreTests.swift
│       └── ImageAnalyzerTests.swift
└── PhotoTidy/
    ├── PhotoTidyApp.swift
    ├── AppModel.swift
    ├── PhotoLibrary.swift
    └── Views/
        ├── AssetImage.swift
        ├── HomeView.swift
        ├── GroupListView.swift
        └── GroupDetailView.swift
```

모든 명령은 저장소 루트 `/Users/imheejung/project/photo-tidy` 기준이다. Core 테스트는 `swift test --package-path PhotoTidyCore`로 돌린다.

---

### Task 1: 패키지 뼈대와 모델

**Files:**
- Create: `.gitignore`, `PhotoTidyCore/Package.swift`, `PhotoTidyCore/Sources/PhotoTidyCore/Models.swift`, `PhotoTidyCore/Sources/PhotoTidyCore/Tuning.swift`, `PhotoTidyCore/Tests/PhotoTidyCoreTests/Fixtures.swift`

- [ ] **Step 1: `.gitignore`**

```
.DS_Store
.build/
build/
*.xcodeproj
xcuserdata/
```

- [ ] **Step 2: `PhotoTidyCore/Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotoTidyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PhotoTidyCore", targets: ["PhotoTidyCore"])],
    targets: [
        .target(name: "PhotoTidyCore"),
        .testTarget(name: "PhotoTidyCoreTests", dependencies: ["PhotoTidyCore"]),
    ]
)
```

- [ ] **Step 3: `Models.swift`**

```swift
import Foundation

public struct PhotoItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let takenAt: Date
    public let isFavorite: Bool
    public let isEdited: Bool
    public let pixelCount: Int

    public init(id: String, takenAt: Date, isFavorite: Bool, isEdited: Bool, pixelCount: Int) {
        self.id = id
        self.takenAt = takenAt
        self.isFavorite = isFavorite
        self.isEdited = isEdited
        self.pixelCount = pixelCount
    }
}

public struct PhotoMetrics: Hashable, Codable, Sendable {
    public let sharpness: Double
    public let faceQuality: Double?

    public init(sharpness: Double, faceQuality: Double?) {
        self.sharpness = sharpness
        self.faceQuality = faceQuality
    }
}

public struct StoredPhoto: Hashable, Codable, Sendable {
    public let item: PhotoItem
    public let metrics: PhotoMetrics

    public init(item: PhotoItem, metrics: PhotoMetrics) {
        self.item = item
        self.metrics = metrics
    }
}

/// 사진이 항상 2장 이상이고 촬영 시각순으로 정렬돼 있다.
public struct StoredGroup: Identifiable, Hashable, Codable, Sendable {
    public var photos: [StoredPhoto]
    public var recommendedID: String
    public var isSkipped: Bool

    public var id: String { photos[0].item.id }

    public init(photos: [StoredPhoto], recommendedID: String, isSkipped: Bool) {
        self.photos = photos
        self.recommendedID = recommendedID
        self.isSkipped = isSkipped
    }
}
```

- [ ] **Step 4: `Tuning.swift`**

```swift
import Foundation

public enum Tuning {
    /// 앞 사진과 이 시간(초) 이내면 같은 구간으로 본다.
    public static let maxGap: TimeInterval = 60
    /// 지문 거리가 이 값 이하면 비슷한 사진으로 본다.
    public static let distanceThreshold: Float = 0.5
    /// 확보 용량 어림용: 픽셀당 바이트.
    public static let estimatedBytesPerPixel: Double = 0.2
}
```

- [ ] **Step 5: `Fixtures.swift`**

```swift
import Foundation
@testable import PhotoTidyCore

func photo(_ id: String, at t: TimeInterval = 0, favorite: Bool = false,
           edited: Bool = false, pixels: Int = 1000) -> PhotoItem {
    PhotoItem(id: id, takenAt: Date(timeIntervalSinceReferenceDate: t),
              isFavorite: favorite, isEdited: edited, pixelCount: pixels)
}

func stored(_ id: String, at t: TimeInterval = 0, sharpness: Double = 1, face: Double? = nil,
            favorite: Bool = false, edited: Bool = false, pixels: Int = 1000) -> StoredPhoto {
    StoredPhoto(item: photo(id, at: t, favorite: favorite, edited: edited, pixels: pixels),
                metrics: PhotoMetrics(sharpness: sharpness, faceQuality: face))
}
```

- [ ] **Step 6: 빌드 확인**

Run: `swift build --package-path PhotoTidyCore`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add .gitignore PhotoTidyCore
git commit -m "chore: PhotoTidyCore 패키지 뼈대와 모델 추가"
```

---

### Task 2: SimilarityGrouper

**Files:**
- Create: `PhotoTidyCore/Sources/PhotoTidyCore/SimilarityGrouper.swift`
- Test: `PhotoTidyCore/Tests/PhotoTidyCoreTests/SimilarityGrouperTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import PhotoTidyCore

final class SimilarityGrouperTests: XCTestCase {
    private func distance(_ table: [String: Float]) -> (PhotoItem, PhotoItem) -> Float? {
        { a, b in table["\(a.id)|\(b.id)"] ?? table["\(b.id)|\(a.id)"] }
    }

    func testSegmentsSplitWhenGapExceedsMaxGap() {
        let photos = [photo("a", at: 0), photo("b", at: 30), photo("c", at: 90),
                      photo("d", at: 200), photo("e", at: 201)]
        let segments = SimilarityGrouper.segments(photos, maxGap: 60)
        XCTAssertEqual(segments.map { $0.map(\.id) }, [["a", "b", "c"], ["d", "e"]])
    }

    func testSegmentsSortByTime() {
        let segments = SimilarityGrouper.segments([photo("b", at: 10), photo("a", at: 0)], maxGap: 60)
        XCTAssertEqual(segments.map { $0.map(\.id) }, [["a", "b"]])
    }

    func testGroupsChainSimilarPhotosAndDropSingles() {
        let segment = [photo("a", at: 0), photo("b", at: 1), photo("c", at: 2), photo("d", at: 3)]
        let table: [String: Float] = ["a|b": 0.2, "b|c": 0.4, "a|c": 0.9, "a|d": 0.9, "b|d": 0.9, "c|d": 0.9]
        let groups = SimilarityGrouper.groups(in: segment, threshold: 0.5, distance: distance(table))
        XCTAssertEqual(groups.map { $0.map(\.id) }, [["a", "b", "c"]])
    }

    func testGroupsCanProduceTwoGroupsInOneSegment() {
        let segment = [photo("a", at: 0), photo("b", at: 1), photo("c", at: 2), photo("d", at: 3)]
        let table: [String: Float] = ["a|b": 0.1, "c|d": 0.1, "a|c": 0.9, "a|d": 0.9, "b|c": 0.9, "b|d": 0.9]
        let groups = SimilarityGrouper.groups(in: segment, threshold: 0.5, distance: distance(table))
        XCTAssertEqual(groups.map { $0.map(\.id) }, [["a", "b"], ["c", "d"]])
    }

    func testGroupsTreatMissingDistanceAsNotSimilar() {
        let segment = [photo("a", at: 0), photo("b", at: 1)]
        let groups = SimilarityGrouper.groups(in: segment, threshold: 0.5, distance: distance([:]))
        XCTAssertTrue(groups.isEmpty)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path PhotoTidyCore --filter SimilarityGrouperTests`
Expected: 컴파일 오류 `cannot find 'SimilarityGrouper' in scope`

- [ ] **Step 3: 구현**

```swift
import Foundation

public enum SimilarityGrouper {
    /// 촬영 시각순으로 정렬한 뒤, 앞 사진과의 간격이 maxGap 이내인 사진끼리 한 구간으로 잇는다.
    public static func segments(_ photos: [PhotoItem], maxGap: TimeInterval = Tuning.maxGap) -> [[PhotoItem]] {
        var result: [[PhotoItem]] = []
        for photo in photos.sorted(by: { $0.takenAt < $1.takenAt }) {
            if let last = result.last?.last, photo.takenAt.timeIntervalSince(last.takenAt) <= maxGap {
                result[result.count - 1].append(photo)
            } else {
                result.append([photo])
            }
        }
        return result
    }

    /// 구간 안에서 거리가 threshold 이하인 사진을 연결하고, 연결된 덩어리 중 2장 이상인 것만 돌려준다.
    public static func groups(in segment: [PhotoItem],
                              threshold: Float = Tuning.distanceThreshold,
                              distance: (PhotoItem, PhotoItem) -> Float?) -> [[PhotoItem]] {
        var parent = Array(segment.indices)
        func find(_ start: Int) -> Int {
            var i = start
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        for i in segment.indices {
            for j in segment.indices where j > i {
                guard let d = distance(segment[i], segment[j]), d <= threshold else { continue }
                let (a, b) = (find(i), find(j))
                parent[a] = b
            }
        }
        var buckets: [Int: [PhotoItem]] = [:]
        for i in segment.indices {
            buckets[find(i), default: []].append(segment[i])
        }
        return buckets.values
            .filter { $0.count >= 2 }
            .sorted { $0[0].takenAt < $1[0].takenAt }
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --package-path PhotoTidyCore --filter SimilarityGrouperTests`
Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add PhotoTidyCore
git commit -m "feat: 시간 구간과 거리로 비슷한 사진 묶기"
```

---

### Task 3: BestShotPicker

**Files:**
- Create: `PhotoTidyCore/Sources/PhotoTidyCore/BestShotPicker.swift`
- Test: `PhotoTidyCore/Tests/PhotoTidyCoreTests/BestShotPickerTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import PhotoTidyCore

final class BestShotPickerTests: XCTestCase {
    func testEmptyReturnsNil() {
        XCTAssertNil(BestShotPicker.pick([]))
    }

    func testSharpestWinsWhenNoFaces() {
        let picked = BestShotPicker.pick([stored("a", sharpness: 3), stored("b", sharpness: 9), stored("c", sharpness: 5)])
        XCTAssertEqual(picked, "b")
    }

    func testFavoriteBeatsSharper() {
        let picked = BestShotPicker.pick([stored("a", sharpness: 9), stored("b", sharpness: 1, favorite: true)])
        XCTAssertEqual(picked, "b")
    }

    func testFaceQualityCountsWhenEveryPhotoHasFace() {
        // a: 1.0*0.5 + 0.1*0.4 = 0.54, b: 0.8*0.5 + 0.9*0.4 = 0.76, c: 0 + 0.5*0.4 = 0.2
        let picked = BestShotPicker.pick([stored("a", sharpness: 10, face: 0.1),
                                          stored("b", sharpness: 8, face: 0.9),
                                          stored("c", sharpness: 0, face: 0.5)])
        XCTAssertEqual(picked, "b")
    }

    func testFaceIgnoredWhenAnyPhotoHasNoFace() {
        let picked = BestShotPicker.pick([stored("a", sharpness: 10, face: 0.1),
                                          stored("b", sharpness: 8, face: 0.9),
                                          stored("c", sharpness: 0, face: nil)])
        XCTAssertEqual(picked, "a")
    }

    func testEditedBreaksEqualSharpness() {
        let picked = BestShotPicker.pick([stored("a", sharpness: 5), stored("b", sharpness: 5, edited: true)])
        XCTAssertEqual(picked, "b")
    }

    func testTieGoesToMorePixelsThenLater() {
        XCTAssertEqual(BestShotPicker.pick([stored("a", pixels: 2000), stored("b", pixels: 1000)]), "a")
        XCTAssertEqual(BestShotPicker.pick([stored("a", at: 0), stored("b", at: 5)]), "b")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path PhotoTidyCore --filter BestShotPickerTests`
Expected: 컴파일 오류 `cannot find 'BestShotPicker' in scope`

- [ ] **Step 3: 구현**

```swift
import Foundation

public enum BestShotPicker {
    /// 추천 사진의 id. 즐겨찾기가 있으면 그중에서만 고른다.
    public static func pick(_ photos: [StoredPhoto]) -> String? {
        let favorites = photos.filter { $0.item.isFavorite }
        let pool = favorites.isEmpty ? photos : favorites
        guard let lo = pool.map(\.metrics.sharpness).min(),
              let hi = pool.map(\.metrics.sharpness).max() else { return nil }
        let useFaces = pool.allSatisfy { $0.metrics.faceQuality != nil }

        func score(_ photo: StoredPhoto) -> Double {
            let sharp = hi > lo ? (photo.metrics.sharpness - lo) / (hi - lo) : 0
            let edited = photo.item.isEdited ? 1.0 : 0.0
            if useFaces, let face = photo.metrics.faceQuality {
                return sharp * 0.5 + face * 0.4 + edited * 0.1
            }
            return sharp * 0.9 + edited * 0.1
        }

        return pool.max { a, b in
            let (sa, sb) = (score(a), score(b))
            if sa != sb { return sa < sb }
            if a.item.pixelCount != b.item.pixelCount { return a.item.pixelCount < b.item.pixelCount }
            return a.item.takenAt < b.item.takenAt
        }?.item.id
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --package-path PhotoTidyCore --filter BestShotPickerTests`
Expected: `Executed 7 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add PhotoTidyCore
git commit -m "feat: 묶음에서 추천 사진 고르기"
```

---

### Task 4: StoreState와 GroupStore

**Files:**
- Create: `PhotoTidyCore/Sources/PhotoTidyCore/GroupStore.swift`
- Test: `PhotoTidyCore/Tests/PhotoTidyCoreTests/GroupStoreTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import PhotoTidyCore

final class GroupStoreTests: XCTestCase {
    private func group(_ ids: [String], recommended: String, skipped: Bool = false) -> StoredGroup {
        let photos = ids.enumerated().map { stored($1, at: TimeInterval($0), sharpness: Double($0)) }
        return StoredGroup(photos: photos, recommendedID: recommended, isSkipped: skipped)
    }

    func testSaveAndLoadRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GroupStore(url: url)
        let state = StoreState(groups: [group(["a", "b"], recommended: "b")],
                               watermark: Date(timeIntervalSinceReferenceDate: 100))
        try store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testLoadMissingFileGivesEmptyState() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        XCTAssertEqual(GroupStore(url: url).load(), StoreState())
    }

    func testResumeDateIsWatermarkMinusMaxGap() {
        let state = StoreState(watermark: Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertEqual(state.resumeDate, Date(timeIntervalSinceReferenceDate: 100 - Tuning.maxGap))
        XCTAssertNil(StoreState().resumeDate)
    }

    func testPruneRemovesMissingPhotosAndSmallGroups() {
        var state = StoreState(groups: [group(["a", "b", "c"], recommended: "c"), group(["x", "y"], recommended: "y")])
        state.prune(existing: ["a", "b", "x"])
        XCTAssertEqual(state.groups.count, 1)
        XCTAssertEqual(state.groups[0].photos.map(\.item.id), ["a", "b"])
        XCTAssertEqual(state.groups[0].recommendedID, "b") // c가 사라져 다시 고름(더 선명한 b)
    }

    func testMergeAppendsGroupWithoutOverlap() {
        var state = StoreState(groups: [group(["a", "b"], recommended: "b")])
        state.merge([group(["x", "y"], recommended: "y")])
        XCTAssertEqual(state.groups.count, 2)
    }

    func testMergeUnionsOverlappingGroupAndUnhides() {
        var state = StoreState(groups: [group(["a", "b"], recommended: "b", skipped: true)])
        let incoming = StoredGroup(photos: [stored("b", at: 1, sharpness: 1), stored("c", at: 2, sharpness: 9)],
                                   recommendedID: "c", isSkipped: false)
        state.merge([incoming])
        XCTAssertEqual(state.groups.count, 1)
        XCTAssertEqual(state.groups[0].photos.map(\.item.id), ["a", "b", "c"])
        XCTAssertEqual(state.groups[0].recommendedID, "c")
        XCTAssertFalse(state.groups[0].isSkipped)
    }

    func testMergeKeepsHiddenGroupWhenNothingNew() {
        let hidden = group(["a", "b"], recommended: "a", skipped: true)
        var state = StoreState(groups: [hidden])
        state.merge([group(["a", "b"], recommended: "b")])
        XCTAssertEqual(state.groups, [hidden])
    }

    func testResolveHidesGroupWhenTwoOrMoreRemain() {
        var state = StoreState(groups: [group(["a", "b", "c"], recommended: "c")])
        state.resolve(groupID: "a", deleted: ["a"])
        XCTAssertEqual(state.groups[0].photos.map(\.item.id), ["b", "c"])
        XCTAssertTrue(state.groups[0].isSkipped)
    }

    func testResolveRemovesGroupWhenOneRemains() {
        var state = StoreState(groups: [group(["a", "b", "c"], recommended: "c")])
        state.resolve(groupID: "a", deleted: ["a", "b"])
        XCTAssertTrue(state.groups.isEmpty)
    }

    func testSkipHidesGroup() {
        var state = StoreState(groups: [group(["a", "b"], recommended: "b")])
        state.skip(groupID: "a")
        XCTAssertTrue(state.groups[0].isSkipped)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path PhotoTidyCore --filter GroupStoreTests`
Expected: 컴파일 오류 `cannot find 'GroupStore' in scope`

- [ ] **Step 3: 구현**

```swift
import Foundation

public struct StoreState: Codable, Equatable, Sendable {
    public var groups: [StoredGroup]
    /// 분석을 마친 마지막 사진의 촬영 시각.
    public var watermark: Date?

    public init(groups: [StoredGroup] = [], watermark: Date? = nil) {
        self.groups = groups
        self.watermark = watermark
    }

    /// 다음 분석은 이 시각 이후 사진만 대상으로 한다.
    public var resumeDate: Date? { watermark?.addingTimeInterval(-Tuning.maxGap) }

    /// 사진첩에서 사라진 사진을 빼고, 2장 미만이 된 묶음을 지운다.
    public mutating func prune(existing: Set<String>) {
        groups = groups.compactMap { original in
            var group = original
            group.photos.removeAll { !existing.contains($0.item.id) }
            return Self.repaired(group)
        }
    }

    /// 새 묶음을 합친다. 기존 묶음과 사진을 공유하면 하나로 합치고 추천을 다시 고른다.
    public mutating func merge(_ incoming: [StoredGroup]) {
        for new in incoming {
            let newIDs = Set(new.photos.map(\.item.id))
            let overlapping = groups.filter { $0.photos.contains { newIDs.contains($0.item.id) } }
            guard !overlapping.isEmpty else {
                groups.append(new)
                continue
            }
            var byID: [String: StoredPhoto] = [:]
            for photo in overlapping.flatMap(\.photos) + new.photos {
                byID[photo.item.id] = photo
            }
            let photos = byID.values.sorted { ($0.item.takenAt, $0.item.id) < ($1.item.takenAt, $1.item.id) }
            if overlapping.count == 1, overlapping[0].photos.count == photos.count {
                continue // 새로 더해진 사진이 없으면 기존 묶음(추천·숨김 포함)을 그대로 둔다
            }
            groups.removeAll { overlapping.contains($0) }
            if let recommended = BestShotPicker.pick(photos) {
                groups.append(StoredGroup(photos: photos, recommendedID: recommended, isSkipped: false))
            }
        }
    }

    /// 삭제를 마친 묶음: 남은 사진이 2장 이상이면 숨기고, 아니면 지운다.
    public mutating func resolve(groupID: String, deleted: Set<String>) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        var group = groups[index]
        group.photos.removeAll { deleted.contains($0.item.id) }
        group.isSkipped = true
        if let repaired = Self.repaired(group) {
            groups[index] = repaired
        } else {
            groups.remove(at: index)
        }
    }

    public mutating func skip(groupID: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].isSkipped = true
    }

    private static func repaired(_ group: StoredGroup) -> StoredGroup? {
        guard group.photos.count >= 2 else { return nil }
        var group = group
        if !group.photos.contains(where: { $0.item.id == group.recommendedID }),
           let recommended = BestShotPicker.pick(group.photos) {
            group.recommendedID = recommended
        }
        return group
    }
}

public struct GroupStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// 파일이 없거나 읽을 수 없으면 빈 상태.
    public func load() -> StoreState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(StoreState.self, from: data) else {
            return StoreState()
        }
        return state
    }

    public func save(_ state: StoreState) throws {
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --package-path PhotoTidyCore --filter GroupStoreTests`
Expected: `Executed 10 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add PhotoTidyCore
git commit -m "feat: 분석 결과 저장과 합치기·정리 규칙"
```

---

### Task 5: ImageAnalyzer와 SegmentProcessor

**Files:**
- Create: `PhotoTidyCore/Sources/PhotoTidyCore/ImageAnalyzer.swift`, `PhotoTidyCore/Sources/PhotoTidyCore/SegmentProcessor.swift`
- Test: `PhotoTidyCore/Tests/PhotoTidyCoreTests/ImageAnalyzerTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

테스트 이미지는 코드로 직접 그린다(저장소에 사진 파일을 넣지 않는다).

```swift
import CoreGraphics
import CoreImage
import XCTest
@testable import PhotoTidyCore

final class ImageAnalyzerTests: XCTestCase {
    private func makeImage(_ draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context)
        return context.makeImage()!
    }

    private func checkerboard() -> CGImage {
        makeImage { context in
            for row in 0..<16 {
                for column in 0..<16 {
                    let white = (row + column) % 2 == 0
                    context.setFillColor(gray: white ? 1 : 0, alpha: 1)
                    context.fill(CGRect(x: column * 16, y: row * 16, width: 16, height: 16))
                }
            }
        }
    }

    private func scene(offset: CGFloat = 0) -> CGImage {
        makeImage { context in
            context.setFillColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            context.setFillColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
            context.fillEllipse(in: CGRect(x: 40 + offset, y: 60, width: 100, height: 100))
            context.setFillColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)
            context.fill(CGRect(x: 150 + offset, y: 140, width: 70, height: 50))
        }
    }

    private func blurred(_ image: CGImage) -> CGImage {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: input.extent)
        return CIContext().createCGImage(output, from: input.extent)!
    }

    func testSharpImageScoresHigherThanBlurred() {
        let sharp = checkerboard()
        XCTAssertGreaterThan(ImageAnalyzer.sharpness(sharp), ImageAnalyzer.sharpness(blurred(sharp)))
    }

    func testSimilarImagesAreCloserThanDifferentOnes() throws {
        let base = try ImageAnalyzer.analyze(scene())
        let shifted = try ImageAnalyzer.analyze(scene(offset: 6))
        let other = try ImageAnalyzer.analyze(checkerboard())
        let near = try XCTUnwrap(ImageAnalyzer.distance(base.featurePrint, shifted.featurePrint))
        let far = try XCTUnwrap(ImageAnalyzer.distance(base.featurePrint, other.featurePrint))
        XCTAssertLessThan(near, far)
    }

    func testImageWithoutFaceHasNoFaceQuality() throws {
        XCTAssertNil(try ImageAnalyzer.analyze(checkerboard()).metrics.faceQuality)
    }

    func testSegmentProcessorGroupsIdenticalImagesAndCountsUnreadable() {
        let images: [String: CGImage] = ["a": scene(), "b": scene(), "c": checkerboard()]
        let segment = [photo("a", at: 0), photo("b", at: 1), photo("c", at: 2), photo("d", at: 3)]
        let output = SegmentProcessor.process(segment, threshold: 0.01) { images[$0] }
        XCTAssertEqual(output.groups.map { $0.photos.map(\.item.id) }, [["a", "b"]])
        XCTAssertEqual(output.unreadable, 1)
        XCTAssertFalse(output.groups[0].isSkipped)
    }

    func testSegmentProcessorSkipsSinglePhotoSegment() {
        var loaded = 0
        let output = SegmentProcessor.process([photo("a")]) { _ in
            loaded += 1
            return nil
        }
        XCTAssertTrue(output.groups.isEmpty)
        XCTAssertEqual(output.unreadable, 0)
        XCTAssertEqual(loaded, 0)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path PhotoTidyCore --filter ImageAnalyzerTests`
Expected: 컴파일 오류 `cannot find 'ImageAnalyzer' in scope`

- [ ] **Step 3: `ImageAnalyzer.swift` 구현**

```swift
import CoreGraphics
import Foundation
import Vision

public struct ImageAnalysis {
    public let featurePrint: VNFeaturePrintObservation
    public let metrics: PhotoMetrics
}

public enum ImageAnalyzerError: Error {
    case noFeaturePrint
}

public enum ImageAnalyzer {
    public static func analyze(_ image: CGImage) throws -> ImageAnalysis {
        let printRequest = VNGenerateImageFeaturePrintRequest()
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([printRequest, faceRequest])
        guard let featurePrint = printRequest.results?.first else {
            throw ImageAnalyzerError.noFeaturePrint
        }
        let qualities = (faceRequest.results ?? []).compactMap { $0.faceCaptureQuality }.map(Double.init)
        let faceQuality = qualities.isEmpty ? nil : qualities.reduce(0, +) / Double(qualities.count)
        return ImageAnalysis(featurePrint: featurePrint,
                             metrics: PhotoMetrics(sharpness: sharpness(image), faceQuality: faceQuality))
    }

    /// 두 지문의 거리(작을수록 비슷). 비교할 수 없으면 nil.
    public static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var value: Float = 0
        do {
            try a.computeDistance(&value, to: b)
            return value
        } catch {
            return nil
        }
    }

    /// 256×256 흑백으로 줄인 뒤 라플라시안 값의 분산을 구한다. 클수록 선명하다.
    public static func sharpness(_ image: CGImage) -> Double {
        let side = 256
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 0 }

        var sum = 0.0
        var sumOfSquares = 0.0
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let i = y * side + x
                let laplacian = Double(4 * Int(pixels[i]) - Int(pixels[i - 1]) - Int(pixels[i + 1])
                    - Int(pixels[i - side]) - Int(pixels[i + side]))
                sum += laplacian
                sumOfSquares += laplacian * laplacian
            }
        }
        let count = Double((side - 2) * (side - 2))
        let mean = sum / count
        return sumOfSquares / count - mean * mean
    }
}
```

- [ ] **Step 4: `SegmentProcessor.swift` 구현**

```swift
import CoreGraphics
import Foundation

public enum SegmentProcessor {
    public struct Output: Sendable {
        public var groups: [StoredGroup]
        /// 이미지를 받지 못해 건너뛴 사진 수.
        public var unreadable: Int
    }

    /// 시간 구간 하나를 분석해 묶음을 만든다. 사진이 1장뿐이면 이미지를 읽지 않는다.
    public static func process(_ segment: [PhotoItem],
                               threshold: Float = Tuning.distanceThreshold,
                               loadImage: (String) -> CGImage?) -> Output {
        guard segment.count >= 2 else { return Output(groups: [], unreadable: 0) }

        var analyses: [String: ImageAnalysis] = [:]
        for photo in segment {
            autoreleasepool {
                if let image = loadImage(photo.id), let analysis = try? ImageAnalyzer.analyze(image) {
                    analyses[photo.id] = analysis
                }
            }
        }
        let readable = segment.filter { analyses[$0.id] != nil }

        let grouped = SimilarityGrouper.groups(in: readable, threshold: threshold) { a, b in
            guard let first = analyses[a.id], let second = analyses[b.id] else { return nil }
            return ImageAnalyzer.distance(first.featurePrint, second.featurePrint)
        }
        let groups = grouped.compactMap { members -> StoredGroup? in
            let photos = members.compactMap { item in
                analyses[item.id].map { StoredPhoto(item: item, metrics: $0.metrics) }
            }
            guard let recommended = BestShotPicker.pick(photos) else { return nil }
            return StoredGroup(photos: photos, recommendedID: recommended, isSkipped: false)
        }
        return Output(groups: groups, unreadable: segment.count - readable.count)
    }
}
```

- [ ] **Step 5: 통과 확인(전체 테스트)**

Run: `swift test --package-path PhotoTidyCore`
Expected: `Executed 27 tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add PhotoTidyCore
git commit -m "feat: Vision 이미지 분석과 구간 처리"
```

---

### Task 6: 앱 뼈대와 PhotoLibrary

**Files:**
- Create: `project.yml`, `PhotoTidy/PhotoTidyApp.swift`, `PhotoTidy/PhotoLibrary.swift`

- [ ] **Step 1: `project.yml`**

```yaml
name: PhotoTidy
options:
  bundleIdPrefix: com.heejung
  deploymentTarget:
    iOS: "17.0"
packages:
  PhotoTidyCore:
    path: PhotoTidyCore
targets:
  PhotoTidy:
    type: application
    platform: iOS
    sources:
      - PhotoTidy
    dependencies:
      - package: PhotoTidyCore
    info:
      path: PhotoTidy/Info.plist
      properties:
        CFBundleDisplayName: Photo Tidy
        NSPhotoLibraryUsageDescription: 비슷한 사진을 찾아 묶고, 선택한 사진을 삭제하기 위해 사진첩에 접근합니다.
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.heejung.phototidy
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "1"
        CODE_SIGN_STYLE: Automatic
```

`PhotoTidy/Info.plist`는 XcodeGen이 생성하므로 `.gitignore`에 `PhotoTidy/Info.plist`를 추가한다.

- [ ] **Step 2: `PhotoTidy/PhotoTidyApp.swift` (임시 화면)**

```swift
import SwiftUI

@main
struct PhotoTidyApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Photo Tidy")
        }
    }
}
```

- [ ] **Step 3: `PhotoTidy/PhotoLibrary.swift`**

```swift
import Photos
import PhotoTidyCore
import UIKit

/// 사진첩 읽기·삭제. 상태를 갖지 않는다.
final class PhotoLibrary: Sendable {
    var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// 이미지 타입만, 촬영 시각 오름차순. date가 있으면 그 이후 사진만.
    func fetchPhotos(after date: Date?) -> [PhotoItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        if let date {
            options.predicate = NSPredicate(format: "creationDate > %@", date as NSDate)
        }
        var items: [PhotoItem] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            guard let takenAt = asset.creationDate else { return }
            items.append(PhotoItem(id: asset.localIdentifier, takenAt: takenAt,
                                   isFavorite: asset.isFavorite, isEdited: asset.hasAdjustments,
                                   pixelCount: asset.pixelWidth * asset.pixelHeight))
        }
        return items
    }

    /// ids 중 사진첩에 아직 있는 것.
    func existingIDs(of ids: [String]) -> Set<String> {
        var found: Set<String> = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            found.insert(asset.localIdentifier)
        }
        return found
    }

    /// 분석용 이미지(긴 변 약 512px). 네트워크는 쓰지 않고, 원본이 기기에 없으면 미리보기로 받는다.
    func analysisImage(id: String) -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        return requestImage(asset, mode: .highQualityFormat) ?? requestImage(asset, mode: .fastFormat)
    }

    private func requestImage(_ asset: PHAsset, mode: PHImageRequestOptionsDeliveryMode) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = mode
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        var result: CGImage?
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 512, height: 512),
                                              contentMode: .aspectFit, options: options) { image, _ in
            result = image?.cgImage
        }
        return result
    }

    /// 화면 표시용 이미지. 저화질이 먼저 오고 고화질이 뒤따를 수 있다.
    func displayImages(id: String, targetSize: CGSize) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
                continuation.finish()
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = false
            let requestID = PHImageManager.default().requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
            ) { image, info in
                if let image {
                    continuation.yield(image)
                }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }

    /// iOS 삭제 확인 창을 띄운다. 사용자가 취소하면 false.
    func delete(ids: [String]) async -> Bool {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 4: 프로젝트 생성과 빌드 확인**

Run:
```bash
xcodegen generate
xcodebuild -project PhotoTidy.xcodeproj -scheme PhotoTidy -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build > build.log 2>&1; tail -n 3 build.log
```
Expected: `** BUILD SUCCEEDED **` (`build.log`도 `.gitignore`에 추가)

- [ ] **Step 5: Commit**

```bash
git add .gitignore project.yml PhotoTidy
git commit -m "chore: 앱 타깃과 사진첩 래퍼 추가"
```

---

### Task 7: AppModel

**Files:**
- Create: `PhotoTidy/AppModel.swift`

- [ ] **Step 1: 구현**

```swift
import Foundation
import Observation
import Photos
import PhotoTidyCore

@MainActor
@Observable
final class AppModel {
    enum Access {
        case notDetermined, denied, limited, full
    }

    private(set) var access: Access = .notDetermined
    private(set) var isAnalyzing = false
    private(set) var processed = 0
    private(set) var total = 0
    private(set) var unreadable = 0
    private(set) var state: StoreState

    let library = PhotoLibrary()
    private let store: GroupStore
    private var task: Task<Void, Never>?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = GroupStore(url: directory.appendingPathComponent("groups.json"))
        state = store.load()
        refreshAccess()
    }

    var hasAnalyzed: Bool { state.watermark != nil }

    /// 숨기지 않은 묶음, 최신순.
    var visibleGroups: [StoredGroup] {
        state.groups
            .filter { !$0.isSkipped }
            .sorted { $0.photos[0].item.takenAt > $1.photos[0].item.takenAt }
    }

    /// 추천 한 장씩만 남길 때 지울 수 있는 장수.
    var deletableCount: Int {
        visibleGroups.reduce(0) { $0 + $1.photos.count - 1 }
    }

    /// 추천 한 장씩만 남길 때 확보되는 용량(어림).
    var reclaimableBytes: Int64 {
        let pixels = visibleGroups.reduce(0) { sum, group in
            sum + group.photos.filter { $0.item.id != group.recommendedID }.reduce(0) { $0 + $1.item.pixelCount }
        }
        return Int64(Double(pixels) * Tuning.estimatedBytesPerPixel)
    }

    func refreshAccess() {
        switch library.status {
        case .authorized: access = .full
        case .limited: access = .limited
        case .denied, .restricted: access = .denied
        case .notDetermined: access = .notDetermined
        @unknown default: access = .denied
        }
        if access == .full || access == .limited {
            let ids = state.groups.flatMap { $0.photos.map(\.item.id) }
            state.prune(existing: library.existingIDs(of: ids))
        }
    }

    func requestAccess() async {
        _ = await library.requestAccess()
        refreshAccess()
    }

    func startAnalysis() {
        guard !isAnalyzing, access == .full || access == .limited else { return }
        isAnalyzing = true
        processed = 0
        total = 0
        unreadable = 0
        let library = self.library
        let resumeDate = state.resumeDate

        task = Task {
            let segments = await Task.detached(priority: .userInitiated) {
                SimilarityGrouper.segments(library.fetchPhotos(after: resumeDate))
            }.value
            total = segments.reduce(0) { $0 + $1.count }
            var sinceSave = 0

            for segment in segments {
                if Task.isCancelled { break }
                if segment.count >= 2 {
                    let output = await Task.detached(priority: .userInitiated) {
                        SegmentProcessor.process(segment) { library.analysisImage(id: $0) }
                    }.value
                    state.merge(output.groups)
                    unreadable += output.unreadable
                }
                if let last = segment.last {
                    state.watermark = max(state.watermark ?? .distantPast, last.takenAt)
                }
                processed += segment.count
                sinceSave += segment.count
                if sinceSave >= 200 {
                    try? store.save(state)
                    sinceSave = 0
                }
            }
            try? store.save(state)
            isAnalyzing = false
        }
    }

    func cancelAnalysis() {
        task?.cancel()
    }

    /// keep에 없는 사진을 삭제한다. 사용자가 확인 창에서 취소하면 false.
    func delete(group: StoredGroup, keeping keep: Set<String>) async -> Bool {
        let ids = group.photos.map(\.item.id).filter { !keep.contains($0) }
        guard !keep.isEmpty, !ids.isEmpty else { return false }
        guard await library.delete(ids: ids) else { return false }
        state.resolve(groupID: group.id, deleted: Set(ids))
        try? store.save(state)
        return true
    }

    func skip(_ group: StoredGroup) {
        state.skip(groupID: group.id)
        try? store.save(state)
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodegen generate && xcodebuild -project PhotoTidy.xcodeproj -scheme PhotoTidy -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build > build.log 2>&1; tail -n 3 build.log`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PhotoTidy
git commit -m "feat: 분석 흐름을 조율하는 AppModel"
```

---

### Task 8: 화면

**Files:**
- Create: `PhotoTidy/Views/AssetImage.swift`, `PhotoTidy/Views/HomeView.swift`, `PhotoTidy/Views/GroupListView.swift`, `PhotoTidy/Views/GroupDetailView.swift`
- Modify: `PhotoTidy/PhotoTidyApp.swift` (전체 교체)

- [ ] **Step 1: `AssetImage.swift`**

```swift
import SwiftUI

/// 사진첩 사진 한 장을 불러와 보여 준다.
struct AssetImage: View {
    @Environment(AppModel.self) private var model
    let id: String
    let targetSize: CGSize
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: id) {
            for await loaded in model.library.displayImages(id: id, targetSize: targetSize) {
                image = loaded
            }
        }
    }
}
```

- [ ] **Step 2: `HomeView.swift`**

```swift
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch model.access {
                case .notDetermined:
                    Text("비슷한 사진을 찾으려면 사진첩 접근이 필요해요. 사진은 기기 밖으로 나가지 않습니다.")
                        .multilineTextAlignment(.center)
                    Button("사진 접근 허용") {
                        Task { await model.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                case .denied:
                    Text("사진첩 접근이 꺼져 있어요. 설정에서 허용해 주세요.")
                        .multilineTextAlignment(.center)
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                case .limited, .full:
                    analysis
                }
            }
            .padding()
            .navigationTitle("Photo Tidy")
        }
    }

    @ViewBuilder
    private var analysis: some View {
        if model.access == .limited {
            Text("선택한 일부 사진만 분석합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if model.isAnalyzing {
            ProgressView(value: Double(model.processed), total: Double(max(model.total, 1)))
            Text("\(model.processed) / \(model.total)장 분석 중")
                .monospacedDigit()
            Button("취소") {
                model.cancelAnalysis()
            }
        } else {
            if model.hasAnalyzed {
                summary
            }
            Button(model.hasAnalyzed ? "새 사진 분석" : "분석 시작") {
                model.startAnalysis()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var summary: some View {
        let groups = model.visibleGroups
        if groups.isEmpty {
            Text("정리할 묶음이 없어요.")
        } else {
            let size = ByteCountFormatter.string(fromByteCount: model.reclaimableBytes, countStyle: .file)
            Text("비슷한 사진 묶음 \(groups.count)개")
                .font(.title2.bold())
            Text("정리하면 \(model.deletableCount)장 · 약 \(size) 확보")
                .foregroundStyle(.secondary)
            NavigationLink("묶음 보기") {
                GroupListView()
            }
            .buttonStyle(.bordered)
        }
        if model.unreadable > 0 {
            Text("이미지를 불러오지 못해 건너뛴 사진 \(model.unreadable)장")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: `GroupListView.swift`**

```swift
import PhotoTidyCore
import SwiftUI

struct GroupListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = model.visibleGroups
        Group {
            if groups.isEmpty {
                ContentUnavailableView("정리할 묶음이 없어요", systemImage: "checkmark.circle")
            } else {
                List(groups) { group in
                    NavigationLink(value: group) {
                        HStack(spacing: 12) {
                            AssetImage(id: group.recommendedID, targetSize: CGSize(width: 200, height: 200))
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(group.photos.count)장")
                                    .font(.headline)
                                Text(group.photos[0].item.takenAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("비슷한 사진 묶음")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: StoredGroup.self) { group in
            GroupDetailView(group: group)
        }
    }
}
```

- [ ] **Step 4: `GroupDetailView.swift`**

```swift
import PhotoTidyCore
import SwiftUI

struct GroupDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let group: StoredGroup
    @State private var keep: Set<String>
    @State private var current: String
    @State private var isDeleting = false

    init(group: StoredGroup) {
        self.group = group
        _keep = State(initialValue: [group.recommendedID])
        _current = State(initialValue: group.recommendedID)
    }

    private var deleteCount: Int { group.photos.count - keep.count }

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $current) {
                ForEach(group.photos, id: \.item.id) { photo in
                    AssetImage(id: photo.item.id, targetSize: CGSize(width: 1200, height: 1200), contentMode: .fit)
                        .tag(photo.item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Button {
                if keep.contains(current) {
                    keep.remove(current)
                } else {
                    keep.insert(current)
                }
            } label: {
                Label(keep.contains(current) ? "남기는 사진" : "이 사진 남기기",
                      systemImage: keep.contains(current) ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.bordered)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.photos, id: \.item.id) { photo in
                        thumbnail(photo.item.id)
                    }
                }
                .padding(.horizontal)
            }

            Button("나머지 \(deleteCount)장 삭제", role: .destructive) {
                isDeleting = true
                Task {
                    let deleted = await model.delete(group: group, keeping: keep)
                    isDeleting = false
                    if deleted {
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(keep.isEmpty || deleteCount == 0 || isDeleting)

            Button("이 묶음 건너뛰기") {
                model.skip(group)
                dismiss()
            }
            .padding(.bottom)
        }
        .navigationTitle("\(group.photos.count)장 중 \(keep.count)장 남김")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func thumbnail(_ id: String) -> some View {
        Button {
            current = id
        } label: {
            AssetImage(id: id, targetSize: CGSize(width: 200, height: 200))
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if keep.contains(id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, .green)
                            .padding(3)
                    }
                }
                .overlay(alignment: .bottom) {
                    if id == group.recommendedID {
                        Text("추천")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .background(.yellow, in: Capsule())
                            .foregroundStyle(.black)
                            .padding(3)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(id == current ? Color.accentColor : .clear, lineWidth: 3)
                }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 5: `PhotoTidyApp.swift` 전체 교체**

```swift
import SwiftUI

@main
struct PhotoTidyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshAccess()
            }
        }
    }
}
```

- [ ] **Step 6: 빌드 확인**

Run: `xcodegen generate && xcodebuild -project PhotoTidy.xcodeproj -scheme PhotoTidy -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build > build.log 2>&1; tail -n 3 build.log`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add PhotoTidy
git commit -m "feat: 홈·묶음 목록·묶음 상세 화면"
```

---

### Task 9: 시뮬레이터 확인과 README

**Files:**
- Create: `README.md`

- [ ] **Step 1: 시뮬레이터에 테스트 사진 넣고 실행**

같은 사진 2장과 다른 사진 1장을 시뮬레이터 사진첩에 넣는다(연달아 추가되므로 같은 시간 구간에 들어간다).

```bash
xcrun simctl boot "iPhone 15 Pro" 2>/dev/null; xcrun simctl bootstatus "iPhone 15 Pro" -b
mkdir -p build/samples
cp /System/Library/Desktop\ Pictures/*.heic build/samples/ 2>/dev/null
ls build/samples | head
# 목록에서 두 파일을 골라 A, B로 쓴다. A를 두 번, B를 한 번 추가한다.
xcrun simctl addmedia "iPhone 15 Pro" build/samples/<A> build/samples/<A> build/samples/<B>
xcodebuild -project PhotoTidy.xcodeproj -scheme PhotoTidy -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -derivedDataPath build build > build.log 2>&1; tail -n 3 build.log
xcrun simctl install "iPhone 15 Pro" build/Build/Products/Debug-iphonesimulator/PhotoTidy.app
xcrun simctl privacy "iPhone 15 Pro" grant photos com.heejung.phototidy
xcrun simctl launch "iPhone 15 Pro" com.heejung.phototidy
```

`/System/Library/Desktop Pictures`에 heic가 없으면 아무 JPEG/PNG 두 장으로 대체한다.

- [ ] **Step 2: 화면 확인(스크린샷)**

`xcrun simctl io "iPhone 15 Pro" screenshot build/home.png`로 찍어 확인한다.

확인할 것:
1. 홈에 "분석 시작"이 보인다.
2. 분석 후 "비슷한 사진 묶음 1개 · 정리하면 1장"이 보인다(같은 사진 2장이 한 묶음, 다른 사진은 제외).
3. 묶음 상세에서 추천 표시와 체크, "나머지 1장 삭제"가 보인다.
4. 삭제하면 iOS 확인 창이 뜨고, 허용 후 묶음이 목록에서 사라진다.

버튼 조작은 시뮬레이터 창에서 손으로 한다. 자동으로 확인할 수 없는 항목은 README의 확인 목록에 남긴다.

- [ ] **Step 3: `README.md`**

```markdown
# Photo Tidy

아이폰 사진첩에서 연달아 찍은 비슷한 사진을 묶고, 잘 나온 한 장을 추천해 나머지를 지우는 개인용 앱.

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
   `xcodegen generate`를 다시 돌리면 이 선택이 지워지므로, `project.yml`의 `settings.base`에 `DEVELOPMENT_TEAM: <팀 ID>`를 적어 두면 편하다.
3. 아이폰을 연결하고 실행한다. 처음에는 아이폰 설정 > 일반 > VPN 및 기기 관리에서 개발자를 신뢰해야 한다.

무료 계정은 7일마다 다시 설치해야 한다.

## 테스트

```bash
swift test --package-path PhotoTidyCore
```

## 조정할 수 있는 값

`PhotoTidyCore/Sources/PhotoTidyCore/Tuning.swift`

- `maxGap`: 연달아 찍은 사진으로 보는 시간 간격(초)
- `distanceThreshold`: 비슷하다고 보는 정도. 다른 사진이 같이 묶이면 낮추고, 비슷한 사진이 안 묶이면 높인다.

## 구조

- `PhotoTidyCore/`: 묶기·추천·저장 로직(화면과 사진첩에 의존하지 않음)
- `PhotoTidy/`: 사진첩 접근, 화면
- 설계: `docs/superpowers/specs/2026-11-16-photo-tidy-design.md`
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: README 추가"
```
