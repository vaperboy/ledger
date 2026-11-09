import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct CompanyHero: View {
    var label: String
    var value: String
    var tint: Color? = nil
    var change: String = ""
    var changeTint: Color? = nil
    var context: String = ""
    var trend: [Double] = []
    var live: Double? = nil
    var liveFormat: ((Double) -> String)? = nil
    var gain: Double? = nil
    var compareBefore: Double? = nil
    var compareAgainst: String = ""
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 42
    @Environment(\.outsidePalette) private var P

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label.tidyText).textStyle(.label, tint: P.inkFaint)
            HStack(alignment: .center, spacing: Theme.Space.m) {
                figure
                Spacer(minLength: 0)
                if trend.count >= 2 {
                    Sparkline(values: trend, tint: changeTint ?? P.accent).frame(width: 88, height: 36).accessibilityHidden(true)
                }
            }
            if compareBefore != nil, let live {
                HStack(spacing: Theme.Space.s) {
                    ChangeNote(now: live, before: compareBefore, against: compareAgainst, format: liveFormat ?? { (v: Double) -> String in String(Int(v)) }, step: .body)
                    if !context.isEmpty { Text(context.tidyText).textStyle(.body, tint: P.inkSoft) }
                }
            } else if !change.isEmpty || !context.isEmpty { contextLine }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var figure: some View {
        if let live, let liveFormat {
            HStack(spacing: Theme.Space.s) {
                if let gain, abs(gain) >= 0.5 { StockArrow(up: gain > 0, good: gain > 0, side: size * 0.4) }
                RollingMoney(value: live, format: liveFormat)
                    .font(.system(size: size, weight: .medium, design: .serif))
                    .foregroundStyle(tint ?? P.ink).lineLimit(2).minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(((gain ?? 0) > 0.5 ? "up " : (gain ?? 0) < -0.5 ? "down " : "") + liveFormat(live))
        } else {
            plainFigure
        }
    }

    @ViewBuilder private var plainFigure: some View {
        let t = Text(value.tidyText).font(.system(size: size, weight: .medium, design: .serif).monospacedDigit())
            .foregroundStyle(tint ?? P.ink).lineLimit(2).minimumScaleFactor(0.8)
        if let live { t.moneyFlash(live) } else { t }
    }

    private var contextLine: some View {
        let sep: String = !change.isEmpty && !context.isEmpty ? "  \u{00B7}  " : ""
        return (Text(change.tidyText).foregroundColor(changeTint ?? P.inkSoft) + Text((sep + context).tidyText).foregroundColor(P.inkSoft))
            .font(Font.step(.body, numeric: true))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PageGroup<Content: View, Trailing: View>: View {
    var title: String
    var spacing: CGFloat = 0
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    @Environment(\.outsidePalette) private var P

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if !title.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(title.tidyText).textStyle(.label, tint: P.inkFaint)
                    Spacer(minLength: Theme.Space.s)
                    trailing()
                }
            }
            VStack(alignment: .leading, spacing: spacing) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PageGroup where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

struct RowRule: View {
    var inset: CGFloat = 32
    var body: some View { Hairline().padding(.leading, inset) }
}

struct CompanyIssue: Identifiable {
    var id: String
    var glyph: String
    var tint: Color
    var title: String
    var sub: String
    var action: String
    var run: () -> Void
}

struct FixFirstCard: View {
    var issues: [CompanyIssue]
    var heading: String = "Fix this first"
    @State private var showAll = false
    @Environment(\.outsidePalette) private var P

    var body: some View {
        if let first = issues.first {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(heading).textStyle(.label, tint: first.tint)
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    LedgerGlyph(glyph: first.glyph, size: Theme.Icon.large, tint: first.tint)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(first.title.tidyText).textStyle(.headline).fixedSize(horizontal: false, vertical: true)
                        if !first.sub.isEmpty { Text(first.sub.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer(minLength: 0)
                }
                Button { Haptics.tap(); first.run() } label: { Text(first.action) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("company-fix-first")
                if issues.count > 1 {
                    Button {
                        Haptics.choose()
                        Motion.animate(Motion.quickAnimation) { showAll.toggle() }
                    } label: {
                        HStack {
                            Text(showAll ? "Hide the rest" : "\(issues.count - 1) more \(issues.count == 2 ? "needs" : "need") you").textStyle(.body, tint: P.accent)
                            Spacer()
                            LedgerGlyph(glyph: showAll ? Glyph.chevronUp : Glyph.chevronDown, size: 12, tint: P.accent)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("company-needs-more")
                    if showAll {
                        VStack(spacing: 0) {
                            ForEach(Array(issues.dropFirst().enumerated()), id: \.element.id) { (n: Int, i: CompanyIssue) in
                                if n > 0 { Hairline() }
                                LedgerRow(leading: .glyph(i.glyph), leadingTint: i.tint, title: i.title, subtitle: i.sub, valueNote: i.action,
                                          valueNoteTint: P.accent, action: i.run)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.surfaceRaised))
            .elevation(.raised)
        }
    }
}

enum CompanyRunner {
    struct Reading { var short: String; var line: String; var nobody: Bool; var title: String; var why: String }

    static func of(_ co: Company, _ e: GameEngine) -> Reading {
        if let boss = e.decisionChain(companyID: co.id).first {
            let role: String = GameEngine.bossTitle(boss.kind, trade: e.tradeInfo(companyID: co.id)).lowercased()
            return Reading(short: "Run by \(boss.name), \(role)", line: "Run by \(boss.name)", nobody: false, title: "", why: "")
        }
        if co.type == "hold" || co.status != .open { return Reading(short: "", line: "", nobody: false, title: "", why: "") }
        if co.managerID != nil { return Reading(short: "Has a manager", line: "Has a manager", nobody: false, title: "", why: "") }
        if OwnerHours.works(co) && co.ownerHours > 0 {
            return Reading(short: "Run by you", line: "You work here, \(Int(saturating: co.ownerHours.rounded())) h a week", nobody: false, title: "", why: "")
        }
        if OwnerHours.works(co) {
            return Reading(short: "No one runs it", line: "You work here, but with no hours left for it", nobody: true,
                           title: "No one runs it", why: "Your week is full in your other companies and there is no manager")
        }
        return Reading(short: "No one runs it", line: "No manager, and you do not work here", nobody: true,
                       title: "No one runs it", why: "You do not work here and there is no manager")
    }
}

struct CompanyOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var openPage: (OverviewPage) -> Void = { _ in }
    var openTab: (CompanyTab) -> Void = { _ in }
    var openOps: (OpsPart) -> Void = { _ in }
    var openMoney: (CompanyMoneyPart) -> Void = { _ in }
    @State private var months = 12
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let co = company
        let h: CompanyHealth = store.memo("coHealth\(co.id)") { $0.companyHealth(co) } ?? engine.companyHealth(co)
        let ops: OperationsFigures? = engine.operationsFigures(companyID: co.id)
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                hero(co, h, ops)
                strip(co, h, ops)
                structureStrip(co)
            }
            CompanyLiveFigures(engine: engine, company: co)
            let list: [CompanyIssue] = issues(co, h, ops)
            if list.isEmpty {
                if co.status == .open { allClear(h) }
            } else {
                FixFirstCard(issues: list)
            }
            sectionRows(co, h, ops)
            performance(co, h)
        }
    }

    private func go(_ target: CompanySection) {
        guard CompanyDetailView.availableSections(company, engine).contains(target) else { return }
        Haptics.choose()
        switch target {
        case .staff, .holding: openTab(.people)
        case .operations: openPage(.run)
        case .finances: openPage(.stats)
        case .salesMarket: openPage(.sales)
        case .setup: store.openCompany(company.id, section: .setup)
        default: break
        }
    }

    private func goMoney(_ part: CompanyMoneyPart) { Haptics.choose(); openMoney(part) }

    @ViewBuilder private func hero(_ co: Company, _ h: CompanyHealth, _ ops: OperationsFigures?) -> some View {
        if co.status == .open, let pw = ops?.profitPerWeek {
            let delta: Double? = ops?.profitChangePerWeek
            let tint: Color? = (delta ?? 0) >= 0 ? P.gain : P.loss
            CompanyHero(label: "Profit a week", value: store.money(abs(pw), in: co), tint: pw < 0 ? P.loss : (pw > 0.5 ? P.gain : nil),
                        changeTint: tint, context: delta == nil ? "last full month" : "",
                        trend: Array(h.profitSeries.suffix(12)), live: pw,
                        liveFormat: { (v: Double) -> String in store.money(abs(v), in: co) }, gain: pw,
                        compareBefore: delta.map { (d: Double) -> Double in pw - d }, compareAgainst: "last month")
        } else {
            CompanyHero(label: "Cash", value: store.money(co.cash, in: co), tint: co.cash < 0 ? P.loss : nil,
                        context: verdict(co, h), trend: Array(h.cashSeries.suffix(12)), live: co.cash,
                        liveFormat: { (v: Double) -> String in store.money(v, in: co) })
        }
    }

    @ViewBuilder private func strip(_ co: Company, _ h: CompanyHealth, _ ops: OperationsFigures?) -> some View {
        let heroIsCash: Bool = !(co.status == .open && ops?.profitPerWeek != nil)
        let margin: String = h.marginTTM.map { String(format: "%.0f%%", $0 * 100) } ?? "\u{2013}"
        let runway: String = h.runwayWeeks != nil ? "lasts \(RunwayText.of(h))" : (h.profitTTM > 0 ? "self-funding" : "")
        let short: Bool = h.runwayWeeks.map { $0 < 8 } ?? false
        let cashTint: Color = co.cash < 0 ? P.loss : (short ? P.warn : P.ink)
        let cashCell = KeyFigures.Item(label: "Cash", value: store.short(co.cash, in: co), tint: cashTint, sub: runway, live: co.cash)
        let revCell = KeyFigures.Item(label: "Revenue 12 mo", value: store.short(h.revenueTTM, in: co), live: h.revenueTTM)
        let marginCell = KeyFigures.Item(label: "Margin", value: margin, tint: (h.marginTTM ?? 0) < 0 ? P.loss : P.ink)
        let healthCell = KeyFigures.Item(label: "Health", value: h.label, tint: HealthChip.tint(h.label))
        FigureRow(items: heroIsCash ? [revCell, marginCell, healthCell] : [cashCell, revCell, marginCell], combineCells: true)
    }

    @ViewBuilder private func structureStrip(_ co: Company) -> some View {
        let line: String = structureLine(co)
        if !line.isEmpty {
            Text(line).textStyle(.caption, tint: P.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("overview-structure-strip")
        }
    }

    private func structureLine(_ co: Company) -> String {
        guard co.status.isLive else { return "" }
        var parts: [String] = []
        if let pos = engine.branchParent(companyID: co.id), let chain = engine.chainSummary(id: pos.chainID) {
            parts.append("Part of " + chain.name)
        } else if co.type != "hold" {
            if let hid = engine.ownerLine(companyID: co.id).holdingID, let holding = engine.state.company(hid) {
                parts.append("Part of " + holding.name)
            } else if let host = HoldingStakes.divisionHostID(co).flatMap({ (id: Int) -> Company? in engine.state.company(id) }) {
                parts.append("Division of " + host.name)
            }
        }
        if co.status != .setup {
            let gm: GroupManagement? = store.memo("groupMgmt") { (e: GameEngine) -> GroupManagement in e.groupManagement() }
            parts.append("run by " + ChainWords.runnerName(gm, companyID: co.id))
        }
        parts.append(ChainWords.lowered(ChainWords.ownerText(engine, companyID: co.id, showFull: true)))
        let joined: String = parts.joined(separator: " \u{00B7} ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    private func verdict(_ co: Company, _ h: CompanyHealth) -> String {
        switch co.status {
        case .setup: return "Not open yet: finish the setup to start trading"
        case .closed: return "Closed for now: rent and part of the wages still run"
        case .sold: return "No longer yours"
        case .bust: return "Bankrupt"
        default: break
        }
        if co.cash < 0 { return "Out of cash: bills and wages are at risk" }
        if h.runwayWeeks != nil { return "Losing money: the cash lasts \(RunwayText.of(h))" }
        return h.label == "New" ? "Profit shows after the first full month" : "\(String(format: "%.0f", h.weeksOfCash)) weeks of costs in hand"
    }

    private func allClear(_ h: CompanyHealth) -> some View {
        HStack(spacing: Theme.Space.s) {
            LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.medium, tint: P.gain)
            Text(h.label == "Struggling" || h.label == "Tight" ? "Nothing waits for you, but margins are thin." : "Nothing needs you here.")
                .textStyle(.body, tint: P.inkSoft)
        }
        .accessibilityIdentifier("company-all-clear")
    }

    private func staffMatters(_ co: Company) -> [TeamOverview.Issue] {
        (store.teamOverviewNow ?? engine.teamOverview()).issues.filter { $0.companyID == co.id && $0.needsOwner && [.tired, .managerLeaving, .managerWeak].contains($0.kind) }
    }

    private func issues(_ co: Company, _ h: CompanyHealth, _ ops: OperationsFigures?) -> [CompanyIssue] {
        var out: [CompanyIssue] = []
        let lastWeek: OperationsFigures.Week? = ops?.weeks.last
        if co.status == .open, co.type != "hold", let w = lastWeek, w.capacity <= 0, w.demand > 0 {
            let label: String = h.bottleneck ?? ""
            let machine: Bool = label.localizedCaseInsensitiveContains("repair") || label.localizedCaseInsensitiveContains("broken")
            let limit: String = label.isEmpty ? "Staff or equipment is missing: nothing comes in"
                : machine ? "\(label) stopped the work" : "No \(label.lowercased()) to serve them: hire one or work the role yourself"
            out.append(CompanyIssue(id: "nocap", glyph: machine ? Glyph.opsWrench : Glyph.capacity, tint: P.loss, title: "Served no one last week",
                                    sub: "\(Int(saturating: w.demand.rounded())) customers wanted to buy. " + limit,
                                    action: machine ? "Open Equipment" : (label.isEmpty ? "Open Manage" : "Open Team")) {
                if machine { openOps(.equipment) } else if label.isEmpty { go(.operations) } else { go(.staff) }
            })
        }
        let asks = engine.state.inbox.filter { $0.companyID == co.id && $0.status == "open" }.sorted { $0.week > $1.week }
        let people = co.staff.filter { !$0.value("flag").isNull || $0.noticeWeeks > 0 || $0.sickUntilWeek != nil }.count
        let matters = staffMatters(co)
        let runner: CompanyRunner.Reading = CompanyRunner.of(co, engine)
        let setupLeft = co.status == .setup ? engine.openingChecklist(companyID: co.id).filter { !$0.isDone }.count : 0
        let behind = engine.state.loans.contains { $0.companyID == co.id && $0.int("miss") > 0 } || co.int("supCut") > 0 || co.num("vatOver") > 1 || co.int("loanCall") != 0
        if co.cash < 0 && co.status == .open {
            out.append(CompanyIssue(id: "cash", glyph: Glyph.warning, tint: P.loss, title: "Out of cash", sub: "Bills and wages are at risk: put money in or cut costs", action: "Open finances") { goMoney(.summary) })
        }
        if behind { out.append(CompanyIssue(id: "behind", glyph: Glyph.warning, tint: P.loss, title: "Behind on payments", sub: "Loans, VAT or suppliers", action: "Open finances") { goMoney(.summary) }) }
        if runner.nobody { out.append(CompanyIssue(id: "nobody", glyph: Glyph.person, tint: P.loss, title: runner.title, sub: runner.why, action: "Open Team") { go(.staff) }) }
        for m in asks.prefix(3) {
            let mid = m.id
            out.append(CompanyIssue(id: "ask\(m.id)", glyph: Glyph.inbox, tint: P.warn, title: m.title, sub: m.from.isEmpty ? "Waiting for your answer" : "From \(m.from)", action: "Decide") { store.openMessage(mid) })
        }
        if setupLeft > 0 { out.append(CompanyIssue(id: "setup", glyph: Glyph.reports, tint: P.warn, title: "\(setupLeft.countText("thing")) left before opening", sub: "Documents, premises, equipment, stock", action: "Open setup") { go(.setup) }) }
        if co.status == .closed { out.append(CompanyIssue(id: "closed", glyph: Glyph.settings, tint: P.warn, title: "Closed", sub: "Reopen it or close down for good", action: "Open settings") { goMoney(.settings) }) }
        if !matters.isEmpty {
            let one: Bool = matters.count == 1
            out.append(CompanyIssue(id: "matters", glyph: Glyph.person, tint: P.warn, title: one ? matters[0].title : "\(matters.count) staff matters need you", sub: one ? matters[0].detail : "Tired staff or your manager", action: "Open Team") { go(.staff) })
        }
        if people > 0 { out.append(CompanyIssue(id: "people", glyph: Glyph.team, tint: P.warn, title: "\(people) \(people == 1 ? "person needs" : "people need") attention", sub: "Problems, notice or sickness", action: "Open Team") { go(.staff) }) }
        return out
    }

    @ViewBuilder private func sectionRows(_ co: Company, _ h: CompanyHealth, _ ops: OperationsFigures?) -> some View {
        let a: [CompanySection] = CompanyDetailView.availableSections(co, engine)
        let sells: Bool = a.contains(.operations)
        PageGroup("The business") {
            if sells {
                let items: Int = engine.salesItems(companyID: co.id).count
                let week: Double = co.lastWeekRevenue
                LedgerRow(leading: .glyph(Glyph.opsBox), leadingTint: P.inkSoft, title: "Sales", subtitle: items == 0 ? "Nothing on sale yet" : "\(items.countText("item")) on sale",
                          value: week > 0 ? store.short(week, in: co) : "", valueNote: week > 0 ? "last week" : "", identifier: "overview-open-sales") { openPage(.sales) }
                RowRule()
                let use: String = ops?.capacityUse.map { "\(Int(saturating: ($0 * 100).rounded()))%" } ?? ""
                let turnedAway: Bool = h.demandCoverage > 1.05
                let note: String = h.bottleneck.map { b in turnedAway ? "Turning customers away: \(b.lowercased()) is full" : "Room to grow: demand is the limit" } ?? ""
                LedgerRow(leading: .glyph(Glyph.capacity), leadingTint: turnedAway ? P.warn : P.inkSoft, title: "Run the place", subtitle: note, value: use, valueNote: use.isEmpty ? "" : "capacity used",
                          identifier: "overview-open-manage") { openPage(.run) }
                RowRule()
            }
            let rated: String = h.rating > 0 ? StandingWords.ratingText(h.rating) : ""
            LedgerRow(leading: .glyph(Glyph.stats), leadingTint: P.inkSoft, title: "Money and stats", subtitle: "Reputation " + StandingWords.reputation(co.reputation).lowercased(),
                      value: rated, valueNote: rated.isEmpty ? "" : "rating", identifier: "overview-open-stats") { openPage(.stats) }
            if sells {
                RowRule()
                LedgerRow(leading: .glyph(Glyph.person), leadingTint: P.inkSoft, title: "Customers", identifier: "overview-open-customers") { openPage(.customers) }
            }
            if CompanyDetailView.hasProjects(co, engine) {
                RowRule()
                LedgerRow(leading: .glyph(Glyph.reports), leadingTint: P.inkSoft, title: "Projects", identifier: "overview-open-projects") { openPage(.projects) }
            }
        }
    }

    private func performance(_ co: Company, _ h: CompanyHealth) -> some View {
        let rev = Array(h.revenueSeries.suffix(months)), prof = Array(h.profitSeries.suffix(months))
        let monthsBinding = Binding<Int>(get: { months }, set: { months = $0 })
        let spans: [Int] = [6, 12, 24]
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("By month").textStyle(.label, tint: P.inkFaint)
                Spacer()
                Menu {
                    ForEach(spans, id: \.self) { (s: Int) in Button(spanTitle(s)) { monthsBinding.wrappedValue = s } }
                } label: {
                    HStack(spacing: 4) {
                        Text(spanTitle(months)).textStyle(.caption, tint: P.accent)
                        LedgerGlyph(glyph: Glyph.chevronDown, size: 10, tint: P.accent)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("overview-chart-span")
            }
            ChartFrame(key: [("Revenue", Theme.accent), ("Profit", Theme.gain)], height: 120, isEmpty: rev.count < 2,
                       emptyText: "The chart starts after the first full month.") {
                RevenueProfitChart(revenue: rev, profit: prof, format: { store.short($0, in: co) }, height: 120)
            }
        }
    }

    private func spanTitle(_ s: Int) -> String { s == 6 ? "6 months" : s == 12 ? "1 year" : "2 years" }
}
