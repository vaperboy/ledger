import SwiftUI
import GameCore
import Finance
import Businesses
import Simulation

/// Company > Operations > Suppliers: the one place for who provides each input this company uses. For every input (goods, repairs, and each
/// service one of your own companies could supply) it shows who provides it now, price and terms, reliability, and what a different provider
/// would save or cost. Choosing is one engine action (`switchSupplier`) after a confirmation with the whole deal. Better deals come from
/// the relationship with the supplier (lunch, buying over time); that is the engine's own discount, shown here, not a rule of this screen.
/// Replaces the former "Supply from your own companies" card in the Chain section.
struct CompanySourcing: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var open: String?
    @State private var pending: PendingAction?
    private let classNames = Suppliers.goodsClassNames

    var body: some View {
        let inputs = engine.supplierInputs(companyID: company.id)
        let sells = engine.supplyLinks().filter { $0.supplierID == company.id }
        if company.status.isLive, !inputs.isEmpty || !sells.isEmpty {
            let cur = engine.currency(for: company)
            LedgerSection(title: "Suppliers", trailing: {
                if engine.isSuppliedFromInside(companyID: company.id) { Chip(text: "Own supplier", tint: Theme.gain) }
            }) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Who provides what this company uses. Tap an input to compare providers: outside suppliers, your own companies and your business customers. Knowing a supplier well, buying from them for a long time, brings better prices.")
                        .font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
                    if let a = engine.boardAgreement(scope: "goods") {
                        Text("Board agreement: goods for every company through \(engine.knownSuppliers.first { $0.id == a }?.name ?? "one supplier"), unless a company names its own.")
                            .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).padding(.bottom, 6)
                    }
                    ForEach(Array(inputs.enumerated()), id: \.element.id) { n, input in
                        if n > 0 { Hairline() }
                        inputBlock(input, cur: cur)
                    }
                    ForEach(Array(sells.enumerated()), id: \.element.id) { n, l in
                        if let b = engine.state.company(l.buyerID), let k = IntercompanySupply.kind(l.kindID) {
                            Hairline()
                            NavigationLink(value: CompanyRoute.companyAt(b.id, .operations)) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Supplies \(b.name)").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                        Text("\(k.name) · \(IntercompanySupply.modeName(l.mode)) · \(Int((l.lastShare * 100).rounded()))% delivered")
                                            .font(.system(size: 11)).foregroundStyle(l.lastShare < 0.9 ? Theme.loss : Theme.ivoryFaint)
                                    }
                                    Spacer(minLength: 8)
                                    Text(cur.tidyShort(l.lastSpend * l.lastShare * l.lastPriceFactor * 52) + " / yr").font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                                }.padding(.vertical, 9).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    if company.num("int27u") > 0 {
                        Text("Holding back \(Int(company.num("int27u").rounded())) sales a week of its capacity for the group.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 4)
                    }
                }
            }
            .confirmAction($pending)
        }
    }

    // MARK: One input

    @ViewBuilder private func inputBlock(_ input: SupplierInput, cur: Currency) -> some View {
        let isOpen = open == input.id
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeOut(duration: 0.18)) { open = isOpen ? nil : input.id }; Haptics.tap() } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(input.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ivoryFaint)
                        Text(input.current?.name ?? "Not set").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Text(headerLine(input, cur: cur)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if let c = input.current { Chip(text: chipText(c), tint: chipTint(c)) }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.ivoryFaint)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if isOpen {
                Text(input.what).font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                if input.id == "goods" {
                    SectionTabs(items: [0, 1, 2], title: { classNames[$0] },
                                selection: Binding(get: { min(2, max(0, company.value("src")["c"].isNull ? 1 : company.value("src")["c"].int)) },
                                                   set: { v in store.act { $0.chooseGoodsClass(companyID: company.id, goodsClass: v) } }))
                        .padding(.horizontal, -Theme.Space.margin)
                    Text("The quality class changes the cost and the quality of everything you buy; the prices below are for the class chosen.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
                if let none = input.noOwnProvider {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        Text(none).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(Array(input.options.enumerated()), id: \.element.id) { n, o in
                    if n > 0 { Hairline() }
                    optionRow(input, o, cur: cur)
                }
            }
        }.padding(.vertical, 9)
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

    // MARK: One option

    @ViewBuilder private func optionRow(_ input: SupplierInput, _ o: SupplierOption, cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard o.blocked == nil, !o.isCurrent else { return }
                confirm(input, o, cur: cur)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(o.name).font(.system(size: 13.5, weight: o.isCurrent ? .semibold : .regular)).foregroundStyle(o.blocked != nil ? Theme.ivoryFaint : o.isCurrent ? Theme.gold : Theme.ivory)
                        Text(o.subtitle).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        if let pf = o.priceFactor { Text("\(Int((pf * 100).rounded()))% of market").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory) }
                        else if let d = o.discount, d > 0 { Text("\(Int((d * 100).rounded()))% off").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory) }
                        if o.isCurrent { Text("Current").font(.system(size: 11)).foregroundStyle(Theme.gold) }
                        else if let v = o.yearlyVsCurrent, abs(v) >= 1 {
                            Text(v > 0 ? "saves \(cur.tidyShort(v)) / yr" : "costs \(cur.tidyShort(-v)) / yr more").font(.system(size: 11).monospacedDigit()).foregroundStyle(v > 0 ? Theme.gain : Theme.caution)
                        }
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Text(o.terms + " · " + o.reliability).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            if let b = o.blocked { Text(b).font(.system(size: 11)).foregroundStyle(Theme.caution) }
            if let next = o.nextLevel, o.kind != .ownCompany, o.kind != .outside {
                Text("Better terms ahead: \(next)").font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted)
            }
            if let vid = o.vendorID, o.kind == .outsideVendor || o.kind == .repairVendor, o.isCurrent || (o.relationship ?? 0) > 0 {
                Button("Take \(o.name) to lunch · about \(engine.homeCurrency.tidyShort(engine.homeCurrency.scaledPrice(5000)))") { lunch(vid, name: o.name) }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
            }
        }.padding(.vertical, 6)
    }

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
            default: Haptics.warning(); store.show("Nothing changed.", tone: "warn")
            }
        }
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
