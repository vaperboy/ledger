import XCTest

/// Screenshots of the app shell on the showcase game: the five tabs, the Custom tab and its picker, a pushed page with its header and
/// back, segmented controls, and every popup kind that can be reached (report, decision, info, notice, confirm, panel, toast, banner).
/// Nothing asserts: a step that cannot be reached is shot as it is and the run goes on.
final class ShotsShellTests: FeatureTourCase {

    func shot(_ name: String, settle: Double = 0.8) {
        pause(settle)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "Shell-" + name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Shoots whatever popup is up (when one is), then closes it.
    func shootPopup(_ name: String) {
        if popupUp(2) { shot(name); closePopup() } else { shot(name + "-none") }
    }

    func scrollDown() { dragPage(-420) }

    func testShots() {
        // Tabs at their roots, then each scrolled (large titles collapse, the bar stays clear of content).
        goTab("Home"); shot("tab-home")
        scrollDown(); shot("tab-home-scrolled"); dragPage(900)
        goTab("Ventures"); shot("tab-ventures")
        goTab("Group"); shot("tab-group")
        scrollDown(); shot("tab-group-scrolled"); dragPage(900)
        goTab("Phone"); shot("tab-phone")

        // The Custom tab: empty, its picker, then filled with an app.
        if let c = customTab() {
            touch(c); shot("custom-empty")
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: c.frame.midX, dy: c.frame.midY)).press(forDuration: 1.2)
            shot("custom-picker")
            if !tapWhere(wait: 2, { $0.id.hasPrefix("custom-pick-") && $0.type == .button }) { closePopup() }
            pause(0.8)
            var k = 0
            while popupUp(0.5) && k < 4 { closePopup(); k += 1 }
            if let c2 = customTab() { touch(c2) }
            shot("custom-filled")
        } else { shot("custom-missing") }

        // A pushed page: header, back, segmented control.
        if openCompany("Caf") {
            shot("pushed-company")
            scrollDown(); shot("pushed-company-scrolled")
            dragPage(900)
            if tapID("company-tab-team", wait: 2) { shot("segmented-team") }
            _ = tapBack(); shot("after-back")
        } else { shot("pushed-company-missing") }

        // Phone app pages: Bank and Settings.
        if openPhoneApp("Bank") {
            shot("bank")
            if tapPrefix("bank-pick-", wait: 4) {
                shot("bank-account")
                if tapID("loan-payoff", wait: 2) || tapText("Pay off", wait: 2) { shootPopup("popup-confirm") }
            }
            toRoot()
        }
        if openPhoneApp("Settings") {
            shot("settings")
            if tapID("settings-ledger-pro", wait: 3) { shootPopup("popup-paywall") }
            toRoot()
        }

        // Home popups: info, the day's report, the week's report, then anything the week raised.
        goTab("Home")
        let info = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'About '")).firstMatch
        if info.waitForExistence(timeout: 3), ctap(info) { shootPopup("popup-info") }
        goTab("Home")
        if tapID("next-day", wait: 3) {
            shot("after-next-day-banner", settle: 0.4)
            if popupUp(3) { shot("popup-day-report") }
            var n = 0
            while popupUp(1) && n < 4 { closePopup(); n += 1; if popupUp(0.5) { shot("popup-after-day-\(n)") } }
        }
        goTab("Home")
        if tapID("play-week", wait: 4) {
            if popupUp(15) { shot("popup-week-report") }
            if tapID("report-open", wait: 2) {
                shot("popup-week-report-detail")
                if tapID("report-next", wait: 2) { shot("popup-week-report-next") }
            }
            var n = 0
            while popupUp(1.5) && n < 8 {
                closePopup(); n += 1
                if popupUp(0.6) { shot("popup-after-week-\(n)") }
            }
            shot("after-week-toasts", settle: 0.2)
        }
        goTab("Home")
        if tapID("decide-appoint-manager", wait: 2) || tapID("banner-go", wait: 2) { shootPopup("popup-decision") }
        goTab("Home"); shot("home-end")
    }
}
