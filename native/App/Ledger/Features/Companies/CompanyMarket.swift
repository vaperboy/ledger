import SwiftUI
import Charts
import GameCore
import Businesses
import Countries
import Simulation

/// The market around one company, inside the Market app: where you stand (share over time and against the named rivals, drawn only when
/// an analyst measures the market) and the named rivals as a ranked table. Pricing has its own screen (`CompanyPricing`).
struct CompanyMarket: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var rival: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            position
            rivals
        }
        .sheet(item: rivalBinding) { r in
            RivalSheet(engine: engine, companyID: company.id, rivalID: r.id)
        }
    }

    private struct RivalID: Identifiable { var id: Int }

    private var rivalBinding: Binding<RivalID?> {
        Binding<RivalID?>(get: { rival.map { RivalID(id: $0) } }, set: { rival = $0?.id })
    }

    // MARK: Position

    /// One bar of the "against the field" chart.
    private struct FieldBar: Identifiable {
        var id: String
        var name: String
        var percent: Double
        var text: String
        var mine: Bool
    }

    private struct SharePoint: Identifiable { var id: Int; var share: Double }

    @ViewBuilder private var position: some View {
        if let row = engine.marketRows().first(where: { $0.companyNames.contains(company.name) }) {
            let detail: MarketDetail? = engine.marketDetail(key: row.id)
            shareHero(row, detail)
            fieldBlock(row, detail)
        } else {
            Card(padding: 12, radius: Theme.Radius.row) {
                Text("The market map fills in once the business has opened.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func levelWords(_ row: MarketRow) -> String {
        switch row.level {
        case .feeling: return "Your own guess"
        case .dataAnalyst: return "Your data analyst's estimate"
        default: return "Measured by your market analyst"
        }
    }

    private func shareHero(_ row: MarketRow, _ detail: MarketDetail?) -> some View {
        let history: [Double] = detail?.history ?? []
        let measured: Bool = row.level.canDrawShareGraph
        let moved: Double? = history.count >= 2 ? (history[history.count - 1] - history[history.count - 2]) : nil
        let changeText: String = moved.map { String(format: "%+.1f points on last month", $0) } ?? "Monthly points appear as months close"
        let changeTint: Color = (moved ?? 0) < 0 ? Theme.loss : ((moved ?? 0) > 0 ? Theme.gain : Theme.ivoryFaint)
        return NavigationLink { MarketDetailView(marketKey: row.id) } label: {
            Card(padding: 14, radius: Theme.Radius.hero) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        IconCircle(glyph: Glyph.stats, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                            Text(levelWords(row)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer(minLength: 6)
                        MoreChevron()
                    }
                    Text(row.shareText).font(.serifTitle(34)).foregroundStyle(Theme.gold).lineLimit(1).minimumScaleFactor(0.6)
                    // Without an analyst the share is a guess in words: no graph and no exact points.
                    if measured {
                        Text(changeText).font(.system(size: 11.5)).foregroundStyle(changeTint)
                        shareChart(history)
                    }
                }
                .contentShape(Rectangle())
            }
        }.buttonStyle(PressableStyle())
    }

    @ViewBuilder private func shareChart(_ history: [Double]) -> some View {
        if history.count >= 2 {
            let pts: [SharePoint] = history.enumerated().map { (i: Int, v: Double) in SharePoint(id: i, share: v) }
            Chart(pts) { (p: SharePoint) in
                AreaMark(x: .value("Month", p.id), y: .value("Share", p.share))
                    .foregroundStyle(Theme.gold.opacity(0.12)).interpolationMethod(.monotone)
                LineMark(x: .value("Month", p.id), y: .value("Share", p.share))
                    .foregroundStyle(Theme.gold).lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { (v: AxisValue) in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                    AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.0f%%", d)).font(.system(size: 9.5)).foregroundStyle(Theme.ivoryFaint) } }
                }
            }
            .frame(height: 96)
        } else {
            Text("The share line starts after the first month of trading.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    private func fieldBars(_ detail: MarketDetail?, _ shareText: String) -> [FieldBar] {
        var bars: [FieldBar] = []
        if let mine = detail?.history.last { bars.append(FieldBar(id: "me", name: company.name, percent: mine, text: shareText, mine: true)) }
        for r in engine.rivalRows(company) {
            guard let e = r.share else { continue }
            bars.append(FieldBar(id: "r\(r.id)", name: r.rival.name, percent: e.center * 100, text: MarketMap.text(e), mine: false))
        }
        return bars.sorted { $0.percent > $1.percent }
    }

    @ViewBuilder private func fieldBlock(_ row: MarketRow, _ detail: MarketDetail?) -> some View {
        let bars: [FieldBar] = fieldBars(detail, row.shareText)
        if row.level.canDrawShareGraph, bars.count >= 2 {
            MoreBlock(title: "Against the field", trailing: {
                Text("\(max(0, bars.count - 1)) rivals sized").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                fieldChart(bars)
            }
        }
    }

    private func fieldChart(_ bars: [FieldBar]) -> some View {
        Chart(bars) { (b: FieldBar) in
            BarMark(x: .value("Share", b.percent), y: .value("Name", b.name), height: .fixed(14))
                .foregroundStyle(b.mine ? Theme.gold : Theme.ivoryDim)
                .cornerRadius(3)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(b.text).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(b.mine ? Theme.gold : Theme.ivoryMuted)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { (_: AxisValue) in
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted)
            }
        }
        .chartXScale(range: .plotDimension(endPadding: 56))
        .frame(height: CGFloat(bars.count) * 30 + 8)
    }

    // MARK: Rivals

    private var rivals: some View {
        let rows: [RivalRow] = engine.rivalRows(company).sorted { ($0.share?.center ?? -1) > ($1.share?.center ?? -1) }
        let cols: [TableColumn] = [TableColumn(title: "Rival"), TableColumn(title: "Share", width: 78), TableColumn(title: "Price", width: 60)]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Named rivals").capsLabel()
                Spacer()
                Text("\(rows.count) near you").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }.padding(.horizontal, 2)
            if rows.isEmpty {
                Card(padding: 12, radius: Theme.Radius.row) {
                    Text("Rivals appear once the business has opened.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                }
            } else {
                SharpTable {
                    TableHeader(columns: cols)
                    ForEach(rows, id: \.id) { (r: RivalRow) in rivalRow(r, cols) }
                }
            }
        }
    }

    private func rivalRow(_ r: RivalRow, _ cols: [TableColumn]) -> some View {
        let name: String = r.rival.name + (r.rival.forSale ? " · for sale" : "")
        let discountText: String = r.rival.discountPercent.map { " · \($0)% off" } ?? ""
        let marketingText: String = r.rival.marketing ? " · marketing" : ""
        let note: String = "\(r.sizeWord)\(discountText)\(marketingText)"
        let shareText: String = r.share.map { MarketMap.text($0) } ?? r.feel
        let same: Bool = abs(r.priceGap) < 0.03
        let gapPct: Int = Int((abs(r.priceGap) * 100).rounded())
        let gapText: String = same ? "Same" : (r.priceGap > 0 ? "+" : "-") + "\(gapPct)%"
        let gapTint: Color = r.priceGap < -0.03 ? Theme.caution : Theme.ivoryMuted
        let logo = ThumbSpec(kind: .logo, key: "rival|co\(company.id)|\(r.rival.id)", glyph: Glyph.person, initials: r.rival.name, shape: .square)
        return TableRow(columns: cols, title: name, note: note, values: [shareText, gapText], valueTints: [Theme.ivory, gapTint], thumb: logo) { rival = r.id }
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
                    content(e, co, d)
                } else {
                    Text("This rival is gone.").foregroundStyle(Theme.ivoryMuted).padding()
                }
            }
            .ledgerBackground()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: Binding(get: { pendingPrice.map { PriceID(price: $0) } }, set: { pendingPrice = $0?.price })) { p in
                AcquisitionSheet(companyID: companyID, rivalID: rivalID, price: p.price) { kind in
                    switch kind {
                    case .own: pendingPrice = nil; buy(p.price)
                    case .branch: absorb(p.price, .branch)
                    case .merge: absorb(p.price, .merge)
                    case .shut: absorb(p.price, .shut)
                    case .franchiseOldOwner: absorb(p.price, .franchiseOldOwner)
                    case .franchiseNewOwner: absorb(p.price, .franchiseNewOwner)
                    case .ownBank: buyWithBank(p.price)
                    }
                }
            }
        }
    }


    @ViewBuilder private func content(_ e: GameEngine, _ co: Company, _ d: RivalDetail) -> some View {
        let cur: Currency = e.currency(for: co)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            header(d)
            factsSection(d)
            ownerSection(d)
            groupSection(d)
            reviewsSection(d)
            HostingSection(engine: e, onlyRival: rivalID)
            cutSection(e, d)
            actionsSection(e, co, d, cur)
        }
        .padding(.horizontal, Theme.Space.margin).padding(.vertical, Theme.Space.m)
    }

    @ViewBuilder private func header(_ d: RivalDetail) -> some View {
            MoreHeader(glyph: Glyph.person, title: d.rival.name,
                       thumb: ThumbSpec(kind: .logo, key: "rival|co\(companyID)|\(rivalID)", glyph: Glyph.person, initials: d.rival.name, shape: .square),
                       blurb: "Owner \(d.rival.owner) · \(Rivals.relationshipWord(d.rival.relationship))" + (d.rival.forSale ? " · open to offers" : ""))
    }

    @ViewBuilder private func factsSection(_ d: RivalDetail) -> some View {
            MoreBlock(d.analyst.map { "\($0), your analyst" } ?? "Your feeling") {
                VStack(spacing: 0) {
                    ForEach(Array(d.facts.enumerated()), id: \.element.id) { n, f in
                        if n > 0 { CardLine() }
                        HStack { Text(f.label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted); Spacer(); Text(f.value).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory) }.padding(.vertical, 7)
                    }
                }
            }
    }

    @ViewBuilder private func ownerSection(_ d: RivalDetail) -> some View {
            MoreBlock("The owner") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(d.moodWord) · \(d.temperament)").font(.system(size: 13)).foregroundStyle(Theme.ivory)
                    Text(d.nextMove).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(d.rival.memory.prefix(6).enumerated()), id: \.offset) { _, m in
                        CardLine()
                        HStack(alignment: .top) {
                            Circle().fill(m.change > 0 ? Theme.gain : m.change < 0 ? Theme.loss : Theme.ivoryFaint).frame(width: 6, height: 6).padding(.top, 6)
                            Text(m.text.tidyMoney).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                        }
                    }
                }
            }
    }

    @ViewBuilder private func groupSection(_ d: RivalDetail) -> some View {
            if let g = d.group {
                MoreBlock("Group behind it") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(g.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Text("\(g.strategyName): \(g.strategyText)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        Text("\(g.branches) sites · cash \(g.cashWord.lowercased()) · debt \(g.debtWord.lowercased())" + (g.inTrouble ? " · in money trouble" : "")).font(.system(size: 11.5)).foregroundStyle(g.inTrouble ? Theme.caution : Theme.ivoryFaint)
                    }
                }
            }
    }

    @ViewBuilder private func reviewsSection(_ d: RivalDetail) -> some View {
            MoreBlock(title: "Reviews", trailing: { Text(String(format: "%.1f ★ · %d", d.reviewRating, d.reviewCount)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(d.reviews) { r in
                        Text("\(String(repeating: "★", count: r.stars)) \(r.text)").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
    }

    @ViewBuilder private func cutSection(_ e: GameEngine, _ d: RivalDetail) -> some View {
            if let cut = e.rivalPriceCut(companyID: companyID, rivalID: rivalID), cut.answered == nil {
                MoreBlock("\(d.rival.name) cut prices \(cut.pct)%") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Some of your customers are trying them. It runs until about week \(cut.end).").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                        Button("Match their price") { answerCut(.match) }.buttonStyle(TinyButtonStyle(tint: Theme.gold))
                        Button("Hold prices, sell quality") { answerCut(.quality) }.buttonStyle(TinyButtonStyle(tint: Theme.gold))
                        Button("Add a cheap second brand") { answerCut(.brand) }.buttonStyle(TinyButtonStyle(tint: Theme.gold))
                    }
                }
            } else if let cut = e.rivalPriceCut(companyID: companyID, rivalID: rivalID), let answer = cut.answered {
                Text("You answered their price cut: \(answer).").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            }
    }

    @ViewBuilder private func actionsSection(_ e: GameEngine, _ co: Company, _ d: RivalDetail, _ cur: Currency) -> some View {
            MoreBlock("What you can do") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Meet the owner · " + cur.tidyShort(cur.scaledPrice(4000))) {
                        let r = store.act { $0.meetRival(companyID: companyID, rivalID: rivalID) }
                        switch r {
                        case .wait?: store.show("You met recently. Give it a few weeks.", tone: "warn")
                        case .cash?: store.show("Not enough cash for the lunch.", tone: "warn")
                        default: Haptics.success(); store.show("Lunch with \(d.rival.owner). The relationship is warmer.", tone: "good")
                        }
                    }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
                    CardLine()
                    let value = e.rivalValue(companyID: companyID, rivalID: rivalID)
                    Text("Offer to buy · worth about \(cur.tidyShort(value))").capsLabel(Theme.ivoryFaint)
                    HStack {
                        Slider(value: $offer, in: 0.8...3, step: 0.05).tint(Theme.gold)
                        Text(cur.tidyShort(value * offer)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 74, alignment: .trailing)
                    }
                    Text("Plus about \(cur.tidyShort(e.rivalStartupMoney(companyID: companyID, rivalID: rivalID))) to set the business up as your own.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    Button("Make the offer") { makeOffer(multiple: offer) }.buttonStyle(TinyButtonStyle())
                    if let reply { Text(reply).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true) }
                    if let counter { Button("Accept their price · " + cur.tidyShort(counter)) { pendingPrice = counter }.buttonStyle(TinyButtonStyle(tint: Theme.gold)) }
                    CardLine()
                    if co.value("docs")["fran"]["st"].string == "ok" {
                        Button("Open a new site beside them") { openSite() }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
                    } else {
                        Text("A new site beside a rival needs your franchise papers (Chain section).").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
    }

    private struct PriceID: Identifiable { var price: Double; var id: Double { price } }

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
    @State private var pending: PendingAction?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let co = e.state.company(companyID) {
                    let rows = e.rivalRows(co)
                    let cur = e.currency(for: co)
                    let chosen = rows.first { $0.id == rivalID } ?? rows.sorted { $0.rival.size < $1.rival.size }.first
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        MoreHeader(glyph: Glyph.warning, title: "Price war",
                                   blurb: "Your prices drop to the floor for the weeks you choose. The rival loses money every week, and so do you. If it runs out first it closes, and its customers look for somewhere new. Afterwards your prices go back.")
                        MoreBlock("Who") {
                            VStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { n, r in
                                    if n > 0 { CardLine() }
                                    Button { rivalID = r.id } label: {
                                        HStack { Text(r.rival.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory); Spacer()
                                            Text(r.sizeWord).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                                            GlyphView(glyph: chosen?.id == r.id ? Glyph.check : Glyph.ring, size: 16, weight: 1.6, tint: chosen?.id == r.id ? Theme.gold : Theme.ivoryFaint)
                                        }.padding(.vertical, 9).contentShape(Rectangle())
                                    }.buttonStyle(PressableStyle())
                                }
                            }
                        }
                        MoreBlock("How long") {
                            WrapRow { Group { ForEach([6, 10, 14, 20], id: \.self) { w in
                                Button("\(w) weeks") { weeks = w }.buttonStyle(TinyButtonStyle(tint: weeks == w ? Theme.gold : Theme.ivoryFaint)) } } }
                        }
                        if let c = chosen, let est = e.warEstimate(companyID: companyID, rivalID: c.id, weeks: weeks) {
                            MoreBlock("Your chances") {
                                FigureStrip(items: [
                                    .init(label: "They hold out", value: "\(est.holdOutWeeks) wk"),
                                    .init(label: "You hold out", value: est.yourWeeks >= 99 ? "Long" : "\(est.yourWeeks) wk", tint: est.yourWeeks < weeks ? Theme.loss : Theme.ivory),
                                    .init(label: "They close", value: "\(Int((est.odds * 100).rounded()))%"),
                                    .init(label: "To you", value: "\(Int((est.toYou * 100).rounded()))%", sub: "of their customers"),
                                    .init(label: "It costs", value: cur.tidyShort(est.cost), tint: Theme.loss),
                                    .init(label: "Authority", value: est.yourShare >= 0.35 ? "Can fine" : "Low risk", tint: est.yourShare >= 0.35 ? Theme.loss : Theme.ivory),
                                ])
                            }
                            Button("Start a price war against \(c.rival.name)") { askWar(c.rival.name, c.id, est, cur) }.buttonStyle(TinyButtonStyle())
                        }
                    }
                    .padding(.horizontal, Theme.Space.margin).padding(.vertical, Theme.Space.m)
                }
            }
            .ledgerBackground()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmAction($pending)
        }
    }

    private func askWar(_ name: String, _ rid: Int, _ est: Rivals.WarEstimate, _ cur: Currency) {
        let wk: Int = weeks
        let msg: String = "It costs you about \(cur.tidyShort(est.cost)) over \(wk) weeks. The chance that \(name) closes is about \(Int((est.odds * 100).rounded()))%; if you run out first, you lose. A big share of the market can draw a fine for abusing a dominant position."
        pending = PendingAction(title: "Start a price war against \(name)?", message: msg, button: "Start price war", destructive: true) {
            let r = store.act { $0.startPriceWar(companyID: companyID, rivalID: rid, weeks: wk) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else if r != nil { Haptics.success(); store.show("Price war against \(name) started.", tone: "n"); dismiss() }
        }
    }
}

// MARK: The market, for the whole group

/// The "All markets" page of the Market app: your share of every market you are in, the weight of the group in the economy and the groups
/// around you. The reviews of you and your rivals are in the Reviews app. No header of its own: the app draws the title.
struct MarketView: View {
    @EnvironmentObject var store: GameStore
    @State private var showGroups = false

    var body: some View {
        if let e = store.engine {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                shares(e)
                SettingsTable(heading: "Around you") {
                    SettingsTableRow(title: "Groups", note: "The groups around you", value: "See who") { showGroups = true }
                }
            }
            .navigationDestination(isPresented: $showGroups) {
                SettingsPage(title: "Groups", subtitle: "Market", tab: .phone) { groups(e) }
            }
        }
    }

    private func shares(_ e: GameEngine) -> some View {
        let rows = e.marketRows()
        let weight = e.economyWeight()
        let note: String = weight.biggestShare >= 0.35 ? "You hold over a third of a market. A price war now can bring a fine for abusing a dominant position." : "At about a third of a local market, the competition authority starts to watch your pricing."
        return VStack(alignment: .leading, spacing: Theme.Space.l) { MoreBlock("Your share of each market") {
            VStack(spacing: 0) {
                if rows.isEmpty { Text("Your share shows up here once one of your businesses is open.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
                ForEach(Array(rows.enumerated()), id: \.element.id) { n, r in
                    if n > 0 { CardLine() }
                    NavigationLink { MarketDetailView(marketKey: r.id) } label: {
                        HStack {
                            Text(r.label).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Spacer()
                            Text(r.shareText).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.gold)
                            MoreChevron()
                        }.padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(PressableStyle())
                }
            }
        }
            DataAnalystCard()
            MoreBlock("Your weight in the economy") {
                VStack(spacing: 6) {
                    weightRow("Share of all business loans", weight.debt > 0 ? String(format: "%.2f%%", weight.loanShare * 100) : "None")
                    weightRow("Jobs you provide", "\(weight.jobs)")
                    weightRow("Regulator attention", weight.attention)
                    Text(note)
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func weightRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).font(.system(size: 13.5)).foregroundStyle(Theme.ivory); Spacer(); Text(value).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivoryMuted) }
    }

    private func groups(_ e: GameEngine) -> some View {
        let gs = e.rivalGroupsAround()
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            if gs.isEmpty { Text("Groups that compete near you appear once a business is open.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
            ForEach(gs.prefix(12)) { g in
                MoreBlock(title: g.name, card: true, trailing: { Text(g.strategyName).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                    VStack(alignment: .leading, spacing: 6) {
                        ThumbnailView(kind: .logo, key: "group|\(g.id)", size: 40, shape: .square, glyph: Glyph.group, initials: g.name)
                        Text("\(g.owner) · \(g.branches) sites · cash \(g.cashWord.lowercased()) · debt \(g.debtWord.lowercased())" + (g.inTrouble ? " · in money trouble" : ""))
                            .font(.system(size: 12)).foregroundStyle(g.inTrouble ? Theme.caution : Theme.ivoryMuted)
                        Text("Ambition: \(g.ambition)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                        let mine = e.rivalsOfGroup(g.id)
                        NavigationLink { RivalGroupProfileView(groupID: g.id) } label: {
                            HStack(spacing: 4) { Text("Open profile").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold); MoreChevron() }.contentShape(Rectangle())
                        }.buttonStyle(PressableStyle())
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
                    Card(padding: 14, radius: Theme.Radius.hero) {
                        FigureStrip(items: [
                            .init(label: "Your share", value: d.shareText),
                            .init(label: "Market a year", value: d.sizeText ?? "Not known"),
                            .init(label: "Your sales", value: store.short(d.yourSales)),
                        ])
                    }
                    if d.history.count >= 3, d.level.canDrawShareGraph { MoreBlock("Your share, month by month") { Sparkline(values: d.history).frame(height: 54) } }
                    MoreBlock("Who has the market") {
                        VStack(spacing: 0) {
                            ForEach(Array(d.players.enumerated()), id: \.element.id) { n, p in
                                if n > 0 { CardLine() }
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                                        if !p.detail.isEmpty { Text(p.detail.tidyMoney).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
                                    }
                                    Spacer()
                                    Text(p.text.tidyMoney).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                    if d.level == .marketAnalyst {
                        Button("Ask \(d.analystName) for a report now") {
                            let r = store.act { $0.orderMarketReport(marketKey: marketKey) }
                            if case .refused(let why)? = r { store.show(why, tone: "warn") } else { store.show("Report sent to your inbox."); Haptics.success() }
                        }.buttonStyle(TinyButtonStyle(tint: Theme.gold))
                    }
                    if !d.report.isEmpty {
                        MoreBlock(d.analystName.isEmpty ? "Report" : "\(d.analystName)'s report") {
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
        .appScreen(title: detailTitle, subtitle: detailSubtitle, tab: .phone)
    }

    private var detailTitle: String { store.engine?.marketDetail(key: marketKey)?.title.tidyMoney ?? "Market" }
    private var detailSubtitle: String { store.engine?.marketDetail(key: marketKey)?.subtitle ?? "" }
}
