import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// "New menu item", "New service line", "New product range" ...: the development projects of a trade whose projects are written for it
/// (`Development.isSpecific`; the heading's noun is `Development.noun`). One project runs at a time; each costs money up front and takes
/// weeks, and the confirmation says both. Trades with only generic projects (project businesses, logistics) do not get this page.
struct CompanyDevelopment: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: PendingAction?
    @State private var formFor: ExpansionChoice?

    /// The page title: "New menu item".
    static func title(_ co: Company, _ e: GameEngine) -> String {
        "New " + (Development.noun(for: co, data: e.data) ?? "product")
    }

    /// True when this company's trade has development written for it and the company is open.
    static func isAvailable(_ co: Company, _ e: GameEngine) -> Bool {
        co.status == .open && Development.isSpecific(co, data: e.data)
    }

    var body: some View {
        let list = engine.developmentProjects(companyID: company.id)
        let cur: Currency = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if let run = Development.running(company), let p = list.first(where: { $0.project.id == run.project }) {
                runningCard(p.project, run: run, cur: cur)
            } else {
                ForEach(list, id: \.project.id) { x in projectCard(x.project, cost: x.cost, cur: cur) }
            }
            finishedCard
        }
        .confirmAction($pending)
        .centerSheet(item: $formFor) { c in ExpansionForm(engine: engine, company: company, project: c.project, onStarted: { formFor = nil }) }
    }

    private static func kindGlyph(_ kind: String) -> String {
        switch kind {
        case "dem": return Glyph.market
        case "tick": return Glyph.stats
        case "cogs": return Glyph.settings
        default: return Glyph.home
        }
    }

    private func runningCard(_ p: Development.Project, run: (project: String, weeksLeft: Int, cost: Double), cur: Currency) -> some View {
        let left: Int = max(0, run.weeksLeft - engine.state.week)
        let fraction: Double = p.weeks > 0 ? min(1, max(0, 1 - Double(left) / Double(p.weeks))) : 1
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconCircle(glyph: Self.kindGlyph(p.kind))
                    Text(p.name).textStyle(.headline)
                    Spacer(minLength: 0)
                }
                RateBar(label: "Progress", fraction: fraction)
                StatStrip(cells: [
                    .init(label: "Paid", value: cur.tidyShort(run.cost)),
                    .init(label: "To go", value: left.weeksText, tint: Theme.caution),
                ])
                HStack {
                    Spacer(minLength: 8)
                    QuietButton(title: "Cancel the project") { confirmCancel(p, cost: run.cost, left: left, cur) }
                }
            }
        }
    }

    private func projectCard(_ p: Development.Project, cost: Double, cur: Currency) -> some View {
        Card(padding: 14, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconCircle(glyph: Self.kindGlyph(p.kind))
                    Text(p.name).textStyle(.headline)
                    Spacer(minLength: 0)
                }
                StatStrip(cells: [
                    .init(label: "Takes", value: p.weeks.weeksText),
                    .init(label: "Costs", value: cur.tidyShort(cost)),
                ])
                HStack {
                    Spacer(minLength: 8)
                    QuietButton(title: "Plan it") { formFor = ExpansionChoice(id: p.id, project: p) }
                }
            }
        }
    }

    @ViewBuilder private var finishedCard: some View {
        let live: [JSONValue] = Development.finished(company)
        if !live.isEmpty {
            Card(padding: 12, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Working now").capsLabel(Theme.ivoryFaint)
                    ForEach(Array(live.enumerated()), id: \.offset) { n, d in
                        if n > 0 { CardLine() }
                        HStack {
                            GlyphView(glyph: Glyph.check, size: 14, weight: 1.8, tint: Theme.gain)
                            Text(d["n"].string).textStyle(.body)
                            Spacer(minLength: 8)
                            Text("\(Int((d["mag"].double * 100).rounded()))%").textStyle(.body, tint: Theme.gain, numeric: true)
                        }
                    }
                }
            }
        }
    }

    /// Cancelling returns the part of the cost that has not been spent yet (the weeks still to run); what was spent is gone.
    private func confirmCancel(_ p: Development.Project, cost: Double, left: Int, _ cur: Currency) {
        let refund: Double = p.weeks > 0 ? cost * Double(min(left, p.weeks)) / Double(p.weeks) : 0
        let message: String = "\(cur.tidyShort(refund)) of the \(cur.tidyShort(cost)) comes back to the company, for the \(left.weeksText) that will not be run. The rest is spent. Nothing else changes."
        pending = PendingAction(title: "Cancel \(p.name.lowercased())?", message: message, button: "Cancel it and take \(cur.tidyShort(refund)) back") {
            if let back = store.act({ $0.cancelDevelopment(companyID: company.id) }) ?? nil {
                Haptics.success(); store.show("Cancelled. \(cur.tidyShort(back)) came back.", tone: "good")
            } else { store.show("Nothing to cancel.", tone: "warn") }
        }
    }

    /// Spending real money on something that can fail: the question says what it costs and how long it takes.
    private func confirm(_ p: Development.Project, cost: Double, _ cur: Currency) {
        let message: String = "Costs \(cur.tidyShort(cost)), paid now. Takes \(p.weeks.weeksText). The team's skill and your quality decide how well it works; it can work fully, partly or not at all."
        pending = PendingAction(title: "Start \(p.name.lowercased())?", message: message, button: "Start for \(cur.tidyShort(cost))", amount: cost, currency: cur) { start(p) }
    }

    private func start(_ p: Development.Project) {
        switch store.act({ $0.startDevelopment(companyID: company.id, project: p.id) }) {
        case .ok?: Haptics.success(); store.show("Development started.", tone: "good")
        case .notEnoughCash?: store.show("Not enough cash in the company.", tone: "warn")
        case .busy?: store.show("One project at a time.", tone: "warn")
        default: store.show("Not possible right now.", tone: "warn")
        }
    }
}


/// Which project the expansion form is open for.
struct ExpansionChoice: Identifiable {
    var id: String
    var project: Development.Project
}

/// The product-expansion form: only what matters to the decision. What it is, what it costs and when, what it needs, what you can expect, and the
/// company's cash before and after. Closing the sheet changes nothing; "Start" pays and begins the project. Read from `developmentPlan`.
struct ExpansionForm: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var engine: GameEngine
    var company: Company
    var project: Development.Project
    var onStarted: () -> Void

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let plan: Development.Plan? = engine.developmentPlan(companyID: company.id, project: project.id)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(project.name).popupText(.figure)
            Text(project.text).popupText(.subtitle)
            if let plan { details(plan, cur) }
            QuietButton(title: "Start for \(cur.tidyShort(plan?.cost ?? 0))", fullWidth: true) { start() }
                .opacity(plan?.blockedReason == nil ? 1 : 0.4).disabled(plan?.blockedReason != nil)
        }
    }

    @ViewBuilder private func details(_ plan: Development.Plan, _ cur: Currency) -> some View {
        let columns: [TableColumn] = [TableColumn(title: "Cash"), TableColumn(title: "Amount", width: 96)]
        StatStrip(cells: [.init(label: "Costs", value: cur.tidyShort(plan.cost)), .init(label: "Takes", value: plan.weeks.weeksText),
                          .init(label: "Ready", value: "week " + String(engine.state.week + plan.weeks))])
        SharpTable {
            TableHeader(columns: columns)
            TableRow(columns: columns, title: "Company cash now", values: [cur.tidyShort(plan.cashBefore)])
            TableRow(columns: columns, title: "This project", values: [cur.tidyShort(plan.cost)])
            TableRow(columns: columns, title: "Cash left after", values: [cur.tidyShort(plan.cashAfter)], valueTints: [plan.cashAfter < 0 ? Theme.loss : Theme.gain], selected: true)
        }
        CardSection("What to expect") {
            Text("Works fully: \(Int((plan.oddsFull * 100).rounded()))% · works half as well: \(Int((plan.oddsPartial * 100).rounded()))% · does not work out: \(Int(((1 - plan.oddsFull - plan.oddsPartial) * 100).rounded()))%")
                .popupText(.body)
            Text("Rivals copy it in time: about half the gain is gone after two years, 40% stays.").popupText(.caption)
        }
        CardSection("Requirements") {
            ForEach(plan.requirements, id: \.self) { r in Text(r).popupText(.subtitle) }
            if let why = plan.blockedReason { Text(why).popupText(.risk) }
        }
        Text("Closing this sheet changes nothing. A running project can be cancelled later and the part not yet spent comes back.").popupText(.caption)
    }

    private func start() {
        switch store.act({ $0.startDevelopment(companyID: company.id, project: project.id) }) {
        case .ok?: Haptics.success(); store.show("Development started.", tone: "good"); onStarted()
        case .notEnoughCash?: store.show("Not enough cash in the company.", tone: "warn")
        case .busy?: store.show("One project at a time.", tone: "warn")
        default: store.show("Not possible right now.", tone: "warn")
        }
    }
}
