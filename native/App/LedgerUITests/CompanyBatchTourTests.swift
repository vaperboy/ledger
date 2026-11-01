import XCTest

/// Tours of the Company screens batch: the one Pricing screen, the How-you-sell popup, Stats (Finances, Performance, Customers), the Overview
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

/// Sales: the Pricing screen (a normal pushed screen) and the How-you-sell popup (a sheet with choices and their cost only).
final class CompanySalesTourTests: CompanyBatchTourCase {
    func testPricingAndHowYouSell() {
        guard openFirstCompany() else { return }
        guard tapID("company-tab-sales") else { return }
        shot("90-sales")
        if tapLabel("Pricing") || tapContaining("Pricing") {
            shot("91-pricing")
            app.swipeUp(); sleep(1)
            shot("91-pricing-lower")
            goBack()
        }
        if tapID("sales-how-you-sell") || tapContaining("How you sell") {
            shot("92-how-you-sell-popup")
            tapLabel("Done")
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

/// The Reviews app (yours and the rivals') and the Market app (all markets, then one business chosen in the selector).
final class ReviewsAndMarketTourTests: CompanyBatchTourCase {
    func testReviewsApp() {
        guard openPhoneApp("Reviews") else { return }
        XCTAssertTrue(app.otherElements["reviews-app"].exists || app.scrollViews.firstMatch.waitForExistence(timeout: 5), "the Reviews app opens")
        shot("97-reviews-yours")
        if tapID("reviews-side-rivals") { shot("97-reviews-rivals") }
    }

    func testMarketApp() {
        guard openPhoneApp("Market") else { return }
        XCTAssertTrue(app.buttons["market-business-picker"].waitForExistence(timeout: 5), "the Market app shows the business selector")
        shot("98-market-all")
        if tapID("market-business-picker") {
            shot("98-market-selector")
            let option = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Café' OR label CONTAINS[c] 'Cafe'")).firstMatch
            if option.waitForExistence(timeout: 3) && option.isHittable { option.tap(); sleep(1); shot("99-market-company") }
            else { note("no company in the Market selector") }
        }
    }
}
