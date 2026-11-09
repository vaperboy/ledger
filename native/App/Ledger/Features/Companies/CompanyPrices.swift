import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompanyPrices: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var addingService: Bool?
    @State private var showHire = false
    @Environment(\.outsidePalette) private var P

    private struct NewItemPick: Identifiable { var id: Bool }

    var body: some View {
        let items: [SalesItem] = engine.salesItems(companyID: company.id)
        let service: Bool = !items.isEmpty && items.allSatisfy { (i: SalesItem) -> Bool in i.isService }
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if company.type == UsedCarDealer.tradeID {
                UsedCarYardSection(engine: engine, company: company)
            } else if company.type == CarDealer.tradeID {
                CarDealerSection(engine: engine, company: company)
            } else {
                priceList(items, service)
            }
        }
        .centerSheet(item: Binding(get: { addingService.map { (v: Bool) -> NewItemPick in NewItemPick(id: v) } }, set: { (v: NewItemPick?) in addingService = v?.id }), category: .medium, tone: .info) { (p: NewItemPick) in
            NewItemSheet(companyID: company.id, isService: p.id, onClose: { addingService = nil },
                         onHireAdvisor: { addingService = nil; showHire = true },
                         onAdded: { (_: String) in })
        }
        .navigationDestination(isPresented: $showHire) { HireWorkersView(companyID: company.id, startRole: "advisor") }
    }

    private func priceList(_ items: [SalesItem], _ service: Bool) -> some View {
        let cur: Currency = engine.currency(for: company)
        let noun: String = service ? "service" : "product"
        let range: ClosedRange<Double> = engine.itemPriceRange(companyID: company.id)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("What you charge for each \(noun), next to the price in the market.").textStyle(.body, tint: P.inkSoft)
            keepPrice
            PageGroup(service ? "Services" : "Products") {
                if items.isEmpty && company.status == .open && engine.needsFirstItemChoice(companyID: company.id) {
                    FirstItemPicker(engine: engine, company: company, noun: noun, onAddOwn: { addingService = service })
                } else if items.isEmpty {
                    EmptyState(glyph: service ? Glyph.opsWrench : Glyph.opsBox, title: "Nothing is on sale yet",
                               message: company.status == .open ? "Add what you sell." : "", centered: false)
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { (i: Int, it: SalesItem) in
                        if i > 0 { RowRule(inset: 52) }
                        PriceRow(companyID: company.id, item: it, cur: cur, range: range, first: i == 0)
                            .coachAnchor(.firstItemRow, enabled: i == 0)
                    }
                }
                if company.status == .open && !items.isEmpty {
                    Hairline()
                    Button { Haptics.tap(); addingService = service } label: {
                        HStack(spacing: Theme.Space.m) {
                            LedgerGlyph(glyph: Glyph.hire, size: Theme.Icon.medium, tint: P.accent).frame(width: 40)
                            Text("Add a \(noun)").textStyle(.headline, tint: P.accent)
                            Spacer()
                        }
                        .frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(AcctPressStyle())
                    .accessibilityIdentifier("sales-add-item")
                }
            }
        }
    }

    @ViewBuilder private var keepPrice: some View {
        if store.tutorialStep == .setPrice {
            Button("Keep these prices") { Haptics.tap(); store.tutorialAdvance(from: .setPrice) }
                .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                .accessibilityIdentifier("item-keep-price")
        }
    }
}

private struct PriceRow: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var item: SalesItem
    var cur: Currency
    var range: ClosedRange<Double>
    var first: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    private var lo: Double { item.marketPrice * range.lowerBound }
    private var hi: Double { item.marketPrice * range.upperBound }
    private var typed: PriceInput.Result? { PriceInput.parse(text, currency: cur, range: lo...max(lo, hi)) }
    private var changed: Bool { typed.map { (t: PriceInput.Result) -> Bool in abs(t.value - item.price) > 1e-9 } ?? false }
    private var lockedBy: String? { item.priceSetter.isOwner ? nil : item.priceSetter.label }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.m) {
                ThumbnailView(kind: .trade, key: item.name, size: 36, glyph: item.isService ? Glyph.opsWrench : Glyph.opsBox)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(item.name.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    if let lockedBy { Text("Set by \(lockedBy)").textStyle(.caption, tint: P.inkFaint) }
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text("Market").textStyle(.caption, tint: P.inkFaint)
                    Text(itemAmount(item.marketPrice, cur)).textStyle(.body, tint: P.inkSoft, numeric: true)
                }
                field
            }
            if changed, lockedBy == nil {
                HStack(spacing: Theme.Space.s) {
                    if let t = typed, t.clamped {
                        Text("Allowed from \(PriceInput.text(lo, currency: cur)) to \(PriceInput.text(hi, currency: cur))").textStyle(.caption, tint: P.inkFaint)
                    }
                    Spacer(minLength: 0)
                    Button("Set price") { commit() }
                        .buttonStyle(TertiaryButtonStyle(size: .compact))
                        .accessibilityIdentifier("price-set-\(item.id)")
                }
            }
        }
        .padding(.vertical, Theme.Space.s)
        .onAppear { text = PriceInput.text(item.price, currency: cur) }
        .onChange(of: item.price) { (_: Double, p: Double) in if !focused { text = PriceInput.text(p, currency: cur) } }
        .onChange(of: focused) { (_: Bool, f: Bool) in if !f { commit() } }
    }

    private var field: some View {
        HStack(spacing: Theme.Space.xxs) {
            Text(cur.country.currencySymbol).textStyle(.body, tint: P.inkFaint)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .disabled(lockedBy != nil)
                .textStyle(.headline, numeric: true)
                .onSubmit { commit() }
                .accessibilityLabel("Price of \(item.name)")
                .accessibilityIdentifier("sales-item-price-\(item.id)")
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(width: 104, height: 44)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.card))
        .coachAnchor(.itemPrice, enabled: first)
    }

    private func commit() {
        guard lockedBy == nil, changed, let t = typed else {
            text = PriceInput.text(item.price, currency: cur)
            return
        }
        let id: Int = companyID
        let itemID: String = item.id
        let price: Double = t.value
        let r = store.act { $0.setItemPrice(companyID: id, itemID: itemID, price: price) }
        text = PriceInput.text(price, currency: cur)
        if case .refused(let why)? = r {
            Haptics.warning()
            store.show(why, tone: "warn")
            text = PriceInput.text(item.price, currency: cur)
        } else if r?.didChange == true {
            store.saved("price " + itemAmount(price, cur))
        }
    }
}
