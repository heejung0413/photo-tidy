import CoreLocation
import Foundation
import PhotoTidyCore

/// 좌표를 장소 이름으로 바꾼다(애플 서버에 좌표만 전송). 받은 이름은 기기에 저장한다.
/// 요청을 한 번에 하나씩 보내고 이름을 기억하는 일은 `PlaceNameLookup`이 한다.
@MainActor
final class PlaceNamer {
    private let lookup: PlaceNameLookup

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("place-names.json")
        let saved = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) ?? [:]
        let geocoder = CLGeocoder()
        lookup = PlaceNameLookup(cache: saved, lookup: { coordinate in
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
            return placemark.areasOfInterest?.first ?? placemark.subLocality
                ?? placemark.locality ?? placemark.name
        }, onChange: { names in
            try? JSONEncoder().encode(names).write(to: url, options: .atomic)
        })
    }

    /// 이미 받아 둔 이름. 서버에 묻지 않는다.
    func cachedName(for coordinate: Coordinate) -> String? {
        lookup.cachedName(for: coordinate)
    }

    /// 실패하면 nil.
    func name(for coordinate: Coordinate) async -> String? {
        await lookup.name(for: coordinate)
    }
}
