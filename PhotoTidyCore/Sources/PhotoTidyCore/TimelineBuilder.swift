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

/// 하루치 머문 곳. 여러 날을 이어 볼 때 쓴다.
public struct TimelineDay: Identifiable, Hashable, Sendable {
    /// 그날의 0시.
    public let day: Date
    public let stops: [TimelineStop]

    public var id: Date { day }
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

    /// 여러 날 사진을 날짜별로 나눠 각각 머문 곳으로 묶는다. 날짜 오름차순.
    /// 날이 바뀌면 같은 장소여도 새 머문 곳이 된다.
    public static func days(_ photos: [TimelinePhoto], calendar: Calendar = .current,
                            radius: Double = Tuning.stopRadius) -> [TimelineDay] {
        let byDay = Dictionary(grouping: photos) { calendar.startOfDay(for: $0.takenAt) }
        return byDay.keys.sorted().map { day in
            TimelineDay(day: day, stops: stops(byDay[day] ?? [], radius: radius))
        }
    }
}
