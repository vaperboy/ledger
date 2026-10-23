import SwiftUI
import GameCore
import Businesses
import Simulation

/// "How you sell": the business's own choices (concept, add-ons). Changing a single choice costs a changeover and a few weeks
/// of reduced capacity; add-ons are switched on and off one by one. A chain's standard or a franchise agreement locks a choice.
/// All the rules and numbers come from the engine (`knobChangeQuote`, `changeKnob`, `toggleKnobOption`); this view only asks and reports.
struct CompanyHowYouSell: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var trade: Trade
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        let changing = company.value("hys56c")
        VStack(spacing: Theme.Space.l) {
            ForEach(trade.knobs, id: \.id) { knob in
                let value = company.value("knob")[knob.id].isNull ? knob.defaultIndex : company.value("knob")[knob.id].int
                let lock = engine.knobGovernedBy(companyID: company.id, knob: knob.id)
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        SectionLabel(knob.name)
                        Text(knob.detail).font(.caption).foregroundStyle(Theme.ivoryMuted)
                        if let lock {
                            Label("Locked. " + lock, systemImage: "lock.fill").font(.caption).foregroundStyle(Theme.caution)
                        }
                        if !changing.isNull, changing["k"].string == knob.id, Double(engine.state.week) < changing["end"].double {
                            Label("Changing over to \(changing["to"].string): reduced capacity until week \(changing["end"].int).", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(Theme.caution)
                        }
                        if knob.isMulti {
                            ForEach(Array(knob.options.enumerated()), id: \.offset) { i, o in
                                VStack(alignment: .leading, spacing: 2) {
                                    Toggle(o.name, isOn: Binding(get: { value & (1 << i) != 0 }, set: { on in toggle(knob, i, on, cur) })).disabled(lock != nil)
                                    Text(o.detail).font(.caption2).foregroundStyle(Theme.ivoryFaint)
                                }
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(Array(knob.options.enumerated()), id: \.offset) { i, o in
                                        Button(o.name) { choose(knob, i, cur) }
                                            .buttonStyle(QuietButtonStyle(tint: i == value ? Theme.gold : Theme.ivoryMuted))
                                            .disabled(lock != nil)
                                    }
                                }
                            }
                            if knob.options.indices.contains(value) { Text(knob.options[value].detail).font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                            if lock == nil { Text("Changing how you sell costs a changeover and a few weeks at reduced capacity. It may win or lose customers and margin.").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                        }
                    }
                }
            }
        }
        .confirmAction($pending)
    }

    private func summary(_ q: KnobChangeQuote, _ cur: Currency) -> String {
        var lines: [String] = []
        if q.changeoverCost > 0 { lines.append("Changeover: \(cur.tidyShort(q.changeoverCost)), paid now.") }
        for d in q.documents { lines.append("\(d.name): \(cur.tidyShort(d.fee)), about \(d.weeks) weeks to approve. It does not work until approved.") }
        if q.totalCost > 0 { lines.append("Total: \(cur.tidyShort(q.totalCost)).") }
        if q.transitionWeeks > 0 { lines.append("\(q.transitionWeeks) week\(q.transitionWeeks == 1 ? "" : "s") at \(Int((1 - q.capacityLoss) * 100))% capacity while the business settles.") }
        lines.append(contentsOf: q.onPaper.map { $0 })
        lines.append("No guarantee: it can win or lose customers and margin, depending on your trade, area and how well you deliver.")
        return lines.joined(separator: "\n")
    }

    private func choose(_ knob: Knob, _ option: Int, _ cur: Currency) {
        guard let q = engine.knobChangeQuote(companyID: company.id, knob: knob.id, option: option) else { return }
        if let why = q.blocked { Haptics.warning(); store.show(why, tone: "warn"); return }
        pending = PendingAction(title: "Sell by \(q.optionName)?", message: summary(q, cur), button: q.totalCost > 0 ? "Change for \(cur.tidyShort(q.totalCost))" : "Change") {
            report(store.act { $0.changeKnob(companyID: company.id, knob: knob.id, option: option) }, cur)
        }
    }

    private func toggle(_ knob: Knob, _ option: Int, _ on: Bool, _ cur: Currency) {
        guard let q = engine.knobToggleQuote(companyID: company.id, knob: knob.id, option: option, on: on) else { return }
        if let why = q.blocked { Haptics.warning(); store.show(why, tone: "warn"); return }
        let run = {
            let r = store.act { $0.toggleKnobOption(companyID: company.id, knob: knob.id, option: option, on: on) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else { Haptics.tap(); store.show(on ? "\(q.optionName) is on." : "\(q.optionName) is off.", tone: "good") }
        }
        if q.documents.isEmpty { run() }
        else { pending = PendingAction(title: "Add \(q.optionName)?", message: summary(q, cur), button: "Add for \(cur.tidyShort(q.totalCost))", run: run) }
    }

    private func report(_ r: KnobChangeOutcome?, _ cur: Currency) {
        switch r {
        case .done(let q)?:
            Haptics.success()
            store.show("Now selling by \(q.optionName)." + (q.totalCost > 0 ? " Paid \(cur.tidyShort(q.totalCost))." : ""), tone: "good")
        case .refused(let why)?: Haptics.warning(); store.show(why, tone: "warn")
        case nil: break
        }
    }
}
