import CoreGraphics
import Foundation

public enum SegmentProcessor {
    public struct Output: Sendable {
        public var groups: [StoredGroup]
        /// 이미지를 받지 못해 건너뛴 사진.
        public var unreadableIDs: [String]
        public var unreadable: Int { unreadableIDs.count }
        /// 도중에 멈췄다. 이때 groups와 unreadableIDs는 비어 있고, 이 구간은 분석하지 않은 것으로 본다.
        public var wasCancelled = false
    }

    /// 시간 구간 하나를 분석해 묶음을 만든다. 사진이 1장뿐이면 이미지를 읽지 않는다.
    /// 긴 구간도 멈출 수 있게 사진마다 isCancelled를 확인하고, 읽은 장수를 onProgress로 알린다.
    public static func process(_ segment: [PhotoItem],
                               threshold: Float = Tuning.distanceThreshold,
                               isCancelled: () -> Bool = { false },
                               onProgress: (Int) -> Void = { _ in },
                               loadImage: (String) -> CGImage?) -> Output {
        let cancelled = Output(groups: [], unreadableIDs: [], wasCancelled: true)
        guard segment.count >= 2 else { return Output(groups: [], unreadableIDs: []) }

        var analyses: [String: ImageAnalysis] = [:]
        for (index, photo) in segment.enumerated() {
            if isCancelled() { return cancelled }
            autoreleasepool {
                if let image = loadImage(photo.id), let analysis = try? ImageAnalyzer.analyze(image) {
                    analyses[photo.id] = analysis
                }
            }
            onProgress(index + 1)
        }
        let readable = segment.filter { analyses[$0.id] != nil }

        let grouped = SimilarityGrouper.groups(in: readable, threshold: threshold, isCancelled: isCancelled) { a, b in
            guard let first = analyses[a.id], let second = analyses[b.id] else { return nil }
            return ImageAnalyzer.distance(first.featurePrint, second.featurePrint)
        }
        if isCancelled() { return cancelled }
        let groups = grouped.compactMap { members -> StoredGroup? in
            let photos = members.compactMap { item in
                analyses[item.id].map { StoredPhoto(item: item, metrics: $0.metrics) }
            }
            guard let recommended = BestShotPicker.pick(photos) else { return nil }
            return StoredGroup(photos: photos, recommendedID: recommended, isSkipped: false)
        }
        return Output(groups: groups,
                      unreadableIDs: segment.filter { analyses[$0.id] == nil }.map(\.id))
    }
}
