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

    /// No unused space: the card ends at most `slack` points under its last control.
    private func checkFit(_ name: String, last: String, slack: CGFloat = 36) {
        let card = app.otherElements["popup-card"].firstMatch
        let end = app.buttons[last].firstMatch
        guard card.waitForExistence(timeout: 3), end.exists else { XCTFail("\(name): card or \(last) not found"); return }
        let gap: CGFloat = card.frame.maxY - end.frame.maxY
        XCTAssertLessThanOrEqual(gap, slack, "\(name): \(Int(gap))pt of unused space under the last control")
        XCTAssertGreaterThanOrEqual(gap, 8, "\(name): the last control touches the card edge")
        print("FIT \(name): card \(Int(card.frame.height))pt, gap under last control \(Int(gap))pt")
    }

    private func open(_ id: String, _ name: String, close: [String], last: String? = nil) {
        let b = app.buttons[id]
        guard b.waitForExistence(timeout: 8) else { shot(name + "-missing"); return }
        b.tap()
        sleep(1)
        shot(name)
        if let l = last { checkFit(name, last: l) }
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
        open("gallery-compact-buy", "01-compact-buy", close: ["confirm-cancel"], last: "confirm-cancel")
        open("gallery-compact-hold", "02-compact-hold", close: ["confirm-cancel"], last: "confirm-cancel")
        open("gallery-medium", "03-medium", close: ["popup-close"], last: "gallery-option-2")
        open("gallery-detail", "04-detail", close: ["popup-close"], last: "gallery-offer")
    }
}
