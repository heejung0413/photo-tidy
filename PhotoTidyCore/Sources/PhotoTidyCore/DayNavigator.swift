import Foundation

/// 사진이 있는 날짜 목록(각 날의 0시, 오름차순) 안에서 이동할 날을 고른다.
public enum DayNavigator {
    public static func previous(before day: Date, in days: [Date]) -> Date? {
        days.last { $0 < day }
    }

    public static func next(after day: Date, in days: [Date]) -> Date? {
        days.first { $0 > day }
    }

    /// date가 속한 날과 가장 가까운 날. 거리가 같으면 앞선 날.
    public static func nearest(to date: Date, in days: [Date], calendar: Calendar = .current) -> Date? {
        let target = calendar.startOfDay(for: date)
        return days.min { abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target)) }
    }
}
