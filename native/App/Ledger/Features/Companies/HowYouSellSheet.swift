import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// "How you sell", a popup (sheet) only: the choices a business has (its concept, its add-ons and its ways to sell) with what each
/// costs, and nothing else. The rules and the numbers are the engine's (`knobChangeQuote`, `changeKnob`, `toggleKnobOption`, `waysToSell`,
/// `setWayToSell`); this view only asks and reports. A chain's standard or a franchise agreement locks a choice ("Locked").
/// A change that costs money, needs a licence or reduces capacity asks first, and says only what it costs.
struct HowYouSellSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    /// True when the choices sit inside another popup (the item popup of Sales): no sheet of its own.
    var embedded = false
    @State private var pending: PendingAction?

    var body: some View {
        if embedded {
            VStack(alignment: .leading, spacing: Theme.Space.l) { inner }.confirmAction($pending)
        } else {
            PeopleSheet(title: "How you sell") { inner }
                .confirmAction($pending)
        }
    }

    @ViewBuilder private var inner: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            content(e, co)
        } else {
            Text("This company no longer exists.").popupText(.body)
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        let cur: Currency = e.currency(for: co)
        if let trade = e.tradeInfo(companyID: co.id) {
            ForEach(trade.knobs, id: \.id) { (knob: Knob) in
                if knob.isMulti {
                    addOns(e, co, knob, cur)
                } else {
                    concept(e, co, knob, cur)
                }
            }
        }
        ways(e, co)
    }

    private func currentValue(_ co: Company, _ knob: Knob) -> Int {
        let v: JSONValue = co.value("knob")[knob.id]
        return v.isNull ? knob.defaultIndex : v.int
    }

    private func heading(_ title: String, locked: Bool) -> some View {
        HStack {
            Text(title.uppercased()).capsLabel()
            Spacer()
            if locked { Chip(text: "Locked", tint: Theme.caution) }
        }
    }

    // MARK: The concept (one choice)

    private func concept(_ e: GameEngine, _ co: Company, _ knob: Knob, _ cur: Currency) -> some View {
        let value: Int = currentValue(co, knob)
        let locked: Bool = e.knobGovernedBy(companyID: co.id, knob: knob.id) != nil
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            heading(knob.name, locked: locked)
            ForEach(Array(knob.options.enumerated()), id: \.offset) { i, o in
                let quote: KnobChangeQuote? = i == value ? nil : e.knobChangeQuote(companyID: co.id, knob: knob.id, option: i)
                SellChoiceRow(name: o.name, cost: costText(quote, current: i == value, cur), current: i == value, disabled: locked || quote?.blocked != nil) {
                    choose(e, co, knob, i, cur)
                }
            }
        }
    }

    private func costText(_ q: KnobChangeQuote?, current: Bool, _ cur: Currency) -> String {
        if current { return "Now" }
        guard let q else { return "" }
        if q.blocked != nil { return "Not now" }
        return q.totalCost > 0 ? cur.tidyShort(q.totalCost) : "Free"
    }

    // MARK: Add-ons (several at once)

    private func addOns(_ e: GameEngine, _ co: Company, _ knob: Knob, _ cur: Currency) -> some View {
        let value: Int = currentValue(co, knob)
        let locked: Bool = e.knobGovernedBy(companyID: co.id, knob: knob.id) != nil
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            heading(knob.name, locked: locked)
            ForEach(Array(knob.options.enumerated()), id: \.offset) { i, o in
                addOnRow(e, co, knob, i, o, on: value & (1 << i) != 0, locked: locked, cur)
            }
        }
    }

    private func addOnRow(_ e: GameEngine, _ co: Company, _ knob: Knob, _ i: Int, _ o: KnobOption, on: Bool, locked: Bool, _ cur: Currency) -> some View {
        let quote: KnobChangeQuote? = e.knobToggleQuote(companyID: co.id, knob: knob.id, option: i, on: !on)
        let monthly: Double = e.knobOptionMonthlyCost(companyID: co.id, knob: knob.id, option: i) ?? 0
        let binding = Binding<Bool>(get: { on }, set: { v in toggle(e, co, knob, i, v, cur) })
        return SellToggleRow(name: o.name, cost: addOnCost(quote, monthly: monthly, on: on, cur), isOn: binding, disabled: locked)
    }

    /// "Setup £x, about £y a month": what it costs to switch on and to run (the engine's quote and monthly estimate).
    private func addOnCost(_ q: KnobChangeQuote?, monthly: Double, on: Bool, _ cur: Currency) -> String {
        let running: String = monthly > 0.5 ? "about " + cur.tidyShort(monthly) + " a month" : ""
        if on { return running.isEmpty ? "On" : running }
        let setup: String = (q?.totalCost ?? 0) > 0 ? "Setup " + cur.tidyShort(q?.totalCost ?? 0) : "No setup cost"
        return running.isEmpty ? setup : setup + ", " + running
    }

    // MARK: Ways to sell

    @ViewBuilder private func ways(_ e: GameEngine, _ co: Company) -> some View {
        let rows: [SalesWays.Row] = e.waysToSell(companyID: co.id).filter { $0.canSwitch }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                heading("Ways to sell", locked: false)
                ForEach(rows, id: \.kind) { (r: SalesWays.Row) in
                    let binding = Binding<Bool>(get: { r.isOn }, set: { _ in toggleWay(r, co) })
                    SellToggleRow(name: r.name, cost: r.cost, isOn: binding, disabled: false)
                }
            }
        }
    }

    private func toggleWay(_ r: SalesWays.Row, _ co: Company) {
        let result = store.act { $0.setWayToSell(companyID: co.id, kind: r.kind, on: !r.isOn) }
        switch result {
        case .changed?: Haptics.success(); store.show("\(r.name): \(r.isOn ? "stopped" : "started").", tone: r.isOn ? "n" : "good")
        case .notEnoughCash(let need)?: Haptics.warning(); store.show("Needs \(store.money(need, in: co)) for the set-up.", tone: "warn")
        default: Haptics.warning(); store.show("This cannot be changed.", tone: "warn")
        }
    }

    // MARK: Actions

    /// What the change costs and commits you to, and nothing else.
    private func costLines(_ q: KnobChangeQuote, _ cur: Currency) -> String {
        var lines: [String] = []
        if q.changeoverCost > 0 { lines.append("Changeover: \(cur.tidyShort(q.changeoverCost)), paid now.") }
        for d in q.documents { lines.append("\(d.name): \(cur.tidyShort(d.fee)), about \(d.weeks) weeks to approve.") }
        if q.totalCost > 0 { lines.append("Total: \(cur.tidyShort(q.totalCost)).") }
        if abs(q.monthlyRunningCost) > 0.5 { lines.append("Running cost: about \(cur.tidyShort(abs(q.monthlyRunningCost))) a month \(q.monthlyRunningCost > 0 ? "more" : "less").") }
        if q.transitionWeeks > 0 { lines.append("\(q.transitionWeeks) week\(q.transitionWeeks == 1 ? "" : "s") at \(Int((1 - q.capacityLoss) * 100))% capacity while the business settles.") }
        return lines.joined(separator: "\n")
    }

    // A change is applied at once; it asks first only when it costs more than the size the player set (the cost is `amount`).

    private func choose(_ e: GameEngine, _ co: Company, _ knob: Knob, _ option: Int, _ cur: Currency) {
        guard let q = e.knobChangeQuote(companyID: co.id, knob: knob.id, option: option) else { return }
        if let why = q.blocked { Haptics.warning(); store.show(why, tone: "warn"); return }
        let id: Int = co.id
        let run = {
            report(store.act { $0.changeKnob(companyID: id, knob: knob.id, option: option) }, cur)
        }
        pending = PendingAction(title: "Sell by \(q.optionName)?", message: costLines(q, cur), button: q.totalCost > 0 ? "Change for \(cur.tidyShort(q.totalCost))" : "Change",
                                amount: q.totalCost, currency: cur, run: run)
    }

    private func toggle(_ e: GameEngine, _ co: Company, _ knob: Knob, _ option: Int, _ on: Bool, _ cur: Currency) {
        guard let q = e.knobToggleQuote(companyID: co.id, knob: knob.id, option: option, on: on) else { return }
        if let why = q.blocked { Haptics.warning(); store.show(why, tone: "warn"); return }
        let id: Int = co.id
        let run = {
            let r = store.act { $0.toggleKnobOption(companyID: id, knob: knob.id, option: option, on: on) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else { Haptics.tap(); store.show(on ? "\(q.optionName) is on." : "\(q.optionName) is off.", tone: "good") }
        }
        let button: String = on ? (q.totalCost > 0 ? "Add for \(cur.tidyShort(q.totalCost))" : "Add") : "Drop"
        pending = PendingAction(title: on ? "Add \(q.optionName)?" : "Drop \(q.optionName)?", message: costLines(q, cur), button: button, amount: q.totalCost, currency: cur, run: run)
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

/// One choice of a concept: its name and what it costs to change to it; the company's current choice has a champagne outline and a check.
private struct SellChoiceRow: View {
    var name: String
    var cost: String
    var current: Bool
    var disabled: Bool
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        Button {
            Haptics.choose()
            action()
        } label: {
            HStack(spacing: 12) {
                Text(name.tidyText).popupText(.rowValue).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(cost).font(.system(size: 13).monospacedDigit()).foregroundStyle(current ? Theme.gold : Theme.ivoryMuted)
                if current { GlyphView(glyph: Glyph.check, size: 16, weight: 2, tint: Theme.gold) }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(current ? Theme.goldSelected : Theme.surface))
            .overlay(shape.strokeBorder(current ? Theme.gold : Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled || current)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// One add-on or way to sell: its name, what it costs, and a switch.
private struct SellToggleRow: View {
    var name: String
    var cost: String
    @Binding var isOn: Bool
    var disabled: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.tidyText).popupText(.rowValue)
                if !cost.isEmpty { Text(cost.tidyMoney).popupText(.caption) }
            }
            Spacer(minLength: 8)
            LedgerSwitch(isOn: $isOn).disabled(disabled)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.surface))
        .overlay(shape.strokeBorder(isOn ? Theme.gold : Theme.border, lineWidth: 1))
    }
}
