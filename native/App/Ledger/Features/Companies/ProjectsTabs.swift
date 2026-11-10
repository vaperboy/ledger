import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

typealias ProjectRows = [(co: Company, board: ProjectBoard)]

func shortDate(week: Int) -> String {
    GameCalendar.dateString(week: week).split(separator: " ").dropLast().joined(separator: " ")
}

private func rangeText(_ low: Int, _ high: Int, unit: String) -> String {
    low == high ? "\(low) \(unit)" : "\(low) to \(high) \(unit)"
}

private func percent(_ x: Double) -> Int { Int(saturating: (x * 100).rounded()) }

struct ActiveVenture: Identifiable {
    enum Kind { case job, event, build, develop }
    var id: String
    var kind: Kind
    var title: String
    var companyID: Int
    var line: String
    var status: String
    var tone: AcctPill.Tone
    var fraction: Double
    var step: String
    var weeksLeft: Int?
    var dueWeek: Int?
    var late: Bool
    var figures: [(label: String, value: String)]
    var lineID: String?

    var glyph: String {
        switch kind {
        case .job: return Glyph.projects
        case .event: return Glyph.clock
        case .build: return Glyph.home
        case .develop: return Glyph.ventures
        }
    }

    var kindWord: String {
        switch kind {
        case .job: return "Job"
        case .event: return "Event"
        case .build: return "Construction"
        case .develop: return "R&D"
        }
    }

    var timeLeft: String {
        guard let w = weeksLeft else { return "No date set" }
        switch kind {
        case .build: return w <= 0 ? "Stage ends this week" : "Stage ends in " + w.weeksText
        case .event: return w <= 0 ? "Event this week" : "Event in " + w.weeksText
        default: return w <= 0 ? "Due now" : w.weeksText + " left"
        }
    }
}

struct VentureOption: Identifiable {
    enum Group: Int, CaseIterable {
        case build, develop, found

        var title: String {
            switch self {
            case .build: return "Build"
            case .develop: return "Develop"
            case .found: return "New ventures"
            }
        }

        var note: String {
            switch self {
            case .build: return "Buy land, build and sell the units."
            case .develop: return "Pay for a new product, menu or process."
            case .found: return "Start something of your own."
            }
        }

        var glyph: String {
            switch self {
            case .build: return Glyph.home
            case .develop: return Glyph.goals
            case .found: return Glyph.ventures
            }
        }

        var emptyTitle: String {
            switch self {
            case .build: return "No developer company yet"
            case .develop: return "No company can develop anything now"
            case .found: return "Nothing to start yet"
            }
        }

        var emptyMessage: String {
            switch self {
            case .build: return "Open a property developer and it can buy land, build and sell units from here."
            case .develop: return "Open a company first. Development needs a running company with a team."
            case .found: return "Ventures open as you level up."
            }
        }
    }

    enum Action {
        case route(NavRoute)
        case develop(Int)
        case found
    }

    var id: String
    var group: Group
    var title: String
    var subtitle: String
    var cost: String
    var time: String
    var payoff: String
    var risk: String
    var status: String
    var tone: AcctPill.Tone
    var rank: Int
    var sortCost: Double
    var action: Action
}

@MainActor enum VentureBoard {
    static func active(_ e: GameEngine, _ store: GameStore) -> [ActiveVenture] {
        let now: Int = e.state.week
        var out: [ActiveVenture] = []
        for l in e.projectTimelines() where l.kind == .job || l.kind == .event || l.kind == .development {
            guard let co = e.state.company(l.companyID) else { continue }
            out.append(fromLine(l, co, now, store))
        }
        for co in e.state.companies where co.status.isLive && co.type != "hold" {
            if let v = developing(co, e, now, store) { out.append(v) }
        }
        return out.sorted { (a: ActiveVenture, b: ActiveVenture) -> Bool in
            if a.late != b.late { return a.late }
            if a.dueWeek != b.dueWeek { return (a.dueWeek ?? Int.max) < (b.dueWeek ?? Int.max) }
            return a.title < b.title
        }
    }

    private static func lineStatus(_ l: ProjectTimeline) -> (String, AcctPill.Tone) {
        if l.overdueWeeks > 0 { return ("Late \(l.overdueWeeks) wk", l.overdueWeeks >= 2 ? .bad : .warn) }
        if l.delayed { return ("Held up", .warn) }
        if (l.progress ?? 0) <= 0 && !l.stages.contains(where: { (s: ProjectTimeline.Stage) -> Bool in s.state == .done && s.name != "Taken on" && s.name != "Booked" }) {
            return (l.kind == .development ? "Planning" : "Waiting", .neutral)
        }
        return ("On track", .good)
    }

    private static func fromLine(_ l: ProjectTimeline, _ co: Company, _ now: Int, _ store: GameStore) -> ActiveVenture {
        let done: Int = l.stages.filter { (s: ProjectTimeline.Stage) -> Bool in s.state == .done }.count
        let fraction: Double = min(1, max(0, l.progress ?? (l.stages.isEmpty ? 0 : Double(done) / Double(l.stages.count))))
        let current: ProjectTimeline.Stage? = l.stages.first { (s: ProjectTimeline.Stage) -> Bool in s.state == .current }
        let step: String = current.map { (s: ProjectTimeline.Stage) -> String in "Next: " + s.name.lowercased() } ?? (done == l.stages.count ? "Complete" : "")
        let (word, tone): (String, AcctPill.Tone) = lineStatus(l)
        let cost: (label: String, value: String) = l.costSoFar.map { (c: Double) -> (label: String, value: String) in (label: "Costs so far", value: store.short(c, in: co)) }
            ?? l.receivedSoFar.map { (r: Double) -> (label: String, value: String) in (label: "Paid so far", value: store.short(r, in: co)) } ?? (label: "Costs so far", value: "None yet")
        let dueText: String = l.dueWeek.map { (w: Int) -> String in shortDate(week: w) } ?? "None set"
        let figures: [(label: String, value: String)] = [(label: l.kind == .development ? "Expected sales" : "Value", value: store.short(l.value, in: co)), cost,
                                                         (label: "Next date", value: dueText)]
        let kind: ActiveVenture.Kind = l.kind == .development ? .build : (l.kind == .event ? .event : .job)
        return ActiveVenture(id: l.id, kind: kind, title: l.title.tidyMoney, companyID: co.id, line: "\(co.name) · \(l.subtitle)", status: word, tone: tone,
                             fraction: fraction, step: step, weeksLeft: l.dueWeek.map { (w: Int) -> Int in max(0, w - now) }, dueWeek: l.dueWeek,
                             late: l.delayed || l.overdueWeeks > 0,
                             figures: figures, lineID: l.id)
    }

    private static func developing(_ co: Company, _ e: GameEngine, _ now: Int, _ store: GameStore) -> ActiveVenture? {
        guard let run = Development.running(co) else { return nil }
        let raw: JSONValue = co.value("rd56")["run"]
        let start: Int = raw["w0"].int
        let total: Int = max(1, run.weeksLeft - start)
        let fraction: Double = min(1, max(0, Double(now - start) / Double(total)))
        let known: Development.Project? = Development.projects(for: co, data: e.data).first { (p: Development.Project) -> Bool in p.id == run.project }
        let name: String = known?.name ?? (raw["item"].string.isEmpty ? "New product work" : raw["item"].string)
        let left: Int = max(0, run.weeksLeft - now)
        return ActiveVenture(id: "rd-\(co.id)", kind: .develop, title: name, companyID: co.id, line: co.name + " · " + (known?.text ?? "Development"),
                             status: left == 0 ? "Finishing" : "In progress", tone: .good, fraction: fraction, step: left == 0 ? "Result this week" : "Result in " + left.weeksText,
                             weeksLeft: left, dueWeek: run.weeksLeft, late: false,
                             figures: [(label: "Paid", value: store.short(run.cost, in: co)), (label: "Result", value: shortDate(week: run.weeksLeft)), (label: "Works fully", value: "Not certain")],
                             lineID: nil)
    }

    static func options(_ e: GameEngine, _ store: GameStore, _ rows: ProjectRows) -> [VentureOption] {
        var out: [VentureOption] = []
        for r in rows where r.board.isDeveloper && r.co.status == .open {
            if let o = build(e, r.co, store) { out.append(o) }
        }
        for co in e.state.companies where co.status == .open && co.type != "hold" {
            if let o = develop(e, co, store) { out.append(o) }
        }
        out.append(contentsOf: found(e, store))
        return out
    }

    private static func build(_ e: GameEngine, _ co: Company, _ store: GameStore) -> VentureOption? {
        guard let q = e.developmentQuote(companyID: co.id, size: 1, financed: false) else { return nil }
        let weeks: Int = Int(saturating: e.data.catalog[co.type]?.traits["wks"] ?? 70)
        let margin: Double = q.totalCost > 0 ? (q.expectedRevenue - q.totalCost) / q.totalCost : 0
        let ready: Bool = co.cash >= q.cashNow
        let payoff: String = "Sells for about \(store.short(q.expectedRevenue, in: co)), " + (margin >= 0 ? "about \(percent(margin))% over cost" : "\(percent(-margin))% under cost")
        return VentureOption(id: "build-\(co.id)", group: .build, title: "New development", subtitle: co.name,
                             cost: store.short(q.totalCost, in: co) + ", \(store.short(q.cashNow, in: co)) now", time: "About " + weeks.weeksText, payoff: payoff,
                             risk: "Zoning can be refused, building can overrun and a weak housing market lowers prices. A loan can cover most of it.",
                             status: ready ? "Ready" : "Needs cash", tone: ready ? .good : .warn, rank: ready ? 0 : 1, sortCost: q.totalCost,
                             action: .route(.companyAt(co.id, .projects)))
    }

    private static func develop(_ e: GameEngine, _ co: Company, _ store: GameStore) -> VentureOption? {
        let list: [(project: Development.Project, cost: Double)] = e.developmentProjects(companyID: co.id)
        guard !list.isEmpty else { return nil }
        let plans: [Development.Plan] = list.compactMap { (x: (project: Development.Project, cost: Double)) -> Development.Plan? in e.developmentPlan(companyID: co.id, project: x.project.id) }
        guard let first = plans.first else { return nil }
        let costs: [Double] = list.map { (x: (project: Development.Project, cost: Double)) -> Double in x.cost }
        let weeks: [Int] = plans.map { (p: Development.Plan) -> Int in p.weeks }
        let sizes: [Int] = list.map { (x: (project: Development.Project, cost: Double)) -> Int in percent(x.project.size) }
        let busy: Bool = Development.running(co) != nil
        let low: Double = costs.min() ?? 0
        let ready: Bool = co.cash >= low
        let status: String = busy ? "Busy" : (ready ? "Ready" : "Needs cash")
        let tone: AcctPill.Tone = busy ? .neutral : (ready ? .good : .warn)
        let high: Double = costs.max() ?? low
        let cost: String = low == high ? store.short(low, in: co) : store.short(low, in: co) + " to " + store.short(high, in: co)
        let smallest: Int = sizes.min() ?? 0
        let largest: Int = sizes.max() ?? 0
        let gain: String = smallest == largest ? "+\(smallest)%" : "+\(smallest) to \(largest)%"
        let payoff: String = "About \(gain) on demand, prices, costs or capacity, fading as rivals copy it"
        return VentureOption(id: "develop-\(co.id)", group: .develop, title: "Develop something new", subtitle: co.name, cost: cost,
                             time: rangeText(weeks.min() ?? 0, weeks.max() ?? 0, unit: "weeks"), payoff: payoff,
                             risk: "Works fully in about \(percent(first.oddsFull))% of tries, partly in \(percent(first.oddsPartial))%, and not at all otherwise. The money is spent either way.",
                             status: status, tone: tone, rank: busy ? 2 : (ready ? 0 : 1), sortCost: low, action: .develop(co.id))
    }

    private static func found(_ e: GameEngine, _ store: GameStore) -> [VentureOption] {
        var out: [VentureOption] = []
        let cur: Currency = e.homeCurrency
        let plans: [Startups.Plan] = StartupProducts.sectors.compactMap { (s: StartupProducts.Sector) -> Startups.Plan? in e.startupPlan(sector: s.id, who: "c2", seedMultiple: 1) }
        if let low = plans.map({ (p: Startups.Plan) -> Double in p.seed }).min(), let high = plans.map({ (p: Startups.Plan) -> Double in p.seed }).max() {
            let sells: [Int] = plans.compactMap { (p: Startups.Plan) -> Int? in p.weeksToSell }
            let ready: Bool = Payments.liquid(e.state) >= low
            out.append(VentureOption(id: "found-startup", group: .found, title: "Found a startup", subtitle: "Your own idea, built by a small team",
                                     cost: "Seed money " + cur.tidyShort(low) + " to " + cur.tidyShort(high), time: sells.isEmpty ? "Set in the sheet" : rangeText(sells.min() ?? 0, sells.max() ?? 0, unit: "weeks") + " to a product on sale",
                                     payoff: "Most fail and the seed is lost; a hit is worth many times the seed",
                                     risk: "Each funding round brings money in and makes your share smaller.",
                                     status: ready ? "Ready" : "Needs cash", tone: ready ? .good : .warn, rank: ready ? 0 : 1, sortCost: low, action: .found))
        }
        let canOpen: Bool = !e.state.companies.contains { (c: Company) -> Bool in c.status.isLive && c.type != "hold" } || Gates.isOpen(.newCompany, e.state, data: e.data)
        if canOpen {
            out.append(VentureOption(id: "found-company", group: .found, title: "Open a new company", subtitle: "Pick a trade and a city",
                                     cost: "Shown in a trial run before you commit", time: "30 to 52 weeks to build a name",
                                     payoff: "Loses money at first; the trial run shows the cash you need to last",
                                     risk: "The first year is kinder than later ones.", status: "Ready", tone: .good, rank: 0, sortCost: 0, action: .route(.newCompany)))
        }
        return out
    }
}

struct ActiveVentureCard: View {
    var venture: ActiveVenture

    var body: some View {
        let v: ActiveVenture = venture
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                IconCircle(glyph: v.glyph, size: 36, tint: v.late ? Theme.warn : nil)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(v.title).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text(v.kindWord + " · " + v.line).textStyle(.caption).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                AcctPill(text: v.status, tone: v.tone)
            }
            ProgressLine(fraction: v.fraction, tint: v.late ? Theme.warn : Theme.gain, label: v.step.isEmpty ? "\(percent(v.fraction))% done" : v.step, value: v.timeLeft, height: 6)
            HStack(alignment: .top, spacing: Theme.Space.m) {
                ForEach(Array(v.figures.enumerated()), id: \.offset) { (_: Int, f: (label: String, value: String)) in
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(f.label).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.8)
                        Text(f.value).textStyle(.body, numeric: true, weight: .medium).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(raised: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct VenturesActiveSection: View {
    var active: [ActiveVenture]
    var hasCompanies: Bool
    var openDevelopment: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Active").textStyle(.title)
                Spacer(minLength: Theme.Space.s)
                if !active.isEmpty { Text("\(active.count) running").textStyle(.caption, tint: Theme.inkFaint) }
            }
            if active.isEmpty {
                EmptyState(glyph: Glyph.projects, title: hasCompanies ? "Nothing is running" : "No company yet",
                           message: hasCompanies
                               ? "Start a development, a build or a new venture below. Project companies also take jobs on their own as requests come in."
                               : "Open a company first. Its jobs, builds and developments show here with progress and time left.")
            }
            ForEach(active) { (v: ActiveVenture) in
                if let line = v.lineID {
                    NavigationLink { ProjectTimelineDetail(lineID: line) } label: { ActiveVentureCard(venture: v) }
                        .buttonStyle(PressableStyle())
                } else {
                    Button { Haptics.tap(); openDevelopment(v.companyID) } label: { ActiveVentureCard(venture: v) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

struct VenturesStartSection: View {
    var options: [VentureOption]
    var open: (VentureOption) -> Void
    var newCompany: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Start a venture").textStyle(.title)
                Text("Figures are estimates from your own companies. None of this is a promise of profit.").textStyle(.caption)
            }
            ForEach(VentureOption.Group.allCases, id: \.rawValue) { (g: VentureOption.Group) in group(g) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ventures-start")
    }

    private func group(_ g: VentureOption.Group) -> some View {
        let list: [VentureOption] = options.filter { (o: VentureOption) -> Bool in o.group == g }.sorted { (a: VentureOption, b: VentureOption) -> Bool in
            a.rank != b.rank ? a.rank < b.rank : a.sortCost < b.sortCost
        }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: g.glyph, size: Theme.Icon.small, tint: Theme.accent)
                Text(g.title).textStyle(.label)
                Spacer(minLength: Theme.Space.s)
                Text(g.note).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.7)
            }
            if list.isEmpty {
                EmptyState(glyph: g.glyph, title: g.emptyTitle, message: g.emptyMessage,
                           actionTitle: g == .build || g == .develop ? "Open a company" : nil, action: g == .build || g == .develop ? newCompany : nil, centered: false)
            }
            ForEach(list) { (o: VentureOption) in row(o) }
        }
    }

    private func figure(_ label: String, _ value: String, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(label).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
            Text(value).textStyle(.caption, tint: Theme.ink).lineLimit(lines).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ o: VentureOption) -> some View {
        Button { Haptics.tap(); open(o) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(o.title).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                        Text(o.subtitle).textStyle(.caption).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.s)
                    AcctPill(text: o.status, tone: o.tone)
                }
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    figure("Cost", o.cost, lines: 3)
                    figure("Time", o.time, lines: 3)
                    figure("Payoff", o.payoff, lines: 5)
                }
                if !o.risk.isEmpty {
                    Text(o.risk).textStyle(.caption, tint: Theme.inkFaint).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("venture-option-" + o.id)
    }
}

struct DevelopRef: Identifiable { var id: Int }

struct DevelopSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    var companyID: Int
    @State private var pending: PendingAction?

    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID) { content(e, co) }
        }
        .confirmAction($pending)
        .centerSheetTitle("Develop")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        VStack(alignment: .leading, spacing: PopupSpace.card) {
            if let run = Development.running(co) { running(e, co, run) }
            ForEach(Array(e.developmentProjects(companyID: co.id).enumerated()), id: \.offset) { (_: Int, x: (project: Development.Project, cost: Double)) in
                option(e, co, x.project)
            }
        }
    }

    private func running(_ e: GameEngine, _ co: Company, _ run: (project: String, weeksLeft: Int, cost: Double)) -> some View {
        let left: Int = max(0, run.weeksLeft - e.state.week)
        return CardSection("Running now") {
            VStack(alignment: .leading, spacing: PopupSpace.row) {
                PopupRow(label: "Project", value: Development.projects(for: co, data: e.data).first { (p: Development.Project) -> Bool in p.id == run.project }?.name ?? "New product work")
                PopupRow(label: "Result in", value: left.weeksText)
                PopupRow(label: "Paid", value: store.short(run.cost, in: co))
                Text("Stopping returns the part of the cost not yet spent. Nothing else changes.").popupText(.caption)
                Button("Stop the project") {
                    pending = PendingAction(title: "Stop this project?", message: "The unspent part of \(store.money(run.cost, in: co)) returns to \(co.name). The work done so far is lost.",
                                            button: "Stop it", destructive: true, tone: .warning, icon: "xmark.circle") {
                        let refund: Double? = store.act({ (g: inout GameEngine) -> Double? in g.cancelDevelopment(companyID: co.id) }) ?? nil
                        if let refund { Haptics.success(); store.show("Stopped. \(store.short(refund, in: co)) came back.", tone: "n") } else { store.show("Nothing was running.", tone: "warn") }
                        dismiss()
                    }
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
        }
    }

    @ViewBuilder private func option(_ e: GameEngine, _ co: Company, _ p: Development.Project) -> some View {
        if let plan = e.developmentPlan(companyID: co.id, project: p.id) {
            CardSection(p.name) {
                VStack(alignment: .leading, spacing: PopupSpace.row) {
                    Text(p.text).popupText(.caption)
                    PopupRow(label: "Cost, paid now", value: store.short(plan.cost, in: co))
                    PopupRow(label: "Time", value: plan.weeks.weeksText)
                    PopupRow(label: "Works fully", value: "\(percent(plan.oddsFull))%")
                    PopupRow(label: "Works partly", value: "\(percent(plan.oddsPartial))%")
                    PopupRow(label: "Cash after", value: plan.cashAfter < 0 ? "Not enough" : store.short(plan.cashAfter, in: co))
                    if let why = plan.blockedReason { Text(why).popupText(.risk) }
                    Button("Start for \(store.short(plan.cost, in: co))") { askStart(co, p, plan) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .disabled(plan.blockedReason != nil)
                }
            }
        }
    }

    private func askStart(_ co: Company, _ p: Development.Project, _ plan: Development.Plan) {
        pending = PendingAction(title: "Start \(p.name.lowercased())?",
                                message: "\(store.money(plan.cost, in: co)) leaves \(co.name) now. It takes about \(plan.weeks.weeksText) and works fully in about \(percent(plan.oddsFull))% of tries. The money is spent either way.",
                                button: "Start for \(store.short(plan.cost, in: co))", amount: plan.cost, currency: store.engine?.currency(for: co), tone: .investment, icon: "lightbulb") {
            switch store.act({ (g: inout GameEngine) -> Development.StartResult in g.startDevelopment(companyID: co.id, project: p.id) }) {
            case .ok?: Haptics.success(); store.show("Started. The result comes in about \(plan.weeks.weeksText).", tone: "good"); dismiss()
            case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company.", tone: "warn")
            case .busy?: Haptics.warning(); store.show("Another project is already running.", tone: "warn")
            case .recent?: Haptics.warning(); store.show("You developed this less than two years ago.", tone: "warn")
            default: Haptics.warning(); store.show("That cannot be started now.", tone: "warn")
            }
        }
    }
}

private struct ProjectCaps: View {
    var title: String
    var note: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).capsLabel()
            Spacer(minLength: Theme.Space.s)
            if !note.isEmpty { Text(note).textStyle(.caption, tint: Theme.inkFaint) }
        }
        .padding(.top, Theme.Space.s)
    }
}

private struct ProjectFigures: View {
    var items: [(String, String, Color)]
    var body: some View {
        FigureRow(items: items.map { (it: (String, String, Color)) -> KeyFigures.Item in KeyFigures.Item(label: it.0, value: it.1, tint: it.2) }, columns: max(1, items.count), combineCells: true)
            .padding(.top, Theme.Space.s)
            .overlay(alignment: .top) { Hairline() }
    }
}

private struct ProjectList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    var data: Data
    @ViewBuilder var row: (Data.Element) -> Row
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { (n: Int, x: Data.Element) in
                if n > 0 { Hairline() }
                row(x).padding(.vertical, Theme.Space.m)
            }
        }
    }
}

struct ProjectCardRow: View {
    var title: String
    var sub: String = ""
    var body: some View {
        LedgerRow(title: title, subtitle: sub, chevron: true, lineLimit: 3)
    }
}

struct ProjectsBidsTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: ProjectRows
    @State private var openKey: String?
    @State private var priceIndex = 3
    @State private var higherQuality = false
    @State private var pending: PendingAction?
    private let prices: [Double] = [0.85, 0.9, 0.95, 1.0, 1.05, 1.1]

    private struct Tender: Identifiable { var id: String; var co: Company; var t: ProjectBoard.TenderRow }

    var body: some View {
        let open: [Tender] = rows.flatMap { r in r.board.tenders.filter { $0.qualifies && $0.myBid == nil }.map { Tender(id: "\(r.co.id)-\($0.id)", co: r.co, t: $0) } }
            .sorted { $0.t.weeksToBid < $1.t.weeksToBid }
        let sent: [Tender] = rows.flatMap { r in r.board.myTenders.filter { $0.outcome == nil }.map { Tender(id: "\(r.co.id)-\($0.id)", co: r.co, t: $0) } }
        let closing = open.filter { $0.t.weeksToBid <= 0 }.count
        let blocked = rows.reduce(0) { $0 + $1.board.tenders.filter { !$0.qualifies && $0.myBid == nil }.count }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ProjectCaps(title: "Open tenders · \(open.count)", note: closing > 0 ? "\(closing) close this week" : "")
            if open.isEmpty {
                EmptyState(glyph: Glyph.projects, title: rows.isEmpty ? "No project companies yet" : "No open tender for you",
                           message: rows.isEmpty ? "Builders and agencies bid on tenders from here. None of your companies takes projects yet." : "New tenders are posted through the weeks. More staff and equipment let you qualify for more.")
            }
            ProjectList(data: open) { (x: Tender) in tenderCard(x) }
            if blocked > 0 {
                Text("\(blocked) more \(blocked == 1 ? "tender needs" : "tenders need") requirements your firms do not meet yet.").textStyle(.caption, tint: Theme.inkFaint)
            }
            if !sent.isEmpty {
                ProjectCaps(title: "Your bids · \(sent.count)", note: "waiting for a decision")
                ProjectList(data: sent) { (x: Tender) in sentCard(x) }
            }
        }
        .confirmAction($pending)
    }

    private func tenderCard(_ x: Tender) -> some View {
        let t = x.t
        let closes = t.weeksToBid <= 0 ? "closes this week" : t.weeksToBid == 1 ? "closes next week" : "closes in \(t.weeksToBid) wk"
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title.tidyMoney).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(2)
                    Text("\(x.co.name) · \(t.buyer)").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                Text(closes).textStyle(.caption, tint: t.weeksToBid <= 1 ? Theme.warn : Theme.inkFaint)
            }
            ProjectFigures(items: [("Budget", store.short(t.worth, in: x.co), Theme.ivory), ("Your cost est.", t.costEstimate.map { store.short($0, in: x.co) } ?? "n/a", Theme.ivory), ("Rivals bidding", t.rivals, Theme.ivory)])
            HStack(spacing: Theme.Space.s) {
                NavigationLink { ProjectTimelineDetail(lineID: "t\(x.co.id)-\(t.id)") } label: { Text("Details") }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                Button { Haptics.choose(); Motion.animate(Motion.quickAnimation) { openKey = openKey == x.id ? nil : x.id; priceIndex = 3; higherQuality = false } } label: {
                    Text(openKey == x.id ? "Close" : "Place a bid")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.accent))
            }
            if openKey == x.id { bidPanel(x) }
        }
    }

    private func bidPanel(_ x: Tender) -> some View {
        let t = x.t
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Your price against your list price").textStyle(.caption, tint: Theme.inkFaint)
            SegmentedChoice(items: Array(prices.indices), title: { "\(Int(saturating: (prices[$0] * 100).rounded()))%" }, selection: $priceIndex)
            Toggle(isOn: $higherQuality) {
                Text("Commit to higher quality (costs about 3% more to deliver)").textStyle(.caption, tint: Theme.ink)
            }.tint(Theme.accent).frame(minHeight: 44)
            Text("Lower prices win more often on price-heavy tenders, but you deliver at that price. Bids close in \(max(0, t.weeksToBid).weeksText); the buyer decides on \(GameCalendar.dateString(week: t.awardWeek)). Writing the bid costs \(store.money(t.bidCost, in: x.co)) even if you lose.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            Button("Send the bid") { Haptics.tap(); askBid(x) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
        }
        .padding(.top, Theme.Space.xxs)
    }

    private func askBid(_ x: Tender) {
        let t = x.t
        let pf = prices[priceIndex], hq = higherQuality
        pending = PendingAction(title: "Send this bid?",
                                message: "\(t.title.tidyMoney) at \(Int(saturating: (pf * 100).rounded()))% of your list price\(hq ? ", higher quality" : ""). Writing the bid costs \(store.money(t.bidCost, in: x.co)) from \(x.co.name) whether or not you win.",
                                button: "Send the bid", amount: t.bidCost, currency: engine.currency(for: x.co)) {
            let r = store.act { $0.bidOnTender(companyID: x.co.id, tenderID: t.id, priceFactor: pf, higherQuality: hq) }
            switch r {
            case .sent?: Haptics.success(); store.show("Bid sent. The result comes on \(GameCalendar.dateString(week: t.awardWeek)).", tone: "good"); openKey = nil
            case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company to write the bid.", tone: "warn")
            case .notQualified(let why)?: Haptics.warning(); store.show(why, tone: "warn")
            default: Haptics.warning(); store.show("This tender has closed.", tone: "warn")
            }
        }
    }

    private func sentCard(_ x: Tender) -> some View {
        let t = x.t
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title.tidyMoney).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(2)
                    Text("\(x.co.name) · \(t.buyer) · worth \(store.short(t.worth, in: x.co))").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                Text(t.myBid.map { "Bid \(Int(saturating: ($0 * 100).rounded()))%" } ?? "Bid sent").textStyle(.caption, tint: Theme.accent)
            }
            Text("Decision on \(GameCalendar.dateString(week: t.awardWeek)). You can take the bid back until the bids close; a new one costs the writing fee again.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                store.settle(store.act { $0.withdrawBid(companyID: x.co.id, tenderID: t.id) }, "Your bid is withdrawn.", same: "The bid could not be taken back: the bidding has closed.")
            } label: { Text("Take the bid back") }.buttonStyle(SecondaryButtonStyle(size: .compact))
        }
    }
}

struct ProjectsFinishedTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: ProjectRows

    var body: some View {
        let devs = rows.flatMap { r in r.board.finishedDevelopments.map { (co: r.co, f: $0) } }
        let results = rows.flatMap { r in r.board.myTenders.filter { $0.outcome != nil }.map { (co: r.co, t: $0) } }
        let jobsDone = rows.filter { !$0.board.isDeveloper && $0.board.finishedCount > 0 }
        if devs.isEmpty && results.isEmpty && jobsDone.isEmpty {
            EmptyState(glyph: Glyph.projects, title: "Nothing finished yet", message: "Completed jobs, sold-out developments and decided tenders collect here, with what each one earned.")
        }
        if !devs.isEmpty {
            ProjectCaps(title: "Developments · \(devs.count)")
            ForEach(Array(devs.enumerated()), id: \.offset) { n, x in
                let profit = x.f.revenue - x.f.cost
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(x.f.name).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(1)
                        Text("\(x.co.name) · sold for \(store.short(x.f.revenue, in: x.co)) · cost \(store.short(x.f.cost, in: x.co))").textStyle(.caption, tint: Theme.inkFaint).lineLimit(2)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Text((profit < 0 ? "−" : "+") + store.short(abs(profit), in: x.co)).textStyle(.headline, tint: profit < 0 ? Theme.loss : Theme.gain, numeric: true, weight: .semibold)
                }
                .padding(.vertical, Theme.Space.m)
                .overlay(alignment: .top) { if n > 0 { Hairline() } }
            }
        }
        if !jobsDone.isEmpty {
            ProjectCaps(title: "Jobs and events done")
            ForEach(jobsDone, id: \.co.id) { r in
                ProjectCardRow(title: r.co.name, sub: "\(r.board.finishedCount) finished")
            }
        }
        if !results.isEmpty {
            ProjectCaps(title: "Tender results")
            ForEach(Array(results.prefix(12).enumerated()), id: \.offset) { n, x in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(x.t.title.tidyMoney).textStyle(.body, tint: Theme.ink).lineLimit(1)
                        Text("\(x.co.name) · \(x.t.buyer) · worth \(store.short(x.t.worth, in: x.co))").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.s)
                    AcctPill(text: x.t.outcome == "won" ? "Won" : x.t.outcome == "lost" ? "Lost" : "Closed", tone: x.t.outcome == "won" ? .good : .neutral)
                }
                .padding(.vertical, Theme.Space.m)
                .overlay(alignment: .top) { if n > 0 { Hairline() } }
            }
        }
    }
}
