import XCTest

/// Walks through the app on a prepared game and keeps a screenshot of every main screen.
/// Run by CI (see .github/workflows/native-ios.yml); the pictures are the evidence of how the screens look.
final class ScreenshotTests: TourCase {

    /// iPhone has the floating pill tab bar (buttons "tab-Home", "tab-Team", ...); iPad a sidebar.
    func open(_ name: String) {
        let pill = app.buttons["tab-\(name)"]
        if pill.exists { pill.tap(); return }
        let row = app.buttons[name].firstMatch
        if row.exists { row.tap(); return }
        app.staticTexts[name].firstMatch.tap()
    }

    /// Back from a pushed screen: the navigation bar's back button, only when it can really be tapped (on iPad the first
    /// navigation-bar button can be one behind a sheet, which cannot be scrolled to or tapped).
    func goBack() {
        let round = app.buttons["back-button"]
        if round.exists && round.isHittable { round.tap(); return }
        let bars = app.navigationBars
        for i in 0..<bars.count {
            let b = bars.element(boundBy: i).buttons.element(boundBy: 0)
            if b.exists && b.isHittable { b.tap(); return }
        }
    }

    func testTour() {
        if !waitForHome() { note("Home summary not found; continuing anyway") }
        shot("01-home")
        let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Next day")).firstMatch
        if next.exists { next.tap(); next.tap(); shot("02-home-after-two-days") }

        open("Home"); sleep(1); shot("03-home")
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

        // The Phone: its home, then every app on the grid, each with a round back button to the home.
        open("Phone"); sleep(1); shot("09-phone-home")
        let apps = ["Bank", "Inbox", "News", "Weather", "Stats", "Goals", "World", "Luxury", "Ventures", "Rich list", "Reports", "Achievements", "Settings"]
        for (i, name) in apps.enumerated() {
            let icon = app.buttons["phone-app-\(name)"]
            guard icon.waitForExistence(timeout: 2) else { note("no Phone app \(name)"); continue }
            icon.tap(); sleep(1)
            let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
            shot("10-phone-\(String(format: "%02d", i + 1))-\(slug)")
            goBack(); sleep(1)
        }
    }
}
