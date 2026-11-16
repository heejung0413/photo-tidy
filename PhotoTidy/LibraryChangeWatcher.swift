import Photos

/// 사진첩이 바뀌면(이 앱이 바꾼 것 포함) onChange를 부른다. 어느 스레드에서 불릴지는 정해져 있지 않다.
final class LibraryChangeWatcher: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @Sendable () -> Void

    /// 사진 접근 권한을 받은 뒤에 만들 것.
    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
