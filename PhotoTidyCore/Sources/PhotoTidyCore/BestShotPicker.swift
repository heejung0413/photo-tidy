import Foundation

public enum BestShotPicker {
    /// 추천 사진의 id. 즐겨찾기가 있으면 그중에서만 고른다.
    public static func pick(_ photos: [StoredPhoto]) -> String? {
        let favorites = photos.filter { $0.item.isFavorite }
        let pool = favorites.isEmpty ? photos : favorites
        guard let lo = pool.map(\.metrics.sharpness).min(),
              let hi = pool.map(\.metrics.sharpness).max() else { return nil }
        let useFaces = pool.allSatisfy { $0.metrics.faceQuality != nil }

        func score(_ photo: StoredPhoto) -> Double {
            let sharp = hi > lo ? (photo.metrics.sharpness - lo) / (hi - lo) : 0
            let edited = photo.item.isEdited ? 1.0 : 0.0
            if useFaces, let face = photo.metrics.faceQuality {
                return sharp * 0.5 + face * 0.4 + edited * 0.1
            }
            return sharp * 0.9 + edited * 0.1
        }

        return pool.max { a, b in
            let (sa, sb) = (score(a), score(b))
            if sa != sb { return sa < sb }
            if a.item.pixelCount != b.item.pixelCount { return a.item.pixelCount < b.item.pixelCount }
            return a.item.takenAt < b.item.takenAt
        }?.item.id
    }
}
