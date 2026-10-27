import SwiftUI
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
            keyFigures
            settingsTable
            warnings
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

    private var keyFigures: some View {
        let cur: Currency = engine.currency(for: company)
        let spend: Double = marketingSpend
        let spendText: String = spend > 0 ? cur.tidyShort(spend) + " a wk" : "None"
        let cells: [StatStrip.Cell] = [
            .init(label: "Price", value: OpsWords.price(company.priceLevel)),
            .init(label: "Awareness", value: "\(Int(company.awareness.rounded()))%"),
            .init(label: "Your time", value: "\(Int(company.ownerHours.rounded())) h"),
            .init(label: "Marketing", value: spendText, tint: spend > 0 ? Theme.gold : Theme.ivoryMuted),
        ]
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("How it runs").capsLabel()
                Text(OpsWords.price(company.priceLevel)).font(.hero(34)).foregroundStyle(Theme.ivory)
                Text("Cheaper brings more customers, dearer more profit per sale. Changes apply from next week.")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                StatStrip(cells: cells)
            }
        }
    }

    // MARK: Table of settings

    private var settingsTable: some View {
        SettingsTable {
            smallRows
            bigRows
        }
    }

    @ViewBuilder private var smallRows: some View {
        let hold: Bool = company.flag("inflHold")
        SettingsTableRow(title: "Price", note: "Where you sit against the market", value: OpsWords.price(company.priceLevel) + " " + String(format: "%+.1f", company.priceLevel), opens: .sheet) { sheet = .price }
        SettingsTableRow(title: "Your time", note: company.ownerHours == 0 ? "The team runs it without you" : "You work here yourself", value: "\(Int(company.ownerHours.rounded())) h a week", opens: .sheet) { sheet = .hours }
        SettingsTableRow(title: "Maintenance", note: "Equipment upkeep", value: OpsWords.name(OpsWords.maintenance, company.maintenance), opens: .sheet) { sheet = .maintenance }
        SettingsTableRow(title: "Stock", note: "How much you keep in hand", value: OpsWords.name(OpsWords.stock, company.int("stockPol", 1)), opens: .sheet) { sheet = .stock }
        SettingsTableRow(title: "Hold my prices", note: "Keep prices fixed while the market inflates", value: hold ? "On" : "Off", valueTint: hold ? Theme.gold : Theme.ivoryMuted, opens: .sheet) { sheet = .hold }
    }

    @ViewBuilder private var bigRows: some View {
        let cur: Currency = engine.currency(for: company)
        if let trade = engine.tradeInfo(companyID: company.id), !trade.knobs.isEmpty {
            SettingsTableRow(title: "How you sell", note: "Concept and add-ons", value: sellSummary(trade)) { part = .sell }
        }
        SettingsTableRow(title: "Marketing", note: "Campaigns, ways to sell", value: marketingSpend > 0 ? cur.tidyShort(marketingSpend) + " a week" : "No campaigns") { part = .marketing }
        premisesRow
        if engine.isHomeTrade(companyID: company.id), company.status.isLive {
            SettingsTableRow(title: "Where you work", note: "Home, workshop or office", value: engine.isWorkingFromHome(companyID: company.id) ? "At home" : "Own place") { part = .workplace }
        }
        if CompanySourcing.isAvailable(engine: engine, company: company) {
            SettingsTableRow(title: "Suppliers", note: "Who provides each input", value: "\(engine.supplierInputs(companyID: company.id).count) inputs") { part = .suppliers }
        }
        SettingsTableRow(title: "Equipment and fleet", note: "Brands, buy, lease, subscribe", value: "Manage") { part = .equipment }
        coverageRow
    }

    @ViewBuilder private var premisesRow: some View {
        if engine.tradeInfo(companyID: company.id)?.family == "rent" {
            let count: Int = engine.propertyPortfolio(companyID: company.id)?.rows.count ?? 0
            SettingsTableRow(title: "Properties", note: "What you own and let", value: "\(count) \(count == 1 ? "property" : "properties")") { part = .premises }
        } else {
            let place: String = engine.isWorkingFromHome(companyID: company.id) ? "At home" : company.value("prem")["owned"].bool ? "Owned" : "Rented"
            SettingsTableRow(title: "Premises", note: "Rent, buy or work from home", value: place) { part = .premises }
        }
    }

    @ViewBuilder private var coverageRow: some View {
        let o: CoverageOverview? = engine.coverageOverview(companyID: company.id)
        let count: Int = o?.activeCount ?? 0
        let total: Int = o?.policies.count ?? 0
        SettingsTableRow(title: "Insurance and advisers", note: "Policies, insurer, law firm, accountant",
                         value: count == 0 ? "Not insured" : "\(count) of \(total) policies", valueTint: count == 0 ? Theme.caution : Theme.ivory) { part = .insurance }
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

    // MARK: Below: warnings

    @ViewBuilder private var warnings: some View {
        let o: CoverageOverview? = engine.coverageOverview(companyID: company.id)
        let uninsured: Bool = (o?.activeCount ?? 1) == 0
        let outgrown: Bool = engine.isHomeTrade(companyID: company.id) && engine.hasOutgrownHome(companyID: company.id)
        if uninsured || outgrown {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("WORTH A LOOK").capsLabel()
                if uninsured { warning("Not insured. A bad week has nothing behind it: pick an insurer, then the policies you want.") }
                if outgrown { warning("The team has outgrown working from home: morale and quality slip every week.") }
            }
        }
    }

    private func warning(_ text: String) -> some View {
        Card(padding: 12, radius: Theme.Radius.row) {
            HStack(alignment: .top, spacing: 10) {
                GlyphView(glyph: Glyph.warning, size: 16, weight: 1.5, tint: Theme.caution)
                Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
