import XCTest

/// Tours of the financial screens (Master spec Stage 2): the Accounting app, the Bank's two-stage loan flow up to its confirmation (nothing is borrowed),
/// the account list with the wealth overview, the company conversion preview (cancelled, nothing changes) and the Team metrics.
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

/// Accounting, part 1: the home with its business selector, Transactions and one transaction.
final class AccountingHomeTourTests: FinanceTourCase {
    func testAccountingHomeAndTransactions() {
        guard openPhoneApp("Accounting") else { return }
        XCTAssertTrue(app.buttons["acct-company-picker"].waitForExistence(timeout: 5), "the Accounting home shows the business selector")
        shot("70-accounting-home")
        // The selector is a menu of the live companies; open it, photograph it, close it.
        if tapID("acct-company-picker") {
            shot("71-accounting-selector")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.45)).tap()
            sleep(1)
        }
        if tapID("acct-row-transactions") {
            shot("72-accounting-transactions")
            tapID("acct-tx-income"); shot("72-accounting-transactions-income")
            tapID("acct-tx-all")
            tapID("acct-tx-range"); shot("72-accounting-transactions-range")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.45)).tap()
            sleep(1)
            let row = app.buttons["acct-tx-row"].firstMatch
            if row.waitForExistence(timeout: 3) && row.isHittable { row.tap(); sleep(1); shot("72-accounting-transaction-detail"); goBack() }
            else { note("no transaction row") }
            goBack()
        }
    }
}

/// Accounting, part 2: Payroll (all four pages) and Invoices & Payments.
final class AccountingPayrollTourTests: FinanceTourCase {
    func testAccountingPayrollAndInvoices() {
        guard openPhoneApp("Accounting") else { return }
        if tapID("acct-row-payroll") {
            shot("73-accounting-payroll-overview")
            tapLabel("Employees"); shot("73-accounting-payroll-employees")
            tapLabel("Timesheets"); shot("73-accounting-payroll-timesheets")
            tapLabel("Run payroll"); shot("73-accounting-payroll-run")
            goBack()
        }
        if tapID("acct-row-invoices") {
            shot("74-accounting-invoices")
            tapLabel("Payments"); shot("74-accounting-payments")
            goBack()
        }
    }
}

/// Accounting, part 3: Suppliers, Documents (Company, Tax, Contracts) and Settings (access).
final class AccountingRecordsTourTests: FinanceTourCase {
    func testAccountingSuppliersDocumentsSettings() {
        guard openPhoneApp("Accounting") else { return }
        if tapID("acct-row-suppliers") {
            shot("75-accounting-suppliers")
            let row = app.buttons["acct-supplier-row"].firstMatch
            if row.waitForExistence(timeout: 2) && row.isHittable { row.tap(); sleep(1); shot("75-accounting-supplier-profile"); goBack() }
            goBack()
        }
        if tapID("acct-row-documents") {
            shot("76-accounting-documents-company")
            tapLabel("Tax"); shot("76-accounting-documents-tax")
            tapLabel("Contracts"); shot("76-accounting-documents-contracts")
            goBack()
        }
        if tapID("acct-row-settings") {
            shot("77-accounting-settings")
            if tapID("acct-access-add") { shot("77-accounting-add-user"); goBack() }
            goBack()
        }
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
        guard tapID("bank-loan-start") else { return }
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
        tapContaining("I have read and agree")
        if tapLabel("Continue to confirmation") {
            shot("79-loan-5-confirmation")
            XCTAssertTrue(app.buttons["bank-loan-confirm"].exists, "the last step has the confirm button (not pressed here)")
        }
    }
}

/// The company conversion preview and the Team metrics, from the first company of the showcase game. The preview is cancelled: nothing changes.
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
        guard tapContaining("Legal form and trading") else { return }
        shot("81-company-legal-form")
        guard tapID("company-convert-review") else { note("this company is already a limited company"); return }
        shot("81-conversion-preview")
        XCTAssertTrue(app.buttons["conversion-confirm"].waitForExistence(timeout: 3) || app.otherElements["conversion-blocked"].exists, "the preview ends in a decision or says why it is blocked")
        if app.buttons["conversion-payer-company"].exists { app.buttons["conversion-payer-company"].tap(); sleep(1); shot("81-conversion-company-pays") }
        // Cancel: the sheet closes and the company stays what it was.
        tapID("conversion-cancel")
        shot("81-conversion-cancelled")
    }
}
