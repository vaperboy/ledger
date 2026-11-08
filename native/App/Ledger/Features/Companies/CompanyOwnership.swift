import SwiftUI
import Charts
import GameCore
import Countries
import Events
import Simulation

/// Owners, raising money and issuing or selling shares, in Group > Ownership. Logic: `Funding`, `Shareholders`, `CompanySale`.
///
/// `mode` picks the page: owners (a control hero with your share, a stacked ownership bar and what the other owners can do, then the holders
/// with votes, mood, buy-backs and the dividend policy), raise (investors, pitches and offers; a holding: listing and issuing shares) or
/// shares (offers for blocks of your shares and new shares for an investor). Looking for a buyer for a stake is a route in `SaleRoutePicker`.
struct CompanyOwnershipSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    enum Mode { case owners, raise, shares }
    var mode: Mode = .owners
    @State private var pending: PendingAction?
    @State private var policyOpen = false

    /// One slice of the ownership bar.
    private struct Piece: Identifiable {
        var id: String
        var pct: Double
        var tint: Color
    }

    private var palette: [Color] { [Theme.slateBlue, Theme.gain, Theme.roseGold, Theme.goldLight, Theme.loss, Theme.ivoryMuted] }

    private var isOrdinary: Bool { company.form == .limited && company.type != "hold" }
    private var isHolding: Bool { company.type == "hold" }

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            switch mode {
            case .owners:
                control
                owners(cur)
            case .raise:
                raise(cur)
            case .shares:
                if isOrdinary { sell(cur) } else { Text("Only a limited company has shares to issue or sell.").textStyle(.caption, tint: Theme.inkSoft) }
            }
        }
        .confirmAction($pending)
        .centerSheet(isPresented: $policyOpen) { DividendPolicySheet(companyID: company.id).environmentObject(store) }
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
        return Card(padding: Theme.Space.l, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("You own").capsLabel()
                    Spacer(minLength: 8)
                    GlyphView(glyph: Glyph.group, size: 17, weight: 1.6)
                }
                Text("\(Int(saturating: company.ownership.rounded()))%").textStyle(.display, tint: Theme.ink)
                ownershipBar(all)
                Text(power.text).textStyle(.caption, tint: power.kind == .control ? Theme.warn : Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                StatStrip(cells: cells)
                if let t = engine.capTable(companyID: company.id) {
                    Text("\(t.total) shares in issue, \(t.you) of them yours.").textStyle(.caption, tint: Theme.inkFaint)
                }
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .accessibilityLabel("Ownership: you \(Int(saturating: company.ownership.rounded())) percent")
    }

    // MARK: Owners

    @ViewBuilder private func owners(_ cur: Currency) -> some View {
        let list = engine.owners(companyID: company.id)
        let all: [Piece] = pieces(list)
        if list.isEmpty {
            Card(padding: Theme.Space.l, radius: Theme.Radius.row) {
                HStack(spacing: Theme.Space.m) {
                    IconCircle(glyph: Glyph.person, size: 38)
                    Text("You are the only owner.").textStyle(.body, tint: Theme.inkSoft)
                }
            }
        } else {
            ForEach(Array(list.enumerated()), id: \.element.id) { n, h in
                if n > 0 { Hairline() }
                holderCard(h, tint: all[n + 1].tint, cur: cur)
            }
        }
        if isOrdinary { dividendPolicy }
    }

    private func holderCard(_ h: Shareholders.Holder, tint: Color, cur: Currency) -> some View {
        let id = company.id
        let held: Int = engine.capTable(companyID: company.id)?.holders.first { $0.name == h.name }?.shares ?? 0
        let sub: String = "\(Shareholders.profileNames[h.profile] ?? "") · mood: \(h.moodWord)" + (held > 0 ? " · \(held) shares" : "")
        let buyBack: Double? = engine.buyBackPrice(companyID: id, holder: h.name)
        return Card(padding: Theme.Space.m, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    IconCircle(glyph: Glyph.person, size: 38, tint: tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.name).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(2)
                        Text(sub).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                        Text(String(format: "%.1f%%", h.pct)).textStyle(.headline, tint: Theme.ink, numeric: true)
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

    /// One home for the policy: the same sheet as the group's Money page (`DividendPolicySheet`).
    private var dividendPolicy: some View {
        let chosen: String = engine.dividendPolicy(companyID: company.id)
        return SharpTable {
            SettingsTableRow(title: "Dividend policy", value: Shareholders.policyNames[chosen] ?? chosen, opens: .sheet) { policyOpen = true }
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
            Card(padding: Theme.Space.l, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.m) {
                        IconCircle(glyph: Glyph.invest, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Investors").textStyle(.caption, tint: Theme.inkFaint, weight: .medium)
                            Text(engine.investorInterest(companyID: id).word).textStyle(.body, tint: Theme.ink, weight: .medium)
                        }
                    }
                    Button("Pitch for " + cur.tidyShort(amount)) { Haptics.tap(); pitch(amount) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("raise-pitch")
                    Text("A pitch brings offers over the coming weeks. Nothing is taken until you accept.").textStyle(.caption, tint: Theme.inkFaint)
                }
            }
            if offers.isEmpty {
                Text("No offers on the table.").textStyle(.caption, tint: Theme.inkFaint).padding(.horizontal, Theme.Space.xxs)
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
        let headline: String = "\(cur.tidyShort(o.amount)) for \(Int(saturating: o.pct.rounded()))%"
        return Card(padding: Theme.Space.m, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(o.name).textStyle(.body, tint: Theme.ink, weight: .medium)
                        Text(o.says).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(headline).textStyle(.body, tint: Theme.ink, numeric: true, weight: .medium)
                }
                WrapRow {
                    QuietButton(title: "Accept") {
                        pending = PendingAction(title: "Take \(cur.tidyShort(o.amount)) for \(Int(saturating: o.pct.rounded()))%?", message: DealText.describe(engine.fundingOfferTerms(companyID: id, offerIndex: o.id), cur, companyName: company.name) + "\nThis cannot be undone.", button: "Accept", destructive: true) {
                            let ok = store.act { $0.acceptFundingOffer(companyID: id, index: o.id) } ?? false
                            if !ok { Haptics.warning() } else { Haptics.success() }
                            store.show(ok ? "\(cur.tidyShort(o.amount)) is in the company; \(o.name) now owns \(Int(saturating: o.pct.rounded()))%." : "The offer has gone.", tone: ok ? "good" : "warn")
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
            Card(padding: Theme.Space.l, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.m) {
                        IconCircle(glyph: listed ? Glyph.check : Glyph.market, size: 38, tint: listed ? Theme.gain : Theme.gold)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Stock exchange").textStyle(.caption, tint: Theme.inkFaint, weight: .medium)
                            Text(listed ? "Listed on the exchange" : "Not listed").textStyle(.body, tint: listed ? Theme.gain : Theme.ink, weight: .medium)
                        }
                    }
                    if !listed {
                        QuietButton(title: "Go public · fee " + cur.tidyShort(engine.listingFee) + "…", fullWidth: true) { confirmListing(cur) }
                    }
                }
            }
            Card(padding: Theme.Space.l, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Issue new shares").capsLabel()
                    WrapRow {
                        QuietButton(title: "Raise " + cur.tidyShort(goal) + " privately") { confirmRaise(goal, publicOffering: false, cur: cur) }
                        if listed { QuietButton(title: "Raise on the exchange") { confirmRaise(goal, publicOffering: true, cur: cur) } }
                    }
                    Text("New shares are issued for money, so your share shrinks and a fee is taken.").textStyle(.caption, tint: Theme.inkFaint)
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
                Text("Offers from buyers now").capsLabel().padding(.horizontal, Theme.Space.xxs)
                SharpTable {
                    TableHeader(columns: columns)
                    ForEach(Array(offers), id: \.pct) { o in
                        TableRow(columns: columns, title: "\(o.pct)% of the company", note: "Gains are taxed", values: [cur.tidyShort(o.secondary)]) { confirmSale(o.pct, o.secondary, cur: cur) }
                    }
                }
            }
            Card(padding: Theme.Space.l, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("New shares for a private investor").capsLabel()
                    HStack(spacing: Theme.Space.s) {
                        ForEach([5, 10, 20], id: \.self) { p in
                            QuietButton(title: "\(p)%", fullWidth: true) { confirmNewShares(p, cur: cur) }
                        }
                    }
                    Text("The company issues new shares and receives the money; every owner, you included, is diluted. Different from selling some of your own shares above.").textStyle(.caption, tint: Theme.inkFaint)
                }
            }
        }
    }

    private func confirmSale(_ pct: Int, _ secondary: Double, cur: Currency) {
        let id = company.id
        pending = PendingAction(title: "Sell \(pct)% of your shares?", message: DealText.describe(engine.shareSaleTerms(companyID: id, percent: Double(pct), mode: "secondary"), cur, companyName: company.name) + "\nThe buyer gets votes and a share of every dividend. This cannot be undone.", button: "Sell", destructive: true) {
            switch store.act({ $0.sellPrivateShares(companyID: id, percent: Double(pct), mode: "secondary") }) {
            case .ok(let v)?: Haptics.success(); store.show("Sold for \(cur.tidyShort(v)).", tone: "good")
            case .notLimited?: Haptics.warning(); store.show("Only a limited company can sell shares.", tone: "warn")
            case .tooMuch?: Haptics.warning(); store.show("That would cost you control.", tone: "warn")
            case nil: break
            default: Haptics.warning(); store.show("The owners blocked the sale.", tone: "warn")
            }
        }
    }

    private func confirmNewShares(_ pct: Int, cur: Currency) {
        let id = company.id
        pending = PendingAction(title: "Issue new shares for \(pct)% of the company?", message: DealText.describe(engine.shareSaleTerms(companyID: id, percent: Double(pct), mode: "primary"), cur, companyName: company.name) + "\nThis cannot be undone.", button: "Issue the shares", destructive: true) {
            switch store.act({ $0.sellPrivateShares(companyID: id, percent: Double(pct), mode: "primary") }) {
            case .ok(let v)?: Haptics.success(); store.show(cur.tidyShort(v) + " went into the company.", tone: "good")
            case .tooMuch?: Haptics.warning(); store.show("That would cost you control.", tone: "warn")
            case .blocked?: Haptics.warning(); store.show("The other owners block new shares for now.", tone: "warn")
            default: Haptics.warning(); store.show("Not possible now.", tone: "warn")
            }
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
