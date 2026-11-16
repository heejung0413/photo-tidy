import Foundation

public enum PlaceKey {
    /// 좌표를 소수 셋째 자리(약 100m 칸)로 반올림한 글자. 자동으로 받은 장소 이름의 저장 키로 쓴다.
    public static func string(for coordinate: Coordinate) -> String {
        String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
    }
}

/// 사용자가 직접 붙인 장소 이름.
///
/// 이름은 "그 머문 곳의 사진"에 붙는다. 그래서 사진이 더해져 중심이 움직여도 이름이 유지되고,
/// 한 곳의 이름을 고쳐도 옆 장소는 바뀌지 않는다.
/// 이름을 붙인 적 없는 머문 곳은, 가까이에 이름 붙인 곳이 있으면 그 이름을 물려받는다(다른 날 같은 곳).
public struct CustomPlaceNames: Equatable, Codable, Sendable {
    public struct Entry: Equatable, Sendable {
        /// 이름을 붙인 머문 곳의 사진.
        public var photoIDs: [String]
        /// 그때의 중심. 가까운 다른 머문 곳이 이름을 물려받는 기준. 위치 없는 머문 곳이면 nil.
        public var coordinate: Coordinate?
        /// nil이면 "이 머문 곳은 물려받지 말고 자동 이름을 쓴다"는 표시.
        public var name: String?
    }

    public private(set) var entries: [Entry] {
        didSet { rebuildIndex() }
    }
    /// 사진 id → entries 위치. 머문 곳의 이름을 바로 찾기 위한 색인.
    private var entryByPhoto: [String: Int] = [:]

    public init(entries: [Entry] = []) {
        self.entries = entries
        rebuildIndex()
    }

    public static func == (lhs: CustomPlaceNames, rhs: CustomPlaceNames) -> Bool {
        lhs.entries == rhs.entries
    }

    /// 직접 붙인 이름. 없으면 radius 안에서 가장 가까운 이름 붙인 곳의 이름. 그것도 없으면 nil.
    public func name(for stop: TimelineStop, radius: Double = Tuning.stopRadius) -> String? {
        if let own = ownIndex(for: stop) {
            return entries[own].name
        }
        return inheritedName(for: stop, radius: radius, excluding: nil)
    }

    /// 앞뒤 공백을 뗀 이름을 이 머문 곳에 붙인다. 빈 글자면 직접 붙인 이름을 지워 자동 이름으로 돌아간다.
    public mutating func rename(_ stop: TimelineStop, to text: String, radius: Double = Tuning.stopRadius) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let own = ownIndex(for: stop)
        var name: String? = trimmed
        if trimmed.isEmpty {
            // 지웠는데도 옆 장소 이름을 물려받게 되면, 물려받지 않는다는 표시를 남긴다.
            guard inheritedName(for: stop, radius: radius, excluding: own) != nil else {
                if let own {
                    entries.remove(at: own)
                }
                return
            }
            name = nil
        }
        let photoIDs = Set(stop.photos.map(\.id))
        if let own {
            entries[own] = Entry(photoIDs: photoIDs.union(entries[own].photoIDs).sorted(),
                                 coordinate: stop.center, name: name)
        } else {
            entries.append(Entry(photoIDs: photoIDs.sorted(), coordinate: stop.center, name: name))
        }
    }

    /// 이 머문 곳의 사진과 가장 많이 겹치는 항목.
    private func ownIndex(for stop: TimelineStop) -> Int? {
        var overlap: [Int: Int] = [:]
        for photo in stop.photos {
            if let index = entryByPhoto[photo.id] {
                overlap[index, default: 0] += 1
            }
        }
        return overlap.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key
    }

    private func inheritedName(for stop: TimelineStop, radius: Double, excluding excluded: Int?) -> String? {
        guard let center = stop.center else { return nil }
        var best: (name: String, distance: Double)?
        for (index, entry) in entries.enumerated() where index != excluded {
            guard let name = entry.name, let coordinate = entry.coordinate else { continue }
            let distance = TimelineBuilder.distance(center, coordinate)
            if distance <= radius, distance < best?.distance ?? .infinity {
                best = (name, distance)
            }
        }
        return best?.name
    }

    private mutating func rebuildIndex() {
        var index: [String: Int] = [:]
        for (position, entry) in entries.enumerated() {
            for id in entry.photoIDs where index[id] == nil {
                index[id] = position
            }
        }
        entryByPhoto = index
    }

    // MARK: 저장 형식

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            entries = try container.decode([Entry].self)
        } catch let entryError {
            // 처음 형식: "위도,경도" 또는 "photo:<id>" → 이름. 그것도 아니면 원래 오류를 알린다.
            guard let old = try? container.decode([String: String].self) else { throw entryError }
            entries = old.sorted { $0.key < $1.key }.compactMap { key, name in
                if key.hasPrefix("photo:") {
                    return Entry(photoIDs: [String(key.dropFirst("photo:".count))], coordinate: nil, name: name)
                }
                let parts = key.split(separator: ",").compactMap { Double($0) }
                guard parts.count == 2 else { return nil }
                return Entry(photoIDs: [], coordinate: Coordinate(latitude: parts[0], longitude: parts[1]),
                             name: name)
            }
        }
        rebuildIndex()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }
}

extension CustomPlaceNames.Entry: Codable {
    private enum CodingKeys: String, CodingKey {
        case photoIDs, coordinate, name
        /// 두 번째 형식: 위치 없는 머문 곳의 첫 사진 하나.
        case photoID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let ids = try container.decodeIfPresent([String].self, forKey: .photoIDs) {
            photoIDs = ids
        } else {
            photoIDs = try container.decodeIfPresent(String.self, forKey: .photoID).map { [$0] } ?? []
        }
        coordinate = try container.decodeIfPresent(Coordinate.self, forKey: .coordinate)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(photoIDs, forKey: .photoIDs)
        try container.encodeIfPresent(coordinate, forKey: .coordinate)
        try container.encodeIfPresent(name, forKey: .name)
    }
}

/// 직접 붙인 장소 이름 파일.
public struct PlaceNameStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// 파일이 없으면 빈 상태. 읽을 수 없는 파일은 "<이름>.broken"으로 옮겨 두고 빈 상태로 시작한다
    /// (다음 저장이 기존 이름들을 덮어써 없애지 않도록).
    public func load() -> CustomPlaceNames {
        guard let data = try? Data(contentsOf: url) else { return CustomPlaceNames() }
        if let names = try? JSONDecoder().decode(CustomPlaceNames.self, from: data) {
            return names
        }
        let backup = url.appendingPathExtension("broken")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        return CustomPlaceNames()
    }

    public func save(_ names: CustomPlaceNames) throws {
        try JSONEncoder().encode(names).write(to: url, options: .atomic)
    }
}
