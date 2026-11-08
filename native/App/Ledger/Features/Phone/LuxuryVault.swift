import SwiftUI
import GameCore
import Businesses
import Simulation

/// The My Vault tab: what the collection is worth as the one figure, then each piece as a row; a row opens Inspect (use, lend, sell).
struct LuxuryVaultTab: View {
    @EnvironmentObject var store: GameStore
    var onInspect: (Int) -> Void
    var onShowroom: () -> Void
    private var P: OutsidePalette { .luxury }

    var body: some View {
        if let e = store.engine {
            let pieces: [Luxury.Piece] = e.luxuryPieces
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    summary(e, pieces)
                    if pieces.isEmpty {
                        EmptyState(glyph: Glyph.bank, title: "Your vault is empty", message: "What you buy in the Showroom is kept here, with its value and upkeep.",
                                   actionTitle: "Open the Showroom", action: onShowroom)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Your collection").textStyle(.label, tint: P.inkFaint).padding(.bottom, Theme.Space.s)
                            ForEach(Array(pieces.enumerated()), id: \.element.id) { (n: Int, p: Luxury.Piece) in
                                if n > 0 { Hairline().padding(.leading, 92) }
                                row(p)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xxl)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// What the collection is worth, what it cost, and what it costs to keep.
    private func summary(_ e: GameEngine, _ pieces: [Luxury.Piece]) -> some View {
        let worth: Double = pieces.reduce(0) { $0 + $1.value }
        let paid: Double = pieces.reduce(0) { $0 + $1.paid }
        let change: Double = worth - paid
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("My vault").textStyle(.label, tint: P.inkFaint)
            Text(store.short(worth)).font(.system(size: 40, weight: .regular, design: .serif).monospacedDigit()).foregroundStyle(P.ink)
                .lineLimit(2).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            if !pieces.isEmpty {
                Text((change >= 0 ? "+" : "\u{2212}") + store.short(abs(change)) + " on what you paid").textStyle(.body, tint: P.change(change), numeric: true)
            }
            Text((pieces.count == 1 ? "1 piece" : "\(pieces.count) pieces") + " \u{00B7} " + store.short(Luxury.upkeepPerMonth(e.state)) + " a month to keep")
                .textStyle(.caption, tint: P.inkFaint, numeric: true)
        }
    }

    private func row(_ p: Luxury.Piece) -> some View {
        let change: Double = p.value - p.paid
        return Button { Haptics.tap(); onInspect(p.id) } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                LuxuryPhoto(itemID: p.item.id, height: 60).frame(width: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(p.item.name).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text(LuxuryFacts.categoryName(p.item)).textStyle(.caption, tint: P.inkFaint)
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text(store.short(p.value)).textStyle(.headline, numeric: true).lineLimit(1)
                    Text((change >= 0 ? "+" : "\u{2212}") + store.short(abs(change))).textStyle(.caption, tint: P.change(change), numeric: true).lineLimit(1)
                }
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
            }
            .padding(.vertical, Theme.Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("luxury-inspect-\(p.id)")
    }
}

/// Inspect: how the piece was bought, its upkeep, and what can be done with it (use, lend, host).
struct LuxuryInspectSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var pieceID: Int
    @State private var pending: PendingAction? = nil
    private var P: OutsidePalette { .luxury }

    private func askToSell(_ e: GameEngine, _ p: Luxury.Piece) {
        guard let get = e.luxurySellQuote(pieceID: p.id) else { return }
        let fee: Int = Int(saturating: (Luxury.sellFee * 100).rounded())
        let message: String = "You receive \(store.money(get)), after \(fee)% selling costs. A gain is taxed with your other gains."
        pending = PendingAction(title: "Sell \(p.item.name)?", message: message, button: "Sell for \(store.short(get))", destructive: false, tone: .warning, icon: "tag") {
            let v: Double = store.act { $0.sellLuxury(pieceID: p.id) } ?? 0
            store.show(v > 0 ? "Sold for \(store.short(v))." : "It cannot be sold right now.", tone: v > 0 ? "good" : "warn")
            if v > 0 { dismiss() }
        }
    }

    var body: some View {
        if let e = store.engine, let p = e.luxuryPieces.first(where: { $0.id == pieceID }) {
            Group {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    LuxuryItemHead(item: p.item)
                    Text(useLine(e, p)).popupText(.subtitle).padding(.horizontal, Theme.Space.page)
                    manage(e, p).padding(.horizontal, Theme.Space.page)
                    sellButton(e, p).padding(.horizontal, Theme.Space.page)
                }
                .padding(.bottom, Theme.Space.xl)
            }
            .background(P.ground.ignoresSafeArea())
            .environment(\.outsidePalette, P)
            .preferredColorScheme(.dark)
            .confirmAction($pending)
        }
    }

    /// Selling is the quiet last line of Inspect, with the price it would fetch.
    private func sellButton(_ e: GameEngine, _ p: Luxury.Piece) -> some View {
        let get: Double? = e.luxurySellQuote(pieceID: p.id)
        return Button(get.map { "Sell for " + store.short($0) } ?? "Not for sale now") { askToSell(e, p) }
            .buttonStyle(TertiaryButtonStyle(fullWidth: true, tint: P.loss))
            .disabled(get == nil)
            .accessibilityIdentifier("luxury-sell")
    }

    private func useLine(_ e: GameEngine, _ p: Luxury.Piece) -> String {
        var parts = ["Bought for " + store.short(p.paid)]
        if p.companyID != 0, let c = e.state.company(p.companyID) { parts.append("owned by " + c.name) }
        switch p.use {
        case "charter": parts.append("chartered out")
        case "rent": parts.append("rented out")
        case "museum": parts.append("at the museum until " + GameCalendar.monthString(week: p.until))
        default: break
        }
        if p.weeklyIncome > 0 { parts.append(store.short(p.weeklyIncome * 52 / 12) + " a month") }
        return parts.joined(separator: " · ")
    }


    @ViewBuilder private func manage(_ e: GameEngine, _ p: Luxury.Piece) -> some View {
        let uses = Luxury.uses(for: p.item.category)
        VStack(alignment: .leading, spacing: 0) {
            FlatRow(label: "Bought", value: GameCalendar.monthString(week: p.week) + " for " + store.short(p.paid))
            FlatRow(label: "Upkeep and insurance", value: store.short(p.item.upkeep * p.paid / 12) + " a month")
            if p.companyID != 0 {
                FlatRow(label: "In the company's books", value: store.short(p.bookValue))
                FlatRow(label: "Benefit tax on your salary", value: store.short(Luxury.benefitPerYear(p, e.state)) + " a year")
            }
            if let est = Luxury.estateInfo(p.item.id) {
                FlatRow(label: est.what, value: "about " + store.short(p.value * est.yearly / 12) + " a month")
                if p.item.id == "e1" {
                    let vint = e.state.rest["lux"]?.array.first { $0["id"].int == p.id }?["vint"]
                    FlatRow(label: "This year", value: vint == nil || vint!.isNull ? "A normal year until the harvest" : Luxury.vintageWord(vint!.double))
                }
            }
            if !uses.isEmpty && p.use != "museum" {
                Text("Use").capsLabel(P.inkFaint).padding(.top, Theme.Space.s)
                SegmentedPill(items: [""] + uses.map { $0.id }, title: { id in id.isEmpty ? "Keep it" : uses.first { $0.id == id }?.name ?? id },
                            selection: Binding(get: { p.use }, set: { v in
                                if store.act({ $0.setLuxuryUse(pieceID: p.id, use: v.isEmpty ? nil : v) }) != nil { store.saved(v.isEmpty ? "\(p.item.name) is kept for yourself." : "\(p.item.name): \(uses.first { $0.id == v }?.name.lowercased() ?? v).") } }))
                if let u = uses.first(where: { $0.id == p.use }) { Text(u.detail.tidyMoney).popupText(.caption).padding(.top, Theme.Space.xs) }
            }
            if p.item.id == "e5" {
                let open = (e.state.rest["lux"]?.array.first { $0["id"].int == p.id }?["mode"].string ?? "open") != "private"
                SegmentedPill(items: [true, false], title: { $0 ? "Open for events" : "Keep it private" },
                            selection: Binding(get: { open }, set: { v in
                                if store.act({ $0.setCastleOpen(pieceID: p.id, open: v) }) != nil { store.saved(v ? "the castle is open for events." : "the castle is private.") } }))
            }
            LendPieceSection(engine: e, piece: p)
            WrapRow(spacing: Theme.Space.s) {
                if p.item.category == "yachts", p.companyID == 0, let q = e.yachtDinnerQuote() {
                    Button(q.waitWeeks > 0 ? "Dinner in \(q.waitWeeks) wk" : "Host a dinner") {
                        pending = PendingAction(title: "Host a dinner on board?",
                                                message: "Costs \(store.short(q.cost)) from your cash. Warms the three suppliers you know least. Possible once every four weeks.",
                                                button: "Host for \(store.short(q.cost))", amount: q.cost, currency: e.homeCurrency, tone: .prestige, icon: "wineglass") {
                            switch store.act({ $0.hostYachtDinner() }) {
                            case .ok(let guests)?: store.show(guests.isEmpty ? "A quiet evening on board: you know nobody to invite yet." : "Aboard: " + guests.joined(separator: ", ") + ".", tone: "good")
                            case .wait?: store.show("Your last dinner was less than four weeks ago.", tone: "warn")
                            case .notEnoughCash?: store.show("Not enough cash for the dinner.", tone: "warn")
                            default: store.show("Not possible.", tone: "warn")
                            }
                        }
                    }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(q.waitWeeks > 0)
                }
                if p.item.id == "e2" {
                    Button("Host a retreat") {
                        pending = PendingAction(title: "Host a retreat on the island?", message: "Paid from your cash. Possible once every three months.", button: "Host",
                                                amount: Luxury.retreatCost(e.homeCurrency), currency: e.homeCurrency, tone: .prestige, icon: "sun.max") {
                        switch store.act({ $0.hostIslandRetreat() }) {
                        case .ok?: store.show("A retreat on the island.", tone: "good")
                        case .wait?: store.show("Your last retreat was less than three months ago.", tone: "warn")
                        case .notEnoughCash?: store.show("Not enough cash for the retreat.", tone: "warn")
                        default: store.show("Not possible right now.", tone: "warn")
                        }
                        }
                    }.buttonStyle(SecondaryButtonStyle(size: .compact))
                    Button("A week off") {
                        switch store.act({ $0.takeWeekOffOnIsland() }) {
                        case .ok?: store.show("You are away next week.", tone: "good")
                        default: store.show("You are already taking next week off.", tone: "warn")
                        }
                    }.buttonStyle(SecondaryButtonStyle(size: .compact))
                }
                if p.use == "museum" && p.until > e.state.week {
                    Text("At the museum until " + GameCalendar.monthString(week: p.until)).popupText(.caption)
                }
            }.padding(.vertical, Theme.Space.s)
        }
    }
}
