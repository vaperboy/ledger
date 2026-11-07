import XCTest

/// Tours of the Company screens batch: the Sales popups (item price, Marketing), Stats (Finances, Performance, Customers), the Overview
/// boxes, and the Reviews and Market apps of the Phone. Pictures are numbered from 90. Every part is its own short test (each stays well under
/// 100 s) and every step is optional: a screen that is not reachable on this device is noted, never failed.
class CompanyBatchTourCase: FinanceTourCase {
    /// Opens the first company on Home (the showcase game's café).
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

/// Sales: the products table, an item's price popup (centred, with "How it is sold" under it) and the Marketing popup.
final class CompanySalesTourTests: CompanyBatchTourCase {
    /// Closes a centred popup by tapping the dimmed area above it.
    func closePopup() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        sleep(1)
    }

    func testSalesItemAndMarketingPopups() {
        guard openFirstCompany() else { return }
        guard tapID("company-tab-sales") else { return }
        shot("90-sales")
        if tapContaining("vs market") || tapContaining("At market") {
            shot("91-sales-item-popup")
            XCTAssertTrue(app.descendants(matching: .any)["sales-item-price"].waitForExistence(timeout: 3), "the item popup shows the price")
            app.swipeUp(); sleep(1)
            shot("92-how-it-is-sold")
            closePopup()
        }
        if tapLabel("Marketing") || tapContaining("Marketing") {
            shot("92-marketing-popup")
            closePopup()
        }
    }
}

/// Stats: Finances (where the money goes first, the margins under it, Owed), Performance and Customers (Who buys at the top).
final class CompanyStatsTourTests: CompanyBatchTourCase {
    func testStatsPartsAndOverviewBoxes() {
        guard openFirstCompany() else { return }
        shot("93-overview")
        app.swipeUp(); sleep(1)
        shot("93-overview-lower")
        app.swipeDown(); app.swipeDown(); sleep(1)
        guard tapID("company-tab-stats") else { return }
        shot("94-stats-finances")
        app.swipeUp(); sleep(1)
        shot("94-stats-finances-lower")
        app.swipeDown(); app.swipeDown(); sleep(1)
        if tapID("stats-part-customers") {
            shot("96-stats-customers")
            app.swipeUp(); sleep(1)
            shot("96-stats-customers-lower")
        }
    }
}

/// The Reviews app (yours and the rivals') and the Market app (its Overview, then one company's market).
final class ReviewsAndMarketTourTests: CompanyBatchTourCase {
    func testReviewsApp() {
        guard openPhoneApp("Reviews") else { return }
        XCTAssertTrue(app.otherElements["reviews-app"].exists || app.scrollViews.firstMatch.waitForExistence(timeout: 5), "the Reviews app opens")
        shot("97-reviews-yours")
        if tapID("reviews-side-rivals") { shot("97-reviews-rivals") }
    }

    func testMarketApp() {
        guard openPhoneApp("Market") else { return }
        XCTAssertTrue(app.buttons["market-tab-Overview"].waitForExistence(timeout: 5), "the Market app shows its five parts")
        shot("98-market-overview")
        if tapID("market-tab-Companies") {
            shot("98-market-companies")
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'market-company-'")).firstMatch
            if row.waitForExistence(timeout: 3) && row.isHittable { row.tap(); sleep(1); shot("99-market-company") }
            else { note("no company in Market > Companies") }
        }
    }
}
