import Foundation
import GameCore
import Countries
import Finance

public enum SoftwareProducts {
    public static let types: [(id: String, name: String, equipmentPattern: [String])] = [
        ("crm", "CRM and sales", ["crm", "listing", "applicant", "case-management"]),
        ("book", "Booking and scheduling", ["booking", "dispatch app", "hotel management", "reception"]),
        ("acct", "Accounting and payroll", ["accounting", "payroll"]),
        ("shop", "Shop and payments", ["shop platform", "pos and", "webshop"]),
        ("job", "Job and quoting", ["job", "quoting", "estimating"]),
        ("fleet", "Fleet and routing", ["routing", "tracking", "fleet", "tachograph"]),
        ("cad", "Design and CAD", ["cad", "bim", "design and cost"]),
        ("health", "Patient journals", ["journal", "patient"]),
        ("ticket", "Ticketing and events", ["ticketing"]),
        ("erp", "ERP and planning", ["erp", "planning", "dealer management"]),
    ]
    public static let models: [(id: String, name: String)] = [("once", "One-time purchase"), ("sub", "Subscription"), ("both", "Setup fee + subscription")]

    public static func listPrice(_ model: String, scale: (Double) -> Double) -> Double { model == "once" ? scale(15000) : model == "sub" ? scale(1200) : scale(800) }

    public enum Phase: String { case build, beta, live }

    public struct Product: Equatable, Identifiable {
        public var id: Int
        public var name: String
        public var type: String
        public var model: String
        public var price: Double
        public var phase: Phase
        public var progress: Double
        public var coders: Int
        public var selfHours: Double
        public var customers: Int
        public var weeklyRevenue: Double
        public var internalPercent: Int
        public var trust: Double
        public var usable: Bool { phase == .beta || phase == .live }
        public var typeName: String { types.first { $0.id == type }?.name ?? type }
        public var modelName: String { models.first { $0.id == model }?.name ?? model }
    }

    static func read(_ co: Company) -> Product? {
        let sw = co.value("swp")
        guard !sw.isNull else { return nil }
        return Product(id: co.id, name: sw["name"].string, type: sw["type"].string, model: sw["model"].string, price: sw["price"].double,
                       phase: Phase(rawValue: sw["phase"].string) ?? .build, progress: sw["prog"].double, coders: sw["devs"].int, selfHours: sw["selfH"].double,
                       customers: sw["cust"].int, weeklyRevenue: sw["revW"].double, internalPercent: sw["int"].int, trust: sw["tr"].double)
    }

    public static func product(_ s: GameState, companyID: Int) -> Product? { s.company(companyID).flatMap(read) }
    public static func products(_ s: GameState) -> [Product] { s.companies.filter { $0.status.isLive }.compactMap(read) }

    public static func canBuild(_ co: Company) -> Bool { co.status == .open && co.type == "webdev" }

    public static func step(_ sw: inout JSONValue, name: String, quality q: Double, trust tr: inout Double, burn: Double, ownerFactor: Double = 1,
                            random r: inout DeterministicRandom, scale: (Double) -> Double) -> (revenue: Double, notes: [(text: String, news: Bool)]) {
        var notes: [(String, Bool)] = []
        let speed = sw["devs"].double + sw["selfH"].double / 40 * 0.7 * ownerFactor
        var phase = sw["phase"].string
        if phase != "live" {
            sw["prog"] = .number(min(1, sw["prog"].double + speed / 30 * (0.7 + q * 0.6)))
            if phase == "build", sw["prog"].double >= 0.5 { phase = "beta"; notes.append(("\(name) is ready to test. Your companies can try it from the equipment shop.", false)) }
            if sw["prog"].double >= 1 { phase = "live"; notes.append(("\(name) is published and on sale.", false)); notes.append(("\(name) launches its new software.", true)) }
            sw["phase"] = .string(phase)
        }
        var rev = 0.0
        if phase == "live" {
            let cust = sw["cust"].double
            let nc = max(0, (jsRound((q * 2.2 + tr * 3 + sw["devs"].double * 0.3) * (1 + cust / 250) * r.range(0.2, 1.3))))
            sw["cust"] = .number(jsRound(cust * 0.99) + nc)
            let model = sw["model"].string, price = sw["price"].double
            rev = model == "once" ? nc * price : model == "sub" ? sw["cust"].double * price * 12 / 52 : nc * scale(5000) + sw["cust"].double * price * 12 / 52
            tr = clamp(tr + min(0.01, rev / max(1, burn) * 0.004), 0, 1)
        } else if phase == "beta" {
            sw["cust"] = .number(max(sw["cust"].double, 3 + (sw["prog"].double * 10).rounded(.down)))
        }
        sw["revW"] = .number(jsRound(rev))
        return (rev, notes.map { (text: $0.0, news: $0.1) })
    }

    @discardableResult
    public static func start(_ s: inout GameState, companyID: Int, type: String, model: String, name: String? = nil, coders: Int = 1, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), canBuild(s.companies[i]), s.companies[i].value("swp").isNull,
              types.contains(where: { $0.id == type }), models.contains(where: { $0.id == model }) else { return false }
        let cur = World(state: s, data: data).currency(s.companies[i])
        let typeName = types.first { $0.id == type }!.name
        s.companies[i].set("swp", .object(["name": .string(name ?? "\(s.companies[i].name) \(typeName)"), "type": .string(type), "model": .string(model),
                                           "price": .number(listPrice(model, scale: cur.scaledPrice)), "phase": "build", "prog": 0, "devs": .number(Double(min(10, max(0, coders)))),
                                           "selfH": 0, "cust": 0, "revW": 0, "int": 50, "tr": 0]))
        return true
    }

    public static func setCoders(_ s: inout GameState, companyID: Int, coders: Int) {
        guard let i = s.companyIndex(companyID), !s.companies[i].value("swp").isNull else { return }
        var sw = s.companies[i].value("swp"); sw["devs"] = .number(Double(min(10, max(0, coders)))); s.companies[i].set("swp", sw)
    }

    public static func setSelfCoding(_ s: inout GameState, companyID: Int, on: Bool) {
        guard let i = s.companyIndex(companyID), !s.companies[i].value("swp").isNull else { return }
        var sw = s.companies[i].value("swp"); sw["selfH"] = .number(on ? 20 : 0); s.companies[i].set("swp", sw)
    }

    public static func setModel(_ s: inout GameState, companyID: Int, model: String, data: GameData) {
        guard let i = s.companyIndex(companyID), !s.companies[i].value("swp").isNull, models.contains(where: { $0.id == model }) else { return }
        let cur = World(state: s, data: data).currency(s.companies[i])
        var sw = s.companies[i].value("swp"); sw["model"] = .string(model); sw["price"] = .number(listPrice(model, scale: cur.scaledPrice)); s.companies[i].set("swp", sw)
    }

    public static func setInternalPercent(_ s: inout GameState, companyID: Int, percent: Int) {
        guard let i = s.companyIndex(companyID), !s.companies[i].value("swp").isNull else { return }
        var sw = s.companies[i].value("swp"); sw["int"] = .number(Double(min(100, max(0, percent)))); s.companies[i].set("swp", sw)
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status == .open && !s.companies[i].value("swp").isNull {
            let co = s.companies[i]
            let cur = World(state: s, data: data).currency(co)
            var sw = co.value("swp")
            let burn = sw["devs"].double * cur.scaledPrice(65000) * 12 / 52
            if burn > 0 { Payments.companyPays(&s, companyID: co.id, amount: burn, category: "wages", label: "Software team") }
            var tr = sw["tr"].double
            var r = DeterministicRandom(seed: Int(HashedRandom.first("\(s.seed):swp:\(s.week):\(co.id)") * 1_000_000_000))
            let out = step(&sw, name: sw["name"].string, quality: clamp(co.reputation / 100, 0, 1), trust: &tr, burn: max(burn, cur.scaledPrice(2000)), random: &r, scale: cur.scaledPrice)
            sw["tr"] = .number(tr)
            guard let j = s.companyIndex(co.id) else { continue }
            s.companies[j].set("swp", sw)
            if out.revenue > 0 { Payments.companyReceives(&s, companyID: co.id, amount: jsRound(out.revenue), category: "rev", label: "Software sales") }
            for n in out.notes { if n.news { s.news(n.text, tone: "good", companyID: co.id) } else { s.note(n.text, tone: "good", companyID: co.id) } }
        }
    }

    public struct Offer: Identifiable, Equatable {
        public var id: Int { producerID }
        public var producerID: Int
        public var name: String
        public var tested: Bool
        public var modelName: String
        public var monthly: Bool
        public var cost: Double
    }

    public static func offers(_ s: GameState, equipmentName: String, buyerID: Int) -> [Offer] {
        let n = equipmentName.lowercased()
        return products(s).filter { p in
            p.usable && p.id != buyerID && (types.first { $0.id == p.type }?.equipmentPattern.contains { n.contains($0) } ?? false)
        }.map { p in
            Offer(producerID: p.id, name: p.name, tested: p.phase == .beta, modelName: p.modelName, monthly: p.model != "once", cost: jsRound(p.price * 4 * Double(p.internalPercent) / 100))
        }
    }

    public enum AdoptResult: Equatable { case ok, notPossible, notEnoughCash }

    @discardableResult
    public static func adopt(_ s: inout GameState, companyID: Int, equipmentID: String, producerID: Int, data: GameData) -> AdoptResult {
        guard let i = s.companyIndex(companyID), let p = product(s, companyID: producerID), p.usable, let bd = data.catalog[s.companies[i].type],
              let e = bd.equipment.first(where: { $0.id == equipmentID }) else { return .notPossible }
        let cost = jsRound(p.price * 4 * Double(p.internalPercent) / 100)
        var eq = s.companies[i].value("eq")
        let had = !eq[equipmentID].isNull
        let mods: JSONValue = .array([.object(["nm": .string(p.name), "n": 1, "rt": 4])])
        if p.model == "once" {
            if cost > 0 && s.companies[i].cash < cost { return .notEnoughCash }
            if cost > 0 {
                Payments.companyPays(&s, companyID: companyID, amount: cost, category: nil, label: "Licence: \(p.name)")
                Payments.companyReceives(&s, companyID: producerID, amount: cost, category: "rev", label: "Licence: \(s.companies[i].name)")
            }
            eq[equipmentID] = .object(["n": 1, "cond": 1, "bv": .number(cost), "cost": .number(cost), "used": 0, "age": 0, "life": .number(e.lifeYears), "soft": "once",
                                       "ver": .number(Double(s.week)), "perf": 1, "rel": 1, "ownF": .number(Double(producerID)), "mods": mods])
        } else {
            eq[equipmentID] = .object(["n": 1, "cond": 1, "bv": 0, "cost": 0, "used": 0, "age": 0, "life": .number(e.lifeYears),
                                       "sub": .object(["tier": 1, "fee": .number(cost), "nm": .string(p.name), "w0": .number(Double(s.week)), "c": -1]),
                                       "perf": 1, "rel": 1, "ownF": .number(Double(producerID)), "mods": mods])
        }
        s.companies[i].set("eq", eq)
        if !had { SpecialFamilies.afterBuy(&s, companyIndex: i, bd, equipmentID: equipmentID, quantity: 1) }
        s.note("\(s.companies[i].name) now uses \(p.name).", tone: "good", companyID: companyID)
        return .ok
    }

    static func useWeek(_ s: inout GameState, companyIndex i: Int, record rec: inout JSONValue) {
        guard !rec["ownF"].isNull else { return }
        guard let p = product(s, companyID: rec["ownF"].int) else { rec["perf"] = 0.8; return }
        if !rec["sub"].isNull { Payments.companyReceives(&s, companyID: p.id, amount: rec["sub"]["fee"].double * 12 / 52, category: "rev", label: "Software subscription") }
        if p.phase == .beta {
            rec["perf"] = 0.85
            if s.random.chance(0.1) { rec["perf"] = 0.6; s.note("\(p.name) (test version) crashed at \(s.companies[i].name) this week.", tone: "bad", companyID: s.companies[i].id) }
        } else { rec["perf"] = 1.03 }
    }
}
