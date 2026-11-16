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
