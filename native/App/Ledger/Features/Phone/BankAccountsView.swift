import SwiftUI
import GameCore
import Countries
import Simulation

/// Bank, every account (after Back from one): the total with what falls due in 30 days, Transfer as the one action, the accounts with
/// their balances, then bills, giving, wealth and where the money sits. Loans belong to the account they were taken for.
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
            let you: [BankAccountRow] = all.rows.filter { $0.kind != .company }
            let companies: [BankAccountRow] = all.rows.filter { $0.kind == .company }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        BankTotalHero(all: all)
                        actions
                    }
                    accounts("You", you, e)
                    if companies.isEmpty {
                        MoneyGroup("Your companies") {
                            EmptyState(glyph: BankGlyph.company, title: "No company yet", message: "Its account appears here once it exists.", centered: false)
                                .padding(.vertical, Theme.Space.s)
                        }
                    } else {
                        accounts("Your companies", companies, e)
                    }
                    MoneyGroup("More") {
                        billsLink(all, e)
                        MoneyRule(inset: 32)
                        givingLink(e)
                    }
                    BankWealthCard(engine: e)
                    BankHomeRing(all: all, engine: e)
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
                .environment(\.insideCard, true)
            }
            .scrollIndicators(.hidden).noSidewaysDrag().scrollBounceBehavior(.basedOnSize)
            .centerSheet(item: $move) { kind in BankMoveSheet(account: .personal, kind: kind) }
        }
    }

    /// Transfer is the one filled action; paying in and sending out sit beside it as text.
    private var actions: some View {
        VStack(spacing: Theme.Space.xs) {
            Button { Haptics.tap(); move = .transfer } label: { Text("Transfer") }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            HStack(spacing: Theme.Space.l) {
                MoneyTextAction(title: "Deposit") { move = .deposit }
                MoneyTextAction(title: "Send") { move = .withdraw }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bank-round-actions")
    }

    private func accounts(_ title: String, _ rows: [BankAccountRow], _ e: GameEngine) -> some View {
        MoneyGroup(title) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { (n: Int, r: BankAccountRow) in
                if n > 0 { MoneyRule(inset: 52) }
                BankAccountLine(row: r, engine: e, identifier: "bank-account-\(r.id.id)") { onPick(r.id) }
            }
        }
    }

    /// Gifts, sponsorships and the foundation are paid from the personal account, so they live in the Bank.
    private func givingLink(_ e: GameEngine) -> some View {
        let n: Int = e.givingMarks.count
        let sub: String = "\(n) \(n == 1 ? "mark" : "marks")" + (e.foundation != nil ? " \u{00B7} foundation running" : "")
        return LedgerRow(leading: .glyph(Glyph.richList), title: "Giving back", subtitle: "Gifts, sponsorships, foundation \u{00B7} " + sub,
                         lineLimit: 1, identifier: "bank-giving", action: { ent.run(.luxuryGivingFootball, "Giving back") { givingOpen = true } })
            .overlay(alignment: .topTrailing) { ProMark(feature: .luxuryGivingFootball).padding(.top, 4).padding(.trailing, 24) }
            .navigationDestination(isPresented: $givingOpen) { GivingView() }
    }

    private func billsLink(_ all: BankAccounts, _ e: GameEngine) -> some View {
        let count: Int = e.financeOverview().upcoming.count
        let sub: String = count == 0 ? "Nothing is due" : "\(count) coming \u{00B7} \(store.short(all.dueWithin30Days)) in 30 days"
        return NavigationLink {
            BankAllBillsScreen()
        } label: {
            LedgerRow(leading: .glyph(BankGlyph.bill), title: "Bills", subtitle: sub, badge: all.alertCount, chevron: true, lineLimit: 1)
        }
        .buttonStyle(AcctPressStyle())
        .accessibilityIdentifier("bank-all-bills")
    }
}

/// Where the money is: a ring over the accounts that hold some (personal current account, savings, investments, each company), the five
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
        for r in all.rows {
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
