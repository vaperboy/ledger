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
    @State private var popup: SupplierPick?
    @State private var showDebtInfo = false
    /// The payment term last tapped in each input, by input id (its explanation shows under the control).
    @State private var termFocus: [String: String] = [:]
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
                note(inputs)
                if both {
                    SharpTable {
                        SettingsTableRow(title: "Supplying", note: "Companies you sell to", value: "\(sells.count) \(sells.count == 1 ? "company" : "companies")") { showSupplying = true }
                    }
                }
                if inputs.isEmpty { supplying(sells, cur: cur) } else { inputsList(inputs, cur: cur) }
            }
            .navigationDestination(isPresented: $showSupplying) {
                SettingsPage(title: "Supplying", subtitle: company.name) { supplying(engine.supplyLinks().filter { $0.supplierID == company.id }, cur: cur) }
            }
            .confirmAction($pending)
            .centerSheet(item: $popup) { (pick: SupplierPick) in popupContent(pick) }
            .centerSheet(isPresented: $showDebtInfo, title: "Buying on credit") { debtInfo }
        }
    }

    // MARK: Summary

    /// No box of its own: only the board's agreement and whether an own company supplies this one, as plain lines above the suppliers.
    @ViewBuilder private func note(_ inputs: [SupplierInput]) -> some View {
        let agreement: String? = engine.boardAgreement(scope: "goods").map { a in
            "Board agreement: goods for every company through \(engine.knownSuppliers.first { $0.id == a }?.name ?? "one supplier"), unless a company names its own."
        }
        if let agreement { Text(agreement).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2) }
        if engine.isSuppliedFromInside(companyID: company.id) { Chip(text: "Own supplier", tint: Theme.gain) }
    }

    // MARK: Inputs

    private func inputsList(_ inputs: [SupplierInput], cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            ForEach(inputs) { input in
                inputSection(input, cur: cur)
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

    /// One need (goods, repairs, a service): its header, the providers as compact rows (the current one first), and its payment terms.
    private func inputSection(_ input: SupplierInput, cur: Currency) -> some View {
        let ordered: [SupplierOption] = input.options.filter { $0.isCurrent } + input.options.filter { !$0.isCurrent }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GlyphView(glyph: inputGlyph(input), size: 15, weight: 1.6)
                Text(input.title).capsLabel()
                Spacer(minLength: 0)
            }.padding(.horizontal, 2)
            if input.id == "goods" {
                SegmentedPill(items: [0, 1, 2], title: { classNames[$0] }, selection: goodsClassBinding)
                Text("Quality class: sets the cost and quality of all goods.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).padding(.horizontal, 2)
            }
            if let why = input.governedBy { notice(why, tint: Theme.caution) }
            if let none = input.noOwnProvider { notice(none, tint: Theme.ivoryMuted) }
            ForEach(ordered) { o in optionRow(input, o) }
            if !input.paymentTerms.isEmpty { paymentTermsBlock(input) }
        }
    }

    /// One provider on one compact row: name, relationship badge, reliability stars, price or discount; a tap opens its details.
    private func optionRow(_ input: SupplierInput, _ o: SupplierOption) -> some View {
        let stars: String = starText(o.reliability)
        let line: String = rowLine(o)
        return Button {
            popup = SupplierPick(inputID: input.id, optionID: o.id)
            Haptics.tap()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(o.name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(o.isCurrent ? Theme.gold : Theme.ivory).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Chip(text: chipText(o), tint: chipTint(o))
                        if o.isCurrent { Chip(text: "In use", tint: Theme.gold) }
                        if !stars.isEmpty { Text(stars).font(.system(size: 11)).foregroundStyle(Theme.gold) }
                    }
                    Text(line).font(.system(size: 11.5)).foregroundStyle(o.blocked != nil ? Theme.caution : Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(o.isCurrent ? Theme.gold.opacity(0.6) : Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(PressableStyle())
    }

    private func starText(_ s: String) -> String {
        guard s.hasSuffix("stars"), let first = s.split(separator: " ").first, let v = Double(first) else { return "" }
        let n: Int = min(5, max(0, Int(v.rounded())))
        return String(repeating: "\u{2605}", count: n) + String(repeating: "\u{2606}", count: 5 - n)
    }

    private func rowLine(_ o: SupplierOption) -> String {
        if let b = o.blocked { return b }
        var parts: [String] = []
        if let pf = o.priceFactor { parts.append("\(Int((pf * 100).rounded()))% of market") }
        else if let d = o.discount, d > 0 { parts.append("\(Int((d * 100).rounded()))% off") }
        if o.terms.count <= 30 { parts.append(o.terms) }
        if parts.isEmpty { parts.append(o.subtitle) }
        return parts.joined(separator: " · ")
    }

    private func notice(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            GlyphView(glyph: Glyph.lock, size: 14, weight: 1.6, tint: tint)
            Text(text).font(.system(size: 11.5)).foregroundStyle(tint).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 2)
    }

    // MARK: One provider (popup)

    private struct SupplierPick: Identifiable, Equatable {
        var inputID: String
        var optionID: String
        var id: String { inputID + "/" + optionID }
    }

    @ViewBuilder private func popupContent(_ pick: SupplierPick) -> some View {
        let e: GameEngine = store.engine ?? engine
        let found: SupplierInput? = e.supplierInputs(companyID: company.id).first(where: { $0.id == pick.inputID })
        let opt: SupplierOption? = found?.options.first(where: { $0.id == pick.optionID })
        if let input = found, let o = opt {
            supplierPopup(input, o, cur: e.currency(for: company))
        }
    }

    /// Closes the popup, then runs the action once it has gone (its own confirmation popup would otherwise clash with it).
    private func closeThen(_ action: @escaping () -> Void) {
        popup = nil
        presentAfterSheet(action)
    }

    private func supplierPopup(_ input: SupplierInput, _ o: SupplierOption, cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Chip(text: chipText(o), tint: chipTint(o))
                if o.isCurrent { Chip(text: "In use", tint: Theme.gold) }
                Spacer(minLength: 0)
            }
            popupFacts(o, cur: cur)
            popupActions(input, o, cur: cur)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(o.name)
    }

    private func popupFacts(_ o: SupplierOption, cur: Currency) -> some View {
        let riskText: String = o.risks.joined(separator: " ")
        let market: Double = o.yearlyVsMarket ?? 0
        let marketText: String = market > 0 ? "saves about \(cur.tidyShort(market)) a year" : "costs about \(cur.tidyShort(-market)) a year more"
        return VStack(alignment: .leading, spacing: 6) {
            PopupRow(label: "Quality", value: o.quality ?? "Not rated")
            PopupRow(label: "Lead time", value: o.delivery)
            PopupRow(label: "Reliability", value: o.reliability)
            PopupRow(label: "Terms", value: o.terms)
            if abs(market) >= 1 { PopupRow(label: "Against market", value: marketText) }
            if !o.risks.isEmpty { Text("Risk: " + riskText).popupText(.risk) }
            if let b = o.blocked { Text(b).popupText(.risk) }
            if let x = o.dealExtra { Text("Negotiated: \(pct(x)) extra off while the deal lasts.").popupText(.effect) }
        }
    }

    private func popupActions(_ input: SupplierInput, _ o: SupplierOption, cur: Currency) -> some View {
        let canSwitch: Bool = o.blocked == nil && !o.isCurrent && input.governedBy == nil
        let lunchCost: String = engine.homeCurrency.tidyShort(engine.homeCurrency.scaledPrice(5000))
        let canLunch: Bool = o.vendorID != nil && (o.kind == .outsideVendor || o.kind == .repairVendor) && (o.isCurrent || (o.relationship ?? 0) > 0)
        let hint: String? = (o.kind != .ownCompany && o.kind != .outside) ? o.nextLevel : nil
        return VStack(alignment: .leading, spacing: 10) {
            if o.negotiable, o.blocked == nil { negotiationRow(input, o) }
            if let hint { Text("Better terms ahead: " + hint).popupText(.caption) }
            if canLunch, let vid = o.vendorID {
                SmallOutlineButton(title: "Take to lunch · about \(lunchCost)") { closeThen { lunch(vid, name: o.name) } }
            }
            if canSwitch { QuietButton(title: "Use \(o.name)", fullWidth: true) { closeThen { confirm(input, o, cur: cur) } } }
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
            }.buttonStyle(PressableStyle())
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
        let currentID: String? = input.paymentTerms.first(where: { $0.isCurrent })?.id
        let focusID: String? = termFocus[input.id] ?? currentID
        let focus: PaymentTermChoice? = input.paymentTerms.first(where: { $0.id == focusID })
        let explain: String = termExplain(focus)
        let lockedNow: Bool = focus?.blocked != nil
        VStack(alignment: .leading, spacing: 6) {
            Text("Payment terms").capsLabel().padding(.horizontal, 2)
            HStack(spacing: 4) {
                ForEach(input.paymentTerms) { t in termChip(input, t, focused: t.id == focusID) }
            }
            Text(explain).font(.system(size: 11.5)).foregroundStyle(lockedNow ? Theme.caution : Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
            HStack(alignment: .center, spacing: 6) {
                Text("Credit is a debt that falls due on its date.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                Button { showDebtInfo = true } label: {
                    GlyphView(glyph: Glyph.info, size: 16, weight: 1.5, tint: Theme.ivoryMuted).frame(width: 32, height: 32).contentShape(Rectangle())
                }.buttonStyle(PressableStyle()).accessibilityLabel("About buying on credit")
                Spacer(minLength: 0)
            }.padding(.horizontal, 2)
        }.padding(.top, 4)
    }

    private func termExplain(_ t: PaymentTermChoice?) -> String {
        guard let t else { return "" }
        if let b = t.blocked { return "Locked: " + b }
        return t.detail
    }

    private func termChip(_ input: SupplierInput, _ t: PaymentTermChoice, focused: Bool) -> some View {
        let locked: Bool = t.blocked != nil
        let tint: Color = t.isCurrent ? Theme.gold : Theme.ivoryMuted
        return Button {
            termFocus[input.id] = t.id
            Haptics.tap()
            guard !t.isCurrent, t.blocked == nil else { return }
            confirmTerms(input, t)
        } label: {
            Text(t.name).font(.system(size: 11.5, weight: t.isCurrent ? .semibold : .regular)).foregroundStyle(tint)
                .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(focused ? Theme.surface : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.isCurrent ? Theme.gold : Theme.border, lineWidth: 1))
                .opacity(locked ? 0.4 : 1)
                .contentShape(Rectangle())
        }.buttonStyle(PressableStyle())
    }

    private var debtInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buying on credit is a debt: it falls due on its date and shows under what falls due. If the account cannot cover it, it carries interest, the supplier trusts you less, and repeated lateness cuts you off.")
                .popupText(.body)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 6) {
            if let until = o.coolingUntil {
                Text("They ended the last talk. They will talk again from week \(until).").popupText(.risk)
            } else if let counter = talks[o.id]?.counterAmount {
                counterControls(input, o, counter)
            } else {
                Text(o.isCurrent ? "Renegotiate" : "Negotiate").capsLabel()
                SegmentedPill(items: SupplyTerms.asks, title: { (a: Double) -> String in pct(a) }, selection: askBinding(input, o))
            }
            if let f = talks[o.id] { Text(f.text.tidyMoney).popupText(f.popupRole) }
        }
    }

    private func askBinding(_ input: SupplierInput, _ o: SupplierOption) -> Binding<Double> {
        Binding<Double>(get: { -1 }, set: { (v: Double) in ask(input, o, v) })
    }

    private func counterControls(_ input: SupplierInput, _ o: SupplierOption, _ counter: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Accept \(pct(counter)) off") { ask(input, o, counter) }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
            HStack(spacing: 10) {
                Menu("Counter") {
                    ForEach([0.25, 0.5, 0.75], id: \.self) { share in
                        let a = ((lastAsk[o.id] ?? counter) + (counter - (lastAsk[o.id] ?? counter)) * share) / 0.005
                        Button(pct(a.rounded(.down) * 0.005) + " off") { ask(input, o, a.rounded(.down) * 0.005) }
                    }
                }.popupText(.button)
                Button("Walk away") { talks[o.id] = .declined("You left the table. They may talk again later if you come back.") }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                Spacer(minLength: 0)
            }
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
        pending = PendingAction(title: "Take \(name) to lunch?", message: "About \(cost). It warms the relationship, which becomes a better discount on every order. You can only do this every four weeks, and relationships fade if you stop buying.", button: "Go to lunch", amount: engine.homeCurrency.scaledPrice(5000), currency: engine.homeCurrency) {
            switch store.act({ $0.lunchWithSupplier(vendorID: vendorID) }) {
            case .ok?: Haptics.success(); store.show("A good lunch. The relationship is warmer.", tone: "good")
            case .wait?: Haptics.warning(); store.show("You met recently. Wait a few weeks.", tone: "warn")
            case .cash?: Haptics.warning(); store.show("Not enough cash for the lunch.", tone: "warn")
            default: Haptics.warning(); store.show("They cannot be reached.", tone: "warn")
            }
        }
    }
}
