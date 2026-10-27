import SwiftUI
import GameCore
import Businesses
import Simulation

/// The bottom sheet for one item: picture, specs, the cost breakdown, the choice of settlement (cash or financed with 20% down), what is
/// due at closing, and one confirm button. Everything comes from the engine: the price list, `luxuryFinanceQuote`, `buyLuxury`.
struct LuxuryItemSheet: View {
    enum Settlement: Hashable { case cash, financed }

    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var itemID: String
    var onBought: () -> Void
    @State private var settlement: Settlement = .cash
    @State private var problem: String? = nil

    private var P: OutsidePalette { .luxury }

    var body: some View {
        Group {
            if let e = store.engine, let it = Luxury.item(itemID) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            LuxuryItemHead(item: it) { dismiss() }
                            LuxuryItemSpecs(item: it)
                            LuxuryBreakdown(item: it)
                            settlementChoice(e, it)
                        }
                        .padding(.bottom, 16)
                    }
                    .scrollIndicators(.hidden)
                    footer(e, it)
                }
            }
        }
        .background(P.ground.ignoresSafeArea())
        .environment(\.outsidePalette, P)
        .preferredColorScheme(.dark)
        .presentationDetents([.fraction(0.9)])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("luxury-item-sheet")
    }

    // MARK: Settlement

    private func settlementChoice(_ e: GameEngine, _ it: Luxury.Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SETTLEMENT").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(P.accent)
            HStack(spacing: 10) {
                option(.cash, "Cash", "Paid in full from your cash")
                option(.financed, "Financed", "20% down, the bank lends the rest")
            }
            if settlement == .financed { financeLines(e, it) }
            if let p = problem { Text(p).font(.system(size: 12.5)).foregroundStyle(P.loss).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, 18)
    }

    private func option(_ s: Settlement, _ title: String, _ sub: String) -> some View {
        let on: Bool = settlement == s
        return Button { settlement = s; problem = nil } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(on ? P.accent : P.ink)
                Text(sub).font(.system(size: 11.5)).foregroundStyle(P.inkFaint).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? P.accentSelected : P.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? P.accent : P.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(P.line, lineWidth: 1))
            if let r = q.refusal { Text(r).font(.system(size: 12)).foregroundStyle(P.caution) }
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
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Due at closing").font(.system(size: 13)).foregroundStyle(P.inkSoft)
                Spacer()
                Text(store.money(amount)).font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(P.ink)
            }
            Button { confirm(it) } label: {
                Text(short ? "Your cash is \(store.short(max(0, e.state.cash)))" : owned ? "Buy another" : "Confirm purchase")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(short ? P.inkFaint : P.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(short ? P.card : P.accent))
            }
            .buttonStyle(.plain)
            .disabled(short)
            .accessibilityIdentifier("luxury-confirm")
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 14)
        .background(P.ground.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(P.line).frame(height: 1) }
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
        store.show("\(it.name) is now in your vault.", tone: "good")
        onBought()
    }
}

struct LuxuryItemHead: View {
    var item: Luxury.Item
    var close: () -> Void
    private var P: OutsidePalette { .luxury }
    var body: some View {
        LuxuryPhoto(itemID: item.id, height: 240)
            .overlay(alignment: .bottom) { LinearGradient(colors: [.clear, P.ground], startPoint: .top, endPoint: .bottom).frame(height: 110) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LuxuryFacts.categoryName(item).uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(P.accent)
                    Text(item.name).font(.serifTitle(26)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 18).padding(.bottom, 8)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: close) {
                    Text("Close").font(.system(size: 12, weight: .semibold)).foregroundStyle(P.ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.plain).padding(12)
                .accessibilityIdentifier("luxury-sheet-close")
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
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(specs.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.0.uppercased()).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(P.inkFaint)
                    Text(s.1).font(.system(size: 13)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(P.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 18)
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
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        .padding(.horizontal, 18)
    }
}

/// One label and a monospaced figure, with a hairline under it unless it is the last.
struct LuxuryLine: View {
    var label: String
    var value: String
    var tint: Color? = nil
    var last = false
    private var P: OutsidePalette { .luxury }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13)).foregroundStyle(P.inkSoft)
            Spacer(minLength: 10)
            Text(value).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(tint ?? P.ink).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(P.divider).frame(height: 1) } }
    }
}
