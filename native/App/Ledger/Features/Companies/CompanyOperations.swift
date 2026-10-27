import SwiftUI
import Charts
import GameCore
import Countries
import Businesses
import Simulation

/// Where Operations is: `setup` is the page itself; the others are the full-screen pages a row of its settings table opens
/// (the company's links to Marketing and Premises open them directly).
enum OpsPart: String, CaseIterable, Hashable {
    case setup = "Operations", sell = "How you sell", marketing = "Marketing", premises = "Premises", suppliers = "Suppliers"
    case equipment = "Equipment", insurance = "Insurance and advisers", workplace = "Where you work"
}

extension Glyph {
    /// Icons for the Operations screens, in the same 24 x 24 outline style as the mockups' set.
    static let cost = "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M9 12 H15 M9 9 H15 M9 15 H15"
    static let capacity = "M4 18 A8 8 0 0 1 20 18 M12 18 L16 11"
    static let suppliers = "M3 7 H14 V17 H3 Z M14 10 H18 L21 13 V17 H14 M7 19 A1.5 1.5 0 1 0 7 22 M17 19 A1.5 1.5 0 1 0 17 22"
    static let building = "M5 21 V4 H15 V21 M15 9 H19 V21 M3 21 H21 M8 8 H12 M8 12 H12 M8 16 H12"
}

/// The words for the small Operations settings (labels only; the numbers behind them live in the engine).
enum OpsWords {
    static let maintenance: [String] = ["Minimal", "Normal", "Thorough"]
    static let stock: [String] = ["Lean", "Balanced", "Generous"]
    static func name(_ names: [String], _ i: Int) -> String { names[min(names.count - 1, max(0, i))] }
    static func price(_ l: Double) -> String {
        switch l { case ..<(-1.9): return "Bargain"; case ..<(-0.4): return "Below market"; case ..<0.4: return "At market"; case ..<1.9: return "Premium"; default: return "Luxury" }
    }
}

/// A small setting changed in a sheet.
enum OpsSheet: String, Identifiable {
    case price, hours, maintenance, stock, hold
    var id: String { rawValue }
}

/// Operations of one company on ONE page: key figures above, a table of settings (each row one setting with its current value; a
/// small change opens a sheet, a bigger decision a full page), and warnings and open items below.
struct CompanyOperations: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: OpsPart
    @State private var sheet: OpsSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            topCards
            demandChart
            settingsTable
            notes
            CompanyOtherSections(engine: engine, company: company)
        }
        .sheet(item: $sheet) { kind in OpsSettingSheet(kind: kind, companyID: company.id) }
        .navigationDestination(isPresented: Binding(get: { part != .setup }, set: { if !$0 { part = .setup } })) {
            OpsPageDestination(part: part, companyID: company.id)
        }
    }

    // MARK: Key figures above

    private var marketingSpend: Double {
        company.value("mkt").object.values.reduce(0) { $0 + $1["b"].double }
    }

    private var figures: OperationsFigures? { engine.operationsFigures(companyID: company.id) }

    private var topCards: some View {
        let f: OperationsFigures? = figures
        return HStack(alignment: .top, spacing: 10) {
            capacityCard(f).frame(maxWidth: .infinity)
            profitCard(f).frame(maxWidth: .infinity)
        }
    }

    private func capacityCard(_ f: OperationsFigures?) -> some View {
        let use: Double? = f?.capacityUse
        let big: String = use.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        let sub: String = use == nil ? "No trading week yet" : (f?.demandIsLimit == true ? "Demand is the limit" : "Capacity is the limit")
        return Card(padding: 12, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Capacity used").font(.system(size: 12.5)).foregroundStyle(Theme.gold)
                Text(big).font(.hero(32)).foregroundStyle(Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                Text(sub).font(.system(size: 11.5)).foregroundStyle(Theme.caution).lineLimit(2)
            }
        }
    }

    private func profitCard(_ f: OperationsFigures?) -> some View {
        let profit: Double? = f?.profitPerWeek
        let big: String = profit.map { ($0 < 0 ? "−" : "") + store.short(abs($0), in: company) } ?? "–"
        return Card(padding: 12, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profit a week").font(.system(size: 12.5)).foregroundStyle(Theme.gold)
                Text(big).font(.hero(32)).foregroundStyle((profit ?? 0) < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                profitChange(f)
            }
        }
    }

    @ViewBuilder private func profitChange(_ f: OperationsFigures?) -> some View {
        if let d = f?.profitChangePerWeek {
            let up: Bool = d >= 0
            Text((up ? "▲ +" : "▼ −") + store.short(abs(d), in: company) + " vs last month")
                .font(.system(size: 11.5)).foregroundStyle(up ? Theme.gain : Theme.loss).lineLimit(2)
        } else {
            Text("No month to compare yet").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    // MARK: Demand against capacity

    private var demandChart: some View {
        let weeks: [OperationsFigures.Week] = figures?.weeks ?? []
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("DEMAND AGAINST CAPACITY").capsLabel()
                    Spacer(minLength: 8)
                    Text("last 8 weeks").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                }
                if weeks.isEmpty {
                    Text("Shows after the first trading week.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 20)
                } else {
                    DemandCapacityChart(weeks: weeks)
                }
            }
        }
    }

    // MARK: Table of settings

    private var settingsTable: some View {
        OverviewSettingsCard(heading: "Settings") {
            smallRows
            bigRows
        }
    }

    @ViewBuilder private var smallRows: some View {
        let hold: Bool = company.flag("inflHold")
        let stockNote: String = company.inventory > 0 ? "Cash tied up " + store.short(company.inventory, in: company) : "How much you keep in hand"
        SettingsTableRow(title: "Price", note: "Cheaper brings more customers", value: OpsWords.price(company.priceLevel), opens: .sheet,
                         glyph: Glyph.opsPrice, change: String(format: "%+.1f", company.priceLevel), changeTint: Theme.ivoryFaint) { sheet = .price }
        SettingsTableRow(title: "Your time", note: company.ownerHours == 0 ? "The team runs it without you" : "You work here yourself", value: "\(Int(company.ownerHours.rounded())) h a week", opens: .sheet, glyph: Glyph.clock) { sheet = .hours }
        SettingsTableRow(title: "Maintenance", note: "Equipment upkeep", value: OpsWords.name(OpsWords.maintenance, company.maintenance), opens: .sheet, glyph: Glyph.opsWrench) { sheet = .maintenance }
        SettingsTableRow(title: "Stock", note: stockNote, value: OpsWords.name(OpsWords.stock, company.int("stockPol", 1)), opens: .sheet, glyph: Glyph.opsBox) { sheet = .stock }
        SettingsTableRow(title: "Hold my prices", note: "Keep prices fixed while the market inflates", value: hold ? "On" : "Off", valueTint: hold ? Theme.gold : Theme.ivoryMuted, opens: .sheet, glyph: Glyph.lock) { sheet = .hold }
    }

    @ViewBuilder private var bigRows: some View {
        let cur: Currency = engine.currency(for: company)
        if let trade = engine.tradeInfo(companyID: company.id), !trade.knobs.isEmpty {
            SettingsTableRow(title: "How you sell", note: "Concept and add-ons", value: sellSummary(trade), glyph: Glyph.opsRoute) { part = .sell }
        }
        SettingsTableRow(title: "Marketing", note: "Campaigns, ways to sell", value: marketingSpend > 0 ? cur.tidyShort(marketingSpend) + " a week" : "No campaigns", glyph: Glyph.opsMega) { part = .marketing }
        premisesRow
        if engine.isHomeTrade(companyID: company.id), company.status.isLive {
            SettingsTableRow(title: "Where you work", note: "Home, workshop or office", value: engine.isWorkingFromHome(companyID: company.id) ? "At home" : "Own place", glyph: Glyph.building) { part = .workplace }
        }
        if CompanySourcing.isAvailable(engine: engine, company: company) {
            SettingsTableRow(title: "Suppliers", note: "Who provides each input", value: "\(engine.supplierInputs(companyID: company.id).count) inputs", glyph: Glyph.suppliers) { part = .suppliers }
        }
        SettingsTableRow(title: "Equipment and fleet", note: "Brands, buy, lease, subscribe", value: "Manage", glyph: Glyph.opsBox) { part = .equipment }
        coverageRow
    }

    @ViewBuilder private var premisesRow: some View {
        if engine.tradeInfo(companyID: company.id)?.family == "rent" {
            let count: Int = engine.propertyPortfolio(companyID: company.id)?.rows.count ?? 0
            SettingsTableRow(title: "Properties", note: "What you own and let", value: "\(count) \(count == 1 ? "property" : "properties")", glyph: Glyph.opsPin) { part = .premises }
        } else {
            let place: String = engine.isWorkingFromHome(companyID: company.id) ? "At home" : company.value("prem")["owned"].bool ? "Owned" : "Rented"
            SettingsTableRow(title: "Premises", note: "Rent, buy or work from home", value: place, glyph: Glyph.opsPin) { part = .premises }
        }
    }

    @ViewBuilder private var coverageRow: some View {
        let o: CoverageOverview? = engine.coverageOverview(companyID: company.id)
        let count: Int = o?.activeCount ?? 0
        let total: Int = o?.policies.count ?? 0
        SettingsTableRow(title: "Insurance and advisers", note: "Policies, insurer, law firm, accountant",
                         value: count == 0 ? "Not insured" : "\(count) of \(total) policies", valueTint: count == 0 ? Theme.caution : Theme.ivory, glyph: Glyph.opsShield) { part = .insurance }
    }

    /// The company's current choice for each of its "how you sell" knobs, in one line.
    private func sellSummary(_ trade: Trade) -> String {
        let names: [String] = trade.knobs.compactMap { (knob: Knob) -> String? in
            let v: JSONValue = company.value("knob")[knob.id]
            let i: Int = v.isNull ? knob.defaultIndex : v.int
            return knob.options.indices.contains(i) ? knob.options[i].name : nil
        }
        return names.isEmpty ? "Set" : names.joined(separator: ", ")
    }

    // MARK: Below: paperwork and what needs you

    private var paperworkIssues: [TeamOverview.Issue] {
        engine.teamOverview().issues.filter { $0.companyID == company.id && $0.kind == .paperwork }
    }

    @ViewBuilder private var notes: some View {
        let o: CoverageOverview? = engine.coverageOverview(companyID: company.id)
        let uninsured: Bool = (o?.activeCount ?? 1) == 0
        let outgrown: Bool = engine.isHomeTrade(companyID: company.id) && engine.hasOutgrownHome(companyID: company.id)
        let paper: [TeamOverview.Issue] = paperworkIssues
        if let first = paper.first {
            note(paper.count == 1 ? first.detail : "\(paper.count) paperwork matters need you. An inspection can fine you.", action: "Team") { store.openCompany(company.id, section: .staff) }
        }
        if uninsured { note("Not insured. A bad week has nothing behind it: pick an insurer, then the policies you want.", action: "Cover") { part = .insurance } }
        if outgrown { note("The team has outgrown working from home: morale and quality slip every week.", action: "Premises") { part = .workplace } }
    }

    private func note(_ text: String, action: String, tap: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            GlyphView(glyph: Glyph.warning, size: 16, weight: 1.5, tint: Theme.caution)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Haptics.tap()
                tap()
            } label: {
                Text(action + " ›").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.caution.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Color(hex: 0x6A5630), lineWidth: 1))
    }
}

/// Demand (bars, gold where it passes capacity) against what the company could serve (dashed line), one point a week.
struct DemandCapacityChart: View {
    var weeks: [OperationsFigures.Week]

    var body: some View {
        Chart {
            ForEach(weeks) { w in
                BarMark(x: .value("Week", "W\(w.week)"), y: .value("Demand", w.demand))
                    .foregroundStyle(w.demand > w.capacity ? Theme.gold : Theme.borderStrong)
                RuleMark(x: .value("Week", "W\(w.week)"), yStart: .value("Capacity", w.capacity), yEnd: .value("Capacity", w.capacity))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    .foregroundStyle(Theme.ivoryFaint)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint) }
        }
        .frame(height: 96)
        .accessibilityLabel("Demand against capacity over the last \(weeks.count) weeks")
    }
}

extension Glyph {
    static let opsPrice = "M3 12 L12 3 H20 V11 L11 20 Z M16 8 V8.5"
    static let opsWrench = "M14 4 L20 10 L17 13 L11 7 Z M12 9 L4 18 L6 20 L15 12"
    static let opsBox = "M4 8 L12 4 L20 8 V17 L12 21 L4 17 Z M4 8 L12 12 L20 8 M12 12 V21"
    static let opsRoute = "M3 7 H14 V17 H3 Z M14 10 H18 L21 13 V17 H14"
    static let opsMega = "M4 10 V14 H8 L15 18 V6 L8 10 Z M18 9 C19.5 10.5 19.5 13.5 18 15"
    static let opsPin = "M12 21 C7 15 5 12 5 9 A7 7 0 0 1 19 9 C19 12 17 15 12 21 M12 7 A2 2 0 1 0 12 11 A2 2 0 1 0 12 7"
    static let opsShield = "M12 3 L19 6 V12 C19 16 16 19 12 21 C8 19 5 16 5 12 V6 Z"
}
