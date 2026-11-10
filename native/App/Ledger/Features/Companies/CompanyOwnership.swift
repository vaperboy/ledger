import SwiftUI
import Charts
import GameCore
import Countries
import Events
import Simulation

struct CompanyOwnershipSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    enum Mode { case owners, raise }
    var mode: Mode = .owners
    @State private var pending: PendingAction?
    @State private var policyOpen = false

    private struct Piece: Identifiable {
        var id: String
        var pct: Double
        var tint: Color
    }

    private var palette: [Color] { [Theme.slateBlue, Theme.gain, Theme.roseGold, Theme.goldLight, Theme.loss, Theme.ivoryMuted] }

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            switch mode {
            case .owners:
                control
                owners(cur)
            case .raise:
                investors(cur)
            }
        }
        .confirmAction($pending)
        .centerSheet(isPresented: $policyOpen) { DividendPolicySheet(companyID: company.id).environmentObject(store) }
    }

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
        dividendPolicy
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

    private var dividendPolicy: some View {
        let chosen: String = engine.dividendPolicy(companyID: company.id)
        return SharpTable {
            SettingsTableRow(title: "Dividend policy", value: Shareholders.policyNames[chosen] ?? chosen, opens: .sheet) { policyOpen = true }
        }
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
            case .notLimited: Haptics.warning(); store.show("This company cannot pitch to investors.", tone: "warn")
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
                            store.show(ok ? "\(cur.tidyShort(o.amount)) is in your account; \(o.name) now owns \(Int(saturating: o.pct.rounded()))%." : "The offer has gone.", tone: ok ? "good" : "warn")
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
}
