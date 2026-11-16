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
