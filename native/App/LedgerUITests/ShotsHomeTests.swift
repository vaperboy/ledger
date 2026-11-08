import XCTest

/// Screenshots of the Home territory: Home (top, companies, rank and shortcuts), Needs you, Insights and the paywall, the Inbox (three
/// segments and a message), the daily briefing, week and month reports, the Reports app, the wardrobe, game over, and the new-player
/// start. Every step is optional: a control that is not there is skipped and the next screen is still taken.
final class ShotsHomeTests: FeatureTourCase {
    func testShots() {
        snap("home")
        // Home fits one screen: a drag must not move it.
        dragPage(-360); snap("home-after-drag")

        // Needs you: the first item opens its popup right on Home.
        if tapPrefix("suggestion-", wait: 2) { snap("needs-you-popup"); closePopup() }

        // All companies (the Group tab's list), the rank button (Goals), Insights and the paywall behind it for a free player.
        if bringAndTap("show-all-companies") { pause(1); snap("all-companies") }
        toRoot(); _ = goTab("Home")
        if bringAndTap("home-rank-ring") { pause(1); snap("rank-goals") }
        toRoot(); _ = goTab("Home")
        if bringAndTap("home-mission") { pause(1.2); snap("mission-tapped") }
        toRoot(); _ = goTab("Home")
        if bringAndTap("home-milestone") { pause(1); snap("milestone-tapped") }
        toRoot(); _ = goTab("Home")
        if bringAndTap("home-insights") {
            snap("insights")
            if tapLabel("Unlock with Ledger Pro") { pause(1); snap("paywall"); closePopup(prefer: ["paywall-pass"]) } else { closePopup() }
        }
        toRoot(); _ = goTab("Home"); dragPage(1400)

        // Inbox: Needs you, Handled, All and one message.
        if openPhoneApp("inbox") {
            pause(1); snap("inbox-needs-you")
            if tapText("Handled") { snap("inbox-handled") }
            if tapText("All") { snap("inbox-all") }
            if tapPrefix("inbox-row", wait: 2) { pause(0.8); snap("inbox-message"); closePopup() }
        }
        toRoot(); _ = goTab("Home")

        // The daily briefing after Next day.
        if tapID("next-day", wait: 4) {
            if popupUp(12) { pause(2.5); snap("daily-briefing"); while popupUp(1) { closePopup(prefer: ["report-continue"]) } }
        }

        // Week and month reports: play to the end of the week until a month closes (at most five weeks).
        for w in 1...5 {
            _ = goTab("Home")
            _ = tapID("skip-menu", wait: 3)
            guard tapEnabled("play-week", wait: 4) else { break }
            if w == 1 { pause(0.5); snap("skip-week-playing") }
            var month = false
            var n = 0
            while n < 6 && popupUp(n == 0 ? 25 : 2) {
                pause(2)
                let isMonth: Bool = onScreenText("month") || onScreenText("Month")
                snap(isMonth ? "month-report-w\(w)" : "week-report-w\(w)")
                if isMonth && !month { dragPage(-500); snap("month-report-more"); month = true }
                closePopup(prefer: ["report-continue", "celebration-dismiss"])
                n += 1
            }
            if month { break }
        }
        toRoot()

        // The Reports app (week, month, year).
        if openPhoneApp("reports") {
            pause(1); snap("reports-week")
            dragPage(-500); snap("reports-week-more")
            if tapText("Month") { pause(0.8); snap("reports-month") }
        }
        toRoot()

        // Wardrobe (Settings).
        if openPhoneApp("settings"), bringAndTap("settings-wardrobe") { pause(1); snap("wardrobe"); closePopup() }
        toRoot()

        // Game over, over the showcase game.
        relaunch(["-showcase", "-showcase-rich", "-showcase-gameover"])
        pause(2); snap("game-over")
        dragPage(-600); snap("game-over-more")

        // A brand new player: start screen, the three setup steps, the ambition prompt, the first Home and its first briefing.
        relaunch([])
        pause(4); snap("start")
        if tapID("start-new", wait: 3) || tapLabel("Start") || tapLabel("New game") {
            pause(1); snap("setup-country")
            let field: XCUIElement = app.textFields.firstMatch
            if field.waitForExistence(timeout: 2) { field.tap(); field.typeText("United Kingdom") }
            if tapID("country-GB", wait: 2) || tapWhere(wait: 2, { $0.type == .button && $0.label.contains("United Kingdom") }) {
                pause(3); snap("setup-trade")
                if tapID("trade-cafe", wait: 6) || tapWhere(wait: 6, { $0.type == .button && $0.label.hasPrefix("Café") }) || tapWhere(wait: 2, { $0.type == .button && $0.label.hasPrefix("Cafe") }) {
                    pause(2); snap("setup-trade-popup")
                    if tapID("trade-open", wait: 3) || tapLabel("Open ") {
                        pause(1); snap("setup-name")
                        if tapID("setup-start", wait: 3) || tapWhere(wait: 3, { $0.type == .button && $0.label == "Start" }) {
                            pause(3); snap("ambition")
                            if tapID("ambition-later", wait: 4) { pause(1) }
                            var k = 0
                            while k < 4 && popupUp(1) { snap("first-popup-\(k)"); closePopup(); k += 1 }
                            snap("home-new-player")
                            dragPage(-500); snap("home-new-player-more")
                            dragPage(1400)
                            if tapID("next-day", wait: 4), popupUp(12) { pause(2.5); snap("daily-briefing-first") }
                        }
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func snap(_ name: String) {
        pause(0.7)
        let a: XCTAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "Home-\(name)"
        a.lifetime = .keepAlways
        add(a)
    }

    /// Scrolls the control into view and taps it.
    private func bringAndTap(_ id: String) -> Bool {
        guard let h = bringIn({ $0.id == id }, wait: 3) else { return false }
        _ = touch(h)
        pause(0.8)
        return true
    }

    private func relaunch(_ args: [String]) {
        app.terminate()
        app.launchArguments = args
        app.launch()
        pause(2)
    }
}
