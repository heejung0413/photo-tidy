import Foundation

/// 타임라인 화면과 공유 이미지에 같이 쓰는 글자.
public enum TimelineText {
    /// "오전 9:10" 또는 "오전 9:10–오전 11:20". 시작과 끝 표시가 같으면 하나만 적는다.
    public static func timeRange(_ stop: TimelineStop, locale: Locale = .autoupdatingCurrent,
                                 timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        let start = stop.start.formatted(style)
        let end = stop.end.formatted(style)
        return start == end ? start : "\(start)–\(end)"
    }

    /// 앨범 기간. 하루뿐이면 날짜 하나, 아니면 "첫날 – 마지막 날".
    public static func period(from first: Date, to last: Date, locale: Locale = .autoupdatingCurrent,
                              timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle.dateTime.year().month().day().locale(locale)
        style.timeZone = timeZone
        return first == last ? first.formatted(style) : "\(first.formatted(style)) – \(last.formatted(style))"
    }
}
