import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// "Who supplies it?" for one product or service the company sells. Asked at once when an item is picked or added (`asking`: the best offer is
/// suggested and one button keeps it), and used again from the Supply tab to change the supplier later.
struct ItemSupplierChooser: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var itemID: String
    /// True right after the item was picked or added: the button keeps the suggested supplier and the tutorial moves on.
    var asking: Bool = false
    var onClose: () -> Void

    /// True when the item has suppliers to choose between (an item with no stock to supply has none).
    static func hasChoice(engine: GameEngine, companyID: Int, itemID: String) -> Bool {
        guard let p = engine.itemPage(companyID: companyID, itemID: itemID) else { return false }
        return !p.offers.isEmpty
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let p = e.itemPage(companyID: companyID, itemID: itemID) {
            content(e, co, p)
        } else {
            EmptyState(glyph: Glyph.suppliers, title: "This item is gone")
        }
    }

    /// Offers cheapest first; the current supplier, else the cheapest, is the suggested one.
    private func ordered(_ p: ItemPageData) -> [ItemModels.SupplyLine] {
        p.offers.sorted { (a: ItemModels.SupplyLine, b: ItemModels.SupplyLine) -> Bool in a.buyPrice != b.buyPrice ? a.buyPrice < b.buyPrice : a.vendorName < b.vendorName }
    }

    private func content(_ e: GameEngine, _ co: Company, _ p: ItemPageData) -> some View {
        let cur: Currency = e.currency(for: co)
        let offers: [ItemModels.SupplyLine] = ordered(p)
        let currentID: String? = p.record?.supplierID
        let suggested: ItemModels.SupplyLine? = offers.first { (o: ItemModels.SupplyLine) -> Bool in o.vendorID == currentID } ?? offers.first
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Who supplies \(p.item.name.tidyText)?").popupText(.title)
            if offers.isEmpty {
                Text("This one needs no supplier.").popupText(.subtitle)
            } else {
                Text(asking ? "We suggest \(suggested?.vendorName ?? "one of these"). You can change it any time under Supply." : "Pick who you buy it from.").popupText(.subtitle)
                VStack(spacing: 0) {
                    ForEach(Array(offers.enumerated()), id: \.element.vendorID) { (n: Int, o: ItemModels.SupplyLine) in
                        if n > 0 { Hairline() }
                        offerRow(o, cur, current: o.vendorID == currentID, suggested: o.vendorID == suggested?.vendorID && currentID == nil)
                    }
                }
                if asking, let s = suggested {
                    Button(currentID == nil ? "Use \(s.vendorName)" : "Keep \(s.vendorName)") { keep(s, hasCurrent: currentID != nil) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("item-supplier-keep")
                }
            }
            Button(asking ? "Decide later" : "Done") { Haptics.tap(); onClose() }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("item-supplier-done")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle("Supplier")
        .accessibilityIdentifier("item-supplier-chooser")
    }

    private func offerRow(_ o: ItemModels.SupplyLine, _ cur: Currency, current: Bool, suggested: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(o.vendorName.tidyText).popupText(.body).lineLimit(2)
                Spacer(minLength: Theme.Space.s)
                if current { Chip(text: "In use", tint: P.accent) } else if suggested { Chip(text: "Suggested", tint: P.gain) }
            }
            Text("You pay \(itemAmount(o.buyPrice, cur)) each" + (o.leadDays > 0 ? " \u{00B7} \(o.leadDays) days" : "") + " \u{00B7} " + o.relationshipWord)
                .popupText(.caption)
            if !current {
                Button("Use this supplier") { choose(o) }
                    .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                    .accessibilityIdentifier("item-supplier-use-\(o.vendorID)")
            }
        }
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keep(_ o: ItemModels.SupplyLine, hasCurrent: Bool) {
        Haptics.tap()
        if hasCurrent {
            store.tutorialAdvance(from: .pickSupplier)
            onClose()
        } else {
            choose(o)
        }
    }

    private func choose(_ o: ItemModels.SupplyLine) {
        let id: Int = companyID
        let item: String = itemID
        let vendor: String = o.vendorID
        let r = store.act { $0.setItemSupplier(companyID: id, itemID: item, vendorID: vendor) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn"); return }
        if r?.didChange == true { Haptics.success(); store.saved("supplied by " + o.vendorName) }
        if asking { store.tutorialAdvance(from: .pickSupplier); onClose() }
    }
}

/// The Supply tab's part for what the company sells: one card per product or service, with who supplies it and Change.
struct ItemSupplySection: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company
    @State private var changing: ItemPick?

    struct ItemPick: Identifiable, Hashable { var id: String }

    var body: some View {
        let items: [SalesItem] = engine.salesItems(companyID: company.id)
        let cur: Currency = engine.currency(for: company)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(items.allSatisfy { (i: SalesItem) -> Bool in i.isService } ? "What you sell: services" : "What you sell").textStyle(.label, tint: P.inkFaint)
            ForEach(Array(items.enumerated()), id: \.element.id) { (n: Int, it: SalesItem) in
                card(it, cur, first: n == 0)
            }
        }
        .centerSheet(item: $changing, category: .medium, tone: .info) { (p: ItemPick) in
            ItemSupplierChooser(companyID: company.id, itemID: p.id, onClose: { changing = nil })
        }
    }

    private func card(_ it: SalesItem, _ cur: Currency, first: Bool) -> some View {
        let page: ItemPageData? = engine.itemPage(companyID: company.id, itemID: it.id)
        let offers: Int = page?.offers.count ?? 0
        let supply: ItemModels.SupplyLine? = page?.supply
        let id: String = it.id
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(it.name.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.s)
                Chip(text: it.isService ? "Service" : "Product", tint: P.inkFaint)
            }
            Hairline()
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    if let s = supply {
                        Text(s.vendorName.tidyText).textStyle(.body).lineLimit(2).multilineTextAlignment(.leading)
                        Text("You pay \(itemAmount(s.buyPrice, cur)) each" + (s.leadDays > 0 ? " \u{00B7} \(s.leadDays) days" : "")).textStyle(.caption, tint: P.inkSoft, numeric: true)
                    } else if offers > 0 {
                        Text("No supplier chosen").textStyle(.body, tint: P.caution)
                        Text("Pick one so it can be stocked.").textStyle(.caption, tint: P.inkSoft)
                    } else {
                        Text("Needs no supplier").textStyle(.body, tint: P.inkSoft)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                if offers > 0 {
                    Button("Change") { Haptics.tap(); changing = ItemPick(id: id) }
                        .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                        .accessibilityIdentifier("item-supplier-change-\(id)")
                        .coachAnchor(.itemSupplier, enabled: first)
                }
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
        .accessibilityElement(children: .contain)
    }
}
