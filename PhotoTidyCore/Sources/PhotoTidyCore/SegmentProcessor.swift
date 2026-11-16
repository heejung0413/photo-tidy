import CoreGraphics
import Foundation

public enum SegmentProcessor {
    public struct Output: Sendable {
        public var groups: [StoredGroup]
        /// 이미지를 받지 못해 건너뛴 사진 수.
        public var unreadable: Int
    }

    /// 시간 구간 하나를 분석해 묶음을 만든다. 사진이 1장뿐이면 이미지를 읽지 않는다.
    public static func process(_ segment: [PhotoItem],
                               threshold: Float = Tuning.distanceThreshold,
                               loadImage: (String) -> CGImage?) -> Output {
        guard segment.count >= 2 else { return Output(groups: [], unreadable: 0) }

        var analyses: [String: ImageAnalysis] = [:]
        for photo in segment {
            autoreleasepool {
                if let image = loadImage(photo.id), let analysis = try? ImageAnalyzer.analyze(image) {
                    analyses[photo.id] = analysis
                }
            }
        }
        let readable = segment.filter { analyses[$0.id] != nil }

        let grouped = SimilarityGrouper.groups(in: readable, threshold: threshold) { a, b in
            guard let first = analyses[a.id], let second = analyses[b.id] else { return nil }
            return ImageAnalyzer.distance(first.featurePrint, second.featurePrint)
        }
        let groups = grouped.compactMap { members -> StoredGroup? in
            let photos = members.compactMap { item in
                analyses[item.id].map { StoredPhoto(item: item, metrics: $0.metrics) }
            }
            guard let recommended = BestShotPicker.pick(photos) else { return nil }
            return StoredGroup(photos: photos, recommendedID: recommended, isSkipped: false)
        }
        return Output(groups: groups, unreadable: segment.count - readable.count)
    }
}
