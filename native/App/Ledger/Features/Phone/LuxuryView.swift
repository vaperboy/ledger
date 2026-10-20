import SwiftUI
import GameCore
import Businesses
import Simulation

/// Aurum private sales: cars, watches, art, yachts, private jets, homes and estates; and your collection with its uses and estates.
/// Original: the Aurum shop (features/screens/hiring_place_swipe_luxury.js) and the manage sheets of lifestyle.js and estates.js.
/// Flat rows between hairlines; nothing here is a card.
struct LuxuryView: View {
    @EnvironmentObject var store: GameStore
    @State private var tab = "collection"
    @State private var openItem: String? = nil
    @State private var openPiece: Int? = nil
    @State private var pendingSell: Luxury.Piece? = nil
    @State private var companyChoice: Luxury.Item? = nil

    var body: some View {
        if let e = store.engine {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aurum").font(.serifTitle(26)).foregroundStyle(Theme.ivory)
                        Text("Private sales. Paid from your personal cash, delivered, insured and stored for you.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    SectionTabs(items: ["collection"] + Luxury.categories.map { $0.id }, title: { id in id == "collection" ? "Your collection" : Luxury.categories.first(where: { $0.id == id })?.name ?? id },
                                selection: Binding(get: { tab }, set: { tab = $0; openItem = nil })).padding(.horizontal, -Theme.Space.margin)
                    if tab == "collection" { collection(e) } else if let c = Luxury.categories.first(where: { $0.id == tab }) { shop(e, c) }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .navigationTitle("Luxury")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(pendingSell.map { "Sell \($0.item.name)?" } ?? "", isPresented: Binding(get: { pendingSell != nil }, set: { if !$0 { pendingSell = nil } }), titleVisibility: .visible) {
                if let p = pendingSell {
                    Button("Sell for \(store.short(p.value * (1 - Luxury.sellFee)))", role: .destructive) {
                        let v = store.act { $0.sellLuxury(pieceID: p.id) } ?? 0
                        store.show(v > 0 ? "Sold for \(store.short(v))." : "It cannot be sold right now.", tone: v > 0 ? "good" : "warn")
                        pendingSell = nil
                    }
                }
            } message: { Text("You receive the value after \(Int((Luxury.sellFee * 100).rounded()))% selling costs. A gain on a collectible is taxed with your other gains.") }
            .confirmationDialog("Buy through a company", isPresented: Binding(get: { companyChoice != nil }, set: { if !$0 { companyChoice = nil } }), titleVisibility: .visible) {
                if let it = companyChoice {
                    ForEach(e.luxuryCompanies(itemID: it.id), id: \.id) { c in
                        Button("\(c.name) · cash \(store.short(c.cash, in: c))") {
                            switch store.act({ $0.buyLuxury(itemID: it.id, throughCompany: c.id) }) {
                            case .ok?: Haptics.success(); store.show("\(c.name) bought \(it.name).", tone: "good"); tab = "collection"
                            case .notEnoughCash?: store.show("\(c.name) does not have the cash.", tone: "warn")
                            default: store.show("Not possible.", tone: "warn")
                            }
                            companyChoice = nil
                        }
                    }
                }
            } message: { Text("The company pays, writes it down in its books and pays the upkeep, all before company tax. You pay tax on the private use as salary. A company too small for it draws the tax office.") }
        }
    }

    // MARK: Shop

    @ViewBuilder private func shop(_ e: GameEngine, _ c: Luxury.Category) -> some View {
        LedgerSection(title: c.name, trailing: { Text("\(c.items.count) pieces").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(spacing: 0) {
                ForEach(Array(c.items.enumerated()), id: \.element.id) { n, it in
                    VStack(alignment: .leading, spacing: 0) {
                        if n > 0 { Hairline() }
                        Button { openItem = openItem == it.id ? nil : it.id } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(it.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                                    Text(it.detail).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                Text(store.short(it.price)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(e.state.cash >= it.price ? Theme.ivory : Theme.ivoryFaint)
                            }.padding(.vertical, 9).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if openItem == it.id { detail(e, it) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func detail(_ e: GameEngine, _ it: Luxury.Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    switch store.act({ $0.buyLuxury(itemID: it.id) }) {
                    case .ok?: Haptics.success(); store.show("Bought: \(it.name).", tone: "good"); tab = "collection"
                    case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash.", tone: "warn")
                    default: Haptics.warning(); store.show("Not possible.", tone: "warn")
                    }
                }.buttonStyle(GoldButtonStyle()).disabled(e.state.cash < it.price)
                if !e.luxuryCompanies(itemID: it.id).isEmpty {
                    Button("Through a company") { companyChoice = it }.buttonStyle(SmallOutlineButtonStyle())
                }
            }.padding(.vertical, 10)
        }
    }

    // MARK: Collection

    @ViewBuilder private func collection(_ e: GameEngine) -> some View {
        let pieces = e.luxuryPieces
        let income = pieces.reduce(0) { $0 + $1.weeklyIncome }
        KeyFigures(items: [
            .init(label: "Worth today", value: store.short(e.luxuryValue), sub: "in your name"),
            .init(label: "Upkeep", value: store.short(Luxury.upkeepPerMonth(e.state)), sub: "a month"),
            .init(label: "Earns", value: income > 0 ? store.short(income * 52 / 12) : "–", tint: income > 0 ? Theme.gain : Theme.ivory, sub: income > 0 ? "a month, before tax" : ""),
        ])
        if pieces.isEmpty {
            Text("Nothing yet. What you buy is kept here.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
        }
        LedgerSection("Pieces") {
            VStack(spacing: 0) {
                ForEach(Array(pieces.enumerated()), id: \.element.id) { n, p in
                    VStack(alignment: .leading, spacing: 0) {
                        if n > 0 { Hairline() }
                        Button { openPiece = openPiece == p.id ? nil : p.id } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.item.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                                    Text(useLine(e, p)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(store.short(p.value)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                                    Text(Int((p.gain * 100).rounded()) == 0 ? "unchanged" : (p.gain > 0 ? "up " : "down ") + "\(abs(Int((p.gain * 100).rounded())))%")
                                        .font(.system(size: 10.5)).foregroundStyle(Theme.change(p.gain))
                                }
                            }.padding(.vertical, 9).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if openPiece == p.id { manage(e, p) }
                    }
                }
            }
        }
        let perks = perkLines(pieces)
        if !perks.isEmpty {
            LedgerSection("What it does for you") {
                VStack(spacing: 0) { ForEach(Array(perks.enumerated()), id: \.offset) { n, l in FlatRow(label: l.0, value: l.1, rule: n > 0) } }
            }
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
                SectionTabs(items: [""] + uses.map { $0.id }, title: { id in id.isEmpty ? "Keep it" : uses.first { $0.id == id }?.name ?? id },
                            selection: Binding(get: { p.use }, set: { v in store.act { $0.setLuxuryUse(pieceID: p.id, use: v.isEmpty ? nil : v) } })).padding(.horizontal, -Theme.Space.margin)
                if let u = uses.first(where: { $0.id == p.use }) { Text(u.detail).font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 4) }
            }
            if p.item.id == "e5" {
                let open = (e.state.rest["lux"]?.array.first { $0["id"].int == p.id }?["mode"].string ?? "open") != "private"
                SectionTabs(items: [true, false], title: { $0 ? "Open for events" : "Keep it private" },
                            selection: Binding(get: { open }, set: { v in store.act { $0.setCastleOpen(pieceID: p.id, open: v) } })).padding(.horizontal, -Theme.Space.margin)
            }
            HStack(spacing: Theme.Space.m) {
                if p.item.id == "e2" {
                    Button("Host a retreat") {
                        switch store.act({ $0.hostIslandRetreat() }) {
                        case .ok?: store.show("A retreat on the island.", tone: "good")
                        case .wait?: store.show("Your last retreat was less than three months ago.", tone: "warn")
                        case .notEnoughCash?: store.show("Not enough cash for the retreat.", tone: "warn")
                        default: break
                        }
                    }.buttonStyle(SmallOutlineButtonStyle())
                    Button("A week off") {
                        switch store.act({ $0.takeWeekOffOnIsland() }) {
                        case .ok?: store.show("You are away next week.", tone: "good")
                        default: store.show("You are already taking next week off.", tone: "warn")
                        }
                    }.buttonStyle(SmallOutlineButtonStyle())
                }
                if p.use == "museum" && p.until > e.state.week {
                    Text("At the museum until " + GameCalendar.monthString(week: p.until)).font(.caption).foregroundStyle(Theme.ivoryFaint)
                } else {
                    Button("Sell") { pendingSell = p }.buttonStyle(SmallOutlineButtonStyle())
                }
            }.padding(.vertical, 10)
        }
    }
}
