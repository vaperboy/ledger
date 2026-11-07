import XCTest

/// Manual CI run (job `popup-shots`): opens every popup site on the showcase game and attaches a full-screen picture named
/// "popup-<site>", so the sizes can be checked on a small and a large phone. Every site is optional: one that cannot be reached
/// records a "MISSING <site>" attachment and the run goes on. Nothing here asserts.
final class PopupShotsTests: CompanyBatchTourCase {

    func keep(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func popup(_ site: String) { sleep(1); keep("popup-" + site) }

    func missing(_ site: String) {
        let a = XCTAttachment(string: "MISSING " + site)
        a.name = "MISSING " + site
        a.lifetime = .keepAlways
        add(a)
    }

    /// Runs one site; false from the body (or a skipped step) is recorded as MISSING.
    func site(_ name: String, _ body: () -> Bool) {
        if !body() { missing(name) }
    }

    func closeAny() {
        for id in ["popup-close", "report-continue", "alert-continue", "error-ok", "unlock-skip", "celebration-dismiss", "ambition-later", "conversion-keep"] {
            let b = app.buttons[id]
            if b.exists && b.isHittable { b.tap(); sleep(1); return }
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        sleep(1)
    }

    func exists(_ id: String, _ wait: TimeInterval = 2) -> Bool {
        app.descendants(matching: .any)[id].waitForExistence(timeout: wait)
    }

    func home() {
        _ = waitForHome()
        let p = app.buttons["tab-Home"]
        if p.waitForExistence(timeout: 3) { p.tap(); sleep(1) }
    }

    func goBackToHome() {
        let p = app.buttons["tab-Home"]
        if p.exists && p.isHittable { p.tap(); sleep(1) }
    }

    // MARK: Reports and event popups

    func testReportsAndEvents() {
        home()
        site("daily-report") {
            guard tapID("next-day") else { return false }
            sleep(2)
            popup("daily-report-or-after-day")
            if app.buttons["report-continue"].exists || app.buttons["daily-insight-action"].exists { closeAny() }
            return true
        }
        site("week-report") {
            guard tapID("play-week", wait: 5) else { return false }
            guard exists("report-open", 15) || exists("report-continue", 5) else { return false }
            popup("week-report-1")
            if tapID("report-open", wait: 2) {
                popup("week-report-detail")
                for i in 2...4 { if tapID("report-next", wait: 2) { popup("week-report-\(i)") } else { break } }
            }
            tapID("report-continue", wait: 2)
            return true
        }
        site("decision") {
            guard tapID("decide-appoint-manager", wait: 2) || exists("banner-go", 2) else { return false }
            popup("decision"); closeAny(); return true
        }
        site("celebration") {
            guard exists("celebration-claim", 2) || exists("celebration-dismiss", 2) else { return false }
            popup("celebration"); closeAny(); return true
        }
        site("unlock") {
            guard exists("unlock-go", 2) || exists("unlock-skip", 2) else { return false }
            popup("unlock"); closeAny(); return true
        }
        site("notice") {
            guard exists("alert-continue", 2) || exists("error-ok", 2) else { return false }
            popup("notice"); closeAny(); return true
        }
        site("ambition") {
            guard exists("ambition-later", 2) else { return false }
            popup("ambition"); closeAny(); return true
        }
    }

    // MARK: Phone apps

    func testSettingsSavesPaywall() {
        site("settings") {
            guard openPhoneApp("Settings") else { return false }
            popup("settings-page"); return true
        }
        site("paywall") {
            guard tapID("settings-ledger-pro", wait: 3) else { return false }
            popup("paywall"); closeAny(); return true
        }
        site("save-slots") {
            guard tapContaining("Save slots") else { return false }
            popup("save-slots")
            return true
        }
    }

    func testFoundAndLaunch() {
        site("found-startup") {
            guard openPhoneApp("Ventures") else { return false }
            guard tapLabel("Found a startup") else { return false }
            popup("found-startup")
            closeAny(); return true
        }
        site("launch-price") {
            guard tapContaining("Launch") || tapContaining("Change price") || tapContaining("Set price") else { return false }
            popup("launch-change-price"); closeAny(); return true
        }
    }

    func testLoanAndConfirm() {
        site("loan-flow") {
            guard openPhoneApp("Bank") else { return false }
            let pick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bank-pick-'")).firstMatch
            guard pick.waitForExistence(timeout: 5) else { return false }
            pick.tap(); sleep(1)
            guard tapLabel("Loans"), tapID("bank-apply-loan") else { return false }
            popup("loan-1-apply")
            guard tapID("bank-loan-choose") else { return false }
            popup("loan-2-choose")
            tapID("bank-loan-chip-50%")
            guard tapID("bank-loan-continue") else { return false }
            popup("loan-3-agreement")
            tapID("bank-loan-agree")
            if app.buttons["bank-loan-confirm"].waitForExistence(timeout: 3) {
                popup("loan-4-confirmation")
                tapID("bank-loan-confirm")
                popup("confirm-or-after-loan")
            }
            return true
        }
        site("confirm") {
            // A confirm question: paying a loan off in full, when there is a loan to pay.
            if tapID("loan-payoff", wait: 2) || tapContaining("Pay off", wait: 2) { popup("confirm"); closeAny(); return true }
            return false
        }
    }

    func testLuxury() {
        site("luxury") {
            guard openPhoneApp("Luxury") else { return false }
            popup("luxury-showroom")
            let hero = app.descendants(matching: .any)["luxury-hero"].firstMatch
            guard hero.waitForExistence(timeout: 3) else { return false }
            hero.tap(); sleep(1)
            guard exists("luxury-item-sheet", 3) || exists("luxury-confirm", 1) else { return false }
            popup("luxury-purchase")
            closeAny()
            if tapID("luxury-tab-owned", wait: 2) || tapContaining("Owned", wait: 1) {
                let owned = app.descendants(matching: .any)["luxury-hero"].firstMatch
                if owned.waitForExistence(timeout: 2) { owned.tap(); popup("luxury-inspect"); closeAny() }
            }
            return true
        }
    }

    // MARK: Company popups

    func testCompanyPopups() {
        site("conversion") {
            guard openFirstCompany(), tapContaining("Legal form and trading"), tapID("company-convert-review") else { return false }
            popup("conversion"); closeAny(); return true
        }
        goBackToHome()
        site("acquisition") {
            guard openPhoneApp("Market"), tapID("market-tab-Rivals") else { return false }
            let r = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'market-rival-co'")).firstMatch
            guard r.waitForExistence(timeout: 4) else { return false }
            r.tap(); sleep(1)
            guard tapID("rival-make-offer", wait: 2) else { return false }
            popup("acquisition"); closeAny(); return true
        }
        goBackToHome()
        site("sales-item") {
            guard openFirstCompany(), tapID("company-tab-sales") else { return false }
            guard tapContaining("vs market") || tapContaining("At market") else { return false }
            popup("sales-item"); closeAny(); return true
        }
    }

    func testHireFlow() {
        site("hire-flow") {
            guard openFirstCompany(), tapID("company-tab-team"), tapID("team-hire-workers") else { return false }
            popup("hire-list")
            guard tapID("hire-talk-terms", wait: 5) else { return false }
            popup("hire-1-terms")
            guard tapID("hire-next") else { return false }
            popup("hire-2-offer")
            tapID("hire-back"); tapID("hire-next")
            tapID("hire-walk-away")
            return true
        }
    }

    func testInfo() {
        site("info") {
            home()
            let i = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'About '")).firstMatch
            guard i.waitForExistence(timeout: 3), i.isHittable else { return false }
            i.tap(); popup("info"); closeAny(); return true
        }
    }
}
