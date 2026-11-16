import XCTest
@testable import PhotoTidyCore

final class SimilarityGrouperTests: XCTestCase {
    private func distance(_ table: [String: Float]) -> (PhotoItem, PhotoItem) -> Float? {
        { a, b in table["\(a.id)|\(b.id)"] ?? table["\(b.id)|\(a.id)"] }
    }

    func testSegmentsSplitWhenGapExceedsMaxGap() {
        let photos = [photo("a", at: 0), photo("b", at: 30), photo("c", at: 90),
                      photo("d", at: 200), photo("e", at: 201)]
        let segments = SimilarityGrouper.segments(photos, maxGap: 60)
        XCTAssertEqual(segments.map { $0.map(\.id) }, [["a", "b", "c"], ["d", "e"]])
    }

    func testSegmentsSortByTime() {
        let segments = SimilarityGrouper.segments([photo("b", at: 10), photo("a", at: 0)], maxGap: 60)
        XCTAssertEqual(segments.map { $0.map(\.id) }, [["a", "b"]])
    }

    func testGroupsChainSimilarPhotosAndDropSingles() {
        let segment = [photo("a", at: 0), photo("b", at: 1), photo("c", at: 2), photo("d", at: 3)]
        let table: [String: Float] = ["a|b": 0.2, "b|c": 0.4, "a|c": 0.9, "a|d": 0.9, "b|d": 0.9, "c|d": 0.9]
        let groups = SimilarityGrouper.groups(in: segment, threshold: 0.5, distance: distance(table))
        XCTAssertEqual(groups.map { $0.map(\.id) }, [["a", "b", "c"]])
    }

    func testGroupsCanProduceTwoGroupsInOneSegment() {
        let segment = [photo("a", at: 0), photo("b", at: 1), photo("c", at: 2), photo("d", at: 3)]
        let table: [String: Float] = ["a|b": 0.1, "c|d": 0.1, "a|c": 0.9, "a|d": 0.9, "b|c": 0.9, "b|d": 0.9]
        let groups = SimilarityGrouper.groups(in: segment, threshold: 0.5, distance: distance(table))
        XCTAssertEqual(groups.map { $0.map(\.id) }, [["a", "b"], ["c", "d"]])
    }

    func testGroupsTreatMissingDistanceAsNotSimilar() {
        let segment = [photo("a", at: 0), photo("b", at: 1)]
        let groups = SimilarityGrouper.groups(in: segment, threshold: 0.5, distance: distance([:]))
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: 경계값

    func testGapExactlyMaxGapStaysInSameSegment() {
        let segments = SimilarityGrouper.segments([photo("a", at: 0), photo("b", at: 60), photo("c", at: 120.5)],
                                                  maxGap: 60)
        XCTAssertEqual(segments.map { $0.map(\.id) }, [["a", "b"], ["c"]])
    }

    func testEmptyInputGivesNoSegmentsAndNoGroups() {
        XCTAssertTrue(SimilarityGrouper.segments([]).isEmpty)
        XCTAssertTrue(SimilarityGrouper.groups(in: [], threshold: 0.5) { _, _ in 0 }.isEmpty)
    }

    func testDistanceExactlyThresholdCountsAsSimilar() {
        let segment = [photo("a", at: 0), photo("b", at: 1), photo("c", at: 2)]
        let groups = SimilarityGrouper.groups(in: segment, threshold: 0.5) { first, second in
            Set([first.id, second.id]) == ["a", "b"] ? 0.5 : 0.5001
        }
        XCTAssertEqual(groups.map { $0.map(\.id).sorted() }, [["a", "b"]])
    }

    func testNothingSimilarGivesNoGroups() {
        let segment = [photo("a", at: 0), photo("b", at: 1)]
        XCTAssertTrue(SimilarityGrouper.groups(in: segment, threshold: 0.5) { _, _ in 0.9 }.isEmpty)
    }
}
