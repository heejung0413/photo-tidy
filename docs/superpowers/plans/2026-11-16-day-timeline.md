# 하루 타임라인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 하루치 사진을 위치·시간으로 "머문 곳"으로 묶어 지도와 목록으로 보여 주는 타임라인 탭을 추가한다.

**Architecture:** 머문 곳을 나누는 순수 로직 `TimelineBuilder`를 `PhotoTidyCore`에 추가하고 맥에서 테스트한다. 앱에는 사진첩 조회 확장, 장소 이름 변환(`PlaceNamer`), 상태(`TimelineModel`), 화면(`TimelineView`)을 추가하고 루트를 탭 구조로 바꾼다. 기존 정리 기능 코드는 건드리지 않는다.

**Tech Stack:** Swift, SwiftUI, MapKit, CoreLocation(CLGeocoder), Photos, XCTest/XCUITest.

**설계 문서:** `docs/superpowers/specs/2026-11-16-day-timeline-design.md`

모든 명령은 저장소 루트 기준. 각 코드 블록 위의 `<!-- file: 경로 -->`가 그 블록이 들어갈 파일(전체 내용)이다.

---

### Task 1: TimelineBuilder (Core)

**Files:**
- Modify: `PhotoTidyCore/Sources/PhotoTidyCore/Tuning.swift` (전체 교체)
- Create: `PhotoTidyCore/Sources/PhotoTidyCore/TimelineBuilder.swift`
- Test: `PhotoTidyCore/Tests/PhotoTidyCoreTests/TimelineBuilderTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

위도 0.001도는 약 111m다.

<!-- file: PhotoTidyCore/Tests/PhotoTidyCoreTests/TimelineBuilderTests.swift -->
```swift
import XCTest
@testable import PhotoTidyCore

final class TimelineBuilderTests: XCTestCase {
    private func tp(_ id: String, at t: TimeInterval, _ latitude: Double? = nil) -> TimelinePhoto {
        TimelinePhoto(id: id, takenAt: Date(timeIntervalSinceReferenceDate: t),
                      coordinate: latitude.map { Coordinate(latitude: $0, longitude: 127.0) })
    }

    private func ids(_ stops: [TimelineStop]) -> [[String]] {
        stops.map { $0.photos.map(\.id) }
    }

    func testDistanceIsAbout111MetersPerThousandthDegreeOfLatitude() {
        let meters = TimelineBuilder.distance(Coordinate(latitude: 37.0, longitude: 127.0),
                                              Coordinate(latitude: 37.001, longitude: 127.0))
        XCTAssertEqual(meters, 111.2, accuracy: 0.5)
    }

    func testEmptyInputGivesNoStops() {
        XCTAssertTrue(TimelineBuilder.stops([]).isEmpty)
    }

    func testPhotosWithinRadiusBecomeOneStop() {
        let stops = TimelineBuilder.stops([tp("a", at: 0, 37.0), tp("b", at: 60, 37.001)], radius: 200)
        XCTAssertEqual(ids(stops), [["a", "b"]])
        XCTAssertEqual(stops[0].center?.latitude ?? 0, 37.0005, accuracy: 0.00001)
        XCTAssertEqual(stops[0].start, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(stops[0].end, Date(timeIntervalSinceReferenceDate: 60))
    }

    func testPhotoOutsideRadiusStartsNewStop() {
        let stops = TimelineBuilder.stops([tp("a", at: 0, 37.0), tp("b", at: 60, 37.01)], radius: 200)
        XCTAssertEqual(ids(stops), [["a"], ["b"]])
    }

    func testReturningToSamePlaceIsSeparateStop() {
        let stops = TimelineBuilder.stops([tp("a", at: 0, 37.0), tp("b", at: 60, 37.01), tp("c", at: 120, 37.0)],
                                          radius: 200)
        XCTAssertEqual(ids(stops), [["a"], ["b"], ["c"]])
    }

    func testPhotoWithoutLocationJoinsCurrentStop() {
        let stops = TimelineBuilder.stops([tp("a", at: 0, 37.0), tp("b", at: 60), tp("c", at: 120, 37.01)],
                                          radius: 200)
        XCTAssertEqual(ids(stops), [["a", "b"], ["c"]])
    }

    func testLeadingPhotosWithoutLocationJoinFirstLocatedStop() {
        let stops = TimelineBuilder.stops([tp("a", at: 0), tp("b", at: 60, 37.0)], radius: 200)
        XCTAssertEqual(ids(stops), [["a", "b"]])
        XCTAssertEqual(stops[0].center?.latitude, 37.0)
    }

    func testAllPhotosWithoutLocationBecomeOneStopWithoutCenter() {
        let stops = TimelineBuilder.stops([tp("a", at: 0), tp("b", at: 60)], radius: 200)
        XCTAssertEqual(ids(stops), [["a", "b"]])
        XCTAssertNil(stops[0].center)
    }

    func testInputIsSortedByTime() {
        let stops = TimelineBuilder.stops([tp("b", at: 60, 37.0), tp("a", at: 0, 37.0)], radius: 200)
        XCTAssertEqual(ids(stops), [["a", "b"]])
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path PhotoTidyCore --filter TimelineBuilderTests`
Expected: 컴파일 오류 `cannot find 'TimelinePhoto' in scope`

- [ ] **Step 3: `Tuning.swift`에 반경 추가(전체 교체)**

<!-- file: PhotoTidyCore/Sources/PhotoTidyCore/Tuning.swift -->
```swift
import Foundation

public enum Tuning {
    /// 앞 사진과 이 시간(초) 이내면 같은 구간으로 본다.
    public static let maxGap: TimeInterval = 60
    /// 지문 거리가 이 값 이하면 비슷한 사진으로 본다.
    public static let distanceThreshold: Float = 0.5
    /// 확보 용량 어림용: 픽셀당 바이트.
    public static let estimatedBytesPerPixel: Double = 0.2
    /// 타임라인: 머문 곳 중심에서 이 거리(미터) 이내면 같은 곳으로 본다.
    public static let stopRadius: Double = 200
}
```

- [ ] **Step 4: 구현**

<!-- file: PhotoTidyCore/Sources/PhotoTidyCore/TimelineBuilder.swift -->
```swift
import Foundation

public struct Coordinate: Hashable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct TimelinePhoto: Identifiable, Hashable, Sendable {
    public let id: String
    public let takenAt: Date
    public let coordinate: Coordinate?

    public init(id: String, takenAt: Date, coordinate: Coordinate?) {
        self.id = id
        self.takenAt = takenAt
        self.coordinate = coordinate
    }
}

/// 한곳에 머물며 찍은 사진들. 사진은 1장 이상이고 촬영 시각순이다.
public struct TimelineStop: Identifiable, Hashable, Sendable {
    public let photos: [TimelinePhoto]
    /// 위치가 있는 사진 좌표의 평균. 위치 있는 사진이 없으면 nil.
    public let center: Coordinate?

    public var id: String { photos[0].id }
    public var start: Date { photos[0].takenAt }
    public var end: Date { photos[photos.count - 1].takenAt }
}

public enum TimelineBuilder {
    /// 두 좌표 사이 거리(미터, 하버사인 공식).
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// 사진을 시각순으로 보며, 현재 머문 곳 중심에서 radius를 벗어나면 새 머문 곳을 시작한다.
    public static func stops(_ photos: [TimelinePhoto], radius: Double = Tuning.stopRadius) -> [TimelineStop] {
        var result: [TimelineStop] = []
        var current: [TimelinePhoto] = []
        var located: [Coordinate] = []

        func center() -> Coordinate? {
            guard !located.isEmpty else { return nil }
            let count = Double(located.count)
            return Coordinate(latitude: located.reduce(0) { $0 + $1.latitude } / count,
                              longitude: located.reduce(0) { $0 + $1.longitude } / count)
        }
        func flush() {
            guard !current.isEmpty else { return }
            result.append(TimelineStop(photos: current, center: center()))
            current = []
            located = []
        }

        for photo in photos.sorted(by: { $0.takenAt < $1.takenAt }) {
            if let coordinate = photo.coordinate {
                if let center = center(), distance(center, coordinate) > radius {
                    flush()
                }
                located.append(coordinate)
            }
            current.append(photo)
        }
        flush()
        return result
    }
}
```

- [ ] **Step 5: 통과 확인(전체)**

Run: `swift test --package-path PhotoTidyCore`
Expected: `Executed 36 tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add PhotoTidyCore
git commit -m "feat: 위치와 시간으로 머문 곳 나누기"
```

---

### Task 2: 사진첩 조회 확장과 PlaceNamer

**Files:**
- Create: `PhotoTidy/PhotoLibrary+Timeline.swift`, `PhotoTidy/PlaceNamer.swift`

- [ ] **Step 1: 사진첩 조회 확장**

<!-- file: PhotoTidy/PhotoLibrary+Timeline.swift -->
```swift
import Photos
import PhotoTidyCore

extension PhotoLibrary {
    /// day가 속한 날(기기 시간대 0시~24시 전)의 사진. 촬영 시각 오름차순.
    func timelinePhotos(on day: Date, calendar: Calendar = .current) -> [TimelinePhoto] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                        start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var photos: [TimelinePhoto] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            guard let takenAt = asset.creationDate else { return }
            let coordinate = asset.location.map {
                Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            }
            photos.append(TimelinePhoto(id: asset.localIdentifier, takenAt: takenAt, coordinate: coordinate))
        }
        return photos
    }

    /// 사진이 있는 날짜(각 날의 0시) 목록, 오름차순.
    func photoDays(calendar: Calendar = .current) -> [Date] {
        var days: Set<Date> = []
        PHAsset.fetchAssets(with: .image, options: nil).enumerateObjects { asset, _, _ in
            if let date = asset.creationDate {
                days.insert(calendar.startOfDay(for: date))
            }
        }
        return days.sorted()
    }
}
```

- [ ] **Step 2: PlaceNamer**

<!-- file: PhotoTidy/PlaceNamer.swift -->
```swift
import CoreLocation
import Foundation
import PhotoTidyCore

/// 좌표를 장소 이름으로 바꾼다(애플 서버에 좌표만 전송). 받은 이름은 기기에 저장한다.
@MainActor
final class PlaceNamer {
    private var cache: [String: String]
    private let url: URL
    private let geocoder = CLGeocoder()

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("place-names.json")
        cache = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) ?? [:]
    }

    /// 실패하면 nil.
    func name(for coordinate: Coordinate) async -> String? {
        let key = String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
        if let cached = cache[key] {
            return cached
        }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first,
              let name = placemark.areasOfInterest?.first ?? placemark.subLocality
                  ?? placemark.locality ?? placemark.name else {
            return nil
        }
        cache[key] = name
        try? JSONEncoder().encode(cache).write(to: url, options: .atomic)
        return name
    }
}
```

- [ ] **Step 3: Commit** (빌드 확인은 Task 3 끝에서 한다)

```bash
git add PhotoTidy
git commit -m "feat: 날짜별 사진 조회와 장소 이름 변환"
```

---

### Task 3: TimelineModel, TimelineView, 탭 구조

**Files:**
- Create: `PhotoTidy/TimelineModel.swift`, `PhotoTidy/Views/TimelineView.swift`
- Modify: `PhotoTidy/PhotoTidyApp.swift` (전체 교체)

- [ ] **Step 1: TimelineModel**

<!-- file: PhotoTidy/TimelineModel.swift -->
```swift
import Foundation
import Observation
import PhotoTidyCore

@MainActor
@Observable
final class TimelineModel {
    /// 사진이 있는 날짜(각 날의 0시), 오름차순.
    private(set) var days: [Date] = []
    private(set) var day: Date?
    private(set) var stops: [TimelineStop] = []
    /// 머문 곳 id → 장소 이름.
    private(set) var names: [String: String] = [:]
    private(set) var isLoading = false

    private let library: PhotoLibrary
    private let namer = PlaceNamer()
    private var loadTask: Task<Void, Never>?

    init(library: PhotoLibrary) {
        self.library = library
    }

    var previousDay: Date? {
        guard let day else { return nil }
        return days.last { $0 < day }
    }

    var nextDay: Date? {
        guard let day else { return nil }
        return days.first { $0 > day }
    }

    /// 날짜 목록을 읽고, 보고 있던 날이 없으면 가장 최근 날을 연다.
    func loadDays() async {
        let library = self.library
        days = await Task.detached(priority: .userInitiated) { library.photoDays() }.value
        if let day, days.contains(day) {
            show(day)
        } else if let last = days.last {
            show(last)
        } else {
            day = nil
            stops = []
        }
    }

    /// date와 가장 가까운, 사진이 있는 날을 연다.
    func showNearest(to date: Date) {
        let target = Calendar.current.startOfDay(for: date)
        let nearest = days.min { abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target)) }
        if let nearest {
            show(nearest)
        }
    }

    func show(_ newDay: Date) {
        day = newDay
        loadTask?.cancel()
        isLoading = true
        let library = self.library
        loadTask = Task {
            let photos = await Task.detached(priority: .userInitiated) {
                library.timelinePhotos(on: newDay)
            }.value
            if Task.isCancelled { return }
            stops = TimelineBuilder.stops(photos)
            names = [:]
            isLoading = false
            for stop in stops {
                guard let center = stop.center else { continue }
                let name = await namer.name(for: center)
                if Task.isCancelled { return }
                if let name {
                    names[stop.id] = name
                }
            }
        }
    }

    func title(for stop: TimelineStop) -> String {
        if let name = names[stop.id] {
            return name
        }
        guard stop.center != nil, let index = stops.firstIndex(of: stop) else {
            return "위치 정보 없음"
        }
        return "장소 \(index + 1)"
    }
}
```

- [ ] **Step 2: TimelineView**

<!-- file: PhotoTidy/Views/TimelineView.swift -->
```swift
import MapKit
import PhotoTidyCore
import SwiftUI

struct TimelineView: View {
    @Environment(AppModel.self) private var app
    @Environment(TimelineModel.self) private var model

    @State private var camera: MapCameraPosition = .automatic
    @State private var isPickingDate = false
    @State private var pickedDate = Date()
    @State private var viewing: TimelinePhoto?

    private struct Pin: Identifiable {
        let id: String
        let number: Int
        let title: String
        let coordinate: CLLocationCoordinate2D
    }

    private var hasAccess: Bool {
        app.access == .full || app.access == .limited
    }

    private var pins: [Pin] {
        model.stops.enumerated().compactMap { index, stop in
            guard let center = stop.center else { return nil }
            return Pin(id: stop.id, number: index + 1, title: model.title(for: stop),
                       coordinate: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasAccess {
                    ContentUnavailableView("사진 접근이 필요해요", systemImage: "photo.on.rectangle",
                                           description: Text("정리 탭에서 사진 접근을 허용해 주세요."))
                } else if let day = model.day {
                    dayContent(day)
                } else {
                    ContentUnavailableView("사진이 없어요", systemImage: "photo")
                }
            }
            .navigationTitle("타임라인")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: hasAccess) {
            if hasAccess {
                await model.loadDays()
            }
        }
        .onChange(of: model.day) {
            camera = .automatic
        }
        .sheet(isPresented: $isPickingDate) {
            datePicker
        }
        .sheet(item: $viewing) { photo in
            AssetImage(id: photo.id, targetSize: CGSize(width: 1600, height: 1600), contentMode: .fit)
                .ignoresSafeArea()
        }
    }

    private func dayContent(_ day: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(day)
                if !pins.isEmpty {
                    map
                }
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(model.stops.enumerated()), id: \.element.id) { index, stop in
                    stopRow(stop, number: index + 1)
                }
            }
            .padding()
        }
    }

    private func header(_ day: Date) -> some View {
        HStack {
            Button {
                if let previous = model.previousDay {
                    model.show(previous)
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(model.previousDay == nil)
            .accessibilityLabel("이전 날")

            Spacer()
            Button(day.formatted(.dateTime.year().month().day().weekday())) {
                pickedDate = day
                isPickingDate = true
            }
            .font(.headline)
            Spacer()

            Button {
                if let next = model.nextDay {
                    model.show(next)
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(model.nextDay == nil)
            .accessibilityLabel("다음 날")
        }
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(pins) { pin in
                Marker(pin.title, monogram: Text("\(pin.number)"), coordinate: pin.coordinate)
            }
            MapPolyline(coordinates: pins.map(\.coordinate))
                .stroke(.blue, lineWidth: 3)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func stopRow(_ stop: TimelineStop, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                focus(stop)
            } label: {
                HStack(spacing: 10) {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.blue, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.title(for: stop))
                            .font(.headline)
                        Text("\(timeRange(stop)) · \(stop.photos.count)장")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(stop.photos) { photo in
                        Button {
                            viewing = photo
                        } label: {
                            AssetImage(id: photo.id, targetSize: CGSize(width: 200, height: 200))
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 72)
        }
    }

    private var datePicker: some View {
        NavigationStack {
            DatePicker("날짜", selection: $pickedDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("날짜 선택")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("보기") {
                            model.showNearest(to: pickedDate)
                            isPickingDate = false
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    private func timeRange(_ stop: TimelineStop) -> String {
        let start = stop.start.formatted(date: .omitted, time: .shortened)
        let end = stop.end.formatted(date: .omitted, time: .shortened)
        return start == end ? start : "\(start)–\(end)"
    }

    private func focus(_ stop: TimelineStop) {
        guard let center = stop.center else { return }
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                latitudinalMeters: 600, longitudinalMeters: 600))
        }
    }
}
```

- [ ] **Step 3: 루트를 탭 구조로(전체 교체)**

<!-- file: PhotoTidy/PhotoTidyApp.swift -->
```swift
import SwiftUI

@main
struct PhotoTidyApp: App {
    @State private var model: AppModel
    @State private var timeline: TimelineModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        _timeline = State(initialValue: TimelineModel(library: model.library))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .tabItem { Label("정리", systemImage: "square.stack") }
                TimelineView()
                    .tabItem { Label("타임라인", systemImage: "map") }
            }
            .environment(model)
            .environment(timeline)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshAccess()
            }
        }
    }
}
```

- [ ] **Step 4: 빌드 확인**

Run: `xcodegen generate && xcodebuild build-for-testing -project PhotoTidy.xcodeproj -scheme PhotoTidy -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO > build.log 2>&1; grep -E "error:|SUCCEEDED|FAILED" build.log | tail -3`
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add PhotoTidy
git commit -m "feat: 타임라인 탭(날짜 선택, 지도, 머문 곳 목록)"
```

---

### Task 4: 샘플 사진 스크립트와 스모크 테스트

**Files:**
- Create: `scripts/make-timeline-samples.swift`
- Modify: `PhotoTidyUITests/SmokeTests.swift` (권한 처리를 함수로 빼고 테스트 하나 추가)

- [ ] **Step 1: 위치·시각이 든 샘플 사진 생성 스크립트**

2026-11-14 하루에 세 곳(성수동 1장, 서울숲 2장, 남산 1장)을 다닌 사진 4장을 만든다.

<!-- file: scripts/make-timeline-samples.swift -->
```swift
// 사용법: swift scripts/make-timeline-samples.swift <출력 폴더>
// 위치(GPS)와 촬영 시각이 든 단색 JPEG 4장을 만든다. 타임라인 확인용.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Sample {
    let name: String
    let date: String
    let latitude: Double
    let longitude: Double
    let color: (CGFloat, CGFloat, CGFloat)
}

let samples = [
    Sample(name: "t1-seongsu", date: "2026:11:14 09:10:00", latitude: 37.5446, longitude: 127.0559, color: (0.95, 0.55, 0.2)),
    Sample(name: "t2-forest", date: "2026:11:14 11:05:00", latitude: 37.5443, longitude: 127.0374, color: (0.2, 0.7, 0.3)),
    Sample(name: "t3-forest", date: "2026:11:14 11:20:00", latitude: 37.5446, longitude: 127.0378, color: (0.1, 0.55, 0.25)),
    Sample(name: "t4-namsan", date: "2026:11:14 15:20:00", latitude: 37.5512, longitude: 126.9882, color: (0.3, 0.45, 0.9)),
]

guard CommandLine.arguments.count == 2 else {
    print("사용법: swift scripts/make-timeline-samples.swift <출력 폴더>")
    exit(1)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for sample in samples {
    let context = CGContext(data: nil, width: 1200, height: 900, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(red: sample.color.0, green: sample.color.1, blue: sample.color.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
    let image = context.makeImage()!

    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: sample.date],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: sample.date],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: sample.latitude,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: sample.longitude,
            kCGImagePropertyGPSLongitudeRef: "E",
        ],
    ]
    let url = directory.appendingPathComponent("\(sample.name).jpg")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        print("실패: \(url.path)")
        exit(1)
    }
    print(url.path)
}
```

- [ ] **Step 2: 스모크 테스트에 추가**

`SmokeTests.swift`에서 `testAnalyzeAndDeleteDuplicates` 안의 권한 처리 블록(`let allow = ...`부터 그 `if` 끝까지)을 아래 함수 호출 `grantAccessIfNeeded()`로 바꾸고, 클래스에 함수와 테스트를 추가한다.

```swift
    private func grantAccessIfNeeded() {
        let allow = app.buttons["사진 접근 허용"]
        guard allow.waitForExistence(timeout: 3) else { return }
        allow.tap()
        let full = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["전체 접근 허용", "Allow Full Access"])).firstMatch
        XCTAssertTrue(full.waitForExistence(timeout: 10))
        full.tap()
    }

    /// 샘플 사진(scripts/make-timeline-samples.swift, 2026-11-14)이 사진첩에 있어야 한다.
    func testTimelineShowsStopsForSampleDay() {
        app.launch()
        grantAccessIfNeeded()
        app.tabBars.buttons["타임라인"].tap()

        let previous = app.buttons["이전 날"]
        XCTAssertTrue(previous.waitForExistence(timeout: 20))
        let sampleStop = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "9:10")).firstMatch
        for _ in 0..<10 where !sampleStop.exists {
            if previous.isEnabled {
                previous.tap()
            }
            sleep(1)
        }
        XCTAssertTrue(sampleStop.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2장")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3:20")).firstMatch.exists)
        sleep(5) // 장소 이름과 지도 불러오기
        shot("7-timeline")
    }
```

- [ ] **Step 3: 샘플을 넣고 타임라인 테스트만 실행**

```bash
swift scripts/make-timeline-samples.swift build/timeline-samples
xcrun simctl addmedia <기기 ID> build/timeline-samples/*.jpg
xcodegen generate
xcodebuild test -project PhotoTidy.xcodeproj -scheme PhotoTidy \
  -destination "platform=iOS Simulator,id=<기기 ID>" -derivedDataPath build \
  -only-testing:PhotoTidyUITests/SmokeTests/testTimelineShowsStopsForSampleDay > build.log 2>&1
grep -E "error:|SHOT:|Executed|TEST (SUCCEEDED|FAILED)" build.log | sort -u
```
Expected: `** TEST SUCCEEDED **`, `SHOT: .../7-timeline.png`. 스크린샷에서 지도 핀 3개와 머문 곳 3개(1장, 2장, 1장)를 눈으로 확인한다.

- [ ] **Step 4: README 갱신**

- 첫 문단의 "사진은 기기 밖으로 나가지 않는다(서버 없음)."를 "사진은 기기 밖으로 나가지 않는다. 타임라인의 장소 이름을 받을 때만 머문 곳의 좌표가 애플 지도 서버로 전송된다."로 바꾼다.
- 첫 문단에 타임라인 기능 한 줄을 추가한다.
- "화면" 표에 `docs/screenshots/7-timeline.png`를 추가한다.
- "테스트"의 스모크 테스트 설명에 샘플 생성 명령(`swift scripts/make-timeline-samples.swift build/timeline-samples` 후 `addmedia`)을 추가한다.
- "조정할 수 있는 값"에 `stopRadius`를 추가한다.

- [ ] **Step 5: Commit**

```bash
git add -A .
git commit -m "test: 타임라인 스모크 테스트와 샘플 생성 스크립트, README 갱신"
```
