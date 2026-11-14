import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum CompanySale {
    public struct Offer: Identifiable, Equatable {
        public var id: Int
        public var kind: String
        public var buyer: String
        public var price: Double
        public var note: String
        public var expiresWeek: Int
        public var countered: Bool
        public var maxPrice: Double = 0
        public var patience: Int = 3
        public var talk: [TalkLine] = []
    }
    public struct TalkLine: Equatable {
        public var mine: Bool
        public var system: Bool = false
        public var text: String
    }
    public struct Listing: Equatable {
        public var companyID: Int
        public var since: Int
        public var offers: [Offer]
        public var pct: Int = 100
        public var route: String = "private"
        public var reserve: Double = 0
        public var round: Int = 0
        public var hasFee: Bool { route == "auction" }
    }

    public static let auctionFee = 0.03
    public static let youngWeeks = 52

    static func saleWorth(_ s: GameState, _ co: Company, data: GameData, factor: Double) -> Double {
        let value = max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
        return value * (s.week - co.foundedWeek < youngWeeks ? min(1, factor) : factor)
    }

    public static func listing(_ s: GameState, companyID: Int) -> Listing? {
        guard let raw = (s.rest["sales"]?.array ?? []).first(where: { $0["co"].int == companyID }) else { return nil }
        return Listing(companyID: companyID, since: raw["w0"].int,
                       offers: raw["offers"].array.map {
                           Offer(id: $0["id"].int, kind: $0["k"].string, buyer: $0["name"].string, price: $0["price"].double, note: $0["note"].string,
                                 expiresWeek: $0["exp"].int, countered: $0["ctr"].bool, maxPrice: $0["max"].double,
                                 patience: $0["pat"].isNull ? 3 : $0["pat"].int,
                                 talk: $0["talk"].array.map { TalkLine(mine: $0["me"].bool, system: $0["sys"].bool, text: $0["t"].string) })
                       }, pct: raw["pct"].isNull ? 100 : raw["pct"].int,
                       route: raw["m"].string == "auction" ? "auction" : "private", reserve: raw["res"].double, round: raw["rnd"].int)
    }

    public static func estimatedValue(_ s: GameState, companyID: Int, data: GameData) -> Double {
        guard let co = s.company(companyID) else { return 0 }
        return max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
    }

    public static func canSell(_ s: GameState, companyID: Int) -> Bool { SaleListings.canSell(s, companyID: companyID) }

    static func write(_ s: inout GameState, _ list: [JSONValue]) { s.rest["sales"] = .array(list) }

    @discardableResult
    public static func startListing(_ s: inout GameState, companyID: Int, pct: Int = 100) -> Bool {
        SaleListings.start(&s, companyID: companyID, route: "private", pct: pct)
    }

    public static func withdraw(_ s: inout GameState, companyID: Int) {
        write(&s, (s.rest["sales"]?.array ?? []).filter { $0["co"].int != companyID })
    }

    static func update(_ s: inout GameState, companyID: Int, _ body: (inout JSONValue) -> Void) {
        var list = s.rest["sales"]?.array ?? []
        if let k = list.firstIndex(where: { $0["co"].int == companyID }) { body(&list[k]); write(&s, list) }
    }

    public static func decline(_ s: inout GameState, companyID: Int, offerID: Int) {
        update(&s, companyID: companyID) { l in l["offers"] = .array(l["offers"].array.filter { $0["id"].int != offerID }) }
    }

    public static func counter(_ s: inout GameState, companyID: Int, offerID: Int) {
        guard let o = listing(s, companyID: companyID)?.offers.first(where: { $0.id == offerID }), !o.countered else { return }
        let ok = s.random.chance(o.kind == "rival" || o.kind == "fund" ? 0.55 : 0.4)
        update(&s, companyID: companyID) { l in
            var offers = l["offers"].array
            guard let k = offers.firstIndex(where: { $0["id"].int == offerID }) else { return }
            if ok {
                offers[k]["price"] = .number((o.price * 1.08 / 1000).rounded() * 1000)
                offers[k]["note"] = .string("Accepted your counter-offer.")
                offers[k]["ctr"] = .number(1)
            } else { offers.remove(at: k) }
            l["offers"] = .array(offers)
        }
        if !ok { s.note("\(o.buyer) walked away.", tone: "n", companyID: companyID) }
    }

    @discardableResult
    public static func accept(_ s: inout GameState, companyID: Int, offerID: Int, data: GameData, context fc: FinanceContext) -> Double? {
        guard let l = listing(s, companyID: companyID), let o = l.offers.first(where: { $0.id == offerID }), let i = s.companyIndex(companyID) else { return nil }
        if Shareholders.isBlocked(s, companyID: companyID) { return nil }
        let board = SaleListings.isBoardListing(s, companyID: companyID)
        if l.pct >= 100 {
            if !board, SaleListings.boardBlock(s, companyID: companyID) != nil { return nil }
            if board {
                let floor = estimatedValue(s, companyID: companyID, data: data) * JVRules.lowestSaleShare
                if o.price < floor {
                    s.note("The board of \(s.companies[i].name) will not sell for less than \(Int(JVRules.lowestSaleShare * 100))% of what it is worth. Wait for a better offer.", tone: "n", companyID: companyID)
                    return nil
                }
                s.rest["jvgo"] = .number(Double(companyID))
            }
        }
        defer { if board { s.rest["jvgo"] = nil } }
        let fee = l.hasFee ? jsRound(o.price * auctionFee) : 0
        if l.pct < 100 {
            sellPart(&s, companyIndex: i, pct: Double(l.pct), amount: o.price - fee, buyer: o.buyer, data: data, context: fc)
            withdraw(&s, companyID: companyID)
            return o.price - fee
        }
        guard let got = complete(&s, companyIndex: i, buyer: o.buyer, price: o.price, data: data, context: fc) else { return nil }
        if fee > 0 { Payments.playerPays(&s, fee, label: "Auction fee") }
        if o.price > s.companies[i].injectedCapital * 1.3 { Funding.bump(&s, "exits") }
        withdraw(&s, companyID: companyID)
        return got - fee
    }

    @discardableResult
    public static func hammer(_ s: inout GameState, companyID: Int, data: GameData, context fc: FinanceContext) -> Double? {
        guard let l = listing(s, companyID: companyID), let best = l.offers.max(by: { $0.price < $1.price }) else { return nil }
        return accept(&s, companyID: companyID, offerID: best.id, data: data, context: fc)
    }

    @discardableResult
    static func complete(_ s: inout GameState, companyIndex i: Int, buyer: String, price: Double, data: GameData, context fc: FinanceContext) -> Double? {
        guard s.companies[i].status.isLive, SaleListings.boardBlock(s, companyID: s.companies[i].id) == nil else { return nil }
        HeldMoney.settle(&s, companyID: s.companies[i].id)
        let co = s.companies[i]
        let mine = co.ownership / 100
        let proceeds = jsRound(price * mine)
        let shortfall = loansNotTakenOver(s, co, data: data)
        let gain = max(0, proceeds - shortfall - max(0, co.injectedCapital) * mine)
        Payments.ownerReceivesSale(&s, from: co, amount: proceeds, gain: gain, label: "Sold \(co.name) (\(buyer))")
        if shortfall > 0 { Payments.playerPays(&s, shortfall, label: "Loans of \(co.name) repaid on sale", companyID: co.id) }
        for l in s.loans.filter({ $0.companyID == co.id }) { Banking.close(loanID: l.id, repaid: l.balance, state: &s) }
        for m in s.companies[i].staff { if var p = s.people[m.id] { p.employerID = 0; s.people[m.id] = p } }
        s.companies[i].staff = []
        if let mid = co.managerID, var p = s.people[mid] { p.employerID = 0; s.people[mid] = p }
        s.companies[i].status = .sold
        s.stats.companiesSold += 1
        for k in s.inbox.indices where s.inbox[k].companyID == co.id && s.inbox[k].status == "open" { s.inbox[k].set("status", "done") }
        s.note("Sold \(co.name) for \(fc.homeCurrency(s).display(proceeds)) to \(buyer).", tone: "good")
        if buyer != "Dissolution" { JointVenture.announceSale(&s, company: co, price: price, buyer: buyer, context: fc) }
        return proceeds
    }

    /// A buyer pays for the shares and takes over the company's loans only as far as the business is worth before them.
    /// The rest is repaid out of the sale, so borrowed money never leaves with the seller.
    public static func loansNotTakenOver(_ s: GameState, _ co: Company, data: GameData) -> Double {
        let owed = s.loans.filter { $0.companyID == co.id }.reduce(0) { $0 + $1.balance }
        guard owed > 0 else { return 0 }
        return jsRound(max(0, owed - Valuation.valueBeforeLoans(co, state: s, trades: data.catalog)))
    }

    static func sellPart(_ s: inout GameState, companyIndex i: Int, pct: Double, amount: Double, buyer: String, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i]
        let t = CapTable.table(co)
        let moved = CapTable.sellFromYou(&s, i, shares: Int(saturating: (Double(t.you) * pct / 100).rounded()), to: buyer, paid: amount)
        let pts = Double(moved) / Double(t.total) * 100
        Payments.ownerReceivesSale(&s, from: co, amount: amount, gain: amount - co.injectedCapital * pts / 100, label: "Sold \(Int(pct))% of \(co.name)")
        if pts >= 20 { Funding.addBoardSeats(&s, i, 1) }
        s.note("Sold \(Int(pct))% of your shares in \(co.name) to \(buyer) for \(fc.currency(co.countryCode, s).display(amount)).", tone: "good", companyID: co.id)
    }

    public static func talkAsk(_ s: inout GameState, companyID: Int, offerID: Int, question: String) {
        guard let o = listing(s, companyID: companyID)?.offers.first(where: { $0.id == offerID }) else { return }
        let staffAnswer = ["rival": "We would merge it with ours. Some jobs will go.", "fund": "We keep the team and the name. We want it to grow.", "private": "I want to run it as it is.", "angel": "The team stays, but I want a say."][o.kind] ?? "They stay for now."
        let payAnswer = "Cash on closing."
        updateOffer(&s, companyID: companyID, offerID: offerID) { off in
            var talk = off["talk"].array
            talk.append(.object(["me": 1, "t": .string(question == "staff" ? "What happens to my staff?" : "How would you pay?")]))
            talk.append(.object(["me": 0, "t": .string(question == "staff" ? staffAnswer : payAnswer)]))
            off["talk"] = .array(talk)
        }
    }

    public enum TalkResult: Equatable { case unchanged, agreed(Double), stretched(Double), refused, walkedAway }

    @discardableResult
    public static func talkCounter(_ s: inout GameState, companyID: Int, offerID: Int, price: Double) -> TalkResult {
        guard let l = listing(s, companyID: companyID), let o = l.offers.first(where: { $0.id == offerID }) else { return .unchanged }
        let ask = (price / 1000).rounded() * 1000
        let mx = o.maxPrice > 0 ? o.maxPrice : (o.price * (1 + s.random.range(o.kind == "rival" || o.kind == "fund" ? 0.06 : 0.02, o.kind == "rival" ? 0.22 : 0.14)) / 1000).rounded() * 1000
        var newPrice = o.price, result = TalkResult.unchanged, reply = ""
        var talk = Negotiation.State()
        var walked = false
        let t = Negotiation.temperament(personality: nil, key: "sale:\(offerID)")
        let patience = Negotiation.patience(rank: "deal", temperament: t)
        var left = o.patience
        if ask <= o.price { reply = "That is what we offered. Shall we sign?" }
        else {
            let stored = s.rest["sales"]?.array.first(where: { $0["co"].int == companyID })?["offers"].array.first(where: { $0["id"].int == offerID })?["neg"] ?? .null
            if !stored.isNull { talk = Negotiation.State(json: stored) }
            let position = Negotiation.Position(opening: o.price, reservation: mx, direction: .lower)
            let reply0 = Negotiation.respond(offer: ask, position: position, temperament: t, rank: "deal", state: &talk, week: s.week, step: 1000, random: &s.random)
            left = max(0, patience - talk.round)
            switch reply0.answer {
            case .accept: newPrice = ask; reply = "Fine. \(Int(ask)) it is."; result = .agreed(ask); talk = Negotiation.State()
            case .counter(let c):
                if reply0.unrealistic || c.amount <= o.price { reply = "We stay at \(Int(o.price)). That is what it is worth to us."; result = .refused }
                else { newPrice = min(mx, c.amount); reply = "We can stretch to \(Int(newPrice)). That is about as far as we go."; result = .stretched(newPrice) }
            case .refuse: reply = "That is far above what it is worth to us."; result = .refused
            case .walkAway: walked = true
            }
        }
        updateOffer(&s, companyID: companyID, offerID: offerID) { off in
            var tl = off["talk"].array
            tl.append(.object(["me": 1, "t": .string("I want \(Int(ask)).")]))
            tl.append(.object(["me": 0, "t": .string(walked ? "I have heard enough. We are done." : reply)]))
            off["talk"] = .array(tl)
            off["max"] = .number(mx); off["price"] = .number(newPrice); off["pat"] = .number(Double(left))
            if talk.isOpen { off["neg"] = talk.json } else { off["neg"] = .null }
        }
        if walked {
            decline(&s, companyID: companyID, offerID: offerID)
            s.note("\(o.buyer) walked away.", tone: "n", companyID: companyID)
            return .walkedAway
        }
        return result
    }

    static func updateOffer(_ s: inout GameState, companyID: Int, offerID: Int, _ body: (inout JSONValue) -> Void) {
        update(&s, companyID: companyID) { l in
            var offers = l["offers"].array
            if let k = offers.firstIndex(where: { $0["id"].int == offerID }) { body(&offers[k]); l["offers"] = .array(offers) }
        }
    }

    static func traction(_ co: Company, _ s: GameState) -> Double {
        let e = CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week)
        let rev = (co.books.year["rev"] ?? 0) > 0 ? co.books.year["rev"]! : co.lastWeekRevenue * 52
        let mg = rev > 0 ? e / rev : -0.2
        let h = co.monthlyHistory.suffix(6).map { $0.revenue }
        let g = h.count >= 2 && h[0] > 0 ? h[h.count - 1] / h[0] - 1 : 0
        return clamp(0.25 + mg * 1.5 + clamp(g, -0.5, 1) * 0.6 + (co.reputation - 50) / 150 + min(0.2, Double(s.week - co.foundedWeek) / 260), 0, 1)
    }

    static let notes: [String: String] = [
        "angel": "A private investor who wants a say in big decisions.",
        "rival": "Strategic buyer. Pays well but may close it and keep only the customers.",
        "fund": "Wants to grow it and sell again. Keeps staff and the brand.",
        "private": "A private buyer who wants to run it themselves.",
        "player": "Another player who wants to run it."]

    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for raw in s.rest["sales"]?.array ?? [] {
            let id = raw["co"].int
            guard let i = s.companyIndex(id), s.companies[i].status.isLive else { withdraw(&s, companyID: id); continue }
            let route = raw["m"].string
            if route == "auction" { auctionWeek(&s, companyIndex: i, raw: raw, data: data, context: fc); continue }
            let pct = raw["pct"].isNull ? 100 : raw["pct"].int
            var offers = raw["offers"].array.filter { s.week < $0["exp"].int }
            if offers.count < 4 {
                let co = s.companies[i]
                let currency = fc.currency(co.countryCode, s)
                let tr = traction(co, s)
                let profit = CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week) > 0
                let hostedInv = StaffPerks.hosted(s, "inv")
                if s.random.chance(0.16 * (0.35 + tr) * (profit ? 1 : 0.45) * (1 + 0.35 * hostedInv)) {
                    let kinds = pct == 100 ? ["private", "fund", "rival"] : ["private", "fund", "angel"]
                    let k = s.random.pick(kinds)
                    let f: Double = { switch k { case "rival": return s.random.range(0.95, 1.18); case "fund": return s.random.range(0.82, 1.02)
                                                case "angel": return s.random.range(0.78, 0.98); default: return s.random.range(0.8, 1) } }() * (0.85 + tr * 0.3)
                    let name: String = k == "rival" ? "A rival in your trade" : k == "fund" ? "An investment fund" : k == "angel" ? "A private investor" : "A private buyer"
                    let worth = saleWorth(s, co, data: data, factor: f * BrandValues.salePremium(BrandValues.company(s, co).score) * (1 + 0.04 * hostedInv))
                    let price = ((pct == 100 ? worth : worth * Double(pct) / 100 * co.ownership / 100) / 1000).rounded() * 1000
                    if price > 0 {
                        offers.append(.object(["id": .number(Double(s.makeID())), "k": .string(k), "name": .string(name), "price": .number(price), "note": .string(notes[k] ?? ""),
                                               "exp": .number(Double(s.week + 6)), "ctr": .number(0)]))
                        s.addMessage(from: name, title: "Offer for \(pct == 100 ? co.name : "\(pct)% of \(co.name)")", body: "\(name) offers \(currency.display(pct == 100 ? price * co.ownership / 100 : price)) for your stake.", companyID: co.id, tone: "good")
                    }
                }
            }
            update(&s, companyID: id) { $0["offers"] = .array(offers) }
        }
        var keep: [JSONValue] = []
        for d in s.rest["deferred"]?.array ?? [] {
            guard s.week >= d["w"].int else { keep.append(d); continue }
            Payments.playerReceives(&s, jsRound(d["amt"].double), label: "Paid back for \(d["name"].string)")
            s.note("The money still owed for \(d["name"].string) has been paid.", tone: "good")
        }
        s.rest["deferred"] = keep.isEmpty ? nil : .array(keep)
    }

    static let fundNames = ["Northgate Capital", "Ashford Partners", "Bluewater Equity", "Kestrel Growth Fund", "Harbour Street Investments"]
    static let buyerNames = ["A family business from the area", "An entrepreneur expanding nearby", "A retired owner looking for a new venture", "A private buyer with cash ready"]
    static let angelNames = ["A business angel", "A private investor", "An investor who wants a say"]

    static func bidLimit(_ s: GameState, _ co: Company, pct: Int, kind: String, u: Double, data: GameData, context fc: FinanceContext) -> Double {
        let tr = traction(co, s)
        let hostedInv = StaffPerks.hosted(s, "inv")
        let f: Double = { switch kind { case "rival": return 0.95 + 0.23 * u; case "fund": return 0.82 + 0.2 * u
                                        case "angel": return 0.78 + 0.2 * u; default: return 0.8 + 0.2 * u } }()
        let worth = saleWorth(s, co, data: data, factor: f * BrandValues.salePremium(BrandValues.company(s, co).score) * (0.85 + tr * 0.3) * (1 + 0.04 * hostedInv))
        return pct == 100 ? worth : worth * Double(pct) / 100 * co.ownership / 100
    }

    @discardableResult
    public static func startAuction(_ s: inout GameState, companyID: Int, reserve: Double, pct: Int = 100, data: GameData, context fc: FinanceContext) -> Bool {
        guard let i = s.companyIndex(companyID), reserve > 0, SaleListings.routeProblem(s, companyID: companyID, route: "auction", pct: pct) == nil else { return false }
        let co = s.companies[i]
        let w0 = s.week
        let kinds = pct == 100 ? ["rival", "fund", "private"] : ["private", "fund", "angel"]
        let rivals = (s.rest["mk"]?[co.type + "|" + co.cityID]["riv"].array ?? []).filter { !$0["name"].string.isEmpty }
        let n = 3 + (HashedRandom.first("auc:n:\(companyID):\(w0)") < 0.5 ? 1 : 0)
        var bd: [JSONValue] = []
        for k in 0..<n {
            let kind = kinds[k % kinds.count]
            let u = HashedRandom.first("auc:u:\(companyID):\(w0):\(k)"), v = HashedRandom.first("auc:v:\(companyID):\(w0):\(k)")
            var name = ""
            switch kind {
            case "rival": name = rivals.isEmpty ? "A rival in your trade" : rivals[Int(v * Double(rivals.count)) % rivals.count]["name"].string
            case "fund": name = fundNames[Int(v * Double(fundNames.count)) % fundNames.count]
            case "angel": name = angelNames[Int(v * Double(angelNames.count)) % angelNames.count]
            default: name = buyerNames[Int(v * Double(buyerNames.count)) % buyerNames.count]
            }
            if bd.contains(where: { $0["name"].string == name }) { name += " (\(k + 1))" }
            bd.append(.object(["id": .number(Double(s.makeID())), "k": .string(kind), "name": .string(name),
                               "lim": .number(bidLimit(s, co, pct: pct, kind: kind, u: u, data: data, context: fc))]))
        }
        guard SaleListings.start(&s, companyID: companyID, route: "auction", pct: pct, extra: ["res": .number(reserve), "rnd": 0, "bd": .array(bd)]) else { return false }
        s.note("\(co.name) is up for auction: \(n) bidders are registered. The first bids come in now.", tone: "n", companyID: companyID)
        if let raw = (s.rest["sales"]?.array ?? []).first(where: { $0["co"].int == companyID }) { auctionWeek(&s, companyIndex: i, raw: raw, data: data, context: fc) }
        return true
    }

    static func auctionWeek(_ s: inout GameState, companyIndex i: Int, raw: JSONValue, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i], id = co.id, w0 = raw["w0"].int
        let rnd = raw["rnd"].int
        if rnd >= 3 {
            let left = raw["offers"].array.filter { s.week < $0["exp"].int }
            if left.isEmpty { withdraw(&s, companyID: id); s.note("The auction of \(co.name) ended with no sale.", tone: "n", companyID: id) }
            else { update(&s, companyID: id) { $0["offers"] = .array(left) } }
            return
        }
        let r = rnd + 1
        let pct = raw["pct"].isNull ? 100 : raw["pct"].int
        let reserve = raw["res"].double
        let currency = fc.currency(co.countryCode, s)
        var bd = raw["bd"].array
        let old = raw["offers"].array
        var offers: [JSONValue] = []
        for k in bd.indices where !bd[k]["out"].bool {
            if r > 1 && HashedRandom.first("auc:drop:\(id):\(w0):\(r):\(k)") < (r == 2 ? 0.15 : 0.25) { bd[k]["out"] = .number(1); s.note("\(bd[k]["name"].string) dropped out of the auction of \(co.name).", tone: "n", companyID: id); continue }
            let jitter = 0.97 + 0.06 * HashedRandom.first("auc:p:\(id):\(w0):\(r):\(k)")
            let price = (bd[k]["lim"].double * (0.78 + 0.07 * Double(r)) * jitter / 1000).rounded() * 1000
            guard price >= reserve else { continue }
            var o: JSONValue = old.first(where: { $0["id"].int == bd[k]["id"].int }) ?? .object(["id": bd[k]["id"], "k": bd[k]["k"], "name": bd[k]["name"], "ctr": 0])
            o["price"] = .number(max(price, o["ctr"].bool ? o["price"].double : 0))
            o["note"] = .string("Round \(r) of 3. " + (notes[bd[k]["k"].string] ?? ""))
            o["exp"] = .number(Double(s.week + (r < 3 ? 2 : 3)))
            offers.append(o)
        }
        update(&s, companyID: id) { l in l["rnd"] = .number(Double(r)); l["bd"] = .array(bd); l["offers"] = .array(offers) }
        if let top = offers.max(by: { $0["price"].double < $1["price"].double }) {
            s.note("Auction of \(co.name), round \(r) of 3: top bid \(currency.display(pct == 100 ? top["price"].double * co.ownership / 100 : top["price"].double)) from \(top["name"].string). Hammer now, or wait for the next round.", tone: "good", companyID: id)
        } else { s.note("Auction of \(co.name), round \(r) of 3: no bid has reached your reserve.", tone: "n", companyID: id) }
        if r == 1 && !raw["heard"].bool {
            update(&s, companyID: id) { $0["heard"] = .number(1) }
            let m = co.value("mood").isNull ? 60 : co.num("mood")
            s.companies[i].set("mood", clamp(m - 8, 0, 100))
        }
    }

    public enum Method: String, CaseIterable, Sendable { case offers, auction, ipo }

    public struct Quote: Equatable, Sendable {
        public var method: Method
        public var pct: Int
        public var companyValue: Double
        public var stakeValue: Double
        public var expected: Double
        public var fee: Double
        public var tax: Double
        public var youGet: Double
        public var ownershipAfter: Double
        public var reserve: Double
        public var problem: String?
        public var lines: [String]
    }

    public static func quote(_ s: GameState, companyID: Int, pct: Int, method: Method, data: GameData, context fc: FinanceContext) -> Quote? {
        guard let co = s.company(companyID) else { return nil }
        let p = min(100, max(10, pct))
        let value = max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
        let share = Double(p) / 100
        let stake = value * co.ownership / 100 * share
        let basis = max(0, co.injectedCapital) * co.ownership / 100 * share
        let rate = fc.homeCountry(s).capitalGainsTax
        var q = Quote(method: method, pct: p, companyValue: value, stakeValue: stake, expected: 0, fee: 0, tax: 0, youGet: 0,
                      ownershipAfter: co.ownership * (1 - share), reserve: 0, problem: nil, lines: [])
        switch method {
        case .offers:
            q.problem = SaleListings.routeProblem(s, companyID: companyID, route: "private", pct: p) ?? (Shareholders.isBlocked(s, companyID: companyID) ? "The other owners block big moves for now." : nil)
            q.expected = stake * 0.9
            q.lines = ["Buyers make offers over the next weeks. You can answer, counter or wait. Nothing is paid before you accept."]
        case .auction:
            q.problem = SaleListings.routeProblem(s, companyID: companyID, route: "auction", pct: p) ?? (Shareholders.isBlocked(s, companyID: companyID) ? "The other owners block big moves for now." : nil)
            q.expected = stake
            q.fee = q.expected * auctionFee
            q.reserve = ((p == 100 ? value : stake) * 0.85 / 1000).rounded() * 1000
            q.lines = ["Bidders compete over three weekly rounds. You set the lowest price you accept, and a fee of \(Int(auctionFee * 100))% is paid when it sells."]
        case .ipo:
            q.problem = PublicCompany.problem(s, companyID: companyID, pct: p, data: data, context: fc)
            if let o = PublicCompany.offering(s, companyID: companyID, pct: p, data: data, context: fc) {
                q.expected = o.gross; q.fee = o.fee; q.tax = o.tax; q.youGet = o.net; q.ownershipAfter = o.ownershipAfter
                q.lines = ["New owners buy at \(Int(PublicCompany.discount * 100))% under the fair price. You keep control while you hold more than half.",
                           "After the listing the company publishes results every quarter and the board pays a dividend by the payout you choose."]
                return q
            }
        }
        let gain = max(0, q.expected - q.fee - basis)
        q.tax = gain * rate
        q.youGet = q.expected - q.fee - q.tax
        return q
    }

    public enum StartResult: Equatable, Sendable { case started, refused(String) }

    @discardableResult
    public static func start(_ s: inout GameState, companyID: Int, pct: Int, method: Method, reserve: Double, data: GameData, context fc: FinanceContext) -> StartResult {
        guard let q = quote(s, companyID: companyID, pct: pct, method: method, data: data, context: fc) else { return .refused("No such company.") }
        if let why = q.problem { return .refused(why) }
        switch method {
        case .offers:
            return startListing(&s, companyID: companyID, pct: q.pct) ? .started : .refused("It cannot be put on the market now.")
        case .auction:
            return startAuction(&s, companyID: companyID, reserve: reserve > 0 ? reserve : q.reserve, pct: q.pct, data: data, context: fc) ? .started : .refused("The auction could not start.")
        case .ipo:
            if let why = PublicCompany.goPublic(&s, companyID: companyID, pct: q.pct, data: data, context: fc) { return .refused(why) }
            return .started
        }
    }
}
