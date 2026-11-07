import XCTest

/// Screenshots of the outside apps (TechPro, AirStay, Atlas, Marketplace, Market, Reviews, Luxury, Ventures) for a visual review.
/// Nothing asserts: a missed tap takes the screenshot anyway and the tour goes on.
final class ShotsAppsTests: FeatureTourCase {
    private var n = 0

    private func shot(_ name: String) {
        pause(0.8)
        n += 1
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = String(format: "Apps-%02d-%@", n, name)
        a.lifetime = .keepAlways
        add(a)
    }

    /// The screen, then the screen scrolled down once (long pages).
    private func shotLong(_ name: String, drags: Int = 1) {
        shot(name)
        for i in 0..<drags {
            dragPage(-520)
            shot(name + "-\(i + 2)")
        }
    }

    private func closeAnyPopup() {
        var k = 0
        while popupUp(0.5) && k < 3 { closePopup(prefer: ["confirm-cancel", "popup-close"]); k += 1 }
    }

    func testShots() {
        testDeadline = Date().addingTimeInterval(80 * 60)
        techPro()
        airStay()
        atlas()
        marketplace()
        luxury()
        others()
    }

    private func techPro() {
        guard openPhoneApp("TechPro Store") else { shot("techpro-not-opened"); return }
        shotLong("techpro-store", drags: 2)
        if openPhoneApp("TechPro Store"), tapID("tp-tab-Products", wait: 3) { shotLong("techpro-products") }
        if openPhoneApp("TechPro Store"), tapPrefix("tp-tile-", wait: 4) {
            shotLong("techpro-suppliers")
            if tapPrefix("tp-supplier-", wait: 3) {
                shotLong("techpro-product")
                if tapID("tp-add", wait: 3) { shot("techpro-added") }
            }
        }
        if tapID("tp-cart", wait: 3) {
            shotLong("techpro-basket")
            if tapID("tp-checkout", wait: 3) {
                shotLong("techpro-checkout", drags: 2)
                if tapID("tp-pay", wait: 3) {
                    shot("techpro-payment")
                    _ = tapID("tp-autofill", wait: 2)
                    if tapID("tp-continue", wait: 3) { shot("techpro-pay-confirm"); closeAnyPopup() }
                }
            }
        }
        if openPhoneApp("TechPro Store"), tapID("tp-tab-My orders", wait: 3) { shotLong("techpro-orders") }
        if openPhoneApp("TechPro Store"), tapID("tp-tab-My items", wait: 3) { shotLong("techpro-owned", drags: 2) }
    }

    private func airStay() {
        guard openPhoneApp("AirStay") else { shot("airstay-not-opened"); return }
        shotLong("airstay-search", drags: 2)
        if tapPrefix("stay-listing-", wait: 4) {
            shotLong("airstay-listing", drags: 2)
            if tapID("stay-rent", wait: 3) {
                shotLong("airstay-rent")
                if tapID("stay-continue", wait: 3) { shot("airstay-rent-confirm"); closeAnyPopup() }
            }
        }
        if openPhoneApp("AirStay"), tapID("stay-tab-Rented", wait: 3) { shotLong("airstay-rented") }
    }

    private func atlas() {
        guard openPhoneApp("Atlas Insurance") else { shot("atlas-not-opened"); return }
        shotLong("atlas-cover", drags: 3)
        if openPhoneApp("Atlas Insurance"), tapID("atlas-get-quote", wait: 3) || tapPrefix("atlas-policy-", wait: 2) {
            shotLong("atlas-quote", drags: 2)
            if tapID("atlas-confirm", wait: 3) { shot("atlas-quote-confirm"); closeAnyPopup() }
        }
        if openPhoneApp("Atlas Insurance"), tapPrefix("atlas-cancel-", wait: 4) { shot("atlas-cancel-confirm"); closeAnyPopup() }
        if openPhoneApp("Atlas Insurance"), tapID("atlas-advisers", wait: 4) { shotLong("atlas-advisers") }
    }

    private func marketplace() {
        guard openPhoneApp("Marketplace") else { shot("marketplace-not-opened"); return }
        shotLong("marketplace-browse")
        if tapPrefix("mk-listing-", wait: 4) {
            shotLong("marketplace-listing")
            if tapID("mk-discuss", wait: 3) { shot("marketplace-talk"); closeAnyPopup() }
            if tapID("mk-buy", wait: 3) { shot("marketplace-buy-confirm"); closeAnyPopup() }
        }
    }

    private func luxury() {
        guard openPhoneApp("Luxury") else { shot("luxury-not-opened"); return }
        pause(1.5)
        if has("luxury-apply", wait: 3) {
            shot("luxury-gate")
            _ = tapID("luxury-apply", wait: 2)
            closeAnyPopup()
            _ = openPhoneApp("Luxury")
        }
        shotLong("luxury-showroom", drags: 2)
        if openPhoneApp("Luxury"), tapID("luxury-hero", wait: 3) || tapPrefix("luxury-inspect-", wait: 2) {
            shot("luxury-item")
            dragPage(-400)
            shot("luxury-item-2")
            closeAnyPopup()
        }
        if openPhoneApp("Luxury"), tapID("luxury-tab-vault", wait: 3) {
            shotLong("luxury-vault")
            if tapPrefix("luxury-inspect-", wait: 2) { shot("luxury-inspect"); closeAnyPopup() }
        }
    }

    private func others() {
        if openPhoneApp("Market") { shotLong("market", drags: 2) } else { shot("market-not-opened") }
        if openPhoneApp("Reviews") { shotLong("reviews", drags: 2) } else { shot("reviews-not-opened") }
        // The Ventures app is the Ventures tab's "Ideas and startups" part.
        if goTab("Ventures"), tapLabel("Ideas and startups", wait: 3) {
            shotLong("ventures-feed", drags: 2)
            if tapPrefix("ventures-part-", wait: 3) { shotLong("ventures-portfolio") }
        } else { shot("ventures-not-opened") }
    }
}
