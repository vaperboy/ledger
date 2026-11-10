import XCTest

class TourCase: XCTestCase {
    var app: XCUIApplication!
    var extraLaunchArguments: [String] { [] }
    private var lastShot: Data?

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-showcase"] + extraLaunchArguments
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

    @discardableResult
    func waitForHome(_ seconds: TimeInterval = 20) -> Bool {
        let found = app.staticTexts["Net worth"].firstMatch.waitForExistence(timeout: seconds) || app.staticTexts["NET WORTH"].firstMatch.waitForExistence(timeout: 2)
        let later = app.buttons["ambition-later"].firstMatch
        if later.waitForExistence(timeout: 2) { later.tap(); sleep(1) }
        return found
    }
}
