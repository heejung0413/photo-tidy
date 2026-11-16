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
        XCTAssertTrue(names.names.isEmpty)
    }

    func testNameFollowsPlaceNotPhoto() {
        var names = CustomPlaceNames()
        names.rename(stop("monday", 37.5001), to: "회사")
        // 다른 날 같은 칸(소수 셋째 자리까지 같음)에서 찍은 머문 곳.
        XCTAssertEqual(names.name(for: stop("tuesday", 37.5003)), "회사")
        // 한 칸 넘게 떨어진 곳에는 붙지 않는다.
        XCTAssertNil(names.name(for: stop("far", 37.503)))
    }

    func testStopWithoutLocationIsNamedByItsFirstPhoto() {
        var names = CustomPlaceNames()
        names.rename(stop("a"), to: "집들이")
        XCTAssertEqual(names.name(for: stop("a")), "집들이")
        XCTAssertNil(names.name(for: stop("b")))
        XCTAssertEqual(names.names, ["photo:a": "집들이"])
    }

    func testNamesRoundTripThroughJSON() throws {
        var names = CustomPlaceNames()
        names.rename(stop("a", 37.5), to: "우리 카페")
        let data = try JSONEncoder().encode(names.names)
        let restored = CustomPlaceNames(names: try JSONDecoder().decode([String: String].self, from: data))
        XCTAssertEqual(restored, names)
    }
}
