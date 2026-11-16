import XCTest
@testable import PhotoTidyCore

final class DayNavigatorTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ n: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(n) * 86_400)
    }

    func testPreviousAndNextSkipDaysWithoutPhotos() {
        let days = [day(1), day(4), day(9)]
        XCTAssertEqual(DayNavigator.previous(before: day(4), in: days), day(1))
        XCTAssertEqual(DayNavigator.next(after: day(4), in: days), day(9))
        // 건너뛸 수 있는 날이 여럿이어도 바로 옆 날을 고른다.
        XCTAssertEqual(DayNavigator.previous(before: day(9), in: days), day(4))
        XCTAssertEqual(DayNavigator.next(after: day(1), in: days), day(4))
    }

    func testNoPreviousBeforeFirstAndNoNextAfterLast() {
        let days = [day(1), day(4)]
        XCTAssertNil(DayNavigator.previous(before: day(1), in: days))
        XCTAssertNil(DayNavigator.next(after: day(4), in: days))
        XCTAssertNil(DayNavigator.previous(before: day(1), in: []))
    }

    func testNearestPicksClosestDayWithPhotos() {
        let days = [day(1), day(4), day(9)]
        XCTAssertEqual(DayNavigator.nearest(to: day(5), in: days, calendar: utc), day(4))
        XCTAssertEqual(DayNavigator.nearest(to: day(8), in: days, calendar: utc), day(9))
        XCTAssertEqual(DayNavigator.nearest(to: day(100), in: days, calendar: utc), day(9))
    }

    func testNearestUsesTheDayTheMomentBelongsTo() {
        // 4일째 밤 11시는 5일째 0시에 더 가깝지만, 4일째에 속하므로 4일을 고른다.
        let lateNight = day(4).addingTimeInterval(23 * 3600)
        XCTAssertEqual(DayNavigator.nearest(to: lateNight, in: [day(4), day(5)], calendar: utc), day(4))
    }

    func testNearestTieGoesToEarlierDay() {
        XCTAssertEqual(DayNavigator.nearest(to: day(3), in: [day(2), day(4)], calendar: utc), day(2))
    }

    func testNearestOfNoDaysIsNil() {
        XCTAssertNil(DayNavigator.nearest(to: day(3), in: [], calendar: utc))
    }
}
