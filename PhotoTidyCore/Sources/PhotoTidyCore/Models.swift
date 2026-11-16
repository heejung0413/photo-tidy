import Foundation

public struct PhotoItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let takenAt: Date
    public let isFavorite: Bool
    public let isEdited: Bool
    public let pixelCount: Int

    public init(id: String, takenAt: Date, isFavorite: Bool, isEdited: Bool, pixelCount: Int) {
        self.id = id
        self.takenAt = takenAt
        self.isFavorite = isFavorite
        self.isEdited = isEdited
        self.pixelCount = pixelCount
    }
}

public struct PhotoMetrics: Hashable, Codable, Sendable {
    public let sharpness: Double
    public let faceQuality: Double?

    public init(sharpness: Double, faceQuality: Double?) {
        self.sharpness = sharpness
        self.faceQuality = faceQuality
    }
}

public struct StoredPhoto: Hashable, Codable, Sendable {
    public let item: PhotoItem
    public let metrics: PhotoMetrics

    public init(item: PhotoItem, metrics: PhotoMetrics) {
        self.item = item
        self.metrics = metrics
    }
}

/// 사진이 항상 2장 이상이고 촬영 시각순으로 정렬돼 있다.
public struct StoredGroup: Identifiable, Hashable, Codable, Sendable {
    public var photos: [StoredPhoto]
    public var recommendedID: String
    public var isSkipped: Bool

    public var id: String { photos[0].item.id }

    public init(photos: [StoredPhoto], recommendedID: String, isSkipped: Bool) {
        self.photos = photos
        self.recommendedID = recommendedID
        self.isSkipped = isSkipped
    }
}
