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
    var name: String
    var badge: String
    var price: String
    var trust: Double?
    var delivery: String
    var cost: Double
    var current: Bool
    var blocked: String?
    var action: SupplierAction
    var unit: Double = 0
    var free: Int?
    var need: Int = 0
    var start: Int = 0
    var logoID: String = ""
    var ownerName: String = ""
    var ownerCode: String = ""
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
    var cooldown: Int = 0
    var endFee: Double?
    var itemID: String?
}

private let weeksPerMonth: Double = 52.0 / 12.0

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
    @State private var ordering: SupplierChoice?
    @State private var units: Double = 1
    @State private var ending: Bool = false

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let sheet = makeSheet(e, co) {
            if ending, let fee = sheet.endFee {
                endView(sheet, fee: fee)
            } else if let c = ordering {
                orderView(c, sheet)
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
            let saved: Int = p.record?.monthlyUnits ?? 0
            let wanted: Int = mine && saved > 0 ? saved : need
            return SupplierChoice(id: o.vendorID, name: o.vendorName, badge: "Supplier", price: itemAmount(o.buyPrice, cur) + " a unit", trust: o.reliability,
                                  delivery: o.leadDays > 0 ? "Delivery: \(o.leadDays) days" : "", cost: o.buyPrice, current: mine, blocked: nil,
                                  action: .vendor(o.vendorID), unit: o.buyPrice, free: o.capacityFree, need: need, start: max(1, min(wanted, max(1, o.capacityFree))))
        }
        let weeks: Int = e.itemRepickWeeksLeft(companyID: companyID, itemID: id)
        let fee: Double? = currentID == nil ? nil : e.itemCancelFee(companyID: companyID, itemID: id)
        return SupplierSheet(title: "Who supplies \(p.item.name.tidyText)?", subtitle: "Pick who you buy it from.", currency: cur, choices: choices, governed: nil,
                             weekly: 0, lineID: nil, lineTitle: p.item.name, goodsTier: false, cooldown: weeks, endFee: fee, itemID: id)
    }

    private func lineSheet(_ e: GameEngine, _ co: Company, _ id: String) -> SupplierSheet? {
        guard let row = e.supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == id }) else { return nil }
        let cur: Currency = e.currency(for: co)
        let contract: SupplyContract? = market.service.contract(buyerCompanyID: companyID, lineID: id)
        var choices: [SupplierChoice] = row.offers.map { (o: SupplyOfferRow) -> SupplierChoice in
            var cost: Double = 1
            if let w = o.weekly, let base = row.weekly, base > 0 { cost = w / base }
            return SupplierChoice(id: "o:" + o.id, name: o.name, badge: o.source, price: o.weekly.map { cur.tidyShort($0) + " a week" } ?? "Paid per job", trust: o.trust,
                                  delivery: Self.leadText(o.lead), cost: cost, current: o.isCurrent && contract == nil, blocked: o.blocked.map { Self.short($0) },
                                  action: .offer(o))
        }
        if row.governed == nil && !SupplyMarketCatalogue.tradesSupplying(line: id).isEmpty {
            choices.append(contentsOf: listingChoices(e, row, cur, contract))
        }
        return SupplierSheet(title: "Who supplies \(row.title.lowercased())?", subtitle: "Pick who you buy it from.", currency: cur, choices: choices, governed: row.governed,
                             weekly: row.weekly ?? 0, lineID: id, lineTitle: row.title, goodsTier: id == "goods", cooldown: 0,
                             endFee: contract == nil ? nil : e.playerSupplyCancelFee(companyID: companyID, lineID: id), itemID: nil)
    }

    private func listingChoices(_ e: GameEngine, _ row: SupplyRow, _ cur: Currency, _ contract: SupplyContract?) -> [SupplierChoice] {
        let today: Int = SupplyMarketStore.today(e)
        let wanted: [SupplyListing] = market.service.listings(lineID: row.id).filter { e.playerSupplyAllowed(companyID: companyID, listing: $0) }
        let landed: [String: SupplyLanded.Row] = SupplyLandedBasis.lookup(SupplyLandedBasis.rows(e, companyID: companyID, listings: wanted, weekly: row.weekly))
        return wanted.map { (l: SupplyListing) -> SupplierChoice in
            let a: SupplyAvailability = SupplyGuards.availability(l, buyerLinkKeys: market.service.buyerLinkKeys, units: max(l.minOrder, SupplyLandedBasis.compareUnits), today: today)
            let r: SupplyLanded.Row? = landed[l.id]
            var price: String = SupplyMarketWords.price(l.priceTier)
            var delivery: [String] = []
            if let r {
                price = cur.tidyShort(r.unitPrice) + " a unit"
                if r.mode != nil {
                    price += " + " + cur.tidyShort(r.freightPerUnit + r.customsPerUnit) + " delivery"
                    delivery.append("\(Int(saturating: r.distanceKm.rounded())) km" + (r.crossesBorder ? " abroad" : ""))
                }
            }
            if l.leadDays > 0 { delivery.append("\(l.leadDays) days") }
            let room: Int = max(0, SupplyGuards.effectiveCapacity(l) - l.committedUnits)
            let weeklyStart: Int = min(max(l.minOrder, 20), max(l.minOrder, room))
            return SupplierChoice(id: "l:" + l.id, name: l.companyName.isEmpty ? l.ownerName : l.companyName, badge: l.isFriend ? "Friend" : "Player", price: price, trust: l.record.ordersTotal == 0 ? nil : l.record.deliveredShare,
                                  delivery: delivery.isEmpty ? "" : "Delivery: " + delivery.joined(separator: " \u{00B7} "), cost: l.priceFactor * (r?.landedFactor ?? 1),
                                  current: contract?.listingID == l.id, blocked: a.message.map { Self.short($0) }, action: .listing(l),
                                  unit: r?.unitPrice ?? 0, free: Int(Double(room) * weeksPerMonth), start: Int((Double(weeklyStart) * weeksPerMonth).rounded()),
                                  logoID: l.logoID, ownerName: l.ownerName, ownerCode: l.profileCode)
        }
    }

    private static func short(_ text: String) -> String {
        let t: String = text.replacingOccurrences(of: "Not available: ", with: "")
        return t.prefix(1).uppercased() + String(t.dropFirst())
    }

    private static func leadText(_ lead: String) -> String {
        ["Continuous", "As needed", "Same week"].contains(lead) ? "" : "Delivery: " + lead.lowercased()
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
        let suggested: SupplierChoice? = now == nil ? usable.first { (c: SupplierChoice) -> Bool in if case .listing = c.action { return false } else { return true } } : nil
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
                    row(c, sheet, locked: true).opacity(0.5)
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
                        onAction: { choose(s) }, cancelID: "item-supplier-done", actionID: "item-supplier-keep")
        } else {
            PopupOptionButton(title: asking ? "Decide later" : "Done", identifier: "item-supplier-done") { onClose() }
        }
    }

    private func row(_ c: SupplierChoice, _ sheet: SupplierSheet, locked: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                SupplierLogo(logoID: c.logoID, name: c.name, size: 64)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(c.name.tidyText).popupText(.rowValue).lineLimit(2).multilineTextAlignment(.leading)
                    Text(c.badge).popupText(.caption)
                        .padding(.horizontal, Theme.Space.s).padding(.vertical, 2)
                        .background(Capsule().fill(P.ink.opacity(0.1)))
                }
                Spacer(minLength: Theme.Space.s)
            }
            if !c.ownerName.isEmpty {
                SupplierOwnerLine(name: c.ownerName, onOpen: ownerAction(c))
            }
            VStack(spacing: Theme.Space.xxs) {
                factLine("Price", c.price)
                if !c.delivery.isEmpty { factLine("Lead time", c.delivery.replacingOccurrences(of: "Delivery: ", with: "")) }
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    Text("Reliability").popupText(.caption)
                    Spacer(minLength: Theme.Space.s)
                    TrustBar(trust: c.trust)
                }
                if let free = c.free, c.blocked == nil, !c.current {
                    factLine("Room", "\(free) units a month")
                }
            }
            if let why = c.blocked { Text(why).popupText(.caption).lineLimit(2) }
            if c.current {
                HStack(spacing: Theme.Space.s) {
                    Chip(text: "In use", tint: P.accent)
                    Spacer(minLength: Theme.Space.s)
                    if case .vendor = c.action {
                        Button("Change order") { Haptics.tap(); open(c) }
                            .buttonStyle(SecondaryButtonStyle(size: .compact))
                            .accessibilityIdentifier("supply-edit-\(c.id)")
                    }
                }
            } else if c.blocked == nil && !locked {
                Button("Use this supplier") { Haptics.tap(); choose(c) }
                    .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                    .accessibilityIdentifier("supply-use-\(c.id)")
            }
        }
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ownerAction(_ c: SupplierChoice) -> (() -> Void)? {
        guard !c.ownerCode.isEmpty, let open = onOpenOwner else { return nil }
        return { open(c.ownerCode) }
    }

    private func factLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(label).popupText(.caption)
            Spacer(minLength: Theme.Space.s)
            Text(value).popupText(.body).multilineTextAlignment(.trailing).lineLimit(2)
        }
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

    private func choose(_ c: SupplierChoice) {
        switch c.action {
        case .vendor: open(c)
        case .offer, .listing: open(c)
        }
    }

    private func open(_ c: SupplierChoice) {
        message = nil
        units = Double(max(1, c.start))
        ordering = c
    }

    @ViewBuilder private func orderView(_ c: SupplierChoice, _ sheet: SupplierSheet) -> some View {
        if case .offer(let o) = c.action {
            offerView(c, o)
        } else {
            unitsView(c, sheet)
        }
    }

    private func offerView(_ c: SupplierChoice, _ o: SupplyOfferRow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("Price").popupText(.rowLabel)
                Spacer(minLength: Theme.Space.s)
                Text(c.price).popupText(.rowValue)
            }
            if !c.delivery.isEmpty { Text(c.delivery).popupText(.caption) }
            TrustBar(trust: c.trust)
            if !o.detail.isEmpty { Text(o.detail.tidyText).popupText(.caption) }
            if let message { Text(message).popupText(.risk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle("Use \(c.name.tidyText)?")
        .popupFooter {
            PopupFooter(cancel: "Back", action: "Confirm", onCancel: { ordering = nil; message = nil }, onAction: { chooseOffer(o) },
                        cancelID: "supply-order-back", actionID: "supply-order-confirm")
        }
        .accessibilityIdentifier("supply-offer")
    }

    private func unitsView(_ c: SupplierChoice, _ sheet: SupplierSheet) -> some View {
        let free: Int = max(0, c.free ?? Int.max)
        let upper: Double = Double(max(1, min(free, 1_000_000)))
        let count: Int = Int(units)
        let month: Double = c.unit * Double(count)
        let fee: Double = month / weeksPerMonth * 2
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(c.need > 0 ? "About \(c.need) units a month is what this item needs now. Change it if you want." : "Say how many units a month you want.").popupText(.subtitle)
            HStack {
                Text("Units a month").popupText(.rowLabel)
                Spacer(minLength: Theme.Space.s)
                Text("\(count)").popupText(.rowValue)
                StepperPill(value: $units, range: 1...upper, step: upper > 40 ? 5 : 1)
            }
            HStack {
                Text("Price a unit").popupText(.rowLabel)
                Spacer(minLength: Theme.Space.s)
                Text(c.unit > 0 ? sheet.currency.tidyShort(c.unit) : c.price).popupText(.rowValue)
            }
            if c.unit > 0 {
                HStack {
                    Text("About a month").popupText(.rowLabel)
                    Spacer(minLength: Theme.Space.s)
                    Text(sheet.currency.tidyShort(month)).popupText(.rowValue)
                }
            }
            if let f = c.free { Text(f > 0 ? "\(f) units a month still free with them." : "They are fully booked.").popupText(.caption) }
            Text("Either side can end it later for a fee of two weeks of the order, about " + sheet.currency.tidyShort(fee) + ".").popupText(.caption)
            if let message { Text(message).popupText(.risk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle("Order from \(c.name.tidyText)")
        .popupFooter {
            PopupFooter(cancel: "Back", action: "Confirm", onCancel: { ordering = nil; message = nil }, onAction: { confirm(c, sheet) },
                        actionEnabled: free > 0, cancelID: "supply-order-back", actionID: "supply-order-confirm")
        }
        .accessibilityIdentifier("supply-order")
    }

    private func confirm(_ c: SupplierChoice, _ sheet: SupplierSheet) {
        switch c.action {
        case .vendor(let vendor): chooseVendor(vendor, c.name, units: Int(units))
        case .listing(let l): signListing(l, sheet)
        case .offer: break
        }
    }

    private func signListing(_ l: SupplyListing, _ sheet: SupplierSheet) {
        guard let lineID = sheet.lineID else { return }
        let room: Int = max(l.minOrder, SupplyGuards.effectiveCapacity(l) - l.committedUnits)
        let weekly: Int = min(room, max(l.minOrder, Int((units / weeksPerMonth).rounded(.up))))
        let r: SupplySignResult = market.sign(store, companyID: companyID, lineID: lineID, listing: l, units: weekly, weeklyMarketSpend: sheet.weekly)
        switch r {
        case .signed:
            Haptics.success()
            store.outcome(chosen: "\(l.ownerName) for \(sheet.lineTitle)", result: "\(l.ownerName) now supplies \(sheet.lineTitle.lowercased()), \(Int(units)) units a month.")
            onClose()
        case .refused(let why):
            Haptics.warning()
            message = why
        }
    }

    private func endView(_ sheet: SupplierSheet, fee: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Ending the supply costs a fee of two weeks of the order: " + sheet.currency.tidyShort(fee) + ". \(sheet.lineTitle) then goes back to the standard supplier.").popupText(.subtitle)
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

    private func chooseVendor(_ vendor: String, _ name: String, units: Int) {
        guard case .item(let item) = subject else { return }
        let id: Int = companyID
        let r = store.act { $0.setItemSupplier(companyID: id, itemID: item, vendorID: vendor, unitsPerMonth: units) }
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
                    Capsule().fill(share >= 0.95 ? P.gain : share >= 0.88 ? P.accent : P.caution).frame(width: 48 * CGFloat(share))
                }
                .frame(width: 48, height: 5)
                Text("\(Int((share * 100).rounded()))% reliable").popupText(.caption)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Not tested yet").popupText(.caption)
        }
    }
}
