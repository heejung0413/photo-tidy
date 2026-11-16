import XCTest
@testable import PhotoTidyCore

final class GroupStoreTests: XCTestCase {
    private func group(_ ids: [String], recommended: String, skipped: Bool = false) -> StoredGroup {
        let photos = ids.enumerated().map { stored($1, at: TimeInterval($0), sharpness: Double($0)) }
        return StoredGroup(photos: photos, recommendedID: recommended, isSkipped: skipped)
    }

    func testSaveAndLoadRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GroupStore(url: url)
        let state = StoreState(groups: [group(["a", "b"], recommended: "b")],
                               watermark: Date(timeIntervalSinceReferenceDate: 100))
        try store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testLoadMissingFileGivesEmptyState() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        XCTAssertEqual(GroupStore(url: url).load(), StoreState())
    }

    func testResumeDateIsWatermarkMinusMaxGap() {
        let state = StoreState(watermark: Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertEqual(state.resumeDate, Date(timeIntervalSinceReferenceDate: 100 - Tuning.maxGap))
        XCTAssertNil(StoreState().resumeDate)
    }

    func testPruneRemovesMissingPhotosAndSmallGroups() {
        var state = StoreState(groups: [group(["a", "b", "c"], recommended: "c"), group(["x", "y"], recommended: "y")])
        state.prune(existing: ["a", "b", "x"])
        XCTAssertEqual(state.groups.count, 1)
        XCTAssertEqual(state.groups[0].photos.map(\.item.id), ["a", "b"])
        XCTAssertEqual(state.groups[0].recommendedID, "b") // c가 사라져 다시 고름(더 선명한 b)
    }

    func testMergeAppendsGroupWithoutOverlap() {
        var state = StoreState(groups: [group(["a", "b"], recommended: "b")])
        state.merge([group(["x", "y"], recommended: "y")])
        XCTAssertEqual(state.groups.count, 2)
    }

    func testMergeUnionsOverlappingGroupAndUnhides() {
        var state = StoreState(groups: [group(["a", "b"], recommended: "b", skipped: true)])
        let incoming = StoredGroup(photos: [stored("b", at: 1, sharpness: 1), stored("c", at: 2, sharpness: 9)],
                                   recommendedID: "c", isSkipped: false)
        state.merge([incoming])
        XCTAssertEqual(state.groups.count, 1)
        XCTAssertEqual(state.groups[0].photos.map(\.item.id), ["a", "b", "c"])
        XCTAssertEqual(state.groups[0].recommendedID, "c")
        XCTAssertFalse(state.groups[0].isSkipped)
    }

    func testMergeKeepsHiddenGroupWhenNothingNew() {
        let hidden = group(["a", "b"], recommended: "a", skipped: true)
        var state = StoreState(groups: [hidden])
        state.merge([group(["a", "b"], recommended: "b")])
        XCTAssertEqual(state.groups, [hidden])
    }

    func testResolveHidesGroupWhenTwoOrMoreRemain() {
        var state = StoreState(groups: [group(["a", "b", "c"], recommended: "c")])
        state.resolve(groupID: "a", deleted: ["a"])
        XCTAssertEqual(state.groups[0].photos.map(\.item.id), ["b", "c"])
        XCTAssertTrue(state.groups[0].isSkipped)
    }

    func testResolveRemovesGroupWhenOneRemains() {
        var state = StoreState(groups: [group(["a", "b", "c"], recommended: "c")])
        state.resolve(groupID: "a", deleted: ["a", "b"])
        XCTAssertTrue(state.groups.isEmpty)
    }

    func testSkipHidesGroup() {
        var state = StoreState(groups: [group(["a", "b"], recommended: "b")])
        state.skip(groupID: "a")
        XCTAssertTrue(state.groups[0].isSkipped)
    }

    // MARK: 파일이 깨졌을 때

    func testLoadBrokenFileGivesEmptyState() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{ not json".utf8).write(to: url)
        XCTAssertEqual(GroupStore(url: url).load(), StoreState())
    }

    func testSaveOverwritesPreviousState() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GroupStore(url: url)
        try store.save(StoreState(groups: [group(["a", "b"], recommended: "a")]))
        try store.save(StoreState())
        XCTAssertEqual(store.load(), StoreState())
    }
}
