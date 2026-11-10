import SwiftUI
import Charts
import GameCore
import Countries
import Businesses
import Simulation

enum OpsPart: String, CaseIterable, Hashable {
    case setup = "Operations", premises = "Premises"
    case supply = "Suppliers", equipment = "Equipment", insurance = "Insurance and law firm", licences = "Licences"
}

extension Glyph {
    static let cost = "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M9 12 H15 M9 9 H15 M9 15 H15"
    static let capacity = "M4 18 A8 8 0 0 1 20 18 M12 18 L16 11"
    static let suppliers = "M3 7 H14 V17 H3 Z M14 10 H18 L21 13 V17 H14 M7 19 A1.5 1.5 0 1 0 7 22 M17 19 A1.5 1.5 0 1 0 17 22"
    static let building = "M5 21 V4 H15 V21 M15 9 H19 V21 M3 21 H21 M8 8 H12 M8 12 H12 M8 16 H12"
}

enum OpsWords {
    static let maintenance: [String] = ["Minimal", "Normal", "Thorough"]
    static let stock: [String] = ["Lean", "Balanced", "Generous"]
    static func name(_ names: [String], _ i: Int) -> String { names[min(names.count - 1, max(0, i))] }
    static func price(_ l: Double) -> String {
        switch l { case ..<(-1.9): return "Bargain"; case ..<(-0.4): return "Below market"; case ..<0.4: return "At market"; case ..<1.9: return "Premium"; default: return "Luxury" }
    }
}

enum OpsSheet: String, Identifiable {
    case upkeep
    var id: String { rawValue }
}

struct CompanyOperations: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: OpsPart
    @State private var sheet: OpsSheet?
    @Environment(\.outsidePalette) private var P

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            CompanyPerformance(engine: engine, company: company)
            runRows
            CompanyOtherSections(engine: engine, company: company)
        }
        .centerSheet(item: $sheet, category: .medium, tone: .info) { kind in OpsSettingSheet(kind: kind, companyID: company.id) }
    }

    private var runRows: some View {
        let licences: [LicenceLine] = engine.licences(companyID: company.id)
        let rental: Bool = engine.tradeInfo(companyID: company.id)?.family == "rent"
        return PageGroup("Run the place") {
            upkeepRow
            RowRule()
            LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: P.inkSoft, title: "Suppliers", subtitle: "Who supplies what you sell and what the company needs",
                      identifier: "manage-suppliers") { part = .supply }
            if !licences.isEmpty {
                let held: Int = licences.filter { $0.form.status == "ok" }.count
                RowRule()
                LedgerRow(leading: .glyph(Glyph.reports), leadingTint: P.inkSoft, title: "Licences",
                          value: "\(held) of \(licences.count)", valueNote: "held", identifier: "manage-licences") { part = .licences }
            }
            if rental {
                let count: Int = engine.propertyPortfolio(companyID: company.id)?.rows.count ?? 0
                RowRule()
                LedgerRow(leading: .glyph(Glyph.opsPin), leadingTint: P.inkSoft, title: "Properties",
                          value: "\(count)", valueNote: count == 1 ? "property" : "properties", identifier: "manage-properties") { part = .premises }
            }
            if equipmentApplies {
                RowRule()
                equipmentRow
            }
            CompanyMorePages(engine: engine, company: company, pages: [.energy, .salmon, .club], ruled: true)
        }
    }

    private var upkeepRow: some View {
        let stockNote: String = company.inventory > 0 ? store.short(company.inventory, in: company) + " tied up in stock" : ""
        return LedgerRow(leading: .glyph(Glyph.opsWrench), leadingTint: P.inkSoft, title: "Upkeep", subtitle: stockNote,
                         value: OpsWords.name(OpsWords.maintenance, company.maintenance), valueNote: OpsWords.name(OpsWords.stock, company.int("stockPol", 1)).lowercased() + " stock",
                         identifier: "manage-upkeep") { sheet = .upkeep }
    }

    private var equipmentApplies: Bool {
        let r = engine.equipmentRelevance(companyID: company.id)
        return r.machines || r.vehicles || r.software
    }

    private var equipmentRow: some View {
        let needs: [EquipmentMarket.Need] = engine.equipmentNeeds(companyID: company.id)
        let missing: Int = needs.filter { $0.ofTrade && $0.need > 0 && $0.have + $0.leased < $0.need }.count
        let owned: Int = engine.ownedEquipment(companyID: company.id).reduce(0) { $0 + Int($1.count) + Int($1.leasedCount) }
        return LedgerRow(leading: .glyph(Glyph.settings), leadingTint: missing > 0 ? P.warn : P.inkSoft, title: "Equipment",
                         value: missing > 0 ? "\(missing)" : "\(owned)", valueTint: missing > 0 ? P.warn : nil, valueNote: missing > 0 ? "missing" : "owned",
                         identifier: "manage-equipment") { part = .equipment }
    }
}

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
            AxisMarks { _ in AxisValueLabel().font(ChartPalette.axisFont).foregroundStyle(ChartPalette.axis) }
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
