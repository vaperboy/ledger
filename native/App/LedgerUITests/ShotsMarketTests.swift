import XCTest

/// Screenshots of every part of the Market app on the showcase game: Overview, Companies (a company's market, Compare with, an offer
/// for a rival), Rivals (filters, a rival profile, a group), Invest (a buy and a sell from start to finish, a position, the fund
/// manager) and World (Rankings, Records, People, a country). Nothing asserts: a control that is not there is noted and the walk goes on.
final class ShotsMarketTests: FeatureTourCase {
    private var count = 0

    private func snap(_ name: String) {
        count += 1
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = String(format: "Market-%02d-%@", count, name)
        a.lifetime = .keepAlways
        add(a)
    }

    /// The screen, then one screen lower for each `lower`.
    private func snapPage(_ name: String, lower: Int = 1) {
        snap(name)
        for i in 0..<lower {
            dragPage(-520)
            snap("\(name)-lower\(i + 1)")
        }
        for _ in 0..<lower { dragPage(520) }
    }

    private func closeAll() { var n = 0; while popupUp(0.5) && n < 4 { closePopup(); n += 1 } }

    /// Back to the Market app's root (its five parts), opening it again when it is gone.
    @discardableResult
    private func toMarket() -> Bool {
        closeAll()
        var n = 0
        while !has("market-tab-Overview", wait: 0.6) && n < 6 {
            if !tapBack() { break }
            n += 1
        }
        if has("market-tab-Overview", wait: 1) { return true }
        return openPhoneApp("Market") && has("market-tab-Overview", wait: 4)
    }

    private func part(_ name: String) -> Bool {
        guard toMarket() else { return false }
        guard tapID("market-tab-\(name)", wait: 3) else { return false }
        pause(0.8)
        return true
    }

    /// Closes an open menu with a tap at the very top of the screen, where nothing is.
    private func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        pause(0.4)
    }

    private func popupShot(_ name: String) {
        if popupUp(3) { pause(0.6); snap(name) } else { snap(name + "-nopopup") }
    }

    func testShots() {
        guard openPhoneApp("Market") else { snap("no-market-app"); return }
        pause(1.2)
        closeAll()

        // Overview
        snapPage("overview", lower: 2)

        // Companies, one company's market, Compare with, an offer for a rival
        if part("Companies") {
            snapPage("companies", lower: 1)
            if tapPrefix("market-company-", wait: 3) {
                pause(1)
                snapPage("company", lower: 3)
                if tapID("market-compare-with", wait: 2) { pause(0.6); snap("company-compare-menu"); closeAll(); dismissMenu() }
                if tapPrefix("market-buy-rival-", wait: 2) {
                    popupShot("company-offer")
                    if tapID("rival-offer-send", wait: 2) { pause(1); snap("company-offer-reply") }
                    closeAll()
                }
                if tapPrefix("market-field-", wait: 2) { pause(1); snapPage("company-rival", lower: 2) }
            } else { snap("companies-no-row") }
        } else { snap("companies-missing") }
        if part("Companies"), tapID("market-data-analyst", wait: 3) { pause(0.8); snap("data-analyst") }

        // Rivals: filters, a rival profile with its offer, a group
        if part("Rivals") {
            snapPage("rivals", lower: 1)
            for f in ["For sale", "Watching", "Groups"] where tapID("market-rivals-\(f)", wait: 2) { pause(0.6); snap("rivals-\(f)") }
            if tapPrefix("market-group-", wait: 2) { pause(1); snapPage("rival-group", lower: 1) }
        }
        if part("Rivals"), tapID("market-rivals-All", wait: 2), tapPrefix("market-rival-co", wait: 3) {
            pause(1)
            snapPage("rival-profile", lower: 3)
            if tapID("rival-watch", wait: 2) { pause(0.5); snap("rival-watched") }
            if tapID("rival-more", wait: 2) { pause(0.5); snap("rival-menu"); closeAll(); dismissMenu() }
            if tapID("rival-make-offer", wait: 2) {
                popupShot("rival-offer")
                if tapID("rival-offer-send", wait: 2) { pause(1); snap("rival-offer-reply") }
                if tapID("rival-offer-accept", wait: 2) { pause(1); popupShot("rival-acquisition") }
                closeAll()
            }
        }

        // Invest: the portfolio, a buy from start to finish
        if part("Invest") {
            snapPage("invest", lower: 1)
            if tapID("invest-buy", wait: 3) {
                pause(0.8)
                snapPage("buy-what", lower: 1)
                if tapID("trade-asset-fund-idx", wait: 3) || tapPrefix("trade-asset-", wait: 2) {
                    pause(0.8)
                    if has("trade-owner-you", wait: 1) { snap("buy-who"); _ = tapID("trade-owner-you") ; pause(0.6) }
                    if let field = find(wait: 3, { $0.type == .textField }) {
                        touch(field)
                        pause(0.6)
                        app.typeText("2000")
                        if let d = find({ $0.type == .button && $0.label == "Done" }) { touch(d) }
                    }
                    snap("buy-amount")
                    if tapEnabled("trade-review", wait: 2) {
                        pause(0.6)
                        snap("buy-review")
                        if tapEnabled("trade-confirm", wait: 2) { pause(1); snap("buy-done"); _ = tapID("trade-done", wait: 2) }
                    } else { snap("buy-review-blocked") }
                }
            } else { snap("invest-no-buy") }
        }

        // Invest: a position, then a sell from start to finish
        if part("Invest") {
            pause(0.6)
            snap("invest-after-buy")
            if tapID("invest-position-you|fund-idx", wait: 3) || tapPrefix("invest-position-", wait: 2) {
                pause(1)
                snapPage("position", lower: 1)
                if tapID("position-sell", wait: 2) {
                    pause(0.8)
                    snap("sell-amount")
                    if tapID("trade-fraction-50", wait: 2) { pause(0.5); snap("sell-half") }
                    if tapEnabled("trade-review", wait: 2) {
                        pause(0.6)
                        snap("sell-review")
                        if tapEnabled("trade-confirm", wait: 2) { pause(1); snap("sell-done"); _ = tapID("trade-done", wait: 2) }
                    }
                }
            } else { snap("invest-no-position") }
        }
        if part("Invest"), tapID("invest-fund-manager", wait: 3) { pause(0.8); snapPage("fund-manager", lower: 1) }

        // World: the countries, Rankings, Records, People, a country
        if part("World") {
            snapPage("world", lower: 2)
            if tapID("world-rankings", wait: 3) {
                pause(1)
                snapPage("rankings", lower: 1)
                for p in ["Companies", "Awards"] where tapID("rankings-\(p)", wait: 2) { pause(0.8); snapPage("rankings-\(p)", lower: 1) }
            }
        }
        if part("World"), tapID("world-records", wait: 3) { pause(1); snap("records") }
        if part("World"), tapID("world-around", wait: 3) { pause(1); snapPage("people", lower: 1) }
        if part("World"), tapPrefix("world-country-", wait: 3) {
            pause(1)
            snapPage("country", lower: 2)
        }
    }
}
