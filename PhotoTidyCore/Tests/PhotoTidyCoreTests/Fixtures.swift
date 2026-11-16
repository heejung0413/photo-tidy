import Foundation
@testable import PhotoTidyCore

func photo(_ id: String, at t: TimeInterval = 0, favorite: Bool = false,
           edited: Bool = false, pixels: Int = 1000) -> PhotoItem {
    PhotoItem(id: id, takenAt: Date(timeIntervalSinceReferenceDate: t),
              isFavorite: favorite, isEdited: edited, pixelCount: pixels)
}

func stored(_ id: String, at t: TimeInterval = 0, sharpness: Double = 1, face: Double? = nil,
            favorite: Bool = false, edited: Bool = false, pixels: Int = 1000) -> StoredPhoto {
    StoredPhoto(item: photo(id, at: t, favorite: favorite, edited: edited, pixels: pixels),
                metrics: PhotoMetrics(sharpness: sharpness, faceQuality: face))
}
