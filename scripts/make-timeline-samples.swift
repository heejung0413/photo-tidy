// 사용법: swift scripts/make-timeline-samples.swift <출력 폴더>
// 위치(GPS)와 촬영 시각이 든 단색 JPEG 4장을 만든다. 타임라인 확인용.
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
