import SwiftUI
import GameCore
import Businesses
import Simulation

/// The My Vault tab: what the player holds, with value and upkeep, and Sell with the sale price shown before confirming.
struct LuxuryVaultTab: View {
    @EnvironmentObject var store: GameStore
    var onInspect: (Int) -> Void
    var onShowroom: () -> Void
    @State private var selling: Int? = nil
    private var P: OutsidePalette { .luxury }

    var body: some View {
        if let e = store.engine {
            let pieces: [Luxury.Piece] = e.luxuryPieces
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary(e, pieces)
                    if pieces.isEmpty { empty } else { ForEach(pieces, id: \.id) { (p: Luxury.Piece) in row(e, p) } }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 24)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .confirmationDialog(sellTitle(e), isPresented: Binding(get: { selling != nil }, set: { if !$0 { selling = nil } }), titleVisibility: .visible) {
                if let id = selling, let get = e.luxurySellQuote(pieceID: id) {
                    Button("Sell for \(store.short(get))", role: .destructive) { sell(id) }
                }
            } message: {
                if let id = selling, let get = e.luxurySellQuote(pieceID: id) {
                    Text("You receive \(store.money(get)), after \(Int((Luxury.sellFee * 100).rounded()))% selling costs. A gain is taxed with your other gains.")
                }
            }
        }
    }

    private func sellTitle(_ e: GameEngine) -> String {
        guard let id = selling, let p = e.luxuryPieces.first(where: { $0.id == id }) else { return "" }
        return "Sell \(p.item.name)?"
    }

    private func sell(_ id: Int) {
        let v: Double = store.act { $0.sellLuxury(pieceID: id) } ?? 0
        store.show(v > 0 ? "Sold for \(store.short(v))." : "It cannot be sold right now.", tone: v > 0 ? "good" : "warn")
        selling = nil
    }

    private func summary(_ e: GameEngine, _ pieces: [Luxury.Piece]) -> some View {
        let worth: Double = pieces.reduce(0) { $0 + $1.value }
        return VStack(alignment: .leading, spacing: 14) {
            Text("ASSET PORTFOLIO").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(P.accent)
            Text("My vault").font(.serifTitle(28)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 0) {
                stat("ASSETS HELD", "\(pieces.count)", P.ink)
                stat("PORTFOLIO VALUE", store.short(worth), P.ink)
                stat("UPKEEP / MONTH", store.short(Luxury.upkeepPerMonth(e.state)), P.loss)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.1).foregroundStyle(P.inkFaint).lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            GlyphView(glyph: Glyph.bank, size: 34, weight: 1.3, tint: P.inkDim)
            Text("Your vault is empty").font(.serifTitle(20)).foregroundStyle(P.ink)
            Text("What you buy in the Showroom is kept here, with its value and upkeep.").font(.system(size: 13)).foregroundStyle(P.inkFaint).multilineTextAlignment(.center)
            Button("Open the Showroom", action: onShowroom).buttonStyle(QuietButtonStyle())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func row(_ e: GameEngine, _ p: Luxury.Piece) -> some View {
        let get: Double? = e.luxurySellQuote(pieceID: p.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                LuxuryPhoto(itemID: p.item.id, height: 80).frame(width: 106).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(LuxuryFacts.categoryName(p.item).uppercased()).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(P.accent)
                    Text(p.item.name).font(.serifTitle(18)).foregroundStyle(P.ink).lineLimit(2).multilineTextAlignment(.leading)
                    Text("Value " + store.short(p.value)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(P.ink)
                    Text(store.short(p.item.monthlyUpkeep * (p.paid / max(1, p.item.price))) + " / month upkeep").font(.system(size: 11, design: .monospaced)).foregroundStyle(P.loss)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button("Inspect") { onInspect(p.id) }.buttonStyle(QuietButtonStyle())
                Button(get.map { "Sell for " + store.short($0) } ?? "Not for sale now") { selling = p.id }
                    .buttonStyle(QuietButtonStyle(tint: P.inkSoft)).disabled(get == nil)
                    .accessibilityIdentifier("luxury-sell")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.line, lineWidth: 1))
    }
}

/// Inspect: how the piece was bought, its upkeep, and what can be done with it (use, lend, host).
struct LuxuryInspectSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var pieceID: Int
    @State private var pending: PendingAction? = nil
    private var P: OutsidePalette { .luxury }

    var body: some View {
        if let e = store.engine, let p = e.luxuryPieces.first(where: { $0.id == pieceID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LuxuryItemHead(item: p.item) { dismiss() }
                    Text(useLine(e, p)).font(.system(size: 12.5)).foregroundStyle(P.inkFaint).padding(.horizontal, 18)
                    manage(e, p).padding(.horizontal, 18)
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(P.ground.ignoresSafeArea())
            .environment(\.outsidePalette, P)
            .preferredColorScheme(.dark)
            .presentationDetents([.fraction(0.9)])
            .confirmAction($pending)
        }
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
                Text("Use").capsLabel(P.inkFaint).padding(.top, 8)
                SegmentedPill(items: [""] + uses.map { $0.id }, title: { id in id.isEmpty ? "Keep it" : uses.first { $0.id == id }?.name ?? id },
                            selection: Binding(get: { p.use }, set: { v in
                                if store.act({ $0.setLuxuryUse(pieceID: p.id, use: v.isEmpty ? nil : v) }) != nil { store.saved(v.isEmpty ? "\(p.item.name) is kept for yourself." : "\(p.item.name): \(uses.first { $0.id == v }?.name.lowercased() ?? v).") } }))
                if let u = uses.first(where: { $0.id == p.use }) { Text(u.detail.tidyMoney).font(.caption2).foregroundStyle(P.inkFaint).padding(.top, 4) }
            }
            if p.item.id == "e5" {
                let open = (e.state.rest["lux"]?.array.first { $0["id"].int == p.id }?["mode"].string ?? "open") != "private"
                SegmentedPill(items: [true, false], title: { $0 ? "Open for events" : "Keep it private" },
                            selection: Binding(get: { open }, set: { v in
                                if store.act({ $0.setCastleOpen(pieceID: p.id, open: v) }) != nil { store.saved(v ? "the castle is open for events." : "the castle is private.") } }))
            }
            LendPieceSection(engine: e, piece: p)
            HStack(spacing: Theme.Space.m) {
                if p.item.category == "yachts", p.companyID == 0, let q = e.yachtDinnerQuote() {
                    Button(q.waitWeeks > 0 ? "Dinner in \(q.waitWeeks) wk" : "Host a dinner") {
                        pending = PendingAction(title: "Host a dinner on board?",
                                                message: "Costs \(store.short(q.cost)) from your cash. Warms the three suppliers you know least. Possible once every four weeks.",
                                                button: "Host for \(store.short(q.cost))") {
                            switch store.act({ $0.hostYachtDinner() }) {
                            case .ok(let guests)?: store.show(guests.isEmpty ? "A quiet evening on board: you know nobody to invite yet." : "Aboard: " + guests.joined(separator: ", ") + ".", tone: "good")
                            case .wait?: store.show("Your last dinner was less than four weeks ago.", tone: "warn")
                            case .notEnoughCash?: store.show("Not enough cash for the dinner.", tone: "warn")
                            default: store.show("Not possible.", tone: "warn")
                            }
                        }
                    }.buttonStyle(GreyOutlineButtonStyle()).disabled(q.waitWeeks > 0)
                }
                if p.item.id == "e2" {
                    Button("Host a retreat") {
                        pending = PendingAction(title: "Host a retreat on the island?", message: "Paid from your cash. Possible once every three months.", button: "Host") {
                        switch store.act({ $0.hostIslandRetreat() }) {
                        case .ok?: store.show("A retreat on the island.", tone: "good")
                        case .wait?: store.show("Your last retreat was less than three months ago.", tone: "warn")
                        case .notEnoughCash?: store.show("Not enough cash for the retreat.", tone: "warn")
                        default: store.show("Not possible right now.", tone: "warn")
                        }
                        }
                    }.buttonStyle(GreyOutlineButtonStyle())
                    Button("A week off") {
                        switch store.act({ $0.takeWeekOffOnIsland() }) {
                        case .ok?: store.show("You are away next week.", tone: "good")
                        default: store.show("You are already taking next week off.", tone: "warn")
                        }
                    }.buttonStyle(GreyOutlineButtonStyle())
                }
                if p.use == "museum" && p.until > e.state.week {
                    Text("At the museum until " + GameCalendar.monthString(week: p.until)).font(.caption).foregroundStyle(P.inkSoft)
                }
            }.padding(.vertical, 10)
        }
    }
}
