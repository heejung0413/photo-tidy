import Foundation
import Observation
import PhotoTidyCore

@MainActor
@Observable
final class TimelineModel {
    enum Source: Hashable {
        /// 사진첩 전체를 하루씩.
        case daily
        /// 앨범 하나를 통째로.
        case album(PhotoAlbum)
    }

    private(set) var source: Source = .daily
    private(set) var albums: [PhotoAlbum] = []
    /// 앨범을 볼 때의 날짜별 머문 곳. 하루씩 볼 때는 비어 있다.
    private(set) var sections: [TimelineDay] = []
    /// 사진이 있는 날짜(각 날의 0시), 오름차순.
    private(set) var days: [Date] = []
    private(set) var day: Date?
    /// 화면에 보이는 머문 곳 전체(앨범이면 모든 날을 이어 붙인 것). 번호는 이 순서를 따른다.
    private(set) var stops: [TimelineStop] = []
    /// 머문 곳 id → 장소 이름.
    private(set) var names: [String: String] = [:]
    private(set) var isLoading = false
    /// 직접 붙인 장소 이름.
    private(set) var customNames = CustomPlaceNames()

    private let library: PhotoLibrary
    private let namer = PlaceNamer()
    private var loadTask: Task<Void, Never>?

    private let customNamesStore: PlaceNameStore

    init(library: PhotoLibrary) {
        self.library = library
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        customNamesStore = PlaceNameStore(url: directory.appendingPathComponent("custom-place-names.json"))
        customNames = customNamesStore.load()
    }

    func customName(for stop: TimelineStop) -> String? {
        customNames.name(for: stop)
    }

    /// 장소 이름을 직접 정한다. 빈 글자면 직접 붙인 이름을 지우고 자동 이름으로 돌아간다.
    func rename(_ stop: TimelineStop, to text: String) {
        customNames.rename(stop, to: text)
        try? customNamesStore.save(customNames)
    }

    /// 지금 화면과 무관하게 알 수 있는 이름(직접 붙인 이름, 또는 이미 받아 둔 자동 이름). 없으면 nil.
    func knownName(for stop: TimelineStop) -> String? {
        customName(for: stop) ?? stop.center.flatMap { namer.cachedName(for: $0) }
    }

    /// 화면에 보이는 머문 곳을 날짜별로. 하루 보기는 그날 하나.
    var displayDays: [TimelineDay] {
        if !sections.isEmpty {
            return sections
        }
        guard let first = stops.first else { return [] }
        return [TimelineDay(day: day ?? first.start, stops: stops)]
    }

    var previousDay: Date? {
        guard let day else { return nil }
        return DayNavigator.previous(before: day, in: days)
    }

    var nextDay: Date? {
        guard let day else { return nil }
        return DayNavigator.next(after: day, in: days)
    }

    /// 날짜·앨범 목록을 읽고, 보고 있던 날이 없으면 가장 최근 날을 연다.
    func loadDays() async {
        let library = self.library
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampleAlbum") {
            await library.makeSampleAlbumIfNeeded()
        }
        #endif
        (days, albums) = await Task.detached(priority: .userInitiated) {
            (library.photoDays(), library.albums())
        }.value
        if case .album = source { return }
        showDaily()
    }

    /// 하루씩 보기로 돌아간다.
    func showDaily() {
        if let day, days.contains(day) {
            show(day)
        } else if let last = days.last {
            show(last)
        } else {
            loadTask?.cancel()
            source = .daily
            day = nil
            stops = []
            sections = []
            isLoading = false
        }
    }

    /// 앨범의 사진 전체를 날짜별로 이어 붙여 연다.
    func showAlbum(_ album: PhotoAlbum) {
        if source != .album(album) {
            stops = []
            sections = []
        }
        source = .album(album)
        let library = self.library
        load(byDay: true) { library.timelinePhotos(inAlbum: album.id) }
    }

    /// date와 가장 가까운, 사진이 있는 날을 연다.
    func showNearest(to date: Date) {
        if let nearest = DayNavigator.nearest(to: date, in: days) {
            show(nearest)
        }
    }

    func show(_ newDay: Date) {
        if source != .daily {
            stops = []
        }
        source = .daily
        day = newDay
        let library = self.library
        load(byDay: false) { library.timelinePhotos(on: newDay) }
    }

    private func load(byDay: Bool, _ fetch: @escaping @Sendable () -> [TimelinePhoto]) {
        loadTask?.cancel()
        isLoading = true
        loadTask = Task {
            let photos = await Task.detached(priority: .userInitiated, operation: fetch).value
            if Task.isCancelled { return }
            if byDay {
                sections = TimelineBuilder.days(photos)
                stops = sections.flatMap(\.stops)
            } else {
                sections = []
                stops = TimelineBuilder.stops(photos)
            }
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
        if let custom = customName(for: stop) {
            return custom
        }
        if let name = names[stop.id] {
            return name
        }
        guard stop.center != nil, let index = stops.firstIndex(of: stop) else {
            return "위치 정보 없음"
        }
        return "장소 \(index + 1)"
    }
}
