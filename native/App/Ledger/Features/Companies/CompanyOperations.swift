import SwiftUI
import GameCore
import Businesses
import Simulation

struct CompanyOperations: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: PendingAction?

    var body: some View {
        let trade = engine.tradeInfo(companyID: company.id)
        VStack(spacing: Theme.Space.l) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Price").capsLabel()
                    HStack {
                        Text(priceWord(company.priceLevel)).font(.hero(34))
                        Spacer()
                        Text(String(format: "%+.1f", company.priceLevel)).font(.system(.subheadline, design: .default).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                    }
                    Slider(value: Binding(get: { company.priceLevel }, set: { v in _ = store.act { $0.setPriceLevel(companyID: company.id, level: (v * 2).rounded() / 2) } }), in: -3...3, step: 0.5) { editing in
                        if !editing { store.show("Price: \(priceWord(company.priceLevel)).", tone: "good"); Haptics.tap() }
                    }
                        .tint(Theme.gold)
                    Text("Cheaper brings more customers, dearer more profit per sale. The right spot depends on your trade and area.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    inflationHold
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Your time")
                    HStack(spacing: Theme.Space.m) {
                        IconBadge(symbol: "clock.fill", tint: Theme.ivoryMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(company.ownerHours.rounded())) hours a week").font(.bodyText.weight(.medium))
                            Text(company.ownerHours == 0 ? "The team runs it without you" : "You work here yourself").font(.caption).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer()
                        StepperPill(value: Binding(get: { company.ownerHours }, set: { v in store.settle(store.act { $0.setOwnerHours(companyID: company.id, hours: v) }, "Hours saved.", same: "Hours are already that.") }), range: 0...80, step: 5)
                    }
                    Text("Your hours across all companies cannot exceed 80.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Upkeep")
                    Text("Maintenance").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    SectionTabs(items: [0, 1, 2], title: { ["Minimal", "Normal", "Thorough"][$0] },
                                selection: Binding(get: { company.maintenance }, set: { v in store.act { $0.setMaintenance(companyID: company.id, level: v) } }))
                        .padding(.horizontal, -Theme.Space.margin)
                    Text("Stock").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    SectionTabs(items: [0, 1, 2], title: { ["Lean", "Balanced", "Generous"][$0] },
                                selection: Binding(get: { company.int("stockPol", 1) }, set: { v in store.act { $0.setStockPolicy(companyID: company.id, level: v) } }))
                        .padding(.horizontal, -Theme.Space.margin)
                    Text("Thorough upkeep costs more but equipment breaks less; generous stock avoids running out but ties up cash.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            if let trade, !trade.knobs.isEmpty {
                CompanyHowYouSell(engine: engine, company: company, trade: trade)
            }
            CompanySourcing(engine: engine, company: company)
            CompanyWorkplaceSection(engine: engine, company: company)
            EquipmentEntryRow(company: company)
            CoverageEntryRow(engine: engine, company: company)
            CompanyOtherSections(engine: engine, company: company)
        }
        .confirmAction($pending)
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
            _ = store.act { $0.setInflationHold(companyID: id, hold: on) }
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
