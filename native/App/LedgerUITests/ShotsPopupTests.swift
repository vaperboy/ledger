import XCTest

/// Screenshots of the three popup categories (compact, medium, detail) from the popup gallery (`-popupGallery`), for review.
final class ShotsPopupTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-popupGallery"]
        app.launch()
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "Popup-" + name
        a.lifetime = .keepAlways
        add(a)
    }

    private func open(_ id: String, _ name: String, close: [String]) {
        let b = app.buttons[id]
        guard b.waitForExistence(timeout: 8) else { shot(name + "-missing"); return }
        b.tap()
        sleep(1)
        shot(name)
        for c in close {
            let e = app.buttons[c]
            if e.waitForExistence(timeout: 2) { e.tap(); sleep(1); return }
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        sleep(1)
    }

    func testShots() {
        sleep(2)
        shot("00-gallery")
        open("gallery-compact-buy", "01-compact-buy", close: ["confirm-cancel"])
        open("gallery-compact-hold", "02-compact-hold", close: ["confirm-cancel"])
        open("gallery-medium", "03-medium", close: ["popup-close"])
        open("gallery-detail", "04-detail", close: ["popup-close"])
    }
}
