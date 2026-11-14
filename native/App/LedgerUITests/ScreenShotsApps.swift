import XCTest

extension ScreenShotsTests {

    func testD_AppsMoneyAndMarket() {
        letter = "D"
        phoneApp("Bank", "app-bank")
        lower("app-bank-lower", on: appOpen, why: "the Bank did not open")
        appPart("app-bank-statements", "bank-tab-Statements", strip: "bank-tab-")
        phoneApp("Stats", "app-stats")
        page("app-stats-reports") { inApp("no stats-reports row") { seekID("stats-reports") } }
        page("app-stats-money") { inApp("no stats-money row") { seekID("stats-money") } }
        page("app-stats-annual") { inApp("no stats-annual row: no finished year in this game") { seekID("stats-annual") } }
        phoneApp("Insurance", "app-insurance")
        phoneApp("Market", "app-market")
        for part in ["Invest", "Exchange"] {
            appPart("app-market-" + part.lowercased(), "market-tab-" + part, strip: "market-tab-")
        }
        phoneApp("Luxury", "app-luxury")
        appPart("app-luxury-vault", "luxury-tab-vault", strip: "luxury-tab-")
    }

    func testE_AppsShopsAndWorld() {
        letter = "E"
        phoneApp("Marketplace", "app-marketplace")
        phoneApp("Auctions", "app-auctions")
        phoneApp("AirStay", "app-airstay")
        phoneApp("TechPro", "app-techpro")
        phoneApp("Reviews", "app-reviews")
        phoneApp("Rankings", "app-rankings")
        screen("app-rankings-second-board") {
            inApp("only one board kind") {
                let kinds: [String] = ids(prefix: "board-kind-", wait: 2)
                guard kinds.count > 1 else { return false }
                return tapInStrip(kinds[1], stripPrefix: "board-kind-")
            }
        }
        phoneApp("World", "app-world")
        for part in ["Countries", "People"] {
            appPart("app-world-" + part.lowercased(), "world-tab-" + part, strip: "world-tab-")
        }
    }

    func testF_AppsDailyAndYou() {
        letter = "F"
        phoneApp("Inbox", "app-inbox")
        page("app-inbox-message") { inApp("no message row in the Inbox") { seekID("inbox-row") } }
        phoneApp("News", "app-news")
        for part in ["players", "government", "weather"] {
            appPart("app-news-" + part, "news-section-" + part, strip: "news-section-")
        }
        phoneApp("Desk", "app-desk")
        phoneApp("Settings", "app-settings")
        lower("app-settings-lower", on: appOpen, why: "Settings did not open")
        page("app-settings-save-slots") { inApp("no Save slots row") { seekText("Save slots") } }
        phoneApp("Profile", "app-profile")
        lower("app-profile-lower", on: appOpen, why: "the Profile did not open")
        page("app-profile-trophies") { inApp("no profile-trophies-all link") { seekID("profile-trophies-all") } }
    }

    // One played day pays the gold for the levels the showcase game already has.
    private func playOneDay() {
        guard goTab("Home"), tapID("next-day", wait: 4) else { return }
        let first: [String] = ["report-continue", "daily-continue", "celebration-claim", "celebration-dismiss", "alert-continue"]
        var n = 0
        while n < 8 && popupUp(n == 0 ? 6 : 2) {
            closePopup(prefer: first)
            n += 1
        }
    }

    func testG_StoreSeasonAndLootBox() {
        letter = "G"
        act { playOneDay() }
        screen("store-1-top") {
            appOpen = goTab("Store")
            return ok(appOpen, "no Store tab")
        }
        scrolled("store", on: appOpen, why: "the Store did not open", pages: 8)
        popup("store-redeem-code") {
            guard storeTop() else { return "no Store tab" }
            return ok(seekID("store-redeem", drags: 14), "no gift code row")
        }
        popup("store-odds") {
            guard storeTop() else { return "no Store tab" }
            return ok(seekID("box-info", drags: 14), "no odds button")
        }
        popup("store-buy-confirm") {
            guard storeTop() else { return "no Store tab" }
            return ok(seek(drags: 14) { (h: Hit) -> Bool in h.type == .button && h.enabled && h.id.hasPrefix("shelf-") }, "no shelf item left to buy")
        }
        page("store-save-slots") {
            guard storeTop() else { return "no Store tab" }
            return ok(seekID("store-shelf", drags: 14), "no save slots link")
        }
        var season = false
        screen("app-goals") {
            _ = openApp("Goals")
            return ok(has("goals-app", wait: 2), "no Goals tile on the Phone grid")
        }
        for tab in ["Weekly", "Season", "Long-term"] {
            screen("goals-" + tab.lowercased()) { when(has("goals-app", wait: 1), off: "Goals did not open", "no \(tab) tab") { seekLabel(tab) } }
        }
        screen("app-season") {
            season = has("goals-pass", wait: 1) && tapID("goals-pass")
            return ok(season, "no battle pass strip on the Goals screen")
        }
        for part in ["Collection"] {
            screen("season-" + part.lowercased()) { when(season, off: "the Season pass did not open", "no \(part) tab") { seekLabel(part) } }
        }
        screen("season-claimed", settle: 2) {
            guard season else { return "the Season pass did not open" }
            guard seekLabel("Rewards") else { return "no Rewards tab" }
            return ok(seekLabelPrefix("Claim "), "no reward ready to claim in this game")
        }
        act { clearPopups() }
        var box = false
        screen("loot-box") {
            guard storeTop() else { return "the Store did not open" }
            guard seek(drags: 14, { (h: Hit) -> Bool in h.type == .button && h.id.hasPrefix("store-box-") }) else { return "no box in stock and no paid boxes offered here" }
            box = has("box-open", wait: 4)
            return ok(box, "the box page did not open")
        }
        var outcome = "none"
        screen("loot-box-confirm") {
            guard box else { return "the box page did not open" }
            guard tapEnabled("box-open", wait: 2) else { return "Open is disabled: no box in stock, or paid boxes are not offered here" }
            pause(1.5)
            if onScreenText("You opened") {
                outcome = "opened"
                return "no confirmation was asked: the box came from stock"
            }
            if onScreenText("Not enough gold") {
                outcome = "short"
                return "no confirmation was asked: not enough gold"
            }
            guard has("confirm-go", wait: 2) else { return "nothing happened after Open" }
            outcome = "confirm"
            return nil
        }
        act {
            guard outcome == "confirm" else { return }
            closePopup(prefer: ["confirm-go"])
            let result: Hit? = find(wait: 8, { (h: Hit) -> Bool in h.label.localizedCaseInsensitiveContains("You opened") })
            if result != nil { outcome = "opened" } else if onScreenText("Not enough gold") { outcome = "short" } else { outcome = "none" }
        }
        screen("loot-box-opening", settle: 0.2) { ok(outcome == "opened", "no box was opened") }
        screen("loot-box-opened", settle: 6) { ok(outcome == "opened", "no box was opened") }
        screen("loot-box-not-enough-gold") { ok(outcome == "short", "not shown: gold was enough, or no box could be tried") }
        act { clearPopups(4) }
        page("store-collection") {
            guard storeTop() else { return "the Store did not open" }
            return ok(seek(drags: 14, { (h: Hit) -> Bool in (h.type == .button || h.type == .cell) && h.label.localizedCaseInsensitiveContains("Artifacts and cards") }), "no Artifacts and cards row")
        }
    }

    func testH_PlayerCustomise() {
        letter = "H"
        var custom = false
        screen("customise-card") {
            guard openApp("Profile") == nil else { return "the Profile app did not open" }
            custom = seekID("profile-customise") && buttonUp(prefix: "customise-part-", wait: 4)
            return ok(custom, "no profile-customise button, or its page did not open")
        }
        var character = false
        screen("customise-character") {
            guard custom else { return "the customise page did not open" }
            character = tapInStrip("customise-part-character", stripPrefix: "customise-part-") && buttonUp(prefix: "customise-look-", wait: 3)
            return ok(character, "no customise-part-character tile, or it has no look tabs")
        }
        for look in ["skin", "hair", "outfit"] {
            screen("customise-character-" + look) {
                when(character, off: "the character part did not open", "no customise-look-\(look) segment") { tapInStrip("customise-look-" + look, stripPrefix: "customise-look-") }
            }
        }
        for part in ["backdrop", "flair"] {
            screen("customise-" + part) {
                when(custom, off: "the customise page did not open", "no customise-part-\(part) chip") { tapInStrip("customise-part-" + part, stripPrefix: "customise-part-") }
            }
        }
        page("profile-friends") {
            guard openApp("Profile") == nil else { return "the Profile app did not open" }
            return ok(seekID("profile-add-friend"), "no profile-add-friend link")
        }
    }
}
