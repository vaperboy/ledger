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
        for part in ["Companies", "Invest", "Exchange"] {
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
        phoneApp("Store", "app-store")
        lower("app-store-lower", on: appOpen, why: "the Store did not open")
        screen("store-plans") { inApp("the plans sheet did not open") { tapID("store-plans") && popupUp(3) } }
        screen("store-plans-lower") {
            guard popupUp() else { return "the plans sheet is not open" }
            dragPage(-420)
            return nil
        }
        act { clearPopups() }
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
            guard openApp("Store") == nil else { return "the Store did not open" }
            guard seekText("Open it") || seekPrefix("store-box-") else { return "no box in stock and no paid boxes offered here" }
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
            guard openApp("Store") == nil else { return "the Store did not open" }
            return ok(seekText("Artifacts and cards"), "no Artifacts and cards row")
        }
        page("store-cosmetics") {
            guard openApp("Store") == nil else { return "the Store did not open" }
            return ok(seekText("Cosmetics and bundles"), "no Cosmetics and bundles row")
        }
    }

    func testH_PlayerCustomise() {
        letter = "H"
        var custom = false
        screen("customise-icon") {
            guard openApp("Profile") == nil else { return "the Profile app did not open" }
            custom = seekID("profile-customise") && has("customise-part-icon", wait: 4)
            return ok(custom, "no profile-customise button, or its page did not open")
        }
        for part in ["card", "plate", "backdrop", "theme", "flair", "colour", "badge", "showcase"] {
            screen("customise-" + part) {
                when(custom, off: "the customise page did not open", "no customise-part-\(part) chip") { tapInStrip("customise-part-" + part, stripPrefix: "customise-part-") }
            }
        }
    }
}
