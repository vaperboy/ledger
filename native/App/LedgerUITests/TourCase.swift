import XCTest

/// Shared base of the UI tours: launches the showcase game and keeps screenshots, skipping a picture identical to the previous one
/// (a scroll or tap that changed nothing) and recording a "note-" attachment instead, so the tour never fails on a missing control.
class TourCase: XCTestCase {
    var app: XCUIApplication!
    private var lastShot: Data?

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-showcase"]
        app.launch()
    }

    func note(_ text: String) {
        let a = XCTAttachment(string: text)
        a.name = "note-" + String(text.prefix(40)).lowercased().filter { $0.isLetter || $0.isNumber }
        a.lifetime = .keepAlways
        add(a)
    }

    func shot(_ name: String) {
        let s = app.screenshot()
        let data = s.pngRepresentation
        if let last = lastShot, last == data { note("skipped \(name): same picture as the previous step"); return }
        lastShot = data
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Waits for the Home summary; on a slow runner this is the only long wait of a test.
    @discardableResult
    func waitForHome(_ seconds: TimeInterval = 20) -> Bool {
        app.staticTexts["Net worth"].firstMatch.waitForExistence(timeout: seconds) || app.staticTexts["NET WORTH"].firstMatch.waitForExistence(timeout: 2)
    }
}
