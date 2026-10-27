import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// One radio-style option card: name, a two-line summary and a chevron; the company's current choice has a gold outline and a check.
private struct OperatingModelCard: View {
    var name: String
    var summary: String
    var current: Bool
    var focused: Bool
    var locked: Bool
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        let outline: Color = current ? Theme.gold : (focused ? Theme.borderStrong : Theme.border)
        let fill: Color = current ? Theme.goldSelected : Theme.surface
        Button {
            Haptics.choose()
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.tidyText).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                    if !summary.isEmpty {
                        Text(summary.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(2).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if current {
                    GlyphView(glyph: Glyph.check, size: 16, weight: 2, tint: Theme.gold)
                } else {
                    GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(outline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// "How you sell": the business's own choices (concept, add-ons). Changing a single choice costs a changeover and a few weeks
/// of reduced capacity; add-ons are switched on and off one by one. A chain's standard or a franchise agreement locks a choice.
/// All the rules and numbers come from the engine (`knobChangeQuote`, `changeKnob`, `toggleKnobOption`); this view only asks and reports.
/// Tapping another model shows its description, changeover cost, reduced capacity and the engine's estimate first; only a change that
/// costs money, needs a licence or reduces capacity asks for confirmation.
struct CompanyHowYouSell: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var trade: Trade
    @State private var pending: PendingAction?
    /// The option looked at (not yet chosen), by knob id.
    @State private var focus: [String: Int] = [:]

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            ForEach(trade.knobs, id: \.id) { knob in
                if knob.isMulti {
                    offers(knob, cur)
                } else {
                    model(knob, cur)
                }
            }
        }
        .confirmAction($pending)
    }

    private func currentValue(_ knob: Knob) -> Int {
        let v: JSONValue = company.value("knob")[knob.id]
        return v.isNull ? knob.defaultIndex : v.int
    }

    // MARK: Operating model (single choice)

    @ViewBuilder private func model(_ knob: Knob, _ cur: Currency) -> some View {
        let value: Int = currentValue(knob)
        let lock: String? = engine.knobGovernedBy(companyID: company.id, knob: knob.id)
        let shown: Int = focus[knob.id] ?? value
        let changing: JSONValue = company.value("hys56c")
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text(knob.name.uppercased()).capsLabel()
                Spacer()
                if lock != nil { Chip(text: "Locked", tint: Theme.caution) }
            }
            if let lock {
                Text("Locked. " + lock).font(.caption).foregroundStyle(Theme.caution)
            }
            if !changing.isNull, changing["k"].string == knob.id, Double(engine.state.week) < changing["end"].double {
                Text("Changing over to \(changing["to"].string): reduced capacity until week \(changing["end"].int).").font(.caption).foregroundStyle(Theme.caution)
            }
            ForEach(Array(knob.options.enumerated()), id: \.offset) { i, o in
                OperatingModelCard(name: o.name, summary: o.detail, current: i == value, focused: i == shown, locked: lock != nil) {
                    focus[knob.id] = i
                }
            }
            if knob.options.indices.contains(shown) {
                focusDetail(knob, option: shown, current: value, locked: lock != nil, cur)
            }
        }
    }

    @ViewBuilder private func focusDetail(_ knob: Knob, option: Int, current: Int, locked: Bool, _ cur: Currency) -> some View {
        let o: KnobOption = knob.options[option]
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(o.detail.tidyMoney).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            if option != current, !locked {
                if let q = engine.knobChangeQuote(companyID: company.id, knob: knob.id, option: option) {
                    changeStrip(knob, option, q, cur)
                }
            }
        }
    }

    @ViewBuilder private func changeStrip(_ knob: Knob, _ option: Int, _ q: KnobChangeQuote, _ cur: Currency) -> some View {
        let preview: KnobPreview? = engine.knobChangePreview(companyID: company.id, knob: knob.id, option: option)
        let cost: String = q.totalCost > 0 ? cur.tidyShort(q.totalCost) : "None"
        let costSub: String = q.documents.isEmpty ? "one-off" : "incl. licences"
        let capacity: String = q.transitionWeeks > 0 ? "\(q.transitionWeeks) wk at \(Int(((1 - q.capacityLoss) * 100).rounded()))%" : "None"
        let impact: (text: String, tint: Color) = impactText(preview, cur)
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .top, spacing: 0) {
                    stripCell(Glyph.cost, "Changeover cost", cost, costSub, Theme.ivory)
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    stripCell(Glyph.capacity, "Reduced capacity", capacity, q.transitionWeeks > 0 ? "while it settles" : "", Theme.ivory)
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    stripCell(Glyph.market, "Estimated impact", impact.text, "depends on demand and execution (estimate)", impact.tint)
                }
                .fixedSize(horizontal: false, vertical: true)
                if let why = q.blocked {
                    Text(why).font(.caption).foregroundStyle(Theme.caution)
                } else {
                    QuietButton(title: q.totalCost > 0 ? "Change for \(cur.tidyShort(q.totalCost))" : "Change to \(q.optionName)", fullWidth: true) {
                        choose(knob, option, cur)
                    }
                }
            }
        }
    }

    private func stripCell(_ glyph: String, _ label: String, _ value: String, _ sub: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            GlyphView(glyph: glyph, size: 18, weight: 1.6)
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.center)
            Text(value).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(tint).lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
            if !sub.isEmpty { Text(sub).font(.system(size: 10)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    /// The engine's estimate of the change in weekly sales, as a typical figure; never a promise.
    private func impactText(_ p: KnobPreview?, _ cur: Currency) -> (text: String, tint: Color) {
        guard let p else { return ("No estimate", Theme.ivoryMuted) }
        let change: Double = p.revenue.change
        let sign: String = change >= 0 ? "+" : "-"
        let text: String = sign + cur.tidyShort(abs(change)) + " a week"
        if p.revenue.uncertain { return (text + ", uncertain", Theme.ivory) }
        return (text, change >= 0 ? Theme.gain : Theme.loss)
    }

    // MARK: Additional offers (add-ons)

    @ViewBuilder private func offers(_ knob: Knob, _ cur: Currency) -> some View {
        let value: Int = currentValue(knob)
        let lock: String? = engine.knobGovernedBy(companyID: company.id, knob: knob.id)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text(knob.name.uppercased()).capsLabel()
                Spacer()
                if lock != nil { Chip(text: "Locked", tint: Theme.caution) }
            }
            if !knob.detail.isEmpty { Text(knob.detail.tidyMoney).font(.caption).foregroundStyle(Theme.ivoryMuted) }
            if let lock { Text("Locked. " + lock).font(.caption).foregroundStyle(Theme.caution) }
            ForEach(Array(knob.options.enumerated()), id: \.offset) { i, o in
                offerRow(knob, i, o, on: value & (1 << i) != 0, locked: lock != nil, cur)
            }
        }
    }

    private func offerRow(_ knob: Knob, _ i: Int, _ o: KnobOption, on: Bool, locked: Bool, _ cur: Currency) -> some View {
        let quote: KnobChangeQuote? = engine.knobToggleQuote(companyID: company.id, knob: knob.id, option: i, on: !on)
        let costLine: String = offerCostLine(quote, on: on, cur)
        let binding = Binding<Bool>(get: { on }, set: { v in toggle(knob, i, v, cur) })
        return HStack(spacing: 12) {
            IconCircle(glyph: Glyph.luxury, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(o.name.tidyText).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                if !o.detail.isEmpty { Text(o.detail.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(2) }
                if !costLine.isEmpty { Text(costLine).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: binding).labelsHidden().tint(Theme.gold).disabled(locked)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(on ? Theme.gold : Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    /// "Setup £x" from the engine's quote for switching it on. No running cost is shown for add-ons.
    private func offerCostLine(_ q: KnobChangeQuote?, on: Bool, _ cur: Currency) -> String {
        guard let q, !on else { return on ? "On" : "" }
        return q.totalCost > 0 ? "Setup " + cur.tidyShort(q.totalCost) : "No setup cost"
    }

    // MARK: Confirmation text

    /// The confirmation text: what it costs and commits you to first, then the engine's before/after estimate (never a promise).
    private func summary(_ q: KnobChangeQuote, _ preview: KnobPreview?, _ cur: Currency) -> String {
        var lines: [String] = []
        if q.changeoverCost > 0 { lines.append("Changeover: \(cur.tidyShort(q.changeoverCost)), paid now.") }
        for d in q.documents { lines.append("\(d.name): \(cur.tidyShort(d.fee)), about \(d.weeks) weeks to approve. It does not work until approved.") }
        if q.totalCost > 0 { lines.append("Total: \(cur.tidyShort(q.totalCost)).") }
        if q.transitionWeeks > 0 { lines.append("\(q.transitionWeeks) week\(q.transitionWeeks == 1 ? "" : "s") at \(Int((1 - q.capacityLoss) * 100))% capacity while the business settles.") }
        if let p = preview {
            lines.append("Estimate for the next \(p.horizon) weeks, a week at a time (low to high, average in brackets):")
            lines.append(row("Customers wanting to buy", p.demand, { String(format: "%.0f", $0) }))
            lines.append(row("Customers you can serve", p.capacity, { String(format: "%.0f", $0) }))
            lines.append(row("Average sale", p.price, { cur.tidyShort($0) }))
            lines.append(row("Sales", p.revenue, { cur.tidyShort($0) }))
            lines.append(row("Left after direct costs", p.margin, { cur.tidyShort($0) }))
            lines.append(String(format: "Share of sales left: %.0f%% now, %.0f%% after.", p.marginShareNow * 100, p.marginShareAfter * 100))
            if p.revenue.uncertain { lines.append("The ranges overlap: this may change little, or go the other way.") }
            if p.capacityBoundAfter { lines.append("You could not serve all the demand: more pull turns into queues, not sales.") }
            lines.append(contentsOf: p.notes)
        } else {
            lines.append("No estimate is available for this kind of business.")
            lines.append(contentsOf: q.onPaper.map { "On paper: " + $0 })
        }
        lines.append("No guarantee: it can win or lose customers and margin, depending on your trade, area, rivals and how well you deliver.")
        return lines.joined(separator: "\n")
    }

    private func row(_ title: String, _ m: KnobPreview.Measure, _ f: (Double) -> String) -> String {
        "\(title): now \(f(m.now.low)) to \(f(m.now.high)) (\(f(m.now.typical))), after \(f(m.after.low)) to \(f(m.after.high)) (\(f(m.after.typical)))"
    }

    // MARK: Actions

    /// Only a change that costs money, needs a licence or reduces capacity asks first; a free one is applied at once.
    private func needsConfirm(_ q: KnobChangeQuote) -> Bool {
        q.totalCost > 0 || !q.documents.isEmpty || q.transitionWeeks > 0
    }

    private func choose(_ knob: Knob, _ option: Int, _ cur: Currency) {
        guard let q = engine.knobChangeQuote(companyID: company.id, knob: knob.id, option: option) else { return }
        if let why = q.blocked { Haptics.warning(); store.show(why, tone: "warn"); return }
        let run = {
            report(store.act { $0.changeKnob(companyID: company.id, knob: knob.id, option: option) }, cur)
            focus[knob.id] = nil
        }
        if !needsConfirm(q) { run(); return }
        let preview = engine.knobChangePreview(companyID: company.id, knob: knob.id, option: option)
        pending = PendingAction(title: "Sell by \(q.optionName)?", message: summary(q, preview, cur), button: q.totalCost > 0 ? "Change for \(cur.tidyShort(q.totalCost))" : "Change", run: run)
    }

    private func toggle(_ knob: Knob, _ option: Int, _ on: Bool, _ cur: Currency) {
        guard let q = engine.knobToggleQuote(companyID: company.id, knob: knob.id, option: option, on: on) else { return }
        if let why = q.blocked { Haptics.warning(); store.show(why, tone: "warn"); return }
        let run = {
            let r = store.act { $0.toggleKnobOption(companyID: company.id, knob: knob.id, option: option, on: on) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else { Haptics.tap(); store.show(on ? "\(q.optionName) is on." : "\(q.optionName) is off.", tone: "good") }
        }
        if !needsConfirm(q) { run(); return }
        let preview = engine.knobTogglePreview(companyID: company.id, knob: knob.id, option: option, on: on)
        let button: String = on ? (q.totalCost > 0 ? "Add for \(cur.tidyShort(q.totalCost))" : "Add") : "Drop"
        pending = PendingAction(title: on ? "Add \(q.optionName)?" : "Drop \(q.optionName)?", message: summary(q, preview, cur), button: button, run: run)
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
