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
            dividendsBox
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
    @Environment(\.dismiss) private var dismiss
    var companyID: Int

    var body: some View {
        let chosen: String = store.engine?.dividendPolicy(companyID: companyID) ?? "none"
        VStack(alignment: .leading, spacing: 8) {
            Text("Dividend policy").font(.serifTitle(22)).foregroundStyle(Theme.ivory)
            ForEach(Shareholders.policies, id: \.self) { (p: String) in
                ChoiceCard(title: Shareholders.policyNames[p] ?? p, subtitle: blurb(p), selected: chosen == p) { pick(p) }
            }
            QuietButton(title: "Close", fullWidth: true) { dismiss() }
        }
        .padding(16)
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
