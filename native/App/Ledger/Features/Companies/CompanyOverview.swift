import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

// MARK: Overview

/// One company at a glance, the same template for every trade, in the new look. Scan order: the cash hero with the key figures, what
/// needs the owner (warning cards), last week, and revenue and profit by month. Families with a model of their own (energy, fish,
/// property, finance, club, holding) keep this summary and do their detailed work in their own section.
struct CompanyOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var section: CompanySection
    @Binding var moneyPart: CompanyMoneyPart
    @State private var months = 12
    /// Energy, fish, holding and club have their own section instead of the customers-and-capacity picture.
    private var isSpecial: Bool { engine.tradeInfo(companyID: company.id).map { SpecialFamilies.handles($0) } ?? false }

    var body: some View {
        let co = company
        let h = engine.companyHealth(co)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            hero(co, h)
            needsYou(co)
            if co.status == .open && !isSpecial { operations(co, h) }
            performance(co, h)
        }
    }

    private func go(_ target: CompanySection) {
        guard CompanyDetailView.availableSections(company, engine).contains(target) else { return }
        withAnimation(.snappy(duration: 0.2)) { section = target }
        Haptics.choose()
    }
    private func goMoney(_ part: CompanyMoneyPart) { moneyPart = part; go(.finances) }

    /// Staff matters shown under "Needs you" (paperwork, worn-out staff, a manager leaving or struggling), the same list the Team tab shows.
    private func staffMatters(_ co: Company) -> [TeamOverview.Issue] {
        engine.teamOverview().issues.filter { $0.companyID == co.id && $0.needsOwner && [.paperwork, .tired, .managerLeaving, .managerWeak].contains($0.kind) }
    }

    // 1. Hero: cash first, the verdict in words, then profit, margin and the figures that decide what happens next
    private func hero(_ co: Company, _ h: CompanyHealth) -> some View {
        let loss: Bool = h.profitTTM < 0
        let cashSub: String = h.runwayWeeks != nil ? "lasts \(RunwayText.of(h))" : String(format: "%.0f weeks of costs", h.weeksOfCash)
        let margin: String = h.marginTTM.map { String(format: "%.1f%%", $0 * 100) } ?? "–"
        let first: [StatStrip.Cell] = [
            .init(label: "Profit 12 mo", value: (loss ? "−" : "") + store.short(abs(h.profitTTM), in: co), tint: loss ? Theme.loss : Theme.ivory),
            .init(label: "Margin", value: margin),
            .init(label: "Revenue 12 mo", value: store.short(h.revenueTTM, in: co)),
        ]
        let second: [StatStrip.Cell] = [
            .init(label: "Costs a week", value: store.short(h.weeklyCost, in: co)),
            .init(label: "Debt", value: store.short(h.debt, in: co), tint: h.debt > 0 ? Theme.loss : Theme.ivory),
            .init(label: "Value", value: store.short(h.value, in: co)),
        ]
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Cash").capsLabel()
                HStack(alignment: .firstTextBaseline) {
                    Text(store.money(co.cash, in: co)).font(.hero(36)).foregroundStyle(co.cash < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                    Spacer(minLength: 8)
                    if let g = h.revenueGrowth {
                        Text(String(format: "Revenue %+.0f%% vs 3 mo", g * 100)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.change(g))
                    }
                }.padding(.top, 2)
                Text("Cash \(cashSub)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).padding(.top, 2)
                if showVerdict(co, h) { Text(verdict(co, h)).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true).padding(.top, 6) }
                StatStrip(cells: first).padding(.top, 12)
                StatStrip(cells: second).padding(.top, 10)
            }
        }
    }

    /// The verdict sentence is shown when it adds something: a company that is not trading, short of cash, or not doing well. A healthy
    /// company's figures already say so, and the line would only push the overview past one screen.
    private func showVerdict(_ co: Company, _ h: CompanyHealth) -> Bool {
        if co.status != .open || co.cash < 0 { return true }
        return h.label == "Tight" || h.label == "Struggling" || (h.runwayWeeks.map { $0 < 8 } ?? false)
    }

    private func verdict(_ co: Company, _ h: CompanyHealth) -> String {
        switch co.status {
        case .setup: return "Not open yet: finish the setup to start trading."
        case .closed: return "Closed for now: no sales, but rent and part of the wages still run."
        case .sold: return "No longer yours."
        case .bust: return "Bankrupt."
        default: break
        }
        if co.cash < 0 { return "Out of cash: bills and wages are at risk. Put money in or cut costs." }
        if let w = h.runwayWeeks, w < 8 { return "Losing money: at this rate the cash runs out in \(Int(w).weeksText)." }
        switch h.label {
        case "Thriving": return "Doing very well: profitable, growing and with cash to spare."
        case "Healthy": return "Doing well: profitable and paying its way."
        case "Tight": return "Getting by, with little room: watch costs and cash."
        case "Struggling": return "Struggling: costs are higher than what comes in."
        default: return "Too new to judge: the picture fills in over the first months."
        }
    }

    // 2. What needs the owner here, first: decisions waiting, setup, closure, unpaid bills, people problems, nobody in charge
    @ViewBuilder private func needsYou(_ co: Company) -> some View {
        let asks = engine.state.inbox.filter { $0.companyID == co.id && $0.status == "open" }.sorted { $0.week > $1.week }
        let people = co.staff.filter { !$0.value("flag").isNull || $0.noticeWeeks > 0 || $0.sickUntilWeek != nil }.count
        // The same list the Team tab shows (paperwork, worn-out staff, a manager leaving or struggling), so the two screens never disagree.
        let matters = staffMatters(co)
        let nobody = co.status == .open && co.type != "hold" && co.managerID == nil && co.ownerHours == 0 && engine.decisionChain(companyID: co.id).isEmpty
        let setupLeft = co.status == .setup ? engine.openingChecklist(companyID: co.id).filter { !$0.isDone }.count : 0
        let behind = engine.state.loans.contains { $0.companyID == co.id && $0.int("miss") > 0 } || co.int("supCut") > 0 || co.num("vatOver") > 1 || co.int("loanCall") != 0
        if !(asks.isEmpty && setupLeft == 0 && co.status != .closed && !behind && people == 0 && matters.isEmpty && !nobody) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Needs you").capsLabel()
                    Spacer(minLength: 8)
                    if !asks.isEmpty { Text(asks.count.countText("decision")).font(.system(size: 11)).foregroundStyle(Theme.caution) }
                }
                ForEach(Array(asks.prefix(2).enumerated()), id: \.element.id) { _, m in
                    warning(glyph: Glyph.inbox, tint: Theme.caution, title: m.title, sub: m.from.isEmpty ? "Waiting for your answer" : "From \(m.from)", action: "Decide") {
                        store.openMessage(m.id)
                    }
                }
                if asks.count > 2 { Text("and \(asks.count - 2) more in Inbox").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
                if setupLeft > 0 { warning(glyph: Glyph.reports, tint: Theme.caution, title: "\(setupLeft.countText("thing")) left before opening", sub: "Documents, premises, equipment, stock", action: "Setup") { go(.setup) } }
                if co.status == .closed { warning(glyph: Glyph.settings, tint: Theme.caution, title: "Closed", sub: "Reopen it or close down for good", action: "Settings") { goMoney(.settings) } }
                if behind { warning(glyph: Glyph.warning, tint: Theme.loss, title: "Behind on payments", sub: "Loans, VAT or suppliers", action: "Finances") { goMoney(.summary) } }
                if !matters.isEmpty {
                    let one: Bool = matters.count == 1
                    warning(glyph: Glyph.person, tint: Theme.caution, title: one ? matters[0].title : "\(matters.count) staff matters need you", sub: one ? matters[0].detail : "Paperwork, tired staff or your manager", action: "Team") { go(.staff) }
                }
                if people > 0 { warning(glyph: Glyph.team, tint: Theme.caution, title: "\(people) \(people == 1 ? "person needs" : "people need") attention", sub: "Problems, notice or sickness", action: "Team") { go(.staff) } }
                if nobody { warning(glyph: Glyph.person, tint: Theme.loss, title: "No one runs it", sub: "You do not work here and there is no manager", action: "Team") { go(.staff) } }
            }
        }
    }

    /// A warning card: tinted outline, round icon, what is wrong, and a tiny outlined button to where it is handled.
    private func warning(glyph: String, tint: Color, title: String, sub: String, action: String, _ run: @escaping () -> Void) -> some View {
        Card(padding: 12, radius: Theme.Radius.row, stroke: tint.opacity(0.45)) {
            HStack(alignment: .center, spacing: 12) {
                IconCircle(glyph: glyph, size: 36, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.tidyText).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                    Text(sub.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
                }
                Spacer(minLength: 6)
                SmallOutlineButton(title: action, action: run)
            }
        }
    }

    // 3. Last week: what limited sales, and how customers see the place
    private func operations(_ co: Company, _ h: CompanyHealth) -> some View {
        let turnedAway: Bool = h.demandCoverage > 1.05
        let note: String? = h.bottleneck.map { b in
            turnedAway ? "Limited by \(b.lowercased()) · turning customers away." : "Spare room: demand, not \(b.lowercased()), limits sales."
        }
        let cells: [StatStrip.Cell] = [
            .init(label: "Rating", value: StandingWords.ratingText(h.rating)),
            .init(label: "Reputation", value: StandingWords.reputation(co.reputation)),
            .init(label: "Quality", value: "\(Int(co.quality.rounded()))"),
        ]
        let capTint: Color = h.capacityUse > 0.95 ? Theme.caution : Theme.gold
        let demandTint: Color = turnedAway ? Theme.caution : Theme.gain
        let demandFraction: Double = h.demandCoverage > 0 ? min(1, 1 / h.demandCoverage) : 0
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last week").capsLabel()
                Spacer(minLength: 8)
                Text("\(Int(h.servedLastWeek.rounded())) served of \(Int(h.capacityLastWeek.rounded())) possible").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }
            Card(padding: 14, radius: Theme.Radius.card) {
                VStack(alignment: .leading, spacing: 10) {
                    RateBar(label: "Capacity used", fraction: h.capacityUse, tint: capTint)
                    RateBar(label: "Demand met", fraction: demandFraction, tint: demandTint)
                    HStack {
                        Text("Awareness").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        Spacer()
                        Text(StandingWords.awareness(co.awareness)).font(.system(size: 12)).foregroundStyle(Theme.ivory)
                    }
                    if let note {
                        Text(note).font(.system(size: 11.5)).foregroundStyle(turnedAway ? Theme.caution : Theme.ivoryMuted)
                    }
                    StatStrip(cells: cells).padding(.top, 2)
                }
            }
        }
    }

    // 4. The trend behind the figures
    private func performance(_ co: Company, _ h: CompanyHealth) -> some View {
        let rev = Array(h.revenueSeries.suffix(months)), prof = Array(h.profitSeries.suffix(months))
        let monthsBinding = Binding<Int>(get: { months }, set: { months = $0 })
        let spans: [Int] = [6, 12, 24]
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Revenue and profit by month").capsLabel()
            Card(padding: 14, radius: Theme.Radius.card) {
                VStack(alignment: .leading, spacing: 10) {
                    SegmentedPill(items: spans, title: { $0 == 6 ? "6 months" : $0 == 12 ? "1 year" : "2 years" }, selection: monthsBinding)
                    if rev.count < 2 {
                        Text("The chart starts after the first full month.").font(.caption).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    } else {
                        ChartKey(items: [("Revenue", Theme.gold), ("Profit", Theme.gain)])
                        RevenueProfitChart(revenue: rev, profit: prof, format: { store.short($0, in: co) }, height: 104)
                    }
                }
            }
        }
    }
}

// MARK: Setup

/// The opening checklist. Each open item leads to where it is done: premises and equipment to the equipment screen, cash for stock to
/// moving money in, properties and products to the family's own section. Documents have no single-document action in the engine:
/// they are applied for by "Fill in what is missing".
struct CompanySetupSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var section: CompanySection
    @Binding var moneyPart: CompanyMoneyPart
    @State private var pending: PendingAction?

    var body: some View {
        let items = engine.openingChecklist(companyID: company.id)
        let left = items.filter { !$0.isDone }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection(title: "Before opening", trailing: {
                Text(left.isEmpty ? "ready" : "\(items.count - left.count) of \(items.count) done").font(.system(size: 11.5)).foregroundStyle(left.isEmpty ? Theme.gain : Theme.ivoryFaint)
            }) {
                VStack(spacing: 0) {
                    if items.isEmpty { Text("Nothing left to do.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(Array((left + items.filter { $0.isDone }).enumerated()), id: \.element.id) { n, it in
                        if n > 0 { Hairline() }
                        checklistRow(it)
                    }
                }
            }
            EquipmentEntryRow(company: company)
            if company.status == .setup {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Button("Fill in what is missing…") { confirmQuickSetup() }.buttonStyle(QuietButtonStyle())
                    Button("Open for business") { open() }.buttonStyle(QuietButtonStyle()).disabled(!left.isEmpty && !left.allSatisfy { $0.id == "stockcash" })
                    if !left.isEmpty { Text("Opens by itself once every item is done and the paperwork is approved.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                }
            }
        }
        .confirmAction($pending)
    }

    @ViewBuilder private func checklistRow(_ it: OpeningChecklist.Item) -> some View {
        let target = destination(it)
        let content = HStack(alignment: .center, spacing: 10) {
            Image(systemName: it.isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(it.isDone ? Theme.gain : Theme.ivoryFaint)
            VStack(alignment: .leading, spacing: 1) {
                Text(it.title.tidyMoney).font(.system(size: 13.5, weight: it.isDone ? .regular : .medium)).foregroundStyle(it.isDone ? Theme.ivoryMuted : Theme.ivory)
                if !it.detail.isEmpty { Text(it.detail.tidyMoney).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
            }
            Spacer(minLength: 6)
            if !it.isDone {
                switch target {
                case .none: Text(it.id.hasPrefix("doc:") ? "with Fill in" : "").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                default: Text(actionLabel(target)).font(.system(size: 11.5)).foregroundStyle(Theme.gold).fixedSize()
                }
            }
        }.padding(.vertical, 9).contentShape(Rectangle())
        if it.isDone {
            content
        } else {
            switch target {
            case .equipment(let premises):
                NavigationLink { CompanyEquipmentScreen(companyID: company.id, opensOnPremises: premises) } label: { content }.buttonStyle(PressableStyle())
            case .money:
                Button { moneyPart = .owners; section = .finances; Haptics.choose() } label: { content }.buttonStyle(PressableStyle())
            case .section(let s):
                Button { if CompanyDetailView.availableSections(company, engine).contains(s) { section = s; Haptics.choose() } } label: { content }.buttonStyle(PressableStyle())
            case .none:
                content
            }
        }
    }

    private enum Target { case equipment(premises: Bool), money, section(CompanySection), none }

    private func destination(_ it: OpeningChecklist.Item) -> Target {
        switch it.id {
        case "prem": return .equipment(premises: true)
        case "mw": return .equipment(premises: false)
        case "stockcash", "cash": return .money
        case "prop": return .section(.properties)
        case "prod", "ver": return .section(.book)
        default: return it.id.hasPrefix("eq:") ? .equipment(premises: false) : .none
        }
    }

    private func actionLabel(_ t: Target) -> String {
        switch t {
        case .equipment(let p): return p ? "Choose →" : "Buy →"
        case .money: return "Put money in →"
        case .section(let s): return "\(s.rawValue) →"
        case .none: return ""
        }
    }

    private func confirmQuickSetup() {
        pending = PendingAction(title: "Fill in what is missing?", message: "Applies for every document, rents a standard place, buys the standard equipment (financed where possible) and hires the standard team, paid from company cash. It opens by itself once the paperwork is approved.", button: "Fill in", alwaysAsk: true) {
            let failed = store.act { $0.quickSetup(companyID: company.id) } ?? []
            if failed.isEmpty { Haptics.success(); store.show("Done: documents applied for, premises, equipment and team in place.", tone: "good") }
            else { Haptics.warning(); store.show("Partly done. Not possible: \(failed.prefix(3).joined(separator: "; "))\(failed.count > 3 ? "…" : "")", tone: "warn") }
        }
    }

    private func open() {
        switch store.act({ $0.openCompany(companyID: company.id) }) {
        case .ok?: Haptics.success(); store.show("\(company.name) is open.", tone: "good"); section = .overview
        case .needsStockCash(let need)?: Haptics.warning(); store.show("Needs \(store.money(need, in: company)) in the company for opening stock.", tone: "warn")
        default: Haptics.warning(); store.show("Something is still missing.", tone: "warn")
        }
    }
}
