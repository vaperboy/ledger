import XCTest

/// Walks through the app on a prepared game and keeps a screenshot of every main screen.
/// Run by CI (see .github/workflows/native-ios.yml); the pictures are the evidence of how the screens look.
final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-showcase"]
        app.launch()
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// iPhone has a tab bar; iPad a sidebar.
    func open(_ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.exists { tab.tap(); return }
        let row = app.buttons[name].firstMatch
        if row.exists { row.tap(); return }
        app.staticTexts[name].firstMatch.tap()
    }

    /// Back from a pushed screen: the navigation bar's back button, only when it can really be tapped (on iPad the first
    /// navigation-bar button can be one behind a sheet, which cannot be scrolled to or tapped).
    func goBack() {
        let bars = app.navigationBars
        for i in 0..<bars.count {
            let b = bars.element(boundBy: i).buttons.element(boundBy: 0)
            if b.exists && b.isHittable { b.tap(); return }
        }
    }

    func testTour() {
        XCTAssertTrue(app.staticTexts["Net worth"].firstMatch.waitForExistence(timeout: 20) || app.staticTexts["NET WORTH"].firstMatch.waitForExistence(timeout: 5))
        shot("01-home")
        let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Next day")).firstMatch
        if next.exists { next.tap(); next.tap(); shot("02-home-after-two-days") }

        open("Company"); sleep(1); shot("03-company")
        // Creating a company starts from the company list's plus button.
        let plus = app.buttons["New company"].firstMatch
        if plus.waitForExistence(timeout: 3) { plus.tap(); sleep(1); shot("03-company-new"); goBack() }
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Café' OR label CONTAINS[c] 'Cafe'")).firstMatch
        if first.waitForExistence(timeout: 3) {
            first.tap(); sleep(1); shot("04-company-overview")
            for section in ["Finances", "Operations", "Marketing"] {
                let b = app.buttons[section]
                if b.exists { b.tap(); sleep(1); shot("05-company-" + section.lowercased()) }
            }
            goBack()
        }
        open("Team"); sleep(1); shot("05-team")
        open("Group"); sleep(1); shot("06-group")
        open("Projects"); sleep(1); shot("08-projects")
        open("Inbox"); sleep(1); shot("09-inbox")
    }
}
