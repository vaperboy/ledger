import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum SupplierSubject: Identifiable, Hashable {
    case item(String)
    case line(String)

    var id: String {
        switch self {
        case .item(let i): return "item:" + i
        case .line(let l): return "line:" + l
        }
    }

    init(_ ask: SupplyAsk, itemID: String) {
        switch ask {
        case .item: self = .item(itemID)
        case .line(let l): self = .line(l)
        }
    }
}

private enum SupplierRank: Int, CaseIterable, Hashable {
    case cheapest, reliable

    var title: String { self == .cheapest ? "Cheapest" : "Most reliable" }
}

private enum SupplierAction {
    case vendor(String)
    case offer(SupplyOfferRow)
    case listing(SupplyListing)
}

private struct SupplierChoice: Identifiable {
    var id: String
    var company: SupplierCompany
    var price: String
    var trust: Double?
    var delivery: String
    var cost: Double
    var current: Bool
    var blocked: String?
    var action: SupplierAction
    var fit: SupplyFit = .fine
    var name: String { company.name }
}

private struct SupplierSheet {
    var title: String
    var subtitle: String
    var currency: Currency
    var choices: [SupplierChoice]
    var governed: String?
    var weekly: Double
    var lineID: String?
    var lineTitle: String
    var goodsTier: Bool
    var need: String
    var cooldown: Int = 0
    var endFee: Double?
    var itemID: String?
}

// Pick who supplies a line or an item. The game orders what the company needs; the player only picks the company.
struct SupplierPopup: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var subject: SupplierSubject
    var asking: Bool = false
    var onClose: () -> Void
    var onOpenOwner: ((String) -> Void)? = nil
    @State private var rank: SupplierRank = .cheapest
    @State private var message: String?
    @State private var confirming: SupplierChoice?
    @State private var opened: String?
    @State private var ending: Bool = false

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let sheet = makeSheet(e, co) {
            if ending, let fee = sheet.endFee {
                endView(sheet, fee: fee)
            } else if let c = confirming {
                confirmView(c, sheet)
            } else {
                content(sheet, co)
            }
        } else {
            Text("This is gone.").popupText(.subtitle)
                .centerSheetTitle("Supplier")
                .popupFooter { PopupOptionButton(title: "Done", identifier: "item-supplier-done") { onClose() } }
        }
    }

    private func makeSheet(_ e: GameEngine, _ co: Company) -> SupplierSheet? {
        switch subject {
        case .item(let id): return itemSheet(e, co, id)
        case .line(let id): return lineSheet(e, co, id)
        }
    }

    private func itemSheet(_ e: GameEngine, _ co: Company, _ id: String) -> SupplierSheet? {
        guard let p = e.itemPage(companyID: companyID, itemID: id), !p.offers.isEmpty else { return nil }
        let cur: Currency = e.currency(for: co)
        let currentID: String? = p.record?.supplierID
        let need: Int = e.itemMonthlyNeed(companyID: companyID, itemID: id)
        let choices: [SupplierChoice] = p.offers.map { (o: ItemModels.SupplyLine) -> SupplierChoice in
            let mine: Bool = o.vendorID == currentID
            return SupplierChoice(id: o.vendorID, company: SupplierCompany.from(o, engine: e), price: itemAmount(o.buyPrice, cur) + " a unit", trust: o.reliability,
                                  delivery: o.leadDays > 0 ? "\(o.leadDays) days" : "", cost: o.buyPrice, current: mine,
                                  blocked: !mine && o.fit == .cannot ? "Cannot supply what it needs" : nil, action: .vendor(o.vendorID), fit: o.fit)
        }
        let weeks: Int = e.itemRepickWeeksLeft(companyID: companyID, itemID: id)
        let fee: Double? = currentID == nil ? nil : e.itemCancelFee(companyID: companyID, itemID: id)
        return SupplierSheet(title: "Who supplies \(p.item.name.tidyText)?", subtitle: "It needs about \(need) units a month. Pick who you buy them from.", currency: cur,
                             choices: choices, governed: nil, weekly: 0, lineID: nil, lineTitle: p.item.name, goodsTier: false, need: "\(need) units a month",
                             cooldown: weeks, endFee: fee, itemID: id)
    }

    private func lineSheet(_ e: GameEngine, _ co: Company, _ id: String) -> SupplierSheet? {
        guard let row = e.supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == id }) else { return nil }
        let cur: Currency = e.currency(for: co)
        let contract: SupplyContract? = market.service.contract(buyerCompanyID: companyID, lineID: id)
        var choices: [SupplierChoice] = row.offers.map { (o: SupplyOfferRow) -> SupplierChoice in
            var cost: Double = 1
            if let w = o.weekly, let base = row.weekly, base > 0 { cost = w / base }
            var blocked: String? = o.blocked
            if blocked == nil && !o.isCurrent && o.fit == .cannot { blocked = "Cannot supply what you need" }
            return SupplierChoice(id: "o:" + o.id, company: SupplierCompany.from(o, engine: e), price: o.weekly.map { cur.tidyShort($0) + " a week" } ?? "Paid per job",
                                  trust: o.trust, delivery: Self.leadText(o.lead), cost: cost, current: o.isCurrent && contract == nil, blocked: blocked,
                                  action: .offer(o), fit: o.fit)
        }
        if row.governed == nil && !SupplyMarketCatalogue.tradesSupplying(line: id).isEmpty {
            choices.append(contentsOf: listingChoices(e, row, cur, contract))
        }
        return SupplierSheet(title: "Who supplies \(row.title.lowercased())?", subtitle: "You need about \(row.need) units a week. Pick who you buy them from.", currency: cur,
                             choices: choices, governed: row.governed, weekly: row.weekly ?? 0, lineID: id, lineTitle: row.title, goodsTier: row.input == "goods",
                             need: "\(row.need) units a week", cooldown: 0,
                             endFee: contract == nil ? nil : e.playerSupplyCancelFee(companyID: companyID, lineID: id), itemID: nil)
    }

    private func listingChoices(_ e: GameEngine, _ row: SupplyRow, _ cur: Currency, _ contract: SupplyContract?) -> [SupplierChoice] {
        let today: Int = SupplyMarketStore.today(e)
        let wanted: [SupplyListing] = market.service.listings(lineID: row.id).filter { e.playerSupplyAllowed(companyID: companyID, listing: $0) }
        let landed: [String: SupplyLanded.Row] = SupplyLandedBasis.lookup(SupplyLandedBasis.rows(e, companyID: companyID, listings: wanted, weekly: row.weekly, units: max(1, row.need)))
        return wanted.map { (l: SupplyListing) -> SupplierChoice in
            let mine: Bool = contract?.listingID == l.id
            let fit: SupplyFit = e.playerSupplyFit(companyID: companyID, listing: l, today: today)
            let a: SupplyAvailability = SupplyGuards.availability(l, buyerLinkKeys: market.service.buyerLinkKeys, units: max(l.minOrder, row.need), today: today)
            let r: SupplyLanded.Row? = landed[l.id]
            var price: String = SupplyMarketWords.price(l.priceTier)
            var delivery: [String] = []
            if let r {
                price = cur.tidyShort(r.landedPerUnit * Double(max(1, row.need))) + " a week"
                if r.mode != nil { delivery.append("\(Int(saturating: r.distanceKm.rounded())) km" + (r.crossesBorder ? " abroad" : "")) }
            }
            if l.leadDays > 0 { delivery.append("\(l.leadDays) days") }
            var blocked: String? = a == .belowMinimum(l.minOrder) || a == .full ? nil : a.message.map { Self.short($0) }
            if blocked == nil && !mine && fit == .cannot { blocked = "Cannot supply what you need" }
            return SupplierChoice(id: "l:" + l.id, company: SupplierCompany.from(l, engine: e), price: price, trust: l.record.ordersTotal == 0 ? nil : l.record.deliveredShare,
                                  delivery: delivery.joined(separator: " \u{00B7} "), cost: l.priceFactor * (r?.landedFactor ?? 1), current: mine, blocked: blocked,
                                  action: .listing(l), fit: fit)
        }
    }

    private static func short(_ text: String) -> String {
        let t: String = text.replacingOccurrences(of: "Not available: ", with: "")
        return t.prefix(1).uppercased() + String(t.dropFirst())
    }

    private static func leadText(_ lead: String) -> String {
        ["Continuous", "As needed", "Same week"].contains(lead) ? "" : lead.lowercased()
    }

    private func ranked(_ list: [SupplierChoice]) -> [SupplierChoice] {
        list.sorted { (a: SupplierChoice, b: SupplierChoice) -> Bool in
            switch rank {
            case .cheapest: return a.cost != b.cost ? a.cost < b.cost : a.name < b.name
            case .reliable: return (a.trust ?? 0.5) != (b.trust ?? 0.5) ? (a.trust ?? 0.5) > (b.trust ?? 0.5) : a.name < b.name
            }
        }
    }

    private func content(_ sheet: SupplierSheet, _ co: Company) -> some View {
        let now: SupplierChoice? = sheet.choices.first { (c: SupplierChoice) -> Bool in c.current }
        let others: [SupplierChoice] = sheet.choices.filter { (c: SupplierChoice) -> Bool in !c.current }
        let usable: [SupplierChoice] = ranked(others.filter { (c: SupplierChoice) -> Bool in c.blocked == nil })
        let unavailable: [SupplierChoice] = others.filter { (c: SupplierChoice) -> Bool in c.blocked != nil }
        let fine: SupplierChoice? = usable.first(where: { (c: SupplierChoice) -> Bool in c.fit == .fine })
        let suggested: SupplierChoice? = now == nil ? (fine ?? usable.first) : nil
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(sheet.subtitle).popupText(.subtitle)
            if let g = sheet.governed { Text(g.tidyText).popupText(.risk) }
            if sheet.goodsTier { goodsTier(co) }
            if sheet.cooldown > 0 {
                Text("You changed this supplier recently. You can pick another one in \(sheet.cooldown) \(sheet.cooldown == 1 ? "week" : "weeks"). The first pick is free.").popupText(.risk)
            }
            if let now {
                heading("Your supplier now")
                row(now, sheet, locked: true)
                if let fee = sheet.endFee {
                    Button("End this supply") { Haptics.tap(); ending = true; message = nil }
                        .buttonStyle(SecondaryButtonStyle(size: .compact))
                        .accessibilityIdentifier("supply-end")
                    Text("Ending it costs two weeks of the order, about " + sheet.currency.tidyShort(fee) + ". Either side can end it.").popupText(.caption)
                }
            } else {
                Text("No supplier chosen yet.").popupText(.risk)
            }
            if !usable.isEmpty {
                heading("Other suppliers")
                if usable.count > 1 {
                    SegmentedPill(items: SupplierRank.allCases, title: { (r: SupplierRank) -> String in r.title }, selection: $rank,
                                  identifier: { (r: SupplierRank) -> String in "supply-rank-\(r.rawValue)" })
                }
                ForEach(Array(usable.enumerated()), id: \.element.id) { (n: Int, c: SupplierChoice) in
                    if n > 0 { Hairline() }
                    row(c, sheet, locked: sheet.governed != nil || sheet.cooldown > 0)
                }
            }
            if !unavailable.isEmpty {
                heading("Not available")
                ForEach(Array(unavailable.enumerated()), id: \.element.id) { (n: Int, c: SupplierChoice) in
                    if n > 0 { Hairline() }
                    row(c, sheet, locked: true).opacity(0.6)
                }
            }
            if let message { Text(message).popupText(.risk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(sheet.title)
        .popupFooter { footer(suggested) }
        .accessibilityIdentifier("item-supplier-chooser")
        .task { market.sync(store) }
    }

    private func heading(_ text: String) -> some View {
        Text(text).popupText(.rowLabel).padding(.top, Theme.Space.xs)
    }

    @ViewBuilder private func footer(_ suggested: SupplierChoice?) -> some View {
        if asking, let s = suggested {
            PopupFooter(cancel: "Decide later", action: "Use \(s.name.tidyText)", onCancel: { onClose() },
                        onAction: { confirming = s; message = nil }, cancelID: "item-supplier-done", actionID: "item-supplier-keep")
        } else {
            PopupOptionButton(title: asking ? "Decide later" : "Done", identifier: "item-supplier-done") { onClose() }
        }
    }

    // A compact row: tap the company to see its card, then use it.
    private func row(_ c: SupplierChoice, _ sheet: SupplierSheet, locked: Bool) -> some View {
        let open: Bool = opened == c.id
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Button {
                Haptics.tap()
                opened = open ? nil : c.id
            } label: {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    SupplierLogo(logoID: c.company.logoID, name: c.name, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name.tidyText).popupText(.rowValue).lineLimit(1)
                        Text(([c.price, c.delivery].filter { (s: String) -> Bool in !s.isEmpty }).joined(separator: " \u{00B7} ")).popupText(.caption).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.xs)
                    FitMark(fit: c.fit)
                    TrustBar(trust: c.trust)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the company card" : "Shows the company card")
            if open {
                SupplierCompanyCard(company: c.company, onOpenOwner: ownerAction(c))
                    .padding(Theme.Space.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.ink.opacity(0.05)))
            }
            if let why = c.blocked { Text(why).popupText(.caption).lineLimit(2) }
            if c.current {
                Chip(text: "In use", tint: P.accent)
            } else if c.blocked == nil && !locked {
                Button("Use this supplier") { Haptics.tap(); confirming = c; message = nil }
                    .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                    .accessibilityIdentifier("supply-use-\(c.id)")
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ownerAction(_ c: SupplierChoice) -> (() -> Void)? {
        guard !c.company.ownerCode.isEmpty, let open = onOpenOwner else { return nil }
        let code: String = c.company.ownerCode
        return { open(code) }
    }

    private func goodsTier(_ co: Company) -> some View {
        let raw: JSONValue = co.value("src")["c"]
        let now: Int = min(2, max(0, raw.isNull ? 1 : raw.int))
        let binding = Binding<Int>(get: { now }, set: { (v: Int) in
            _ = store.act { $0.chooseGoodsClass(companyID: companyID, goodsClass: v) }
            Haptics.tap()
        })
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Quality").popupText(.rowLabel)
            SegmentedPill(items: [0, 1, 2], title: { (i: Int) -> String in Suppliers.goodsClassNames[i] }, selection: binding)
        }
    }

    // One check before switching: the price, and whether they can cover the need.
    private func confirmView(_ c: SupplierChoice, _ sheet: SupplierSheet) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SupplierCompanyCard(company: c.company, onOpenOwner: ownerAction(c))
            HStack {
                Text("Price").popupText(.rowLabel)
                Spacer(minLength: Theme.Space.s)
                Text(c.price).popupText(.rowValue)
            }
            HStack {
                Text("You need").popupText(.rowLabel)
                Spacer(minLength: Theme.Space.s)
                Text(sheet.need).popupText(.rowValue)
            }
            if c.fit == .mayFallShort { Text("They are close to full. Some weeks they may deliver less than you need.").popupText(.risk) }
            if case .listing = c.action {
                Text("Either side can end it later for a fee of two weeks of the order.").popupText(.caption)
            }
            if let message { Text(message).popupText(.risk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle("Use \(c.name.tidyText)?")
        .popupFooter {
            PopupFooter(cancel: "Back", action: "Confirm", onCancel: { confirming = nil; message = nil }, onAction: { apply(c, sheet) },
                        cancelID: "supply-order-back", actionID: "supply-order-confirm")
        }
        .accessibilityIdentifier("supply-confirm")
    }

    private func apply(_ c: SupplierChoice, _ sheet: SupplierSheet) {
        switch c.action {
        case .vendor(let vendor): chooseVendor(vendor, c.name)
        case .listing(let l): signListing(l, sheet)
        case .offer(let o): chooseOffer(o)
        }
    }

    private func signListing(_ l: SupplyListing, _ sheet: SupplierSheet) {
        guard let lineID = sheet.lineID else { return }
        let r: SupplySignResult = market.sign(store, companyID: companyID, lineID: lineID, listing: l, weeklyMarketSpend: sheet.weekly)
        switch r {
        case .signed:
            Haptics.success()
            let who: String = l.companyName.isEmpty ? l.ownerName : l.companyName
            store.outcome(chosen: "\(who) for \(sheet.lineTitle)", result: "\(who) now supplies \(sheet.lineTitle.lowercased()), \(sheet.need).")
            onClose()
        case .refused(let why):
            Haptics.warning()
            message = why
        }
    }

    private func endView(_ sheet: SupplierSheet, fee: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Ending the supply costs a fee of two weeks of the order: " + sheet.currency.tidyShort(fee) + ". \(sheet.lineTitle) then goes back to your usual supplier.").popupText(.subtitle)
            if let message { Text(message).popupText(.risk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle("End this supply?")
        .popupFooter {
            PopupFooter(cancel: "Keep it", action: "Pay " + sheet.currency.tidyShort(fee) + " and end", tone: .destructive, onCancel: { ending = false; message = nil },
                        onAction: { endSupply(sheet) }, cancelID: "supply-end-keep", actionID: "supply-end-confirm")
        }
        .accessibilityIdentifier("supply-end-sheet")
    }

    private func endSupply(_ sheet: SupplierSheet) {
        let id: Int = companyID
        var why: String?
        if let item = sheet.itemID {
            let r: SettingResult? = store.act { $0.cancelItemSupplier(companyID: id, itemID: item) }
            if case .refused(let w)? = r { why = w }
        } else if let line = sheet.lineID {
            why = market.end(store, companyID: id, lineID: line)
        }
        if let why { Haptics.warning(); message = why; return }
        Haptics.success()
        store.saved("supply ended")
        onClose()
    }

    private func chooseVendor(_ vendor: String, _ name: String) {
        guard case .item(let item) = subject else { return }
        let id: Int = companyID
        let r = store.act { $0.setItemSupplier(companyID: id, itemID: item, vendorID: vendor) }
        if case .refused(let why)? = r { Haptics.warning(); message = why; return }
        if r?.didChange == true { Haptics.success(); store.saved("supplied by " + name) }
        if asking { store.tutorialAdvance(from: .pickSupplier) }
        onClose()
    }

    private func chooseOffer(_ o: SupplyOfferRow) {
        let id: Int = companyID
        let result: SupplierSwitchResult? = store.act { $0.chooseSupply(companyID: id, change: o.change) }
        switch result {
        case .ok?:
            Haptics.success()
            store.saved("supplied by " + o.name)
            if asking { store.tutorialAdvance(from: .pickSupplier) }
            onClose()
        case .notKnownWell?: Haptics.warning(); message = "They do not know you well enough yet. Buy from them for a while first."
        case .governed?: Haptics.warning(); message = "A chain rule or your franchise agreement fixes this supplier."
        default: Haptics.warning(); message = "That supplier is not available for this company now."
        }
    }
}

private struct TrustBar: View {
    @Environment(\.outsidePalette) private var P
    var trust: Double?

    var body: some View {
        if let t = trust {
            let share: Double = min(1, max(0, t))
            HStack(spacing: Theme.Space.xs) {
                ZStack(alignment: .leading) {
                    Capsule().fill(P.ink.opacity(0.12))
                    Capsule().fill(share >= 0.95 ? P.gain : share >= 0.88 ? P.accent : P.caution).frame(width: 36 * CGFloat(share))
                }
                .frame(width: 36, height: 5)
                Text("\(Int((share * 100).rounded()))%").popupText(.caption)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Int((share * 100).rounded()))% reliable")
        } else {
            Text("New").popupText(.caption)
        }
    }
}
