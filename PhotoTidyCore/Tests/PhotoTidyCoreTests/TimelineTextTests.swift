import XCTest
@testable import PhotoTidyCore

final class TimelineTextTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let korean = Locale(identifier: "ko_KR")
    private let utc = TimeZone(secondsFromGMT: 0)!

    /// 기준 시각(2001-01-01 00:00 UTC)에서 hour시 minute분.
    private func at(_ hour: Int, _ minute: Int, day: Int = 0) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(day * 86_400 + hour * 3600 + minute * 60))
    }

    private func stop(_ times: [Date]) -> TimelineStop {
        TimelineStop(photos: times.enumerated().map { TimelinePhoto(id: "p\($0)", takenAt: $1, coordinate: nil) },
                     center: nil)
    }

    func testSinglePhotoShowsOneTime() {
        let text = TimelineText.timeRange(stop([at(9, 10)]), locale: english, timeZone: utc)
        XCTAssertTrue(text.hasPrefix("9:10"), text)
        XCTAssertFalse(text.contains("–"), text)
    }

    func testPhotosInSameMinuteShowOneTime() {
        let text = TimelineText.timeRange(stop([at(9, 10), at(9, 10).addingTimeInterval(40)]),
                                          locale: english, timeZone: utc)
        XCTAssertFalse(text.contains("–"), text)
    }

    func testRangeJoinsStartAndEnd() {
        let text = TimelineText.timeRange(stop([at(11, 5), at(11, 12), at(15, 20)]), locale: english, timeZone: utc)
        let parts = text.components(separatedBy: "–")
        XCTAssertEqual(parts.count, 2, text)
        XCTAssertTrue(parts[0].hasPrefix("11:05"), text)
        XCTAssertTrue(parts[1].hasPrefix("3:20"), text)
    }

    func testTimeFollowsLocaleAndTimeZone() {
        let seoul = TimeZone(secondsFromGMT: 9 * 3600)!
        let text = TimelineText.timeRange(stop([at(0, 10)]), locale: korean, timeZone: seoul)
        XCTAssertTrue(text.contains("오전"), text)
        XCTAssertTrue(text.contains("9:10"), text)
    }

    func testPeriodOfOneDayIsSingleDate() {
        let text = TimelineText.period(from: at(0, 0), to: at(0, 0), locale: english, timeZone: utc)
        XCTAssertTrue(text.contains("2001"), text)
        XCTAssertFalse(text.contains("–"), text)
    }

    func testPeriodOfSeveralDaysShowsFirstAndLast() {
        let text = TimelineText.period(from: at(0, 0), to: at(0, 0, day: 400), locale: korean, timeZone: utc)
        let parts = text.components(separatedBy: " – ")
        XCTAssertEqual(parts.count, 2, text)
        XCTAssertTrue(parts[0].contains("2001"), text)
        XCTAssertTrue(parts[1].contains("2002"), text)
    }
}
