import XCTest
@testable import PhotoTidyCore

final class BestShotPickerTests: XCTestCase {
    func testEmptyReturnsNil() {
        XCTAssertNil(BestShotPicker.pick([]))
    }

    func testSharpestWinsWhenNoFaces() {
        let picked = BestShotPicker.pick([stored("a", sharpness: 3), stored("b", sharpness: 9), stored("c", sharpness: 5)])
        XCTAssertEqual(picked, "b")
    }

    func testFavoriteBeatsSharper() {
        let picked = BestShotPicker.pick([stored("a", sharpness: 9), stored("b", sharpness: 1, favorite: true)])
        XCTAssertEqual(picked, "b")
    }

    func testFaceQualityCountsWhenEveryPhotoHasFace() {
        // a: 1.0*0.5 + 0.1*0.4 = 0.54, b: 0.8*0.5 + 0.9*0.4 = 0.76, c: 0 + 0.5*0.4 = 0.2
        let picked = BestShotPicker.pick([stored("a", sharpness: 10, face: 0.1),
                                          stored("b", sharpness: 8, face: 0.9),
                                          stored("c", sharpness: 0, face: 0.5)])
        XCTAssertEqual(picked, "b")
    }

    func testFaceIgnoredWhenAnyPhotoHasNoFace() {
        let picked = BestShotPicker.pick([stored("a", sharpness: 10, face: 0.1),
                                          stored("b", sharpness: 8, face: 0.9),
                                          stored("c", sharpness: 0, face: nil)])
        XCTAssertEqual(picked, "a")
    }

    func testEditedBreaksEqualSharpness() {
        let picked = BestShotPicker.pick([stored("a", sharpness: 5), stored("b", sharpness: 5, edited: true)])
        XCTAssertEqual(picked, "b")
    }

    func testTieGoesToMorePixelsThenLater() {
        XCTAssertEqual(BestShotPicker.pick([stored("a", pixels: 2000), stored("b", pixels: 1000)]), "a")
        XCTAssertEqual(BestShotPicker.pick([stored("a", at: 0), stored("b", at: 5)]), "b")
    }
}
