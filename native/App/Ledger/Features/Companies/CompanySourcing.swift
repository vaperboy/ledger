import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Company > Operations > Suppliers: the one place for who provides each input this company uses. For every input (goods, repairs, and each
/// service one of your own companies could supply) it shows who provides it now, price and terms, reliability, and what a different provider
/// would save or cost. Choosing is one engine action (`switchSupplier`) after a confirmation with the whole deal. Better deals come from
/// the relationship with the supplier (lunch, buying over time); that is the engine's own discount, shown here, not a rule of this screen.
///
/// Layout: a sourcing summary, then two sub-tabs. Inputs: one card per input; opening it shows a price dot plot against the market
/// price, a sharp table comparing the providers (price, saving a year), and a detail card for the provider picked in the table
/// (quality, lead time, reliability, terms, risks, negotiation, switch). Supplying: the table of companies you sell to.
struct CompanySourcing: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var showSupplying = false
    @State private var open: String?
    /// The provider picked in each input's comparison table, by input id.
    @State private var picked: [String: String] = [:]
    @State private var pending: PendingAction?
    /// The last answer of a supplier in a price talk, and the last extra discount asked, by option id (kept under the row like a hiring offer).
    @State private var talks: [String: HireFeedback] = [:]
    @State private var lastAsk: [String: Double] = [:]
    private let classNames = Suppliers.goodsClassNames

    /// One provider on the price dot plot.
    private struct Dot: Identifiable {
        var id: String
        var pct: Double
        var current: Bool
    }

    var body: some View {
        let inputs = engine.supplierInputs(companyID: company.id)
        let sells = engine.supplyLinks().filter { $0.supplierID == company.id }
        if company.status.isLive, !inputs.isEmpty || !sells.isEmpty {
            let cur = engine.currency(for: company)
            let both: Bool = !inputs.isEmpty && !sells.isEmpty
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                summary(inputs, sells: sells, cur: cur)
                if both {
                    SettingsTable(heading: "Sourcing") {
                        SettingsTableRow(title: "Supplying", note: "Companies you sell to", value: "\(sells.count) \(sells.count == 1 ? "company" : "companies")") { showSupplying = true }
                    }
                }
                if inputs.isEmpty { supplying(sells, cur: cur) } else { inputsList(inputs, cur: cur) }
            }
            .navigationDestination(isPresented: $showSupplying) {
                SettingsPage(title: "Supplying", subtitle: company.name) { supplying(engine.supplyLinks().filter { $0.supplierID == company.id }, cur: cur) }
            }
            .confirmAction($pending)
        }
    }

    // MARK: Summary

    private func summary(_ inputs: [SupplierInput], sells: [IntercompanySupply.Link], cur: Currency) -> some View {
        let saving: Double = inputs.reduce(0) { $0 + ($1.current?.yearlyVsMarket ?? 0) }
        let own: Int = inputs.filter { $0.current?.kind == .ownCompany }.count
        let savingTint: Color = saving > 0.5 ? Theme.gain : saving < -0.5 ? Theme.caution : Theme.ivory
        let savingText: String = saving > 0.5 ? "+" + cur.tidyShort(saving) : saving < -0.5 ? "-" + cur.tidyShort(-saving) : cur.tidyShort(0)
        let cells: [StatStrip.Cell] = [
            StatStrip.Cell(label: "Inputs", value: "\(inputs.count)"),
            StatStrip.Cell(label: "Own providers", value: "\(own)"),
            StatStrip.Cell(label: "Vs market a year", value: savingText, tint: savingTint)
        ]
        let agreement: String? = engine.boardAgreement(scope: "goods").map { a in
            "Board agreement: goods for every company through \(engine.knownSuppliers.first { $0.id == a }?.name ?? "one supplier"), unless a company names its own."
        }
        let inside: Bool = engine.isSuppliedFromInside(companyID: company.id)
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sourcing").capsLabel()
                    Spacer(minLength: 8)
                    if inside { Chip(text: "Own supplier", tint: Theme.gain) }
                    GlyphView(glyph: Glyph.suppliers, size: 18, weight: 1.6)
                }
                Text("Who provides what this company uses. Open an input to compare providers: outside suppliers, your own companies and your business customers. Knowing a supplier well, buying from them for a long time, brings better prices.")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                if let agreement { Text(agreement).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
                StatStrip(cells: cells)
            }
        }
    }

    // MARK: Inputs

    private func inputsList(_ inputs: [SupplierInput], cur: Currency) -> some View {
        let openID: String? = open ?? inputs.first?.id
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach(inputs) { input in
                inputBlock(input, isOpen: openID == input.id, cur: cur)
            }
            if company.num("int27u") > 0 {
                Text("Holding back \(Int(company.num("int27u").rounded())) sales a week of its capacity for the group.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.horizontal, 2)
            }
        }
    }

    private func inputGlyph(_ input: SupplierInput) -> String {
        switch input.id {
        case "goods": return Glyph.suppliers
        case "repair": return Glyph.capacity
        default: return Glyph.building
        }
    }

    private func inputBlock(_ input: SupplierInput, isOpen: Bool, cur: Currency) -> some View {
        let line: String = headerLine(input, cur: cur)
        let name: String = input.current?.name ?? "Not set"
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { open = isOpen ? "" : input.id }
                Haptics.tap()
            } label: {
                HStack(spacing: 12) {
                    IconCircle(glyph: inputGlyph(input), size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(input.title.tidyMoney).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                        Text(name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                        Text(line).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    if let c = input.current { Chip(text: chipText(c), tint: chipTint(c)) }
                    GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim).rotationEffect(.degrees(isOpen ? -90 : 90))
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(isOpen ? Theme.gold.opacity(0.6) : Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if isOpen { comparison(input, cur: cur) }
        }
    }

    private func comparison(_ input: SupplierInput, cur: Currency) -> some View {
        let sel: SupplierOption? = selected(input)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(input.what).font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
            if input.id == "goods" {
                SegmentedPill(items: [0, 1, 2], title: { classNames[$0] }, selection: goodsClassBinding)
                Text("The quality class changes the cost and the quality of everything you buy; the prices below are for the class chosen.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.horizontal, 2)
            }
            if let why = input.governedBy { notice(why + (why.contains("franchise agreement") ? " Only the franchisor can change it." : " Change it at the chain, or release the rule there so each store decides."), tint: Theme.caution) }
            if let none = input.noOwnProvider { notice(none, tint: Theme.ivoryMuted) }
            priceChart(input)
            optionTable(input, cur: cur)
            if let sel { optionDetail(input, sel, cur: cur) }
            if !input.paymentTerms.isEmpty { paymentTermsBlock(input) }
        }
    }

    private func notice(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            GlyphView(glyph: Glyph.lock, size: 14, weight: 1.6, tint: tint)
            Text(text).font(.system(size: 11.5)).foregroundStyle(tint).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 2)
    }

    private func selected(_ input: SupplierInput) -> SupplierOption? {
        if let id = picked[input.id], let o = input.options.first(where: { $0.id == id }) { return o }
        return input.current ?? input.options.first
    }

    // MARK: Compare

    @ViewBuilder private func priceChart(_ input: SupplierInput) -> some View {
        let dots: [Dot] = input.options.compactMap { o in o.priceFactor.map { Dot(id: o.id, pct: $0 * 100, current: o.isCurrent) } }
        if dots.count >= 2 {
            let names: [String: String] = Dictionary(input.options.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            let lo: Double = min(100, dots.map { $0.pct }.min() ?? 100) - 6
            let hi: Double = max(100, dots.map { $0.pct }.max() ?? 100) + 6
            Card(padding: 12, radius: Theme.Radius.row) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Price against the market").capsLabel()
                        Spacer(minLength: 8)
                        Text("market = 100%").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Chart {
                        RuleMark(x: .value("Market", 100.0)).foregroundStyle(Theme.ivoryFaint).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        ForEach(dots) { d in
                            PointMark(x: .value("Price", d.pct), y: .value("Provider", d.id))
                                .foregroundStyle(d.current ? Theme.gold : Theme.ivoryMuted)
                                .symbolSize(d.current ? 90 : 50)
                        }
                    }
                    .chartXScale(domain: lo...hi)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { v in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                            AxisValueLabel { if let x = v.as(Double.self) { Text("\(Int(x.rounded()))%").font(.system(size: 9.5)).foregroundStyle(Theme.ivoryFaint) } }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { v in
                            AxisValueLabel { if let id = v.as(String.self) { Text(names[id] ?? "").font(.system(size: 10)).foregroundStyle(Theme.ivoryMuted).lineLimit(1) } }
                        }
                    }
                    .frame(height: CGFloat(dots.count) * 26 + 34)
                }
            }
        }
    }

    private func optionTable(_ input: SupplierInput, cur: Currency) -> some View {
        let columns: [TableColumn] = [
            TableColumn(title: "Provider"),
            TableColumn(title: "Price", width: 58),
            TableColumn(title: "A year", width: 82)
        ]
        let chosen: String? = selected(input)?.id
        return SharpTable {
            TableHeader(columns: columns)
            ForEach(input.options) { o in
                optionTableRow(input, o, columns: columns, chosen: chosen == o.id, cur: cur)
            }
        }
    }

    private func optionTableRow(_ input: SupplierInput, _ o: SupplierOption, columns: [TableColumn], chosen: Bool, cur: Currency) -> some View {
        var price = "-"
        if let pf = o.priceFactor { price = "\(Int((pf * 100).rounded()))%" }
        else if let d = o.discount, d > 0 { price = "-\(Int((d * 100).rounded()))%" }
        var year = "-"
        var yearTint: Color = Theme.ivoryMuted
        if o.isCurrent { year = "Current"; yearTint = Theme.gold }
        else if let v = o.yearlyVsCurrent, abs(v) >= 1 {
            year = (v > 0 ? "+" : "-") + cur.tidyShort(abs(v))
            yearTint = v > 0 ? Theme.gain : Theme.caution
        }
        let note: String = o.blocked ?? o.subtitle
        return TableRow(columns: columns, title: o.name, note: note, values: [price, year], valueTints: [Theme.ivory, yearTint], selected: chosen) {
            picked[input.id] = o.id
        }
    }

    // MARK: One provider

    private func optionDetail(_ input: SupplierInput, _ o: SupplierOption, cur: Currency) -> some View {
        let canSwitch: Bool = o.blocked == nil && !o.isCurrent && input.governedBy == nil
        return Card(padding: 14, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(o.name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(o.isCurrent ? Theme.gold : Theme.ivory)
                    Spacer(minLength: 8)
                    Chip(text: chipText(o), tint: chipTint(o))
                }
                detailRow("Quality", o.quality ?? "Not rated")
                detailRow("Lead time", o.delivery)
                detailRow("Reliability", o.reliability)
                detailRow("Terms", o.terms)
                if let v = o.yearlyVsMarket, abs(v) >= 1 {
                    detailRow("Against the market", v > 0 ? "saves about \(cur.tidyShort(v)) a year" : "costs about \(cur.tidyShort(-v)) a year more")
                }
                ForEach(o.risks, id: \.self) { r in
                    Text("Risk: " + r).font(.system(size: 11)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
                }
                if let b = o.blocked { Text(b).font(.system(size: 11)).foregroundStyle(Theme.caution) }
                if let x = o.dealExtra { Text("Negotiated: \(pct(x)) extra off while the deal lasts.").font(.system(size: 11)).foregroundStyle(Theme.gain) }
                if o.negotiable, o.blocked == nil { negotiationRow(input, o) }
                if let next = o.nextLevel, o.kind != .ownCompany, o.kind != .outside {
                    Text("Better terms ahead: \(next)").font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted)
                }
                if let vid = o.vendorID, o.kind == .outsideVendor || o.kind == .repairVendor, o.isCurrent || (o.relationship ?? 0) > 0 {
                    SmallOutlineButton(title: "Take \(o.name) to lunch · about \(engine.homeCurrency.tidyShort(engine.homeCurrency.scaledPrice(5000)))") { lunch(vid, name: o.name) }
                }
                if canSwitch { QuietButton(title: "Use \(o.name)…", fullWidth: true) { confirm(input, o, cur: cur) } }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Supplying

    private func supplying(_ sells: [IntercompanySupply.Link], cur: Currency) -> some View {
        let columns: [TableColumn] = [
            TableColumn(title: "Buyer"),
            TableColumn(title: "Delivered", width: 70),
            TableColumn(title: "A year", width: 82)
        ]
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: 8) {
                GlyphView(glyph: Glyph.arrowOut, size: 15, weight: 1.6)
                Text("You supply these companies").capsLabel()
            }.padding(.horizontal, 2)
            SharpTable {
                TableHeader(columns: columns)
                ForEach(sells, id: \.id) { l in
                    supplyRow(l, columns: columns, cur: cur)
                }
            }
        }
    }

    @ViewBuilder private func supplyRow(_ l: IntercompanySupply.Link, columns: [TableColumn], cur: Currency) -> some View {
        if let b = engine.state.company(l.buyerID), let k = IntercompanySupply.kind(l.kindID) {
            let delivered: String = "\(Int((l.lastShare * 100).rounded()))%"
            let year: String = cur.tidyShort(l.lastSpend * l.lastShare * l.lastPriceFactor * 52)
            let tint: Color = l.lastShare < 0.9 ? Theme.loss : Theme.ivory
            NavigationLink(value: CompanyRoute.companyAt(b.id, .operations)) {
                TableRow(columns: columns, title: b.name, note: "\(k.name) · \(IntercompanySupply.modeName(l.mode))", values: [delivered, year], valueTints: [tint, Theme.ivory])
            }.buttonStyle(.plain)
        }
    }

    private var goodsClassBinding: Binding<Int> {
        let src: JSONValue = company.value("src")["c"]
        let current: Int = min(2, max(0, src.isNull ? 1 : src.int))
        return Binding<Int>(get: { current }, set: { (v: Int) in
            store.act { $0.chooseGoodsClass(companyID: company.id, goodsClass: v) }
            store.saved("goods quality class: \(classNames[min(2, max(0, v))])")
        })
    }

    private func headerLine(_ input: SupplierInput, cur: Currency) -> String {
        guard let c = input.current else { return input.noOwnProvider != nil ? "Outside suppliers · no own provider" : "Choose a provider" }
        var parts: [String] = []
        if let pf = c.priceFactor { parts.append("\(Int((pf * 100).rounded()))% of market price") }
        else if let d = c.discount, d > 0 { parts.append("\(Int((d * 100).rounded()))% off bills") }
        if let s = c.yearlyVsMarket, abs(s) >= 1 { parts.append(s > 0 ? "saves about \(cur.tidyShort(s)) a year" : "costs about \(cur.tidyShort(-s)) more a year") }
        parts.append(c.reliability)
        if input.noOwnProvider != nil { parts.append("no own provider") }
        return parts.joined(separator: " · ")
    }

    private func chipText(_ o: SupplierOption) -> String {
        switch o.kind {
        case .ownCompany: return "Yours"
        case .businessCustomer: return "Customer"
        case .outsideVendor, .repairVendor: return o.relationshipWord ?? "Outside"
        case .outside, .noneFixed: return "Outside"
        }
    }
    private func chipTint(_ o: SupplierOption) -> Color {
        switch o.kind {
        case .ownCompany, .businessCustomer: return Theme.gain
        default: return Theme.ivoryMuted
        }
    }

    // MARK: Switching

    private func confirm(_ input: SupplierInput, _ o: SupplierOption, cur: Currency) {
        var lines: [String] = []
        lines.append("\(input.title): \(o.name). \(o.subtitle)")
        if let pf = o.priceFactor { lines.append("Price: \(Int((pf * 100).rounded()))% of the market price.") }
        if let d = o.discount, d > 0 { lines.append("Discount: \(Int((d * 100).rounded()))% off.") }
        if let v = o.yearlyVsCurrent, abs(v) >= 1 {
            lines.append(v > 0 ? "Compared with now: saves about \(cur.tidyShort(v)) a year." : "Compared with now: costs about \(cur.tidyShort(-v)) a year more.")
        } else if o.priceFactor != nil { lines.append("Compared with now: about the same cost.") }
        if let q = o.quality { lines.append("Quality: \(q).") }
        lines.append("Terms: \(o.terms).")
        lines.append("Delivery: \(o.delivery). Reliability: \(o.reliability).")
        for r in o.risks { lines.append("Risk: \(r)") }
        lines.append("Estimates from the last three months; no guarantee.")
        pending = PendingAction(title: "Use \(o.name) for \(input.title.lowercased())?", message: lines.joined(separator: "\n"), button: "Switch provider") {
            switch store.act({ $0.switchSupplier(companyID: company.id, input: input.id, to: o.change) }) {
            case .ok?: Haptics.success(); store.show("\(o.name) now provides \(input.title.lowercased()).", tone: "good")
            case .notKnownWell?: Haptics.warning(); store.show("They do not know you well enough yet. Get to know them better first.", tone: "warn")
            case .notAllowed?: Haptics.warning(); store.show("That provider is no longer available for this company.", tone: "warn")
            case .governed?: Haptics.warning(); store.show("A chain rule or your franchise agreement fixes this input.", tone: "warn")
            default: Haptics.warning(); store.show("Nothing changed.", tone: "warn")
            }
        }
    }

    // MARK: Payment terms

    @ViewBuilder private func paymentTermsBlock(_ input: SupplierInput) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Payment terms").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ivoryFaint)
            ForEach(input.paymentTerms) { t in
                Button {
                    guard !t.isCurrent, t.blocked == nil else { return }
                    confirmTerms(input, t)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(t.name).font(.system(size: 13, weight: t.isCurrent ? .semibold : .regular)).foregroundStyle(t.blocked != nil ? Theme.ivoryFaint : t.isCurrent ? Theme.gold : Theme.ivory)
                            Spacer(minLength: 8)
                            if t.isCurrent { Text("Current").font(.system(size: 11)).foregroundStyle(Theme.gold) }
                        }
                        Text(t.blocked ?? t.detail).font(.system(size: 11)).foregroundStyle(t.blocked != nil ? Theme.caution : Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Text("Buying on credit is a debt: it falls due on its date, shows under what falls due, and if the account cannot cover it, it carries interest, the supplier trusts you less, and repeated lateness cuts you off.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 4)
    }

    private func confirmTerms(_ input: SupplierInput, _ t: PaymentTermChoice) {
        pending = PendingAction(title: "Pay by \(t.name.lowercased()) for \(input.title.lowercased())?", message: t.detail, button: "Use these terms") {
            let ok: Bool? = input.id == "goods"
                ? store.act({ $0.setGoodsPaymentTerms(companyID: company.id, term: t.id) })
                : input.id == "repair" ? store.act({ $0.setRepairPaymentTerms(companyID: company.id, term: t.id) })
                : store.act({ $0.setSupplyPaymentTerms(companyID: company.id, input: input.id, term: t.id) })
            if ok == true { Haptics.success(); store.show("Payment terms: \(t.name).", tone: "good") }
            else { Haptics.warning(); store.show("The supplier does not offer those terms now.", tone: "warn") }
        }
    }

    // MARK: Negotiating a supplier's price

    @ViewBuilder private func negotiationRow(_ input: SupplierInput, _ o: SupplierOption) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let until = o.coolingUntil {
                Text("They ended the last talk. They will talk again from week \(until).").font(.system(size: 11)).foregroundStyle(Theme.caution)
            } else if let counter = talks[o.id]?.counterAmount {
                HStack(spacing: 10) {
                    Button("Accept \(pct(counter)) off") { ask(input, o, counter) }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                    Menu("Counter") {
                        ForEach([0.25, 0.5, 0.75], id: \.self) { share in
                            let a = ((lastAsk[o.id] ?? counter) + (counter - (lastAsk[o.id] ?? counter)) * share) / 0.005
                            Button(pct(a.rounded(.down) * 0.005) + " off") { ask(input, o, a.rounded(.down) * 0.005) }
                        }
                    }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ivoryMuted)
                    Button("Walk away") { talks[o.id] = .declined("You left the table. They may talk again later if you come back.") }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 10) {
                    Text(o.isCurrent ? "Renegotiate" : "Negotiate").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    ForEach(SupplyTerms.asks, id: \.self) { a in
                        Button("\(pct(a)) off") { ask(input, o, a) }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                    }
                    Spacer(minLength: 0)
                }
            }
            if let f = talks[o.id] { Text(f.text.tidyMoney).font(.system(size: 11.5)).foregroundStyle(f.tint).fixedSize(horizontal: false, vertical: true) }
            else { Text("Ask for more off the price. The better they know you the more they can give and the longer they listen; ask too much and they may walk out.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func pct(_ x: Double) -> String { x * 100 == (x * 100).rounded() ? "\(Int((x * 100).rounded()))%" : String(format: "%.1f%%", x * 100) }

    private func ask(_ input: SupplierInput, _ o: SupplierOption, _ amount: Double) {
        guard let vid = o.vendorID else { return }
        lastAsk[o.id] = amount
        let talk = store.act { $0.negotiateSupplier(companyID: company.id, input: input.id, vendorID: vid, ask: amount) }
        let fb: HireFeedback
        switch talk {
        case .agreed(let x)?: fb = .hired(x > 0 ? "\(o.name) agrees to \(pct(x)) extra off and is now your supplier." : "\(o.name) is now your supplier at list terms.")
        case .countered(let c)?: fb = .countered(c.amount, c.isFinal ? "\(o.name) says \(pct(c.amount)) off is as far as they will go." : "\(o.name) would give \(pct(c.amount)) off.")
        case .refused?: fb = .declined("\(o.name) took that as an insult and named no figure. Ask for less.")
        case .walkedAway(let until)?: fb = .unavailable("\(o.name) lost patience and ended the talks. They will talk again from week \(until).")
        case .cooling(let until)?: fb = .unavailable("\(o.name) will not talk until week \(until).")
        case .notNeeded(let why)?: fb = .declined(why)
        case .notAllowed?: fb = .unavailable("That supplier is not available, or the chain fixes this input.")
        case nil: fb = .unavailable("No game is loaded.")
        }
        talks[o.id] = fb
        if fb.isHired { Haptics.success(); store.show(fb.text, tone: "good") } else { Haptics.warning() }
    }

    private func lunch(_ vendorID: String, name: String) {
        let cost = engine.homeCurrency.tidyShort(engine.homeCurrency.scaledPrice(5000))
        pending = PendingAction(title: "Take \(name) to lunch?", message: "About \(cost). It warms the relationship, which becomes a better discount on every order. You can only do this every four weeks, and relationships fade if you stop buying.", button: "Go to lunch") {
            switch store.act({ $0.lunchWithSupplier(vendorID: vendorID) }) {
            case .ok?: Haptics.success(); store.show("A good lunch. The relationship is warmer.", tone: "good")
            case .wait?: Haptics.warning(); store.show("You met recently. Wait a few weeks.", tone: "warn")
            case .cash?: Haptics.warning(); store.show("Not enough cash for the lunch.", tone: "warn")
            default: Haptics.warning(); store.show("They cannot be reached.", tone: "warn")
            }
        }
    }
}
