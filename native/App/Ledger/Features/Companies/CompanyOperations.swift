import SwiftUI
import GameCore
import Businesses
import Simulation

/// The parts of Operations, shown as the second row of tabs under the company's own tabs.
enum OpsPart: String, CaseIterable, Hashable {
    case setup = "Setup", sell = "How you sell", marketing = "Marketing", premises = "Premises", more = "More"
}

extension Glyph {
    /// Icons for the Operations screens, in the same 24 x 24 outline style as the mockups' set.
    static let check = "M5 12.5 L10 17.5 L19 7"
    static let info = "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M12 11 V16.5 M12 7.5 V8"
    static let cost = "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M9 12 H15 M9 9 H15 M9 15 H15"
    static let capacity = "M4 18 A8 8 0 0 1 20 18 M12 18 L16 11"
    static let suppliers = "M3 7 H14 V17 H3 Z M14 10 H18 L21 13 V17 H14 M7 19 A1.5 1.5 0 1 0 7 22 M17 19 A1.5 1.5 0 1 0 17 22"
    static let building = "M5 21 V4 H15 V21 M15 9 H19 V21 M3 21 H21 M8 8 H12 M8 12 H12 M8 16 H12"
}

/// Operations of one company: Setup, How you sell, Marketing, Premises and More (suppliers, equipment, insurance).
struct CompanyOperations: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: OpsPart
    @State private var pending: PendingAction?
    @State private var lastPrice: SettingResult?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionTabs(items: OpsPart.allCases, title: { $0.rawValue }, selection: $part, sub: true)
                .padding(.horizontal, -Theme.Space.margin)
            switch part {
            case .setup: setup
            case .sell: sell
            case .marketing: CompanyMarketing(engine: engine, company: company)
            case .premises: premises
            case .more: more
            }
        }
        .confirmAction($pending)
    }

    // MARK: Setup

    @ViewBuilder private var setup: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            priceCard
            hoursCard
            upkeepCard
            CoverageEntryRow(engine: engine, company: company)
            CompanyWorkplaceSection(engine: engine, company: company)
            CompanyOtherSections(engine: engine, company: company)
        }
    }

    private var priceCard: some View {
        let level: Double = company.priceLevel
        let signed: String = String(format: "%+.1f", level)
        let priceBinding = Binding<Double>(get: { company.priceLevel }, set: { v in
            lastPrice = store.act { $0.setPriceLevel(companyID: company.id, level: (v * 2).rounded() / 2) }
        })
        return VStack(alignment: .leading, spacing: 6) {
            Text("PRICE").capsLabel()
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(priceWord(level)).font(.hero(34)).foregroundStyle(Theme.ivory)
                        Spacer()
                        Text(signed).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                    }
                    Slider(value: priceBinding, in: -3...3, step: 0.5) { editing in
                        if !editing {
                            Haptics.tap()
                            store.settle(lastPrice, "Price: \(priceWord(company.priceLevel)).", same: "Price is already \(priceWord(company.priceLevel)).", tone: "good")
                        }
                    }
                    .tint(Theme.gold)
                    HStack {
                        Text("Bargain").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        Spacer()
                        Text("Luxury").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                    Text("Cheaper brings more customers, dearer more profit per sale. The right spot depends on your trade and area. The change applies from next week.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    inflationHold
                }
            }
        }
    }

    private var hoursCard: some View {
        let hours: Int = Int(company.ownerHours.rounded())
        let line: String = company.ownerHours == 0 ? "The team runs it without you" : "You work here yourself"
        let hoursBinding = Binding<Double>(get: { company.ownerHours }, set: { v in
            store.settle(store.act { $0.setOwnerHours(companyID: company.id, hours: v) }, "Hours saved.", same: "Hours are already that.")
        })
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("YOUR TIME").capsLabel()
                Spacer()
                Text("Max 80 h across all companies").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
            Card {
                HStack(spacing: Theme.Space.m) {
                    IconCircle(glyph: Glyph.person)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(hours) hours a week").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text(line).font(.caption).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer()
                    StepperPill(value: hoursBinding, range: 0...80, step: 5)
                }
            }
        }
    }

    private var upkeepCard: some View {
        let maintenance = Binding<Int>(get: { company.maintenance }, set: { v in
            store.act { $0.setMaintenance(companyID: company.id, level: v) }
            store.saved("Maintenance: \(["minimal", "normal", "thorough"][min(2, max(0, v))])")
        })
        let stock = Binding<Int>(get: { company.int("stockPol", 1) }, set: { v in
            store.act { $0.setStockPolicy(companyID: company.id, level: v) }
            store.saved("Stock: \(["lean", "balanced", "generous"][min(2, max(0, v))])")
        })
        let maintenanceNames: [String] = ["Minimal", "Normal", "Thorough"]
        let stockNames: [String] = ["Lean", "Balanced", "Generous"]
        return VStack(alignment: .leading, spacing: 6) {
            Text("UPKEEP AND STOCK").capsLabel()
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Maintenance").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    SegmentedPill(items: [0, 1, 2], title: { maintenanceNames[$0] }, selection: maintenance)
                    Text("Stock").font(.caption).foregroundStyle(Theme.ivoryMuted).padding(.top, Theme.Space.xs)
                    SegmentedPill(items: [0, 1, 2], title: { stockNames[$0] }, selection: stock)
                    Text("Thorough upkeep costs more but equipment breaks less; generous stock avoids running out but ties up cash.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    // MARK: How you sell

    @ViewBuilder private var sell: some View {
        let trade: Trade? = engine.tradeInfo(companyID: company.id)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if let trade, !trade.knobs.isEmpty {
                CompanyHowYouSell(engine: engine, company: company, trade: trade)
            } else {
                Text("This business has no choices of how to sell.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
            }
            if CompanySourcing.isAvailable(engine: engine, company: company) {
                suppliersRow
            }
        }
    }

    private var suppliersRow: some View {
        let chain: JSONValue? = engine.chainOf(companyID: company.id)
        let chainName: String = chain?["name"].string ?? ""
        let chainLabel: String = chainName.isEmpty ? "your chain" : chainName
        let note: String = chain == nil ? "" : "This store belongs to \(chainLabel). Where the chain or a franchise agreement fixes a supplier, the choice is locked for the store and says so."
        return VStack(alignment: .leading, spacing: 6) {
            Text("SUPPLIERS").capsLabel()
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(spacing: Theme.Space.m) {
                        IconCircle(glyph: Glyph.suppliers)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Compare suppliers").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                            Text("Price, terms and reliability for each input").font(.caption).foregroundStyle(Theme.ivoryMuted)
                        }
                        Spacer(minLength: 8)
                        NavigationLink { CompanySuppliersScreen(companyID: company.id) } label: { thisStoreLabel }
                            .buttonStyle(.plain)
                    }
                    if !note.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            GlyphView(glyph: Glyph.info, size: 14, weight: 1.6, tint: Theme.ivoryFaint)
                            Text(note).font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var thisStoreLabel: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        return HStack(spacing: 4) {
            Text("This store").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold)
            GlyphView(glyph: Glyph.chevron, size: 11, weight: 2, tint: Theme.gold)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .frame(minHeight: 30)
        .overlay(shape.strokeBorder(Theme.borderStrong, lineWidth: 1))
        .contentShape(Rectangle())
    }

    // MARK: Premises

    @ViewBuilder private var premises: some View {
        let family: String? = engine.tradeInfo(companyID: company.id)?.family
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if family == "rent" {
                CompanyProperties(engine: engine, company: company)
            } else {
                NavigationLink { CompanyEquipmentScreen(companyID: company.id, opensOnPremises: true) } label: {
                    CardRow(glyph: Glyph.building, title: "Premises", subtitle: "Where the business works: rent, buy or work from home")
                }.buttonStyle(.plain)
                if engine.isHomeTrade(companyID: company.id) {
                    Text("Working from home, and moving into a workshop or office, are under Setup.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    // MARK: More

    @ViewBuilder private var more: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if CompanySourcing.isAvailable(engine: engine, company: company) {
                NavigationLink { CompanySuppliersScreen(companyID: company.id) } label: {
                    CardRow(glyph: Glyph.suppliers, title: "Suppliers", subtitle: "Who provides each input, and what a different provider would save or cost")
                }.buttonStyle(.plain)
            }
            EquipmentEntryRow(company: company)
            CoverageEntryRow(engine: engine, company: company)
        }
    }

    /// "Hold my prices": prices stay where they were set while the market inflates, so customers see the company as cheaper over time.
    /// Switching it off lets prices follow the market again and drops the edge built up so far (the engine resets it).
    @ViewBuilder private var inflationHold: some View {
        let held = company.flag("inflHold")
        let edge = max(0, (company.num("ig", 1) - 1) * 100)
        Toggle(isOn: Binding(get: { held }, set: { v in setHold(v, edge: edge) })) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Hold my prices").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                Text(held ? (edge >= 0.5 ? "Customers now see you about \(Int(edge.rounded()))% cheaper than if prices had followed inflation. Costs still rise." : "Prices stay where you set them while the market inflates. Costs still rise.")
                          : "Prices follow inflation by themselves. Switch on to keep them where you set them: customers see you as cheaper over time, but your margin shrinks as costs rise.")
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }.tint(Theme.gold)
    }

    private func setHold(_ on: Bool, edge: Double) {
        let id = company.id, name = company.name
        let apply = {
            guard store.act({ $0.setInflationHold(companyID: id, hold: on) }) != nil else { store.show("Could not change the price setting.", tone: "warn"); return }
            store.show(on ? "\(name) now holds its prices." : "\(name)'s prices follow inflation again.", tone: "n")
        }
        if !on && edge >= 0.5 {
            pending = PendingAction(title: "Let prices follow inflation?", message: "The edge built up while holding (about \(Int(edge.rounded()))% cheaper in customers' eyes) is dropped at once.", button: "Let go", run: apply)
        } else { apply() }
    }

    private func priceWord(_ l: Double) -> String {
        switch l { case ..<(-1.9): return "Bargain"; case ..<(-0.4): return "Below market"; case ..<0.4: return "At market"; case ..<1.9: return "Premium"; default: return "Luxury" }
    }
}
