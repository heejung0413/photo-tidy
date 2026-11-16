import XCTest

/// 시뮬레이터 스모크 테스트. 사진첩에 "같은 사진 2장"이 연달아 들어 있어야 한다(README 참고).
/// 실제로 사진 1장을 삭제하므로 시뮬레이터에서만 돌린다.
final class SmokeTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func shot(_ name: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        print("SHOT: \(url.path)")
    }

    func testAnalyzeAndDeleteDuplicates() {
        app.launch()

        grantAccessIfNeeded()

        let start = app.buttons.matching(NSPredicate(format: "label IN %@", ["분석 시작", "새 사진 분석"])).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        shot("1-home")
        start.tap()

        let summary = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "비슷한 사진 묶음")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 120))
        shot("2-summary")

        app.buttons["묶음 보기"].tap()
        let firstRow = app.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10))
        shot("3-list")
        firstRow.tap()

        let delete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "나머지")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        sleep(2)
        shot("4-detail")
        delete.tap()

        let confirm = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["삭제", "Delete"])).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        shot("5-confirm")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["정리할 묶음이 없어요"].waitForExistence(timeout: 10))
        shot("6-done")
    }

    private func grantAccessIfNeeded() {
        let allow = app.buttons["사진 접근 허용"]
        guard allow.waitForExistence(timeout: 3) else { return }
        allow.tap()
        let full = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["전체 접근 허용", "Allow Full Access"])).firstMatch
        XCTAssertTrue(full.waitForExistence(timeout: 10))
        full.tap()
    }

    /// 샘플 사진(scripts/make-timeline-samples.swift, 2026-11-14)이 사진첩에 있어야 한다.
    func testTimelineShowsStopsForSampleDay() {
        app.launch()
        grantAccessIfNeeded()
        app.tabBars.buttons["타임라인"].tap()

        let previous = app.buttons["이전 날"]
        XCTAssertTrue(previous.waitForExistence(timeout: 20))
        let sampleStop = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "9:10")).firstMatch
        for _ in 0..<10 where !sampleStop.exists {
            if previous.isEnabled {
                previous.tap()
            }
            sleep(1)
        }
        XCTAssertTrue(sampleStop.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2장")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3:20")).firstMatch.exists)
        sleep(5) // 장소 이름과 지도 불러오기
        shot("7-timeline")
    }

    /// 타임라인 사용 흐름을 단계별로 캡처한다. 샘플 사진(2026-11-14)이 사진첩에 있어야 한다.
    func testTimelineWalkthrough() {
        app.launch()
        grantAccessIfNeeded()
        app.tabBars.buttons["타임라인"].tap()

        let previous = app.buttons["이전 날"]
        XCTAssertTrue(previous.waitForExistence(timeout: 20))
        sleep(4)
        shot("t1-open-tab")

        let sampleStop = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "9:10")).firstMatch
        for _ in 0..<10 where !sampleStop.exists {
            if previous.isEnabled {
                previous.tap()
            }
            sleep(1)
        }
        XCTAssertTrue(sampleStop.waitForExistence(timeout: 10))
        sleep(5)
        shot("t2-previous-day")

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2026")).firstMatch.tap()
        let confirm = app.buttons["보기"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        sleep(1)
        shot("t3-pick-date")
        confirm.tap()
        XCTAssertTrue(sampleStop.waitForExistence(timeout: 10))

        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3:20")).firstMatch.tap()
        sleep(4)
        shot("t4-focus-stop")

        let thumbnail = app.buttons.matching(identifier: "사진 크게 보기").firstMatch
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 10))
        thumbnail.tap()
        sleep(2)
        shot("t5-view-photo")
        app.swipeDown(velocity: .fast)
    }

    /// 앨범 전체 타임라인. 앱이 "-sampleAlbum" 인자로 사진첩 전체를 담은 "샘플 앨범"을 만든다.
    func testAlbumTimeline() {
        app.launchArguments = ["-sampleAlbum"]
        app.launch()
        grantAccessIfNeeded()
        app.tabBars.buttons["타임라인"].tap()

        let menu = app.buttons["범위 선택"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        sleep(3)
        menu.tap()
        let album = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "샘플 앨범")).firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 10))
        sleep(1)
        shot("a1-pick-album")
        album.tap()

        XCTAssertTrue(app.staticTexts["샘플 앨범"].waitForExistence(timeout: 10))
        let sampleStop = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "9:10")).firstMatch
        XCTAssertTrue(sampleStop.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["이전 날"].exists)
        sleep(6)
        shot("a2-album-timeline")
        app.swipeUp()
        sleep(2)
        shot("a3-album-scrolled")
    }
}
