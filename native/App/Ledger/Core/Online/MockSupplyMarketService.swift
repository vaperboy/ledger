import Foundation
import GameCore
import Businesses

/// The local stand-in for the supply market server: seeds suppliers (from the online player list when it is wired, else its own), lets buyers
/// sign, works weeks forward (orders, delivery records, suppliers that fail) and applies the rules of `SupplyGuards` and `SupplyContracts`.
/// Nothing is saved: the market is drawn again, the same, on each launch; the player's own listings and contracts last for the session.
final class MockSupplyMarketService: SupplyMarketService {
    var onChange: (() -> Void)?

    private var all: [SupplyListing] = []
    private var contracts: [SupplyContract] = []
    private var orderLog: [String: [SupplyOrder]] = [:]
    private var unitValues: [String: Double] = [:]
    private var buyersOf: [String: Int] = [:]
    /// Suppliers that will fail: weeks after the market starts, and why.
    private var failPlan: [String: (after: Int, reason: SupplyEnd)] = [:]
    private var failAt: [String: (week: Int, reason: SupplyEnd)] = [:]
    private var knownIDs: Set<String>
    private var processedWeek: Int?
    private var counter = 0

    let buyerLinkKeys: Set<String> = ["me"]
    let ownerID = "me"
    private static let knownKey = "supplyMarket.known"

    init() {
        let saved: [String]? = UserDefaults.standard.stringArray(forKey: Self.knownKey)
        knownIDs = Set(saved ?? [])
        seed()
    }

    // MARK: Seeds

    private static let first = ["Ana", "Ben", "Chidi", "Dara", "Elif", "Farid", "Greta", "Hugo", "Ines", "Jonas", "Kira", "Leo", "Mira", "Nils", "Olga", "Pavel", "Quinn", "Rosa", "Sven", "Tala", "Uma", "Vik", "Wren", "Xavi", "Yara", "Zane"]
    private static let last = ["Holt", "Marsh", "Okafor", "Lindqvist", "Varga", "Bright", "Castell", "Dunmore", "Esposito", "Fairweather", "Gallagher", "Hartmann", "Ivanova", "Jansen", "Kowalski", "Lacroix", "Moreno", "Nakamura", "Ortega", "Petrov", "Quigley", "Rask", "Sato", "Thorne"]
    private static let nouns = ["Supply", "Trading", "Works", "Provisions", "& Sons", "Partners", "Group", "Direct"]
    /// Most suppliers are in the UK; some are abroad, so freight and customs show in the comparison.
    private static let places: [(city: String, region: String, country: String)] = [
        ("Leeds", "North", "UK"), ("Bristol", "South West", "UK"), ("Hamburg", "Hamburg", "DE"), ("Cardiff", "Wales", "UK"), ("Norwich", "East", "UK"),
        ("Birmingham", "Midlands", "UK"), ("Oslo", "Oslo", "NO"), ("Aberdeen", "Scotland", "UK"), ("Exeter", "South West", "UK"), ("Newcastle", "North", "UK"),
        ("Chicago", "Midwest", "US"), ("London", "South East", "UK"), ("Zurich", "Zurich", "CH"), ("Glasgow", "Scotland", "UK"), ("Sydney", "New South Wales", "AU"), ("Munich", "Bavaria", "DE"),
    ]
    private static let tradeTitles: [String: String] = ["bakery": "Bakery", "brewery": "Brewery", "farm": "Farm", "vineyard": "Vineyard", "salmon": "Salmon farm", "factory": "Factory",
                                                         "furniture": "Furniture maker", "grocery": "Grocer", "hardware": "Hardware store", "cleaning": "Cleaning firm", "carclean": "Car wash",
                                                         "webdev": "Web studio", "gamestudio": "Game studio", "startup": "Software startup", "carrepair": "Garage", "handy": "Handyman",
                                                         "electrician": "Electrician", "plumber": "Plumber", "power": "Power company", "oilgas": "Fuel supplier", "courier": "Courier"]

    private func roll(_ key: String) -> Double { HashedRandom.first("supplymock:" + key) }

    private func seed() {
        let provided: [SupplyMarketPlayer] = SupplyMarketPlayersSource.provider?.players() ?? []
        let players: [SupplyMarketPlayer] = provided.isEmpty ? madeUpPlayers() : provided
        let trades: [String] = SupplyMarketCatalogue.supplierTrades
        for (i, p) in players.enumerated() {
            let trade: String = SupplyMarketCatalogue.supplies[p.tradeID] != nil ? p.tradeID : trades[i % trades.count]
            let lines = SupplyMarketCatalogue.supplyableLines(tradeID: trade)
            guard !lines.isEmpty else { continue }
            let line = lines[(i / max(1, trades.count) + i) % lines.count]
            let cap = 40 + Int(roll("cap\(i)") * 360)
            var l = SupplyListing(id: "L\(i)", ownerID: p.ownerID, ownerName: p.ownerName, profileCode: p.profileCode, companyName: p.companyName, tradeID: trade,
                                  tradeName: Self.tradeTitles[trade] ?? trade.capitalized, city: p.city, region: p.region, lineID: line.id, lineName: line.name,
                                  priceTier: Int(roll("pt\(i)") * 3), qualityTier: Int(roll("qt\(i)") * 3), capacityPerWeek: cap, leadDays: 1 + Int(roll("ld\(i)") * 5),
                                  minOrder: [5, 10, 20, 25][Int(roll("mo\(i)") * 4)], termsDays: SupplyMarketCatalogue.termOptions[Int(roll("tm\(i)") * 3)],
                                  linkKey: p.linkKey, record: record(i, cap: cap), isFriend: p.isFriend, country: p.country)
            // Cheap goods are a little less good, dear goods a little better.
            l.qualityTier = min(2, max(0, l.qualityTier + (l.priceTier == 0 ? -1 : l.priceTier == 2 ? 1 : 0)))
            l.committedUnits = Int(Double(cap) * (0.2 + 0.6 * roll("busy\(i)")))
            all.append(l)
            if i == 4 { failPlan[p.ownerID] = (3, .bankrupt) }
            if i == 11 { failPlan[p.ownerID] = (6, .accountDeleted) }
        }
    }

    private func madeUpPlayers() -> [SupplyMarketPlayer] {
        (0..<36).map { i in
            let f = Self.first[i % Self.first.count], l = Self.last[(i * 7 + 3) % Self.last.count]
            let place = Self.places[i % Self.places.count]
            // One supplier shares an owner with the player's accounts, to show the linked-account rule.
            let linked = i == 7
            return SupplyMarketPlayer(ownerID: "owner\(i)", ownerName: linked ? "Mira Vance (your other account)" : "\(f) \(l)", profileCode: String(format: "P%05d", 40_100 + i * 37),
                                      companyName: "\(l) \(Self.nouns[i % Self.nouns.count])", tradeID: "", city: place.city, region: place.region,
                                      linkKey: linked ? "me" : "key\(i)", isFriend: i % 9 == 2, country: place.country)
        }
    }

    /// Veterans, steady middle, newcomers and a few that struggle, by position.
    private func record(_ i: Int, cap: Int) -> DeliveryRecord {
        let kind = i % 6
        let weeks: Int = kind == 3 ? 1 + Int(roll("w\(i)") * 3) : 14 + Int(roll("w\(i)") * 60)
        let orders: Int = max(kind == 3 ? 2 : 8, weeks * 2)
        let delShare: Double = [0.99, 0.985, 0.93, 1, 0.74, 0.96][kind]
        let timeShare: Double = [0.98, 0.97, 0.9, 1, 0.6, 0.94][kind]
        let promised: Int = max(30, weeks * cap / 3)
        let trendOK: Bool = kind != 4
        return DeliveryRecord(weeksTrading: weeks, ordersTotal: orders, ordersOnTime: Int(Double(orders) * timeShare), unitsPromised: promised, unitsDelivered: Int(Double(promised) * delShare),
                              complaints: kind == 4 ? 9 : kind == 2 ? 3 : Int(roll("c\(i)") * 2), disputes: kind == 4 ? 3 : 0, priceChanges: kind == 4 ? 4 : kind == 2 ? 1 : 0,
                              cleanWeeks: kind == 3 ? weeks : kind == 4 ? 0 : 4 + Int(roll("cw\(i)") * 14),
                              deliveredTrend: kind == 3 ? nil : (trendOK ? 0.4 + roll("dt\(i)") * 2.5 : -(2 + roll("dt\(i)") * 5)),
                              onTimeTrend: kind == 3 ? nil : (trendOK ? roll("ot\(i)") * 3 - 0.8 : -(1 + roll("ot\(i)") * 6)), lifetimeUnits: Int(Double(promised) * delShare))
    }

    // MARK: Buying

    func listings(lineID: String) -> [SupplyListing] { all.filter { $0.lineID == lineID && !$0.stopped } }
    func listing(_ id: String) -> SupplyListing? { all.first { $0.id == id } }

    func profile(ownerID: String) -> SupplierProfile? {
        let mine = all.filter { $0.ownerID == ownerID && !$0.stopped }
        guard let f = all.first(where: { $0.ownerID == ownerID }) else { return nil }
        return SupplierProfile(ownerID: ownerID, ownerName: f.ownerName, profileCode: f.profileCode, isFriend: f.isFriend, listings: mine)
    }

    func knownSuppliers() -> Set<String> { knownIDs }

    func setKnown(ownerID: String, _ known: Bool) {
        if known { knownIDs.insert(ownerID) } else { knownIDs.remove(ownerID) }
        UserDefaults.standard.set(Array(knownIDs), forKey: Self.knownKey)
        onChange?()
    }

    func contract(buyerCompanyID: Int, lineID: String) -> SupplyContract? {
        contracts.first { $0.buyerCompanyID == buyerCompanyID && $0.lineID == lineID }
    }

    func sign(buyerCompanyID: Int, lineID: String, listingID: String, unitsPerWeek: Int, today: Int) -> SupplySignResult {
        guard let l = listing(listingID) else { return .refused("That offer is gone.") }
        let a = SupplyGuards.availability(l, buyerLinkKeys: buyerLinkKeys, units: unitsPerWeek, today: today)
        if let m = a.message { return .refused(m) }
        let room = SupplyGuards.effectiveCapacity(l) - l.committedUnits
        guard unitsPerWeek <= room else { return .refused("They can take \(max(0, room)) more units a week for now.") }
        if let old = contract(buyerCompanyID: buyerCompanyID, lineID: lineID) { release(old) }
        counter += 1
        let c = SupplyContract(id: "C\(counter)", buyerCompanyID: buyerCompanyID, lineID: lineID, listingID: listingID, supplierOwnerID: l.ownerID,
                               supplierName: l.ownerName, unitsPerWeek: unitsPerWeek, startDay: today)
        contracts.append(c)
        if let i = all.firstIndex(where: { $0.id == listingID }) { all[i].committedUnits += unitsPerWeek }
        onChange?()
        return .signed(c)
    }

    /// A contract that goes: its units are free on the listing again.
    private func release(_ c: SupplyContract) {
        contracts.removeAll { $0.id == c.id }
        if let i = all.firstIndex(where: { $0.id == c.listingID }) { all[i].committedUnits = max(0, all[i].committedUnits - c.unitsPerWeek) }
    }

    func reserve(listingID: String, units: Int, today: Int) -> String? {
        guard let i = all.firstIndex(where: { $0.id == listingID }) else { return "That offer is gone." }
        let l = all[i]
        if let m = SupplyGuards.availability(l, buyerLinkKeys: buyerLinkKeys, units: units, today: today).message { return m }
        let room = SupplyGuards.effectiveCapacity(l) - l.committedUnits
        guard units <= room else { return "They can take \(max(0, room)) more units this week." }
        all[i].committedUnits += units
        onChange?()
        return nil
    }

    func endContract(buyerCompanyID: Int, lineID: String) {
        guard let c = contract(buyerCompanyID: buyerCompanyID, lineID: lineID) else { return }
        release(c)
        onChange?()
    }

    func restore(contracts saved: [SupplyContract], listings: [SupplyListing], orders: [String: [SupplyOrder]], unitValues values: [String: Double]) {
        all.removeAll { $0.companyID != nil }
        all += listings
        orderLog = orders
        for (k, v) in values { unitValues[k] = v }
        contracts = []
        for c in saved {
            contracts.append(c)
            if let i = all.firstIndex(where: { $0.id == c.listingID }) { all[i].committedUnits += c.unitsPerWeek }
        }
        // New ids continue after the saved ones.
        let used: [Int] = (saved.map { $0.id } + listings.map { $0.id }).compactMap { Int($0.dropFirst()) }
        counter = max(counter, used.max() ?? 0)
        onChange?()
    }

    func ownSnapshot() -> (listings: [SupplyListing], orders: [String: [SupplyOrder]]) {
        let mine = all.filter { $0.companyID != nil && !$0.stopped }
        return (mine, orderLog.filter { k, _ in mine.contains { $0.id == k } })
    }

    func randomPick(lineID: String, units: Int, today: Int, seed: String, excluding: Set<String>) -> SupplyListing? {
        SupplyChoice.draw(SupplyChoice.randomPool(listings(lineID: lineID), units: units, buyerLinkKeys: buyerLinkKeys, today: today), seed: seed, excluding: excluding)
    }

    func wellKnown(lineID: String, units: Int, today: Int) -> [SupplyListing] {
        SupplyChoice.wellKnown(listings(lineID: lineID), units: units, buyerLinkKeys: buyerLinkKeys, today: today)
    }

    // MARK: Supplying

    func myListings(companyID: Int) -> [SupplyListing] { all.filter { $0.companyID == companyID && !$0.stopped } }

    func saveListing(_ d: ListingDraft, today: Int) -> ListingSaveResult {
        guard SupplyMarketCatalogue.supplyableLines(tradeID: d.tradeID).contains(where: { $0.id == d.lineID }), let line = SupplyMarketCatalogue.line(d.lineID) else {
            return .refused("Only what the trade's catalogue lists can be offered.")
        }
        guard d.capacityPerWeek > 0, d.minOrder > 0, d.minOrder <= d.capacityPerWeek else { return .refused("The minimum order has to fit within the weekly capacity.") }
        guard SupplyMarketCatalogue.durations.contains(d.durationDays) else { return .refused("Choose how long the offer lasts.") }
        if let id = d.listingID, let i = all.firstIndex(where: { $0.id == id }) {
            // Changing price or quality under a signed contract is recorded against the supplier.
            let changed: Bool = all[i].priceTier != d.priceTier || all[i].qualityTier != d.qualityTier
            if changed && contracts.contains(where: { $0.listingID == id }) { all[i].record.priceChanges += 1 }
            all[i].priceTier = d.priceTier; all[i].qualityTier = d.qualityTier; all[i].capacityPerWeek = d.capacityPerWeek
            all[i].leadDays = d.leadDays; all[i].minOrder = d.minOrder; all[i].termsDays = d.termsDays
            all[i].expiresDay = today + d.durationDays; all[i].paused = false
            unitValues[id] = d.unitValue
            onChange?()
            return .saved(all[i])
        }
        counter += 1
        let l = SupplyListing(id: "M\(counter)", ownerID: "me", ownerName: "You", profileCode: "YOU", companyName: d.companyName, companyID: d.companyID, tradeID: d.tradeID,
                              tradeName: Self.tradeTitles[d.tradeID] ?? d.tradeID.capitalized, city: "Your city", region: "Your region", lineID: d.lineID, lineName: line.name,
                              priceTier: d.priceTier, qualityTier: d.qualityTier, capacityPerWeek: d.capacityPerWeek, leadDays: d.leadDays, minOrder: d.minOrder,
                              termsDays: d.termsDays, linkKey: "me", expiresDay: today + d.durationDays, country: d.country)
        all.append(l)
        unitValues[l.id] = d.unitValue
        onChange?()
        return .saved(l)
    }

    func setPaused(listingID: String, _ paused: Bool) {
        guard let i = all.firstIndex(where: { $0.id == listingID }) else { return }
        all[i].paused = paused
        onChange?()
    }

    func stopListing(listingID: String) {
        guard let i = all.firstIndex(where: { $0.id == listingID }) else { return }
        all[i].stopped = true
        buyersOf[listingID] = 0
        onChange?()
    }

    func orders(listingID: String) -> [SupplyOrder] { orderLog[listingID] ?? [] }

    func openContractsAsSupplier(ownerID: String) -> Int {
        let signed: Int = contracts.filter { $0.supplierOwnerID == ownerID }.count
        let mock: Int = all.filter { $0.ownerID == ownerID && !$0.stopped }.reduce(0) { $0 + (buyersOf[$1.id] ?? 0) }
        return signed + mock
    }

    // MARK: Time

    func advance(today: Int, liveCompanyIDs: Set<Int>) -> [SupplyMarketEvent] {
        let week: Int = today / 7
        guard let last = processedWeek else {
            processedWeek = week
            for (k, v) in failPlan { failAt[k] = (week + v.after, v.reason) }
            return []
        }
        guard week > last else { return [] }
        var events: [SupplyMarketEvent] = []
        for w in (last + 1)...min(week, last + 4) { events += step(week: w, liveCompanyIDs: liveCompanyIDs) }
        processedWeek = week
        onChange?()
        return events
    }

    private func step(week: Int, liveCompanyIDs: Set<Int>) -> [SupplyMarketEvent] {
        var events: [SupplyMarketEvent] = []
        // Suppliers that fail or leave: their contracts end at once.
        for (owner, f) in failAt.sorted(by: { $0.key < $1.key }) where week >= f.week {
            events += supplierStopped(ownerID: owner, reason: f.reason).map { SupplyMarketEvent.supplierEnded($0) }
            failAt.removeValue(forKey: owner)
        }
        for i in all.indices where !all[i].stopped {
            let l = all[i]
            if let cid = l.companyID, !liveCompanyIDs.contains(cid) {
                all[i].stopped = true
                continue
            }
            let cap: Int = SupplyGuards.effectiveCapacity(l)
            let contractUnits: Int = contracts.filter { $0.listingID == l.id }.reduce(0) { $0 + $1.unitsPerWeek }
            var promised = contractUnits, delivered = contractUnits, late = 0, complaints = 0, orders = contractUnits > 0 ? 1 : 0
            let key = "\(l.id):\(week)"
            if l.companyID != nil {
                guard !l.paused, (l.expiresDay ?? Int.max) >= week * 7 else { all[i].committedUnits = contractUnits; continue }
                // Cheaper, better, and more reliable listings draw more orders.
                let appeal: Double = 0.35 + 0.15 * Double(2 - l.priceTier) + 0.1 * Double(l.qualityTier) + 0.2 * roll("appeal" + key)
                let demand: Int = min(cap, Int(Double(cap) * min(1, appeal)))
                let want: Int = demand >= l.minOrder ? demand : 0
                let n: Int = want == 0 ? 0 : 1 + Int(roll("n" + key) * 3)
                let unit: Double = (unitValues[l.id] ?? 0) * l.priceFactor
                var left: Int = want
                var made: [SupplyOrder] = []
                for k in 0..<n {
                    let units: Int = k == n - 1 ? left : max(l.minOrder, left / (n - k))
                    guard units > 0, units <= left else { continue }
                    left -= units
                    let isLate: Bool = roll("late\(key):\(k)") < 0.1
                    made.append(SupplyOrder(id: "\(key):\(k)", listingID: l.id, buyerName: Self.first[Int(roll("b\(key):\(k)") * 26)] + " " + Self.last[Int(roll("bl\(key):\(k)") * 24)],
                                            units: units, delivered: units, late: isLate, day: week * 7 + k, revenue: Double(units) * unit))
                }
                orderLog[l.id] = Array((made + (orderLog[l.id] ?? [])).prefix(20))
                let sold: Int = made.reduce(0) { $0 + $1.delivered }
                promised += want; delivered += sold; orders += made.count; late += made.filter { $0.late }.count
                buyersOf[l.id] = made.count
                if sold > 0 && unit > 0 { events.append(.sale(companyID: l.companyID ?? 0, units: sold, unitPrice: unit, unitCost: unit * 0.88)) }
                all[i].committedUnits = contractUnits + want
            } else {
                // Seeded suppliers: a missed delivery now and then, more for the weak.
                let miss: Double = l.word == .struggling ? 0.3 : l.word == .mostlyReliable ? 0.12 : 0.04
                let weekPromised: Int = max(1, Int(Double(cap) * (0.2 + 0.4 * roll("load" + key))))
                let short: Bool = roll("short" + key) < miss
                promised += weekPromised; delivered += short ? weekPromised * 3 / 4 : weekPromised; orders += 2
                late += roll("lt" + key) < miss ? 1 : 0; complaints += short ? 1 : 0
                all[i].committedUnits = min(cap, Int(Double(cap) * (0.2 + 0.6 * roll("c" + key))) + contractUnits)
            }
            all[i].record = SupplyRecordRules.applying(all[i].record, promised: promised, delivered: delivered, orders: orders, late: late, complaints: complaints)
            // A supplier the player buys from that delivered short: the books carry the cost (customers served late or not at all).
            if promised > delivered && contracts.contains(where: { $0.listingID == l.id }) { events.append(.shortDelivery(listingID: l.id)) }
        }
        return events
    }

    func companyStopped(companyID: Int, reason: SupplyEnd) -> [SupplyFallback] {
        var out: [SupplyFallback] = []
        for i in all.indices where all[i].companyID == companyID && !all[i].stopped {
            all[i].stopped = true
            buyersOf[all[i].id] = 0
            let r = SupplyContracts.end(contracts, listingID: all[i].id, reason: reason)
            contracts = r.kept
            out += r.fallbacks
        }
        onChange?()
        return out
    }

    func supplierStopped(ownerID: String, reason: SupplyEnd) -> [SupplyFallback] {
        for i in all.indices where all[i].ownerID == ownerID { all[i].stopped = true; buyersOf[all[i].id] = 0 }
        let r = SupplyContracts.end(contracts, supplierOwnerID: ownerID, reason: reason)
        contracts = r.kept
        onChange?()
        return r.fallbacks
    }
}
