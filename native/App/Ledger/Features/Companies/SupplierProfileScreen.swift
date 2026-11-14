import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

// What the supplier list and the supplier profile both show, built once per product or service.
struct SupplierFacts: Identifiable {
    struct Line: Identifiable {
        var label: String
        var value: String
        var id: String { label }
    }

    var subject: SupplierSubject
    var id: String { subject.id }
    var what: String
    var kind: String
    var supplier: String
    var logoID: String = ""
    var ownerName: String = ""
    var ownerCode: String = ""
    var chosen: Bool
    var price: String
    var level: String = ""
    var lead: String = ""
    var reliability: String
    var trust: Double? = nil
    var late: Bool = false
    var termsLine: String = ""
    var deliver: [Line] = []
    var terms: [Line] = []
    var note: String? = nil
    var governed: String? = nil
    var canChange: Bool = true
    var endFee: Double? = nil
    var negotiateInput: String? = nil
    var negotiateVendor: String? = nil
    var coolingUntil: Int? = nil
    var fit: SupplyFit = .fine
    var company: SupplierCompany? = nil

    static func reliabilityWord(_ share: Double?) -> String {
        guard let t = share else { return "Not tested yet" }
        return t >= 0.95 ? "Dependable" : t >= 0.88 ? "Steady" : "Patchy"
    }

    // Pass rows and inputs when building many at once so the engine reads them only once.
    @MainActor static func make(_ e: GameEngine, _ co: Company, _ subject: SupplierSubject, market: SupplyMarketStore, rows: [SupplyRow]? = nil, inputs: [SupplierInput]? = nil) -> SupplierFacts? {
        switch subject {
        case .item(let id): return item(e, co, id)
        case .line(let id): return line(e, co, id, market: market, rows: rows, inputs: inputs)
        }
    }

    private static func item(_ e: GameEngine, _ co: Company, _ id: String) -> SupplierFacts? {
        guard let p = e.itemPage(companyID: co.id, itemID: id), !p.offers.isEmpty else { return nil }
        let cur: Currency = e.currency(for: co)
        let s: ItemModels.SupplyLine? = p.supply
        let units: Int = p.record?.monthlyUnits ?? 0
        let weeks: Int = e.itemRepickWeeksLeft(companyID: co.id, itemID: id)
        let hasOne: Bool = p.record?.supplierID != nil
        let fee: Double? = hasOne ? e.itemCancelFee(companyID: co.id, itemID: id) : nil
        let price: String = s.map { (x: ItemModels.SupplyLine) -> String in itemAmount(x.buyPrice, cur) + " a unit" } ?? "Not chosen"
        var level: String = ""
        if let s { level = s.discount > 0.0001 ? Currency.percent(s.discount, decimals: 0) + " below list" : "List price" }
        var deliver: [Line] = [Line(label: "Delivers", value: p.item.name), Line(label: "Price", value: price)]
        if let s, s.leadDays > 0 { deliver.append(Line(label: "Lead time", value: "\(s.leadDays) days")) }
        if let s, s.need > 0 { deliver.append(Line(label: "What it needs", value: "\(s.need) units a month")) }
        if let s { deliver.append(Line(label: "Room left with them", value: "\(s.capacityFree) units a month")) }
        var terms: [Line] = []
        if let s {
            terms.append(Line(label: "Relationship", value: s.relationshipWord))
            if s.discount > 0.0001 { terms.append(Line(label: "Your discount", value: Currency.percent(s.discount, decimals: 0))) }
        }
        if let fee { terms.append(Line(label: "Ending it", value: "about " + cur.tidyShort(fee))) }
        terms.append(Line(label: "Changing supplier", value: weeks > 0 ? "again in \(weeks.weeksText)" : "free to change"))
        var note: String?
        if weeks > 0 { note = "You changed this supplier recently. You can pick another one in \(weeks.weeksText)." }
        return SupplierFacts(subject: .item(id), what: p.item.name, kind: p.item.isService ? "Service" : "Product", supplier: s?.vendorName ?? "No supplier chosen",
                             logoID: s?.logoID ?? "", ownerName: s?.owner ?? "", ownerCode: s?.ownerCode ?? "", chosen: s != nil, price: price, level: level,
                             lead: s.map { (x: ItemModels.SupplyLine) -> String in x.leadDays > 0 ? "\(x.leadDays) days" : "" } ?? "",
                             reliability: reliabilityWord(s?.reliability), trust: s?.reliability, termsLine: units > 0 ? "\(units) units a month" : "Pick one so it can be stocked",
                             deliver: deliver, terms: terms, note: note, canChange: true, endFee: fee, fit: s?.fit ?? .fine,
                             company: s.map { (x: ItemModels.SupplyLine) -> SupplierCompany in SupplierCompany.from(x, engine: e) })
    }

    @MainActor private static func line(_ e: GameEngine, _ co: Company, _ id: String, market: SupplyMarketStore, rows: [SupplyRow]?, inputs: [SupplierInput]?) -> SupplierFacts? {
        let all: [SupplyRow] = rows ?? e.supplyLines(companyID: co.id).flatMap { (g: SupplyGroup) -> [SupplyRow] in g.rows }
        guard let r = all.first(where: { (x: SupplyRow) -> Bool in x.id == id }) else { return nil }
        let cur: Currency = e.currency(for: co)
        let contract: SupplyContract? = market.service.contract(buyerCompanyID: co.id, lineID: id)
        let listing: SupplyListing? = contract.flatMap { (c: SupplyContract) -> SupplyListing? in market.service.listing(c.listingID) }
        let now: SupplyOfferRow? = r.now
        let inputID: String = r.input ?? id
        let input: SupplierInput? = (inputs ?? e.supplierInputs(companyID: co.id)).first(where: { (i: SupplierInput) -> Bool in i.id == inputID })
        let option: SupplierOption? = input?.current
        let price: String = r.weekly.map { (w: Double) -> String in cur.tidyShort(w) + " a week" } ?? "Paid per job"
        var lead: String = ""
        if let l = listing { lead = SupplyMarketWords.lead(l.leadDays) } else if let l = now?.lead, !l.isEmpty { lead = l }
        var trust: Double? = now?.trust
        if let l = listing { trust = l.record.ordersTotal == 0 ? nil : l.record.deliveredShare }
        let fee: Double? = contract == nil ? nil : e.playerSupplyCancelFee(companyID: co.id, lineID: id)
        var fit: SupplyFit = now?.fit ?? .fine
        if let l = listing { fit = e.playerSupplyFit(companyID: co.id, listing: l, today: SupplyMarketStore.today(e)) }
        var deliver: [Line] = [Line(label: "Delivers", value: r.kind), Line(label: "Price", value: price)]
        if !lead.isEmpty { deliver.append(Line(label: "Lead time", value: lead)) }
        deliver.append(Line(label: "Quality", value: listing.map { (l: SupplyListing) -> String in SupplyMarketWords.quality(l.qualityTier) } ?? r.quality))
        deliver.append(Line(label: "What you need", value: "\(r.need) units a week"))
        if let f = now?.free, listing == nil { deliver.append(Line(label: "Room left with them", value: "\(f) units a week")) }
        deliver.append(Line(label: "Demand", value: r.scale))
        var terms: [Line] = []
        if let o = option, let rel = o.relationshipWord { terms.append(Line(label: "Relationship", value: rel)) }
        if let d = option?.discount, d > 0.0001 { terms.append(Line(label: "Your discount", value: Currency.percent(d, decimals: 1))) }
        if let x = option?.dealExtra, x > 0.0001 { terms.append(Line(label: "Special deal", value: Currency.percent(x, decimals: 1) + " extra off")) }
        if let next = option?.nextLevel { terms.append(Line(label: "Next level", value: next)) }
        if let l = listing {
            terms.append(Line(label: "Payment", value: l.termsDays <= 0 ? "On delivery" : "\(l.termsDays) days after delivery"))
        } else if let t = input?.paymentTerms.first(where: { (p: PaymentTermChoice) -> Bool in p.isCurrent }) {
            terms.append(Line(label: "Payment", value: t.name))
        }
        if let fee { terms.append(Line(label: "Ending it", value: "about " + cur.tidyShort(fee))) }
        let canChange: Bool = r.governed == nil && (r.canSwitch || !SupplyMarketCatalogue.tradesSupplying(line: id).isEmpty)
        var negotiateInput: String?
        var negotiateVendor: String?
        if let inp = input, inp.governedBy == nil, let o = option, o.negotiable, let v = o.vendorID { negotiateInput = inp.id; negotiateVendor = v }
        let paying: String = input?.paymentTerms.first(where: { (p: PaymentTermChoice) -> Bool in p.isCurrent })?.name ?? ""
        let termsLine: String = listing.map { (l: SupplyListing) -> String in l.termsDays <= 0 ? "Pay on delivery" : "Pay \(l.termsDays) days after delivery" } ?? (paying.isEmpty ? r.scale : "Payment: " + paying.lowercased())
        let company: SupplierCompany? = listing.map { (l: SupplyListing) -> SupplierCompany in SupplierCompany.from(l, engine: e) } ?? now.map { (o: SupplyOfferRow) -> SupplierCompany in SupplierCompany.from(o, engine: e) }
        return SupplierFacts(subject: .line(id), what: r.title, kind: r.group, supplier: listing?.companyName ?? contract?.supplierName ?? r.current,
                             logoID: company?.logoID ?? "", ownerName: company?.owner ?? "", ownerCode: company?.ownerCode ?? "", chosen: true, price: price,
                             level: listing.map { (l: SupplyListing) -> String in SupplyMarketWords.price(l.priceTier) } ?? (now?.priceLevel ?? ""), lead: lead, reliability: r.reliability, trust: trust,
                             late: r.note != nil, termsLine: termsLine, deliver: deliver, terms: terms, note: r.governed ?? r.note, governed: r.governed, canChange: canChange,
                             endFee: fee, negotiateInput: negotiateInput, negotiateVendor: negotiateVendor,
                             coolingUntil: negotiateVendor == nil ? nil : option?.coolingUntil, fit: fit, company: company)
    }
}

struct ReliabilityMeter: View {
    @Environment(\.outsidePalette) private var P
    var trust: Double?
    var word: String

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let t = trust {
                let share: Double = min(1, max(0, t))
                ZStack(alignment: .leading) {
                    Capsule().fill(P.hairline)
                    Capsule().fill(share >= 0.95 ? P.gain : share >= 0.88 ? P.accent : P.caution).frame(width: 48 * CGFloat(share))
                }
                .frame(width: 48, height: 5)
                Text("\(Int(saturating: (share * 100).rounded()))% delivered").textStyle(.caption)
            } else {
                Text(word).textStyle(.caption, tint: P.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// One compact row per line or item: who supplies it, at what price, how reliably, and whether it covers the need.
struct SupplierListRow: View {
    @Environment(\.outsidePalette) private var P
    var facts: SupplierFacts
    var identifier: String = ""
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                SupplierLogo(logoID: facts.logoID, name: facts.chosen ? facts.supplier : facts.what, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(facts.what.tidyText).textStyle(.headline).lineLimit(1)
                    HStack(spacing: Theme.Space.xs) {
                        Text(facts.supplier.tidyText).textStyle(.caption, tint: P.inkSoft).lineLimit(1)
                        if facts.company?.isOwn == true { YoursMark() }
                    }
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(facts.price.tidyText).textStyle(.caption, tint: P.ink, numeric: true).lineLimit(1)
                    if !facts.chosen { AcctPill(text: "Pick one", tone: .warn) }
                    else if facts.late { AcctPill(text: "Late", tone: .bad) }
                    else { FitMark(fit: facts.fit) }
                }
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
            }
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AcctPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the supplier")
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

// The one supplier screen: what they deliver, the terms, and the actions (change, negotiate, end).
struct SupplierProfileScreen: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    @Environment(\.outsidePalette) private var P
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var subject: SupplierSubject

    @State private var choosing: SupplierSubject?
    @State private var talk: SupplierTalk?
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let f = SupplierFacts.make(e, co, subject, market: market) {
            content(e, co, f)
        } else {
            EmptyState(glyph: Glyph.suppliers, title: "This supplier is gone").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
                .onAppear { dismiss() }
        }
    }

    private func content(_ e: GameEngine, _ co: Company, _ f: SupplierFacts) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header(f)
                ListingStats {
                    Text(f.price.tidyText).textStyle(.figure, numeric: true).lineLimit(2).minimumScaleFactor(0.7)
                    Text(f.level.isEmpty ? "Price" : f.level).textStyle(.caption)
                } right: {
                    Text("Delivery").textStyle(.caption)
                    ReliabilityMeter(trust: f.trust, word: f.reliability)
                    if !f.lead.isEmpty { Text(f.lead.tidyText).textStyle(.caption, tint: P.inkSoft) }
                }
                PageGroup("What they deliver to you") {
                    ForEach(Array(f.deliver.enumerated()), id: \.element.id) { (n: Int, l: SupplierFacts.Line) in
                        FlatRow(label: l.label, value: l.value, rule: n > 0)
                    }
                }
                if !f.terms.isEmpty {
                    PageGroup("Terms") {
                        ForEach(Array(f.terms.enumerated()), id: \.element.id) { (n: Int, l: SupplierFacts.Line) in
                            FlatRow(label: l.label, value: l.value, rule: n > 0)
                        }
                    }
                }
                if let note = f.note { Text(note.tidyText).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true) }
                actions(e, co, f)
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
        .confirmAction($pending)
        .centerSheet(item: $choosing, category: .detail, tone: .info) { (s: SupplierSubject) in
            SupplierPopup(companyID: companyID, subject: s, onClose: { choosing = nil }, onOpenOwner: { (ref: SupplierOwnerRef) in
                choosing = nil
                store.push(.supplierOwner(ref))
            }).environmentObject(store)
        }
        .centerSheet(item: $talk, category: .detail, tone: .info) { (t: SupplierTalk) in
            SupplierNegotiateSheet(companyID: companyID, input: t.input, vendorID: t.vendor, vendorName: f.supplier, onClose: { talk = nil }).environmentObject(store)
        }
        .task { market.sync(store) }
        .appScreen(title: "Supplier", subtitle: co.name, tab: .company)
        .accessibilityIdentifier("supplier-profile")
    }

    // The supplier's company card, then what it supplies to this company.
    private func header(_ f: SupplierFacts) -> some View {
        ListingPanel {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text((f.what + " \u{00B7} " + f.kind).tidyText).textStyle(.caption, tint: P.inkFaint).lineLimit(2).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Theme.Space.s)
                    FitMark(fit: f.fit)
                }
                if let c = f.company {
                    SupplierCompanyCard(company: c, onOpenOwner: { store.push(.supplierOwner(c.ownerRef)) })
                } else {
                    HStack(alignment: .center, spacing: Theme.Space.m) {
                        SupplierLogo(logoID: f.logoID, name: f.chosen ? f.supplier : f.what, size: 48)
                        Text(f.supplier.tidyText).textStyle(.title).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder private func actions(_ e: GameEngine, _ co: Company, _ f: SupplierFacts) -> some View {
        VStack(spacing: Theme.Space.s) {
            if f.canChange {
                Button(f.chosen ? "Change supplier" : "Choose a supplier") { choosing = f.subject }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("supplier-change")
            }
            if let input = f.negotiateInput, let vendor = f.negotiateVendor {
                if let until = f.coolingUntil {
                    Text("They will talk again in week \(until).").textStyle(.caption, tint: P.inkFaint)
                } else {
                    Button("Negotiate a better price") { talk = SupplierTalk(input: input, vendor: vendor) }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("supplier-negotiate")
                }
            }
            if let fee = f.endFee {
                Button("End this supply") { askEnd(f, fee, e.currency(for: co)) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: P.loss))
                    .accessibilityIdentifier("supplier-end")
            }
            if !f.canChange, let why = f.governed {
                Text(why.tidyText).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func askEnd(_ f: SupplierFacts, _ fee: Double, _ cur: Currency) {
        let cid: Int = companyID
        let subject: SupplierSubject = f.subject
        pending = PendingAction(title: "End this supply?", message: "Ending it costs a fee of two weeks of the order, about " + cur.tidyShort(fee) + ". \(f.what) then goes back to your usual supplier.",
                                button: "End supply", alwaysAsk: true, tone: .danger, icon: "xmark.circle") {
            var why: String?
            switch subject {
            case .item(let item):
                let r: SettingResult? = store.act { $0.cancelItemSupplier(companyID: cid, itemID: item) }
                if case .refused(let w)? = r { why = w }
            case .line(let line):
                why = market.end(store, companyID: cid, lineID: line)
            }
            if let why { Haptics.warning(); store.show(why, tone: "warn"); return }
            Haptics.success()
            store.saved("supply ended")
        }
    }
}

struct SupplierTalk: Identifiable {
    var input: String
    var vendor: String
    var id: String { input + "|" + vendor }
}


// Ask a supplier for an extra discount. They may agree, counter, refuse or walk away for a while.
struct SupplierNegotiateSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var input: String
    var vendorID: String
    var vendorName: String
    var onClose: () -> Void

    @State private var ask: Double = 1
    @State private var counter: Double?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Ask \(vendorName.tidyText) for an extra discount on top of what you get now. A bold ask can make them end the talks for a while.").popupText(.subtitle)
            HStack {
                Text("Extra discount").popupText(.rowLabel)
                Spacer(minLength: Theme.Space.s)
                Text(String(format: "%.1f%%", counter ?? ask)).popupText(.rowValue)
                if counter == nil { StepperPill(value: $ask, range: 0.5...6, step: 0.5) }
            }
            if let c = counter { Text("They would give " + String(format: "%.1f%%", c) + " and no more. Take it or close.").popupText(.caption) }
            if let message { Text(message).popupText(.risk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle("Negotiate")
        .popupFooter {
            PopupFooter(cancel: "Close", action: counter == nil ? "Ask" : "Take it", onCancel: { onClose() }, onAction: { go() },
                        cancelID: "supplier-talk-close", actionID: "supplier-talk-go")
        }
        .accessibilityIdentifier("supplier-negotiate-sheet")
    }

    private func go() {
        let id: Int = companyID
        let inputID: String = input
        let vendor: String = vendorID
        let share: Double = (counter ?? ask) / 100
        let reply: SupplyDeals.Talk? = store.act { (g: inout GameEngine) -> SupplyDeals.Talk in g.negotiateSupplier(companyID: id, input: inputID, vendorID: vendor, ask: share) }
        switch reply {
        case .agreed(let extra)?:
            Haptics.success()
            store.saved(String(format: "%.1f%% extra off", extra * 100))
            onClose()
        case .countered(let c)?:
            counter = c.amount * 100
            message = c.isFinal ? "That is their last word." : "They will not go that far."
        case .refused?:
            Haptics.warning(); message = "They said no. Try a smaller ask."
        case .walkedAway(let until)?:
            Haptics.warning(); store.show("\(vendorName) ended the talks until week \(until).", tone: "warn"); onClose()
        case .cooling(let until)?:
            message = "They will talk again in week \(until)."
        case .notAllowed?:
            message = "This supplier is fixed by a chain rule or an agreement."
        case .notNeeded(let why)?:
            message = why
        case nil:
            break
        }
    }
}
