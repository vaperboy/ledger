import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct SupplyOtherPlayersScreen: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var companyID: Int?
    @State private var editor: EditorPick?
    @State private var detail: DetailPick?

    struct EditorPick: Identifiable, Equatable {
        var id: String { draft.listingID ?? "new-\(draft.companyID)" }
        var draft: ListingDraft
        var maxCapacity: Int
        var lines: [SupplyMarketCatalogue.Line]
    }

    struct DetailPick: Identifiable, Equatable { var id: String }

    var body: some View {
        if let e = store.engine {
            let cos: [Company] = e.state.companies.filter { (c: Company) -> Bool in
                c.status == .open && (companyID == nil || c.id == companyID) && SupplyMarketCatalogue.canSupply(tradeID: c.type)
            }
            ScrollScreen(spacing: Theme.Space.xl) {
                intro
                if cos.isEmpty {
                    EmptyState(glyph: Glyph.suppliers, title: "No company that can supply", message: "Open a company that makes something other players buy.")
                }
                ForEach(cos, id: \.id) { (co: Company) in section(e, co) }
            }
            .appScreen(title: "Supply other players", subtitle: companyID.flatMap { e.state.company($0)?.name } ?? "", tab: .company)
            .centerSheet(item: $editor, category: .medium, tone: .info) { (p: EditorPick) in
                ListingEditorPopup(pick: p, onDone: { editor = nil }).environmentObject(store)
            }
            .centerSheet(item: $detail, category: .medium, tone: .info) { (p: DetailPick) in
                ListingOrdersPopup(listingID: p.id).environmentObject(store)
            }
            .task { market.sync(store) }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Supplying").capsLabel(Theme.ivoryFaint)
            Text("Offer what your company makes from the trade's catalogue. A new supplier has a weekly limit that rises with a clean record. Buyers see how often you deliver on time and in full.")
                .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
    }

    @ViewBuilder private func section(_ e: GameEngine, _ co: Company) -> some View {
        if let bd = e.data.catalog[co.type] {
            let cap = SupplyMarketBooks.capacity(co, bd: bd)
            let lines: [SupplyMarketCatalogue.Line] = SupplyMarketCatalogue.supplyableLines(tradeID: bd.id)
            let mine: [SupplyListing] = lines.flatMap { (_: SupplyMarketCatalogue.Line) -> [SupplyListing] in [] } + market.service.myListings(companyID: co.id)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(co.name).capsLabel(Theme.ivoryFaint).padding(.horizontal, 2)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if let why = cap.why {
                        Text(why).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Can carry about \(cap.maxUnits) units a week for other players.").textStyle(.caption, tint: Theme.inkSoft)
                        ForEach(mine) { (l: SupplyListing) in listingBlock(l, e, co) }
                        QuietButton(title: mine.isEmpty ? "Offer to other players" : "Add another listing", fullWidth: true) {
                            var d = ListingDraft(listingID: nil, companyID: co.id, companyName: co.name, tradeID: bd.id, lineID: lines[0].id)
                            d.capacityPerWeek = max(5, min(cap.maxUnits, 50))
                            d.minOrder = min(10, d.capacityPerWeek)
                            d.unitValue = SupplyMarketBooks.unitValue(co)
                            d.country = co.countryCode
                            editor = EditorPick(draft: d, maxCapacity: cap.maxUnits, lines: lines)
                        }
                    }
                }
                .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
            }
        }
    }

    private func listingBlock(_ l: SupplyListing, _ e: GameEngine, _ co: Company) -> some View {
        let today: Int = SupplyMarketStore.today(e)
        let orders: [SupplyOrder] = market.service.orders(listingID: l.id)
        let state: String = l.paused ? "Paused" : (l.expiresDay.map { $0 < today } ?? false) ? "Offer ended" : "Offered" + (l.expiresDay.map { " for \(max(0, $0 - today)) more days" } ?? "")
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Hairline()
            HStack(alignment: .firstTextBaseline) {
                Text(l.lineName).textStyle(.headline)
                Spacer(minLength: Theme.Space.s)
                Chip(text: l.paused ? "Paused" : "Live", tint: l.paused ? Theme.caution : Theme.gain)
            }
            Text("\(state) · \(SupplyMarketWords.price(l.priceTier)) · \(SupplyMarketWords.quality(l.qualityTier))").textStyle(.caption, tint: Theme.inkSoft)
            Text("\(SupplyGuards.effectiveCapacity(l)) units/week · \(SupplyMarketWords.lead(l.leadDays)) · minimum \(l.minOrder)").textStyle(.caption, tint: Theme.inkFaint)
            if let limit = SupplyGuards.limitText(l) { Text(limit).textStyle(.caption, tint: Theme.caution) }
            Text(orders.isEmpty ? "No orders yet." : "\(orders.count) recent \(orders.count == 1 ? "order" : "orders"), latest from \(orders[0].buyerName).").textStyle(.caption, tint: Theme.inkSoft)
            DeliveryRecordView(record: l.record)
            HStack(spacing: Theme.Space.s) {
                QuietButton(title: "Orders", fullWidth: true) { detail = DetailPick(id: l.id) }
                QuietButton(title: "Edit", fullWidth: true) { openEditor(l, e, co) }
            }
            HStack(spacing: Theme.Space.s) {
                QuietButton(title: l.paused ? "Resume" : "Pause", fullWidth: true) { market.service.setPaused(listingID: l.id, !l.paused) }
                QuietButton(title: "Stop supplying", tint: Theme.loss, fullWidth: true) { market.service.stopListing(listingID: l.id) }
            }
        }
    }

    private func openEditor(_ l: SupplyListing, _ e: GameEngine, _ co: Company) {
        guard let bd = e.data.catalog[co.type] else { return }
        var d = ListingDraft(listingID: l.id, companyID: co.id, companyName: co.name, tradeID: bd.id, lineID: l.lineID)
        d.priceTier = l.priceTier; d.qualityTier = l.qualityTier; d.capacityPerWeek = l.capacityPerWeek; d.leadDays = l.leadDays
        d.minOrder = l.minOrder; d.termsDays = l.termsDays; d.unitValue = SupplyMarketBooks.unitValue(co); d.country = co.countryCode
        editor = EditorPick(draft: d, maxCapacity: SupplyMarketBooks.capacity(co, bd: bd).maxUnits, lines: SupplyMarketCatalogue.supplyableLines(tradeID: bd.id))
    }
}

struct ListingEditorPopup: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var pick: SupplyOtherPlayersScreen.EditorPick
    var onDone: () -> Void
    @State private var draft: ListingDraft
    @State private var capacity: Double
    @State private var lead: Double
    @State private var minimum: Double
    @State private var message: String?

    init(pick: SupplyOtherPlayersScreen.EditorPick, onDone: @escaping () -> Void) {
        self.pick = pick
        self.onDone = onDone
        _draft = State(initialValue: pick.draft)
        _capacity = State(initialValue: Double(pick.draft.capacityPerWeek))
        _lead = State(initialValue: Double(pick.draft.leadDays))
        _minimum = State(initialValue: Double(pick.draft.minOrder))
    }

    private static let durations: [Int] = SupplyMarketCatalogue.durations

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if pick.draft.listingID == nil {
                Menu {
                    ForEach(pick.lines) { (l: SupplyMarketCatalogue.Line) in Button(l.name) { draft.lineID = l.id } }
                } label: {
                    HStack {
                        Text("Offering").popupText(.rowLabel)
                        Spacer(minLength: Theme.Space.s)
                        Text(SupplyMarketCatalogue.line(draft.lineID)?.name ?? "").popupText(.rowValue)
                    }
                }
            } else {
                Text(SupplyMarketCatalogue.line(draft.lineID)?.name ?? "").popupText(.title)
            }
            Text("Only what the trade's catalogue lists can be offered.").popupText(.caption)
            tiers("Price", SupplyMarketCatalogue.priceTiers, $draft.priceTier)
            tiers("Quality", SupplyMarketCatalogue.qualityTiers, $draft.qualityTier)
            stepper("Capacity a week", $capacity, 5...Double(max(5, pick.maxCapacity)), 5, suffix: " units")
            if let cap = SupplyGuards.newSupplierCap(DeliveryRecord()), pick.draft.listingID == nil {
                Text("Limit while new: \(cap) units/week. It rises with each clean week of deliveries.").popupText(.risk)
            }
            stepper("Lead time", $lead, 1...10, 1, suffix: " days")
            stepper("Minimum order", $minimum, 5...max(5, capacity), 5, suffix: " units")
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("The offer lasts").popupText(.rowLabel)
                SegmentedPill(items: Self.durations, title: { (d: Int) -> String in d == 1 ? "1 day" : "\(d) days" }, selection: $draft.durationDays)
            }
            if let message { Text(message).popupText(.risk) }
            PopupOptionButton(title: pick.draft.listingID == nil ? "Start supplying" : "Save changes", highlighted: true) { save() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(pick.draft.listingID == nil ? "New listing" : "Edit listing")
    }

    private func tiers(_ title: String, _ names: [String], _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).popupText(.rowLabel)
            SegmentedPill(items: [0, 1, 2], title: { (i: Int) -> String in names[i] }, selection: value)
        }
    }

    private func stepper(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double, suffix: String) -> some View {
        HStack {
            Text(title).popupText(.rowLabel)
            Spacer(minLength: Theme.Space.s)
            Text("\(Int(value.wrappedValue))\(suffix)").popupText(.rowValue)
            StepperPill(value: value, range: range, step: step)
        }
    }

    private func save() {
        guard let e = store.engine else { return }
        var d: ListingDraft = draft
        d.capacityPerWeek = Int(capacity); d.leadDays = Int(lead); d.minOrder = Int(min(minimum, capacity))
        switch market.service.saveListing(d, today: SupplyMarketStore.today(e)) {
        case .saved:
            Haptics.success()
            onDone()
        case .refused(let why):
            Haptics.warning()
            message = why
        }
    }
}

struct ListingOrdersPopup: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var listingID: String

    private var currency: Currency? {
        guard let e = store.engine, let cid = market.service.listing(listingID)?.companyID, let co = e.state.company(cid) else { return nil }
        return e.currency(for: co)
    }

    var body: some View {
        let orders: [SupplyOrder] = market.service.orders(listingID: listingID)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if orders.isEmpty {
                Text("No orders yet. They come in as weeks pass.").popupText(.caption)
            }
            ForEach(Array(orders.enumerated()), id: \.element.id) { (n: Int, o: SupplyOrder) in
                if n > 0 { Hairline() }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(o.buyerName).popupText(.body)
                        Text("\(o.delivered) of \(o.units) units · " + (o.late ? "Late" : "On time")).popupText(.caption, variant: .standard)
                    }
                    Spacer(minLength: Theme.Space.s)
                    if o.revenue > 0 { Text(currency.map { $0.tidyShort(o.revenue) } ?? "").popupText(.rowValue) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle("Orders")
    }
}
