import XCTest

/// A second, deeper tour of the screens the player uses most: the company screen and its sections, staff, hiring, the contract
/// discussion, group structure, projects and inbox detail. Pictures are numbered from 20 so they sit after the first tour.
/// Everything is optional: a screen that is not reachable on this device is skipped, never failed.
final class MainScreensTests: XCTestCase {
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

    func open(_ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.exists { tab.tap(); return }
        let row = app.buttons[name].firstMatch
        if row.exists { row.tap(); return }
        let t = app.staticTexts[name].firstMatch
        if t.exists { t.tap() }
    }

    func goBack() {
        let bars = app.navigationBars
        for i in 0..<bars.count {
            let b = bars.element(boundBy: i).buttons.element(boundBy: 0)
            if b.exists && b.isHittable { b.tap(); return }
        }
    }

    /// Taps the first button or text whose label begins with / contains the text; returns whether something was tapped.
    @discardableResult
    func tap(_ text: String) -> Bool {
        let b = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        if b.exists && b.isHittable { b.tap(); sleep(1); return true }
        let t = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        if t.exists && t.isHittable { t.tap(); sleep(1); return true }
        return false
    }

    func scrollDown() { app.swipeUp(); sleep(1) }

    func testMainScreens() {
        XCTAssertTrue(app.staticTexts["Net worth"].waitForExistence(timeout: 20) || app.staticTexts["NET WORTH"].waitForExistence(timeout: 5))
        shot("20-home")
        scrollDown(); shot("21-home-lower")

        // Company list and one company with every section
        open("Company"); sleep(1); shot("22-company-list")
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Café' OR label CONTAINS[c] 'Cafe'")).firstMatch
        if first.waitForExistence(timeout: 3) {
            first.tap(); sleep(1); shot("23-company-overview")
            scrollDown(); shot("24-company-overview-lower")
            var n = 25
            for section in ["Team", "Finances", "Operations", "Marketing", "Customers", "Market", "Setup"] {
                let b = app.buttons[section]
                if b.exists && b.isHittable {
                    b.tap(); sleep(1); shot("\(n)-company-\(section.lowercased())"); n += 1
                    scrollDown(); shot("\(n)-company-\(section.lowercased())-lower"); n += 1
                    if section == "Operations" {
                        for sub in ["Suppliers", "Insurance", "Working from home"] where tap(sub) {
                            shot("\(n)-operations-\(sub.lowercased().replacingOccurrences(of: " ", with: "-"))"); n += 1
                            goBack()
                        }
                    }
                    if section == "Finances" {
                        for sub in ["Payroll and bills", "Accounts", "Loans"] where tap(sub) {
                            shot("\(n)-finances-\(sub.lowercased().replacingOccurrences(of: " ", with: "-"))"); n += 1
                            goBack()
                        }
                    }
                    if section == "Team" {
                        if tap("Find workers") { shot("\(n)-team-find-workers"); n += 1; goBack() }
                    }
                }
            }
            goBack()
        }

        // Team tab and a person
        open("Team"); sleep(1); shot("40-team")
        scrollDown(); shot("41-team-lower")

        // Group
        open("Group"); sleep(1); shot("45-group")
        scrollDown(); shot("46-group-lower")
        if tap("Stand alone") { shot("47-group-stand-alone"); goBack() }

        // Projects and Inbox detail
        open("Projects"); sleep(1); shot("50-projects")
        open("Inbox"); sleep(1); shot("52-inbox")
        let row = app.cells.firstMatch
        if row.exists && row.isHittable { row.tap(); sleep(1); shot("53-inbox-message"); goBack() }
    }
}
