import Foundation

/// 좌표의 장소 이름을 받아 기억해 둔다. 실제로 이름을 받아 오는 일(lookup)은 바깥에서 넣는다.
@MainActor
public final class PlaceNameLookup {
    private var cache: [String: String]
    private let lookup: (Coordinate) async -> String?
    private let onChange: ([String: String]) -> Void
    /// 줄의 맨 끝 요청.
    private var last: Task<Void, Never>?

    /// onChange: 새 이름을 받을 때마다 기억한 이름 전체를 넘긴다(저장용).
    public init(cache: [String: String],
                lookup: @escaping (Coordinate) async -> String?,
                onChange: @escaping ([String: String]) -> Void = { _ in }) {
        self.cache = cache
        self.lookup = lookup
        self.onChange = onChange
    }

    /// 이미 받아 둔 이름. 서비스에 묻지 않는다.
    public func cachedName(for coordinate: Coordinate) -> String? {
        cache[PlaceKey.string(for: coordinate)]
    }

    /// 실패하면 nil. 실패는 기억하지 않으므로 다음에 다시 묻는다.
    public func name(for coordinate: Coordinate) async -> String? {
        let key = PlaceKey.string(for: coordinate)
        if let cached = cache[key] {
            return cached
        }
        // 서비스는 요청이 겹치면 답하지 못한다. 앞 요청이 끝난 뒤에 묻도록 한 줄로 세운다.
        let previous = last
        let request = Task { () -> String? in
            await previous?.value
            // 줄 서 있는 동안 앞 요청이 같은 곳의 이름을 받았을 수 있다.
            if let cached = cache[key] {
                return cached
            }
            guard let name = await lookup(coordinate) else { return nil }
            cache[key] = name
            onChange(cache)
            return name
        }
        last = Task { _ = await request.value }
        return await request.value
    }
}
