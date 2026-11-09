import XCTest

/// Tours of the financial screens: the Bank's two-stage loan flow up to its confirmation (nothing is borrowed),
/// the account list with the wealth overview, the company settings and the Team metrics.
/// Pictures are numbered from 70. Every part is its own short test (CI gives each test 150 s; each of these stays well under 100 s), and every step is
/// optional: a screen that is not reachable on this device is noted, never failed.
class FinanceTourCase: TourCase {
    func goBack() {
        let round = app.buttons["back-button"]
        if round.exists && round.isHittable { round.tap(); sleep(1); return }
        let bars = app.navigationBars
        for i in 0..<bars.count {
            let b = bars.element(boundBy: i).buttons.element(boundBy: 0)
            if b.exists && b.isHittable { b.tap(); sleep(1); return }
        }
    }

    /// Opens an app of the Phone tab and waits for something that is on its first screen.
    @discardableResult
    func openPhoneApp(_ name: String) -> Bool {
        _ = waitForHome()
        let pill = app.buttons["tab-Phone"]
        if pill.waitForExistence(timeout: 5) { pill.tap() }
        let icon = app.buttons["phone-app-\(name)"]
        guard icon.waitForExistence(timeout: 5) else { note("no Phone app \(name)"); return false }
        icon.tap()
        sleep(1)
        return true
    }

    /// Taps a button by its accessibility identifier; returns whether it was there and hittable.
    @discardableResult
    func tapID(_ id: String, wait: TimeInterval = 3) -> Bool {
        let b = app.buttons[id]
        if b.waitForExistence(timeout: wait) && b.isHittable { b.tap(); sleep(1); return true }
        note("no button \(id)")
        return false
    }

    /// Taps a button by its exact label (the section tabs have no identifiers).
    @discardableResult
    func tapLabel(_ label: String, wait: TimeInterval = 3) -> Bool {
        let b = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        if b.waitForExistence(timeout: wait) && b.isHittable { b.tap(); sleep(1); return true }
        note("no button labelled \(label)")
        return false
    }

    @discardableResult
    func tapContaining(_ text: String, wait: TimeInterval = 3) -> Bool {
        let b = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        if b.waitForExistence(timeout: wait) && b.isHittable { b.tap(); sleep(1); return true }
        note("no button containing \(text)")
        return false
    }
}

/// The Bank: the account list with the wealth overview, then the loan flow from the first screen to the confirmation. The flow stops before the
/// confirm button, so nothing is borrowed.
final class BankLoanTourTests: FinanceTourCase {
    func testBankWealthAndLoanFlowToConfirmation() {
        guard openPhoneApp("Bank") else { return }
        let pick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bank-pick-'")).firstMatch
        guard pick.waitForExistence(timeout: 5) else { note("no Bank picker row"); return }
        pick.tap(); sleep(1)
        shot("78-bank-account")
        // Back to the account list: the total balance and the wealth overview.
        goBack()
        shot("78-bank-accounts-wealth")
        // Open the account again and its Loans tab.
        let again = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bank-account-'")).firstMatch
        if again.waitForExistence(timeout: 3) && again.isHittable { again.tap(); sleep(1) }
        guard tapLabel("Loans") else { return }
        shot("79-bank-loans")
        guard tapID("bank-apply-loan") else { return }
        shot("79-loan-1-apply")
        shot("79-loan-2-offer")
        if app.otherElements["bank-loan-refused"].exists || app.staticTexts["The bank would not lend now"].exists {
            note("the bank refused this borrower: the refusal is shown, no amount is offered")
            return
        }
        XCTAssertTrue(app.staticTexts["Maximum approved amount"].waitForExistence(timeout: 3), "the offer shows the maximum approved amount")
        guard tapID("bank-loan-choose") else { return }
        shot("79-loan-3-choose")
        tapID("bank-loan-chip-50%")
        shot("79-loan-3-choose-half")
        guard tapID("bank-loan-continue") else { return }
        shot("79-loan-4-agreement")
        tapID("bank-loan-agree")
        if app.buttons["bank-loan-confirm"].waitForExistence(timeout: 3) {
            shot("79-loan-5-confirmation")
            XCTAssertTrue(app.buttons["bank-loan-confirm"].exists, "the last step has the confirm button (not pressed here)")
        }
    }
}

/// The company settings and the Team metrics, from the first company of the showcase game. Nothing is changed.
final class ConversionPreviewTourTests: FinanceTourCase {
    func testConversionPreviewAndTeamMetrics() {
        _ = waitForHome()
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Café' OR label CONTAINS[c] 'Cafe'")).firstMatch
        guard first.waitForExistence(timeout: 5) else { note("no company on Home"); return }
        first.tap(); sleep(1)
        let team = app.buttons["company-tab-team"]
        if team.waitForExistence(timeout: 3) { team.tap(); sleep(1); shot("80-company-team-metrics") }
        let stats = app.buttons["company-tab-stats"]
        if stats.waitForExistence(timeout: 3) { stats.tap(); sleep(1); shot("80-company-stats-cash-first") }
        guard tapContaining("Company settings") else { return }
        shot("81-company-settings")
    }
}
