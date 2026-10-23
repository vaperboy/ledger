import SwiftUI
import GameCore
import Businesses
import Simulation

/// The market around one company: your share, price moves (percent changes, discount, price war) and the named rivals.
struct CompanyMarket: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var change = 0.05
    @State private var discount = 15
    @State private var weeks = 2
    @State private var rival: Int?
    @State private var showWar = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            share
            if let info = engine.priceMoves(company) { priceMoves(info) }
            rivals
        }
        .sheet(item: Binding(get: { rival.map { RivalID(id: $0) } }, set: { rival = $0?.id })) { r in
            RivalSheet(engine: engine, companyID: company.id, rivalID: r.id)
        }
        .sheet(isPresented: $showWar) { PriceWarSheet(engine: engine, companyID: company.id) }
    }

    private struct RivalID: Identifiable { var id: Int }

    // MARK: Share

    @ViewBuilder private var share: some View {
        if let row = engine.marketRows().first(where: { $0.companyNames.contains(company.name) }) {
            LedgerSection("Your share") {
                NavigationLink { MarketDetailView(marketKey: row.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Text(row.level == .feeling ? "Your own guess" : row.level == .dataAnalyst ? "Your data analyst's estimate" : "Measured by your market analyst")
                                .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer()
                        Text(row.shareText).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.gold)
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: Price moves

    private func priceMoves(_ info: PriceMovesInfo) -> some View {
        let cur = engine.currency(for: company)
        return LedgerSection("Price moves") {
            VStack(alignment: .leading, spacing: 10) {
                KeyFigures(items: [
                    .init(label: "Your price", value: cur.short(info.yourTicket), sub: String(format: "%+.0f%% vs market", info.againstMarket * 100)),
                    .init(label: "Rivals", value: info.rivalsAverage.map { cur.short($0) } ?? "–"),
                    .init(label: "Margin", value: info.margin.map { String(format: "%.0f%%", $0 * 100) } ?? "–", tint: (info.margin ?? 0) < 0 ? Theme.loss : Theme.ivory),
                ])
                if let war = info.war {
                    Hairline()
                    Text("Price war · \(war.weeksLeft) wk left · \(cur.short(war.loss)) of revenue given up").font(.system(size: 13)).foregroundStyle(Theme.caution)
                    Button("End the price war now") { store.act { $0.endPriceWar(companyID: company.id) }; Haptics.tap() }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                } else {
                    Hairline()
                    Text("Change price").capsLabel(Theme.ivoryFaint)
                    HStack {
                        Slider(value: $change, in: -0.2...0.2, step: 0.01).tint(Theme.gold)
                        Text(String(format: "%+.0f%%", change * 100)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 48, alignment: .trailing)
                    }
                    Button(abs(change) < 0.005 ? "Pick a change" : String(format: "Set %+.0f%% · %@", change * 100, cur.short(info.yourTicket * (1 + change)))) {
                        if let real = store.act({ $0.changePrice(companyID: company.id, byShare: change) }) ?? nil {
                            store.show(String(format: "Prices %+.0f%%.", real * 100)); Haptics.success()
                        }
                    }.buttonStyle(GoldButtonStyle()).disabled(abs(change) < 0.005)
                    if abs(change) >= 0.005, let fc = engine.priceForecast(companyID: company.id, byShare: change) {
                        HStack {
                            Text("Customers: " + fc.text.customers)
                            Spacer()
                            Text("Margin: " + fc.text.margin)
                        }.font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        Text(fc.text.byAnalyst ? "Ranges from your data analyst." : "A gut feeling. A data analyst in your office gives ranges.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    if info.recentCut >= 0.06 { Text("You cut prices lately. Rivals may match you.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
                    Hairline()
                    Text("Discount campaign").capsLabel(Theme.ivoryFaint)
                    if info.discountOptions.isEmpty {
                        Text("Not done in this trade.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                    } else if let pct = info.discountPercent {
                        Text("\(pct)% off · \(info.discountWeeksLeft) wk left").font(.system(size: 13)).foregroundStyle(Theme.ivory)
                        Button("End the discount") { store.act { $0.endDiscount(companyID: company.id) } }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(info.discountOptions, id: \.self) { d in
                                    Button("\(d)%") { discount = d }.buttonStyle(QuietButtonStyle(tint: discount == d ? Theme.gold : Theme.ivoryFaint))
                                }
                                Divider().frame(height: 14)
                                ForEach([1, 2, 4, 6], id: \.self) { w in
                                    Button("\(w) wk") { weeks = w }.buttonStyle(QuietButtonStyle(tint: weeks == w ? Theme.gold : Theme.ivoryFaint))
                                }
                            }
                        }
                        if info.raisedWeeksAgo > 0 {
                            Text("You raised prices \(info.raisedWeeksAgo) wk ago. A sale measured against that price can be fined as misleading.").font(.system(size: 11.5)).foregroundStyle(Theme.caution)
                        }
                        Button("Start \(discount)% off for \(weeks) wk") {
                            let r = store.act { $0.startDiscount(companyID: company.id, percent: min(discount, info.discountOptions.last ?? discount), weeks: weeks) }
                            if case .refused(let why)? = r { store.show(why, tone: "warn") } else { Haptics.success() }
                        }.buttonStyle(GoldButtonStyle())
                    }
                    if !engine.rivalRows(company).isEmpty {
                        Hairline()
                        Button("Start a price war…") { showWar = true }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                    }
                }
            }
        }
    }

    // MARK: Rivals

    private var rivals: some View {
        let rows = engine.rivalRows(company)
        let cur = engine.currency(for: company)
        _ = cur
        return LedgerSection("Rivals") {
            VStack(spacing: 0) {
                if rows.isEmpty { Text("Rivals appear once the business has opened.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
                ForEach(Array(rows.enumerated()), id: \.element.id) { n, r in
                    if n > 0 { Hairline() }
                    Button { rival = r.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.rival.name + (r.rival.forSale ? " · for sale" : "")).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                                Text("\(r.sizeWord) · \(r.share.map { MarketMap.text($0) + " share" } ?? r.feel)" + (r.rival.discountPercent.map { " · \($0)% off" } ?? "") + (r.rival.marketing ? " · marketing" : ""))
                                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                            }
                            Spacer()
                            Text(abs(r.priceGap) < 0.03 ? "Same price" : (r.priceGap > 0 ? "Dearer " : "Cheaper ") + "\(Int((abs(r.priceGap) * 100).rounded()))%")
                                .font(.system(size: 12)).foregroundStyle(r.priceGap < -0.03 ? Theme.caution : Theme.ivoryMuted)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }.padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: One rival

struct RivalSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var engine: GameEngine
    var companyID: Int
    var rivalID: Int
    @State private var offer = 1.2
    @State private var reply: String?
    @State private var counter: Double?
    /// The price the owner agreed to: asks what the business should become before paying.
    @State private var pendingPrice: Double?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let co = e.state.company(companyID), let d = e.rivalDetail(companyID: companyID, rivalID: rivalID) {
                    let cur = e.currency(for: co)
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.rival.name).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                            Text("Owner \(d.rival.owner) · \(Rivals.relationshipWord(d.rival.relationship))" + (d.rival.forSale ? " · open to offers" : "")).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        }
                        LedgerSection(d.analyst.map { "\($0), your analyst" } ?? "Your feeling") {
                            VStack(spacing: 0) {
                                ForEach(Array(d.facts.enumerated()), id: \.element.id) { n, f in
                                    if n > 0 { Hairline() }
                                    HStack { Text(f.label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted); Spacer(); Text(f.value).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory) }.padding(.vertical, 7)
                                }
                            }
                        }
                        LedgerSection("The owner") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(d.moodWord) · \(d.temperament)").font(.system(size: 13)).foregroundStyle(Theme.ivory)
                                Text(d.nextMove).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                                ForEach(Array(d.rival.memory.prefix(6).enumerated()), id: \.offset) { _, m in
                                    Hairline()
                                    HStack(alignment: .top) {
                                        Circle().fill(m.change > 0 ? Theme.gain : m.change < 0 ? Theme.loss : Theme.ivoryFaint).frame(width: 6, height: 6).padding(.top, 6)
                                        Text(m.text).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                                    }
                                }
                            }
                        }
                        if let g = d.group {
                            LedgerSection("Group behind it") {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(g.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                    Text("\(g.strategyName): \(g.strategyText)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                                    Text("\(g.branches) sites · cash \(g.cashWord.lowercased()) · debt \(g.debtWord.lowercased())" + (g.inTrouble ? " · in money trouble" : "")).font(.system(size: 11.5)).foregroundStyle(g.inTrouble ? Theme.caution : Theme.ivoryFaint)
                                }
                            }
                        }
                        LedgerSection(title: "Reviews", trailing: { Text(String(format: "%.1f ★ · %d", d.reviewRating, d.reviewCount)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(d.reviews) { r in
                                    Text("\(String(repeating: "★", count: r.stars)) \(r.text)").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        HostingSection(engine: e, onlyRival: rivalID)
                        if let cut = e.rivalPriceCut(companyID: companyID, rivalID: rivalID), cut.answered == nil {
                            LedgerSection("\(d.rival.name) cut prices \(cut.pct)%") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Some of your customers are trying them. It runs until about week \(cut.end).").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                                    Button("Match their price") { answerCut(.match) }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                                    Button("Hold prices, sell quality") { answerCut(.quality) }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                                    Button("Add a cheap second brand") { answerCut(.brand) }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                                    Text("Doing nothing is also a choice: you lose some customers until the cut ends. You can also buy them out below.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                                }
                            }
                        } else if let cut = e.rivalPriceCut(companyID: companyID, rivalID: rivalID), let answer = cut.answered {
                            Text("You answered their price cut: \(answer).").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        }
                        LedgerSection("What you can do") {
                            VStack(alignment: .leading, spacing: 10) {
                                Button("Meet the owner · " + cur.short(cur.scaledPrice(4000))) {
                                    let r = store.act { $0.meetRival(companyID: companyID, rivalID: rivalID) }
                                    switch r {
                                    case .wait?: store.show("You met recently. Give it a few weeks.", tone: "warn")
                                    case .cash?: store.show("Not enough cash for the lunch.", tone: "warn")
                                    default: Haptics.success()
                                    }
                                }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                                Hairline()
                                let value = e.rivalValue(companyID: companyID, rivalID: rivalID)
                                Text("Offer to buy · worth about \(cur.short(value))").capsLabel(Theme.ivoryFaint)
                                HStack {
                                    Slider(value: $offer, in: 0.8...3, step: 0.05).tint(Theme.gold)
                                    Text(cur.short(value * offer)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 74, alignment: .trailing)
                                }
                                Text("Plus about \(cur.short(e.rivalStartupMoney(companyID: companyID, rivalID: rivalID))) to set the business up as your own.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                                Button("Make the offer") { makeOffer(multiple: offer) }.buttonStyle(GoldButtonStyle())
                                if let reply { Text(reply).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true) }
                                if let counter { Button("Accept their price · " + cur.short(counter)) { pendingPrice = counter }.buttonStyle(QuietButtonStyle(tint: Theme.gold)) }
                                Hairline()
                                if co.value("docs")["fran"]["st"].string == "ok" {
                                    Button("Open a new site beside them") { openSite() }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                                } else {
                                    Text("A new site beside a rival needs your franchise papers (Chain section).").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.margin).padding(.vertical, Theme.Space.m)
                } else {
                    Text("This rival is gone.").foregroundStyle(Theme.ivoryMuted).padding()
                }
            }
            .ledgerBackground()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("What should it become?", isPresented: Binding(get: { pendingPrice != nil }, set: { if !$0 { pendingPrice = nil } }), titleVisibility: .visible) {
                if let p = pendingPrice, let e = store.engine {
                    Button("Its own company") { pendingPrice = nil; buy(p) }
                    Button("Your branch") { absorb(p, .branch) }
                    Button("Merge into your company (extra 8%)") { absorb(p, .merge) }
                    Button("Close it down (extra 12%)") { absorb(p, .shut) }
                    if e.state.company(companyID)?.value("fr")["on"].bool == true {
                        Button("Franchise office, owner stays") { absorb(p, .franchiseOldOwner) }
                        Button("Franchise office, new franchisee") { absorb(p, .franchiseNewOwner) }
                    }
                    if e.ownBank != nil, e.ownBankRoom() >= p * 0.2 { Button("Its own company, 70% from my own bank") { buyWithBank(p) } }
                }
            } message: { Text("A branch carries your name from day one. Merging brings their customers and some staff over; closing removes a rival (a big market share can draw the competition authority).") }
        }
    }

    private func absorb(_ price: Double, _ how: RivalAbsorb.How) {
        pendingPrice = nil
        let r = store.act { $0.absorbRival(companyID: companyID, rivalID: rivalID, price: price, how: how) }
        switch r {
        case .ok(let message, let id, _)?: Haptics.success(); store.show(message, tone: "good"); dismiss(); if let id { store.openCompany(id) }
        case .notEnoughCash?: reply = "Not enough cash for the price and the extra costs."; Haptics.warning()
        case .failed(let why)?: reply = why
        case nil: break
        }
    }

    private func buyWithBank(_ price: Double) {
        pendingPrice = nil
        guard let e = store.engine else { return }
        let amount = min((price * 0.7 / 1000).rounded() * 1000, (e.ownBankRoom() / 1000).rounded(.down) * 1000)
        let r = store.act { $0.buyRivalWithOwnBank(companyID: companyID, rivalID: rivalID, price: price, amount: amount) }
        switch r {
        case .ok(.ok(let id))?: Haptics.success(); store.show("You bought the business with a loan from your bank.", tone: "good"); dismiss(); store.openCompany(id)
        case .ok(.notEnoughCash)?: reply = "Not enough cash for the rest of the price and the set-up."; Haptics.warning()
        case .ok(.failed(let why))?: reply = why
        case .bankCannotLend?: reply = "Your bank cannot lend that much."; Haptics.warning()
        case nil: break
        }
    }

    private func answerCut(_ answer: RivalAbsorb.Counter) {
        let r = store.act { $0.answerPriceCut(companyID: companyID, rivalID: rivalID, answer: answer) }
        switch r {
        case .done(let m)?: Haptics.success(); store.show(m, tone: "good")
        case .alreadyLowest?: store.show("You are already at your lowest price.", tone: "warn")
        case .notEnoughCash?: store.show("Not enough cash.", tone: "warn")
        case .newCompany(let id)?: Haptics.success(); store.show("The second brand is registered. Set it up to open."); dismiss(); store.openCompany(id)
        case .failed(let m)?: store.show(m, tone: "warn")
        case nil: break
        }
    }

    private func openSite() {
        let r = store.act { $0.openBranchNextToRival(companyID: companyID, rivalID: rivalID) }
        switch r {
        case .ok(let id)?: Haptics.success(); store.show("The new site is registered. Set it up to open."); dismiss(); store.openCompany(id)
        case .needsFranchisePapers?: store.show("You need your franchise papers first.", tone: "warn")
        case .notEnoughCash?: store.show("Not enough money to start it.", tone: "warn")
        case .failed(let m)?: store.show(m, tone: "warn")
        case nil: break
        }
    }

    private func makeOffer(multiple: Double) {
        guard let r = store.act({ $0.offerForRival(companyID: companyID, rivalID: rivalID, multiple: multiple) }) ?? nil else { return }
        counter = nil
        switch r {
        case .ignore(let m), .reject(let m): reply = m; Haptics.warning()
        case .counter(let p, let m): reply = m; counter = p
        case .accept(let p, let m): reply = m; pendingPrice = p
        }
    }

    private func buy(_ price: Double) {
        let r = store.act { $0.buyRival(companyID: companyID, rivalID: rivalID, price: price) }
        switch r {
        case .ok(let id)?: Haptics.success(); store.show("You bought the business."); dismiss(); store.openCompany(id)
        case .notEnoughCash?: reply = "Not enough cash for the price and the set-up."; Haptics.warning()
        case .failed(let why)?: reply = why
        case nil: break
        }
    }
}

// MARK: Price war

struct PriceWarSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var engine: GameEngine
    var companyID: Int
    @State private var rivalID: Int?
    @State private var weeks = 10

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let co = e.state.company(companyID) {
                    let rows = e.rivalRows(co)
                    let cur = e.currency(for: co)
                    let chosen = rows.first { $0.id == rivalID } ?? rows.sorted { $0.rival.size < $1.rival.size }.first
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text("Price war").font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                        Text("Your prices drop to the floor for the weeks you choose. The rival loses money every week, and so do you. If it runs out first it closes, and its customers look for somewhere new. Afterwards your prices go back.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                        LedgerSection("Who") {
                            VStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { n, r in
                                    if n > 0 { Hairline() }
                                    Button { rivalID = r.id } label: {
                                        HStack { Text(r.rival.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory); Spacer()
                                            Text(r.sizeWord).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                                            Image(systemName: chosen?.id == r.id ? "checkmark.circle.fill" : "circle").foregroundStyle(chosen?.id == r.id ? Theme.gold : Theme.ivoryFaint)
                                        }.padding(.vertical, 9).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        LedgerSection("How long") {
                            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach([6, 10, 14, 20], id: \.self) { w in
                                Button("\(w) weeks") { weeks = w }.buttonStyle(QuietButtonStyle(tint: weeks == w ? Theme.gold : Theme.ivoryFaint)) } } }
                        }
                        if let c = chosen, let est = e.warEstimate(companyID: companyID, rivalID: c.id, weeks: weeks) {
                            LedgerSection("Your chances") {
                                KeyFigures(items: [
                                    .init(label: "They hold out", value: "\(est.holdOutWeeks) wk"),
                                    .init(label: "You hold out", value: est.yourWeeks >= 99 ? "Long" : "\(est.yourWeeks) wk", tint: est.yourWeeks < weeks ? Theme.loss : Theme.ivory),
                                    .init(label: "They close", value: "\(Int((est.odds * 100).rounded()))%"),
                                    .init(label: "To you", value: "\(Int((est.toYou * 100).rounded()))%", sub: "of their customers"),
                                    .init(label: "It costs", value: cur.short(est.cost), tint: Theme.loss),
                                    .init(label: "Authority", value: est.yourShare >= 0.35 ? "Can fine" : "Low risk", tint: est.yourShare >= 0.35 ? Theme.loss : Theme.ivory),
                                ])
                            }
                            Button("Start a price war against \(c.rival.name)") {
                                let r = store.act { $0.startPriceWar(companyID: companyID, rivalID: c.id, weeks: weeks) }
                                if case .refused(let why)? = r { store.show(why, tone: "warn") } else { Haptics.success(); dismiss() }
                            }.buttonStyle(GoldButtonStyle())
                        }
                    }
                    .padding(.horizontal, Theme.Space.margin).padding(.vertical, Theme.Space.m)
                }
            }
            .ledgerBackground()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: The market, for the whole group

/// Every market you are in, the reviews of you and your rivals market by market, and the groups around you. Opened from the Group tab.
struct MarketView: View {
    @EnvironmentObject var store: GameStore
    enum Part: String, CaseIterable, Hashable { case shares = "Market share", reviews = "Reviews", groups = "Groups" }
    @State private var part: Part = .shares

    var body: some View {
        ScrollView {
            if let e = store.engine {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("Market").font(.serifTitle(28))
                    SectionTabs(items: Part.allCases, title: { $0.rawValue }, selection: $part).padding(.horizontal, -Theme.Space.margin)
                    switch part {
                    case .shares: shares(e)
                    case .reviews: reviews(e)
                    case .groups: groups(e)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
        }
        .ledgerBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shares(_ e: GameEngine) -> some View {
        let rows = e.marketRows()
        let weight = e.economyWeight()
        return VStack(alignment: .leading, spacing: Theme.Space.l) { LedgerSection("Your share of each market") {
            VStack(spacing: 0) {
                if rows.isEmpty { Text("Your share shows up here once one of your businesses is open.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
                ForEach(Array(rows.enumerated()), id: \.element.id) { n, r in
                    if n > 0 { Hairline() }
                    NavigationLink { MarketDetailView(marketKey: r.id) } label: {
                        HStack {
                            Text(r.label).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Spacer()
                            Text(r.shareText).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.gold)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }.padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
            DataAnalystCard()
            LedgerSection("Your weight in the economy") {
                VStack(spacing: 6) {
                    weightRow("Share of all business loans", weight.debt > 0 ? String(format: "%.2f%%", weight.loanShare * 100) : "None")
                    weightRow("Jobs you provide", "\(weight.jobs)")
                    weightRow("Regulator attention", weight.attention)
                    Text(weight.biggestShare >= 0.35 ? "You hold over a third of a market. A price war now can bring a fine for abusing a dominant position."
                         : "At about a third of a local market, the competition authority starts to watch your pricing.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func weightRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).font(.system(size: 13.5)).foregroundStyle(Theme.ivory); Spacer(); Text(value).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivoryMuted) }
    }

    private func reviews(_ e: GameEngine) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            let groups = e.reviewBoard()
            if groups.isEmpty { Text("Reviews of you and your rivals appear once a business is open.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
            ForEach(groups) { g in
                LedgerSection(g.title) {
                    VStack(spacing: 0) {
                        ForEach(Array(g.rows.enumerated()), id: \.element.id) { n, r in
                            if n > 0 { Hairline() }
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name + (r.mine ? " (yours)" : "")).font(.system(size: 13.5)).foregroundStyle(r.mine ? Theme.gold : Theme.ivory).lineLimit(1)
                                    Text(r.rank.map { "Rated \($0) of \(r.of ?? $0)" } ?? "No rating yet").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer()
                                Text(r.count >= Reviews.minimumShown ? String(format: "%.1f ★", r.rating) : "–").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory)
                                Text("\(r.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.ivoryFaint).frame(width: 44, alignment: .trailing)
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private func groups(_ e: GameEngine) -> some View {
        let gs = e.rivalGroupsAround()
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            if gs.isEmpty { Text("Groups that compete near you appear once a business is open.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
            ForEach(gs.prefix(12)) { g in
                LedgerSection(title: g.name, trailing: { Text(g.strategyName).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(g.owner) · \(g.branches) sites · cash \(g.cashWord.lowercased()) · debt \(g.debtWord.lowercased())" + (g.inTrouble ? " · in money trouble" : ""))
                            .font(.system(size: 12)).foregroundStyle(g.inTrouble ? Theme.caution : Theme.ivoryMuted)
                        Text("Ambition: \(g.ambition)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                        let mine = e.rivalsOfGroup(g.id)
                        if !mine.isEmpty { Text("In your markets: " + mine.map { $0.rival.name }.joined(separator: ", ")).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted) }
                        ForEach(Array(g.moves.prefix(3).enumerated()), id: \.offset) { _, m in
                            Text("Week \(m.week): \(m.text)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
            }
        }
    }
}

struct MarketDetailView: View {
    @EnvironmentObject var store: GameStore
    var marketKey: String

    var body: some View {
        ScrollView {
            if let e = store.engine, let d = e.marketDetail(key: marketKey) {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.title).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                        Text(d.subtitle).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    KeyFigures(items: [
                        .init(label: "Your share", value: d.shareText),
                        .init(label: "Market a year", value: d.sizeText ?? "Not known"),
                        .init(label: "Your sales", value: store.short(d.yourSales)),
                    ])
                    if d.history.count >= 3 { LedgerSection("Your share, month by month") { Sparkline(values: d.history).frame(height: 54) } }
                    LedgerSection("Who has the market") {
                        VStack(spacing: 0) {
                            ForEach(Array(d.players.enumerated()), id: \.element.id) { n, p in
                                if n > 0 { Hairline() }
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                                        if !p.detail.isEmpty { Text(p.detail).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
                                    }
                                    Spacer()
                                    Text(p.text).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                    if d.level == .marketAnalyst {
                        Button("Ask \(d.analystName) for a report now") {
                            let r = store.act { $0.orderMarketReport(marketKey: marketKey) }
                            if case .refused(let why)? = r { store.show(why, tone: "warn") } else { store.show("Report sent to your inbox."); Haptics.success() }
                        }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                    }
                    if !d.report.isEmpty {
                        LedgerSection(d.analystName.isEmpty ? "Report" : "\(d.analystName)'s report") {
                            VStack(alignment: .leading, spacing: 5) { ForEach(d.report, id: \.self) { Text($0).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) } }
                        }
                    } else {
                        Text("Without an analyst you only have a feeling about the market.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
            } else {
                Text("You are no longer in this market.").foregroundStyle(Theme.ivoryMuted).padding()
            }
        }
        .ledgerBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
