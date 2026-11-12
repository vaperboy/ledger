import Foundation
import GameCore
import Businesses

final class MockSupplyMarketService: SupplyMarketService {
    var onChange: (() -> Void)?

    private var all: [SupplyListing] = []
    private var contracts: [SupplyContract] = []
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

    private static let first = ["Ana", "Ben", "Chidi", "Dara", "Elif", "Farid", "Greta", "Hugo", "Ines", "Jonas", "Kira", "Leo", "Mira", "Nils", "Olga", "Pavel", "Quinn", "Rosa", "Sven", "Tala", "Uma", "Vik", "Wren", "Xavi", "Yara", "Zane"]
    private static let last = ["Holt", "Marsh", "Okafor", "Lindqvist", "Varga", "Bright", "Castell", "Dunmore", "Esposito", "Fairweather", "Gallagher", "Hartmann", "Ivanova", "Jansen", "Kowalski", "Lacroix", "Moreno", "Nakamura", "Ortega", "Petrov", "Quigley", "Rask", "Sato", "Thorne"]
    private static let nouns = ["Supply", "Trading", "Works", "Provisions", "& Sons", "Partners", "Group", "Direct"]
    private static let places: [(city: String, region: String, country: String)] = [
        ("Leeds", "North", "UK"), ("Bristol", "South West", "UK"), ("Hamburg", "Hamburg", "DE"), ("Cardiff", "Wales", "UK"), ("Norwich", "East", "UK"),
        ("Birmingham", "Midlands", "UK"), ("Oslo", "Oslo", "NO"), ("Aberdeen", "Scotland", "UK"), ("Exeter", "South West", "UK"), ("Newcastle", "North", "UK"),
        ("Chicago", "Midwest", "US"), ("London", "South East", "UK"), ("Zurich", "Zurich", "CH"), ("Glasgow", "Scotland", "UK"), ("Sydney", "New South Wales", "AU"), ("Munich", "Bavaria", "DE"),
    ]
    // Trade names come from the trade catalogue, so a listing reads like any player company.
    private static let tradeNames: [String: String] = {
        guard let c = try? TradeCatalog.bundled() else { return [:] }
        return c.trades.mapValues { (t: Trade) -> String in t.name }
    }()

    private func roll(_ key: String) -> Double { HashedRandom.first("supplymock:" + key) }

    private func seed() {
        let provided: [SupplyMarketPlayer] = SupplyMarketPlayersSource.provider?.players() ?? []
        let players: [SupplyMarketPlayer] = provided.isEmpty ? madeUpPlayers() : provided
        // Every pair of supplying trade and line from the supply map gets players in turn.
        let pairs: [(trade: String, line: String)] = SupplyMap.supplyPairs
        guard !pairs.isEmpty else { return }
        for (i, p) in players.enumerated() {
            let own: [SupplyMarketCatalogue.Line] = SupplyMarketCatalogue.supplyableLines(tradeID: p.tradeID)
            let trade: String = own.isEmpty ? pairs[i % pairs.count].trade : p.tradeID
            var lines: [SupplyMarketCatalogue.Line] = own
            if own.isEmpty, let l = SupplyMarketCatalogue.line(pairs[i % pairs.count].line) { lines = [l] }
            guard !lines.isEmpty else { continue }
            let line = lines[i % lines.count]
            let cap = 40 + Int(roll("cap\(i)") * 360)
            var l = SupplyListing(id: "L\(i)", ownerID: p.ownerID, ownerName: p.ownerName, profileCode: p.profileCode, companyName: p.companyName, tradeID: trade,
                                  tradeName: Self.tradeNames[trade] ?? trade.capitalized, city: p.city, region: p.region, lineID: line.id, lineName: line.name,
                                  priceTier: Int(roll("pt\(i)") * 3), qualityTier: Int(roll("qt\(i)") * 3), capacityPerWeek: cap, leadDays: 1 + Int(roll("ld\(i)") * 5),
                                  minOrder: [5, 10, 20, 25][Int(roll("mo\(i)") * 4)], termsDays: SupplyMarketCatalogue.termOptions[Int(roll("tm\(i)") * 3)],
                                  linkKey: p.linkKey, record: record(i, cap: cap), isFriend: p.isFriend, country: p.country)
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
            let linked = i == 7
            return SupplyMarketPlayer(ownerID: "owner\(i)", ownerName: linked ? "Mira Vance (your other account)" : "\(f) \(l)", profileCode: String(format: "P%05d", 40_100 + i * 37),
                                      companyName: "\(l) \(Self.nouns[i % Self.nouns.count])", tradeID: "", city: place.city, region: place.region,
                                      linkKey: linked ? "me" : "key\(i)", isFriend: i % 9 == 2, country: place.country)
        }
    }

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

    private func visible(_ l: SupplyListing) -> Bool { !(FakePlayers.removed && FakePlayers.isFake(ownerID: l.ownerID)) }

    func listings(lineID: String) -> [SupplyListing] { all.filter { $0.lineID == lineID && !$0.stopped && visible($0) } }
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

    func restore(contracts saved: [SupplyContract]) {
        contracts = []
        for c in saved {
            contracts.append(c)
            if let i = all.firstIndex(where: { $0.id == c.listingID }) { all[i].committedUnits += c.unitsPerWeek }
        }
        counter = max(counter, saved.compactMap { Int($0.id.dropFirst()) }.max() ?? 0)
        onChange?()
    }

    func randomPick(lineID: String, units: Int, today: Int, seed: String, excluding: Set<String>) -> SupplyListing? {
        SupplyChoice.draw(SupplyChoice.randomPool(listings(lineID: lineID), units: units, buyerLinkKeys: buyerLinkKeys, today: today), seed: seed, excluding: excluding)
    }

    func wellKnown(lineID: String, units: Int, today: Int) -> [SupplyListing] {
        SupplyChoice.wellKnown(listings(lineID: lineID), units: units, buyerLinkKeys: buyerLinkKeys, today: today)
    }

    func openContractsAsSupplier(ownerID: String) -> Int { contracts.filter { $0.supplierOwnerID == ownerID }.count }

    func demandPosts(today: Int) -> [DemandPost] {
        if FakePlayers.removed { return [] }
        let week: Int = today / 7
        let lines: [String] = Array(Set(SupplyMarketCatalogue.supplies.values.flatMap { $0 })).sorted()
        return (0..<6).map { (n: Int) -> DemandPost in
            let key: String = "demand\(week):\(n)"
            let f: String = Self.first[Int(roll(key + "f") * Double(Self.first.count))]
            let l: String = Self.last[Int(roll(key + "l") * Double(Self.last.count))]
            let noun: String = Self.nouns[Int(roll(key + "n") * Double(Self.nouns.count))]
            return DemandPost(id: "D\(week):\(n)", ownerName: "\(f) \(l)", companyName: "\(l) \(noun)", lineID: lines[Int(roll(key + "x") * Double(lines.count))],
                              units: 5 + Int(roll(key + "u") * 40), weeks: [4, 8, 13][Int(roll(key + "w") * 3)])
        }
    }

    func advance(today: Int) -> [SupplyMarketEvent] {
        let week: Int = today / 7
        guard let last = processedWeek else {
            processedWeek = week
            for (k, v) in failPlan { failAt[k] = (week + v.after, v.reason) }
            return []
        }
        guard week > last else { return [] }
        var events: [SupplyMarketEvent] = []
        for w in (last + 1)...min(week, last + 4) { events += step(week: w) }
        processedWeek = week
        onChange?()
        return events
    }

    private func step(week: Int) -> [SupplyMarketEvent] {
        var events: [SupplyMarketEvent] = []
        for (owner, f) in failAt.sorted(by: { $0.key < $1.key }) where week >= f.week {
            events += supplierStopped(ownerID: owner, reason: f.reason).map { SupplyMarketEvent.supplierEnded($0) }
            failAt.removeValue(forKey: owner)
        }
        for i in all.indices where !all[i].stopped {
            let l = all[i]
            let cap: Int = SupplyGuards.effectiveCapacity(l)
            let contractUnits: Int = contracts.filter { $0.listingID == l.id }.reduce(0) { $0 + $1.unitsPerWeek }
            var promised = contractUnits, delivered = contractUnits, late = 0, complaints = 0, orders = contractUnits > 0 ? 1 : 0
            let key = "\(l.id):\(week)"
            let miss: Double = l.word == .struggling ? 0.3 : l.word == .mostlyReliable ? 0.12 : 0.04
            let weekPromised: Int = max(1, Int(Double(cap) * (0.2 + 0.4 * roll("load" + key))))
            let short: Bool = roll("short" + key) < miss
            promised += weekPromised; delivered += short ? weekPromised * 3 / 4 : weekPromised; orders += 2
            late += roll("lt" + key) < miss ? 1 : 0; complaints += short ? 1 : 0
            all[i].committedUnits = min(cap, Int(Double(cap) * (0.2 + 0.6 * roll("c" + key))) + contractUnits)
            all[i].record = SupplyRecordRules.applying(all[i].record, promised: promised, delivered: delivered, orders: orders, late: late, complaints: complaints)
            if promised > 0 && contracts.contains(where: { $0.listingID == l.id }) { events.append(.delivery(listingID: l.id, promised: promised, delivered: delivered, orders: max(1, orders), late: late)) }
        }
        return events
    }

    func supplierStopped(ownerID: String, reason: SupplyEnd) -> [SupplyFallback] {
        for i in all.indices where all[i].ownerID == ownerID { all[i].stopped = true }
        let r = SupplyContracts.end(contracts, supplierOwnerID: ownerID, reason: reason)
        contracts = r.kept
        onChange?()
        return r.fallbacks
    }
}
