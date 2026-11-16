import CoreGraphics
import Foundation
import Vision

public struct ImageAnalysis {
    public let featurePrint: VNFeaturePrintObservation
    public let metrics: PhotoMetrics
}

public enum ImageAnalyzerError: Error {
    case noFeaturePrint
}

public enum ImageAnalyzer {
    public static func analyze(_ image: CGImage) throws -> ImageAnalysis {
        let printRequest = VNGenerateImageFeaturePrintRequest()
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([printRequest, faceRequest])
        guard let featurePrint = printRequest.results?.first else {
            throw ImageAnalyzerError.noFeaturePrint
        }
        let qualities = (faceRequest.results ?? []).compactMap { $0.faceCaptureQuality }.map(Double.init)
        let faceQuality = qualities.isEmpty ? nil : qualities.reduce(0, +) / Double(qualities.count)
        return ImageAnalysis(featurePrint: featurePrint,
                             metrics: PhotoMetrics(sharpness: sharpness(image), faceQuality: faceQuality))
    }

    /// 두 지문의 거리(작을수록 비슷). 비교할 수 없으면 nil.
    public static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var value: Float = 0
        do {
            try a.computeDistance(&value, to: b)
            return value
        } catch {
            return nil
        }
    }

    /// 256×256 흑백으로 줄인 뒤 라플라시안 값의 분산을 구한다. 클수록 선명하다.
    public static func sharpness(_ image: CGImage) -> Double {
        let side = 256
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 0 }

        var sum = 0.0
        var sumOfSquares = 0.0
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let i = y * side + x
                let laplacian = Double(4 * Int(pixels[i]) - Int(pixels[i - 1]) - Int(pixels[i + 1])
                    - Int(pixels[i - side]) - Int(pixels[i + side]))
                sum += laplacian
                sumOfSquares += laplacian * laplacian
            }
        }
        let count = Double((side - 2) * (side - 2))
        let mean = sum / count
        return sumOfSquares / count - mean * mean
    }
}
