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
        let target = group(["a", "b", "c"], recommended: "c")
        var state = StoreState(groups: [target])
        state.resolve(target, deleted: ["a"])
        XCTAssertEqual(state.groups[0].photos.map(\.item.id), ["b", "c"])
        XCTAssertTrue(state.groups[0].isSkipped)
    }

    func testResolveRemovesGroupWhenOneRemains() {
        let target = group(["a", "b", "c"], recommended: "c")
        var state = StoreState(groups: [target])
        state.resolve(target, deleted: ["a", "b"])
        XCTAssertTrue(state.groups.isEmpty)
    }

    func testSkipHidesGroup() {
        let target = group(["a", "b"], recommended: "b")
        var state = StoreState(groups: [target])
        state.skip(target)
        XCTAssertTrue(state.groups[0].isSkipped)
    }

    // MARK: 화면이 들고 있던 묶음과 저장된 묶음이 어긋났을 때

    /// 삭제 확인 창이 닫히며 앱이 다시 켜질 때, 사라진 사진 정리(prune)가 삭제 마무리보다 먼저 돌 수 있다.
    /// 그때 첫 사진이 지워졌으면 묶음의 id가 바뀌어 있다.
    func testResolveHidesGroupWhoseFirstPhotoWasAlreadyPruned() {
        let shown = group(["a", "b", "c", "d"], recommended: "d")
        var state = StoreState(groups: [shown])
        state.prune(existing: ["c", "d"])
        state.resolve(shown, deleted: ["a", "b"])
        XCTAssertEqual(state.groups.map { $0.photos.map(\.item.id) }, [["c", "d"]])
        XCTAssertEqual(state.groups.map(\.isSkipped), [true])
    }

    /// 상세 화면을 연 채로 사진 앱에서 묶음의 첫 사진을 지우고 돌아와 건너뛰기를 누른 경우.
    func testSkipHidesGroupWhoseFirstPhotoWasAlreadyPruned() {
        let shown = group(["a", "b", "c"], recommended: "c")
        var state = StoreState(groups: [shown])
        state.prune(existing: ["b", "c"])
        state.skip(shown)
        XCTAssertEqual(state.groups.map(\.isSkipped), [true])
    }

    /// 첫 사진뿐 아니라 추천 사진·마지막 사진까지 사라져도, 남은 사진이 하나라도 겹치면 같은 묶음이다.
    func testResolveFindsGroupByAnyRemainingPhoto() {
        let shown = group(["a", "b", "c", "d"], recommended: "d")
        var state = StoreState(groups: [shown])
        state.prune(existing: ["b", "c"])
        state.resolve(shown, deleted: ["a", "d"])
        XCTAssertEqual(state.groups.map { $0.photos.map(\.item.id) }, [["b", "c"]])
        XCTAssertEqual(state.groups.map(\.isSkipped), [true])
    }

    func testSkipFindsGroupByAnyRemainingPhoto() {
        let shown = group(["a", "b", "c", "d"], recommended: "d")
        var state = StoreState(groups: [shown])
        state.prune(existing: ["b", "c"])
        state.skip(shown)
        XCTAssertEqual(state.groups.map(\.isSkipped), [true])
    }

    func testResolveAndSkipLeaveOtherGroupsAlone() {
        let first = group(["a", "b", "c"], recommended: "c")
        let second = group(["x", "y", "z"], recommended: "z")
        var state = StoreState(groups: [first, second])
        state.prune(existing: ["b", "c", "y", "z"])
        state.resolve(second, deleted: ["x"])
        XCTAssertEqual(state.groups.map(\.isSkipped), [false, true])
        state = StoreState(groups: [first, second])
        state.prune(existing: ["b", "c", "y", "z"])
        state.skip(second)
        XCTAssertEqual(state.groups.map(\.isSkipped), [false, true])
    }

    /// 묶음이 통째로 사라진 뒤(남은 사진 1장 이하)에 마무리해도 다른 묶음을 건드리지 않는다.
    func testResolveDoesNothingWhenGroupIsGone() {
        let gone = group(["a", "b"], recommended: "b")
        let other = group(["x", "y"], recommended: "y")
        var state = StoreState(groups: [gone, other])
        state.prune(existing: ["b", "x", "y"])
        state.resolve(gone, deleted: ["a"])
        XCTAssertEqual(state.groups, [other])
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
