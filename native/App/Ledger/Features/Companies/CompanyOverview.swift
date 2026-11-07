import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

// MARK: Hero

/// The opening of a company screen: a faint caps label, one large serif figure, one context line (a change in gain or loss colour, then
/// a plain note) and a sparkline of the real history behind the figure when there is any.
struct CompanyHero: View {
    var label: String
    var value: String
    var tint: Color? = nil
    var change: String = ""
    var changeTint: Color? = nil
    var context: String = ""
    var trend: [Double] = []
    var live: Double? = nil
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
            if !change.isEmpty || !context.isEmpty { contextLine }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var figure: some View {
        let t = Text(value.tidyText).font(.system(size: size, weight: .medium, design: .serif).monospacedDigit())
            .foregroundStyle(tint ?? P.ink).lineLimit(1).minimumScaleFactor(0.5)
        if let live { t.moneyFlash(live) } else { t }
    }

    private var contextLine: some View {
        let sep: String = !change.isEmpty && !context.isEmpty ? "  \u{00B7}  " : ""
        return (Text(change.tidyText).foregroundColor(changeTint ?? P.inkSoft) + Text((sep + context).tidyText).foregroundColor(P.inkSoft))
            .font(Font.step(.body, numeric: true))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A titled group of rows sitting on the page: a faint caps label, then the rows (callers put an inset `RowRule` between them). No box.
struct PageGroup<Content: View, Trailing: View>: View {
    var title: String
    /// Space between the children (0 for rows that carry their own rules).
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

/// The hairline between two rows of a group, inset past the leading glyph.
struct RowRule: View {
    var inset: CGFloat = 32
    var body: some View { Hairline().padding(.leading, inset) }
}

/// One matter for the owner: what is wrong, why, and where it is handled.
struct CompanyIssue: Identifiable {
    var id: String
    var glyph: String
    var tint: Color
    var title: String
    var sub: String
    var action: String
    var run: () -> Void
}

/// The one thing to fix first, as a raised card with its own action; the rest of the list opens under it.
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
                            Image(systemName: showAll ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(P.accent)
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

// MARK: Who runs it

/// Who runs a company day to day, from the engine's facts only: the decision chain (a manager or executive), else the owner when the
/// owner works there with hours left for it. Overview, its Team row and the screen header all read this, so they never disagree.
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
            return Reading(short: "Run by you", line: "You work here, \(Int(co.ownerHours.rounded())) h a week", nobody: false, title: "", why: "")
        }
        if OwnerHours.works(co) {
            return Reading(short: "No one runs it", line: "You work here, but with no hours left for it", nobody: true,
                           title: "No one runs it", why: "Your week is full in your other companies and there is no manager")
        }
        return Reading(short: "No one runs it", line: "No manager, and you do not work here", nobody: true,
                       title: "No one runs it", why: "You do not work here and there is no manager")
    }
}

// MARK: Overview

/// One company at a glance, the same cockpit for every trade: profit a week with its trend, cash, revenue and margin; the one thing to
/// fix first; the other sections as rows with their live state; then revenue and profit by month.
struct CompanyOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var section: CompanySection
    @Binding var moneyPart: CompanyMoneyPart
    /// Opens a page of Manage (Equipment, Suppliers ...) on top of the company screen.
    var openOps: (OpsPart) -> Void = { _ in }
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
            }
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
        Motion.animate(Motion.quickAnimation) { section = target }
        Haptics.choose()
    }
    private func goMoney(_ part: CompanyMoneyPart) { moneyPart = part; go(.finances) }

    // MARK: Hero and figures

    /// Profit a week (last closed month) with the change against the month before; before the first month closes, the cash.
    @ViewBuilder private func hero(_ co: Company, _ h: CompanyHealth, _ ops: OperationsFigures?) -> some View {
        if co.status == .open, let pw = ops?.profitPerWeek {
            let change: String = ops?.profitChangePerWeek.map { (d: Double) -> String in
                (d >= 0 ? "\u{25B2} " : "\u{25BC} ") + store.short(abs(d), in: co) + " vs the month before"
            } ?? ""
            let tint: Color? = (ops?.profitChangePerWeek ?? 0) >= 0 ? P.gain : P.loss
            CompanyHero(label: "Profit a week", value: (pw < 0 ? "\u{2212}" : "") + store.money(abs(pw), in: co), tint: pw < 0 ? P.loss : nil,
                        change: change, changeTint: tint, context: change.isEmpty ? "last full month" : "",
                        trend: Array(h.profitSeries.suffix(12)), live: pw)
        } else {
            CompanyHero(label: "Cash", value: store.money(co.cash, in: co), tint: co.cash < 0 ? P.loss : nil,
                        context: verdict(co, h), trend: Array(h.cashSeries.suffix(12)), live: co.cash)
        }
    }

    /// Cash with how long it lasts, revenue and margin over twelve months (profit a week is the hero, so no profit figure here).
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

    /// Nothing needs the owner: one calm line instead of a card.
    private func allClear(_ h: CompanyHealth) -> some View {
        HStack(spacing: Theme.Space.s) {
            LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.medium, tint: P.gain)
            Text(h.label == "Struggling" || h.label == "Tight" ? "Nothing waits for you, but margins are thin." : "Nothing needs you here.")
                .textStyle(.body, tint: P.inkSoft)
        }
        .accessibilityIdentifier("company-all-clear")
    }

    // MARK: What needs the owner

    /// Staff matters (paperwork, worn-out staff, a manager leaving or struggling), the same list the Team tab shows.
    private func staffMatters(_ co: Company) -> [TeamOverview.Issue] {
        (store.teamOverviewNow ?? engine.teamOverview()).issues.filter { $0.companyID == co.id && $0.needsOwner && [.paperwork, .tired, .managerLeaving, .managerWeak].contains($0.kind) }
    }

    /// Everything that needs the owner, most urgent first: money trouble, nobody in charge, decisions waiting, setup, closure, people.
    private func issues(_ co: Company, _ h: CompanyHealth, _ ops: OperationsFigures?) -> [CompanyIssue] {
        var out: [CompanyIssue] = []
        // Open, with customers asking, but it could serve no one last week: nothing comes in until that is fixed.
        let lastWeek: OperationsFigures.Week? = ops?.weeks.last
        if co.status == .open, co.type != "hold", let w = lastWeek, w.capacity <= 0, w.demand > 0 {
            // The engine keeps what limited that week: a required machine in repair goes to Equipment, a missing role to Team.
            let label: String = h.bottleneck ?? ""
            let machine: Bool = label.localizedCaseInsensitiveContains("repair") || label.localizedCaseInsensitiveContains("broken")
            let limit: String = label.isEmpty ? "Staff or equipment is missing: nothing comes in"
                : machine ? "\(label) stopped the work" : "No \(label.lowercased()) to serve them: hire one or work the role yourself"
            out.append(CompanyIssue(id: "nocap", glyph: machine ? Glyph.opsWrench : Glyph.capacity, tint: P.loss, title: "Served no one last week",
                                    sub: "\(Int(w.demand.rounded())) customers wanted to buy. " + limit,
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
            out.append(CompanyIssue(id: "matters", glyph: Glyph.person, tint: P.warn, title: one ? matters[0].title : "\(matters.count) staff matters need you", sub: one ? matters[0].detail : "Paperwork, tired staff or your manager", action: "Open Team") { go(.staff) })
        }
        if people > 0 { out.append(CompanyIssue(id: "people", glyph: Glyph.team, tint: P.warn, title: "\(people) \(people == 1 ? "person needs" : "people need") attention", sub: "Problems, notice or sickness", action: "Open Team") { go(.staff) }) }
        return out
    }

    // MARK: The sections as rows

    @ViewBuilder private func sectionRows(_ co: Company, _ h: CompanyHealth, _ ops: OperationsFigures?) -> some View {
        let tabs: [CompanyTab] = CompanyDetailView.tabs(co, engine)
        let rows: [CompanyTab] = tabs.filter { $0 != .overview }
        if !rows.isEmpty {
            PageGroup("The business") {
                ForEach(Array(rows.enumerated()), id: \.element) { (n: Int, t: CompanyTab) in
                    if n > 0 { RowRule() }
                    sectionRow(t, co, h, ops)
                }
            }
        }
    }

    @ViewBuilder private func sectionRow(_ t: CompanyTab, _ co: Company, _ h: CompanyHealth, _ ops: OperationsFigures?) -> some View {
        switch t {
        case .team:
            let n: Int = co.staff.count
            let boss: String = CompanyRunner.of(co, engine).line
            LedgerRow(leading: .glyph(Glyph.team), leadingTint: P.inkSoft, title: "Team", subtitle: boss, value: n == 0 ? "" : "\(n)", valueNote: n == 0 ? "" : (n == 1 ? "person" : "people"),
                      identifier: "overview-open-team") { go(.staff) }
        case .manage:
            let use: String = ops?.capacityUse.map { "\(Int(($0 * 100).rounded()))%" } ?? ""
            let turnedAway: Bool = h.demandCoverage > 1.05
            let note: String = h.bottleneck.map { b in turnedAway ? "Turning customers away: \(b.lowercased()) is full" : "Room to grow: demand is the limit" } ?? ""
            LedgerRow(leading: .glyph(Glyph.capacity), leadingTint: turnedAway ? P.warn : P.inkSoft, title: "Manage", subtitle: note, value: use, valueNote: use.isEmpty ? "" : "capacity used",
                      identifier: "overview-open-manage") { go(.operations) }
        case .sales:
            let items: Int = engine.salesItems(companyID: co.id).count
            let week: Double = co.lastWeekRevenue
            LedgerRow(leading: .glyph(Glyph.opsBox), leadingTint: P.inkSoft, title: "Sales", subtitle: items == 0 ? "Nothing on sale yet" : "\(items.countText("item")) on sale",
                      value: week > 0 ? store.short(week, in: co) : "", valueNote: week > 0 ? "last week" : "", identifier: "overview-open-sales") { go(.salesMarket) }
        case .stats:
            let rated: String = h.rating > 0 ? StandingWords.ratingText(h.rating) : ""
            LedgerRow(leading: .glyph(Glyph.stats), leadingTint: P.inkSoft, title: "Stats", subtitle: "Reputation " + StandingWords.reputation(co.reputation).lowercased(),
                      value: rated, valueNote: rated.isEmpty ? "" : "rating", identifier: "overview-open-stats") { go(.finances) }
        case .overview:
            EmptyView()
        }
    }

    // MARK: The trend behind the figures

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
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(P.accent)
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
