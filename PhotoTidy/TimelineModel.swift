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
    private(set) var stops: [TimelineStop] = [] {
        didSet {
            order = Dictionary(stops.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
    /// 머문 곳 id → 화면에서의 순서(0부터). 줄마다 목록을 처음부터 찾지 않기 위해 둔다.
    private var order: [String: Int] = [:]
    /// 머문 곳 id → 장소 이름.
    private(set) var names: [String: String] = [:]
    private(set) var isLoading = false
    /// 직접 붙인 장소 이름.
    private(set) var customNames = CustomPlaceNames()

    private let library: PhotoLibrary
    private let namer = PlaceNamer()
    private var loadTask: Task<Void, Never>?
    private var watcher: LibraryChangeWatcher?
    private var refreshTask: Task<Void, Never>?

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

    /// 보고 있는 앨범의 id. 하루씩 볼 때는 nil.
    var albumID: String? {
        if case .album(let album) = source {
            return album.id
        }
        return nil
    }

    /// 날짜·앨범 목록을 읽고, 보고 있던 날이 없으면 가장 최근 날을 연다.
    /// 그 뒤로 사진첩이 바뀌면 알아서 다시 읽는다.
    func loadDays() async {
        let library = self.library
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampleAlbum") {
            await library.makeSampleAlbumIfNeeded()
        }
        growSampleAlbumLaterIfAsked()
        #endif
        if watcher == nil {
            watcher = LibraryChangeWatcher { [weak self] in
                Task { @MainActor in self?.libraryDidChange() }
            }
        }
        await reload()
    }

    /// 사진첩 변경 알림은 짧은 시간에 여러 번 올 수 있어, 잠잠해진 뒤 한 번만 다시 읽는다.
    private func libraryDidChange() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            await reload()
        }
    }

    /// 날짜·앨범 목록과 지금 보고 있는 범위를 다시 읽는다.
    private func reload() async {
        let library = self.library
        (days, albums) = await Task.detached(priority: .userInitiated) {
            (library.photoDays(), library.albums())
        }.value
        // 보던 앨범은 id로 다시 찾는다. 사진 수나 이름이 바뀌어도 같은 앨범이다.
        if let albumID {
            if let album = albums.first(where: { $0.id == albumID }) {
                showAlbum(album)
                return
            }
            // 보던 앨범이 지워졌거나 비었다.
            stops = []
            sections = []
        }
        showDaily()
    }

    #if DEBUG
    private var didScheduleGrow = false

    /// 화면 테스트용: "-growSampleAlbumAfter 초" 인자가 있으면 그만큼 뒤에 샘플 앨범에 사진을 더한다.
    private func growSampleAlbumLaterIfAsked() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !didScheduleGrow, let index = arguments.firstIndex(of: "-growSampleAlbumAfter"),
              arguments.indices.contains(index + 1), let seconds = Double(arguments[index + 1]) else { return }
        didScheduleGrow = true
        let library = self.library
        Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await library.growSampleAlbum()
        }
    }
    #endif

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
        if albumID != album.id {
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
            // 사진이 많은 앨범에서 화면이 멈추지 않게, 묶는 계산도 화면 밖에서 한다.
            let (newSections, newStops) = await Task.detached(priority: .userInitiated) {
                let photos = fetch()
                if byDay {
                    let days = TimelineBuilder.days(photos)
                    return (days, days.flatMap(\.stops))
                }
                return ([TimelineDay](), TimelineBuilder.stops(photos))
            }.value
            if Task.isCancelled { return }
            sections = newSections
            stops = newStops
            // 다시 읽어도 그대로인 머문 곳은 이름을 지우지 않는다(이름이 잠깐 "장소 N"으로 바뀌지 않게).
            let ids = Set(newStops.map(\.id))
            names = names.filter { ids.contains($0.key) }
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
        guard stop.center != nil, let index = order[stop.id] else {
            return "위치 정보 없음"
        }
        return "장소 \(index + 1)"
    }
}
