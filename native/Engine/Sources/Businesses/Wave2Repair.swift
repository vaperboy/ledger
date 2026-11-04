import Foundation
import GameCore
import Countries
import Finance

public struct RepairKind: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Bay hours of the standard job.
    public var hours: Double
    /// Parts at cost as a share of the garage's ticket.
    public var parts: Double
    /// The shortest time the job takes, in days.
    public var days: Int
}

public struct RepairQuote: Equatable, Sendable {
    public var garageID: Int
    public var garageName: String
    public var kind: RepairKind
    /// 1 = the standard job; a worse car is a bigger number.
    public var scale: Double
    public var hours: Double
    public var labour: Double
    /// What the parts cost the garage, and what it charges for them.
    public var partsCost: Double
    public var partsPrice: Double
    /// The price before VAT: labour plus parts at the garage's markup.
    public var price: Double
    public var vat: Double
    public var total: Double { price + vat }
    /// Whole weeks until the car is back (at least the days the job needs, longer when the garage is busy).
    public var weeks: Int
    public var dueWeek: Int
}

public struct RepairOrder: Equatable, Identifiable, Sendable {
    public var id: Int
    public var garageID: Int
    public var dealerID: Int
    public var kind: String
    public var ref: String
    public var price: Double
    public var vat: Double
    public var partsCost: Double
    public var weeks: Int
    public var startWeek: Int
    public var dueWeek: Int
    /// Share of the garage's weekly capacity the job takes, in customers a week.
    public var slotsPerWeek: Double
    public var done: Bool
}

public enum RepairResult: Equatable, Sendable {
    case ordered(RepairOrder)
    case refused(String)
}

/// Job orders: a garage of yours (carrepair) is the supplier of another company of yours (the used car dealer) for repairs. The garage quotes labour hours
/// at its hourly rate plus parts at its markup, from its real spare capacity; the order books the garage's revenue and its parts cost, and the dealer's
/// repair cost, in real double entry (same country, with VAT as between any two of your companies). Orders are kept on the garage (`w2jobs`) and take
/// their share of its capacity until they are done.
public enum Wave2Repair {
    static let key = "w2jobs"

    public static var kinds: [RepairKind] { Wave2.table.kinds }
    public static func kind(_ id: String) -> RepairKind? { kinds.first { $0.id == id } }

    static func isGarage(_ c: Company?) -> Bool { c != nil && c!.type == "carrepair" && c!.status == .open }

    /// Open garages of yours in the dealer's country that could take its cars, cheapest first.
    public static func garages(for dealerID: Int, _ s: GameState, data: GameData) -> [Int] {
        guard let d = s.company(dealerID) else { return [] }
        let list = s.companies.filter { isGarage($0) && $0.id != dealerID && $0.countryCode == d.countryCode }
        return list.sorted { $0.id < $1.id }.map { $0.id }
    }

    // MARK: Jobs on the garage

    static func decode(_ j: JSONValue) -> RepairOrder {
        RepairOrder(id: j["id"].int, garageID: j["g"].int, dealerID: j["d"].int, kind: j["k"].string, ref: j["ref"].string, price: j["p"].double,
                    vat: j["v"].double, partsCost: j["pc"].double, weeks: j["w"].int, startWeek: j["s"].int, dueWeek: j["due"].int,
                    slotsPerWeek: j["sl"].double, done: j["done"].bool)
    }

    static func encode(_ o: RepairOrder) -> JSONValue {
        .object(["id": .number(Double(o.id)), "g": .number(Double(o.garageID)), "d": .number(Double(o.dealerID)), "k": .string(o.kind), "ref": .string(o.ref),
                 "p": .number(o.price), "v": .number(o.vat), "pc": .number(o.partsCost), "w": .number(Double(o.weeks)), "s": .number(Double(o.startWeek)),
                 "due": .number(Double(o.dueWeek)), "sl": .number(o.slotsPerWeek), "done": .bool(o.done)])
    }

    /// The orders of one garage, newest last (finished ones stay a while).
    public static func orders(_ s: GameState, garageID: Int) -> [RepairOrder] {
        s.company(garageID)?.value(key).array.map(decode) ?? []
    }

    /// Orders still being worked on.
    public static func open(_ s: GameState, garageID: Int) -> [RepairOrder] { orders(s, garageID: garageID).filter { !$0.done && $0.dueWeek > s.week } }

    /// What the dealer asked for, for its own screen: the orders it has placed with any garage.
    public static func orders(_ s: GameState, dealerID: Int) -> [RepairOrder] {
        s.companies.filter { $0.type == "carrepair" }.flatMap { orders(s, garageID: $0.id) }.filter { $0.dealerID == dealerID }.sorted { $0.id < $1.id }
    }

    // MARK: Quote

    /// What the garage would charge and how long it would take. nil when the garage cannot take the job (not an open garage, unknown job, no spare
    /// capacity at all). `scale` is how big the job is against the standard one (1 = standard).
    public static func quote(_ s: GameState, garageID: Int, kind id: String, scale: Double = 1, data: GameData) -> RepairQuote? {
        guard let g = s.company(garageID), isGarage(g), let bd = data.catalog[g.type], let k = kind(id), scale.isFinite, scale > 0 else { return nil }
        let w = World(state: s, data: data)
        let ticket = SalesItems.marketTicket(g, bd, w)
        guard ticket > 0 else { return nil }
        let hours = k.hours * scale
        let labour = hours * Wave2.table.labourPerHour * ticket
        let partsCost = k.parts * scale * ticket
        let partsPrice = partsCost * (1 + Wave2.table.partsMarkup)
        let price = Double(jsRound(labour + partsPrice))
        let vat = w.country(g).usesSalesTax ? 0 : Double(jsRound(price * Vat.rate(g, bd, w)))
        // the garage's own spare capacity (customers a week), less what the jobs already booked take each week
        let reserved = open(s, garageID: garageID).reduce(0.0) { $0 + $1.slotsPerWeek }
        let spare = OwnListings.spareSlots(s, seller: g, bd, w) - reserved
        guard spare > 0 else { return nil }
        let slots = OwnListings.slotsPerUnit(price: price, seller: g, bd, w)
        let shortest = Int((Double(k.days) * max(1, scale.squareRoot()) / 7).rounded(.up))
        let weeks = max(1, shortest, Int((slots / spare).rounded(.up)))
        return RepairQuote(garageID: garageID, garageName: g.name, kind: k, scale: scale, hours: hours, labour: labour, partsCost: partsCost,
                           partsPrice: partsPrice, price: price, vat: vat, weeks: weeks, dueWeek: s.week + weeks)
    }

    // MARK: Order

    /// Order a repair: the dealer pays the garage. The garage books the sale (revenue) and what the parts cost it; the dealer books the repair cost
    /// (category `cogs`, so the cars it sells carry it); VAT moves as between any two of your companies. Nothing is paid when refused.
    public static func order(_ s: inout GameState, garageID: Int, dealerID: Int, kind id: String, scale: Double = 1, ref: String = "", data: GameData) -> RepairResult {
        guard let gi = s.companyIndex(garageID), let di = s.companyIndex(dealerID), garageID != dealerID else { return .refused("That company no longer exists.") }
        guard isGarage(s.companies[gi]) else { return .refused("That is not an open car repair garage.") }
        guard s.companies[di].status == .open else { return .refused("The buyer is not open.") }
        guard s.companies[gi].countryCode == s.companies[di].countryCode else { return .refused("The garage works in another country.") }
        guard let q = quote(s, garageID: garageID, kind: id, scale: scale, data: data) else { return .refused("The garage has no room for this job now.") }
        guard s.companies[di].cash >= q.total else { return .refused("Not enough cash in \(s.companies[di].name).") }
        let w = World(state: s, data: data)
        let g = s.companies[gi], d = s.companies[di]
        let what = ref.isEmpty ? q.kind.name : "\(q.kind.name): \(ref)"
        Payments.companyPays(&s, companyID: dealerID, amount: q.price, category: "cogs", label: "Repair at \(g.name): \(what)")
        Payments.companyReceives(&s, companyID: garageID, amount: q.price, category: "rev", label: "Repair for \(d.name): \(what)")
        Payments.companyPays(&s, companyID: garageID, amount: q.partsCost, category: "cogs", label: nil)
        IntercompanySupply.transferVat(&s, supplier: s.companies[gi], buyerIndex: di, net: q.price, data: data, w, cashNow: true)
        var jobs = s.companies[gi].value(key).array
        let nextID = s.companies[gi].int("w2jid") + 1
        s.companies[gi].set("w2jid", .number(Double(nextID)))
        let ticket = data.catalog[g.type].map { SalesItems.marketTicket(g, $0, w) } ?? 1
        let slots = max(1e-6, q.price / max(0.01, ticket)) / Double(q.weeks)
        let o = RepairOrder(id: nextID, garageID: garageID, dealerID: dealerID, kind: id, ref: ref, price: q.price, vat: q.vat, partsCost: q.partsCost,
                            weeks: q.weeks, startWeek: s.week, dueWeek: q.dueWeek, slotsPerWeek: slots, done: false)
        jobs.append(encode(o))
        s.companies[gi].set(key, .array(jobs))
        return .ordered(o)
    }

    // MARK: Weekly

    /// Finished jobs are marked done and the garage is told; old finished jobs are forgotten after a quarter.
    static func weekly(_ s: inout GameState, _ i: Int, data: GameData) {
        let raw = s.companies[i].value(key)
        guard !raw.isNull else { return }
        var jobs = raw.array.map(decode), changed = false
        for k in jobs.indices where !jobs[k].done && jobs[k].dueWeek <= s.week {
            jobs[k].done = true; changed = true
            let name = kind(jobs[k].kind)?.name.lowercased() ?? "repair"
            s.note("The \(name) for \(s.company(jobs[k].dealerID)?.name ?? "a company of yours") is finished and the car is back.", tone: "g", companyID: s.companies[i].id)
        }
        let kept = jobs.filter { !($0.done && s.week - $0.dueWeek > 13) }
        if kept.count != jobs.count { changed = true }
        if changed { s.companies[i].set(key, .array(kept.map(encode))) }
    }
}

public extension Wave2 {
    /// What the used car dealer (or any company of yours) can ask a garage of yours. `carRepairQuote` is the price, weeks and capacity check; nothing moves.
    static func carRepairQuote(_ s: GameState, garageID: Int, kind: String, scale: Double = 1, data: GameData) -> RepairQuote? {
        Wave2Repair.quote(s, garageID: garageID, kind: kind, scale: scale, data: data)
    }

    /// `orderRepair` books it for real: garage revenue and parts cost, dealer repair cost, VAT.
    static func orderRepair(_ s: inout GameState, garageID: Int, dealerID: Int, kind: String, scale: Double = 1, ref: String = "", data: GameData) -> RepairResult {
        Wave2Repair.order(&s, garageID: garageID, dealerID: dealerID, kind: kind, scale: scale, ref: ref, data: data)
    }
}
