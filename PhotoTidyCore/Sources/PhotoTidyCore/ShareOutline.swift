import Foundation

/// 공유 이미지에 담을 내용. 만드는 순간의 값을 모두 담아 두므로,
/// 이미지를 만드는 동안 화면 상태가 바뀌어도 내용이 섞이지 않는다.
public struct ShareOutline: Sendable {
    public struct Stop: Identifiable, Sendable {
        public let stop: TimelineStop
        public let number: Int
        public let title: String
        /// 썸네일로 쓸 사진.
        public let thumbnailIDs: [String]
        /// 썸네일에 담지 못한 사진 수.
        public let moreCount: Int

        public var id: String { stop.id }
    }

    public struct Section: Identifiable, Sendable {
        public let day: Date
        public let stops: [Stop]

        public var id: Date { day }
    }

    public struct Pin: Sendable {
        public let number: Int
        public let coordinate: Coordinate
    }

    public let sections: [Section]
    /// 날짜별 경로. 위치 있는 머문 곳만.
    public let routes: [[Pin]]
    /// maxStops를 넘어 담지 못한 머문 곳 수.
    public let hiddenStops: Int
    /// 담지 못한 머문 곳까지 포함한 전체 사진 수.
    public let photoCount: Int

    public init(days: [TimelineDay], maxStops: Int, thumbnailsPerStop: Int, title: (TimelineStop) -> String) {
        var sections: [Section] = []
        var routes: [[Pin]] = []
        var number = 0
        for day in days where number < maxStops {
            var stops: [Stop] = []
            var route: [Pin] = []
            for stop in day.stops where number < maxStops {
                number += 1
                stops.append(Stop(stop: stop, number: number, title: title(stop),
                                  thumbnailIDs: stop.photos.prefix(thumbnailsPerStop).map(\.id),
                                  moreCount: max(0, stop.photos.count - thumbnailsPerStop)))
                if let center = stop.center {
                    route.append(Pin(number: number, coordinate: center))
                }
            }
            sections.append(Section(day: day.day, stops: stops))
            routes.append(route)
        }
        let allStops = days.flatMap(\.stops)
        self.sections = sections
        self.routes = routes
        self.hiddenStops = allStops.count - number
        self.photoCount = allStops.reduce(0) { $0 + $1.photos.count }
    }
}
