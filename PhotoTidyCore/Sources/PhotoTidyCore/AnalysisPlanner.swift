import Foundation

public enum AnalysisPlanner {
    /// 아직 분석하지 않은 사진이 하나라도 든 구간만 고른다.
    /// 촬영 시각이 아니라 "분석했는지"로 판단하므로, 나중에 사진첩에 들어온 옛날 사진과
    /// 지난번에 읽지 못한 사진도 이웃 사진과 함께 다시 본다.
    public static func pendingSegments(_ photos: [PhotoItem], analyzed: Set<String>,
                                       maxGap: TimeInterval = Tuning.maxGap) -> [[PhotoItem]] {
        SimilarityGrouper.segments(photos, maxGap: maxGap).filter { segment in
            segment.contains { !analyzed.contains($0.id) }
        }
    }
}
