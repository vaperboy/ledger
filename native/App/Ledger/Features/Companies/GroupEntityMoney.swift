import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The dividend desk of ONE entity: its quarterly decision and group-tax position, the policy link, and paying out of this company or
/// collecting for this holding. Nothing is paid by itself.
struct GroupEntityDividends: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity

    var body: some View {
        let cos: [Company] = entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("QUARTERLY PROPOSAL").capsLabel()
                Card(padding: 4, radius: Theme.Radius.hero) {
                    VStack(spacing: 0) {
                        ForEach(Array(cos.enumerated()), id: \.element.id) { (n: Int, c: Company) in
                            statusRow(c, first: n == 0)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(entity.isHolding ? "COLLECT FOR THIS HOLDING" : "PAY OUT").capsLabel()
                GroupDividendsPage(engine: engine, scope: Set(entity.members), holding: entity.isHolding ? entity.companyID : nil)
            }
            Button { Haptics.tap(); store.openCompany(entity.companyID, section: CompanySection.finances) } label: {
                CardRow(glyph: Glyph.reports, title: "Dividend policy", subtitle: "Set in the company's owners and stats; group tax runs between group companies")
            }.buttonStyle(PressableStyle())
        }
    }

    private func statusRow(_ c: Company, first: Bool) -> some View {
        let cur: Currency = engine.currency(for: c)
        let d = engine.lastDividendDecision(companyID: c.id)
        let t = engine.groupTaxContribution(companyID: c.id)
        let head: String = d.map { ($0.paid > 0 ? "Last quarter paid \(cur.tidyShort($0.paid))" : "Last quarter skipped") + " on profit \(cur.tidyShort($0.profit))" } ?? "No dividend decided yet"
        var tax: String = ""
        if let t {
            let thisYear: Double = t.thisYear.in - t.thisYear.out
            let lastYear: Double = t.lastYear.in - t.lastYear.out
            tax = "Group tax this year \(cur.tidyShort(thisYear)), last year \(cur.tidyShort(lastYear))"
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(c.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
            Text(head).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            if !tax.isEmpty { Text(tax).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.divider).frame(height: 1) } }
    }
}

// MARK: - Money

/// What this entity holds and how money moves to and from it: cash per company, putting money in or taking it out (the Bank's own move
/// sheet), and group loans between sister companies.
struct GroupEntityMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity
    @State private var move: MoveTarget?
    @State private var pending: PendingAction?

    private struct MoveTarget: Identifiable {
        var id: String { "\(companyID)-\(kind.rawValue)" }
        var companyID: Int
        var kind: BankMoveKind
    }

    var body: some View {
        let cos: [Company] = entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
        let cash: Double = cos.reduce(0) { (a: Double, c: Company) -> Double in a + c.cash }
        let owed: Double = cos.reduce(0) { (a: Double, c: Company) -> Double in a + engine.groupLoanBalance(companyID: c.id) }
        VStack(alignment: .leading, spacing: 14) {
            Card(padding: 14, radius: Theme.Radius.hero) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entity.isHolding ? "Cash in the holding group" : "Cash").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        LiveFigure(value: cash, text: store.short(cash)).font(.serifTitle(28)).foregroundStyle(cash < 0 ? Theme.loss : Theme.ivory).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 8)
                    if owed > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Owed to sister companies").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                            Text(store.short(owed)).font(.system(size: 17, weight: .medium).monospacedDigit()).foregroundStyle(Theme.caution)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("MOVE MONEY TO AND FROM IT").capsLabel()
                Card(padding: 4, radius: Theme.Radius.hero) {
                    VStack(spacing: 0) {
                        ForEach(Array(cos.enumerated()), id: \.element.id) { (n: Int, c: Company) in
                            companyRow(c, first: n == 0)
                        }
                    }
                }
                Text("A limited company can only pay money out as a dividend (see Dividends). A sole trader's money is yours.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            loans(cos)
        }
        .centerSheet(item: $move) { (t: MoveTarget) in BankMoveSheet(account: .company(t.companyID), kind: t.kind) }
        .confirmAction($pending)
    }

    private func companyRow(_ c: Company, first: Bool) -> some View {
        let cur: Currency = engine.currency(for: c)
        let id: Int = c.id
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text("Cash \(cur.tidyShort(c.cash))").font(.system(size: 11.5)).foregroundStyle(c.cash < 0 ? Theme.loss : Theme.ivoryFaint)
            }
            Spacer(minLength: 6)
            Button("Put in") { move = MoveTarget(companyID: id, kind: .deposit) }.buttonStyle(TinyButtonStyle(tint: Theme.gold))
            if c.form != .limited && c.type != "hold" {
                Button("Take out") { move = MoveTarget(companyID: id, kind: .withdraw) }.buttonStyle(TinyButtonStyle())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.divider).frame(height: 1) } }
    }

    // MARK: Group loans

    /// A company out of cash can borrow from the sister company with the most to spare, repaid once it has a cushion again.
    @ViewBuilder private func loans(_ cos: [Company]) -> some View {
        let short: [Company] = cos.filter { (c: Company) -> Bool in c.cash < 0 && c.type != "hold" }
        let indebted: [Company] = cos.filter { (c: Company) -> Bool in engine.groupLoanBalance(companyID: c.id) > 0 }
        if !short.isEmpty || !indebted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("LOANS BETWEEN GROUP COMPANIES").capsLabel()
                Card(padding: 4, radius: Theme.Radius.hero) {
                    VStack(spacing: 0) {
                        ForEach(Array(cos.enumerated()), id: \.element.id) { (n: Int, c: Company) in
                            loanRow(c, first: n == 0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func loanRow(_ c: Company, first: Bool) -> some View {
        let owed: Double = engine.groupLoanBalance(companyID: c.id)
        let cur: Currency = engine.currency(for: c)
        let weekly: Double = engine.companyHealth(c).weeklyCost
        let need: Double = cur.roundedStep(max(0, -c.cash) + weekly * 4, about: 1000)
        if owed > 0 || c.cash < 0 {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Text(owed > 0 ? "Owes sister companies \(cur.tidyShort(owed))" : "Out of cash").font(.system(size: 11.5)).foregroundStyle(Theme.caution)
                }
                Spacer(minLength: 6)
                if c.cash < 0 && c.type != "hold" {
                    Button("Group loan \(cur.tidyShort(need))") { askLoan(c, need, cur) }.buttonStyle(TinyButtonStyle(tint: Theme.gold)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.divider).frame(height: 1) } }
        }
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
