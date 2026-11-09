import Foundation
import GameCore

// Artifact auctions: timed, in gold. A bid is held while it leads and returned when beaten; a bid in the last two minutes extends the
// auction; the sale carries a fee that leaves the economy. Times are seconds (any fixed origin). Nothing here knows about screens.

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
    /// Hidden minimum: below it the item is not sold. Bidders only learn whether it has been met.
    public var reserve: Int?
    public var startsAt: Double
    public var endsAt: Double
    public var duration: AuctionDuration
    public var bids: [AuctionBid] = []
    public var extensions = 0
    public var status: Status = .live
    /// The price a sale closed at (set when sold).
    public var soldFor: Int?

    public var currentPrice: Int { bids.last?.amount ?? startPrice }
    public var leader: String? { bids.last?.bidder }
    public var reserveMet: Bool { reserve == nil || currentPrice >= (reserve ?? 0) && !bids.isEmpty }
    public func secondsLeft(at now: Double) -> Double { max(0, endsAt - now) }
    public func isLive(at now: Double) -> Bool { status == .live && now < endsAt }
}

public enum AuctionError: Error, Equatable, Sendable {
    case notLive, sellerCannotBid, linkedAccount, alreadyLeading, tooLow(minimum: Int), notEnoughGold(missing: Int)
    case notYours, hasBids, badPrice(String)
}

extension AuctionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notLive: return "This auction has ended."
        case .sellerCannotBid: return "You cannot bid on your own auction."
        case .linkedAccount: return "You cannot bid on an auction of a linked account."
        case .alreadyLeading: return "You already lead this auction."
        case .tooLow(let m): return "The lowest bid is \(m) gold."
        case .notEnoughGold(let m): return "You are \(m) gold short."
        case .notYours: return "That piece is not in your cabinet."
        case .hasBids: return "It has bids, so it cannot be taken back."
        case .badPrice(let why): return why
        }
    }
}

public enum AuctionRules {
    public static let feePercent = 10
    /// A bid this close to the end pushes the end out to this many seconds after the bid.
    public static let antiSnipeWindow: Double = 120
    /// After this many extensions the end stays where it is, so an auction cannot run for ever.
    public static let maxExtensions = 12
    public static let minimumStartPrice = 10

    /// The smallest step by which a new bid must beat the price.
    public static func increment(at price: Int) -> Int {
        switch price {
        case ..<100: return 5
        case ..<500: return 10
        case ..<2_000: return 25
        case ..<10_000: return 100
        default: return 500
        }
    }

    /// The lowest bid that is allowed now: the start price for the first bid, else the price plus one increment.
    public static func minimumBid(_ a: Auction) -> Int { a.bids.isEmpty ? a.startPrice : a.currentPrice + increment(at: a.currentPrice) }

    /// The fee on a sale: 10%, never less than 1 gold. It is removed from the economy.
    public static func fee(forSale price: Int) -> Int { price <= 0 ? 0 : max(1, price * feePercent / 100) }
    public static func proceeds(forSale price: Int) -> Int { price - fee(forSale: price) }

    /// The end after a bid at `time`: pushed to `time + window` if inside the window and extensions remain.
    public static func extendedEnd(endsAt: Double, extensions: Int, bidAt time: Double) -> (end: Double, extended: Bool) {
        guard extensions < maxExtensions, endsAt - time <= antiSnipeWindow else { return (endsAt, false) }
        let end: Double = time + antiSnipeWindow
        return end > endsAt ? (end, true) : (endsAt, false)
    }

    /// Why a listing is not allowed, in words; nil when it is.
    public static func listingProblem(startPrice: Int, reserve: Int?) -> String? {
        if startPrice < minimumStartPrice { return "The start price is at least \(minimumStartPrice) gold." }
        if let r = reserve {
            if r < startPrice { return "The reserve cannot be below the start price." }
            if r > startPrice * 50 { return "The reserve is too far above the start price." }
        }
        return nil
    }

    /// What a bid would do, shown before it is placed.
    public struct BidPreview: Equatable, Sendable {
        public var amount: Int
        public var minimum: Int
        public var allowed: Bool
        public var problem: String?
        /// Gold held after the bid (everything else stays spendable).
        public var heldAfter: Int
        public var availableAfter: Int
        public var extendsAuction: Bool
        public var newEnd: Double
        public var reserveMetAfter: Bool
    }

    public static func preview(_ a: Auction, amount: Int, bidder: String, wallet: GoldWallet, now: Double, linked: Bool = false) -> BidPreview {
        let minimum: Int = minimumBid(a)
        var problem: String?
        let mineNow: Int = a.leader == bidder ? a.currentPrice : 0
        if !a.isLive(at: now) { problem = "This auction has ended." }
        else if a.seller == bidder { problem = "You cannot bid on your own auction." }
        else if linked { problem = "You cannot bid on an auction of a linked account." }
        else if a.leader == bidder { problem = "You already lead with \(a.currentPrice) gold." }
        else if amount < minimum { problem = "The lowest bid is \(minimum) gold." }
        else if amount > wallet.available + mineNow { problem = "You are \(amount - wallet.available - mineNow) gold short." }
        let ext = extendedEnd(endsAt: a.endsAt, extensions: a.extensions, bidAt: now)
        return BidPreview(amount: amount, minimum: minimum, allowed: problem == nil, problem: problem,
                          heldAfter: wallet.held - mineNow + amount, availableAfter: wallet.available + mineNow - amount,
                          extendsAuction: ext.extended, newEnd: ext.end, reserveMetAfter: a.reserve == nil || amount >= (a.reserve ?? 0))
    }
}

extension AuctionRules {
    /// The fee in words, for the listing screen: shown before anything is listed.
    public static var feeText: String {
        "A sale costs the seller a fee of \(feePercent)% of the price (at least 1 gold). The fee is taken out of the game for good."
    }

    /// What listing a piece would do, shown before it is listed ("If you do this, this will happen").
    public struct ListingPreview: Equatable, Sendable {
        public var problem: String?
        /// What the seller keeps if it sells at the start price, and at the reserve.
        public var proceedsAtStart: Int
        public var proceedsAtReserve: Int?
        public var lines: [String]
    }

    public static func listingPreview(startPrice: Int, reserve: Int?, duration: AuctionDuration) -> ListingPreview {
        let problem = listingProblem(startPrice: startPrice, reserve: reserve)
        var lines: [String] = [
            "The piece leaves your cabinet while it is on sale, for \(duration.title).",
            "Bidders' gold is held while they lead and returned when they are beaten.",
            feeText,
            "A bid in the last \(Int(antiSnipeWindow / 60)) minutes pushes the end out to \(Int(antiSnipeWindow / 60)) minutes after that bid, at most \(maxExtensions) times."
        ]
        if reserve != nil { lines.append("Bidders are told only whether your reserve has been met, not what it is. Below it the piece is not sold and comes back to you.") }
        lines.append("Accounts linked to yours cannot bid on it.")
        return ListingPreview(problem: problem, proceedsAtStart: proceeds(forSale: startPrice), proceedsAtReserve: reserve.map { proceeds(forSale: $0) }, lines: lines)
    }
}

extension AuctionBook {
    /// The preview of a bid, with the link rule applied.
    public func previewBid(_ auctionID: String, amount: Int, bidder: String, wallet: GoldWallet, now: Double) -> AuctionRules.BidPreview? {
        guard let a = auction(auctionID) else { return nil }
        return AuctionRules.preview(a, amount: amount, bidder: bidder, wallet: wallet, now: now, linked: a.seller != bidder && linked(a.seller, bidder))
    }
}

/// How an auction ended, for the people it touches.
public struct AuctionSettlement: Equatable, Sendable {
    public var auctionID: String
    public var item: ArtifactItem
    public var status: Auction.Status
    public var price: Int
    public var fee: Int
    public var seller: String
    public var winner: String?
    /// Collections the winner (the player) completed with this piece.
    public var completed: [ArtifactCollection]

    public static func == (a: AuctionSettlement, b: AuctionSettlement) -> Bool {
        a.auctionID == b.auctionID && a.status == b.status && a.price == b.price && a.fee == b.fee && a.winner == b.winner && a.seller == b.seller
    }
}

/// All auctions plus the rules that move gold and pieces. Only the player (`me`) has a wallet and a cabinet here; other bidders are
/// stand-ins with no limits, which is why `place` takes the wallet only to touch it when `me` is involved.
public struct AuctionBook: Codable, Equatable, Sendable {
    public var me: String
    public var auctions: [Auction] = []
    /// Fees taken over the life of the book: gold that left the economy.
    public var feesBurned = 0
    public var nextNumber = 1
    /// Accounts that share an owner carry the same key (account id to key). Linked accounts cannot trade with each other here: that would be wash
    /// trading, a way to move gold or pieces between your own accounts or to push a price up. An account without a key counts as its own.
    public var linkKeys: [String: String]?

    public init(me: String) { self.me = me }

    public func linkKey(of account: String) -> String { linkKeys?[account] ?? account }

    /// True for the same account or two accounts of one owner.
    public func linked(_ a: String, _ b: String) -> Bool { a == b || linkKey(of: a) == linkKey(of: b) }

    public func auction(_ id: String) -> Auction? { auctions.first { $0.id == id } }

    private func index(_ id: String) -> Int? { auctions.firstIndex { $0.id == id } }

    /// Places a bid. For the player the amount is held in the wallet; a beaten player's hold is returned at once.
    @discardableResult
    public mutating func place(_ auctionID: String, bidder: String, amount: Int, now: Double, wallet: inout GoldWallet) throws -> (extended: Bool, newEnd: Double) {
        guard let i = index(auctionID), auctions[i].isLive(at: now) else { throw AuctionError.notLive }
        let a: Auction = auctions[i]
        if a.seller == bidder { throw AuctionError.sellerCannotBid }
        if linked(a.seller, bidder) { throw AuctionError.linkedAccount }
        if a.leader == bidder { throw AuctionError.alreadyLeading }
        let minimum: Int = AuctionRules.minimumBid(a)
        if amount < minimum { throw AuctionError.tooLow(minimum: minimum) }
        if bidder == me {
            if amount > wallet.available { throw AuctionError.notEnoughGold(missing: amount - wallet.available) }
            wallet.hold(amount)
        }
        if let prev = a.bids.last, prev.bidder == me, bidder != me { wallet.release(prev.amount) }
        let ext = AuctionRules.extendedEnd(endsAt: a.endsAt, extensions: a.extensions, bidAt: now)
        auctions[i].bids.append(AuctionBid(bidder: bidder, amount: amount, at: now))
        if ext.extended { auctions[i].endsAt = ext.end; auctions[i].extensions += 1 }
        return (ext.extended, auctions[i].endsAt)
    }

    /// Lists a piece from the player's cabinet (it leaves the cabinet while on sale).
    @discardableResult
    public mutating func list(_ itemID: String, startPrice: Int, reserve: Int?, duration: AuctionDuration, now: Double, cabinet: inout Cabinet) throws -> Auction {
        if let problem = AuctionRules.listingProblem(startPrice: startPrice, reserve: reserve) { throw AuctionError.badPrice(problem) }
        guard let item = cabinet.remove(itemID) else { throw AuctionError.notYours }
        let a = Auction(id: "A\(nextNumber)", item: item, seller: me, startPrice: startPrice, reserve: reserve, startsAt: now,
                        endsAt: now + duration.seconds, duration: duration)
        nextNumber += 1
        auctions.append(a)
        return a
    }

    /// Adds a listing by someone else (the stand-in market).
    @discardableResult
    public mutating func addOther(item: ArtifactItem, seller: String, startPrice: Int, reserve: Int?, duration: AuctionDuration, startsAt: Double, endsAt: Double) -> Int {
        auctions.append(Auction(id: "A\(nextNumber)", item: item, seller: seller, startPrice: startPrice, reserve: reserve, startsAt: startsAt, endsAt: endsAt, duration: duration))
        nextNumber += 1
        return auctions.count - 1
    }

    /// Takes a listing of the player's back while nobody has bid.
    public mutating func cancel(_ auctionID: String, cabinet: inout Cabinet) throws {
        guard let i = index(auctionID), auctions[i].status == .live else { throw AuctionError.notLive }
        guard auctions[i].seller == me else { throw AuctionError.notYours }
        guard auctions[i].bids.isEmpty else { throw AuctionError.hasBids }
        auctions[i].status = .cancelled
        cabinet.add(auctions[i].item)
    }

    /// Closes every auction whose time is up. Sold: the winner pays (a held bid becomes the payment), the seller gets the price less the fee,
    /// the fee is burned and the piece changes hands. Unsold (no bids, or reserve not met): holds are returned and the piece goes back.
    @discardableResult
    public mutating func settleDue(now: Double, wallet: inout GoldWallet, cabinet: inout Cabinet) -> [AuctionSettlement] {
        var out: [AuctionSettlement] = []
        for i in auctions.indices where auctions[i].status == .live && auctions[i].endsAt <= now {
            let a: Auction = auctions[i]
            // A bid is paid out of the hold. If the hold is short, the rest must be spendable; if it is not, or the winner turned out linked
            // to the seller, the sale does not happen and every hold is returned.
            var payable = true
            if let top = a.bids.last, top.bidder == me { payable = wallet.held >= top.amount || top.amount - wallet.held <= wallet.available }
            let clean: Bool = a.bids.last.map { !linked(a.seller, $0.bidder) } ?? true
            if let top = a.bids.last, a.reserveMet, payable, clean {
                let fee: Int = AuctionRules.fee(forSale: top.amount)
                auctions[i].status = .sold
                auctions[i].soldFor = top.amount
                feesBurned += fee
                var done: [ArtifactCollection] = []
                if top.bidder == me {
                    let heldBefore: Int = wallet.held
                    wallet.spendHeld(top.amount)
                    if heldBefore < top.amount { wallet.spend(top.amount - heldBefore) }
                    done = cabinet.add(a.item)
                }
                if a.seller == me { wallet.credit(top.amount - fee) }
                out.append(AuctionSettlement(auctionID: a.id, item: a.item, status: .sold, price: top.amount, fee: fee, seller: a.seller, winner: top.bidder, completed: done))
            } else {
                auctions[i].status = .unsold
                if let top = a.bids.last, top.bidder == me { wallet.release(top.amount) }
                var done: [ArtifactCollection] = []
                if a.seller == me { done = cabinet.add(a.item) }
                out.append(AuctionSettlement(auctionID: a.id, item: a.item, status: .unsold, price: a.currentPrice, fee: 0, seller: a.seller, winner: nil, completed: done))
            }
        }
        return out
    }
}

/// The stand-in market: other players list pieces and bid on each other's and the player's auctions as time passes. Deterministic from
/// the book's state and the time, so it can be tested. A real server replaces all of this.
public enum AuctionMarket {
    public static let slotSeconds: Double = 30
    /// Live auctions by other players the market keeps topped up.
    public static let targetListings = 9
    private static let longestCatchUp: Double = 2 * 86_400

    private static func roll(_ key: String) -> Double { HashedRandom.first("auction|" + key) }

    private static func basePrice(_ r: BoxRarity) -> Int {
        switch r {
        case .common: return 20
        case .rare: return 80
        case .epic: return 300
        case .legendary: return 1_200
        }
    }

    /// Rounds a price to a tidy number.
    static func tidy(_ v: Double) -> Int {
        let n = Int(v.rounded())
        if n >= 1_000 { return n / 50 * 50 }
        if n >= 100 { return n / 10 * 10 }
        return max(AuctionRules.minimumStartPrice, n / 5 * 5)
    }

    /// Moves the market from `last` to `now`: bids of other players slot by slot, endings, and new listings.
    @discardableResult
    public static func advance(_ book: inout AuctionBook, wallet: inout GoldWallet, cabinet: inout Cabinet, from last: Double, to now: Double,
                               players: [String]) -> [AuctionSettlement] {
        guard now > last, players.count >= 3 else { return [] }
        var settled: [AuctionSettlement] = []
        let first: Double = max(last, now - longestCatchUp)
        var slot: Int = Int((first / slotSeconds).rounded(.down)) + 1
        let lastSlot: Int = Int((now / slotSeconds).rounded(.down))
        while slot <= lastSlot {
            let t: Double = Double(slot) * slotSeconds
            settled += book.settleDue(now: t, wallet: &wallet, cabinet: &cabinet)
            for i in book.auctions.indices where book.auctions[i].status == .live && book.auctions[i].startsAt <= t { botTurn(&book, i, slot: slot, t: t, players: players, wallet: &wallet) }
            slot += 1
        }
        settled += book.settleDue(now: now, wallet: &wallet, cabinet: &cabinet)
        topUp(&book, now: now, players: players, wallet: &wallet)
        return settled
    }

    /// One slot of one auction: maybe a stand-in bidder bids. Each auction has a private ceiling past which nobody bids, and a hidden
    /// appetite that makes some auctions busy and some quiet; the last minutes are busier, and the player's lead draws a counter-bid.
    private static func botTurn(_ book: inout AuctionBook, _ i: Int, slot: Int, t: Double, players: [String], wallet: inout GoldWallet) {
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
        _ = try? book.place(a.id, bidder: who, amount: amount, now: t, wallet: &wallet)
    }

    private static func topUp(_ book: inout AuctionBook, now: Double, players: [String], wallet: inout GoldWallet) {
        var live: Int = book.auctions.filter { $0.status == .live && $0.seller != book.me }.count
        while live < targetListings {
            let n: Int = book.nextNumber
            let key = "list\(n)"
            let rr: Double = roll(key + "|rar")
            let rarity: BoxRarity = rr < 0.55 ? .common : rr < 0.85 ? .rare : rr < 0.97 ? .epic : .legendary
            let pool: [ArtifactDef] = ArtifactCatalog.defs(of: rarity)
            let def: ArtifactDef = pool[min(pool.count - 1, Int(roll(key + "|def") * Double(pool.count)))]
            let item = ArtifactItem(defID: def.id, serial: ArtifactCatalog.serial(of: def, roll: roll(key + "|ser")))
            let startPrice: Int = tidy(Double(basePrice(rarity)) * (0.7 + roll(key + "|sp") * 0.7))
            let reserve: Int? = roll(key + "|hasres") < 0.3 ? tidy(Double(startPrice) * (1.4 + roll(key + "|rs") * 1.2)) : nil
            let duration: AuctionDuration = AuctionDuration.allCases[min(2, Int(roll(key + "|dur") * 3))]
            let elapsedShare: Double = book.auctions.isEmpty || live < targetListings / 2 ? roll(key + "|el") * 0.9 : roll(key + "|el") * 0.15
            let started: Double = now - duration.seconds * elapsedShare
            let seller: String = players[min(players.count - 1, Int(roll(key + "|sel") * Double(players.count)))]
            let idx: Int = book.addOther(item: item, seller: seller, startPrice: startPrice, reserve: reserve, duration: duration, startsAt: started, endsAt: started + duration.seconds)
            // Let the bidders catch up on the time already gone.
            var slot: Int = Int((started / slotSeconds).rounded(.down)) + 1
            let lastSlot: Int = Int((now / slotSeconds).rounded(.down))
            while slot <= lastSlot, book.auctions[idx].status == .live {
                botTurn(&book, idx, slot: slot, t: Double(slot) * slotSeconds, players: players, wallet: &wallet)
                slot += 1
            }
            live += 1
        }
    }
}
