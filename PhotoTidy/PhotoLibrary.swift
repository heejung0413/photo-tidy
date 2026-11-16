import Photos
import PhotoTidyCore
import UIKit

/// 사진첩 읽기·삭제. 상태를 갖지 않는다.
final class PhotoLibrary: Sendable {
    var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// 이미지 타입만, 촬영 시각 오름차순. date가 있으면 그 이후 사진만.
    func fetchPhotos(after date: Date?) -> [PhotoItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        if let date {
            options.predicate = NSPredicate(format: "creationDate > %@", date as NSDate)
        }
        var items: [PhotoItem] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            guard let takenAt = asset.creationDate else { return }
            items.append(PhotoItem(id: asset.localIdentifier, takenAt: takenAt,
                                   isFavorite: asset.isFavorite, isEdited: asset.hasAdjustments,
                                   pixelCount: asset.pixelWidth * asset.pixelHeight))
        }
        return items
    }

    /// ids 중 사진첩에 아직 있는 것.
    func existingIDs(of ids: [String]) -> Set<String> {
        var found: Set<String> = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            found.insert(asset.localIdentifier)
        }
        return found
    }

    /// 분석용 이미지(긴 변 약 512px). 네트워크는 쓰지 않고, 원본이 기기에 없으면 미리보기로 받는다.
    func analysisImage(id: String) -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        return requestImage(asset, mode: .highQualityFormat) ?? requestImage(asset, mode: .fastFormat)
    }

    private func requestImage(_ asset: PHAsset, mode: PHImageRequestOptionsDeliveryMode) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = mode
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        var result: CGImage?
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 512, height: 512),
                                              contentMode: .aspectFit, options: options) { image, _ in
            result = image?.cgImage
        }
        return result
    }

    /// 화면 표시용 이미지. 저화질이 먼저 오고 고화질이 뒤따를 수 있다.
    func displayImages(id: String, targetSize: CGSize, allowNetwork: Bool = false) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            // 공유 앨범 사진도 찾을 수 있게 출처를 모두 포함한다.
            let fetchOptions = PHFetchOptions()
            fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: fetchOptions).firstObject else {
                continuation.finish()
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = allowNetwork
            let requestID = PHImageManager.default().requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
            ) { image, info in
                if let image {
                    continuation.yield(image)
                }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }

    /// iOS 삭제 확인 창을 띄운다. 사용자가 취소하면 false.
    func delete(ids: [String]) async -> Bool {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch {
            return false
        }
    }
}
