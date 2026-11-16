import CoreLocation
import Foundation
import PhotoTidyCore

/// 좌표를 장소 이름으로 바꾼다(애플 서버에 좌표만 전송). 받은 이름은 기기에 저장한다.
@MainActor
final class PlaceNamer {
    private var cache: [String: String]
    private let url: URL
    private let geocoder = CLGeocoder()

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("place-names.json")
        cache = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) ?? [:]
    }

    /// 실패하면 nil.
    func name(for coordinate: Coordinate) async -> String? {
        let key = String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
        if let cached = cache[key] {
            return cached
        }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first,
              let name = placemark.areasOfInterest?.first ?? placemark.subLocality
                  ?? placemark.locality ?? placemark.name else {
            return nil
        }
        cache[key] = name
        try? JSONEncoder().encode(cache).write(to: url, options: .atomic)
        return name
    }
}
