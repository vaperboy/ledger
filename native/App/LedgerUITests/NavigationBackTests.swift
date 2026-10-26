import XCTest

/// Back-navigation (roadmap D1): a company opened from Home, Projects or Inbox must return to that screen on Back, not to the
/// Company list. Run by CI with the screenshot tests. An entry point that the prepared game does not have (the showcase game has no
/// project company) is reported as skipped, never as a pass.
final class NavigationBackTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-showcase"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Net worth"].firstMatch.waitForExistence(timeout: 20) || app.staticTexts["NET WORTH"].firstMatch.waitForExistence(timeout: 5))
    }

    private func open(_ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.exists { tab.tap(); return }
        let row = app.buttons[name].firstMatch
        if row.exists { row.tap(); return }
        app.staticTexts[name].firstMatch.tap()
    }

    /// The navigation bar's back button, when it can really be tapped.
    /// `title` is the screen being returned to: the back button carries its name (on iPad the first bar button can be the sidebar toggle).
    @discardableResult private func tapBack(to title: String) -> Bool {
        let named = app.navigationBars.buttons[title].firstMatch
        if named.exists && named.isHittable { named.tap(); return true }
        let generic = app.navigationBars.buttons["BackButton"].firstMatch
        if generic.exists && generic.isHittable { generic.tap(); return true }
        let bars = app.navigationBars
        for i in 0..<bars.count {
            let b = bars.element(boundBy: i).buttons.element(boundBy: 0)
            if b.exists && b.isHittable { b.tap(); return true }
        }
        return false
    }

    /// A pushed company shows the section tabs of a company.
    private func assertCompanyOpen(_ from: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["Operations"].waitForExistence(timeout: 5) || app.buttons["Finances"].waitForExistence(timeout: 2),
                      "a company should be open after the link from \(from)", file: file, line: line)
    }

    func testBackFromHomeSuggestionReturnsToHome() throws {
        open("Company")
        let link = app.buttons["suggestion-open-company"].firstMatch
        guard link.waitForExistence(timeout: 3) else { throw XCTSkip("no Home suggestion opens a company in the showcase game") }
        link.tap()
        assertCompanyOpen("Home")
        XCTAssertTrue(tapBack(to: "Company"))
        // Asserted: Back lands on Home (the net-worth summary).
        XCTAssertTrue(app.staticTexts["Net worth"].firstMatch.waitForExistence(timeout: 5) || app.staticTexts["NET WORTH"].firstMatch.exists, "Back should return to Home")
    }

    func testBackFromInboxCompanyLinkReturnsToInbox() throws {
        open("Inbox")
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 5))
        let link = app.buttons["open-company-link"].firstMatch
        guard link.waitForExistence(timeout: 3) else { throw XCTSkip("no Inbox message with a company link in the showcase game") }
        link.tap()
        assertCompanyOpen("Inbox")
        XCTAssertTrue(tapBack(to: "Inbox"))
        // Asserted: Back lands on the Inbox, not on the Company list.
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 5), "Back should return to the Inbox")
        XCTAssertFalse(app.staticTexts["Net worth"].firstMatch.exists, "Back must not land on Company/Home")
    }

    func testBackFromProjectsReturnsToProjects() throws {
        open("Projects")
        let link = app.buttons["open-project-company"].firstMatch
        guard link.waitForExistence(timeout: 3) else { throw XCTSkip("no company with project work in the showcase game") }
        link.tap()
        assertCompanyOpen("Projects")
        XCTAssertTrue(tapBack(to: "Projects"))
        // Asserted: Back lands on Projects (Work / Ventures tabs), not on the Company list.
        XCTAssertTrue(app.buttons["Ventures"].waitForExistence(timeout: 5), "Back should return to Projects")
        XCTAssertFalse(app.staticTexts["Net worth"].firstMatch.exists)
    }
}
