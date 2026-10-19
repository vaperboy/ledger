import SwiftUI
import GameCore
import Businesses
import Simulation

struct CompanyOperations: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let trade = engine.tradeInfo(companyID: company.id)
        VStack(spacing: Theme.Space.l) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Price")
                    HStack {
                        Text(priceWord(company.priceLevel)).font(.heading)
                        Spacer()
                        Text(String(format: "%+.1f", company.priceLevel)).font(.system(.subheadline, design: .serif).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                    }
                    Slider(value: Binding(get: { company.priceLevel }, set: { v in store.act { $0.setPriceLevel(companyID: company.id, level: (v * 2).rounded() / 2) } }), in: -3...3, step: 0.5)
                        .tint(Theme.gold)
                    Text("Cheaper brings more customers, dearer more profit per sale. The right spot depends on your trade and area.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Your time")
                    Stepper(value: Binding(get: { company.ownerHours }, set: { v in store.act { $0.setOwnerHours(companyID: company.id, hours: v) } }), in: 0...80, step: 5) {
                        Text("\(Int(company.ownerHours.rounded())) hours a week here").font(.bodyText)
                    }
                    Text("Your hours across all companies cannot exceed 80.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Upkeep")
                    Picker("Maintenance", selection: Binding(get: { company.maintenance }, set: { v in store.act { $0.setMaintenance(companyID: company.id, level: v) } })) {
                        Text("Minimal").tag(0); Text("Normal").tag(1); Text("Thorough").tag(2)
                    }.pickerStyle(.segmented)
                    Picker("Stock", selection: Binding(get: { company.int("stockPol", 1) }, set: { v in store.act { $0.setStockPolicy(companyID: company.id, level: v) } })) {
                        Text("Lean").tag(0); Text("Balanced").tag(1); Text("Generous").tag(2)
                    }.pickerStyle(.segmented)
                    Text("Thorough upkeep costs more but equipment breaks less; generous stock avoids running out but ties up cash.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            if let trade, !trade.knobs.isEmpty {
                ForEach(trade.knobs, id: \.id) { knob in
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            SectionLabel(knob.name)
                            Text(knob.detail).font(.caption).foregroundStyle(Theme.ivoryMuted)
                            let current = company.value("knob")[knob.id].isNull ? knob.defaultIndex : company.value("knob")[knob.id].int
                            Picker(knob.name, selection: Binding(get: { current }, set: { v in store.act { $0.setKnob(companyID: company.id, knob: knob.id, option: v) } })) {
                                ForEach(Array(knob.options.enumerated()), id: \.offset) { i, o in Text(o.name).tag(i) }
                            }.pickerStyle(.menu)
                            if knob.options.indices.contains(current) { Text(knob.options[current].detail).font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                        }
                    }
                }
            }
        }
    }

    private func priceWord(_ l: Double) -> String {
        switch l { case ..<(-1.9): return "Bargain"; case ..<(-0.4): return "Below market"; case ..<0.4: return "At market"; case ..<1.9: return "Premium"; default: return "Luxury" }
    }
}
