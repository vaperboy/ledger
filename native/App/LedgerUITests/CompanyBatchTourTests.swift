import XCTest

class CompanyBatchTourCase: FinanceTourCase {
    @discardableResult
    func openFirstCompany() -> Bool {
        _ = waitForHome()
        let pill = app.buttons["tab-Home"]
        if pill.waitForExistence(timeout: 5) { pill.tap(); sleep(1) }
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Café' OR label CONTAINS[c] 'Cafe'")).firstMatch
        guard first.waitForExistence(timeout: 5) else { note("no company on Home"); return false }
        first.tap()
        sleep(1)
        return true
    }
}
