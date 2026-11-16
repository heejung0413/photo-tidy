import XCTest
@testable import PhotoTidyCore

final class PlaceNamesTests: XCTestCase {
    private func stop(_ id: String, _ latitude: Double? = nil, _ longitude: Double = 127.0) -> TimelineStop {
        let coordinate = latitude.map { Coordinate(latitude: $0, longitude: longitude) }
        return TimelineStop(photos: [TimelinePhoto(id: id, takenAt: Date(timeIntervalSinceReferenceDate: 0),
                                                   coordinate: coordinate)],
                            center: coordinate)
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

    /// 사진이 더해져 머문 곳 중심이 조금 움직여도(좌표 칸의 경계를 넘어도) 이름이 유지된다.
    func testNameSurvivesSmallShiftOfCenter() {
        var names = CustomPlaceNames()
        names.rename(stop("monday", 37.5004, 127.0296), to: "우리 집")
        // 약 30m 옆. 소수 셋째 자리로 반올림하면 다른 칸(37.501, 127.029)이다.
        XCTAssertEqual(names.name(for: stop("tuesday", 37.5006, 127.0294)), "우리 집")
    }

    func testNameDoesNotReachBeyondRadius() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5), to: "회사")
        // 위도 0.001도 ≈ 111m.
        XCTAssertNil(names.name(for: stop("b", 37.501)))
    }

    func testNearestNamedPlaceWins() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5000), to: "카페")
        names.rename(stop("b", 37.5010), to: "서점")
        XCTAssertEqual(names.name(for: stop("c", 37.5003)), "카페")
        XCTAssertEqual(names.name(for: stop("d", 37.5007)), "서점")
    }

    func testRenamingNearbyStopUpdatesExistingEntryInsteadOfAddingAnother() {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5000), to: "카페")
        names.rename(stop("b", 37.5002), to: "단골 카페")
        XCTAssertEqual(names.entries.count, 1)
        XCTAssertEqual(names.name(for: stop("a", 37.5000)), "단골 카페")
    }

    func testStopWithoutLocationIsNamedByItsFirstPhoto() {
        var names = CustomPlaceNames()
        names.rename(stop("a"), to: "집들이")
        XCTAssertEqual(names.name(for: stop("a")), "집들이")
        XCTAssertNil(names.name(for: stop("b")))
        XCTAssertNil(names.name(for: stop("c", 37.5)))
    }

    func testNamesRoundTripThroughJSON() throws {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5), to: "우리 카페")
        names.rename(stop("b"), to: "집들이")
        let restored = try JSONDecoder().decode(CustomPlaceNames.self, from: JSONEncoder().encode(names))
        XCTAssertEqual(restored, names)
    }

    /// 예전 저장 형식("위도,경도" 또는 "photo:id" → 이름)도 읽는다.
    func testReadsOldDictionaryFormat() throws {
        let old = Data(#"{"37.500,127.030":"회사","photo:a":"집들이"}"#.utf8)
        let names = try JSONDecoder().decode(CustomPlaceNames.self, from: old)
        XCTAssertEqual(names.name(for: stop("x", 37.5001, 127.0301)), "회사")
        XCTAssertEqual(names.name(for: stop("a")), "집들이")
    }
}
