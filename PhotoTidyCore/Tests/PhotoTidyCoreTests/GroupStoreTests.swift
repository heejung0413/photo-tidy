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
                               analyzedIDs: ["a", "b", "c"], hasAnalyzed: true)
        try store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testLoadMissingFileGivesEmptyState() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        XCTAssertEqual(GroupStore(url: url).load(), StoreState())
    }

    func testNewStateHasAnalyzedNothing() {
        XCTAssertTrue(StoreState().analyzedIDs.isEmpty)
        XCTAssertFalse(StoreState().hasAnalyzed)
    }

    func testMarkAnalyzedRemembersPhotos() {
        var state = StoreState()
        state.markAnalyzed(["a", "b"])
        state.markAnalyzed(["b", "c"])
        XCTAssertEqual(state.analyzedIDs, ["a", "b", "c"])
    }

    func testForgetAnalyzedDropsPhotosNoLongerInLibrary() {
        var state = StoreState(analyzedIDs: ["a", "b", "c"])
        state.forgetAnalyzed(notIn: ["a", "c", "new"])
        XCTAssertEqual(state.analyzedIDs, ["a", "c"])
    }

    /// 예전 형식(기준 시각만 저장) 파일: 묶음은 유지하고, 분석 기록이 없으므로 다음에 전체를 다시 본다.
    func testOldFileWithWatermarkKeepsGroupsAndReanalyzesEverything() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let groupsJSON = String(decoding: try JSONEncoder().encode([group(["a", "b"], recommended: "b")]),
                                as: UTF8.self)
        try Data("{\"groups\":\(groupsJSON),\"watermark\":100}".utf8).write(to: url)
        let state = GroupStore(url: url).load()
        XCTAssertEqual(state.groups.map(\.id), ["a"])
        XCTAssertTrue(state.analyzedIDs.isEmpty)
        XCTAssertTrue(state.hasAnalyzed)
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

    // MARK: 읽지 못한 사진 다시 시도

    func testUnreadablePhotoIsRetriedUntilLimitThenGivenUp() {
        var state = StoreState()
        for _ in 0..<(Tuning.maxReadAttempts - 1) {
            state.markUnreadable(["bad"])
            XCTAssertFalse(state.analyzedIDs.contains("bad"))
        }
        state.markUnreadable(["bad"])
        XCTAssertTrue(state.analyzedIDs.contains("bad"))
    }

    func testSuccessfulReadClearsFailureCount() {
        var state = StoreState()
        for _ in 0..<(Tuning.maxReadAttempts - 1) {
            state.markUnreadable(["flaky"])
        }
        state.markAnalyzed(["flaky"])
        XCTAssertTrue(state.failedReads.isEmpty)
    }

    func testFailureCountsSurviveSaveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        var state = StoreState()
        state.markUnreadable(["bad"])
        try GroupStore(url: url).save(state)
        var loaded = GroupStore(url: url).load()
        XCTAssertEqual(loaded, state)
        for _ in 0..<(Tuning.maxReadAttempts - 1) {
            loaded.markUnreadable(["bad"])
        }
        XCTAssertTrue(loaded.analyzedIDs.contains("bad"))
    }

    func testForgetAnalyzedAlsoDropsFailureCountsOfMissingPhotos() {
        var state = StoreState()
        state.markUnreadable(["gone", "kept"])
        state.forgetAnalyzed(notIn: ["kept"])
        XCTAssertEqual(Array(state.failedReads.keys), ["kept"])
    }
}
