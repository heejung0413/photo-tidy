import XCTest
@testable import PhotoTidyCore

final class ShareOutlineTests: XCTestCase {
    private func stop(_ id: String, photos: Int = 1, _ latitude: Double? = 37.0) -> TimelineStop {
        let coordinate = latitude.map { Coordinate(latitude: $0, longitude: 127.0) }
        let items = (0..<photos).map {
            TimelinePhoto(id: $0 == 0 ? id : "\(id)-\($0)", takenAt: Date(timeIntervalSinceReferenceDate: 0),
                          coordinate: coordinate)
        }
        return TimelineStop(photos: items, center: coordinate)
    }

    private func day(_ n: Int, _ stops: [TimelineStop]) -> TimelineDay {
        TimelineDay(day: Date(timeIntervalSinceReferenceDate: TimeInterval(n) * 86_400), stops: stops)
    }

    private func outline(_ days: [TimelineDay], maxStops: Int = 40, thumbnails: Int = 4) -> ShareOutline {
        ShareOutline(days: days, maxStops: maxStops, thumbnailsPerStop: thumbnails) { stop in "이름-\(stop.id)" }
    }

    func testNumbersContinueAcrossDays() {
        let result = outline([day(0, [stop("a"), stop("b")]), day(1, [stop("c")])])
        XCTAssertEqual(result.sections.map { $0.stops.map(\.number) }, [[1, 2], [3]])
        XCTAssertEqual(result.sections.map(\.day), [day(0, []).day, day(1, []).day])
        XCTAssertEqual(result.hiddenStops, 0)
    }

    func testStopsBeyondLimitAreCountedAsHidden() {
        let result = outline([day(0, [stop("a"), stop("b")]), day(1, [stop("c"), stop("d")]), day(2, [stop("e")])],
                             maxStops: 3)
        XCTAssertEqual(result.sections.map { $0.stops.map(\.id) }, [["a", "b"], ["c"]])
        XCTAssertEqual(result.hiddenStops, 2)
    }

    func testThumbnailsAreLimitedAndRestIsCounted() {
        let result = outline([day(0, [stop("a", photos: 6), stop("b", photos: 2)])], thumbnails: 4)
        let stops = result.sections[0].stops
        XCTAssertEqual(stops[0].thumbnailIDs, ["a", "a-1", "a-2", "a-3"])
        XCTAssertEqual(stops[0].moreCount, 2)
        XCTAssertEqual(stops[1].thumbnailIDs, ["b", "b-1"])
        XCTAssertEqual(stops[1].moreCount, 0)
    }

    func testPhotoCountIncludesHiddenStops() {
        let result = outline([day(0, [stop("a", photos: 3), stop("b", photos: 5)])], maxStops: 1)
        XCTAssertEqual(result.photoCount, 8)
    }

    func testRoutesAreSeparatePerDayAndSkipStopsWithoutLocation() {
        let result = outline([day(0, [stop("a", 37.0), stop("b", nil), stop("c", 37.1)]), day(1, [stop("d", 37.2)])])
        XCTAssertEqual(result.routes.map { $0.map(\.number) }, [[1, 3], [4]])
        XCTAssertEqual(result.routes[0].map(\.coordinate.latitude), [37.0, 37.1])
    }

    /// 제목은 만들 때 한 번만 묻는다. 그 뒤 화면 상태가 바뀌어도 내용이 섞이지 않는다.
    func testTitlesAreCapturedWhenOutlineIsMade() {
        var calls: [String] = []
        var prefix = "처음"
        let result = ShareOutline(days: [day(0, [stop("a"), stop("b")])], maxStops: 40, thumbnailsPerStop: 4) { stop in
            calls.append(stop.id)
            return "\(prefix)-\(stop.id)"
        }
        prefix = "나중"
        XCTAssertEqual(calls, ["a", "b"])
        XCTAssertEqual(result.sections[0].stops.map(\.title), ["처음-a", "처음-b"])
    }

    func testEmptyDaysGiveEmptyOutline() {
        let result = outline([])
        XCTAssertTrue(result.sections.isEmpty)
        XCTAssertTrue(result.routes.isEmpty)
        XCTAssertEqual(result.photoCount, 0)
    }
}
