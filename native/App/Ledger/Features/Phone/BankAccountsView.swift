import SwiftUI
import Charts
import GameCore
import Countries
import Simulation

/// Bank, pick an account (BankAccounts.dc.html): the cash total of every account with what is due in 30 days, then YOU (personal) and
/// YOUR COMPANIES. Loans are not an account: a row only says how many loans the account carries. Investing is in the Market app.
struct BankAccountsScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var onPick: (BankAccountID) -> Void
    @Environment(Entitlements.self) private var ent
    @State private var givingOpen = false
    @State private var move: BankMoveKind?

    var body: some View {
        if let e = store.engine {
            let all = e.bankAccounts()
            let you: [BankAccountRow] = all.rows.filter { $0.kind == .personal }
            let companies: [BankAccountRow] = all.rows.filter { $0.kind == .company }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    totalCard(all)
                    BankWealthCard(engine: e)
                    BankHomeRing(all: all, engine: e)
                    roundButtons(all)
                    billsLink(all, e)
                    givingLink(e)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOU").capsLabel()
                        ForEach(you) { r in row(r, e) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR COMPANIES").capsLabel()
                        if companies.isEmpty {
                            EmptyState(glyph: BankGlyph.company, title: "No company yet", message: "Its account appears here once it exists.", centered: false)
                        }
                        ForEach(companies) { r in row(r, e) }
                    }
                    Text("Loans belong to the account they were taken for. Open an account and choose Loans.")
                        .textStyle(.caption, tint: P.inkFaint).padding(.horizontal, 4)
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).noSidewaysDrag().scrollBounceBehavior(.basedOnSize)
            .centerSheet(item: $move) { kind in BankMoveSheet(account: .personal, kind: kind) }
        }
    }

    private func roundButtons(_ all: BankAccounts) -> some View {
        HStack(spacing: 0) {
            BankRoundButton(glyph: BankGlyph.deposit, title: "Deposit") { move = .deposit }
            BankRoundButton(glyph: BankGlyph.withdraw, title: "Send") { move = .withdraw }
            BankRoundButton(glyph: BankGlyph.transfer, title: "Transfer") { move = .transfer }
        }
        .accessibilityIdentifier("bank-round-actions")
    }

    /// Gifts, sponsorships and the foundation are paid from the personal account, so they live in the Bank (they used to sit in Group).
    private func givingLink(_ e: GameEngine) -> some View {
        let n: Int = e.givingMarks.count
        let sub: String = "\(n) \(n == 1 ? "mark" : "marks")" + (e.foundation != nil ? " \u{00B7} foundation running" : "")
        return Button { ent.run(.luxuryGivingFootball, "Giving back") { givingOpen = true } } label: {
            CardRow(glyph: Glyph.richList, title: "Giving back", subtitle: "Gifts, sponsorships and your foundation \u{00B7} " + sub)
                .overlay(alignment: .topTrailing) { ProMark(feature: .luxuryGivingFootball).padding(8) }
        }
        .buttonStyle(PressableStyle())
        .navigationDestination(isPresented: $givingOpen) { GivingView() }
        .accessibilityIdentifier("bank-giving")
    }

    private func billsLink(_ all: BankAccounts, _ e: GameEngine) -> some View {
        let count: Int = e.financeOverview().upcoming.count
        let sub: String = count == 0 ? "Nothing is due" : "\(count) coming · \(store.short(all.dueWithin30Days)) due in 30 days"
        return NavigationLink {
            BankAllBillsScreen()
        } label: {
            CardRow(glyph: BankGlyph.bill, title: "Bills", subtitle: sub)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("bank-all-bills")
    }

    /// The balance on warm ivory, as in the Banking mockup: the cash of every account (investments are in the Market app), what falls due
    /// in 30 days and whether it is covered.
    private func totalCard(_ all: BankAccounts) -> some View {
        let invested: Double = all.rows.filter { (r: BankAccountRow) -> Bool in r.kind == .investments }.reduce(0) { (a: Double, r: BankAccountRow) -> Double in a + r.balance }
        let cash: Double = all.total - invested
        let totalText: String = store.short(cash)
        let dueText: String = store.short(all.dueWithin30Days)
        return IvoryPanel {
            BankTotalPanel(totalText: totalText, negative: cash < 0, dueText: dueText, covered: all.isCovered)
        }
    }

    private func row(_ r: BankAccountRow, _ e: GameEngine) -> some View {
        let co: Company? = r.companyID.flatMap { e.state.company($0) }
        let fmt = BankFmt(store: store, company: co)
        let glyph: String = r.kind == .personal ? Glyph.person : BankGlyph.company
        let note: String = rowNote(r, fmt)
        let value: String = fmt.short(r.balance)
        let tint: Color = r.balance < 0 ? P.loss : P.ink
        return Button { Haptics.tap(); onPick(r.id) } label: {
            CardRow(glyph: glyph, title: r.name, subtitle: note, value: value, valueTint: tint, thumb: co.map { ThumbSpec(kind: .trade, key: $0.type, glyph: glyph) })
        }
        .newGroupMarker(.bank, store.messageItemIDs(.bank, companyID: r.companyID ?? 0), alignment: .topLeading)
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("bank-account-\(r.id.id)")
    }

    private func rowNote(_ r: BankAccountRow, _ fmt: BankFmt) -> String {
        var parts: [String] = []
        switch r.kind {
        case .personal:
            if let rate = r.savingsRate { parts.append("Savings \(Currency.percent(rate, decimals: 2))") }
            if let s = r.savings, s > 0 { parts.append(fmt.short(s) + " saved") }
        case .investments: break
        case .company: parts.append(r.detail)
        }
        if r.loanCount > 0 { parts.append("\(r.loanCount) loan\(r.loanCount == 1 ? "" : "s")") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Where the money is: a ring over the accounts that hold some (personal current account, savings, each company), the five
/// biggest named and the rest together. Only drawn when at least two places hold money; one place is not an allocation.
struct BankHomeRing: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var all: BankAccounts
    var engine: GameEngine

    private var palette: [Color] { [P.accent, Theme.roseGold, Theme.slateBlue, P.gain, P.inkSoft, P.inkDim] }

    var body: some View {
        let parts: [PortfolioRingCard.Slice] = slices()
        if parts.count >= 2 {
            PortfolioRingCard(slices: parts, cur: engine.homeCurrency, title: "WHERE YOUR MONEY IS", centerLabel: "Total")
        }
    }

    private func slices() -> [PortfolioRingCard.Slice] {
        var raw: [(String, Double)] = []
        for r in all.rows where r.kind != .investments {
            if r.balance > 0 { raw.append((r.kind == .personal ? "Current account" : r.name, r.balance)) }
            if let s = r.savings, s > 0 { raw.append(("Savings", s)) }
        }
        raw.sort { $0.1 > $1.1 }
        var out: [PortfolioRingCard.Slice] = []
        for (i, p) in raw.prefix(5).enumerated() {
            out.append(PortfolioRingCard.Slice(id: "\(i)-\(p.0)", name: p.0, value: p.1, tint: palette[i % palette.count]))
        }
        let rest: Double = raw.dropFirst(5).reduce(0) { $0 + $1.1 }
        if rest > 0 { out.append(PortfolioRingCard.Slice(id: "other", name: "Other", value: rest, tint: palette[5])) }
        return out
    }
}

/// The ring of where the money is: a donut of the parts with the total in the middle, and the shares beside it.
struct PortfolioRingCard: View {
    @Environment(\.outsidePalette) private var P
    struct Slice: Identifiable { var id: String; var name: String; var value: Double; var tint: Color }
    var slices: [Slice]
    var cur: Currency
    var title = "PORTFOLIO"
    var centerLabel = "Invested"

    var body: some View {
        let total: Double = slices.reduce(0) { $0 + max(0, $1.value) }
        let live: [Slice] = slices.filter { $0.value > 0 }
        Card(padding: 16, radius: Theme.Radius.hero) {
            HStack(spacing: 18) {
                ring(total, live)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).capsLabel()
                    ForEach(slices) { s in
                        HStack(spacing: 8) {
                            Circle().fill(s.tint).frame(width: 8, height: 8)
                            Text(s.name).textStyle(.body, tint: P.inkSoft)
                            Spacer(minLength: 4)
                            Text(total > 0 ? String(format: "%.0f%%", s.value / total * 100) : "-").textStyle(.body, numeric: true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func ring(_ total: Double, _ live: [Slice]) -> some View {
        ZStack {
            if live.isEmpty {
                Circle().strokeBorder(P.line, lineWidth: 14)
            } else {
                Chart(live) { s in
                    SectorMark(angle: .value("Value", s.value), innerRadius: .ratio(0.78), angularInset: 1.5).foregroundStyle(s.tint)
                }
                .chartLegend(.hidden)
            }
            VStack(spacing: 0) {
                Text(centerLabel).textStyle(.caption, tint: P.inkFaint)
                Text(cur.tidyShort(total)).textStyle(.figure, numeric: true).minimumScaleFactor(0.6).lineLimit(1)
            }
            .padding(.horizontal, 18)
        }
        .frame(width: 128, height: 128)
    }
}
