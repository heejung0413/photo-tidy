import XCTest
@testable import PhotoTidyCore

/// 애플 장소 이름 서비스처럼, 요청이 겹치면 뒤에 온 요청에 답하지 못하는 가짜 서비스.
@MainActor
private final class FakeService {
    private(set) var calls: [Coordinate] = []
    private(set) var overlapped = false
    private var busy = false
    var names: [String: String] = [:]

    func lookup(_ coordinate: Coordinate) async -> String? {
        calls.append(coordinate)
        if busy {
            overlapped = true
            return nil
        }
        busy = true
        try? await Task.sleep(nanoseconds: 20_000_000)
        busy = false
        return names[PlaceKey.string(for: coordinate)]
    }
}

@MainActor
final class PlaceNameLookupTests: XCTestCase {
    private let palace = Coordinate(latitude: 37.5796, longitude: 126.9770)
    private let gangnam = Coordinate(latitude: 37.4979, longitude: 127.0276)
    private let jamsil = Coordinate(latitude: 37.5133, longitude: 127.1001)

    private func service() -> FakeService {
        let service = FakeService()
        service.names = [PlaceKey.string(for: palace): "세종로",
                         PlaceKey.string(for: gangnam): "역삼동",
                         PlaceKey.string(for: jamsil): "잠실동"]
        return service
    }

    func testRequestsMadeAtTheSameTimeAreSentOneByOne() async {
        let service = service()
        let lookup = PlaceNameLookup(cache: [:]) { await service.lookup($0) }

        async let first = lookup.name(for: palace)
        async let second = lookup.name(for: gangnam)
        async let third = lookup.name(for: jamsil)
        let names = await [first, second, third]

        XCTAssertFalse(service.overlapped)
        XCTAssertEqual(names, ["세종로", "역삼동", "잠실동"])
    }

    func testSamePlaceAskedTwiceAtOnceIsLookedUpOnce() async {
        let service = service()
        let lookup = PlaceNameLookup(cache: [:]) { await service.lookup($0) }

        async let first = lookup.name(for: palace)
        async let second = lookup.name(for: palace)
        let names = await [first, second]

        XCTAssertEqual(names, ["세종로", "세종로"])
        XCTAssertEqual(service.calls.count, 1)
    }

    func testCachedNameIsReturnedWithoutAsking() async {
        let service = service()
        let lookup = PlaceNameLookup(cache: [PlaceKey.string(for: palace): "경복궁"]) { await service.lookup($0) }

        let name = await lookup.name(for: palace)

        XCTAssertEqual(name, "경복궁")
        XCTAssertEqual(lookup.cachedName(for: palace), "경복궁")
        XCTAssertTrue(service.calls.isEmpty)
    }

    func testFailedLookupIsNotRememberedSoItCanBeTriedAgain() async {
        let service = FakeService()
        let lookup = PlaceNameLookup(cache: [:]) { await service.lookup($0) }

        let failed = await lookup.name(for: palace)
        XCTAssertNil(failed)
        XCTAssertNil(lookup.cachedName(for: palace))

        service.names = [PlaceKey.string(for: palace): "세종로"]
        let retried = await lookup.name(for: palace)
        XCTAssertEqual(retried, "세종로")
    }

    func testNewNamesAreHandedOverForSaving() async {
        let service = service()
        var saved: [[String: String]] = []
        let lookup = PlaceNameLookup(cache: [:], lookup: { await service.lookup($0) }, onChange: { saved.append($0) })

        _ = await lookup.name(for: palace)
        _ = await lookup.name(for: palace)

        XCTAssertEqual(saved, [[PlaceKey.string(for: palace): "세종로"]])
    }
}
