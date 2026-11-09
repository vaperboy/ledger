import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// What a week of a purchase cost, with the arrow against the week before: green when it fell, red when it rose. Without a figure for the
/// week before it is the amount alone; a purchase billed per job has no weekly figure and says so.
struct SupplyCost: View {
    var now: Double?
    var before: Double?
    var currency: Currency
    var step: TextStep = .headline

    var body: some View {
        if let now {
            if let before, before > 0 {
                ArrowAmount(gain: before - now, amount: now, format: { (v: Double) -> String in currency.tidyShort(v) }, step: step)
            } else {
                Text(currency.tidyShort(now)).textStyle(step, numeric: true)
            }
        } else {
            Text("Billed per job").textStyle(.caption, tint: Theme.inkFaint)
        }
    }
}

/// The plain words for how good and how dependable a supplier is. "Patchy" supply is the one that needs a look, so it gets the caution colour.
struct SupplyWords: View {
    var quality: String
    var reliability: String

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text("\(quality) quality").textStyle(.caption, tint: Theme.inkSoft)
            Text("\(reliability) supply").textStyle(.caption, tint: reliability == "Patchy" ? Theme.caution : Theme.inkSoft)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

/// One thing a company buys: the item, who supplies it now, quality and reliability in words, and this week's cost with its arrow. A tap opens
/// the offers.
struct SupplyLineRow: View {
    var row: SupplyRow
    var currency: Currency
    /// The player supplying this line under a contract, when there is one.
    var playerSupplier: String? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(row.title.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text(playerSupplier.map { $0.tidyText + " · Player supplier" } ?? row.current.tidyText).textStyle(.caption, tint: Theme.inkSoft).lineLimit(1)
                    SupplyWords(quality: row.quality, reliability: row.reliability)
                    if let note = row.governed ?? row.note {
                        Text(note.tidyText).textStyle(.caption, tint: Theme.caution).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    SupplyCost(now: row.weekly, before: row.weeklyBefore, currency: currency)
                    if row.weekly != nil { Text("a week").textStyle(.caption, tint: Theme.inkFaint) }
                }
            }
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Compare suppliers")
    }
}

/// The offers for one purchase, side by side in a popup: who, how good, how dependable, terms and lead time, the cost a week against now, and
/// the button to switch. It reads the company live, so after a switch the popup shows the new supplier in use.
struct SupplyOffersPopup: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var lineID: String
    /// Opens the Browse page for this purchase (the screen closes this popup and pushes it).
    var onBrowse: () -> Void = {}
    @State private var message: String?

    private let classNames: [String] = Suppliers.goodsClassNames

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let row = e.supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == lineID }) {
            content(e, co, row)
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company, _ row: SupplyRow) -> some View {
        let cur: Currency = e.currency(for: co)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(row.scale).popupText(.caption)
            if row.id == "goods" { goodsClass(co) }
            if let governed = row.governed { Text(governed).popupText(.risk) }
            if let note = row.note { Text(note).popupText(.risk) }
            if let message { Text(message).popupText(.risk) }
            if row.governed == nil && !SupplyMarketCatalogue.tradesSupplying(line: row.id).isEmpty {
                SupplyWaysBlock(companyID: companyID, row: row, currency: cur, onBrowse: onBrowse)
                Hairline()
                Text("Other suppliers").capsLabel(Theme.ivoryFaint)
                Text("The backup if a supplier stops, at market price.").popupText(.caption)
            }
            ForEach(Array(row.offers.enumerated()), id: \.element.id) { (n: Int, o: SupplyOfferRow) in
                if n > 0 { Hairline() }
                offer(o, row: row, cur: cur)
            }
            if row.offers.count < 2 {
                Text("No other supplier offers this yet.").popupText(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(row.title)
    }

    private func goodsClass(_ co: Company) -> some View {
        let raw: JSONValue = co.value("src")["c"]
        let now: Int = min(2, max(0, raw.isNull ? 1 : raw.int))
        let binding = Binding<Int>(get: { now }, set: { (v: Int) in
            _ = store.act { $0.chooseGoodsClass(companyID: companyID, goodsClass: v) }
            Haptics.tap()
        })
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Price tier").capsLabel(Theme.ivoryFaint)
            SegmentedPill(items: [0, 1, 2], title: { (i: Int) -> String in classNames[i] }, selection: binding)
            Text("Basic costs less and lowers quality a little; Premium costs more and lifts it.").popupText(.caption)
        }
    }

    private func offer(_ o: SupplyOfferRow, row: SupplyRow, cur: Currency) -> some View {
        let locked: Bool = row.governed != nil
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(o.name.tidyText).textStyle(.headline)
                    if !o.detail.isEmpty { Text(o.detail.tidyText).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: Theme.Space.s)
                if o.isCurrent { Chip(text: "In use", tint: Theme.gold) }
            }
            SupplyWords(quality: o.quality, reliability: o.reliability)
            Text("\(o.terms) · \(o.lead)").textStyle(.caption, tint: Theme.inkFaint)
            HStack(alignment: .center, spacing: Theme.Space.s) {
                if let w = o.weekly {
                    Text(cur.tidyShort(w) + " a week").textStyle(.caption, tint: Theme.inkSoft, numeric: true)
                    if !o.isCurrent, let d = o.weeklyVsNow, abs(d) >= 0.5 {
                        ArrowAmount(gain: -d, amount: abs(d), format: { (v: Double) -> String in cur.tidyShort(v) }, step: .caption)
                    }
                }
                Spacer(minLength: 0)
            }
            if let b = o.blocked {
                Text(b).popupText(.risk)
            } else if !o.isCurrent && !locked {
                QuietButton(title: "Use \(o.name)", fullWidth: true) { choose(o) }
            }
        }
    }

    private func choose(_ o: SupplyOfferRow) {
        let result: SupplierSwitchResult? = store.act { $0.chooseSupply(companyID: companyID, change: o.change) }
        switch result {
        case .ok?: Haptics.success(); message = nil
        case .notKnownWell?: Haptics.warning(); message = "They do not know you well enough yet. Buy from them or take them to lunch first."
        case .governed?: Haptics.warning(); message = "A chain rule or your franchise agreement fixes this supplier."
        default: Haptics.warning(); message = "That supplier is not available for this company now."
        }
    }
}
