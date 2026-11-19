import Photos
import PhotoTidyCore

struct PhotoAlbum: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// 앨범 안 사진 수(동영상 제외).
    let count: Int
    let isShared: Bool
}

extension PhotoLibrary {
    private static var albumPhotoOptions: PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return options
    }

    /// 사진이 1장 이상 든 앨범. 공유 앨범이 먼저, 그다음 내가 만든 앨범.
    func albums() -> [PhotoAlbum] {
        var result: [PhotoAlbum] = []
        for (subtype, isShared) in [(PHAssetCollectionSubtype.albumCloudShared, true), (.albumRegular, false)] {
            PHAssetCollection.fetchAssetCollections(with: .album, subtype: subtype, options: nil)
                .enumerateObjects { collection, _, _ in
                    let count = PHAsset.fetchAssets(in: collection, options: Self.albumPhotoOptions).count
                    guard count > 0 else { return }
                    result.append(PhotoAlbum(id: collection.localIdentifier,
                                             title: collection.localizedTitle ?? "이름 없는 앨범",
                                             count: count, isShared: isShared))
                }
        }
        return result
    }

    /// 앨범 안 사진 전체. 촬영 시각 오름차순.
    func timelinePhotos(inAlbum id: String) -> [TimelinePhoto] {
        guard let collection = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [id], options: nil).firstObject else { return [] }
        return Self.timelinePhotos(PHAsset.fetchAssets(in: collection, options: Self.albumPhotoOptions))
    }

    #if DEBUG
    /// 시뮬레이터 확인용: 사진첩의 모든 사진을 담은 일반 앨범을 만든다(이미 있으면 그대로 둔다).
    func makeSampleAlbumIfNeeded(title: String = "샘플 앨범") async {
        guard regularAlbum(titled: title) == nil else { return }
        let assets = PHAsset.fetchAssets(with: .image, options: nil)
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title).addAssets(assets)
        }
    }

    /// 시뮬레이터 확인용: 앱이 켜져 있는 동안 앨범 내용이 바뀌는 상황을 만든다.
    /// 사진첩에는 있지만 샘플 앨범에는 없는 사진을 모두 앨범에 넣는다.
    func growSampleAlbum(title: String = "샘플 앨범") async {
        guard let album = regularAlbum(titled: title) else { return }
        var inAlbum: Set<String> = []
        PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
            inAlbum.insert(asset.localIdentifier)
        }
        var missing: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: nil).enumerateObjects { asset, _, _ in
            if !inAlbum.contains(asset.localIdentifier) {
                missing.append(asset)
            }
        }
        guard !missing.isEmpty else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets(missing as NSArray)
        }
    }

    /// 내가 만든 앨범 중 이름이 title인 첫 앨범.
    private func regularAlbum(titled title: String) -> PHAssetCollection? {
        var found: PHAssetCollection?
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { collection, _, stop in
                if collection.localizedTitle == title {
                    found = collection
                    stop.pointee = true
                }
            }
        return found
    }
    #endif
}
