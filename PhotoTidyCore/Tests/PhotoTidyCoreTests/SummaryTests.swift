import XCTest
@testable import PhotoTidyCore

final class SummaryTests: XCTestCase {
    private func group(_ ids: [String], at t: TimeInterval, recommended: String, pixels: Int = 1000,
                       skipped: Bool = false) -> StoredGroup {
        let photos = ids.enumerated().map { stored($1, at: t + TimeInterval($0), pixels: pixels) }
        return StoredGroup(photos: photos, recommendedID: recommended, isSkipped: skipped)
    }

    func testEmptyStateHasNothingToTidy() {
        let state = StoreState()
        XCTAssertTrue(state.visibleGroups.isEmpty)
        XCTAssertEqual(state.deletableCount, 0)
        XCTAssertEqual(state.reclaimableBytes, 0)
    }

    func testVisibleGroupsHideSkippedAndShowNewestFirst() {
        let state = StoreState(groups: [
            group(["old1", "old2"], at: 0, recommended: "old1"),
            group(["skip1", "skip2"], at: 500, recommended: "skip1", skipped: true),
            group(["new1", "new2"], at: 1000, recommended: "new1"),
        ])
        XCTAssertEqual(state.visibleGroups.map(\.id), ["new1", "old1"])
    }

    func testDeletableCountKeepsOnePhotoPerVisibleGroup() {
        let state = StoreState(groups: [
            group(["a", "b", "c"], at: 0, recommended: "a"),
            group(["d", "e"], at: 100, recommended: "e"),
            group(["f", "g", "h", "i"], at: 200, recommended: "f", skipped: true),
        ])
        XCTAssertEqual(state.deletableCount, 3)
    }

    func testReclaimableBytesCountsOnlyPhotosThatWouldBeDeleted() {
        let photos = [stored("keep", pixels: 5_000_000), stored("drop1", at: 1, pixels: 1_000_000),
                      stored("drop2", at: 2, pixels: 2_000_000)]
        let state = StoreState(groups: [StoredGroup(photos: photos, recommendedID: "keep", isSkipped: false)])
        XCTAssertEqual(state.reclaimableBytes, Int64(3_000_000 * Tuning.estimatedBytesPerPixel))
    }

    func testReclaimableBytesIgnoresSkippedGroups() {
        let state = StoreState(groups: [group(["a", "b"], at: 0, recommended: "a", skipped: true)])
        XCTAssertEqual(state.reclaimableBytes, 0)
    }
}
