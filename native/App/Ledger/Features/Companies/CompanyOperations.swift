import SwiftUI
import Charts
import GameCore
import Countries
import Businesses
import Simulation

/// Where Operations is: `setup` is the page itself; the others are the full-screen pages a row of its settings table opens
/// (the company's links to Marketing and Premises open them directly).
enum OpsPart: String, CaseIterable, Hashable {
    case setup = "Operations", premises = "Premises", suppliers = "Suppliers"
    case equipment = "Equipment", insurance = "Insurance and advisers", develop = "Develop", licences = "Licences"
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
    case upkeep
    var id: String { rawValue }
}

/// Operations of one company on ONE page: what needs fixing first, capacity, then a table of settings (each row one setting with its
/// current value; a small change opens a sheet, a bigger decision a full page), and open complaints.
struct CompanyOperations: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: OpsPart
    @State private var sheet: OpsSheet?
    /// The last opened page, kept while the page slides away.
    @State private var heldPart: OpsPart = .setup

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            notes
            CompanyPerformance(engine: engine, company: company)
            settingsTable
            CompanyOtherSections(engine: engine, company: company)
        }
        .centerSheet(item: $sheet) { kind in OpsSettingSheet(kind: kind, companyID: company.id) }
        .navigationDestination(isPresented: Binding(get: { part != .setup }, set: { if !$0 { part = .setup } })) {
            OpsPageDestination(part: part == .setup ? heldPart : part, companyID: company.id)
        }
        .onChange(of: part) { (_: OpsPart, new: OpsPart) in if new != .setup { heldPart = new } }
    }

    // MARK: Table of settings

    private var settingsTable: some View {
        OverviewSettingsCard(heading: "Settings") {
            smallRows
            bigRows
        }
    }

    @ViewBuilder private var smallRows: some View {
        let stockNote: String = company.inventory > 0 ? "Equipment upkeep and stock; cash tied up " + store.short(company.inventory, in: company) : "Equipment upkeep and how much stock you keep"
        SettingsTableRow(title: "Upkeep", note: stockNote, value: OpsWords.name(OpsWords.maintenance, company.maintenance) + " / " + OpsWords.name(OpsWords.stock, company.int("stockPol", 1)).lowercased(), opens: .sheet, glyph: Glyph.opsWrench) { sheet = .upkeep }
    }

    @ViewBuilder private var bigRows: some View {
        let licences: [LicenceLine] = engine.licences(companyID: company.id)
        if !licences.isEmpty {
            let held: Int = licences.filter { $0.form.status == "ok" }.count
            SettingsTableRow(title: "Licences", note: "Add new things to sell; apply and wait for the answer", value: "\(held) of \(licences.count) held", glyph: Glyph.reports) { part = .licences }
        }
        premisesRow
        equipmentRow
        if CompanySourcing.isAvailable(engine: engine, company: company) {
            SettingsTableRow(title: "Suppliers", note: "Who provides each input", value: "\(engine.supplierInputs(companyID: company.id).count) inputs", glyph: Glyph.suppliers) { part = .suppliers }
        }
    }

    @ViewBuilder private var premisesRow: some View {
        if engine.tradeInfo(companyID: company.id)?.family == "rent" {
            let count: Int = engine.propertyPortfolio(companyID: company.id)?.rows.count ?? 0
            SettingsTableRow(title: "Properties", note: "What you own and let", value: "\(count) \(count == 1 ? "property" : "properties")", glyph: Glyph.opsPin) { part = .premises }
        }
        // Premises are in AirStay and insurance and advisers in Atlas: no rows for them here. Equipment is bought in TechPro Store.
    }

    /// What the company owns and what is missing; the page sells, services and links to TechPro Store to buy.
    private var equipmentRow: some View {
        let needs: [EquipmentMarket.Need] = engine.equipmentNeeds(companyID: company.id)
        let missing: Int = needs.filter { !$0.isVehicle && !$0.isSoftware && $0.need > 0 && $0.have + $0.leased < $0.need }.count
        let owned: Int = engine.ownedEquipment(companyID: company.id).filter { $0.kind != "veh" }.count
        return SettingsTableRow(title: "Equipment", note: "What you own, what is missing, selling and leases",
                                value: missing > 0 ? "\(missing) missing" : "\(owned) owned", valueTint: missing > 0 ? Theme.warn : Theme.ink,
                                glyph: Glyph.settings) { part = .equipment }
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
        if paper.first != nil || uninsured || outgrown {
            LedgerSection("Needs you", rule: false) {
                VStack(spacing: 0) {
                    if let first = paper.first {
                        note(paper.count == 1 ? first.detail : "\(paper.count) paperwork matters need you. An inspection can fine you.", action: "Team") { store.openCompany(company.id, section: .staff) }
                    }
                    if uninsured { note("Not insured. A bad week has nothing behind it: get the policies you want in Atlas.", action: "Cover") { store.openAtlas(companyID: company.id) } }
                    if outgrown { note("The team has outgrown working from home: morale and quality slip every week.", action: "Premises") { store.openAirStay(companyID: company.id) } }
                }
            }
        }
    }

    /// A warning row, the same as the Overview's: warn glyph, what is wrong, and where it is handled; the whole row opens it.
    private func note(_ text: String, action: String, tap: @escaping () -> Void) -> some View {
        LedgerRow(leading: .glyph(Glyph.warning), leadingTint: Theme.warn, title: text, valueNote: action, valueNoteTint: Theme.accent, lineLimit: 3, action: tap)
    }
}

/// Demand (bars, gold where it passes capacity) against what the company could serve (dashed line), one point a week.
struct DemandCapacityChart: View {
    var weeks: [OperationsFigures.Week]

    var body: some View {
        Chart {
            ForEach(weeks) { w in
                BarMark(x: .value("Week", "W\(w.week)"), y: .value("Demand", w.demand))
                    .foregroundStyle(w.demand > w.capacity ? Theme.accent : Theme.lineStrong)
                RuleMark(x: .value("Week", "W\(w.week)"), yStart: .value("Capacity", w.capacity), yEnd: .value("Capacity", w.capacity))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.caption2).foregroundStyle(Theme.inkFaint) }
        }
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
