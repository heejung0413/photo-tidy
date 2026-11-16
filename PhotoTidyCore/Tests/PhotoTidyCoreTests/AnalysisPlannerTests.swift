import XCTest
@testable import PhotoTidyCore

final class AnalysisPlannerTests: XCTestCase {
    private func ids(_ segments: [[PhotoItem]]) -> [[String]] {
        segments.map { $0.map(\.id) }
    }

    func testFirstRunPlansEverySegment() {
        let photos = [photo("a", at: 0), photo("b", at: 10), photo("c", at: 1000)]
        XCTAssertEqual(ids(AnalysisPlanner.pendingSegments(photos, analyzed: [], maxGap: 60)), [["a", "b"], ["c"]])
    }

    func testNothingPendingWhenEverythingWasAnalyzed() {
        let photos = [photo("a", at: 0), photo("b", at: 10), photo("c", at: 1000)]
        XCTAssertTrue(AnalysisPlanner.pendingSegments(photos, analyzed: ["a", "b", "c"], maxGap: 60).isEmpty)
    }

    func testNewerPhotosArePlannedWithoutRedoingOldSegments() {
        let photos = [photo("a", at: 0), photo("b", at: 10), photo("c", at: 1000), photo("d", at: 1010)]
        XCTAssertEqual(ids(AnalysisPlanner.pendingSegments(photos, analyzed: ["a", "b"], maxGap: 60)), [["c", "d"]])
    }

    /// 분석을 마친 뒤 사진첩에 들어온, 촬영 시각이 옛날인 사진(에어드롭 등)도 빠지지 않는다.
    func testPhotoAddedLaterWithOldCaptureTimeIsPlannedWithItsNeighbours() {
        let photos = [photo("old", at: 0), photo("lateArrival", at: 10), photo("recent", at: 5000)]
        let pending = AnalysisPlanner.pendingSegments(photos, analyzed: ["old", "recent"], maxGap: 60)
        XCTAssertEqual(ids(pending), [["old", "lateArrival"]])
    }

    /// 읽지 못해 분석 완료로 표시되지 않은 사진은 다음 분석에서 다시 시도한다.
    func testPhotoNotMarkedAnalyzedIsRetried() {
        let photos = [photo("a", at: 0), photo("unreadable", at: 10), photo("c", at: 1000)]
        let pending = AnalysisPlanner.pendingSegments(photos, analyzed: ["a", "c"], maxGap: 60)
        XCTAssertEqual(ids(pending), [["a", "unreadable"]])
    }
}
