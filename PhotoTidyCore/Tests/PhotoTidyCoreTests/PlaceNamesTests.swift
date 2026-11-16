import XCTest
@testable import PhotoTidyCore

final class PlaceNamesTests: XCTestCase {
    /// ids의 사진으로 이뤄진 머문 곳. latitude가 nil이면 위치 없음.
    private func stop(_ ids: [String], _ latitude: Double? = nil, _ longitude: Double = 127.0) -> TimelineStop {
        let coordinate = latitude.map { Coordinate(latitude: $0, longitude: longitude) }
        return TimelineStop(photos: ids.map { TimelinePhoto(id: $0, takenAt: Date(timeIntervalSinceReferenceDate: 0),
                                                            coordinate: coordinate) },
                            center: coordinate)
    }

    private func stop(_ id: String, _ latitude: Double? = nil, _ longitude: Double = 127.0) -> TimelineStop {
        stop([id], latitude, longitude)
    }

    func testPlaceKeyRoundsToThreeDecimals() {
        XCTAssertEqual(PlaceKey.string(for: Coordinate(latitude: 37.54464, longitude: 127.05587)), "37.545,127.056")
        XCTAssertEqual(PlaceKey.string(for: Coordinate(latitude: -33.8, longitude: 151.2)), "-33.800,151.200")
    }

    func testNoCustomNameByDefault() {
        XCTAssertNil(CustomPlaceNames().name(for: stop("a", 37.5)))
    }

    func testRenameStoresTrimmedName() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5), to: "  우리 카페\n")
        XCTAssertEqual(names.name(for: stop("a", 37.5)), "우리 카페")
    }

    func testRenameWithBlankTextRemovesCustomName() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5), to: "우리 카페")
        names.rename(stop("a", 37.5), to: "   ")
        XCTAssertNil(names.name(for: stop("a", 37.5)))
        XCTAssertTrue(names.entries.isEmpty)
    }

    // MARK: 이름은 그 머문 곳의 사진에 붙는다

    /// 같은 머문 곳에 사진이 많이 더해져 중심이 100m 넘게 움직여도 이름이 유지된다.
    func testNameStaysWhenMorePhotosMoveTheCenterFar() {
        var names = CustomPlaceNames()
        names.rename(stop(["p1", "p2"], 37.5000), to: "우리 집")
        // 같은 사진 2장 + 새 사진 3장. 중심이 약 130m 옮겨졌다.
        XCTAssertEqual(names.name(for: stop(["p1", "p2", "p3", "p4", "p5"], 37.5012), radius: 80), "우리 집")
    }

    func testRenamingAgainUpdatesTheSameEntry() {
        var names = CustomPlaceNames()
        names.rename(stop(["p1", "p2"], 37.5), to: "카페")
        names.rename(stop(["p1", "p2", "p3"], 37.5003), to: "단골 카페")
        XCTAssertEqual(names.entries.count, 1)
        XCTAssertEqual(names.name(for: stop("p3", 37.5003)), "단골 카페")
    }

    // MARK: 가까운 다른 머문 곳은 이름을 물려받는다

    func testAnotherVisitNearbyInheritsTheName() {
        var names = CustomPlaceNames()
        names.rename(stop("monday", 37.5000), to: "회사")
        XCTAssertEqual(names.name(for: stop("tuesday", 37.5005), radius: 200), "회사")
    }

    func testNameIsNotInheritedBeyondRadius() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5), to: "회사")
        // 위도 0.003도 ≈ 333m.
        XCTAssertNil(names.name(for: stop("b", 37.503), radius: 200))
    }

    func testNearestNamedPlaceIsInherited() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5000), to: "카페")
        names.rename(stop("b", 37.5010), to: "서점")
        XCTAssertEqual(names.name(for: stop("c", 37.5003), radius: 200), "카페")
        XCTAssertEqual(names.name(for: stop("d", 37.5007), radius: 200), "서점")
    }

    // MARK: 물려받은 이름을 고쳐도 원래 장소는 그대로

    func testRenamingStopThatInheritedDoesNotRenameTheOriginal() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5000), to: "카페")
        names.rename(stop("b", 37.5005), to: "서점")
        XCTAssertEqual(names.name(for: stop("a", 37.5000)), "카페")
        XCTAssertEqual(names.name(for: stop("b", 37.5005)), "서점")
    }

    /// 물려받은 이름을 지우면 그 머문 곳만 자동 이름으로 돌아가고, 원래 장소의 이름은 남는다.
    func testClearingInheritedNameOnlyAffectsThatStop() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5000), to: "카페")
        names.rename(stop("b", 37.5005), to: "")
        XCTAssertNil(names.name(for: stop("b", 37.5005)))
        XCTAssertEqual(names.name(for: stop("a", 37.5000)), "카페")
    }

    /// "물려받지 않음" 표시는 그 머문 곳만의 것이다. 근처의 또 다른 머문 곳에 이름처럼 퍼지지 않는다.
    func testClearedStopDoesNotPassAnythingOnToItsNeighbours() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5000), to: "카페")
        names.rename(stop("b", 37.5015), to: "")       // a에서 약 167m: 물려받던 이름을 지움
        // c는 b에서 167m, a에서 333m. 물려받을 이름이 없다.
        XCTAssertNil(names.name(for: stop("c", 37.5030)))
    }

    func testClearingNameWhereNothingWasNamedStoresNothing() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5), to: "  ")
        XCTAssertTrue(names.entries.isEmpty)
    }

    // MARK: 위치 없는 머문 곳

    func testStopWithoutLocationIsNamedByItsPhotos() {
        var names = CustomPlaceNames()
        names.rename(stop("a"), to: "집들이")
        XCTAssertEqual(names.name(for: stop("a")), "집들이")
        XCTAssertNil(names.name(for: stop("b")))
        XCTAssertNil(names.name(for: stop("c", 37.5)))
    }

    // MARK: 저장

    func testNamesRoundTripThroughJSON() throws {
        var names = CustomPlaceNames()
        names.rename(stop(["a", "a2"], 37.5), to: "우리 카페")
        names.rename(stop("b"), to: "집들이")
        names.rename(stop("c", 37.5004), to: "")
        let restored = try JSONDecoder().decode(CustomPlaceNames.self, from: JSONEncoder().encode(names))
        XCTAssertEqual(restored, names)
        XCTAssertEqual(restored.name(for: stop("a2", 37.6)), "우리 카페")
    }

    /// 처음 저장 형식("위도,경도" 또는 "photo:id" → 이름)도 읽는다.
    func testReadsOldDictionaryFormat() throws {
        let old = Data(#"{"37.500,127.030":"회사","photo:a":"집들이"}"#.utf8)
        let names = try JSONDecoder().decode(CustomPlaceNames.self, from: old)
        XCTAssertEqual(names.name(for: stop("x", 37.5001, 127.0301)), "회사")
        XCTAssertEqual(names.name(for: stop("a")), "집들이")
    }

    /// 두 번째 저장 형식(좌표 또는 사진 하나 + 이름)도 읽는다.
    func testReadsCoordinateEntryFormat() throws {
        let old = Data(#"[{"coordinate":{"latitude":37.5,"longitude":127.0},"name":"회사"},{"photoID":"a","name":"집들이"}]"#.utf8)
        let names = try JSONDecoder().decode(CustomPlaceNames.self, from: old)
        XCTAssertEqual(names.name(for: stop("x", 37.5001)), "회사")
        XCTAssertEqual(names.name(for: stop("a")), "집들이")
    }

    // MARK: 파일

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    func testStoreSavesAndLoads() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5), to: "우리 카페")
        let store = PlaceNameStore(url: url)
        try store.save(names)
        XCTAssertEqual(store.load(), names)
    }

    func testStoreLoadsEmptyWhenFileIsMissing() {
        XCTAssertEqual(PlaceNameStore(url: temporaryURL()).load(), CustomPlaceNames())
    }

    /// 읽을 수 없는 파일은 지우지 않고 옆에 보관한다. 다음 저장이 덮어써도 원래 내용을 되찾을 수 있다.
    func testStoreKeepsUnreadableFileAside() throws {
        let url = temporaryURL()
        let backup = url.appendingPathExtension("broken")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: backup)
        }
        try Data("[{\"name\": 3}]".utf8).write(to: url)
        let store = PlaceNameStore(url: url)
        XCTAssertEqual(store.load(), CustomPlaceNames())
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "[{\"name\": 3}]")

        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5), to: "새 이름")
        try store.save(names)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "[{\"name\": 3}]")
    }
}
