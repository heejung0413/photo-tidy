import Foundation

public enum PlaceKey {
    /// 좌표를 소수 셋째 자리(약 100m 칸)로 반올림한 글자. 자동으로 받은 장소 이름의 저장 키로 쓴다.
    public static func string(for coordinate: Coordinate) -> String {
        String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
    }
}

/// 사용자가 직접 붙인 장소 이름.
public struct CustomPlaceNames: Equatable, Codable, Sendable {
    public struct Entry: Equatable, Codable, Sendable {
        /// 이름을 붙인 곳. 위치 없는 머문 곳이면 nil.
        public var coordinate: Coordinate?
        /// 위치 없는 머문 곳을 가리키는 첫 사진 id.
        public var photoID: String?
        public var name: String
    }

    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// 위치가 있으면 반경 안에서 가장 가까운 이름을 쓴다(같은 곳에 다시 가도 이름이 따라온다).
    /// 위치가 없으면 그 머문 곳(첫 사진)에 붙인 이름만 쓴다.
    public func name(for stop: TimelineStop, radius: Double = Tuning.placeNameRadius) -> String? {
        index(for: stop, radius: radius).map { entries[$0].name }
    }

    /// 앞뒤 공백을 뗀 이름을 저장한다. 빈 글자면 직접 붙인 이름을 지운다.
    public mutating func rename(_ stop: TimelineStop, to text: String, radius: Double = Tuning.placeNameRadius) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = index(for: stop, radius: radius)
        if name.isEmpty {
            if let existing {
                entries.remove(at: existing)
            }
        } else if let existing {
            entries[existing].name = name
        } else if let center = stop.center {
            entries.append(Entry(coordinate: center, photoID: nil, name: name))
        } else {
            entries.append(Entry(coordinate: nil, photoID: stop.id, name: name))
        }
    }

    private func index(for stop: TimelineStop, radius: Double) -> Int? {
        guard let center = stop.center else {
            return entries.firstIndex { $0.coordinate == nil && $0.photoID == stop.id }
        }
        var best: (index: Int, distance: Double)?
        for (index, entry) in entries.enumerated() {
            guard let coordinate = entry.coordinate else { continue }
            let distance = TimelineBuilder.distance(center, coordinate)
            if distance <= radius, distance < best?.distance ?? .infinity {
                best = (index, distance)
            }
        }
        return best?.index
    }

    // MARK: 저장 형식

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let entries = try? container.decode([Entry].self) {
            self.entries = entries
            return
        }
        // 예전 형식: "위도,경도" 또는 "photo:<id>" → 이름.
        let old = try container.decode([String: String].self)
        entries = old.sorted { $0.key < $1.key }.compactMap { key, name in
            if key.hasPrefix("photo:") {
                return Entry(coordinate: nil, photoID: String(key.dropFirst("photo:".count)), name: name)
            }
            let parts = key.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else { return nil }
            return Entry(coordinate: Coordinate(latitude: parts[0], longitude: parts[1]), photoID: nil, name: name)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }
}
