import Foundation

public enum SimilarityGrouper {
    /// 촬영 시각순으로 정렬한 뒤, 앞 사진과의 간격이 maxGap 이내인 사진끼리 한 구간으로 잇는다.
    public static func segments(_ photos: [PhotoItem], maxGap: TimeInterval = Tuning.maxGap) -> [[PhotoItem]] {
        var result: [[PhotoItem]] = []
        for photo in photos.sorted(by: { $0.takenAt < $1.takenAt }) {
            if let last = result.last?.last, photo.takenAt.timeIntervalSince(last.takenAt) <= maxGap {
                result[result.count - 1].append(photo)
            } else {
                result.append([photo])
            }
        }
        return result
    }

    /// 구간 안에서 거리가 threshold 이하인 사진을 연결하고, 연결된 덩어리 중 2장 이상인 것만 돌려준다.
    public static func groups(in segment: [PhotoItem],
                              threshold: Float = Tuning.distanceThreshold,
                              distance: (PhotoItem, PhotoItem) -> Float?) -> [[PhotoItem]] {
        var parent = Array(segment.indices)
        func find(_ start: Int) -> Int {
            var i = start
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        for i in segment.indices {
            for j in segment.indices where j > i {
                guard let d = distance(segment[i], segment[j]), d <= threshold else { continue }
                let (a, b) = (find(i), find(j))
                parent[a] = b
            }
        }
        var buckets: [Int: [PhotoItem]] = [:]
        for i in segment.indices {
            buckets[find(i), default: []].append(segment[i])
        }
        return buckets.values
            .filter { $0.count >= 2 }
            .sorted { $0[0].takenAt < $1[0].takenAt }
    }
}
