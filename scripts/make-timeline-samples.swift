// 사용법: swift scripts/make-timeline-samples.swift <출력 폴더>
// 위치(GPS)와 촬영 시각이 든 단색 JPEG 6장(이틀 치)을 만든다. 타임라인 확인용.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Sample {
    let name: String
    let date: String
    let latitude: Double
    let longitude: Double
    let color: (CGFloat, CGFloat, CGFloat)
}

let samples = [
    Sample(name: "t1-seongsu", date: "2026:11:14 09:10:00", latitude: 37.5446, longitude: 127.0559, color: (0.95, 0.55, 0.2)),
    Sample(name: "t2-forest", date: "2026:11:14 11:05:00", latitude: 37.5443, longitude: 127.0374, color: (0.2, 0.7, 0.3)),
    Sample(name: "t3-forest", date: "2026:11:14 11:20:00", latitude: 37.5446, longitude: 127.0378, color: (0.1, 0.55, 0.25)),
    Sample(name: "t4-namsan", date: "2026:11:14 15:20:00", latitude: 37.5512, longitude: 126.9882, color: (0.3, 0.45, 0.9)),
    // 둘째 날: 다른 동네 두 곳. 날짜를 넘길 때와 앨범에서 날짜별 경로를 확인하는 데 쓴다.
    Sample(name: "t5-gangnam", date: "2026:11:15 10:30:00", latitude: 37.4979, longitude: 127.0276, color: (0.85, 0.3, 0.55)),
    Sample(name: "t6-jamsil", date: "2026:11:15 14:40:00", latitude: 37.5133, longitude: 127.1001, color: (0.55, 0.35, 0.8)),
]

guard CommandLine.arguments.count == 2 else {
    print("사용법: swift scripts/make-timeline-samples.swift <출력 폴더>")
    exit(1)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for sample in samples {
    let context = CGContext(data: nil, width: 1200, height: 900, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(red: sample.color.0, green: sample.color.1, blue: sample.color.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
    let image = context.makeImage()!

    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: sample.date],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: sample.date],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: sample.latitude,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: sample.longitude,
            kCGImagePropertyGPSLongitudeRef: "E",
        ],
    ]
    let url = directory.appendingPathComponent("\(sample.name).jpg")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        print("실패: \(url.path)")
        exit(1)
    }
    print(url.path)
}
