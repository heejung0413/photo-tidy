import Foundation

public enum PlaceKey {
    /// 좌표를 소수 셋째 자리(약 100m 칸)로 반올림한 글자. 장소 이름 저장 키로 쓴다.
    public static func string(for coordinate: Coordinate) -> String {
        String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
    }
}

/// 사용자가 직접 붙인 장소 이름.
public struct CustomPlaceNames: Equatable, Sendable {
    /// 키 → 이름. 이 모양 그대로 파일에 저장한다.
    public private(set) var names: [String: String]

    public init(names: [String: String] = [:]) {
        self.names = names
    }

    /// 위치가 있으면 좌표 칸으로 묶어 같은 곳에 다시 가도 이름이 따라온다.
    /// 위치가 없으면 그 머문 곳(첫 사진)에만 붙는다.
    public static func key(for stop: TimelineStop) -> String {
        if let center = stop.center {
            return PlaceKey.string(for: center)
        }
        return "photo:\(stop.id)"
    }

    public func name(for stop: TimelineStop) -> String? {
        names[Self.key(for: stop)]
    }

    /// 앞뒤 공백을 뗀 이름을 저장한다. 빈 글자면 직접 붙인 이름을 지운다.
    public mutating func rename(_ stop: TimelineStop, to text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        names[Self.key(for: stop)] = name.isEmpty ? nil : name
    }
}
