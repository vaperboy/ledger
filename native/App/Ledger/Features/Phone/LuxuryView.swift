import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Luxury phone app (Aurum private sales), drawn as a store: category chips, a grid of product tiles (picture, name, price, an
/// "Owned" badge) and a collection view. Tapping a tile opens the item sheet, where a piece is bought, managed, used or sold.
/// Original: the Aurum shop (features/screens/hiring_place_swipe_luxury.js) and the manage sheets of lifestyle.js and estates.js.
struct LuxuryView: View {
    /// Which item sheet is open: a shop item to buy, or an owned piece to manage.
    enum LuxurySheet: Identifiable, Hashable {
        case item(String)
        case piece(Int)
        var id: String {
            switch self {
            case .item(let s): return "item-" + s
            case .piece(let n): return "piece-\(n)"
            }
        }
    }

    @EnvironmentObject var store: GameStore
    @State private var tab = "collection"
    @State private var sheet: LuxurySheet? = nil
    @State private var pendingSell: Luxury.Piece? = nil
    @State private var companyChoice: Luxury.Item? = nil
    @State private var pending: PendingAction? = nil

    private let columns: [GridItem] = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        if let e = store.engine {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    storeHeader(e)
                    chips
                    if tab == "collection" { collection(e) } else if let c = Luxury.categories.first(where: { $0.id == tab }) { shop(e, c) }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .outsideScreen()
            .accessibilityIdentifier("luxury-app")
            .sheet(item: $sheet) { (s: LuxurySheet) in sheetContent(e, s) }
        }
    }

    // MARK: Store front

    private func storeHeader(_ e: GameEngine) -> some View {
        HStack(alignment: .center, spacing: 12) {
            OutsideBack()
            VStack(alignment: .leading, spacing: 1) {
                Text("AURUM").font(.system(size: 10.5, weight: .semibold)).tracking(3).foregroundStyle(Theme.gold)
                Text("Private sales").font(.serifTitle(26)).foregroundStyle(Theme.ivory).accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("Your cash").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                Text(store.short(max(0, e.state.cash))).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.ivory)
            }
        }
    }

    private var chips: some View {
        let ids: [String] = ["collection"] + Luxury.categories.map { $0.id }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ids, id: \.self) { id in chip(id) }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ id: String) -> some View {
        let on: Bool = tab == id
        let name: String = id == "collection" ? "Your collection" : (Luxury.categories.first(where: { $0.id == id })?.name ?? id)
        return Button { tab = id } label: {
            Text(name).font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.gold : Theme.ivoryMuted)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(on ? Theme.goldSelected : Color.clear))
                .overlay(Capsule().strokeBorder(on ? Theme.gold : Theme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Tiles

    private func ownedCount(_ e: GameEngine, _ id: String) -> Int { e.luxuryPieces.filter { $0.item.id == id }.count }

    @ViewBuilder private func shop(_ e: GameEngine, _ c: Luxury.Category) -> some View {
        HStack {
            Text(c.name.uppercased()).capsLabel()
            Spacer()
            Text("\(c.items.count) pieces").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(c.items, id: \.id) { (it: Luxury.Item) in tile(e, it) }
        }
    }

    private func tile(_ e: GameEngine, _ it: Luxury.Item) -> some View {
        let owned: Int = ownedCount(e, it.id)
        let afford: Bool = e.state.cash >= it.price
        return Button { sheet = .item(it.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ThumbnailView(kind: .luxury, key: it.id, size: 96, shape: .square)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surfaceTable))
                    if owned > 0 { ownedBadge(owned) }
                }
                Text(it.name).font(.serifTitle(15)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                HStack(alignment: .firstTextBaseline) {
                    Text(store.short(it.price)).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(afford ? Theme.gold : Theme.ivoryFaint)
                    Spacer(minLength: 4)
                    if !afford { Text("Out of reach").font(.system(size: 10)).foregroundStyle(Theme.ivoryFaint) }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(it.name + ", " + store.short(it.price) + (owned > 0 ? ", owned" : ""))
    }

    private func ownedBadge(_ n: Int) -> some View {
        Text(n > 1 ? "OWNED ×\(n)" : "OWNED").font(.system(size: 9, weight: .bold)).tracking(0.8)
            .foregroundStyle(Theme.page)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Theme.gold))
            .padding(6)
    }

    // MARK: Collection

    @ViewBuilder private func collection(_ e: GameEngine) -> some View {
        let pieces = e.luxuryPieces
        let income = pieces.reduce(0) { $0 + $1.weeklyIncome }
        FigureCard(items: [
            .init(label: "Worth today", value: store.short(e.luxuryValue), sub: "in your name"),
            .init(label: "Upkeep", value: store.short(Luxury.upkeepPerMonth(e.state)), sub: "a month"),
            .init(label: "Earns", value: income > 0 ? store.short(income * 52 / 12) : "–", tint: income > 0 ? Theme.gain : Theme.ivory, sub: income > 0 ? "a month, before tax" : ""),
        ])
        if pieces.isEmpty {
            NoteCard(text: "Nothing yet. What you buy is kept here, with its upkeep and what it earns. Cash for a purchase: \(store.short(max(0, e.state.cash))). Pick a category above.", glyph: Glyph.luxury)
        } else {
            HStack {
                Text("PIECES").capsLabel()
                Spacer()
                Text("tap to manage").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(pieces, id: \.id) { (p: Luxury.Piece) in pieceTile(p) }
            }
        }
        let perks = perkLines(pieces)
        if !perks.isEmpty {
            CardSection("What it does for you") {
                VStack(spacing: 0) { ForEach(Array(perks.enumerated()), id: \.offset) { n, l in FlatRow(label: l.0, value: l.1, rule: n > 0) } }
            }
        }
    }

    private func pieceTile(_ p: Luxury.Piece) -> some View {
        let pct: Int = Int((p.gain * 100).rounded())
        let change: String = pct == 0 ? "unchanged" : (p.gain > 0 ? "up " : "down ") + "\(abs(pct))%"
        return Button { sheet = .piece(p.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailView(kind: .luxury, key: p.item.id, size: 96, shape: .square)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surfaceTable))
                Text(p.item.name).font(.serifTitle(15)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                HStack(alignment: .firstTextBaseline) {
                    Text(store.short(p.value)).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Spacer(minLength: 4)
                    Text(change).font(.system(size: 10.5)).foregroundStyle(Theme.change(p.gain))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Item sheet

    @ViewBuilder private func sheetContent(_ e: GameEngine, _ s: LuxurySheet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                sheetBody(e, s)
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 30)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.page.ignoresSafeArea())
        .presentationDetents([.large])
        .confirmAction($pending)
        .confirmationDialog(pendingSell.map { "Sell \($0.item.name)?" } ?? "", isPresented: Binding(get: { pendingSell != nil }, set: { if !$0 { pendingSell = nil } }), titleVisibility: .visible) {
            if let p = pendingSell {
                Button("Sell for \(store.short(p.value * (1 - Luxury.sellFee)))", role: .destructive) {
                    let v = store.act { $0.sellLuxury(pieceID: p.id) } ?? 0
                    store.show(v > 0 ? "Sold for \(store.short(v))." : "It cannot be sold right now.", tone: v > 0 ? "good" : "warn")
                    pendingSell = nil
                    if v > 0 { sheet = nil }
                }
            }
        } message: { Text("You receive the value after \(Int((Luxury.sellFee * 100).rounded()))% selling costs. A gain on a collectible is taxed with your other gains.") }
        .confirmationDialog("Buy through a company", isPresented: Binding(get: { companyChoice != nil }, set: { if !$0 { companyChoice = nil } }), titleVisibility: .visible) {
            if let it = companyChoice {
                ForEach(e.luxuryCompanies(itemID: it.id), id: \.id) { c in
                    Button("\(c.name) · cash \(store.short(c.cash, in: c))") {
                        switch store.act({ $0.buyLuxury(itemID: it.id, throughCompany: c.id) }) {
                        case .ok?: Haptics.success(); store.show("\(c.name) bought \(it.name).", tone: "good"); tab = "collection"; sheet = nil
                        case .notEnoughCash?: store.show("\(c.name) does not have the cash.", tone: "warn")
                        default: store.show("Not possible.", tone: "warn")
                        }
                        companyChoice = nil
                    }
                }
            }
        } message: { Text("The company pays, writes it down in its books and pays the upkeep, all before company tax. You pay tax on the private use as salary. A company too small for it draws the tax office.") }
    }

    @ViewBuilder private func sheetBody(_ e: GameEngine, _ s: LuxurySheet) -> some View {
        switch s {
        case .item(let id):
            if let it = Luxury.categories.flatMap({ $0.items }).first(where: { $0.id == id }) {
                sheetTitle(it.name, it.detail.tidyMoney, store.short(it.price))
                detail(e, it)
            }
        case .piece(let pid):
            if let p = e.luxuryPieces.first(where: { $0.id == pid }) {
                sheetTitle(p.item.name, useLine(e, p), store.short(p.value))
                manage(e, p)
            }
        }
    }

    private func sheetTitle(_ name: String, _ note: String, _ price: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.serifTitle(24)).foregroundStyle(Theme.ivory).accessibilityAddTraits(.isHeader)
                Text(note).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(price).font(.serifTitle(22)).foregroundStyle(Theme.gold).monospacedDigit()
        }
    }

    /// The picture (or the house icon until art arrives) at the top of an item's detail. Always the same 72 pt square, so nothing shifts.
    private func detailThumb(_ it: Luxury.Item) -> some View {
        HStack {
            ThumbnailView(kind: .luxury, key: it.id, size: 72, shape: .square)
            Spacer(minLength: 0)
        }
        .frame(height: 72)
        .padding(.vertical, 8)
    }

    @ViewBuilder private func detail(_ e: GameEngine, _ it: Luxury.Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailThumb(it)
            FlatRow(label: "Upkeep, insurance and storage", value: store.short(it.monthlyUpkeep) + " a month")
            FlatRow(label: "Value over time", value: it.trend, tint: it.growth > 0 ? Theme.gain : it.growth < -0.06 ? Theme.loss : Theme.ivory)
            FlatRow(label: "If you sell", value: "\(Int((Luxury.sellFee * 100).rounded()))% in selling costs")
            if let est = Luxury.estateInfo(it.id) {
                FlatRow(label: est.what, value: "about " + store.short(it.price * est.yearly / 12) + " a month")
                FlatRow(label: "What it does", value: est.does)
                FlatRow(label: "The bank lends on it", value: store.short(it.price * 0.5))
            }
            HStack(spacing: Theme.Space.m) {
                Button(e.state.cash < it.price ? "Your cash is \(store.short(max(0, e.state.cash)))" : "Purchase") {
                    pending = PendingAction(title: "Buy \(it.name)?",
                                            message: "\(store.money(it.price)) from your own cash, then about \(store.short(it.monthlyUpkeep)) a month for upkeep, insurance and storage. Selling later costs \(Int((Luxury.sellFee * 100).rounded()))%.",
                                            button: "Purchase for \(store.short(it.price))", amount: it.price, currency: e.homeCurrency) {
                        switch store.act({ $0.buyLuxury(itemID: it.id) }) {
                        case .ok?: Haptics.success(); store.show("Bought: \(it.name).", tone: "good"); tab = "collection"; sheet = nil
                        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash.", tone: "warn")
                        default: Haptics.warning(); store.show("Not possible.", tone: "warn")
                        }
                    }
                }.buttonStyle(QuietButtonStyle()).disabled(e.state.cash < it.price)
                if !e.luxuryCompanies(itemID: it.id).isEmpty {
                    Button("Through a company") { companyChoice = it }.buttonStyle(GreyOutlineButtonStyle())
                }
            }.padding(.vertical, 10)
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

    private func perkLines(_ pieces: [Luxury.Piece]) -> [(String, String)] {
        var out: [(String, String)] = []
        if pieces.contains(where: { $0.item.category == "homes" && $0.companyID == 0 && $0.use != "rent" }) { out.append(("A home of your own", "A place to recover from long weeks")) }
        if pieces.contains(where: { $0.item.category == "jets" }) { out.append(("Your own jet", "You fly in to meetings yourself")) }
        if pieces.contains(where: { $0.item.category == "yachts" }) { out.append(("A yacht", "Dinners on board warm the people you know")) }
        return out
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
                Text("Use").capsLabel(Theme.ivoryFaint).padding(.top, 8)
                SegmentedPill(items: [""] + uses.map { $0.id }, title: { id in id.isEmpty ? "Keep it" : uses.first { $0.id == id }?.name ?? id },
                            selection: Binding(get: { p.use }, set: { v in
                                if store.act({ $0.setLuxuryUse(pieceID: p.id, use: v.isEmpty ? nil : v) }) != nil { store.saved(v.isEmpty ? "\(p.item.name) is kept for yourself." : "\(p.item.name): \(uses.first { $0.id == v }?.name.lowercased() ?? v).") } }))
                if let u = uses.first(where: { $0.id == p.use }) { Text(u.detail.tidyMoney).font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 4) }
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
                    Text("At the museum until " + GameCalendar.monthString(week: p.until)).font(.caption).foregroundStyle(Theme.ivoryMuted)
                } else {
                    Button("Sell for \(store.short(p.value * (1 - Luxury.sellFee)))") { pendingSell = p }.buttonStyle(GreyOutlineButtonStyle())
                }
            }.padding(.vertical, 10)
        }
    }
}
