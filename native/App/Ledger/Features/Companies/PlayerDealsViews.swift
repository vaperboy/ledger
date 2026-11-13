import SwiftUI
import GameCore
import Countries
import Finance
import Events
import Businesses
import Simulation

struct FranchiseToPlayersCard: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var deals: PlayerDealsStore = PlayerDealsStore.shared
    var companyID: Int
    @State private var days = 7
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, e.isFranchisor(companyID: companyID) {
            let today: Int = PlayerDeals.today(e.state)
            let until: Int? = e.franchiseOpenUntil(companyID: companyID)
            MoreBlock("Offer to other players") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if let until, until >= today {
                        let left: Int = until - today + 1
                        Text("Open to other players for \(left) more \(left == 1 ? "day" : "days"). Players who apply show with the other applicants; talk to them the same way.")
                            .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                        QuietButton(title: "Close the offer", tint: Theme.loss, fullWidth: true) { askToClose() }
                    } else {
                        Text("Let other players see your franchise and apply for a unit. You choose how long the offer lasts; when it ends, players who have not signed leave.")
                            .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                        SegmentedPill(items: PlayerDeals.offerDays, title: { (d: Int) -> String in PlayerDeals.daysText(d) }, selection: $days)
                        QuietButton(title: "Offer to players", fullWidth: true) { open() }
                    }
                }
            }
            .confirmAction($pending)
            .task { deals.sync(store) }
        }
    }

    private func open() {
        let n: Int = days
        switch store.act({ $0.openFranchiseToPlayers(companyID: companyID, days: n) }) {
        case .ok?:
            Haptics.success()
            store.show("Your franchise is open to players for \(PlayerDeals.daysText(n)).", tone: "good")
            deals.sync(store)
        case .notFranchising?, .badDays?:
            Haptics.warning()
            store.show("The franchise could not be opened to players now.", tone: "warn")
        case nil:
            break
        }
    }

    private func askToClose() {
        pending = PendingAction(title: "Close the offer to players?", message: "Players who applied and have not signed leave. Units already signed stay.", button: "Close the offer", destructive: true) {
            store.act { $0.closeFranchiseToPlayers(companyID: companyID) }
            Haptics.tap()
            deals.sync(store)
        }
    }
}

struct PlayerFranchiseShelf: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var deals: PlayerDealsStore = PlayerDealsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let e = store.engine {
                let offers: [PlayerDeals.FranchiseListing] = deals.franchiseOffers(e)
                if !offers.isEmpty {
                    MoreBlock(title: "Run by players", card: false, trailing: { Text("\(offers.count)").textStyle(.caption, tint: Theme.inkFaint) }) {
                        ForEach(offers) { (l: PlayerDeals.FranchiseListing) in offer(e, l) }
                    }
                }
            }
        }
        .task { deals.sync(store) }
    }

    private func offer(_ e: GameEngine, _ l: PlayerDeals.FranchiseListing) -> some View {
        let today: Int = PlayerDeals.today(e.state)
        let cur: Currency = e.homeCurrency
        let brand: FranchiseBrands.Brand? = e.franchiseBrand("P:" + l.id)
        let fee: Double = brand.map { e.franchiseEntryFee($0) } ?? cur.scaledPrice(l.baseFee)
        let linked: Bool = deals.service.buyerLinkKeys.contains(l.linkKey)
        let left: Int = max(1, l.expiresDay - today + 1)
        let figures: [KeyFigures.Item] = [
            .init(label: "Entry fee", value: cur.tidyShort(fee)),
            .init(label: "Royalty", value: Currency.percent(l.royalty, decimals: 1)),
            .init(label: "Units", value: "\(l.units)"),
        ]
        return EntityCard {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    IconCircle(glyph: Glyph.person, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.brandName).textStyle(.headline, tint: Theme.ink).lineLimit(2)
                        Text("\(e.data.catalog[l.tradeID]?.name ?? l.tradeID) · run by \(l.ownerName)").textStyle(.caption, tint: Theme.inkSoft).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if l.isFriend { Chip(text: "Friend", tint: Theme.gold) }
                }
                FigureStrip(items: figures, columns: 3)
                Text("Brand \(FranchiseBrands.brandWord(l.strength).lowercased()) · open to applications for \(left) more \(left == 1 ? "day" : "days")")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                if linked {
                    Text("Not available: linked account").textStyle(.caption, tint: Theme.loss)
                } else if brand != nil {
                    Text("On your list of brands above. Apply there.").textStyle(.caption, tint: Theme.gain)
                } else {
                    QuietButton(title: "Take a look") { take(l) }
                }
            }
        }
    }

    private func take(_ l: PlayerDeals.FranchiseListing) {
        let added: String? = store.act({ $0.importPlayerFranchise(l) }) ?? nil
        if added != nil {
            Haptics.success()
            store.show("\(l.brandName) is on your list of brands above. Apply to start.", tone: "good")
        } else {
            Haptics.warning()
            store.show("This offer cannot be taken up now.", tone: "warn")
        }
    }
}

struct SaleToPlayersCard: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var deals: PlayerDealsStore = PlayerDealsStore.shared
    var companyID: Int
    @State private var days = 7

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let cur: Currency = e.currency(for: co)
            let today: Int = PlayerDeals.today(e.state)
            let until: Int? = e.playerSaleUntil(companyID: companyID)
            let listing: CompanySale.Listing? = CompanySale.listing(e.state, companyID: companyID)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Other players").capsLabel(Theme.ivoryFaint)
                if let until, until >= today {
                    let left: Int = until - today + 1
                    Text("Shown to other players for \(left) more \(left == 1 ? "day" : "days"), asking about \(cur.tidyShort(PlayerDealsStore.asking(e, companyID))). Their offers stand for two weeks.")
                        .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                    QuietButton(title: "Stop showing it to players", fullWidth: true) {
                        store.act { $0.stopSaleToPlayers(companyID: companyID) }
                        deals.sync(store)
                    }
                } else if (listing?.pct ?? 100) < 100 {
                    Text("Only a sale of the whole company can be shown to players.").textStyle(.caption, tint: Theme.inkSoft)
                } else {
                    Text("Let other players see \(co.name) and make offers. You choose how long it is shown; the asking price is a little over what it is worth.")
                        .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                    SegmentedPill(items: PlayerDeals.offerDays, title: { (d: Int) -> String in PlayerDeals.daysText(d) }, selection: $days)
                    QuietButton(title: listing == nil ? "Offer it to players" : "Show it to players", fullWidth: true) { show() }
                }
            }
            .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
            .task { deals.sync(store) }
        }
    }

    private func show() {
        let n: Int = days
        if store.act({ $0.startSaleToPlayers(companyID: companyID, days: n) }) == true {
            Haptics.success()
            store.show("Your company is shown to other players for \(PlayerDeals.daysText(n)).", tone: "good")
            deals.sync(store)
        } else {
            Haptics.warning()
            store.show("It could not be shown to players now.", tone: "warn")
        }
    }
}

struct PlayerCompanyOffers: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var deals: PlayerDealsStore = PlayerDealsStore.shared
    @State private var opened: Pick?

    struct Pick: Identifiable, Equatable { var id: String }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let e = store.engine {
                let list: [PlayerDeals.CompanyListing] = deals.companyOffers(e)
                if list.isEmpty {
                    EmptyState(glyph: Glyph.market, title: "No player sells a company now", message: "Offers come and go as players put their companies up.")
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, l: PlayerDeals.CompanyListing) in
                            if n > 0 { Hairline().padding(.leading, 40 + Theme.Space.m) }
                            row(e, l)
                        }
                    }
                }
            }
        }
        .task { deals.sync(store) }
        .centerSheet(item: $opened, category: .medium, tone: .investment) { (p: Pick) in
            PlayerCompanyOfferSheet(listingID: p.id, onClose: { opened = nil }).environmentObject(store)
        }
    }

    private func row(_ e: GameEngine, _ l: PlayerDeals.CompanyListing) -> some View {
        let linked: Bool = deals.service.buyerLinkKeys.contains(l.linkKey)
        let trade: String = e.data.catalog[l.tradeID]?.name ?? l.tradeID
        let place: String = e.data.countries.city(l.cityID, preferring: l.countryCode)?.city.name ?? ""
        let logo = ThumbSpec(kind: .logo, key: "player|\(l.id)", glyph: Glyph.person, initials: l.companyName, shape: .square)
        return LedgerRow(leading: .thumb(logo), title: l.companyName, subtitle: [trade, place, l.ownerName].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "),
                         value: e.homeCurrency.tidyShort(l.askPrice), valueNote: "asking", pill: linked ? "Linked account" : (l.isFriend ? "Friend" : nil),
                         pillTone: linked ? .warn : .good, lineLimit: 1, identifier: "player-company-\(l.id)", action: { opened = Pick(id: l.id) })
    }
}

struct PlayerCompanyOfferSheet: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var deals: PlayerDealsStore = PlayerDealsStore.shared
    var listingID: String
    var onClose: () -> Void
    @State private var multiple = 1.0
    @State private var round = 0
    @State private var reply: String?
    @State private var counter: Double?
    @State private var agreed: Double?
    @State private var message: String?

    var body: some View {
        if let e = store.engine, let l = deals.companyOffers(e).first(where: { $0.id == listingID }) {
            content(e, l)
        } else {
            Text("This company is no longer for sale.").popupText(.caption)
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ l: PlayerDeals.CompanyListing) -> some View {
        let cur: Currency = e.homeCurrency
        let today: Int = PlayerDeals.today(e.state)
        let left: Int = max(1, l.expiresDay - today + 1)
        let linked: Bool = deals.service.buyerLinkKeys.contains(l.linkKey)
        let figures: [KeyFigures.Item] = [
            .init(label: "Asking", value: cur.tidyShort(l.askPrice)),
            .init(label: "Takings a year", value: cur.tidyShort(l.yearlyRevenue)),
            .init(label: "Profit a year", value: cur.tidyShort(l.yearlyProfit), tint: l.yearlyProfit < 0 ? Theme.loss : Theme.ink),
        ]
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("\(e.data.catalog[l.tradeID]?.name ?? l.tradeID) · sold by \(l.ownerName) (\(l.profileCode))").popupText(.subtitle)
            KeyFigures(items: figures)
            Text("\(l.staff) \(l.staff == 1 ? "person" : "people") · reputation \(Int(saturating: l.reputation.rounded())) of 100 · trading \(l.weeksTrading) weeks · on offer for \(left) more \(left == 1 ? "day" : "days")")
                .popupText(.caption)
            Text("You buy the business and its customers. It opens as a new company of yours, and you pay for its set-up and for merging suppliers and systems.").popupText(.caption)
            Hairline()
            if linked {
                Text("Not available: linked account").popupText(.risk)
            } else if let price = agreed {
                purchase(e, l, price, cur)
            } else {
                offer(e, l, cur)
            }
            if let message { Text(message).popupText(.risk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(l.companyName)
    }

    private func priceNow(_ l: PlayerDeals.CompanyListing) -> Double { max(1000, (l.askPrice * multiple / 1000).rounded() * 1000) }

    @ViewBuilder private func offer(_ e: GameEngine, _ l: PlayerDeals.CompanyListing, _ cur: Currency) -> some View {
        let price: Double = priceNow(l)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("Your offer").popupText(.rowLabel)
            Text(cur.tidyShort(price)).popupText(.figure)
            Text(String(format: "%.0f%% of what they ask", multiple * 100)).popupText(.caption)
        }
        LedgerSlider(value: $multiple, in: 0.6...1.1, step: 0.01)
        if let reply { Text(reply).popupText(.body).fixedSize(horizontal: false, vertical: true) }
        if let counter {
            PopupOptionButton(title: "Accept their price \u{00B7} " + cur.tidyShort(counter)) { agreed = counter; message = nil }
        }
        PopupOptionButton(title: "Send the offer", highlighted: true) { send(e, l, price, cur) }
    }

    @ViewBuilder private func purchase(_ e: GameEngine, _ l: PlayerDeals.CompanyListing, _ price: Double, _ cur: Currency) -> some View {
        if let plan = e.playerCompanyBuyPlan(l, price: price) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("\(l.ownerName) agrees to \(cur.tidyShort(price)).").popupText(.body)
                line("Price", cur.tidyShort(plan.price))
                line("Set-up money for the new company", cur.tidyShort(plan.startupMoney))
                line("Merging suppliers and systems", cur.tidyShort(plan.integration))
                line("In all", cur.tidyShort(plan.cashNeeded))
                line("You have", cur.tidyShort(plan.cash))
            }
            if plan.affordable {
                PopupOptionButton(title: "Buy for \(cur.tidyShort(plan.cashNeeded))", highlighted: true) { buy(e, l, price) }
            } else {
                Text("You are \(cur.tidyShort(plan.cashNeeded - plan.cash)) short.").popupText(.risk)
            }
        } else {
            Text("This business cannot be set up here.").popupText(.risk)
        }
        QuietButton(title: "Back to the offer", fullWidth: true) { agreed = nil; message = nil }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).popupText(.caption)
            Spacer(minLength: Theme.Space.s)
            Text(value).popupText(.rowValue)
        }
    }

    private func send(_ e: GameEngine, _ l: PlayerDeals.CompanyListing, _ price: Double, _ cur: Currency) {
        let r: PlayerDeals.Reply = deals.service.makeOffer(listingID: l.id, price: price, round: round, today: PlayerDeals.today(e.state))
        round += 1
        counter = nil
        message = nil
        switch r {
        case .accept:
            Haptics.success()
            agreed = price
        case .counter(let c):
            Haptics.tap()
            reply = "\(l.ownerName) will do it for \(cur.tidyShort(c)), no less."
            counter = c
        case .refuse:
            Haptics.warning()
            reply = round >= 3 ? "\(l.ownerName) has stopped bargaining." : "That is far below what it is worth to them."
        }
    }

    private func buy(_ e: GameEngine, _ l: PlayerDeals.CompanyListing, _ price: Double) {
        let keys: Set<String> = deals.service.buyerLinkKeys
        switch store.act({ $0.buyPlayerCompany(l, price: price, buyerLinkKeys: keys) }) {
        case .ok(let id)?:
            deals.service.soldToPlayer(listingID: l.id)
            Haptics.success()
            store.show("You bought \(l.companyName). It opens as a new company of yours.", tone: "good")
            store.openCompany(id)
            onClose()
        case .notEnoughCash?:
            Haptics.warning()
            message = "Not enough cash for the price and the set-up."
        case .notAllowed(let why)?:
            Haptics.warning()
            message = why
        case nil:
            break
        }
    }
}
