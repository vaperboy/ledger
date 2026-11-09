import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

// MARK: - Money

/// An entity's money as one vertical list: cash with Put in and Take out, group loans, dividends, and (a holding) a dividend to you.
/// A holding invests its treasury in the Market app.
struct GroupEntityMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity
    @State private var move: MoveTarget?
    @State private var pending: PendingAction?
    @State private var policyOpen = false
    @State private var payOpen = false
    @State private var amount = 0.0

    private struct MoveTarget: Identifiable {
        var id: String { "\(companyID)-\(kind.rawValue)" }
        var companyID: Int
        var kind: BankMoveKind
    }

    private var cos: [Company] {
        entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            cashBox
            loansBox
            dividendsOrLock
            if entity.isHolding { treasuryBox }
        }
        .centerSheet(item: $move) { (t: MoveTarget) in BankMoveSheet(account: .company(t.companyID), kind: t.kind) }
        .centerSheet(isPresented: $policyOpen) { DividendPolicySheet(companyID: entity.companyID).environmentObject(store) }
        .centerSheet(isPresented: $payOpen, title: "Pay yourself") { PayYourselfSheet(companyID: entity.companyID).environmentObject(store) }
        .confirmAction($pending)
    }

    /// The cash leads as a figure; moving money in or out are rows under it.
    private var cashBox: some View {
        // A chain is one company: its stores share one combined cash.
        let cash: Double = entity.chainID.map { (id: Int) -> Double in engine.chainCash(chainID: id).cash } ?? cos.reduce(0) { (a: Double, c: Company) -> Double in a + c.cash }
        let id: Int = entity.companyID
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(entity.isHolding ? "Group cash" : (entity.isChain ? "Chain cash" : "Cash")).textStyle(.label, tint: Theme.inkFaint)
            LiveFigure(value: cash, text: store.short(cash)).textStyle(.figure, tint: cash < 0 ? Theme.loss : nil)
                .lineLimit(1).minimumScaleFactor(0.6)
            VStack(spacing: 0) {
                LedgerRow(leading: .symbol("arrow.down.to.line"), title: "Put money in", subtitle: "From your own account",
                          identifier: "money-put-in", action: { move = MoveTarget(companyID: id, kind: .deposit) })
            }
        }
    }

    /// The holding pays you a dividend: an amount and one action.
    private var treasuryBox: some View {
        let main: Company? = engine.state.company(entity.companyID)
        let cur: Currency = main.map { (c: Company) -> Currency in engine.currency(for: c) } ?? engine.homeCurrency
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Dividend to you").textStyle(.label, tint: Theme.inkFaint)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                AmountField(title: "Amount", currency: cur, amount: $amount)
                HStack(spacing: Theme.Space.s) {
                    Button("Pay me a dividend\u{2026}") { askDividend(cur) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    Menu {
                        Button("Invest in index") { investIndex() }
                        Button("Sell index\u{2026}") { askSellIndex(cur) }
                    } label: {
                        Text("Index fund")
                    }
                    .menuStyle(.button)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint("Invest in or sell the index fund")
                }
                Text("Index fund: 0.66% to sell \u{00B7} dividends carry \(PayRules.dividendTaxText(engine))")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func investIndex() {
        let id: Int = entity.companyID
        let amt: Double = amount
        if amt > 0, store.act({ $0.holdingInvest(holdingID: id, amount: amt) }) == true { Haptics.success(); store.show("Invested.", tone: "good") }
        else { Haptics.warning(); store.show(amt > 0 ? "Not enough cash in the holding." : "Enter an amount first.", tone: "warn") }
    }

    private func askSellIndex(_ cur: Currency) {
        guard amount > 0 else { Haptics.warning(); store.show("Enter an amount first.", tone: "warn"); return }
        let id: Int = entity.companyID
        let sold: Double = amount
        pending = PendingAction(title: "Sell \(cur.tidyShort(sold)) of the index fund?", message: "The holding sells index holdings worth this much. The fund charges 0.66% to sell.", button: "Sell index", destructive: true) {
            if store.act({ $0.holdingDivest(holdingID: id, amount: sold) }) == true { Haptics.success(); store.show("Sold.", tone: "good") }
            else { Haptics.warning(); store.show("Nothing to sell.", tone: "warn") }
        }
    }


    private func askDividend(_ cur: Currency) {
        let id: Int = entity.companyID
        let amt: Double = amount
        guard amt > 0 else { Haptics.warning(); store.show("Enter an amount first.", tone: "warn"); return }
        pending = PendingAction(title: "Pay \(cur.tidyShort(amt)) to yourself?", message: "It comes out of the holding's retained profits and is added to your dividends for the year, with \(PayRules.dividendTaxText(engine)). It cannot be paid back in as a dividend.", button: "Pay dividend", amount: amt, currency: cur) {
            switch store.act({ $0.payDividend(companyID: id, amount: amt) }) {
            case .ok?: Haptics.success(); store.show("Dividend of \(cur.tidyShort(amt)) paid.", tone: "good")
            case .needsBoard?: Haptics.warning(); store.show("This company has partners. A board meeting must vote for a dividend.", tone: "warn")
            case .noRetainedProfit?: Haptics.warning(); store.show("There are no retained profits to pay out.", tone: "warn")
            default: Haptics.warning(); store.show("Not enough cash in the holding.", tone: "warn")
            }
        }
    }

    /// What sister companies lent each other, as one row; when a company is short, the row offers the loan.
    private var loansBox: some View {
        let owed: Double = cos.reduce(0) { (a: Double, c: Company) -> Double in a + engine.groupLoanBalance(companyID: c.id) }
        let short: Company? = cos.first { (c: Company) -> Bool in c.cash < 0 && c.type != "hold" }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Group loans").textStyle(.label, tint: Theme.inkFaint)
            if let c = short {
                lendRow(c, owed: owed)
            } else {
                LedgerRow(leading: .glyph(Glyph.bank), leadingTint: Theme.inkFaint, title: owed > 0 ? "Owed between your companies" : "No loans",
                          subtitle: "Nobody is short of cash", value: owed > 0 ? store.short(owed) : "", valueTint: Theme.warn)
            }
        }
    }

    private func lendRow(_ c: Company, owed: Double) -> some View {
        let cur: Currency = engine.currency(for: c)
        let weekly: Double = engine.companyHealth(c).weeklyCost
        let need: Double = cur.roundedStep(max(0, -c.cash) + weekly * 4, about: 1000)
        return LedgerRow(leading: .glyph(Glyph.warning), leadingTint: Theme.warn, title: "Lend \(cur.tidyShort(need)) to \(c.name)",
                         subtitle: "It is short of cash; a sister company pays", value: owed > 0 ? store.short(owed) : "",
                         valueNote: owed > 0 ? "owed now" : "", identifier: "money-lend", action: { askLoan(c, need, cur) })
    }

    /// The dividend desk, or (while the company has no retained profit to pay out) a locked line that says what opens it. A holding collects, so it is never locked.
    @ViewBuilder private var dividendsOrLock: some View {
        if let lock = engine.unlockItem("dividends", companyID: entity.companyID), !lock.unlocked {
            LockedBlock(title: "Dividends", reason: lock.reason)
        } else {
            dividendsBox
        }
    }

    private var dividendsBox: some View {
        let d = engine.lastDividendDecision(companyID: entity.companyID)
        let main: Company? = engine.state.company(entity.companyID)
        let last: String = lastLine(d, main)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(entity.isHolding ? "Dividends \u{00B7} collect" : "Dividends").textStyle(.label, tint: Theme.inkFaint)
                Spacer(minLength: Theme.Space.s)
                Button("Policy") { Haptics.tap(); policyOpen = true }.buttonStyle(TertiaryButtonStyle(size: .compact)).accessibilityIdentifier("money-policy")
            }
            GroupDividendsPage(engine: engine, scope: Set(entity.members), holding: entity.isHolding ? entity.companyID : nil, compact: true)
            Text(last).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2)
            LedgerRow(leading: .symbol("person.crop.circle"), title: "Pay yourself", subtitle: "Salary, dividend or keep it in the company",
                      identifier: "money-pay-yourself", action: { payOpen = true })
        }
    }

    private func lastLine(_ d: (week: Int, paid: Double, profit: Double)?, _ main: Company?) -> String {
        guard let d, let main else { return "No dividend decided yet" }
        let paid: String = d.paid > 0 ? "Last payout \(store.short(d.paid, in: main))" : "Last quarter skipped"
        return paid + " on profit \(store.short(d.profit, in: main))"
    }

    private func askLoan(_ c: Company, _ need: Double, _ cur: Currency) {
        let id: Int = c.id
        let name: String = c.name
        pending = PendingAction(title: "Lend \(cur.tidyShort(need)) to \(name)?",
                                message: "The sister company with the most spare cash pays it, as a group loan. \(name) pays it back by itself once it has about ten weeks of costs again.",
                                button: "Lend", amount: need, currency: cur, risk: "The lending company has less of a cushion until then.") {
            let ok: Bool = store.act { $0.lendFromSister(companyID: id, amount: need) } ?? false
            if ok { Haptics.success(); store.show("\(name) received a group loan of \(cur.tidyShort(need)).", tone: "good") }
            else { Haptics.warning(); store.show("No sister company can spare that much right now.", tone: "warn") }
        }
    }
}

// MARK: - Dividend policy popup

/// The dividend policy of one company in a centred popup: how much of the profit is proposed each quarter. Nothing is paid by itself.
struct DividendPolicySheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int

    var body: some View {
        let chosen: String = store.engine?.dividendPolicy(companyID: companyID) ?? "none"
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Shareholders.policies, id: \.self) { (p: String) in
                ChoiceCard(title: Shareholders.policyNames[p] ?? p, subtitle: blurb(p), selected: chosen == p) { pick(p) }
            }
        }
        .centerSheetTitle("Dividend policy")
    }

    private func blurb(_ p: String) -> String {
        switch p {
        case "none": return "Keep all profit in the company; no proposals."
        case "low": return "Each quarter you are offered a quarter of the profit."
        case "mid": return "Each quarter you are offered half of the profit."
        default: return "Each quarter you are offered most of the profit."
        }
    }

    private func pick(_ p: String) {
        let id: Int = companyID
        let name: String = Shareholders.policyNames[p] ?? p
        store.settle(store.act { $0.setDividendPolicy(companyID: id, policy: p) }, "Dividend policy: \(name).", same: "That is already the dividend policy.")
    }
}
