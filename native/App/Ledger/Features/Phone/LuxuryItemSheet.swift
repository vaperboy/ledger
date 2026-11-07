import SwiftUI
import GameCore
import Businesses
import Simulation

/// The bottom sheet for one item: picture, specs, the cost breakdown, the choice of settlement (cash or financed with 20% down), what is
/// due at closing, and one confirm button. Everything comes from the engine: the price list, `luxuryFinanceQuote`, `buyLuxury`.
struct LuxuryItemSheet: View {
    enum Settlement: Hashable { case cash, financed }

    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var itemID: String
    var onBought: () -> Void
    @State private var settlement: Settlement = .cash
    @State private var problem: String? = nil

    private var P: OutsidePalette { .luxury }

    var body: some View {
        Group {
            if let e = store.engine, let it = Luxury.item(itemID) {
                VStack(spacing: 0) {
                    Group {
                        VStack(alignment: .leading, spacing: Theme.Space.l) {
                            LuxuryItemHead(item: it)
                            LuxuryItemSpecs(item: it)
                            LuxuryBreakdown(item: it)
                            settlementChoice(e, it)
                        }
                        .padding(.bottom, Theme.Space.l)
                    }
                    footer(e, it)
                }
            }
        }
        .background(P.ground.ignoresSafeArea())
        .environment(\.outsidePalette, P)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("luxury-item-sheet")
    }

    // MARK: Settlement

    private func settlementChoice(_ e: GameEngine, _ it: Luxury.Item) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Settlement").textStyle(.label)
            HStack(spacing: Theme.Space.s) {
                option(.cash, "Cash", "Paid in full from your cash")
                option(.financed, "Financed", "20% down, the bank lends the rest")
            }
            if settlement == .financed { financeLines(e, it) }
            if let p = problem { Text(p).popupText(.risk) }
        }
        .padding(.horizontal, Theme.Space.page)
    }

    private func option(_ s: Settlement, _ title: String, _ sub: String) -> some View {
        let on: Bool = settlement == s
        return Button { Haptics.choose(); settlement = s; problem = nil } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).textStyle(.headline, tint: on ? P.accent : P.ink)
                Text(sub).textStyle(.caption).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .padding(Theme.Space.m)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(on ? P.accentWash : P.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("luxury-settle-" + (s == .cash ? "cash" : "financed"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func financeLines(_ e: GameEngine, _ it: Luxury.Item) -> some View {
        if let q = e.luxuryFinanceQuote(itemID: it.id) {
            VStack(spacing: 0) {
                LuxuryLine(label: "Down payment (20%)", value: store.short(q.down))
                LuxuryLine(label: "Bank loan", value: store.short(q.loan))
                LuxuryLine(label: "Bank fee", value: store.short(q.fee))
                LuxuryLine(label: "Interest a year", value: String(format: "%.2f%%", q.yearlyRate * 100))
                LuxuryLine(label: "Repayment a month, \(q.termMonths) months", value: store.short(q.monthlyPayment), last: true)
            }
            if let r = q.refusal { Text(r).popupText(.risk) }
        }
    }

    // MARK: Footer

    private func due(_ e: GameEngine, _ it: Luxury.Item) -> Double {
        settlement == .cash ? it.price : (e.luxuryFinanceQuote(itemID: it.id)?.dueAtClosing ?? it.price)
    }

    private func footer(_ e: GameEngine, _ it: Luxury.Item) -> some View {
        let owned: Bool = e.luxuryPieces.contains { $0.item.id == it.id }
        let amount: Double = due(e, it)
        let short: Bool = e.state.cash < amount
        return VStack(spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Due at closing").popupText(.subtitle)
                Spacer()
                Text(store.money(amount)).textStyle(.figure)
            }
            PrimaryAction(title: owned ? "Buy another" : "Confirm purchase",
                          blockedReason: short ? "Your cash is \(store.short(max(0, e.state.cash)))." : nil,
                          identifier: "luxury-confirm") { confirm(it) }
        }
        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.m)
        .background(P.page.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
    }

    private func confirm(_ it: Luxury.Item) {
        problem = nil
        if settlement == .cash {
            switch store.act({ $0.buyLuxury(itemID: it.id) }) {
            case .ok?: done(it)
            case .notEnoughCash?: problem = "Not enough cash for this purchase."
            default: problem = "This purchase is not possible."
            }
        } else {
            switch store.act({ $0.buyLuxuryFinanced(itemID: it.id) }) {
            case .ok?: done(it)
            case .notEnoughCash?: problem = "Not enough cash for the down payment and the bank fee."
            case .refused(let why)?: problem = why
            default: problem = "This purchase is not possible."
            }
        }
    }

    private func done(_ it: Luxury.Item) {
        Haptics.success()
        store.tellLuxury(name: it.name, price: store.money(it.price))
        onBought()
    }
}

struct LuxuryItemHead: View {
    var item: Luxury.Item
    private var P: OutsidePalette { .luxury }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            LuxuryPhoto(itemID: item.id, height: 240)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(LuxuryFacts.categoryName(item)).textStyle(.label)
                Text(item.name).textStyle(.title).accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, Theme.Space.page)
        }
    }
}

struct LuxuryItemSpecs: View {
    var item: Luxury.Item
    private var P: OutsidePalette { .luxury }

    private var specs: [(String, String)] {
        var rows: [(String, String)] = [("Category", LuxuryFacts.categoryName(item)), ("About", item.detail), ("Outlook", item.trend)]
        if let est = Luxury.estateInfo(item.id) { rows.append(("Earns from", est.what)) }
        else { rows.append(("Selling costs", "\(Int((Luxury.sellFee * 100).rounded()))% of the value")) }
        return rows
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.l, alignment: .topLeading), GridItem(.flexible(), spacing: Theme.Space.l, alignment: .topLeading)],
                  alignment: .leading, spacing: Theme.Space.m) {
            ForEach(Array(specs.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(s.0).textStyle(.caption, tint: P.inkFaint)
                    Text(s.1).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, Theme.Space.page)
    }
}

struct LuxuryBreakdown: View {
    @EnvironmentObject var store: GameStore
    var item: Luxury.Item
    private var P: OutsidePalette { .luxury }
    var body: some View {
        VStack(spacing: 0) {
            LuxuryLine(label: "Acquisition price", value: store.money(item.price))
            LuxuryLine(label: "Monthly upkeep", value: store.money(item.monthlyUpkeep), tint: P.loss)
            LuxuryLine(label: "Value change a year", value: LuxuryFacts.percent(item.growth), tint: item.growth >= 0 ? P.gain : P.loss, last: true)
        }
        .overlay(alignment: .top) { Hairline() }
        .padding(.horizontal, Theme.Space.page)
    }
}

/// One label and a tabular figure, with a hairline under it unless it is the last.
struct LuxuryLine: View {
    var label: String
    var value: String
    var tint: Color? = nil
    var last = false
    private var P: OutsidePalette { .luxury }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).textStyle(.body, tint: P.inkSoft)
            Spacer(minLength: Theme.Space.m)
            Text(value).textStyle(.body, tint: tint ?? P.ink, numeric: true, weight: .medium).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Theme.Space.m)
        .overlay(alignment: .bottom) { if !last { Hairline() } }
    }
}
