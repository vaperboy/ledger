import Foundation
import GameCore

public enum AuctionDuration: Int, Codable, CaseIterable, Sendable {
    case oneHour = 1, sixHours = 6, oneDay = 24
    public var seconds: Double { Double(rawValue) * 3_600 }
    public var title: String { rawValue == 1 ? "1 hour" : "\(rawValue) hours" }
}

public struct AuctionBid: Codable, Equatable, Sendable {
    public var bidder: String
    public var amount: Int
    public var at: Double
    public init(bidder: String, amount: Int, at: Double) { self.bidder = bidder; self.amount = amount; self.at = at }
}

public struct Auction: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case live, sold, unsold, cancelled }

    public var id: String
    public var item: ArtifactItem
    public var seller: String
    public var startPrice: Int
    public var reserve: Int?
    public var buyNow: Int?
    public var startsAt: Double
    public var endsAt: Double
    public var duration: AuctionDuration
    public var bids: [AuctionBid] = []
    public var extensions = 0
    public var status: Status = .live
    public var soldFor: Int?

    public var currentPrice: Int { bids.last?.amount ?? startPrice }
    public var leader: String? { bids.last?.bidder }
    public var reserveMet: Bool { reserve == nil || currentPrice >= (reserve ?? 0) && !bids.isEmpty }
    public func secondsLeft(at now: Double) -> Double { max(0, endsAt - now) }
    public func isLive(at now: Double) -> Bool { status == .live && now < endsAt }
    public func canBuyNow(at now: Double) -> Bool { isLive(at: now) && (buyNow.map { currentPrice < $0 } ?? false) }
}

public enum AuctionError: Error, Equatable, Sendable {
    case notLive, sellerCannotBid, linkedAccount, alreadyLeading, tooLow(minimum: Int), notEnoughCash(missing: Int)
    case notYours, hasBids, badPrice(String), noBuyNow
}

extension AuctionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notLive: return "This auction has ended."
        case .sellerCannotBid: return "You cannot bid on your own auction."
        case .linkedAccount: return "You cannot bid on an auction of a linked account."
        case .alreadyLeading: return "You already lead this auction."
        case .tooLow: return "That is below the lowest bid."
        case .notEnoughCash: return "You do not have enough cash for that."
        case .notYours: return "That piece is not in your cabinet."
        case .hasBids: return "It has bids, so it cannot be taken back."
        case .badPrice(let why): return why
        case .noBuyNow: return "This piece cannot be bought outright now."
        }
    }
}

public enum AuctionRules {
    public static let feePercent = 10
    public static let antiSnipeWindow: Double = 120
    public static let maxExtensions = 12
    public static let minimumStartPrice = 1

    public static func increment(at price: Int) -> Int {
        let raw: Int = max(1, price / 20)
        var step = 1
        while step * 10 <= raw { step *= 10 }
        let lead: Int = raw / step
        return (lead >= 5 ? 5 : lead >= 2 ? 2 : 1) * step
    }

    public static func minimumBid(_ a: Auction) -> Int { a.bids.isEmpty ? a.startPrice : a.currentPrice + increment(at: a.currentPrice) }

    public static func fee(forSale price: Int) -> Int { price <= 0 ? 0 : max(1, price * feePercent / 100) }
    public static func proceeds(forSale price: Int) -> Int { price - fee(forSale: price) }

    public static func extendedEnd(endsAt: Double, extensions: Int, bidAt time: Double) -> (end: Double, extended: Bool) {
        guard extensions < maxExtensions, endsAt - time <= antiSnipeWindow else { return (endsAt, false) }
        let end: Double = time + antiSnipeWindow
        return end > endsAt ? (end, true) : (endsAt, false)
    }

    public static func listingProblem(startPrice: Int, reserve: Int?, buyNow: Int? = nil) -> String? {
        if startPrice < minimumStartPrice { return "Set a start price." }
        if let r = reserve {
            if r < startPrice { return "The reserve cannot be below the start price." }
            if r > startPrice * 50 { return "The reserve is too far above the start price." }
        }
        if let b = buyNow {
            if b <= startPrice { return "The buy-now price must be above the start price." }
            if let r = reserve, b < r { return "The buy-now price cannot be below the reserve." }
        }
        return nil
    }

    public static func held(by me: String, in auctions: [Auction]) -> Int {
        auctions.filter { $0.status == .live && $0.leader == me }.reduce(0) { $0 + $1.currentPrice }
    }

    public struct BidPreview: Equatable, Sendable {
        public var amount: Int
        public var minimum: Int
        public var allowed: Bool
        public var problem: String?
        public var shortBy: Int
        public var heldAfter: Int
        public var availableAfter: Int
        public var extendsAuction: Bool
        public var newEnd: Double
        public var reserveMetAfter: Bool
    }

    public static func preview(_ a: Auction, amount: Int, bidder: String, cash: Int, held: Int, now: Double, linked: Bool = false) -> BidPreview {
        let minimum: Int = minimumBid(a)
        let available: Int = max(0, cash - held)
        var problem: String?
        if !a.isLive(at: now) { problem = "This auction has ended." }
        else if a.seller == bidder { problem = "You cannot bid on your own auction." }
        else if linked { problem = "You cannot bid on an auction of a linked account." }
        else if a.leader == bidder { problem = "You already lead this auction." }
        else if amount < minimum { problem = "That is below the lowest bid." }
        else if amount > available { problem = "You do not have enough cash for that bid." }
        let ext = extendedEnd(endsAt: a.endsAt, extensions: a.extensions, bidAt: now)
        return BidPreview(amount: amount, minimum: minimum, allowed: problem == nil, problem: problem, shortBy: max(0, amount - available),
                          heldAfter: held + amount, availableAfter: available - amount,
                          extendsAuction: ext.extended, newEnd: ext.end, reserveMetAfter: a.reserve == nil || amount >= (a.reserve ?? 0))
    }
}

extension AuctionRules {
    public static let quickSalePercent = 88

    public static func quickSalePrice(_ rarity: BoxRarity, priceLevel: Double) -> Int {
        max(1, AuctionMarket.suggestedStart(rarity, priceLevel: priceLevel) * quickSalePercent / 100)
    }

    public static var quickSaleText: String {
        "A quick sale pays \(quickSalePercent)% of the market value at once, with no fee."
    }

    public static var feeText: String {
        "A sale costs the seller a fee of \(feePercent)% of the price. The fee is taken out of the game for good."
    }

    public struct ListingPreview: Equatable, Sendable {
        public var problem: String?
        public var proceedsAtStart: Int
        public var proceedsAtReserve: Int?
        public var proceedsAtBuyNow: Int?
        public var lines: [String]
    }

    public static func listingPreview(startPrice: Int, reserve: Int?, buyNow: Int? = nil, duration: AuctionDuration) -> ListingPreview {
        let problem = listingProblem(startPrice: startPrice, reserve: reserve, buyNow: buyNow)
        var lines: [String] = [
            "The piece leaves your cabinet while it is on sale, for \(duration.title).",
            "Bids are in cash. A bidder's cash is set aside while they lead and is free again when they are beaten.",
            feeText,
            "A bid in the last \(Int(antiSnipeWindow / 60)) minutes pushes the end out to \(Int(antiSnipeWindow / 60)) minutes after that bid, at most \(maxExtensions) times."
        ]
        if reserve != nil { lines.append("Bidders are told only whether your reserve has been met, not what it is. Below it the piece is not sold and comes back to you.") }
        if buyNow != nil { lines.append("Anyone can buy it at once for the buy-now price until a bid reaches that price. Then the auction ends and you are paid.") }
        lines.append("Accounts linked to yours cannot bid on it.")
        return ListingPreview(problem: problem, proceedsAtStart: proceeds(forSale: startPrice), proceedsAtReserve: reserve.map { proceeds(forSale: $0) },
                              proceedsAtBuyNow: buyNow.map { proceeds(forSale: $0) }, lines: lines)
    }
}

extension AuctionBook {
    public func previewBid(_ auctionID: String, amount: Int, bidder: String, cash: Int, now: Double) -> AuctionRules.BidPreview? {
        guard let a = auction(auctionID) else { return nil }
        return AuctionRules.preview(a, amount: amount, bidder: bidder, cash: cash, held: held, now: now, linked: a.seller != bidder && linked(a.seller, bidder))
    }
}

public struct AuctionSettlement: Equatable, Sendable {
    public var auctionID: String
    public var item: ArtifactItem
    public var status: Auction.Status
    public var price: Int
    public var fee: Int
    public var seller: String
    public var winner: String?
    public var cash: Int
    public var completed: [ArtifactCollection]

    public static func == (a: AuctionSettlement, b: AuctionSettlement) -> Bool {
        a.auctionID == b.auctionID && a.status == b.status && a.price == b.price && a.fee == b.fee && a.winner == b.winner && a.seller == b.seller && a.cash == b.cash
    }
}

public struct AuctionBook: Codable, Equatable, Sendable {
    public var me: String
    public var auctions: [Auction] = []
    public var feesBurned = 0
    public var nextNumber = 1
    public var linkKeys: [String: String]?

    public init(me: String) { self.me = me }

    public func linkKey(of account: String) -> String { linkKeys?[account] ?? account }

    public func linked(_ a: String, _ b: String) -> Bool { a == b || linkKey(of: a) == linkKey(of: b) }

    public func auction(_ id: String) -> Auction? { auctions.first { $0.id == id } }

    public var held: Int { AuctionRules.held(by: me, in: auctions) }

    public func available(cash: Int) -> Int { max(0, cash - held) }

    private func index(_ id: String) -> Int? { auctions.firstIndex { $0.id == id } }

    @discardableResult
    public mutating func place(_ auctionID: String, bidder: String, amount: Int, now: Double, cash: Int = 0) throws -> (extended: Bool, newEnd: Double) {
        guard let i = index(auctionID), auctions[i].isLive(at: now) else { throw AuctionError.notLive }
        let a: Auction = auctions[i]
        if a.seller == bidder { throw AuctionError.sellerCannotBid }
        if linked(a.seller, bidder) { throw AuctionError.linkedAccount }
        if a.leader == bidder { throw AuctionError.alreadyLeading }
        let minimum: Int = AuctionRules.minimumBid(a)
        if amount < minimum { throw AuctionError.tooLow(minimum: minimum) }
        if bidder == me, amount > available(cash: cash) { throw AuctionError.notEnoughCash(missing: amount - available(cash: cash)) }
        let ext = AuctionRules.extendedEnd(endsAt: a.endsAt, extensions: a.extensions, bidAt: now)
        auctions[i].bids.append(AuctionBid(bidder: bidder, amount: amount, at: now))
        if ext.extended { auctions[i].endsAt = ext.end; auctions[i].extensions += 1 }
        return (ext.extended, auctions[i].endsAt)
    }

    public mutating func buyNow(_ auctionID: String, buyer: String, now: Double, cash: Int = 0) throws {
        guard let i = index(auctionID), auctions[i].isLive(at: now) else { throw AuctionError.notLive }
        let a: Auction = auctions[i]
        guard a.canBuyNow(at: now), let price = a.buyNow else { throw AuctionError.noBuyNow }
        if a.seller == buyer { throw AuctionError.sellerCannotBid }
        if linked(a.seller, buyer) { throw AuctionError.linkedAccount }
        if a.leader == buyer { throw AuctionError.alreadyLeading }
        if buyer == me, price > available(cash: cash) { throw AuctionError.notEnoughCash(missing: price - available(cash: cash)) }
        auctions[i].bids.append(AuctionBid(bidder: buyer, amount: price, at: now))
        auctions[i].endsAt = now
    }

    @discardableResult
    public mutating func list(_ itemID: String, startPrice: Int, reserve: Int?, buyNow: Int? = nil, duration: AuctionDuration, now: Double, cabinet: inout Cabinet) throws -> Auction {
        if let problem = AuctionRules.listingProblem(startPrice: startPrice, reserve: reserve, buyNow: buyNow) { throw AuctionError.badPrice(problem) }
        guard let item = cabinet.remove(itemID) else { throw AuctionError.notYours }
        let a = Auction(id: "A\(nextNumber)", item: item, seller: me, startPrice: startPrice, reserve: reserve, buyNow: buyNow, startsAt: now,
                        endsAt: now + duration.seconds, duration: duration)
        nextNumber += 1
        auctions.append(a)
        return a
    }

    @discardableResult
    public mutating func addOther(item: ArtifactItem, seller: String, startPrice: Int, reserve: Int?, buyNow: Int? = nil, duration: AuctionDuration, startsAt: Double, endsAt: Double) -> Int {
        auctions.append(Auction(id: "A\(nextNumber)", item: item, seller: seller, startPrice: startPrice, reserve: reserve, buyNow: buyNow, startsAt: startsAt, endsAt: endsAt, duration: duration))
        nextNumber += 1
        return auctions.count - 1
    }

    public mutating func cancel(_ auctionID: String, cabinet: inout Cabinet) throws {
        guard let i = index(auctionID), auctions[i].status == .live else { throw AuctionError.notLive }
        guard auctions[i].seller == me else { throw AuctionError.notYours }
        guard auctions[i].bids.isEmpty else { throw AuctionError.hasBids }
        auctions[i].status = .cancelled
        cabinet.add(auctions[i].item)
    }

    @discardableResult
    public mutating func settleDue(now: Double, cash: Int, cabinet: inout Cabinet) -> [AuctionSettlement] {
        var out: [AuctionSettlement] = []
        var money: Int = cash
        for i in auctions.indices where auctions[i].status == .live && auctions[i].endsAt <= now {
            let a: Auction = auctions[i]
            var payable = true
            if let top = a.bids.last, top.bidder == me { payable = top.amount <= money }
            let clean: Bool = a.bids.last.map { !linked(a.seller, $0.bidder) } ?? true
            if let top = a.bids.last, a.reserveMet, payable, clean {
                let fee: Int = AuctionRules.fee(forSale: top.amount)
                auctions[i].status = .sold
                auctions[i].soldFor = top.amount
                feesBurned += fee
                var done: [ArtifactCollection] = []
                var change = 0
                if top.bidder == me {
                    change -= top.amount
                    done = cabinet.add(a.item)
                }
                if a.seller == me { change += top.amount - fee }
                money += change
                out.append(AuctionSettlement(auctionID: a.id, item: a.item, status: .sold, price: top.amount, fee: fee, seller: a.seller, winner: top.bidder, cash: change, completed: done))
            } else {
                auctions[i].status = .unsold
                var done: [ArtifactCollection] = []
                if a.seller == me { done = cabinet.add(a.item) }
                out.append(AuctionSettlement(auctionID: a.id, item: a.item, status: .unsold, price: a.currentPrice, fee: 0, seller: a.seller, winner: nil, cash: 0, completed: done))
            }
        }
        return out
    }
}

public enum AuctionMarket {
    public static let slotSeconds: Double = 30
    public static let targetListings = 9
    private static let longestCatchUp: Double = 2 * 86_400

    private static func roll(_ key: String) -> Double { HashedRandom.first("auction|" + key) }

    public static func suggestedStart(_ r: BoxRarity, priceLevel: Double) -> Int { tidy(Double(basePrice(r)) * priceLevel) }

    static func basePrice(_ r: BoxRarity) -> Int {
        switch r {
        case .common: return 300
        case .rare: return 1_200
        case .epic: return 4_000
        case .legendary: return 15_000
        }
    }

    static func tidy(_ v: Double) -> Int {
        let n: Int = max(1, Int(v.rounded()))
        var step = 1
        while step * 100 <= n { step *= 10 }
        return max(1, n / step * step)
    }

    @discardableResult
    public static func advance(_ book: inout AuctionBook, cash: Int, cabinet: inout Cabinet, from last: Double, to now: Double,
                               players: [String], priceLevel: Double = 1) -> [AuctionSettlement] {
        guard now > last, players.count >= 3 else { return [] }
        var settled: [AuctionSettlement] = []
        var money: Int = cash
        func settle(_ time: Double) {
            let done = book.settleDue(now: time, cash: money, cabinet: &cabinet)
            money += done.reduce(0) { $0 + $1.cash }
            settled += done
        }
        let first: Double = max(last, now - longestCatchUp)
        var slot: Int = Int((first / slotSeconds).rounded(.down)) + 1
        let lastSlot: Int = Int((now / slotSeconds).rounded(.down))
        while slot <= lastSlot {
            let t: Double = Double(slot) * slotSeconds
            settle(t)
            for i in book.auctions.indices where book.auctions[i].status == .live && book.auctions[i].startsAt <= t { botTurn(&book, i, slot: slot, t: t, players: players) }
            slot += 1
        }
        settle(now)
        topUp(&book, now: now, players: players, priceLevel: priceLevel)
        return settled
    }

    private static func botTurn(_ book: inout AuctionBook, _ i: Int, slot: Int, t: Double, players: [String]) {
        let a: Auction = book.auctions[i]
        let key: String = a.id
        let appetite: Double = 0.4 + roll(key + "|app") * 1.2
        var ceiling = Double(a.startPrice) * (1.3 + roll(key + "|cap") * 2.2)
        if let r = a.reserve { ceiling = roll(key + "|res") < 0.6 ? max(ceiling, Double(r) * 1.25) : min(ceiling, Double(r) * 0.9) }
        var p: Double = 0.025 * appetite
        let left: Double = a.endsAt - t
        if left < 300 { p += 0.10 * appetite }
        if a.leader == book.me { p += 0.07 * appetite }
        if a.bids.isEmpty && left > a.duration.seconds * 0.5 { p *= 0.5 }
        guard roll("\(key)|go|\(slot)") < p else { return }
        let steps: Int = roll("\(key)|st|\(slot)") < 0.2 ? 1 + Int(roll("\(key)|sx|\(slot)") * 2) : 0
        let min0: Int = AuctionRules.minimumBid(a)
        let amount: Int = min0 + steps * AuctionRules.increment(at: min0)
        guard Double(amount) <= ceiling else { return }
        let candidates: [String] = players.filter { $0 != a.seller && $0 != a.leader && $0 != book.me }
        guard !candidates.isEmpty else { return }
        let who: String = candidates[min(candidates.count - 1, Int(roll("\(key)|who|\(slot)") * Double(candidates.count)))]
        _ = try? book.place(a.id, bidder: who, amount: amount, now: t)
    }

    private static func topUp(_ book: inout AuctionBook, now: Double, players: [String], priceLevel: Double) {
        var live: Int = book.auctions.filter { $0.status == .live && $0.seller != book.me }.count
        while live < targetListings {
            let n: Int = book.nextNumber
            let key = "list\(n)"
            let rr: Double = roll(key + "|rar")
            let rarity: BoxRarity = rr < 0.55 ? .common : rr < 0.85 ? .rare : rr < 0.97 ? .epic : .legendary
            let pool: [ArtifactDef] = ArtifactCatalog.defs(of: rarity)
            let def: ArtifactDef = pool[min(pool.count - 1, Int(roll(key + "|def") * Double(pool.count)))]
            let item = ArtifactItem(defID: def.id, serial: ArtifactCatalog.serial(of: def, roll: roll(key + "|ser")))
            let startPrice: Int = tidy(Double(basePrice(rarity)) * priceLevel * (0.7 + roll(key + "|sp") * 0.7))
            let reserve: Int? = roll(key + "|hasres") < 0.3 ? tidy(Double(startPrice) * (1.4 + roll(key + "|rs") * 1.2)) : nil
            let buyNow: Int? = roll(key + "|hasbn") < 0.3 ? max(tidy(Double(startPrice) * (2.2 + roll(key + "|bn") * 1.6)), reserve ?? 0) : nil
            let duration: AuctionDuration = AuctionDuration.allCases[min(2, Int(roll(key + "|dur") * 3))]
            let elapsedShare: Double = book.auctions.isEmpty || live < targetListings / 2 ? roll(key + "|el") * 0.9 : roll(key + "|el") * 0.15
            let started: Double = now - duration.seconds * elapsedShare
            let seller: String = players[min(players.count - 1, Int(roll(key + "|sel") * Double(players.count)))]
            let idx: Int = book.addOther(item: item, seller: seller, startPrice: startPrice, reserve: reserve, buyNow: buyNow, duration: duration, startsAt: started, endsAt: started + duration.seconds)
            var slot: Int = Int((started / slotSeconds).rounded(.down)) + 1
            let lastSlot: Int = Int((now / slotSeconds).rounded(.down))
            while slot <= lastSlot, book.auctions[idx].status == .live {
                botTurn(&book, idx, slot: slot, t: Double(slot) * slotSeconds, players: players)
                slot += 1
            }
            live += 1
        }
    }
}
