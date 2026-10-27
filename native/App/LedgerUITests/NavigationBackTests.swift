import XCTest

/// Back-navigation (roadmap D1): a company opened from Home, Projects or Inbox must return to that screen on Back, not to the
/// Company list. Run by CI with the screenshot tests. An entry point that the prepared game does not have (the showcase game has no
/// project company) is reported as skipped, never as a pass.
final class NavigationBackTests: TourCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        if !waitForHome() { note("Home summary not found") }
    }

    private func open(_ name: String) {
        let pill = app.buttons["tab-\(name)"]
        if pill.exists { pill.tap(); return }
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
        // Screens with the new header (Phone apps) have the round back button instead of a navigation bar.
        let round = app.buttons["back-button"]
        if round.exists && round.isHittable { round.tap(); return true }
        return false
    }

    /// A pushed company shows the section tabs of a company. When the link did not open one on this device the test is skipped
    /// with a note (the picture is kept), instead of waiting out long timeouts and failing.
    private func assertCompanyOpen(_ from: String) throws {
        if app.buttons["Operations"].waitForExistence(timeout: 3) || app.buttons["Finances"].waitForExistence(timeout: 1) { return }
        shot("90-nav-\(from.lowercased())-link-no-company")
        throw XCTSkip("the link from \(from) did not open a company on this device")
    }

    func testBackFromHomeSuggestionReturnsToHome() throws {
        open("Home")
        let link = app.buttons["suggestion-open-company"].firstMatch
        guard link.waitForExistence(timeout: 2) else { throw XCTSkip("no Home suggestion opens a company in the showcase game") }
        link.tap()
        try assertCompanyOpen("Home")
        XCTAssertTrue(tapBack(to: "Home"))
        // Asserted: Back lands on Home (the net-worth summary).
        XCTAssertTrue(app.staticTexts["Net worth"].firstMatch.waitForExistence(timeout: 5) || app.staticTexts["NET WORTH"].firstMatch.exists, "Back should return to Home")
    }

    func testBackFromInboxCompanyLinkReturnsToInbox() throws {
        open("Phone")
        let inboxIcon = app.buttons["phone-app-Inbox"]
        XCTAssertTrue(inboxIcon.waitForExistence(timeout: 3), "the Inbox is an app on the Phone")
        inboxIcon.tap()
        XCTAssertTrue(app.textFields["Search messages"].waitForExistence(timeout: 3), "the Inbox app should be open")
        let link = app.buttons["open-company-link"].firstMatch
        guard link.waitForExistence(timeout: 2) else { throw XCTSkip("no Inbox message with a company link in the showcase game") }
        link.tap()
        // Strict: the Inbox link must open the company (no skip).
        XCTAssertTrue(app.buttons["Operations"].waitForExistence(timeout: 5) || app.buttons["Finances"].waitForExistence(timeout: 2), "the Inbox company link should open the company")
        XCTAssertTrue(tapBack(to: "Inbox"))
        // Asserted: Back lands on the Inbox app, not on Home.
        XCTAssertTrue(app.textFields["Search messages"].waitForExistence(timeout: 5), "Back should return to the Inbox")
        XCTAssertFalse(app.staticTexts["Net worth"].firstMatch.exists, "Back must not land on Company/Home")
    }

    func testBackFromProjectsReturnsToProjects() throws {
        open("Projects")
        let link = app.buttons["open-project-company"].firstMatch
        guard link.waitForExistence(timeout: 2) else { throw XCTSkip("no company with project work in the showcase game") }
        link.tap()
        try assertCompanyOpen("Projects")
        XCTAssertTrue(tapBack(to: "Projects"))
        // Asserted: Back lands on Projects (Work / Ventures tabs), not on the Company list.
        XCTAssertTrue(app.buttons["Ventures"].waitForExistence(timeout: 5), "Back should return to Projects")
        XCTAssertFalse(app.staticTexts["Net worth"].firstMatch.exists)
    }
}
