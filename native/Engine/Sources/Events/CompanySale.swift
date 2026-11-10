import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Selling a whole company. Original: features/player/selling_startups_and_crisis.js (the sale screen) and
/// engine/world/deals.js (`acceptSale`). You put a company on the market, privately or through a broker; buyers make
/// offers over the next weeks (each open six weeks); you accept, counter once (+8%) or decline. Listings live in
/// `state.rest["sales"]`, earn-outs in `state.rest["deferred"]`.
///
/// Selling part of your shares works the same way (`pct` < 100, limited companies only; the buyer pays you personally and takes
/// a share of the company). Raising funding from investors (new shares, money into the company) is in `Funding`.
/// Routes (the listing's `m`): a quiet handshake ("private"), a broker (4% fee, word gets out), an auction ("auction": a reserve, three weekly
/// bidding rounds with named bidders; hammer any time or wait for higher bids, but bidders drop out), and a management buyout ("mbo").
/// A merger with a rival and a sale to a rival group are direct deals (`mergeWithRival`, `GroupDeals.sellToGroup`). Every route ends in `complete` or `sellPart`.
/// The buyer talk of the original (`V.saletalk`: ask about staff or payment, name your price, patience) is `talkAsk` and `talkCounter`.
public enum CompanySale {
    public struct Offer: Identifiable, Equatable {
        public var id: Int
        public var kind: String          // private, fund, rival, mbo
        public var buyer: String
        public var price: Double         // for the whole company
        public var note: String
        public var expiresWeek: Int
        public var countered: Bool
        /// What the buyer will pay at most, and how many times you can overreach before they leave. Set when the talk starts.
        public var maxPrice: Double = 0
        public var patience: Int = 3
        public var talk: [TalkLine] = []
        /// Set when the bidder is a rival group (the sale then goes through `GroupDeals.sellToGroup`).
        public var group: String = ""
    }
    /// One line of the buyer talk: `mine` = you said it; `system` = a notice.
    public struct TalkLine: Equatable {
        public var mine: Bool
        public var system: Bool = false
        public var text: String
    }
    public struct Listing: Equatable {
        public var companyID: Int
        public var broker: Bool
        public var since: Int
        public var offers: [Offer]
        /// 100 = the whole company, else the percent of YOUR shares that is for sale.
        public var pct: Int = 100
        /// private, broker, auction or mbo.
        public var route: String = "private"
        /// Auction: the lowest whole-company price you accept (for a stake sale, the price of the stake), and the bidding round (0...3).
        public var reserve: Double = 0
        public var round: Int = 0
        /// Broker and auction cost 4% of the price.
        public var hasFee: Bool { route == "broker" || route == "auction" }
    }

    public static let brokerFee = 0.04
    public static let youngWeeks = 52

    static func saleWorth(_ s: GameState, _ co: Company, data: GameData, factor: Double) -> Double {
        let value = max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
        let cash = min(value, max(0, co.cash))
        let goodwillFactor = s.week - co.foundedWeek < youngWeeks ? min(1, factor) : factor
        return cash * min(1, factor) + (value - cash) * goodwillFactor
    }

    // MARK: Reading

    public static func listing(_ s: GameState, companyID: Int) -> Listing? {
        guard let raw = (s.rest["sales"]?.array ?? []).first(where: { $0["co"].int == companyID }) else { return nil }
        return Listing(companyID: companyID, broker: raw["m"].string == "broker", since: raw["w0"].int,
                       offers: raw["offers"].array.map {
                           Offer(id: $0["id"].int, kind: $0["k"].string, buyer: $0["name"].string, price: $0["price"].double, note: $0["note"].string,
                                 expiresWeek: $0["exp"].int, countered: $0["ctr"].bool, maxPrice: $0["max"].double,
                                 patience: $0["pat"].isNull ? 3 : $0["pat"].int,
                                 talk: $0["talk"].array.map { TalkLine(mine: $0["me"].bool, system: $0["sys"].bool, text: $0["t"].string) },
                                 group: $0["gid"].string)
                       }, pct: raw["pct"].isNull ? 100 : raw["pct"].int,
                       route: ["broker", "auction", "mbo"].contains(raw["m"].string) ? raw["m"].string : "private", reserve: raw["res"].double, round: raw["rnd"].int)
    }

    /// Value as shown on the sale screen: what a buyer would pay for the whole company.
    public static func estimatedValue(_ s: GameState, companyID: Int, data: GameData) -> Double {
        guard let co = s.company(companyID) else { return 0 }
        return max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
    }

    public static func canSell(_ s: GameState, companyID: Int) -> Bool { SaleListings.canSell(s, companyID: companyID) }

    // MARK: Listing

    static func write(_ s: inout GameState, _ list: [JSONValue]) { s.rest["sales"] = .array(list) }

    @discardableResult
    public static func startListing(_ s: inout GameState, companyID: Int, broker: Bool, pct: Int = 100) -> Bool {
        SaleListings.start(&s, companyID: companyID, route: broker ? "broker" : "private", pct: pct)
    }
    /// List with a route: "private", "broker" or "mbo" (an auction is `startAuction`). Only limited companies sell part of their shares; keep at least 1%.
    @discardableResult
    public static func startListing(_ s: inout GameState, companyID: Int, route: String, pct: Int = 100) -> Bool {
        guard ["private", "broker", "mbo"].contains(route) else { return false }
        return SaleListings.start(&s, companyID: companyID, route: route, pct: pct)
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

    /// Ask for 8% more, once. Some buyers walk away. Original: `ACT.salectr`.
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

    /// Accept an offer. Returns the cash you get, or nil if it is no longer possible.
    @discardableResult
    public static func accept(_ s: inout GameState, companyID: Int, offerID: Int, data: GameData, context fc: FinanceContext) -> Double? {
        guard let l = listing(s, companyID: companyID), let o = l.offers.first(where: { $0.id == offerID }), let i = s.companyIndex(companyID) else { return nil }
        if Shareholders.isBlocked(s, companyID: companyID) { return nil }   // the other owners block a sale for half a year
        // A company with partners is sold only through the listing its board voted for, and not for much less than it is worth.
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
        if l.pct < 100 {
            let fee = l.hasFee ? jsRound(o.price * brokerFee) : 0
            sellPart(&s, companyIndex: i, pct: Double(l.pct), amount: o.price - fee, buyer: o.buyer, data: data, context: fc)
            withdraw(&s, companyID: companyID)
            return o.price - fee
        }
        let fee = l.hasFee ? jsRound(o.price * brokerFee) : 0
        var got: Double?
        if o.group.isEmpty { got = complete(&s, companyIndex: i, buyer: o.buyer, price: o.price, mbo: o.kind == "mbo", data: data, context: fc) }
        else {
            let mine = jsRound(o.price * s.companies[i].ownership / 100)
            got = GroupDeals.sellToGroup(&s, companyIndex: i, groupID: o.group, price: o.price, data: data, context: fc) ? mine : nil
        }
        if let got = got {
            if fee > 0 { Payments.playerPays(&s, fee, label: l.route == "auction" ? "Auction fee" : "Broker fee") }
            if o.price > s.companies[i].injectedCapital * 1.3 { Funding.bump(&s, "exits") }
            withdraw(&s, companyID: companyID)
            return got - fee
        }
        return nil
    }

    /// Hammer down: take the highest bid standing now. Nil when nobody has bid.
    @discardableResult
    public static func hammer(_ s: inout GameState, companyID: Int, data: GameData, context fc: FinanceContext) -> Double? {
        guard let l = listing(s, companyID: companyID), let best = l.offers.max(by: { $0.price < $1.price }) else { return nil }
        return accept(&s, companyID: companyID, offerID: best.id, data: data, context: fc)
    }

    /// The sale itself: proceeds to you, loans closed, staff released. Original: `acceptSale`.
    /// With `mbo` a third of the price is lent back to the buyers and paid after two years.
    @discardableResult
    static func complete(_ s: inout GameState, companyIndex i: Int, buyer: String, price: Double, mbo: Bool = false, data: GameData, context fc: FinanceContext) -> Double? {
        guard s.companies[i].status.isLive, SaleListings.boardBlock(s, companyID: s.companies[i].id) == nil else { return nil }
        HeldMoney.settle(&s, companyID: s.companies[i].id)
        let co = s.companies[i]
        defer { if co.holdingID != 0 { HoldingModel.refreshAssets(&s, holdingID: co.holdingID, data: data) } }   // a sold company leaves the holding's assets at once
        let mine = co.ownership / 100
        let proceeds = jsRound(price * mine)
        let basis = max(0, co.injectedCapital)
        let gain = max(0, proceeds - basis * mine)
        var now = proceeds
        if mbo {
            let later = jsRound(proceeds / 3)
            now -= later
            var d = s.rest["deferred"]?.array ?? []
            d.append(.object(["w": .number(Double(s.week + 104)), "amt": .number(later), "name": .string(co.name), "hurdle": .number(0), "to": .number(Double(co.holdingID))]))
            s.rest["deferred"] = .array(d)
        }
        Payments.ownerReceivesSale(&s, from: co, amount: now, gain: gain, label: "Sold \(co.name) (\(buyer))")
        HoldingStakes.settleSale(&s, company: co, price: price)
        for l in s.loans.filter({ $0.companyID == co.id }) { Banking.close(loanID: l.id, repaid: l.balance, state: &s) }
        for m in s.companies[i].staff { if var p = s.people[m.id] { p.employerID = 0; s.people[m.id] = p } }
        s.companies[i].staff = []
        if let mid = co.managerID, var p = s.people[mid] { p.employerID = 0; s.people[mid] = p }
        s.companies[i].status = .sold
        Ledger.set(&s, .company(co.id), to: 0)
        s.stats.companiesSold += 1
        for k in s.inbox.indices where s.inbox[k].companyID == co.id && s.inbox[k].status == "open" { s.inbox[k].set("status", "done") }
        for k in s.companies.indices where s.companies[k].holdingID == co.id { s.companies[k].holdingID = 0 }
        HoldingStakes.releaseLines(&s, holdingID: co.id)
        s.note("Sold \(co.name) for \(fc.homeCurrency(s).display(proceeds)) to \(buyer).", tone: "good")
        if buyer != "Dissolution" { JointVenture.announceSale(&s, company: co, price: price, buyer: buyer, context: fc) }
        return now
    }

    /// Part of your shares go to a buyer; the cash is yours. Original: `sellPart`.
    static func sellPart(_ s: inout GameState, companyIndex i: Int, pct: Double, amount: Double, buyer: String, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i]
        let t = CapTable.table(co)
        let moved = CapTable.sellFromYou(&s, i, shares: Int(saturating: (Double(t.you) * pct / 100).rounded()), to: buyer, paid: amount)
        let pts = Double(moved) / Double(t.total) * 100
        Payments.ownerReceivesSale(&s, from: co, amount: amount, gain: amount - co.injectedCapital * pts / 100, label: "Sold \(Int(pct))% of \(co.name)")
        if pts >= 20 { Funding.addBoardSeats(&s, i, 1) }
        s.note("Sold \(Int(pct))% of your shares in \(co.name) to \(buyer) for \(fc.currency(co.countryCode, s).display(amount)).", tone: "good", companyID: co.id)
    }

    // MARK: The buyer talk (V.saletalk)

    /// Ask the buyer something. kind: "staff" or "pay". Original: `ACT.saleq`.
    public static func talkAsk(_ s: inout GameState, companyID: Int, offerID: Int, question: String) {
        guard let o = listing(s, companyID: companyID)?.offers.first(where: { $0.id == offerID }) else { return }
        let staffAnswer = ["rival": "We would merge it with ours. Some jobs will go.", "fund": "We keep the team and the name. We want it to grow.", "mbo": "I know everyone here. Nobody goes.",
                           "private": "I want to run it as it is.", "angel": "The team stays, but I want a say."][o.kind] ?? "They stay for now."
        let payAnswer = o.kind == "mbo" ? "Two thirds now, the rest as a seller loan over two years." : "Cash on closing."
        updateOffer(&s, companyID: companyID, offerID: offerID) { off in
            var talk = off["talk"].array
            talk.append(.object(["me": 1, "t": .string(question == "staff" ? "What happens to my staff?" : "How would you pay?")]))
            talk.append(.object(["me": 0, "t": .string(question == "staff" ? staffAnswer : payAnswer)]))
            off["talk"] = .array(talk)
        }
    }

    public enum TalkResult: Equatable { case unchanged, agreed(Double), stretched(Double), refused, walkedAway }

    /// Name your price. At or below the offer: they ask you to sign. Up to their limit: they agree. Above it the buyer answers through the shared
    /// `Negotiation` (it is a buyer, so it wants the price down): it stretches towards a figure it can pay, usually one it can really pay and now and then
    /// an unrealistic one that does not move the offer; an insulting ask is refused; and when its patience is gone it walks away. Original: `ACT.salecounter`.
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

    // MARK: Weekly

    /// How well the company is doing in the eyes of investors, 0...1. Original: `traction`.
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
        "mbo": "Management buyout. A third is paid as a seller loan over two years. Safe, loyal, slower to pay.",
        "private": "A private buyer who wants to run it themselves.",
        "player": "Another player who wants to run it."]

    /// Offers arrive; old ones lapse; earn-outs fall due. Original: `salesWeek`, `deferredWeek`.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for raw in s.rest["sales"]?.array ?? [] {
            let id = raw["co"].int
            guard let i = s.companyIndex(id), s.companies[i].status.isLive else { withdraw(&s, companyID: id); continue }
            let route = raw["m"].string
            if route == "auction" { auctionWeek(&s, companyIndex: i, raw: raw, data: data, context: fc); continue }
            let broker = route == "broker"
            let pct = raw["pct"].isNull ? 100 : raw["pct"].int
            var offers = raw["offers"].array.filter { s.week < $0["exp"].int }
            if offers.count < 4 {
                let co = s.companies[i]
                let currency = fc.currency(co.countryCode, s)
                let tr = traction(co, s)
                let profit = CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week) > 0
                let hostedInv = StaffPerks.hosted(s, "inv")   // investors you hosted: buyers come sooner and pay a little more
                // A buyout listing hears only from the manager, by a hash of the company and the week (no shared random rolls).
                let mboU = HashedRandom.first("mbo:\(id):\(s.week)")
                if route == "mbo" ? (offers.isEmpty && mboU < 0.3 && co.managerID != nil && s.people[co.managerID!] != nil) : s.random.chance((broker ? 0.42 : 0.16) * (0.35 + tr) * (profit ? 1 : 0.45) * (1 + 0.35 * hostedInv)) {
                    var kinds = pct == 100 ? ["private", "fund", "rival"] : ["private", "fund", "angel"]
                    if pct == 100, co.managerID != nil && s.people[co.managerID!] != nil { kinds.append("mbo") }
                    let k = route == "mbo" ? "mbo" : s.random.pick(kinds)
                    let f: Double = { switch k { case "rival": return s.random.range(0.95, 1.18); case "fund": return s.random.range(0.82, 1.02)
                                                case "mbo": return route == "mbo" ? 0.62 + 0.18 * mboU : s.random.range(0.62, 0.8); case "angel": return s.random.range(0.78, 0.98); default: return s.random.range(0.8, 1) } }() * (broker ? 1.05 : 1) * (0.85 + tr * 0.3)
                    let name: String = k == "mbo" ? (s.people[co.managerID ?? 0]?.name ?? "Your manager") + ", your manager"
                        : k == "rival" ? "A rival in your trade" : k == "fund" ? "An investment fund" : k == "angel" ? "A private investor" : "A private buyer"
                    let worth = saleWorth(s, co, data: data, factor: f * BrandValues.salePremium(BrandValues.company(s, co).score) * (1 + 0.04 * hostedInv))
                    let price = ((pct == 100 ? worth : worth * Double(pct) / 100 * co.ownership / 100) / 1000).rounded() * 1000
                    if price > 0 {
                        offers.append(.object(["id": .number(Double(s.makeID())), "k": .string(k), "name": .string(name), "price": .number(price), "note": .string(notes[k] ?? ""),
                                               "exp": .number(Double(s.week + 6)), "ctr": .number(0)]))
                        s.addMessage(from: name, title: "Offer for \(pct == 100 ? co.name : "\(pct)% of \(co.name)")", body: "\(name) offers \(currency.display(pct == 100 ? price * co.ownership / 100 : price)) for your stake.", companyID: co.id, tone: "good")
                        if broker && !raw["heard"].bool {
                            update(&s, companyID: id) { $0["heard"] = .number(1) }
                            let m = co.value("mood").isNull ? 60 : co.num("mood")
                            s.companies[i].set("mood", clamp(m - 8, 0, 100))
                            s.note("Word is out that \(co.name) is for sale. Staff are uneasy and rivals are watching.", tone: "n", companyID: co.id)
                        }
                    }
                }
            }
            update(&s, companyID: id) { $0["offers"] = .array(offers) }
        }
        // Earn-outs
        var keep: [JSONValue] = []
        for d in s.rest["deferred"]?.array ?? [] {
            guard s.week >= d["w"].int else { keep.append(d); continue }
            let paid = jsRound(d["amt"].double)
            if d["to"].int != 0, let hi = s.companyIndex(d["to"].int), s.companies[hi].status.isLive {
                Ledger.moveRaw(&s, .company(d["to"].int), paid)
                s.companies[hi].addTransaction(week: s.week, amount: paid, label: "Paid back for \(d["name"].string)")
            } else { Payments.playerReceives(&s, paid, label: "Paid back for \(d["name"].string)") }
            s.note("The money still owed for \(d["name"].string) has been paid.", tone: "good")
        }
        s.rest["deferred"] = .array(keep)
    }

    // MARK: Auction

    static let fundNames = ["Northgate Capital", "Ashford Partners", "Bluewater Equity", "Kestrel Growth Fund", "Harbour Street Investments"]
    static let buyerNames = ["A family business from the area", "An entrepreneur expanding nearby", "A retired owner looking for a new venture", "A private buyer with cash ready"]
    static let angelNames = ["A business angel", "A private investor", "An investor who wants a say"]

    /// What a whole-company buyer would pay at most, by kind, in the units of the sale (the whole company, or the stake for a part sale).
    static func bidLimit(_ s: GameState, _ co: Company, pct: Int, kind: String, u: Double, data: GameData, context fc: FinanceContext) -> Double {
        let tr = traction(co, s)
        let hostedInv = StaffPerks.hosted(s, "inv")
        let f: Double = { switch kind { case "rival": return 0.95 + 0.23 * u; case "group": return 0.95 + 0.25 * u; case "fund": return 0.82 + 0.2 * u
                                        case "angel": return 0.78 + 0.2 * u; default: return 0.8 + 0.2 * u } }()
        let worth = saleWorth(s, co, data: data, factor: f * BrandValues.salePremium(BrandValues.company(s, co).score) * (0.85 + tr * 0.3) * (1 + 0.04 * hostedInv))
        return pct == 100 ? worth : worth * Double(pct) / 100 * co.ownership / 100
    }

    /// Run an auction: set the lowest price you accept (`reserve`); three weekly rounds of bids from named bidders follow. Bidders are drawn by a
    /// hash of the company and the week, so the same sale always draws the same field. Fee: 4%, and word gets out.
    @discardableResult
    public static func startAuction(_ s: inout GameState, companyID: Int, reserve: Double, pct: Int = 100, data: GameData, context fc: FinanceContext) -> Bool {
        guard let i = s.companyIndex(companyID), reserve > 0, SaleListings.routeProblem(s, companyID: companyID, route: "auction", pct: pct) == nil else { return false }
        let co = s.companies[i]
        let w0 = s.week
        var kinds = pct == 100 ? ["rival", "fund", "private"] : ["private", "fund", "angel"]
        let groups = pct == 100 ? GroupStakes.groups(s, country: co.countryCode).filter { $0["dist"].int == 0 } : []
        if !groups.isEmpty { kinds.append("group") }
        let rivals = (s.rest["mk"]?[co.type + "|" + co.cityID]["riv"].array ?? []).filter { !$0["name"].string.isEmpty }
        let n = 3 + (HashedRandom.first("auc:n:\(companyID):\(w0)") < 0.5 ? 1 : 0)
        var bd: [JSONValue] = []
        for k in 0..<n {
            let kind = kinds[k % kinds.count]
            let u = HashedRandom.first("auc:u:\(companyID):\(w0):\(k)"), v = HashedRandom.first("auc:v:\(companyID):\(w0):\(k)")
            var name = "", gid = ""
            switch kind {
            case "rival": name = rivals.isEmpty ? "A rival in your trade" : rivals[Int(v * Double(rivals.count)) % rivals.count]["name"].string
            case "group": let g = groups[Int(v * Double(groups.count)) % groups.count]; name = g["name"].string; gid = g["id"].string
            case "fund": name = fundNames[Int(v * Double(fundNames.count)) % fundNames.count]
            case "angel": name = angelNames[Int(v * Double(angelNames.count)) % angelNames.count]
            default: name = buyerNames[Int(v * Double(buyerNames.count)) % buyerNames.count]
            }
            if bd.contains(where: { $0["name"].string == name }) { name += " (\(k + 1))" }
            bd.append(.object(["id": .number(Double(s.makeID())), "k": .string(kind), "name": .string(name), "gid": .string(gid),
                               "lim": .number(bidLimit(s, co, pct: pct, kind: kind, u: u, data: data, context: fc))]))
        }
        guard SaleListings.start(&s, companyID: companyID, route: "auction", pct: pct, extra: ["res": .number(reserve), "rnd": 0, "bd": .array(bd)]) else { return false }
        s.note("\(co.name) is up for auction: \(n) bidders are registered. The first bids come in now.", tone: "n", companyID: companyID)
        if let raw = (s.rest["sales"]?.array ?? []).first(where: { $0["co"].int == companyID }) { auctionWeek(&s, companyIndex: i, raw: raw, data: data, context: fc) }
        return true
    }

    /// One bidding round. Bids rise by about 7% a round; a bidder may drop out; bids under your reserve stay hidden. After round three the bids stand
    /// for three weeks and then lapse; with no bid at your reserve the auction ends unsold.
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
            var o: JSONValue = old.first(where: { $0["id"].int == bd[k]["id"].int }) ?? .object(["id": bd[k]["id"], "k": bd[k]["k"], "name": bd[k]["name"], "ctr": 0, "gid": bd[k]["gid"]])
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

    // MARK: Routes, stake tiers and what each unlocks

    public struct Route: Identifiable, Equatable {
        public var id: String
        public var title: String
        public var pitch: String
        public var available: Bool
        /// Why it cannot be used now (empty when available).
        public var why: String
    }
    /// Every way to sell, with the reason when one is shut. ids: private, broker, auction, mbo, merger, group, stake, ipo, franchise.
    public static func routes(_ s: GameState, companyID: Int, data: GameData, context fc: FinanceContext) -> [Route] {
        guard let co = s.company(companyID) else { return [] }
        let whole = SaleListings.routeProblem(s, companyID: companyID, route: "private", pct: 100)
        func r(_ id: String, _ title: String, _ pitch: String, _ problem: String?) -> Route { Route(id: id, title: title, pitch: pitch, available: problem == nil, why: problem ?? "") }
        let blocked: String? = s.isBranch(co) ? SaleListings.branchNote : Shareholders.isBlocked(s, companyID: companyID) ? "The other owners block big moves for now." : nil
        let hasGroup = !GroupStakes.groups(s, country: co.countryCode).isEmpty
        return [
            r("private", "Handshake", "Slow and quiet. One or two offers, nobody hears.", whole ?? blocked),
            r("broker", "Broker", "Faster, 4% fee, but staff hear the word and mood drops.", whole ?? blocked),
            r("auction", "Auction", "Set a reserve. Three weekly rounds of bids, then hammer or wait.", whole ?? blocked),
            r("mbo", "Management buyout", "Your manager buys: 62-80% of value, a third paid in two years. Staff stay calm.",
              SaleListings.routeProblem(s, companyID: companyID, route: "mbo", pct: 100) ?? blocked),
            r("merger", "Merge with a rival", "Swap the company for a stake in the merged business.",
              co.status == .open ? (blocked ?? (mergeCandidates(s, companyID: companyID).isEmpty ? "No independent rival here is big enough to merge with." : nil)) : "The company must be open."),
            r("group", "Sell to a rival group", "Approach a group directly for a quick deal.", co.status.isLive && co.type != "hold" ? (blocked ?? (SaleListings.isListed(s, companyID: companyID) ? "It is already listed: withdraw the listing first." : (hasGroup ? nil : "No group is active in this country."))) : "This company cannot be sold."),
            r("stake", "Sell a stake", "Keep control and sell 10, 25, 34 or 49% of your shares.", SaleListings.routeProblem(s, companyID: companyID, route: "private", pct: 10) ?? blocked),
            r("ipo", "Go public", "List a holding on the exchange.", blocked ?? ipoProblem(s, companyID: companyID, data: data, context: fc)),
            r("franchise", "Master franchise", "Sell the franchise rights of a country.", co.value("fr")["on"].bool ? nil : "Set up franchising for this company first."),
        ]
    }
    static func ipoProblem(_ s: GameState, companyID: Int, data: GameData, context fc: FinanceContext) -> String? {
        guard let co = s.company(companyID) else { return "No such company." }
        if co.type != "hold" { return "Only a holding can go public. Put this company under a holding first." }
        if Funding.isListed(co) { return "Already listed on the exchange." }
        if Funding.holdingValue(s, holdingID: companyID, data: data) < Funding.listingMinimum(s, fc) { return "The holding is worth too little to list yet." }
        return nil
    }

    public struct StakeTier: Identifiable, Equatable {
        public var id: Int { pct }
        public var pct: Int
        /// Points of the company the buyer gets, and what you keep.
        public var buyerPoints: Double
        public var youKeep: Double
        public var unlocks: [String]
        public var allowed: Bool
    }
    /// 10 / 25 / 34 / 49% of YOUR shares, with what the buyer gains: a board seat from 20 points, a block over 33.4, control over 50.
    public static func stakeTiers(_ s: GameState, companyID: Int) -> [StakeTier] {
        guard let co = s.company(companyID) else { return [] }
        return [10, 25, 34, 49].map { p in
            let pts = co.ownership * Double(p) / 100, keep = co.ownership - pts
            let outside = (100 - co.ownership) + pts
            var u = ["Cash for you, no change in who runs it."]
            if pts >= 20 { u.append("The buyer takes a board seat.") }
            if outside >= 33.4 { u.append("Outside owners together can block big moves.") }
            if outside > 50 { u.append("Outside owners could outvote you.") }
            return StakeTier(pct: p, buyerPoints: pts, youKeep: keep, unlocks: u, allowed: SaleListings.routeProblem(s, companyID: companyID, route: "private", pct: p) == nil)
        }
    }

    // MARK: Merger

    public struct MergeCandidate: Identifiable, Equatable { public var id: Int; public var name: String; public var owner: String; public var size: Double }
    public static func mergeCandidates(_ s: GameState, companyID: Int) -> [MergeCandidate] {
        guard let co = s.company(companyID) else { return [] }
        return (s.rest["mk"]?[co.type + "|" + co.cityID]["riv"].array ?? []).filter { r in
            let g = r["g27"]; return (g.isNull || g.string == "0" || g.string.isEmpty || g.string == "false") && !r["name"].string.isEmpty
        }.map { MergeCandidate(id: $0["id"].int, name: $0["name"].string, owner: $0["owner"].string, size: $0["size"].double) }
    }
    public enum MergeResult: Equatable { case merged, declined, refused(String) }
    /// Merge with a rival: it joins the company (more size, awareness and demand), and its owner gets `pct`% of the company. 30% is certain; less
    /// is a try that the rival owner may turn down (decided by a hash of the pair and the week, so you can try again next week).
    @discardableResult
    public static func mergeWithRival(_ s: inout GameState, companyID: Int, rivalID: Int, pct: Double, data: GameData, context fc: FinanceContext) -> MergeResult {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open else { return .refused("The company must be open.") }
        if s.isBranch(s.companies[i]) { return .refused(SaleListings.branchNote) }
        if let why = SaleListings.boardBlock(s, companyID: companyID) { return .refused(why) }
        if Shareholders.isBlocked(s, companyID: companyID) { return .refused("The other owners block a merger for now.") }
        guard let r = mergeCandidates(s, companyID: companyID).first(where: { $0.id == rivalID }) else { return .refused("That rival is no longer there.") }
        let chance = min(1, 0.35 + (pct - 20) * 0.065)
        if pct < 30 && HashedRandom.first("merge:\(companyID):\(rivalID):\(s.week)") >= chance {
            s.note("\(r.owner) turned down \(Int(pct))% of \(s.companies[i].name).", tone: "n", companyID: companyID)
            return .declined
        }
        let cur = fc.currency(s.companies[i].countryCode, s)
        StrategicDecisions.mergeRival(&s, companyIndex: i, rivalID: rivalID, rivalName: r.name, owner: r.owner, pct: pct, data: data, context: fc, currency: cur)
        return .merged
    }

    // MARK: Selling to a rival group

    public struct GroupBuyer: Identifiable, Equatable { public var id: String; public var name: String; public var price: Double }
    /// What each active group would pay for the whole company now: about its value, a little either side by a hash of the group and the week.
    public static func groupBuyers(_ s: GameState, companyID: Int, data: GameData, context fc: FinanceContext) -> [GroupBuyer] {
        guard let co = s.company(companyID), co.status.isLive, co.type != "hold", !s.isBranch(co), !Shareholders.isBlocked(s, companyID: companyID), SaleListings.boardBlock(s, companyID: companyID) == nil else { return [] }
        let premium = BrandValues.salePremium(BrandValues.company(s, co).score)
        return GroupStakes.groups(s, country: co.countryCode).filter { $0["dist"].int == 0 }.map { g in
            let f = (0.9 + 0.15 * HashedRandom.first("grp:\(companyID):\(g["id"].string):\(s.week)")) * premium
            return GroupBuyer(id: g["id"].string, name: g["name"].string, price: (saleWorth(s, co, data: data, factor: f) / 1000).rounded() * 1000)
        }
    }
    /// Approach a group: it buys at its quote and the company becomes one of its sites. Returns the cash you get.
    @discardableResult
    public static func sellToGroupNow(_ s: inout GameState, companyID: Int, groupID: String, data: GameData, context fc: FinanceContext) -> Double? {
        guard let i = s.companyIndex(companyID), let q = groupBuyers(s, companyID: companyID, data: data, context: fc).first(where: { $0.id == groupID }), !SaleListings.isListed(s, companyID: companyID) else { return nil }
        let mine = jsRound(q.price * s.companies[i].ownership / 100)
        return GroupDeals.sellToGroup(&s, companyIndex: i, groupID: groupID, price: q.price, data: data, context: fc) ? mine : nil
    }
}
