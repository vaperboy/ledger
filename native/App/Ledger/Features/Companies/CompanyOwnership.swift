import SwiftUI
import Charts
import GameCore
import Countries
import Events
import Simulation

/// Owners, raising money and selling shares, in the Money tab of a company. Logic: `Funding`, `Shareholders`, `CompanySale`.
///
/// Layout: a control hero (your share as a serif figure, a stacked ownership bar and what the other owners can do), then sub-tabs.
/// Owners: the holders list with votes, mood and board seats, buy-backs and the dividend policy. Raise money: investors, pitches and
/// the offers on the table (a holding: listing and issuing shares). Sell shares: the engine's offers and listing a share for sale.
struct CompanyOwnershipSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var page: Part?
    @State private var pending: PendingAction?

    private enum Part: String, CaseIterable, Identifiable { case owners = "Owners", raise = "Raise money", sell = "Sell shares"; var id: String { rawValue } }

    /// One slice of the ownership bar.
    private struct Piece: Identifiable {
        var id: String
        var pct: Double
        var tint: Color
    }

    private var palette: [Color] { [Theme.slateBlue, Theme.gain, Theme.roseGold, Theme.goldLight, Theme.loss, Theme.ivoryMuted] }

    private var isOrdinary: Bool { company.form == .limited && company.type != "hold" }
    private var isHolding: Bool { company.type == "hold" }

    private var parts: [Part] {
        if isOrdinary { return [.owners, .raise, .sell] }
        if isHolding { return [.owners, .raise] }
        return [.owners]
    }

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            control
            owners(cur)
            if parts.count > 1 { moreTable }
        }
        .navigationDestination(item: $page) { (p: Part) in
            SettingsPage(title: p.rawValue, subtitle: company.name) { pageContent(p, cur) }
        }
        .confirmAction($pending)
    }

    /// Raising money and selling shares are bigger decisions: rows that open pages of their own.
    private var moreTable: some View {
        SettingsTable(heading: "Money and shares") {
            SettingsTableRow(title: Part.raise.rawValue, note: "New owners put money into the company", value: "Open") { page = .raise }
            if parts.contains(.sell) {
                SettingsTableRow(title: Part.sell.rawValue, note: "Sell some of your own shares", value: "\(Int(company.ownership.rounded()))% yours") { page = .sell }
            }
        }
    }

    @ViewBuilder private func pageContent(_ p: Part, _ cur: Currency) -> some View {
        switch p {
        case .owners: owners(cur)
        case .raise: raise(cur)
        case .sell: sell(cur)
        }
    }

    // MARK: Control

    private func pieces(_ owners: [Shareholders.Holder]) -> [Piece] {
        var out: [Piece] = [Piece(id: "You", pct: company.ownership, tint: Theme.gold)]
        for (n, h) in owners.enumerated() { out.append(Piece(id: h.name, pct: h.pct, tint: palette[n % palette.count])) }
        return out
    }

    private var control: some View {
        let owners = engine.owners(companyID: company.id)
        let all: [Piece] = pieces(owners)
        let power = Shareholders.power(company)
        let seats: Int = owners.filter { $0.boardSeat }.count
        let cells: [StatStrip.Cell] = [
            StatStrip.Cell(label: "Your votes", value: String(format: "%.1f%%", company.ownership)),
            StatStrip.Cell(label: "Other owners", value: String(format: "%.1f%%", Shareholders.outside(company))),
            StatStrip.Cell(label: "Board seats held", value: "\(seats)")
        ]
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("You own").capsLabel()
                    Spacer(minLength: 8)
                    GlyphView(glyph: Glyph.group, size: 17, weight: 1.6)
                }
                Text("\(Int(company.ownership.rounded()))%").font(.hero(34)).foregroundStyle(Theme.ivory)
                ownershipBar(all)
                Text(power.text).font(.system(size: 12)).foregroundStyle(power.kind == .control ? Theme.caution : Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                StatStrip(cells: cells)
            }
        }
    }

    private func ownershipBar(_ all: [Piece]) -> some View {
        let names: [String] = all.map { $0.id }
        let tints: [Color] = all.map { $0.tint }
        return Chart(all) { s in
            BarMark(x: .value("Share", s.pct), y: .value("Company", "Shares"), width: .ratio(1))
                .foregroundStyle(by: .value("Holder", s.id))
                .cornerRadius(2)
        }
        .chartForegroundStyleScale(domain: names, range: tints)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityLabel("Ownership: you \(Int(company.ownership.rounded())) percent")
    }

    // MARK: Owners

    @ViewBuilder private func owners(_ cur: Currency) -> some View {
        let list = engine.owners(companyID: company.id)
        let all: [Piece] = pieces(list)
        if list.isEmpty {
            Card(padding: 14, radius: Theme.Radius.row) {
                HStack(spacing: 12) {
                    IconCircle(glyph: Glyph.person, size: 38)
                    Text("You are the only owner.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                }
            }
        } else {
            ForEach(Array(list.enumerated()), id: \.element.id) { n, h in
                holderCard(h, tint: all[n + 1].tint, cur: cur)
            }
        }
        if isOrdinary { dividendPolicy }
    }

    private func holderCard(_ h: Shareholders.Holder, tint: Color, cur: Currency) -> some View {
        let id = company.id
        let sub: String = "\(Shareholders.profileNames[h.profile] ?? "") · mood: \(h.moodWord)"
        let buyBack: Double? = engine.buyBackPrice(companyID: id, holder: h.name)
        return Card(padding: 12, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconCircle(glyph: Glyph.person, size: 38, tint: tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                        Text(sub).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f%%", h.pct)).font(.system(size: 15, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                        if h.boardSeat { Chip(text: "Board seat", tint: Theme.gold) }
                    }
                }
                if let p = buyBack {
                    QuietButton(title: "Buy back for " + cur.tidyShort(p) + "…", fullWidth: true) {
                        pending = PendingAction(title: "Buy back \(h.name)'s \(String(format: "%.1f", h.pct))%?", message: "\(cur.tidyDisplay(p)) from your own cash. Their votes and dividends come back to you.", button: "Buy back", destructive: true) {
                            let ok = store.act { $0.buyBackStake(companyID: id, holder: h.name) } ?? false
                            if !ok { Haptics.warning() }
                            store.show(ok ? "You bought back \(h.name)'s stake for \(cur.tidyShort(p))." : "Not enough cash, or they will not sell now.", tone: ok ? "good" : "warn")
                        }
                    }
                }
            }
        }
    }

    private var dividendPolicy: some View {
        let id = company.id
        let chosen: String = engine.dividendPolicy(companyID: id)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: 8) {
                GlyphView(glyph: Glyph.cost, size: 15, weight: 1.6)
                Text("Dividend policy").capsLabel()
            }.padding(.horizontal, 2)
            ForEach(Shareholders.policies, id: \.self) { p in
                let name: String = Shareholders.policyNames[p] ?? p
                ChoiceCard(title: name, selected: chosen == p) {
                    store.settle(store.act { $0.setDividendPolicy(companyID: id, policy: p) }, "Dividend policy: \(name).", same: "That is already the dividend policy.")
                }
            }
        }
    }

    // MARK: Raise money

    @ViewBuilder private func raise(_ cur: Currency) -> some View {
        if isHolding { holdingRaise(cur) } else { investors(cur) }
    }

    private func investors(_ cur: Currency) -> some View {
        let id = company.id
        let amount: Double = engine.suggestedFundingAmount(companyID: id)
        let offers = engine.fundingOffers(companyID: id)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        IconCircle(glyph: Glyph.invest, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Investors").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ivoryFaint)
                            Text(engine.investorInterest(companyID: id).word).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        }
                    }
                    QuietButton(title: "Pitch for " + cur.tidyShort(amount), fullWidth: true) { pitch(amount) }
                    Text("A pitch brings offers over the coming weeks. Nothing is taken until you accept.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
            }
            if offers.isEmpty {
                Text("No offers on the table.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).padding(.horizontal, 2)
            }
            ForEach(offers) { o in offerCard(o, cur: cur) }
        }
    }

    private func pitch(_ amount: Double) {
        let id = company.id
        if let r = store.act({ $0.pitchToInvestors(companyID: id, amount: amount) }) {
            switch r {
            case .none: Haptics.warning(); store.show("No investor bit.", tone: "warn")
            case .tooSoon(let w): Haptics.warning(); store.show("Try again in \(w.weeksText).", tone: "warn")
            case .notLimited: Haptics.warning(); store.show("Only a limited company can pitch to investors.", tone: "warn")
            case .offers(let n): Haptics.success(); store.show("\(n) \(n == 1 ? "offer" : "offers") came in: see below. Nothing is taken until you accept.", tone: "good")
            }
        }
    }

    private func offerCard(_ o: Funding.FundOffer, cur: Currency) -> some View {
        let id = company.id
        let headline: String = "\(cur.tidyShort(o.amount)) for \(Int(o.pct.rounded()))%"
        return Card(padding: 12, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(o.name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text(o.says).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(headline).font(.system(size: 14, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                }
                WrapRow {
                    QuietButton(title: "Accept") {
                        pending = PendingAction(title: "Take \(cur.tidyShort(o.amount)) for \(Int(o.pct.rounded()))%?", message: "The money goes into the company. \(o.name) becomes an owner with votes and a share of profits; your share falls. This cannot be undone.", button: "Accept", destructive: true) {
                            let ok = store.act { $0.acceptFundingOffer(companyID: id, index: o.id) } ?? false
                            if !ok { Haptics.warning() } else { Haptics.success() }
                            store.show(ok ? "\(cur.tidyShort(o.amount)) is in the company; \(o.name) now owns \(Int(o.pct.rounded()))%." : "The offer has gone.", tone: ok ? "good" : "warn")
                        }
                    }
                    if !o.countered {
                        QuietButton(title: "Counter", tint: Theme.ivoryMuted) { store.settle(store.act { $0.counterFundingOffer(companyID: id, index: o.id) }, "Counter sent. Their answer replaces the offer.", same: "That offer has gone or was already countered.") }
                    }
                    QuietButton(title: "Decline", tint: Theme.loss) { store.settle(store.act { $0.declineFundingOffer(companyID: id, index: o.id) }, "Declined.", same: "That offer had already gone.") }
                }
            }
        }
    }

    // MARK: Holding: listing and issuing shares

    private func holdingRaise(_ cur: Currency) -> some View {
        let id = company.id
        let listed: Bool = engine.isListed(companyID: id)
        let goal: Double = engine.holdingValue(companyID: id) * 0.1
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        IconCircle(glyph: listed ? Glyph.check : Glyph.market, size: 38, tint: listed ? Theme.gain : Theme.gold)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Stock exchange").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ivoryFaint)
                            Text(listed ? "Listed on the exchange" : "Not listed").font(.system(size: 14.5, weight: .medium)).foregroundStyle(listed ? Theme.gain : Theme.ivory)
                        }
                    }
                    if !listed {
                        QuietButton(title: "Go public · fee " + cur.tidyShort(engine.listingFee) + "…", fullWidth: true) { confirmListing(cur) }
                    }
                }
            }
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Issue new shares").capsLabel()
                    WrapRow {
                        QuietButton(title: "Raise " + cur.tidyShort(goal) + " privately") { confirmRaise(goal, publicOffering: false, cur: cur) }
                        if listed { QuietButton(title: "Raise on the exchange") { confirmRaise(goal, publicOffering: true, cur: cur) } }
                    }
                    Text("New shares are issued for money, so your share shrinks and a fee is taken.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func confirmListing(_ cur: Currency) {
        let id = company.id
        pending = PendingAction(title: "List \(company.name) on the exchange?", message: "A bank takes the holding public for a fee of \(cur.tidyDisplay(engine.listingFee)). The shares can then be traded and raised on.", button: "Go public", destructive: true) {
            switch store.act({ $0.listHoldingOnExchange(companyID: id) }) {
            case .ok?: Haptics.success(); store.show("\(company.name) is listed on the exchange.", tone: "good")
            case .alreadyListed?: store.show("It is already listed.", tone: "n")
            case .tooSmall(let n)?: Haptics.warning(); store.show("Needs a value of at least " + cur.tidyShort(n) + ".", tone: "warn")
            case .notEnoughMoney(let n)?: Haptics.warning(); store.show("The fee needs " + cur.tidyShort(n) + ".", tone: "warn")
            case .notAHolding?: store.show("Only a holding company can go public.", tone: "warn")
            case nil: break
            }
        }
    }

    // MARK: Sell shares

    private func sell(_ cur: Currency) -> some View {
        let id = company.id
        let offers = engine.shareOffers(companyID: id).prefix(3)
        let columns: [TableColumn] = [TableColumn(title: "Share"), TableColumn(title: "You receive", width: 100)]
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            if !offers.isEmpty {
                Text("Offers from buyers now").capsLabel().padding(.horizontal, 2)
                SharpTable {
                    TableHeader(columns: columns)
                    ForEach(Array(offers), id: \.pct) { o in
                        TableRow(columns: columns, title: "\(o.pct)% of the company", note: "Gains are taxed", values: [cur.tidyShort(o.secondary)]) { confirmSale(o.pct, o.secondary, cur: cur) }
                    }
                }
            }
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        GlyphView(glyph: Glyph.arrowOut, size: 15, weight: 1.6)
                        Text("Look for a buyer").capsLabel()
                    }
                    HStack(spacing: 8) {
                        ForEach([10, 25, 34, 49], id: \.self) { p in
                            QuietButton(title: "\(p)%", fullWidth: true) { confirmListingForSale(p) }
                        }
                    }
                    Text("Buyers make offers over the coming weeks; nothing is sold until you accept one.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func confirmSale(_ pct: Int, _ secondary: Double, cur: Currency) {
        let id = company.id
        pending = PendingAction(title: "Sell \(pct)% of your shares?", message: "About \(cur.tidyDisplay(secondary)) comes to you (gains are taxed). The buyer gets votes and a share of every dividend; your control falls. This cannot be undone.", button: "Sell", destructive: true) {
            switch store.act({ $0.sellPrivateShares(companyID: id, percent: Double(pct), mode: "secondary") }) {
            case .ok(let v)?: Haptics.success(); store.show("Sold for \(cur.tidyShort(v)).", tone: "good")
            case .notLimited?: Haptics.warning(); store.show("Only a limited company can sell shares.", tone: "warn")
            case .tooMuch?: Haptics.warning(); store.show("That would cost you control.", tone: "warn")
            case nil: break
            default: Haptics.warning(); store.show("The owners blocked the sale.", tone: "warn")
            }
        }
    }

    private func confirmListingForSale(_ p: Int) {
        let id = company.id
        pending = PendingAction(title: "Look for a buyer for \(p)%?", message: "Buyers make offers over the coming weeks; nothing is sold until you accept one.", button: "List \(p)%") {
            let ok = store.act { $0.listSharesForSale(companyID: id, percent: p, broker: false) } ?? false
            if !ok { Haptics.warning() }
            store.show(ok ? "\(p)% listed. Offers arrive in the Inbox." : "Not possible now: it may already be listed, or would cost you control.", tone: ok ? "good" : "warn")
        }
    }

    /// New shares are issued for money: say what it costs before doing it, and report what the engine raised.
    private func confirmRaise(_ goal: Double, publicOffering: Bool, cur: Currency) {
        let id = company.id
        pending = PendingAction(title: "Raise about \(cur.tidyShort(goal))?",
                                message: "Benefit: the money goes into the holding. Cost: new shares are issued, so your share of it shrinks, and a fee is taken. Risk: it cannot be undone; the engine decides how much it raises and at what price.",
                                button: "Raise", destructive: true) {
            if let raised = store.act({ $0.raiseMoneyForHolding(holdingID: id, goal: goal, publicOffering: publicOffering) }) ?? nil {
                Haptics.success(); store.show("Raised " + cur.tidyShort(raised) + ", before the fee.", tone: "good")
            } else { Haptics.warning(); store.show("Nothing was raised.", tone: "warn") }
        }
    }
}
