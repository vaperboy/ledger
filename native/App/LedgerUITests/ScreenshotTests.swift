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

    func testTour() {
        XCTAssertTrue(app.staticTexts["Net worth"].waitForExistence(timeout: 20) || app.staticTexts["NET WORTH"].waitForExistence(timeout: 5))
        shot("01-home")
        let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Next day")).firstMatch
        if next.exists { next.tap(); next.tap(); shot("02-home-after-two-days") }

        open("Company"); sleep(1); shot("03-company")
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Café' OR label CONTAINS[c] 'Cafe'")).firstMatch
        if first.waitForExistence(timeout: 3) {
            first.tap(); sleep(1); shot("04-company-overview")
            for section in ["Finances", "Operations", "Marketing"] {
                let b = app.buttons[section]
                if b.exists { b.tap(); sleep(1); shot("05-company-" + section.lowercased()) }
            }
            if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        }
        open("Team"); sleep(1); shot("05-team")
        open("Group"); sleep(1); shot("06-group")
        let money = app.buttons["Money"].firstMatch
        if money.exists { money.tap(); sleep(1) }
        shot("06-money")
        for section in ["Bank", "Invest", "Taxes", "Costs"] {
            let b = app.buttons[section]
            if b.exists { b.tap(); sleep(1); shot("06-money-" + section.lowercased()) }
        }
        let more = app.buttons["more-button"].firstMatch
        if more.exists { more.tap(); sleep(1) }
        shot("07-phone")
        for item in ["Settings", "Stats"] {
            let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", item)).firstMatch
            if b.exists {
                b.tap(); sleep(1); shot("08-phone-" + item.lowercased())
                if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
            }
        }
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        open("Projects"); sleep(1); shot("08-projects")
        open("Inbox"); sleep(1); shot("09-inbox")
    }
}
