import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

// MARK: Overview

/// One company at a glance, the same template for every trade: how healthy it is, what needs the owner, who runs it, why the figures
/// look the way they do, then the operating picture and the trend. Families with a model of their own (energy, fish, property, finance,
/// club, holding) keep this summary and do their detailed work in their own section.
struct CompanyOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var section: CompanySection
    @Binding var moneyPart: CompanyMoneyPart
    @State private var months = 12
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Energy, fish, holding and club have their own section instead of the customers-and-capacity picture.
    private var isSpecial: Bool { engine.tradeInfo(companyID: company.id).map { SpecialFamilies.handles($0) } ?? false }

    var body: some View {
        let co = company
        let h = engine.companyHealth(co)
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.l) { health(co, h); needsYou(co); whoRunsIt(co); diagnosis(co) }
                VStack(alignment: .leading, spacing: Theme.Space.l) { if co.status == .open && !isSpecial { operations(co, h) }; performance(co, h) }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                health(co, h)
                needsYou(co)
                whoRunsIt(co)
                diagnosis(co)
                if co.status == .open && !isSpecial { operations(co, h) }
                performance(co, h)
            }
        }
    }

    private func go(_ target: CompanySection) {
        guard CompanyDetailView.availableSections(company, engine).contains(target) else { return }
        withAnimation(.snappy(duration: 0.2)) { section = target }
        Haptics.choose()
    }
    private func goMoney(_ part: CompanyMoneyPart) { moneyPart = part; go(.finances) }

    // 1. Health: the verdict in words, then the figures that decide what happens next
    private func health(_ co: Company, _ h: CompanyHealth) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profit · 12 months").capsLabel()
                    Text((h.profitTTM < 0 ? "−" : "") + store.money(abs(h.profitTTM), in: co)).font(.hero(34))
                        .foregroundStyle(h.profitTTM < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if co.status == .open { HealthChip(label: h.label) } else { StatusChip(company: co) }
                    if let g = h.revenueGrowth { Text(String(format: "Revenue %+.0f%% vs 3 mo", g * 100)).foregroundStyle(Theme.change(g)) }
                }.font(.system(size: 11.5).monospacedDigit())
            }
            Text(verdict(co, h)).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            KeyFigures(items: [
                .init(label: "Cash", value: store.short(co.cash, in: co), tint: co.cash < 0 ? Theme.loss : Theme.ivory,
                      sub: h.runwayWeeks != nil ? "lasts \(RunwayText.of(h))" : String(format: "%.0f weeks of costs", h.weeksOfCash)),
                .init(label: "Revenue", value: store.short(h.revenueTTM, in: co), sub: "12 months"),
                .init(label: "Margin", value: h.marginTTM.map { String(format: "%.1f%%", $0 * 100) } ?? "–"),
                .init(label: "Costs a week", value: store.short(h.weeklyCost, in: co), sub: "\(co.staff.count) staff"),
                .init(label: "Debt", value: store.short(h.debt, in: co), tint: h.debt > 0 ? Theme.loss : Theme.ivory),
                .init(label: "Value", value: store.short(h.value, in: co), sub: "book + goodwill"),
            ]).padding(.top, 12)
        }
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
        if let w = h.runwayWeeks, w < 8 { return "Losing money: at this rate the cash runs out in \(Int(w)) weeks." }
        switch h.label {
        case "Thriving": return "Doing very well: profitable, growing and with cash to spare."
        case "Healthy": return "Doing well: profitable and paying its way."
        case "Tight": return "Getting by, with little room: watch costs and cash."
        case "Struggling": return "Struggling: costs are higher than what comes in."
        default: return "Too new to judge: the picture fills in over the first months."
        }
    }

    // 2. What needs the owner here: decisions waiting, setup, closure, unpaid bills, people problems, nobody in charge
    @ViewBuilder private func needsYou(_ co: Company) -> some View {
        let asks = engine.state.inbox.filter { $0.companyID == co.id && $0.status == "open" }.sorted { $0.week > $1.week }
        let people = co.staff.filter { !$0.value("flag").isNull || $0.noticeWeeks > 0 || $0.sickUntilWeek != nil }.count
        let nobody = co.status == .open && co.type != "hold" && co.managerID == nil && co.ownerHours == 0 && engine.decisionChain(companyID: co.id).isEmpty
        let setupLeft = co.status == .setup ? engine.openingChecklist(companyID: co.id).filter { !$0.isDone }.count : 0
        let behind = engine.state.loans.contains { $0.companyID == co.id && $0.int("miss") > 0 } || co.int("supCut") > 0 || co.num("vatOver") > 1 || co.int("loanCall") != 0
        LedgerSection(title: "Needs you", trailing: {
            if !asks.isEmpty { Text("\(asks.count) decision\(asks.count == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(Theme.caution) }
        }) {
            VStack(spacing: 0) {
                ForEach(Array(asks.prefix(3).enumerated()), id: \.element.id) { n, m in
                    if n > 0 { Hairline() }
                    row(symbol: "questionmark.bubble", tint: Theme.caution, title: m.title, sub: m.from.isEmpty ? "Waiting for your answer" : "From \(m.from)", action: "Decide") {
                        store.openMessageID = m.id; store.tab = .inbox
                    }
                }
                if asks.count > 3 { Text("and \(asks.count - 3) more in Inbox").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4) }
                if setupLeft > 0 { divider(asks.isEmpty); row(symbol: "checklist", tint: Theme.caution, title: "\(setupLeft) thing\(setupLeft == 1 ? "" : "s") left before opening", sub: "Documents, premises, equipment, stock", action: "Setup") { go(.setup) } }
                if co.status == .closed { divider(asks.isEmpty && setupLeft == 0); row(symbol: "moon.zzz", tint: Theme.caution, title: "Closed", sub: "Reopen it or close down for good", action: "Settings") { goMoney(.settings) } }
                if behind { divider(false); row(symbol: "exclamationmark.triangle", tint: Theme.loss, title: "Behind on payments", sub: "Loans, VAT or suppliers", action: "Finances") { goMoney(.summary) } }
                if people > 0 { divider(false); row(symbol: "person.crop.circle.badge.exclamationmark", tint: Theme.caution, title: "\(people) \(people == 1 ? "person needs" : "people need") attention", sub: "Problems, notice or sickness", action: "Team") { go(.staff) } }
                if nobody { divider(false); row(symbol: "person.fill.questionmark", tint: Theme.loss, title: "No one runs it", sub: "You do not work here and there is no manager", action: "Team") { go(.staff) } }
                if asks.isEmpty && setupLeft == 0 && co.status != .closed && !behind && people == 0 && !nobody {
                    Text("Nothing waiting for you here.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder private func divider(_ first: Bool) -> some View { if !first { Hairline() } }

    private func row(symbol: String, tint: Color, title: String, sub: String, action: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(tint).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(2)
                    Text(sub).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text("\(action) →").font(.system(size: 11.5)).foregroundStyle(Theme.gold).fixedSize()
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // 3. Who runs it day to day, with what authority, and where that is changed
    @ViewBuilder private func whoRunsIt(_ co: Company) -> some View {
        if co.status.isLive && co.type != "hold" {
            let chain = engine.decisionChain(companyID: co.id)
            let trade = engine.tradeInfo(companyID: co.id)
            LedgerSection(title: "Who runs it", trailing: {
                if CompanyDetailView.availableSections(co, engine).contains(.staff) {
                    Button { go(.staff) } label: { Text("Team →").font(.system(size: 11.5)).foregroundStyle(Theme.gold) }.buttonStyle(.plain)
                }
            }) {
                VStack(spacing: 0) {
                    if let boss = chain.first {
                        let lvl = ["asks you before deciding", "decides within your limits", "decides on their own"][min(2, max(0, boss.level))]
                        FlatRow(label: boss.name, value: GameEngine.bossTitle(boss.kind, trade: trade), sub: String(lvl.prefix(1).uppercased() + lvl.dropFirst()), rule: false)
                        ForEach(Array(chain.dropFirst().prefix(2).enumerated()), id: \.offset) { _, b in
                            FlatRow(label: b.name, value: GameEngine.bossTitle(b.kind, trade: trade), sub: "Above them")
                        }
                    } else {
                        FlatRow(label: co.ownerHours > 0 ? "You" : "No one", value: co.ownerHours > 0 ? "\(Int(co.ownerHours.rounded())) h a week" : "–",
                                sub: co.ownerHours > 0 ? "You work here yourself; a manager can take the day-to-day off you" : "Hire a manager or put in hours under Operations", rule: false)
                    }
                    FlatRow(label: "Team", value: "\(co.staff.count) \(co.staff.count == 1 ? "person" : "people")", sub: co.staff.isEmpty ? "" : store.short(co.staff.reduce(0) { $0 + $1.monthlyWage }, in: co) + " a month in wages")
                }
            }
        }
    }

    // 4. Why, and where to act: findings from the company's own numbers, each with a way to the section that changes it
    private func diagnosis(_ co: Company) -> some View {
        let items = engine.insights(for: co, limit: 5)
        return LedgerSection("What is going on") {
            VStack(spacing: 0) {
                if items.isEmpty { Text("Nothing stands out yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(Array(items.enumerated()), id: \.element.id) { n, i in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: i.symbol).font(.system(size: 13)).foregroundStyle(Theme.tone(i.tone.rawValue) == Theme.ivoryMuted ? Theme.gold : Theme.tone(i.tone.rawValue)).frame(width: 18).padding(.top, 2)
                        Text(i.text.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if let target = i.section.flatMap({ CompanySection(key: $0) }), CompanyDetailView.availableSections(company, engine).contains(target) {
                            Button { go(target) } label: {
                                Text("\(target.rawValue) →").font(.system(size: 11.5)).foregroundStyle(Theme.gold).fixedSize()
                            }.buttonStyle(.plain).padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 8)
                    if n < items.count - 1 { Hairline() }
                }
            }
        }
    }

    // 5. The operating picture: what limits sales, and how customers see the place
    private func operations(_ co: Company, _ h: CompanyHealth) -> some View {
        LedgerSection(title: "Last week", trailing: {
            Text("\(Int(h.servedLastWeek.rounded())) served of \(Int(h.capacityLastWeek.rounded())) possible").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: 9) {
                RateBar(label: "Capacity used", fraction: h.capacityUse, tint: h.capacityUse > 0.95 ? Theme.caution : Theme.gold)
                RateBar(label: "Demand met", fraction: h.demandCoverage > 0 ? min(1, 1 / h.demandCoverage) : 0, tint: h.demandCoverage > 1.05 ? Theme.caution : Theme.gain)
                RateBar(label: "Awareness", fraction: co.awareness / 100, tint: Theme.gold)
                if let b = h.bottleneck {
                    Text(h.demandCoverage > 1.05 ? "Limited by \(b.lowercased()) · turning customers away." : "Spare room: demand, not \(b.lowercased()), limits sales.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
                KeyFigures(items: [
                    .init(label: "Rating", value: String(format: "%.1f / 5", h.rating)),
                    .init(label: "Reputation", value: "\(Int(co.reputation.rounded()))"),
                    .init(label: "Quality", value: "\(Int(co.quality.rounded()))"),
                ])
            }
        }
    }

    // 6. The trend behind the figures
    private func performance(_ co: Company, _ h: CompanyHealth) -> some View {
        let rev = Array(h.revenueSeries.suffix(months)), prof = Array(h.profitSeries.suffix(months))
        return LedgerSection(title: "Revenue and profit by month", trailing: {
            HStack(spacing: 10) {
                ForEach([6, 12, 24], id: \.self) { m in
                    Button { months = m; Haptics.choose() } label: {
                        Text(m == 6 ? "6M" : m == 12 ? "1Y" : "2Y").font(.system(size: 11, weight: .medium)).foregroundStyle(months == m ? Theme.ivory : Theme.ivoryFaint)
                            .padding(.bottom, 2).overlay(alignment: .bottom) { if months == m { Rectangle().fill(Theme.gold).frame(height: 1) } }
                    }.buttonStyle(.plain)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
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
                    Button("Open for business") { open() }.buttonStyle(GoldButtonStyle()).disabled(!left.isEmpty && !left.allSatisfy { $0.id == "stockcash" })
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
                Text(it.title).font(.system(size: 13.5, weight: it.isDone ? .regular : .medium)).foregroundStyle(it.isDone ? Theme.ivoryMuted : Theme.ivory)
                if !it.detail.isEmpty { Text(it.detail).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
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
                NavigationLink { CompanyEquipmentScreen(companyID: company.id, opensOnPremises: premises) } label: { content }.buttonStyle(.plain)
            case .money:
                Button { moneyPart = .owners; section = .finances; Haptics.choose() } label: { content }.buttonStyle(.plain)
            case .section(let s):
                Button { if CompanyDetailView.availableSections(company, engine).contains(s) { section = s; Haptics.choose() } } label: { content }.buttonStyle(.plain)
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
        pending = PendingAction(title: "Fill in what is missing?", message: "Applies for every document, rents a standard place, buys the standard equipment (financed where possible) and hires the standard team, paid from company cash. It opens by itself once the paperwork is approved.", button: "Fill in") {
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
