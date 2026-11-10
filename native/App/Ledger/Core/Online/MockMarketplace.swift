import Foundation
import GameCore

actor MockMarketBook {
    static let shared = MockMarketBook()

    private struct Seed { var title: String, kind: String, family: String, price: Double, cond: Double, age: Int, km: Int }
    private static let seeds: [Seed] = [
        Seed(title: "Volvo V70 estate", kind: "car", family: "Car", price: 38_000, cond: 0.62, age: 9, km: 188_000),
        Seed(title: "Ford Transit panel van", kind: "van", family: "Van", price: 64_000, cond: 0.55, age: 7, km: 214_000),
        Seed(title: "Cessna 172 Skyhawk", kind: "plane", family: "Plane", price: 1_450_000, cond: 0.7, age: 21, km: 0),
        Seed(title: "Beneteau Oceanis 38", kind: "boat", family: "Boat", price: 890_000, cond: 0.66, age: 11, km: 0),
        Seed(title: "Heavy duty pizza oven", kind: "equipment", family: "Oven", price: 24_000, cond: 0.8, age: 3, km: 0),
        Seed(title: "Vintage dive watch", kind: "luxury", family: "Watch", price: 120_000, cond: 0.9, age: 12, km: 0),
        Seed(title: "Peugeot 308", kind: "car", family: "Car", price: 52_000, cond: 0.74, age: 5, km: 96_000),
        Seed(title: "Mercedes Sprinter", kind: "van", family: "Van", price: 98_000, cond: 0.6, age: 8, km: 240_000),
    ]
    private static let sellers: [(String, String)] = [("Ingrid Solheim", "NO"), ("Oliver Whitfield", "UK"), ("Camille Laurent", "FR"), ("Erik Lindqvist", "SE"),
                                                       ("Magnus Berg", "NO"), ("Priya Shah", "UK"), ("Manon Girard", "FR"), ("Mikkel Jensen", "DK")]

    private var listings: [PlayerListing] = []
    private var deals: [MarketDeal] = []
    private var queue: [OnlineSettlementRow] = []
    private var answerAt: [String: Date] = [:]
    private var seeded = false
    private var counter = 0

    private func next(_ p: String) -> String { counter += 1; return "\(p)-mock-\(counter)" }

    private func seed() {
        guard !seeded else { return }
        seeded = true
        for (i, s) in Self.seeds.enumerated() {
            let who = Self.sellers[i % Self.sellers.count]
            let item: JSONValue = .object(["id": .string("mk-seed-\(i)"), "kind": .string(s.kind), "title": .string(s.title), "family": .string(s.family), "ref": .string(""),
                                           "lux": .bool(s.kind == "luxury"), "age": .number(Double(s.age)), "km": .number(Double(s.km)), "seen": .number(s.cond),
                                           "cond": .number(s.cond), "base": .number(s.price * 1.3)])
            listings.append(PlayerListing(id: "mkl-seed-\(i)", sellerID: "mkp-\(i)", sellerName: who.0, sellerCode: nil, avatarColour: i % 8, avatarIcon: nil, sellerCountry: who.1,
                                          sellerLevel: 5 + i * 2, sellerOnline: i % 3 != 2, sellerLastSeen: Date().timeIntervalSince1970 - Double(i * 900), kind: s.kind, title: s.title,
                                          item: item, price: s.price, currency: "NOK", status: "active", postedAt: Date().timeIntervalSince1970 - Double(i * 40_000),
                                          mine: false, offerUsed: false, myDeal: nil))
        }
    }

    private func visible() -> [PlayerListing] {
        seed()
        if FakePlayers.removed { return listings.filter { (l: PlayerListing) -> Bool in l.mine } }
        return listings
    }

    private func dealFor(_ id: String) -> MarketDeal? { deals.first { (d: MarketDeal) -> Bool in d.id == id } }

    private func decorated(_ l: PlayerListing) -> PlayerListing {
        var x = l
        x.myDeal = deals.last { (d: MarketDeal) -> Bool in d.listingID == l.id && d.isBuyer }
        x.offerUsed = deals.contains { (d: MarketDeal) -> Bool in d.listingID == l.id && d.isBuyer && d.kind == "offer" }
        return x
    }

    private func settleDue() {
        let now = Date()
        for (id, at) in answerAt where at <= now {
            answerAt[id] = nil
            guard let i = deals.firstIndex(where: { (d: MarketDeal) -> Bool in d.id == id }), deals[i].status == "pending", deals[i].isBuyer,
                  let li = listings.firstIndex(where: { (l: PlayerListing) -> Bool in l.id == deals[i].listingID }), listings[li].status == "active" else { continue }
            let accept = deals[i].price >= listings[li].price * 0.88
            if accept {
                complete(i, li, price: deals[i].price)
            } else if deals[i].kind == "offer" {
                deals[i].status = "discussing"
                deals[i].specialPrice = (listings[li].price * 0.94).rounded()
            } else {
                deals[i].status = "declined"
                queue.append(OnlineSettlementRow(id: next("n"), amount: 0, currency: deals[i].currency, kind: "market_refund", label: "\(deals[i].otherName) declined. Your money is back.",
                                                 meta: .object(["dealID": .string(deals[i].id), "title": .string("Deal declined"), "tone": .string("n")])))
            }
        }
    }

    private func complete(_ i: Int, _ li: Int, price: Double) {
        deals[i].status = "accepted"
        deals[i].finalPrice = price
        listings[li].status = "sold"
        var item = listings[li].item
        if case .object(var o) = item { o["title"] = .string(listings[li].title); o["kind"] = .string(listings[li].kind); item = .object(o) }
        queue.append(OnlineSettlementRow(id: next("n"), amount: 0, currency: deals[i].currency, kind: "market_purchase",
                                         label: "You bought \(listings[li].title) for \(Int(price)).",
                                         meta: .object(["dealID": .string(deals[i].id), "price": .number(price), "item": item, "title": .string("Bought: " + listings[li].title), "tone": .string("good")])))
    }

    func browse(kind: String?) -> [PlayerListing] {
        settleDue()
        return visible().filter { (l: PlayerListing) -> Bool in l.status == "active" && (kind == nil || l.kind == kind) }.map(decorated)
    }

    func mine() -> MarketState {
        settleDue()
        _ = visible()
        return MarketState(listings: listings.filter { (l: PlayerListing) -> Bool in l.mine }, incoming: [], outgoing: deals.filter { (d: MarketDeal) -> Bool in d.isBuyer }.reversed())
    }

    func list(item: JSONValue, price: Double, currency: String) throws -> PlayerListing {
        seed()
        guard price > 0 else { throw OnlineError.rejected("Check the price.") }
        if listings.contains(where: { (l: PlayerListing) -> Bool in l.mine && l.status == "active" && l.itemID == item["id"].string }) { throw OnlineError.rejected("This is already on offer.") }
        let l = PlayerListing(id: next("mkl"), sellerID: "me", sellerName: "You", sellerCode: nil, avatarColour: 0, avatarIcon: nil, sellerCountry: nil, sellerLevel: nil, sellerOnline: true,
                              sellerLastSeen: nil, kind: item["kind"].string, title: item["title"].string, item: item, price: price, currency: currency, status: "active",
                              postedAt: Date().timeIntervalSince1970, mine: true, offerUsed: false, myDeal: nil)
        listings.append(l)
        return l
    }

    func cancel(_ id: String) throws {
        guard let i = listings.firstIndex(where: { (l: PlayerListing) -> Bool in l.id == id && l.mine }) else { throw OnlineError.notFound }
        listings[i].status = "cancelled"
        queue.append(OnlineSettlementRow(id: next("n"), amount: 0, currency: listings[i].currency, kind: "market_unlist", label: "Your listing was taken down.",
                                         meta: .object(["itemID": .string(listings[i].itemID), "title": .string("Listing closed"), "tone": .string("n")])))
    }

    private func open(_ id: String, kind: String, price: Double) throws -> MarketDeal {
        settleDue()
        guard let l = visible().first(where: { (x: PlayerListing) -> Bool in x.id == id && x.status == "active" }) else { throw OnlineError.notFound }
        if l.mine { throw OnlineError.rejected("You cannot buy your own listing or one from a linked account.") }
        if deals.contains(where: { (d: MarketDeal) -> Bool in d.listingID == id && d.isBuyer && d.isOpen }) { throw OnlineError.rejected("You already have a deal open on this.") }
        if kind == "offer" {
            if deals.contains(where: { (d: MarketDeal) -> Bool in d.listingID == id && d.isBuyer && d.kind == "offer" }) { throw OnlineError.rejected("You have already made your offer on this.") }
            if price >= l.price { throw OnlineError.rejected("An offer has to be lower than the asking price.") }
            if price < l.price * 0.4 { throw OnlineError.rejected("That offer is too far below the asking price.") }
        }
        let d = MarketDeal(id: next("mkd"), listingID: id, role: "buyer", kind: kind, price: price, specialPrice: nil, finalPrice: nil, status: "pending", title: l.title, itemKind: l.kind,
                           family: l.family, currency: l.currency, listingPrice: l.price, listingStatus: "active", otherID: l.sellerID, otherName: l.sellerName, otherCode: nil,
                           otherOnline: l.sellerOnline, createdAt: Date().timeIntervalSince1970, answeredAt: nil)
        deals.append(d)
        answerAt[d.id] = Date().addingTimeInterval(Double.random(in: 20...90))
        return d
    }

    func buy(_ id: String) throws -> MarketDeal {
        guard let l = visible().first(where: { (x: PlayerListing) -> Bool in x.id == id }) else { throw OnlineError.notFound }
        return try open(id, kind: "buy", price: l.price)
    }

    func offer(_ id: String, price: Double) throws -> MarketDeal { try open(id, kind: "offer", price: price) }

    func answer(_ id: String, accept: Bool) throws -> MarketResult {
        settleDue()
        guard let i = deals.firstIndex(where: { (d: MarketDeal) -> Bool in d.id == id && d.status == "discussing" }),
              let li = listings.firstIndex(where: { (l: PlayerListing) -> Bool in l.id == deals[i].listingID }) else { throw OnlineError.notFound }
        let special = deals[i].specialPrice ?? deals[i].price
        if accept {
            complete(i, li, price: special)
            return MarketResult(status: "accepted", dealID: id, price: special, specialPrice: nil)
        }
        deals[i].status = "withdrawn"
        queue.append(OnlineSettlementRow(id: next("n"), amount: 0, currency: deals[i].currency, kind: "market_refund", label: "You turned the price down. Your money is back.",
                                         meta: .object(["dealID": .string(id), "title": .string("Deal closed"), "tone": .string("n")])))
        return MarketResult(status: "withdrawn", dealID: id, price: nil, specialPrice: nil)
    }

    func withdraw(_ id: String) throws -> MarketResult {
        guard let i = deals.firstIndex(where: { (d: MarketDeal) -> Bool in d.id == id && d.isOpen && d.isBuyer }) else { throw OnlineError.notFound }
        deals[i].status = "withdrawn"
        answerAt[id] = nil
        queue.append(OnlineSettlementRow(id: next("n"), amount: 0, currency: deals[i].currency, kind: "market_refund", label: "You withdrew the request. Your money is back.",
                                         meta: .object(["dealID": .string(id), "title": .string("Deal closed"), "tone": .string("n")])))
        return MarketResult(status: "withdrawn", dealID: id, price: nil, specialPrice: nil)
    }

    func pending() -> [OnlineSettlementRow] { settleDue(); return queue }
    func acknowledge(_ ids: [String]) { queue.removeAll { (r: OnlineSettlementRow) -> Bool in ids.contains(r.id) } }
}

extension MockOnlineService {
    func marketBrowse(kind: String?) async throws -> [PlayerListing] { await MockMarketBook.shared.browse(kind: kind) }
    func marketMine() async throws -> MarketState { await MockMarketBook.shared.mine() }
    func marketList(item: JSONValue, price: Double, currency: String) async throws -> PlayerListing { try await MockMarketBook.shared.list(item: item, price: price, currency: currency) }
    func marketCancel(listingID: String) async throws { try await MockMarketBook.shared.cancel(listingID) }
    func marketBuy(listingID: String) async throws -> MarketDeal { try await MockMarketBook.shared.buy(listingID) }
    func marketOffer(listingID: String, price: Double) async throws -> MarketDeal { try await MockMarketBook.shared.offer(listingID, price: price) }
    func marketRespond(dealID: String, reply: MarketReply, price: Double?) async throws -> MarketResult { throw OnlineError.rejected("That cannot be done now.") }
    func marketAnswer(dealID: String, accept: Bool) async throws -> MarketResult { try await MockMarketBook.shared.answer(dealID, accept: accept) }
    func marketWithdraw(dealID: String) async throws -> MarketResult { try await MockMarketBook.shared.withdraw(dealID) }
}
