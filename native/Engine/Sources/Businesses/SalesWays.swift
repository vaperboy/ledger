import Foundation
import GameCore
import Countries
import Finance

public enum SalesWays {
    public enum Switch: Equatable, Sendable { case changed, notAWay, notSwitchable, notEnoughCash(Double), noCompany }

    static let switchable: Set<String> = ["platform", "members", "emergency", "upsell"]

    public struct Row: Equatable, Sendable {
        public var kind: String
        public var name: String
        public var isOn: Bool
        public var canSwitch: Bool
        public var detail: String
        public var cost: String = ""
    }

    static func ways(_ co: Company, _ w: World) -> [Balance.SalesWay] { w.balance.salesWays[co.type] ?? [] }

    public static func rows(_ s: GameState, companyID: Int, data: GameData) -> [Row] {
        guard let co = s.company(companyID) else { return [] }
        let w = World(state: s, data: data)
        let cur = w.currency(co)
        let sw = co.value("sw33")
        return ways(co, w).filter { $0.kind != "contract" && $0.kind != "offer" }.map { (way: Balance.SalesWay) -> Row in
            let on = sw["on"][way.kind].bool
            var detail = ""
            var cost = ""
            switch way.kind {
            case "platform":
                detail = "About \(Int(saturating: jsRound((way.options["lift"] ?? 0.2) * 100)))% more customers, \(Int(saturating: jsRound((way.options["fee"] ?? 0.2) * 100)))% commission on them"
                cost = "\(Int(saturating: jsRound((way.options["fee"] ?? 0.2) * 100)))% commission"
                if (way.options["deliv"] ?? 0) > 0, let dk = IntercompanySupply.deliveryKind {
                    let share = dk.buyers[co.type] ?? 0
                    let fill = IntercompanySupply.deliveryFill(s, buyer: co, way: way)
                    detail = "Up to \(Int(saturating: jsRound((way.options["lift"] ?? 0.2) * 100)))% more customers, only for the orders that get delivered (\(Int(saturating: jsRound(fill * 100)))% now). "
                        + "\(Int(saturating: jsRound(max(0, (way.options["fee"] ?? 0.2) - share) * 100)))% marketplace commission plus delivery at \(Int(saturating: jsRound(share * 100)))% of those orders; set the courier under Suppliers"
                    cost = "\(Int(saturating: jsRound(max(0, (way.options["fee"] ?? 0.2) - share) * 100)))% commission plus delivery at \(Int(saturating: jsRound(share * 100)))%"
                }
            case "members":
                detail = (on ? "\(Int(saturating: jsRound(sw["mem"].double))) members" : "Not offered") + ", perks cost 2% of sales"
                cost = "Perks cost 2% of sales"
            case "emergency":
                detail = "On call \(cur.display(cur.scaledPrice(2500))) a week, urgent jobs pay half again"
                cost = "On call \(cur.display(cur.scaledPrice(2500))) a week"
            case "upsell":
                detail = "About \(Int(saturating: jsRound((way.options["u"] ?? 0.08) * 100)))% extra per sale" + (sw["paidUp"].bool ? "" : ", set-up \(cur.display(cur.scaledPrice(12000)))")
                cost = sw["paidUp"].bool ? "Set-up paid" : "Set-up \(cur.display(cur.scaledPrice(12000)))"
            case "referral":
                detail = VolumeContracts.ratingFactor(co) < 0.2 ? "Too few happy customers" : "About \(jsRound(sw["ref"].double * 10) / 10) a week"
            case "peak":
                detail = "Busy in months " + way.peakMonths.map { String($0) }.joined(separator: ", ")
            default:
                break
            }
            return Row(kind: way.kind, name: way.name, isOn: on, canSwitch: switchable.contains(way.kind), detail: detail, cost: cost)
        }
    }

    @discardableResult
    public static func setOn(_ s: inout GameState, companyID: Int, kind: String, on: Bool, data: GameData) -> Switch {
        guard let i = s.companyIndex(companyID) else { return .noCompany }
        let co = s.companies[i]
        let w = World(state: s, data: data)
        guard let way = ways(co, w).first(where: { $0.kind == kind }) else { return .notAWay }
        guard switchable.contains(kind) else { return .notSwitchable }
        var sw = VolumeContracts.store(co)
        if sw["on"][kind].bool == on { return .changed }
        if on, kind == "upsell", !sw["paidUp"].bool {
            let fee = w.currency(co).scaledPrice(12000)
            if co.cash < fee { return .notEnoughCash(fee) }
            Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Set-up: \(way.name.lowercased())")
            sw["paidUp"] = 1
        }
        var onMap = sw["on"].object
        onMap[kind] = on ? 1 : 0
        sw["on"] = .object(onMap)
        VolumeContracts.addLog(&sw, week: s.week, "\(on ? "Started" : "Stopped"): \(way.name.lowercased()).")
        s.companies[i].set("sw33", sw)
        return .changed
    }

    static func weekly(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        let co = s.companies[i]
        guard co.status == .open else { return }
        let w = World(state: s, data: data)
        let list = ways(co, w)
        if list.isEmpty { return }
        func way(_ k: String) -> Balance.SalesWay? { list.first { $0.kind == k } }
        var sw = VolumeContracts.store(co)
        let on = sw["on"]
        let lw = co.value("lastW")
        let rev = lw["rev"].double, units = lw["units"].double
        let tk = Pricing.ticket(co, bd, w)
        let rating = VolumeContracts.ratingFactor(co)
        var changed = false
        let id = co.id

        if let pl = way("platform"), on["platform"].bool, rev > 0 {
            var lift = pl.options["lift"] ?? 0.2
            var fee = pl.options["fee"] ?? 0.2
            var delivery = 0.0
            if let dk = IntercompanySupply.deliveryKind, (pl.options["deliv"] ?? 0) > 0 {
                lift *= IntercompanySupply.deliveryFill(s, buyer: co, way: pl)
                delivery = dk.buyers[co.type] ?? 0
                fee = max(0, fee - delivery)
            }
            let brought = rev * lift / (1 + lift)
            Payments.companyPays(&s, companyID: id, amount: brought * fee, category: "oth")
            if delivery > 0, let dk = IntercompanySupply.deliveryKind {
                Payments.companyPays(&s, companyID: id, amount: brought * delivery, category: dk.category)
                s.companies[i].set("dlvRev", brought)
                let fee = brought * (pl.options["dfee"] ?? 0)
                if fee > 0, IntercompanySupply.hasOwnDelivery(s, buyer: id) {
                    Payments.companyReceives(&s, companyID: id, amount: fee, category: "rev", label: "Delivery fees from customers")
                }
            }
        } else if s.companies[i].raw["dlvRev"] != nil {
            s.companies[i].raw.removeValue(forKey: "dlvRev")
        }
        if way("members") != nil {
            let mem = sw["mem"].double
            if on["members"].bool {
                sw["mem"] = .number(max(0, mem * 0.97 + units * 0.03 * (0.5 + rating)))
                if rev > 0 { Payments.companyPays(&s, companyID: id, amount: rev * 0.02, category: "oth") }
                changed = true
            } else if mem != 0 {
                sw["mem"] = .number(mem * 0.85)
                changed = true
            }
        }
        if way("referral") != nil {
            let ref = sw["ref"].double * 0.75 + units * 0.05 * rating
            if ref != sw["ref"].double { sw["ref"] = .number(ref); changed = true }
        }
        if way("emergency") != nil, on["emergency"].bool {
            Payments.companyPays(&s, companyID: id, amount: w.currency(co).scaledPrice(2500), category: "wages")
            if units > 0 { Payments.companyReceives(&s, companyID: id, amount: jsRound(units * 0.07 * tk * 0.5), category: "rev", label: nil) }
        }
        if let up = way("upsell"), on["upsell"].bool, rev > 0 {
            let x = jsRound(rev * (up.options["u"] ?? 0.08) * rating)
            Payments.companyReceives(&s, companyID: id, amount: x, category: "rev", label: nil)
            Payments.companyPays(&s, companyID: id, amount: x * 0.35, category: "cogs")
        }
        if let pk = way("peak") {
            let ahead = GameCalendar.month(week: s.week + 3) + 1, now = GameCalendar.month(week: s.week) + 1
            let year = GameCalendar.year(week: s.week)
            if pk.peakMonths.contains(ahead), !pk.peakMonths.contains(now), !(sw["peakY"].int == year && sw["peakM"].int == ahead) {
                sw["peakY"] = .number(Double(year)); sw["peakM"] = .number(Double(ahead))
                let boost = Int(saturating: jsRound((pk.options["b"] ?? 0.3) * 100))
                let room = lw["util"].double > 0.8 ? " You are already near your limit, so plan for extra hands (seasonal workers are hired under Find workers)." : " You have the room to serve it."
                s.addMessage(from: co.name, title: "\(monthName(ahead)): \(pk.name.lowercased()) is coming",
                             body: "Customers come in waves in \(pk.peakMonths.map { monthName($0) }.joined(separator: " and ")): about \(boost)% more than usual.\(room)",
                             companyID: id, tone: "n")
                changed = true
            }
        }
        if changed || !co.value("sw33").isNull { s.companies[i].set("sw33", sw) }
    }

    static func monthName(_ m: Int) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return names[max(0, min(11, m - 1))]
    }
}

public enum SalesChannel: String, CaseIterable, Equatable, Sendable {
    case consumers = "private"
    case business

    static let consumerDemand = 1.05
    static let consumerPrice = 0.985
    static let businessDemand = 0.5
    static let businessPrice = 1.12
    static let businessLumpiness = 0.5
    static let contractShareOfCapacity = 0.7
    static let contractWeeks = [4, 8, 13]

    public var title: String { self == .consumers ? "Private customers" : "Business customers" }

    public static func canChoose(_ channel: SalesChannel, tradeID: String) -> Bool {
        channel == .consumers || SupplyMarketCatalogue.canSupply(tradeID: tradeID)
    }

    public static func options(tradeID: String) -> [SalesChannel] { allCases.filter { canChoose($0, tradeID: tradeID) } }

    static func takesContracts(_ co: Company) -> Bool { co.chosenChannel == .business }

    static func demandFactor(_ co: Company, week: Int, seed: Int) -> Double {
        switch co.chosenChannel {
        case nil: return 1
        case .consumers?: return consumerDemand
        case .business?: return businessDemand * (1 + businessLumpiness * (2 * HashedRandom.first("\(seed):chan:\(week):\(co.id)") - 1))
        }
    }

    static func priceFactor(_ co: Company) -> Double {
        switch co.chosenChannel {
        case nil: return 1
        case .consumers?: return consumerPrice
        case .business?: return businessPrice
        }
    }

    public static func refusal(_ s: GameState, companyID: Int, channel: SalesChannel) -> String? {
        guard let co = s.company(companyID) else { return "That company no longer exists." }
        if co.chosenChannel != nil || co.status != .setup { return "How you sell is chosen once, when the company starts." }
        if !canChoose(channel, tradeID: co.type) { return "This kind of company has nothing to supply to business customers." }
        return nil
    }

    @discardableResult
    public static func choose(_ s: inout GameState, companyID: Int, channel: SalesChannel) -> String? {
        if let why = refusal(s, companyID: companyID, channel: channel) { return why }
        guard let i = s.companyIndex(companyID) else { return "That company no longer exists." }
        s.companies[i].set("chan", channel.rawValue)
        return nil
    }
}

public extension Company {
    var chosenChannel: SalesChannel? {
        let v = str("chan")
        return v.isEmpty ? nil : SalesChannel(rawValue: v)
    }

    var channel: SalesChannel { chosenChannel ?? .consumers }
}

public struct DemandPost: Equatable, Identifiable, Sendable {
    public var id: String
    public var ownerName: String
    public var companyName: String
    public var lineID: String
    public var units: Int
    public var weeks: Int

    public init(id: String, ownerName: String, companyName: String, lineID: String, units: Int, weeks: Int) {
        self.id = id; self.ownerName = ownerName; self.companyName = companyName; self.lineID = lineID; self.units = units; self.weeks = weeks
    }

    init(_ j: JSONValue) {
        self.init(id: j["id"].string, ownerName: j["o"].string, companyName: j["c"].string, lineID: j["l"].string, units: j["u"].int, weeks: j["w"].int)
    }

    var json: JSONValue {
        .object(["id": .string(id), "o": .string(ownerName), "c": .string(companyName), "l": .string(lineID), "u": .number(Double(units)), "w": .number(Double(weeks))])
    }
}

extension SalesChannel {
    public static func demandPosts(_ s: GameState) -> [DemandPost] { (s.rest["pdm"]?.array ?? []).map { DemandPost($0) } }

    public static func saveDemandPosts(_ s: inout GameState, _ posts: [DemandPost]) {
        s.rest["pdm"] = .array(posts.prefix(60).map { $0.json })
    }

    static func offers(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        let co = s.companies[i]
        guard co.status == .open else { return }
        let lw = co.value("lastW")
        let cap = lw["cap"].double
        guard cap >= 1 else { return }
        let waiting = s.inbox.filter { $0.status == "open" && $0.companyID == co.id && $0.actionID == VolumeContracts.action }.count
        let room = cap * contractShareOfCapacity - VolumeContracts.committedUnits(co)
        guard waiting < 2, room >= 1 else { return }
        var h = HashedRandom("\(s.seed):bzo:\(s.week):\(co.id)")
        let chance = 0.15 + 0.2 * clamp(co.awareness / 100, 0, 1) + 0.15 * clamp((co.reputation - 40) / 60, 0, 1)
        guard h.next() < chance else { return }
        let seen = co.value("bzSeen").array.map { $0.string }
        let supplied = SupplyMarketCatalogue.supplies[co.type] ?? []
        let posts = demandPosts(s).filter { supplied.contains($0.lineID) && !seen.contains($0.id) }
        let w = World(state: s, data: data)
        let tk = Pricing.ticket(co, bd, w)
        let usePost = !posts.isEmpty && h.next() < 0.5
        let post: DemandPost? = usePost ? posts[min(posts.count - 1, Int(h.next() * Double(posts.count)))] : nil
        let who: String
        if let post {
            who = post.companyName
        } else {
            let country = data.countries[co.countryCode] ?? data.countries.countries[0]
            var names = DeterministicRandom(seed: Int(h.next() * 1_000_000_000))
            who = CompanySetup.generateName(country: country, family: "svc", &names)
        }
        let wanted: Double = post.map { Double($0.units) } ?? max(1, jsRound(cap * (0.06 + 0.16 * h.next())))
        let units: Double = max(1, min(room.rounded(.down), wanted))
        let weeks: Int = post?.weeks ?? contractWeeks[min(contractWeeks.count - 1, Int(h.next() * Double(contractWeeks.count)))]
        let discount: Double = jsRound((post == nil ? 0.02 - 0.10 * h.next() : 0.01 - 0.06 * h.next()) * 100) / 100
        let pay: Int = post == nil ? [0, 0, 2, 4][min(3, Int(h.next() * 4))] : 0
        let reliability: Double = post == nil ? jsRound((0.4 + 0.6 * h.next()) * 100) / 100 : 0.9
        let terms = VolumeContracts.Terms(name: "Supply contract", customer: who, units: units, discount: discount, weeks: weeks, paymentWeeks: pay,
                                          reliability: reliability, buyerIsPlayer: post != nil)
        if let post {
            var marks = co.value("bzSeen").array
            marks.append(.string(post.id))
            s.companies[i].set("bzSeen", .array(Array(marks.suffix(40))))
        }
        let price = tk * (1 - discount)
        let worth = price * units * Double(weeks)
        if let manager = co.managerID.flatMap({ s.people[$0]?.name }) {
            let takes = lw["util"].double < 0.9 && reliability >= 0.6
            MarketEvents.noteContractOffer(&s, company: co, customer: who, worth: worth,
                                           outcome: takes ? "\(manager) signed it." : "\(manager) declined it: the terms or the room were not right.")
            if takes { VolumeContracts.sign(&s, companyID: co.id, terms: terms, signedBy: manager) }
            return
        }
        MarketEvents.noteContractOffer(&s, company: co, customer: who, worth: worth)
        let cur = w.currency(co)
        let paid = pay == 0 ? "on delivery" : "\(pay) weeks after delivery"
        let buyer = post != nil ? "a player's company" : "a company"
        let body = "\(who) is \(buyer). It wants \(Int(units)) units a week for \(weeks) weeks at \(cur.display(price)) a unit, paid \(paid). "
            + "Worth about \(cur.display(worth)) in all. Once you accept, deliveries run by themselves; missed units bring warnings, a penalty and a worse name."
        s.addMessage(kind: "ask", from: co.name, title: "\(who) offers a supply contract", body: body, companyID: co.id, tone: "n", status: "open",
                     options: [.option("Accept"), .option("Decline")], action: VolumeContracts.action, data: VolumeContracts.json(terms), expiresWeek: s.week + 2)
    }
}
