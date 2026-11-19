import Foundation

/// 앱이 기기에 저장하는 파일의 위치(앱의 Application Support 폴더).
enum AppFiles {
    /// 저장 폴더 안의 name 파일 위치. 폴더가 없으면 만든다.
    static func url(_ name: String) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
}
