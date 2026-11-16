import CoreGraphics
import CoreImage
import XCTest
@testable import PhotoTidyCore

final class ImageAnalyzerTests: XCTestCase {
    private func makeImage(_ draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context)
        return context.makeImage()!
    }

    private func checkerboard() -> CGImage {
        makeImage { context in
            for row in 0..<16 {
                for column in 0..<16 {
                    let white = (row + column) % 2 == 0
                    context.setFillColor(gray: white ? 1 : 0, alpha: 1)
                    context.fill(CGRect(x: column * 16, y: row * 16, width: 16, height: 16))
                }
            }
        }
    }

    private func scene(offset: CGFloat = 0) -> CGImage {
        makeImage { context in
            context.setFillColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            context.setFillColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
            context.fillEllipse(in: CGRect(x: 40 + offset, y: 60, width: 100, height: 100))
            context.setFillColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)
            context.fill(CGRect(x: 150 + offset, y: 140, width: 70, height: 50))
        }
    }

    private func blurred(_ image: CGImage) -> CGImage {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: input.extent)
        return CIContext().createCGImage(output, from: input.extent)!
    }

    func testSharpImageScoresHigherThanBlurred() {
        let sharp = checkerboard()
        XCTAssertGreaterThan(ImageAnalyzer.sharpness(sharp), ImageAnalyzer.sharpness(blurred(sharp)))
    }

    func testSimilarImagesAreCloserThanDifferentOnes() throws {
        let base = try ImageAnalyzer.analyze(scene())
        let shifted = try ImageAnalyzer.analyze(scene(offset: 6))
        let other = try ImageAnalyzer.analyze(checkerboard())
        let near = try XCTUnwrap(ImageAnalyzer.distance(base.featurePrint, shifted.featurePrint))
        let far = try XCTUnwrap(ImageAnalyzer.distance(base.featurePrint, other.featurePrint))
        XCTAssertLessThan(near, far)
    }

    func testImageWithoutFaceHasNoFaceQuality() throws {
        XCTAssertNil(try ImageAnalyzer.analyze(checkerboard()).metrics.faceQuality)
    }

    func testSegmentProcessorGroupsIdenticalImagesAndCountsUnreadable() {
        let images: [String: CGImage] = ["a": scene(), "b": scene(), "c": checkerboard()]
        let segment = [photo("a", at: 0), photo("b", at: 1), photo("c", at: 2), photo("d", at: 3)]
        let output = SegmentProcessor.process(segment, threshold: 0.01) { images[$0] }
        XCTAssertEqual(output.groups.map { $0.photos.map(\.item.id) }, [["a", "b"]])
        XCTAssertEqual(output.unreadable, 1)
        XCTAssertFalse(output.groups[0].isSkipped)
    }

    func testSegmentProcessorSkipsSinglePhotoSegment() {
        var loaded = 0
        let output = SegmentProcessor.process([photo("a")]) { _ in
            loaded += 1
            return nil
        }
        XCTAssertTrue(output.groups.isEmpty)
        XCTAssertEqual(output.unreadable, 0)
        XCTAssertEqual(loaded, 0)
    }
}
