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
                    Text(p.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                    Spacer(minLength: 0)
                }
                RateBar(label: "Progress", fraction: fraction)
                StatStrip(cells: [
                    .init(label: "Spent", value: cur.tidyShort(run.cost)),
                    .init(label: "To go", value: left.weeksText, tint: Theme.caution),
                ])
            }
        }
    }

    private func projectCard(_ p: Development.Project, cost: Double, cur: Currency) -> some View {
        Card(padding: 14, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconCircle(glyph: Self.kindGlyph(p.kind))
                    Text(p.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                    Spacer(minLength: 0)
                }
                StatStrip(cells: [
                    .init(label: "Takes", value: p.weeks.weeksText),
                    .init(label: "Costs", value: cur.tidyShort(cost)),
                ])
                HStack {
                    Spacer(minLength: 8)
                    QuietButton(title: "Start") { confirm(p, cost: cost, cur) }
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
                            Text(d["n"].string).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                            Spacer(minLength: 8)
                            Text("\(Int((d["mag"].double * 100).rounded()))%").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.gain)
                        }
                    }
                }
            }
        }
    }

    /// Spending real money on something that can fail: the question says what it costs and how long it takes.
    private func confirm(_ p: Development.Project, cost: Double, _ cur: Currency) {
        let message: String = "Costs \(cur.tidyShort(cost)), paid now. Takes \(p.weeks.weeksText). The team's skill and your quality decide how well it works; it can work fully, partly or not at all."
        pending = PendingAction(title: "Start \(p.name.lowercased())?", message: message, button: "Start for \(cur.tidyShort(cost))") { start(p) }
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
