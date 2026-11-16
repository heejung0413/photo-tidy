import Foundation

extension StoreState {
    /// 건너뛰지 않은 묶음. 최근에 찍은 것부터.
    public var visibleGroups: [StoredGroup] {
        groups
            .filter { !$0.isSkipped }
            .sorted { $0.photos[0].item.takenAt > $1.photos[0].item.takenAt }
    }

    /// 추천 한 장씩만 남길 때 지울 수 있는 장수.
    public var deletableCount: Int {
        visibleGroups.reduce(0) { $0 + $1.photos.count - 1 }
    }

    /// 추천 한 장씩만 남길 때 확보되는 용량(어림).
    public var reclaimableBytes: Int64 {
        let pixels = visibleGroups.reduce(0) { sum, group in
            sum + group.photos.filter { $0.item.id != group.recommendedID }.reduce(0) { $0 + $1.item.pixelCount }
        }
        return Int64(Double(pixels) * Tuning.estimatedBytesPerPixel)
    }
}
