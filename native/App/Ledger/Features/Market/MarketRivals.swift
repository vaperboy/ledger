import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Rivals: every rival business in your markets and the rival groups around you, searchable, with a For sale and a Watching filter.
/// A rival opens its profile (history, owner, the offer); a group opens its own profile.
struct MarketRivalsPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var open: (MarketRoute) -> Void
    @State private var query = ""
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Hashable { case all = "All", forSale = "For sale", watching = "Watching", groups = "Groups", players = "Players" }

    var body: some View {
        if let e = store.engine {
            let all: [MarketUI.RivalItem] = store.memo("mk.rivals") { MarketData.rivals($0) } ?? []
            let groups: [MarketUI.GroupItem] = store.memo("mk.groups") { MarketData.groups($0) } ?? []
            let watched: Set<String> = Set(all.filter { (r: MarketUI.RivalItem) -> Bool in r.watched }.map { (r: MarketUI.RivalItem) -> String in r.id })
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                hero(all, groups, e)
                LedgerField(placeholder: "Search", text: $query, identifier: "market-rival-search")
                SegmentedPill(items: Filter.allCases, title: { (f: Filter) -> String in f.rawValue }, selection: $filter,
                              identifier: { (f: Filter) -> String in "market-rivals-\(f.rawValue)" })
                if filter == .players {
                    PlayerCompanyOffers()
                } else if filter == .groups {
                    groupList(groups.filter { (g: MarketUI.GroupItem) -> Bool in matches(g.name + " " + g.owner + " " + g.countries.joined(separator: " ")) })
                } else {
                    rivalList(shown(all, watched), watched)
                }
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        let q: String = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func shown(_ all: [MarketUI.RivalItem], _ watched: Set<String>) -> [MarketUI.RivalItem] {
        all.filter { (r: MarketUI.RivalItem) -> Bool in
            switch filter {
            case .all, .groups, .players: break
            case .forSale: if !r.forSale { return false }
            case .watching: if !watched.contains(r.id) { return false }
            }
            return matches([r.name, r.owner, r.trade, r.city, r.country, r.groupName ?? ""].joined(separator: " "))
        }
    }

    private func hero(_ all: [MarketUI.RivalItem], _ groups: [MarketUI.GroupItem], _ e: GameEngine) -> some View {
        let forSale: Int = all.filter { (r: MarketUI.RivalItem) -> Bool in r.forSale }.count
        let context: String = all.isEmpty ? "" : "\(forSale) for sale \u{00B7} \(groups.count.countText("group"))"
        return MarketHero(label: "Rivals in your markets", value: "\(all.count)", context: context, contextTint: forSale > 0 ? P.accent : nil,
                          identifier: "market-rivals-hero")
    }

    @ViewBuilder private func rivalList(_ list: [MarketUI.RivalItem], _ watched: Set<String>) -> some View {
        if list.isEmpty {
            EmptyState(glyph: Glyph.market, title: filter == .watching ? "No rival watched" : "No rival matches")
        } else {
            let cur: Currency? = store.engine?.homeCurrency
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketUI.RivalItem)) in
                    if pair.offset > 0 { Hairline().padding(.leading, 40 + Theme.Space.m) }
                    rivalRow(pair.element, watched.contains(pair.element.id), cur)
                }
            }
        }
    }

    private func rivalRow(_ r: MarketUI.RivalItem, _ watched: Bool, _ cur: Currency?) -> some View {
        let logo = ThumbSpec(kind: .logo, key: "rival|co\(r.companyID)|\(r.rivalID)", glyph: Glyph.person, initials: r.name, shape: .square)
        let value: String = cur.map { (c: Currency) -> String in c.tidyShort(r.valuation) } ?? ""
        let title: String = watched ? r.name + " \u{2605}" : r.name
        return LedgerRow(leading: .thumb(logo), title: title, subtitle: "\(r.trade) \u{00B7} \(r.city) \u{00B7} \(r.sizeWord)", value: value,
                         valueNote: r.forSale ? "" : r.shareText, pill: r.forSale ? "For sale" : (r.inTrouble ? "In trouble" : nil),
                         pillTone: r.forSale ? .good : .warn, lineLimit: 1, identifier: "market-rival-\(r.id)",
                         action: { open(.rival(companyID: r.companyID, rivalID: r.rivalID)) })
            .newMarker(.market, "r\(r.companyID).\(r.rivalID)", style: .dot, alignment: .topLeading)
    }

    @ViewBuilder private func groupList(_ list: [MarketUI.GroupItem]) -> some View {
        if list.isEmpty {
            EmptyState(glyph: Glyph.group, title: "No rival group around you")
        } else {
            let cur: Currency? = store.engine?.homeCurrency
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketUI.GroupItem)) in
                    if pair.offset > 0 { Hairline().padding(.leading, 40 + Theme.Space.m) }
                    let g: MarketUI.GroupItem = pair.element
                    LedgerRow(leading: .thumb(ThumbSpec(kind: .logo, key: "group|\(g.id)", glyph: Glyph.group, initials: g.name, shape: .square)),
                              title: g.name, subtitle: "\(g.owner) \u{00B7} \(g.sites) sites \u{00B7} \(g.strategy)",
                              value: cur.map { (c: Currency) -> String in c.tidyShort(g.revenue) } ?? "", valueNote: "sales a year",
                              pill: g.inTrouble ? "In trouble" : nil, pillTone: .warn, lineLimit: 1, identifier: "market-group-\(g.id)",
                              action: { open(.group(g.id)) })
                }
            }
        }
    }
}

// MARK: A rival's profile

/// One rival: what it is worth and whether it sells, what your analyst sees, how it fares against you, its owner and their history with
/// you, the group behind it and its reviews. The page's one action is the offer; meeting the owner and opening beside them are in the menu.
struct RivalProfilePage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var rivalID: Int
    @State private var offering = false
    @State private var group: String?

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID), let d = e.rivalDetail(companyID: companyID, rivalID: rivalID) {
                let cur: Currency = e.currency(for: co)
                ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                    hero(e, d, cur)
                    facts(d)
                    against(e, co, d)
                    priceCut(e, d)
                    owner(d)
                    groupRow(d)
                    reviews(d)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PrimaryAction(title: "Make an offer", identifier: "rival-make-offer") { offering = true }
                        .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
                        .background(P.ground.opacity(0.96))
                }
                .appScreen(title: d.rival.name, subtitle: "\(e.tradeName(co)) in \(e.cityName(co))") { menu(e, d, cur) }
                .centerSheet(isPresented: $offering, title: "Make an offer", category: .medium, tone: .investment) {
                    RivalOfferSheet(companyID: companyID, rivalID: rivalID)
                }
                .navigationDestination(item: Binding(get: { group.map { (g: String) -> MarketRoute in MarketRoute.group(g) } },
                                                     set: { (r: MarketRoute?) in if r == nil { group = nil } })) { (r: MarketRoute) in MarketDestination(route: r) }
            } else {
                EmptyState(glyph: Glyph.market, title: "This rival is gone")
                    .appScreen(title: "Rival", subtitle: "Market")
            }
        }
    }

    // MARK: Hero

    private func hero(_ e: GameEngine, _ d: RivalDetail, _ cur: Currency) -> some View {
        let value: Double = e.rivalValue(companyID: companyID, rivalID: rivalID)
        let context: String = d.rival.forSale ? "Open to offers \u{00B7} owner \(d.rival.owner)"
            : "Owner \(d.rival.owner) \u{00B7} \(Rivals.relationshipWord(d.rival.relationship).lowercased())"
        return MarketHero(label: "Worth about", value: cur.tidyShort(value), context: context, contextTint: d.rival.forSale ? P.accent : nil,
                          identifier: "rival-hero")
    }

    // MARK: Facts

    private func facts(_ d: RivalDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarketLabel(title: d.analyst.map { (a: String) -> String in "What \(a) sees" } ?? "Your feeling")
            ForEach(Array(d.facts.enumerated()), id: \.element.id) { (pair: (offset: Int, element: Fact)) in
                if pair.offset > 0 { Hairline() }
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(pair.element.label.tidyText).textStyle(.body, tint: P.inkSoft)
                    Spacer(minLength: Theme.Space.s)
                    Text(pair.element.value.tidyText).textStyle(.body, numeric: true).multilineTextAlignment(.trailing)
                }
                .padding(.vertical, Theme.Space.s + 2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Against you

    private func against(_ e: GameEngine, _ co: Company, _ d: RivalDetail) -> some View {
        let row: RivalRow? = e.rivalRows(co).first { (r: RivalRow) -> Bool in r.id == rivalID }
        let share: String = row?.share.map { (s: MarketMap.Estimate) -> String in MarketMap.text(s) } ?? (row?.feel ?? "")
        return VStack(alignment: .leading, spacing: 0) {
            MarketLabel(title: "Against \(co.name)")
            FigureRow(items: [
                KeyFigures.Item(label: "Their share", value: share),
                KeyFigures.Item(label: "Their price", value: e.currency(for: co).tidyShort(d.price)),
                KeyFigures.Item(label: "Rating", value: String(format: "%.1f", d.reviewRating), sub: "\(d.reviewCount) reviews"),
            ], combineCells: true)
            .padding(.top, Theme.Space.s)
        }
    }

    // MARK: Their price cut

    @ViewBuilder private func priceCut(_ e: GameEngine, _ d: RivalDetail) -> some View {
        if let cut = e.rivalPriceCut(companyID: companyID, rivalID: rivalID) {
            MarketLabel(title: "\(d.rival.name) cut prices \(cut.pct)%")
            if let answer = cut.answered {
                Text("You answered: \(answer).").textStyle(.caption)
            } else {
                Text("Until week \(cut.end)").textStyle(.caption)
                VStack(spacing: 0) {
                    LedgerRow(leading: .symbol("tag"), title: "Match their price", identifier: "rival-cut-match", action: { answerCut(.match) })
                    Hairline()
                    LedgerRow(leading: .symbol("sparkles"), title: "Hold prices, sell quality", identifier: "rival-cut-quality", action: { answerCut(.quality) })
                    Hairline()
                    LedgerRow(leading: .symbol("plus.square.on.square"), title: "Add a cheap second brand", identifier: "rival-cut-brand", action: { answerCut(.brand) })
                }
            }
        }
    }

    // MARK: Owner and history

    private func owner(_ d: RivalDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            MarketLabel(title: "The owner")
            Text("\(d.rival.owner) \u{00B7} \(d.moodWord)").textStyle(.headline)
            Text(d.nextMove.tidyText).textStyle(.caption).lineLimit(1)
            if !d.rival.memory.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(d.rival.memory.prefix(8).enumerated()), id: \.offset) { (pair: (offset: Int, element: (week: Int, text: String, change: Double))) in
                        historyRow(pair.element, last: pair.offset == min(8, d.rival.memory.count) - 1)
                    }
                }
                .padding(.top, Theme.Space.s)
            }
        }
    }

    private func historyRow(_ m: (week: Int, text: String, change: Double), last: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(spacing: 0) {
                Circle().fill(m.change > 0 ? P.gain : (m.change < 0 ? P.loss : P.inkFaint)).frame(width: 7, height: 7).padding(.top, 6)
                if !last { Rectangle().fill(P.hairline).frame(width: 1).frame(maxHeight: .infinity) }
            }
            .frame(width: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(GameCalendar.dateString(week: m.week)).textStyle(.caption, tint: P.inkFaint)
                Text(m.text.tidyText).textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, last ? 0 : Theme.Space.m)
        }
    }

    // MARK: Group and reviews

    @ViewBuilder private func groupRow(_ d: RivalDetail) -> some View {
        if let g = d.group {
            MarketLabel(title: "Group behind it")
            LedgerRow(leading: .thumb(ThumbSpec(kind: .logo, key: "group|\(g.id)", glyph: Glyph.group, initials: g.name, shape: .square)),
                      title: g.name, subtitle: "\(g.strategyName) \u{00B7} \(g.branches) sites" + (g.inTrouble ? " \u{00B7} in money trouble" : ""),
                      identifier: "rival-group", action: { group = g.id })
        }
    }

    @ViewBuilder private func reviews(_ d: RivalDetail) -> some View {
        if !d.reviews.isEmpty {
            MarketLabel(title: "What customers say", note: String(format: "%.1f \u{2605}", d.reviewRating))
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(d.reviews.prefix(3)) { (r: ReviewLine) in
                    Text(String(repeating: "\u{2605}", count: r.stars) + "  " + r.text.tidyText).textStyle(.caption).lineLimit(2)
                }
            }
        }
    }

    // MARK: Menu

    private func menu(_ e: GameEngine, _ d: RivalDetail, _ cur: Currency) -> some View {
        let watching: Bool = MarketData.isWatched(e, rivalID: rivalID)
        let canOpenBeside: Bool = e.state.company(companyID)?.value("docs")["fran"]["st"].string == "ok"
        return HStack(spacing: 0) {
            Button {
                Haptics.choose()
                MarketData.toggleWatch(store, rivalID: rivalID)
            } label: {
                Image(systemName: watching ? "star.fill" : "star").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(watching ? P.accent : P.ink).frame(width: 44, height: 44)
            }
            .accessibilityLabel(watching ? "Stop watching" : "Watch")
            .accessibilityIdentifier("rival-watch")
            Menu {
                Button("Meet the owner \u{00B7} " + cur.tidyShort(cur.scaledPrice(4000))) { meet(d) }
                if canOpenBeside { Button("Open a new site beside them") { openSite() } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(P.ink).frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("rival-more")
        }
    }

    // MARK: Actions

    private func meet(_ d: RivalDetail) {
        let cid: Int = companyID
        let rid: Int = rivalID
        switch store.act({ (g: inout GameEngine) -> Rivals.MeetResult in g.meetRival(companyID: cid, rivalID: rid) }) {
        case .wait?: store.show("You met recently. Give it a few weeks.", tone: "warn")
        case .cash?: store.show("Not enough cash for the lunch.", tone: "warn")
        case .ok?: Haptics.success(); store.show("Lunch with \(d.rival.owner). The relationship is warmer.", tone: "good")
        default: store.show("This rival is gone.", tone: "warn")
        }
    }

    private func answerCut(_ answer: RivalAbsorb.Counter) {
        let cid: Int = companyID
        let rid: Int = rivalID
        switch store.act({ (g: inout GameEngine) -> RivalAbsorb.CounterResult in g.answerPriceCut(companyID: cid, rivalID: rid, answer: answer) }) {
        case .done(let m)?: Haptics.success(); store.show(m, tone: "good")
        case .alreadyLowest?: store.show("You are already at your lowest price.", tone: "warn")
        case .notEnoughCash?: store.show("Not enough cash.", tone: "warn")
        case .newCompany?: Haptics.success(); store.show("The second brand is registered. Set it up to open.")
        case .failed(let m)?: store.show(m, tone: "warn")
        case nil: break
        }
    }

    private func openSite() {
        let cid: Int = companyID
        let rid: Int = rivalID
        let r = store.act { $0.openBranchNextToRival(companyID: cid, rivalID: rid) }
        switch r {
        case .ok?: Haptics.success(); store.show("The new site is registered. Set it up to open.")
        case .needsFranchisePapers?: store.show("You need your franchise papers first.", tone: "warn")
        case .notEnoughCash?: store.show("Not enough money to start it.", tone: "warn")
        case .failed(let m)?: store.show(m, tone: "warn")
        case nil: break
        }
    }
}

// MARK: The offer

/// Making an offer for a rival: the price as a multiple of what it is worth, the owner's answer (no, a counter price, or yes), then what
/// the business should become (`AcquisitionSheet`) before anything is paid.
struct RivalOfferSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var rivalID: Int
    @State private var multiple = 1.2
    @State private var reply: String?
    @State private var counter: Double?
    /// The price the owner agreed to: asks what the business should become before paying.
    @State private var agreed: Double?

    private struct PriceID: Identifiable { var price: Double; var id: Double { price } }

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID), let d = e.rivalDetail(companyID: companyID, rivalID: rivalID) {
                content(e, co, d)
            } else {
                EmptyState(glyph: Glyph.market, title: "This rival is gone")
            }
        }
        .centerSheet(item: Binding(get: { agreed.map { (p: Double) -> PriceID in PriceID(price: p) } }, set: { (x: PriceID?) in agreed = x?.price }),
                     title: "Acquisition", category: .detail, tone: .investment) { (p: PriceID) in
            AcquisitionSheet(companyID: companyID, rivalID: rivalID, price: p.price) { (kind: AcquisitionPlan.Kind) in
                switch kind {
                case .own: agreed = nil; buy(p.price)
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

    private func content(_ e: GameEngine, _ co: Company, _ d: RivalDetail) -> some View {
        let cur: Currency = e.currency(for: co)
        let value: Double = e.rivalValue(companyID: companyID, rivalID: rivalID)
        let price: Double = value * multiple
        let setUp: Double = e.rivalStartupMoney(companyID: companyID, rivalID: rivalID)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Your offer for \(d.rival.name)").textStyle(.label, tint: P.inkFaint)
                Text(cur.tidyShort(price)).textStyle(.display).lineLimit(2).minimumScaleFactor(0.8).accessibilityIdentifier("rival-offer-price")
                Text(String(format: "%.2f\u{00D7} its value of %@", multiple, cur.tidyShort(value))).textStyle(.caption)
            }
            LedgerSlider(value: $multiple, in: 0.8...3, step: 0.05)
                .accessibilityIdentifier("rival-offer-slider")
            Text("+ \(cur.tidyShort(setUp)) set-up").popupText(.caption)
            if let reply {
                Text(reply.tidyText).popupText(.body).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("rival-offer-reply")
            }
            if let counter {
                Button("Accept their price \u{00B7} " + cur.tidyShort(counter)) { agreed = counter }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: P.accent))
                    .accessibilityIdentifier("rival-offer-accept")
            }
        }
        .popupFooter {
            PopupFooter(action: "Send the offer", tone: .expensive, onCancel: { dismiss() }, onAction: { makeOffer() },
                        cancelID: "rival-offer-cancel", actionID: "rival-offer-send")
        }
    }

    private func makeOffer() {
        let cid: Int = companyID
        let rid: Int = rivalID
        let m: Double = multiple
        guard let r = store.act({ (g: inout GameEngine) -> Rivals.OfferReply? in g.offerForRival(companyID: cid, rivalID: rid, multiple: m) }) ?? nil else { return }
        counter = nil
        switch r {
        case .ignore(let text), .reject(let text): reply = text; Haptics.warning()
        case .counter(let p, let text): reply = text; counter = p
        case .accept(let p, let text): reply = text; agreed = p
        }
    }

    private func absorb(_ price: Double, _ how: RivalAbsorb.How) {
        agreed = nil
        let cid: Int = companyID
        let rid: Int = rivalID
        let r = store.act { $0.absorbRival(companyID: cid, rivalID: rid, price: price, how: how) }
        switch r {
        case .ok(let message, _, _)?: Haptics.success(); store.show(message, tone: "good"); dismiss()
        case .notEnoughCash?: reply = "Not enough cash for the price and the extra costs."; Haptics.warning()
        case .failed(let why)?: reply = why
        case nil: break
        }
    }

    private func buyWithBank(_ price: Double) {
        agreed = nil
        guard let e = store.engine else { return }
        let cid: Int = companyID
        let rid: Int = rivalID
        let amount: Double = min((price * 0.7 / 1000).rounded() * 1000, (e.ownBankRoom() / 1000).rounded(.down) * 1000)
        let r = store.act { $0.buyRivalWithOwnBank(companyID: cid, rivalID: rid, price: price, amount: amount) }
        switch r {
        case .ok(.ok)?: Haptics.success(); store.show("You bought the business with a loan from your bank.", tone: "good"); dismiss()
        case .ok(.notEnoughCash)?: reply = "Not enough cash for the rest of the price and the set-up."; Haptics.warning()
        case .ok(.failed(let why))?: reply = why
        case .bankCannotLend?: reply = "Your bank cannot lend that much."; Haptics.warning()
        case nil: break
        }
    }

    private func buy(_ price: Double) {
        let cid: Int = companyID
        let rid: Int = rivalID
        let r = store.act { $0.buyRival(companyID: cid, rivalID: rid, price: price) }
        switch r {
        case .ok?: Haptics.success(); store.show("You bought the business.", tone: "good"); dismiss()
        case .notEnoughCash?: reply = "Not enough cash for the price and the set-up."; Haptics.warning()
        case .failed(let why)?: reply = why
        case nil: break
        }
    }
}
