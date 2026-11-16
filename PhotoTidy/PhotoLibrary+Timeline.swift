import Photos
import PhotoTidyCore

extension PhotoLibrary {
    /// day가 속한 날(기기 시간대 0시~24시 전)의 사진. 촬영 시각 오름차순.
    func timelinePhotos(on day: Date, calendar: Calendar = .current) -> [TimelinePhoto] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                        start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var photos: [TimelinePhoto] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            guard let takenAt = asset.creationDate else { return }
            let coordinate = asset.location.map {
                Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            }
            photos.append(TimelinePhoto(id: asset.localIdentifier, takenAt: takenAt, coordinate: coordinate))
        }
        return photos
    }

    /// 사진이 있는 날짜(각 날의 0시) 목록, 오름차순.
    func photoDays(calendar: Calendar = .current) -> [Date] {
        var days: Set<Date> = []
        PHAsset.fetchAssets(with: .image, options: nil).enumerateObjects { asset, _, _ in
            if let date = asset.creationDate {
                days.insert(calendar.startOfDay(for: date))
            }
        }
        return days.sorted()
    }
}
