import Foundation

public struct StoreState: Codable, Equatable, Sendable {
    public var groups: [StoredGroup]
    /// 분석을 마친 사진. 여기 없는 사진이 든 구간은 다음 분석 대상이다.
    public private(set) var analyzedIDs: Set<String>
    /// 분석을 한 번이라도 돌렸는지.
    public var hasAnalyzed: Bool
    /// 읽지 못한 사진 → 실패한 횟수. Tuning.maxReadAttempts에 이르면 포기한다.
    public private(set) var failedReads: [String: Int] = [:]

    public init(groups: [StoredGroup] = [], analyzedIDs: Set<String> = [], hasAnalyzed: Bool = false) {
        self.groups = groups
        self.analyzedIDs = analyzedIDs
        self.hasAnalyzed = hasAnalyzed
    }

    private enum CodingKeys: String, CodingKey {
        case groups, analyzedIDs, hasAnalyzed, failedReads
        /// 예전 형식: 마지막으로 분석한 사진의 촬영 시각.
        case watermark
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decode([StoredGroup].self, forKey: .groups)
        analyzedIDs = try container.decodeIfPresent(Set<String>.self, forKey: .analyzedIDs) ?? []
        hasAnalyzed = try container.decodeIfPresent(Bool.self, forKey: .hasAnalyzed)
            ?? container.contains(.watermark)
        failedReads = try container.decodeIfPresent([String: Int].self, forKey: .failedReads) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groups, forKey: .groups)
        try container.encode(analyzedIDs, forKey: .analyzedIDs)
        try container.encode(hasAnalyzed, forKey: .hasAnalyzed)
        try container.encode(failedReads, forKey: .failedReads)
    }

    public mutating func markAnalyzed<S: Sequence>(_ ids: S) where S.Element == String {
        for id in ids {
            analyzedIDs.insert(id)
            failedReads[id] = nil
        }
    }

    /// 읽지 못한 사진을 기록한다. 다음 분석에서 다시 시도하되, 계속 실패하면 포기한다
    /// (영영 못 읽는 사진 하나 때문에 그 구간을 매번 다시 분석하지 않도록).
    public mutating func markUnreadable<S: Sequence>(_ ids: S) where S.Element == String {
        for id in ids {
            let attempts = (failedReads[id] ?? 0) + 1
            if attempts >= Tuning.maxReadAttempts {
                markAnalyzed([id])
            } else {
                failedReads[id] = attempts
            }
        }
    }

    /// 사진첩에서 사라진 사진의 분석 기록을 지운다.
    public mutating func forgetAnalyzed(notIn existing: Set<String>) {
        analyzedIDs.formIntersection(existing)
        failedReads = failedReads.filter { existing.contains($0.key) }
    }

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
    /// target은 화면이 들고 있던 묶음이라, 저장된 묶음과 사진 구성이 조금 다를 수 있다.
    public mutating func resolve(_ target: StoredGroup, deleted: Set<String>) {
        guard let index = index(of: target) else { return }
        var group = groups[index]
        group.photos.removeAll { deleted.contains($0.item.id) }
        group.isSkipped = true
        if let repaired = Self.repaired(group) {
            groups[index] = repaired
        } else {
            groups.remove(at: index)
        }
    }

    public mutating func skip(_ target: StoredGroup) {
        guard let index = index(of: target) else { return }
        groups[index].isSkipped = true
    }

    /// target과 사진이 겹치는 저장된 묶음의 위치.
    /// 묶음의 id는 첫 사진의 id라서, 첫 사진이 사진첩에서 사라지면 같은 묶음인데도 id가 달라진다.
    /// 그래서 id가 아니라 사진으로 찾는다. 저장된 묶음끼리는 사진이 겹치지 않는다(merge가 합친다).
    private func index(of target: StoredGroup) -> Int? {
        let ids = Set(target.photos.map(\.item.id))
        return groups.firstIndex { $0.photos.contains { ids.contains($0.item.id) } }
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
