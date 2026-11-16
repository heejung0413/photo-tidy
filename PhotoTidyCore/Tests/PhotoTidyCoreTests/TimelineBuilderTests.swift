import XCTest
@testable import PhotoTidyCore

final class TimelineBuilderTests: XCTestCase {
    private func tp(_ id: String, at t: TimeInterval, _ latitude: Double? = nil) -> TimelinePhoto {
        TimelinePhoto(id: id, takenAt: Date(timeIntervalSinceReferenceDate: t),
                      coordinate: latitude.map { Coordinate(latitude: $0, longitude: 127.0) })
    }

    private func ids(_ stops: [TimelineStop]) -> [[String]] {
        stops.map { $0.photos.map(\.id) }
    }

    func testDistanceIsAbout111MetersPerThousandthDegreeOfLatitude() {
        let meters = TimelineBuilder.distance(Coordinate(latitude: 37.0, longitude: 127.0),
                                              Coordinate(latitude: 37.001, longitude: 127.0))
        XCTAssertEqual(meters, 111.2, accuracy: 0.5)
    }

    func testEmptyInputGivesNoStops() {
        XCTAssertTrue(TimelineBuilder.stops([]).isEmpty)
    }

    func testPhotosWithinRadiusBecomeOneStop() {
        let stops = TimelineBuilder.stops([tp("a", at: 0, 37.0), tp("b", at: 60, 37.001)], radius: 200)
        XCTAssertEqual(ids(stops), [["a", "b"]])
        XCTAssertEqual(stops[0].center?.latitude ?? 0, 37.0005, accuracy: 0.00001)
        XCTAssertEqual(stops[0].start, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(stops[0].end, Date(timeIntervalSinceReferenceDate: 60))
    }

    func testPhotoOutsideRadiusStartsNewStop() {
        let stops = TimelineBuilder.stops([tp("a", at: 0, 37.0), tp("b", at: 60, 37.01)], radius: 200)
        XCTAssertEqual(ids(stops), [["a"], ["b"]])
    }

    func testReturningToSamePlaceIsSeparateStop() {
        let stops = TimelineBuilder.stops([tp("a", at: 0, 37.0), tp("b", at: 60, 37.01), tp("c", at: 120, 37.0)],
                                          radius: 200)
        XCTAssertEqual(ids(stops), [["a"], ["b"], ["c"]])
    }

    func testPhotoWithoutLocationJoinsCurrentStop() {
        let stops = TimelineBuilder.stops([tp("a", at: 0, 37.0), tp("b", at: 60), tp("c", at: 120, 37.01)],
                                          radius: 200)
        XCTAssertEqual(ids(stops), [["a", "b"], ["c"]])
    }

    func testLeadingPhotosWithoutLocationJoinFirstLocatedStop() {
        let stops = TimelineBuilder.stops([tp("a", at: 0), tp("b", at: 60, 37.0)], radius: 200)
        XCTAssertEqual(ids(stops), [["a", "b"]])
        XCTAssertEqual(stops[0].center?.latitude, 37.0)
    }

    func testAllPhotosWithoutLocationBecomeOneStopWithoutCenter() {
        let stops = TimelineBuilder.stops([tp("a", at: 0), tp("b", at: 60)], radius: 200)
        XCTAssertEqual(ids(stops), [["a", "b"]])
        XCTAssertNil(stops[0].center)
    }

    func testInputIsSortedByTime() {
        let stops = TimelineBuilder.stops([tp("b", at: 60, 37.0), tp("a", at: 0, 37.0)], radius: 200)
        XCTAssertEqual(ids(stops), [["a", "b"]])
    }

    // MARK: 여러 날

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDaysOfEmptyInputIsEmpty() {
        XCTAssertTrue(TimelineBuilder.days([], calendar: utc).isEmpty)
    }

    func testDaysSplitsSamePlaceByDate() {
        let days = TimelineBuilder.days([tp("a", at: 0, 37.0), tp("b", at: 86_399, 37.0), tp("c", at: 86_400, 37.0)],
                                        calendar: utc, radius: 200)
        XCTAssertEqual(days.map { ids($0.stops) }, [[["a", "b"]], [["c"]]])
        XCTAssertEqual(days.map(\.day), [Date(timeIntervalSinceReferenceDate: 0),
                                         Date(timeIntervalSinceReferenceDate: 86_400)])
    }

    func testDaysAreSortedAndKeepStopsWithinEachDay() {
        let days = TimelineBuilder.days([tp("d", at: 90_000, 37.0), tp("b", at: 60, 37.01), tp("a", at: 0, 37.0)],
                                        calendar: utc, radius: 200)
        XCTAssertEqual(days.map { ids($0.stops) }, [[["a"], ["b"]], [["d"]]])
    }

    func testDaysFollowCalendarTimeZone() {
        var seoul = Calendar(identifier: .gregorian)
        seoul.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        // 기준 시각 0은 서울 09:00. 15시간 뒤가 서울의 다음 날 0시다.
        let photos = [tp("a", at: 0), tp("b", at: 53_999), tp("c", at: 54_000)]
        XCTAssertEqual(TimelineBuilder.days(photos, calendar: seoul).map { ids($0.stops) }, [[["a", "b"]], [["c"]]])
        XCTAssertEqual(TimelineBuilder.days(photos, calendar: utc).count, 1)
    }
}
