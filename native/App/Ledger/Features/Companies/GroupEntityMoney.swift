import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

// MARK: - Money

/// One fixed screen for an entity's money: a cash box and a group-loans box side by side, and a dividends box below.
struct GroupEntityMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity
    @State private var move: MoveTarget?
    @State private var pending: PendingAction?
    @State private var policyOpen = false
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                cashBox
                loansBox
            }
            .fixedSize(horizontal: false, vertical: true)
            dividendsOrLock
            if entity.isHolding { treasuryBox }
        }
        .centerSheet(item: $move) { (t: MoveTarget) in BankMoveSheet(account: .company(t.companyID), kind: t.kind) }
        .centerSheet(isPresented: $policyOpen) { DividendPolicySheet(companyID: entity.companyID).environmentObject(store) }
        .confirmAction($pending)
    }

    private var cashBox: some View {
        let cash: Double = cos.reduce(0) { (a: Double, c: Company) -> Double in a + c.cash }
        let main: Company? = engine.state.company(entity.companyID)
        let canTake: Bool = main.map { (c: Company) -> Bool in c.form != .limited && c.type != "hold" } ?? false
        let id: Int = entity.companyID
        return Card(padding: 10, radius: Theme.Radius.table) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entity.isHolding ? "GROUP CASH" : "CASH").capsLabel()
                LiveFigure(value: cash, text: store.short(cash)).font(.serifTitle(24)).foregroundStyle(cash < 0 ? Theme.loss : Theme.ivory).lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    Button("Put in") { move = MoveTarget(companyID: id, kind: .deposit) }.buttonStyle(TinyButtonStyle(tint: Theme.gold))
                    if canTake {
                        Button("Take out") { move = MoveTarget(companyID: id, kind: .withdraw) }.buttonStyle(TinyButtonStyle())
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The holding's treasury: the index fund and paying yourself a dividend (moved here from the holding's own page).
    private var treasuryBox: some View {
        let main: Company? = engine.state.company(entity.companyID)
        let cur: Currency = main.map { (c: Company) -> Currency in engine.currency(for: c) } ?? engine.homeCurrency
        return Card(padding: 10, radius: Theme.Radius.table) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TREASURY").capsLabel()
                AmountField(title: "Amount", currency: cur, amount: $amount)
                HStack(spacing: 6) {
                    Button("Invest in index") { investIndex() }.buttonStyle(TinyButtonStyle())
                    Button("Sell index") { askSellIndex(cur) }.buttonStyle(TinyButtonStyle())
                    Button("Pay me a dividend\u{2026}") { askDividend(cur) }.buttonStyle(TinyButtonStyle(tint: Theme.gold))
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                Text("The index fund costs 0.66% to sell. A dividend to you comes out of retained profit and is taxed as your income.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        pending = PendingAction(title: "Pay \(cur.tidyShort(amt)) to yourself?", message: "It comes out of the holding's retained profits and is taxed as your income. It cannot be paid back in as a dividend.", button: "Pay dividend", amount: amt, currency: cur) {
            switch store.act({ $0.payDividend(companyID: id, amount: amt) }) {
            case .ok?: Haptics.success(); store.show("Dividend of \(cur.tidyShort(amt)) paid.", tone: "good")
            case .noRetainedProfit?: Haptics.warning(); store.show("There are no retained profits to pay out.", tone: "warn")
            default: Haptics.warning(); store.show("Not enough cash in the holding.", tone: "warn")
            }
        }
    }

    private var loansBox: some View {
        let owed: Double = cos.reduce(0) { (a: Double, c: Company) -> Double in a + engine.groupLoanBalance(companyID: c.id) }
        let short: Company? = cos.first { (c: Company) -> Bool in c.cash < 0 && c.type != "hold" }
        return Card(padding: 10, radius: Theme.Radius.table) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GROUP LOANS").capsLabel()
                if owed > 0 {
                    Text(store.short(owed)).font(.system(size: 20, weight: .medium).monospacedDigit()).foregroundStyle(Theme.caution).lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text("No loans").font(.system(size: 14)).foregroundStyle(Theme.ivoryFaint)
                }
                if let c = short {
                    lendButton(c)
                } else {
                    Text("Nobody is short").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func lendButton(_ c: Company) -> some View {
        let cur: Currency = engine.currency(for: c)
        let weekly: Double = engine.companyHealth(c).weeklyCost
        let need: Double = cur.roundedStep(max(0, -c.cash) + weekly * 4, about: 1000)
        return Button("Lend \(cur.tidyShort(need))") { askLoan(c, need, cur) }.buttonStyle(TinyButtonStyle(tint: Theme.gold)).lineLimit(1).minimumScaleFactor(0.8)
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
        return Card(padding: 10, radius: Theme.Radius.table) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entity.isHolding ? "DIVIDENDS \u{00B7} COLLECT" : "DIVIDENDS \u{00B7} PAY OUT").capsLabel()
                    Spacer(minLength: 6)
                    Button("Policy") { Haptics.tap(); policyOpen = true }.buttonStyle(TinyButtonStyle()).accessibilityIdentifier("money-policy")
                }
                GroupDividendsPage(engine: engine, scope: Set(entity.members), holding: entity.isHolding ? entity.companyID : nil, compact: true)
                Text(last).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 8) {
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
