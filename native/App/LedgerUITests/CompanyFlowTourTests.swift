import XCTest

/// Tours of startups, investment, product expansion and business creation. Short tests, pictures numbered from 110. Every step is
/// optional: a screen that is not reachable on this device is noted, never failed. Nothing is paid or started.
final class CompanyFlowTourTests: CompanyBatchTourCase {
    /// New company: the start-up statement with mandatory costs, optional extras (stock, equipment, team), remaining cash and the reserve.
    func testNewCompanyPlanStatement() {
        _ = waitForHome()
        let pill = app.buttons["tab-Home"]
        if pill.waitForExistence(timeout: 5) { pill.tap(); sleep(1) }
        let plus = app.buttons["New company"].firstMatch
        guard plus.waitForExistence(timeout: 5) else { note("no New company button"); return }
        plus.tap(); sleep(1)
        shot("110-new-company-trades")
        guard tapContaining("Café") || tapContaining("Cafe") || tapContaining("Consultant") else { return }
        shot("111-new-company-trade")
        app.swipeUp(); sleep(1)
        shot("111-new-company-statement")
        app.swipeUp(); sleep(1)
        shot("111-new-company-optional-and-cash")
        if tapLabel("None") { shot("112-new-company-no-stock") }
        app.swipeUp(); sleep(1)
        shot("112-new-company-alternatives-or-risks")
    }

    /// Product expansion: the project list, the form (cost, timeline, requirements, expected effect, cash after) and closing it changes nothing.
    func testExpansionForm() {
        guard openFirstCompany() else { return }
        guard tapID("company-tab-manage") else { return }
        app.swipeUp(); sleep(1)
        guard tapContaining("New menu item") || tapContaining("Develop") || tapContaining("New product") else { return }
        shot("113-expansion-projects")
        guard tapLabel("Plan it") else { return }
        shot("114-expansion-form")
        app.swipeUp(); sleep(1)
        shot("114-expansion-form-lower")
        tapLabel("Close")
        shot("115-expansion-closed-nothing-changed")
    }

    /// Ventures: the startups you founded (real companies), the rounds with their share terms, the launch sheet.
    func testVenturesStartupAndRounds() {
        guard openPhoneApp("Ventures") else { return }
        shot("116-ventures")
        app.swipeUp(); sleep(1)
        shot("116-ventures-lower")
        if tapContaining("Found a startup") {
            shot("117-found-startup")
            app.swipeUp(); sleep(1)
            shot("117-found-startup-plan")
            tapLabel("Close")
        }
        if tapContaining("Launch it") {
            shot("118-launch-sheet")
            tapLabel("Close")
        }
    }

    /// Ownership: share counts, price per share and the new-shares / sell-your-shares operations side by side.
    func testOwnershipAndShares() {
        guard openFirstCompany() else { return }
        guard tapID("company-tab-manage") else { return }
        app.swipeUp(); sleep(1)
        guard tapContaining("Owners") || tapContaining("Ownership") else { return }
        shot("119-ownership")
        if tapContaining("Sell shares") {
            shot("120-sell-shares")
            app.swipeUp(); sleep(1)
            shot("120-sell-shares-lower")
        }
    }
}
