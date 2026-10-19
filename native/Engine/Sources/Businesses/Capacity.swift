import Foundation
import GameCore
import Countries
import Employees

/// One limit on how much a company can serve: a staff role, a machine, the space.
public struct CapacityPart: Equatable {
    public enum Kind: String { case staff, equip, gate, space }
    public var key: String           // "role:barista", "eq:esp", "prem"
    public var label: String
    public var kind: Kind
    /// How many we have, in full-time equivalents / pieces / m²
    public var have: Double
    public var need: Double
    /// How many customers this part can serve in a week
    public var capacity: Double
    public var capacityPerUnit: Double
    /// Owner's share of this role, in FTE
    public var ownerFTE: Double = 0
}

public struct CapacityResult: Equatable {
    /// Customers per week the company can serve
    public var capacity: Double
    public var parts: [CapacityPart]
    /// The part that limits capacity
    public var bottleneck: CapacityPart?
    public var ownerFTE: Double
}

/// How much a company can serve in a week. Original: `capacityCore` (engine/company/model.js) and its
/// 'capacity' steps. Capacity is the smallest of: each staff role's output, required equipment, premises space.
public enum CapacityModel {
    // MARK: Owner's time

    /// Total hours the owner has committed across all companies they run themselves. Original: `hoursUsed`.
    public static func ownerHoursCommitted(_ s: GameState, except: Int? = nil) -> Double {
        let companies = s.companies.filter { $0.id != except && $0.status.isLive && $0.managerID == nil && $0.type != "hold" }
        let startups = (s.rest["founded"]?.array ?? []).filter { $0["st"].string == "live" }
        let dev = startups.reduce(0) { $0 + $1["sw"]["selfH"].double + $1["sw16"]["selfH"].double }
        return companies.reduce(0) { $0 + $1.ownerHours } + dev
    }

    /// Above 55 hours a week you work less well. Original: `ownerFactor`.
    public static func ownerFactor(_ s: GameState) -> Double {
        if let burn = s.rest["burnUntil"], !burn.isNull, Double(s.week) < burn.double { return 0.15 }
        if let sick = s.rest["sickW"], !sick.isNull, sick.int == s.week { return 0 }
        let t = ownerHoursCommitted(s)
        return t <= 55 ? 1 : max(0.6, 1 - (t - 55) * 0.012)
    }

    // MARK: Entry point

    public static func compute(_ co: Company, _ bd: Trade, _ w: World) -> CapacityResult {
        var c = co
        let f = ownerFactor(w.state)
        // While counting, the owner's hours count for what they can really give.
        if !(f == 1 || co.managerID != nil || co.ownerHours == 0) { c.ownerHours = co.ownerHours * f }
        var res = core(c, bd, w, originalOwnerHours: co.ownerHours)
        applySteps(&res, co, bd, w)
        return res
    }

    // MARK: Core

    static func equipmentCount(_ co: Company, _ e: EquipmentSpec) -> Double {
        if e.vehicleModels != nil { return Double(co.value("veh").array.filter { $0["eq"].string == e.id }.count) }
        let own = co.value("eq")[e.id]["n"].double
        let leased = co.value("lease")[e.id].double
        return own + leased
    }

    static func equipmentCondition(_ co: Company, _ e: EquipmentSpec) -> Double {
        if e.vehicleModels != nil {
            let vs = co.value("veh").array.filter { $0["eq"].string == e.id }
            return vs.isEmpty ? 1 : vs.reduce(0) { $0 + $1["cond"].double } / Double(vs.count)
        }
        let rec = co.value("eq")[e.id]
        if rec.isNull { return 1 }
        return min(1.15, rec["cond"].double * pow(rec["perf"].isNull ? 1 : rec["perf"].double, 1.5))
    }

    /// Fraction of the manager's week spent working hands-on. Original: `R24.mgrBase` + `mgrFTE`.
    static func managerHandsOn(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let n = bd.standardStaff.reduce(0) { $0 + $1.count } * co.size
        var base: Double = n < 3 ? 0.85 : n < 6 ? 0.7 : n < 10 ? 0.55 : n < 16 ? 0.35 : 0.15
        let hist = Array(co.monthlyHistory.suffix(3))
        let monthProfit = hist.isEmpty ? 0 : hist.reduce(0) { $0 + $1.profit } / Double(hist.count)
        let m = co.managerID.flatMap { w.state.people[$0] }
        if n >= 10, m != nil, monthProfit > (co.managerMonthlyWage != 0 ? co.managerMonthlyWage : (m?.askingMonthlyWage ?? 50000)) * 4 { base = 0 }
        // How hard the business pushes against its capacity: demand above capacity makes the manager pitch in.
        let h = co.value("wh22").array.suffix(3).filter { !$0["d"].isNull }
        var pressure: Double
        if h.isEmpty {
            let lw = co.value("lastW")
            pressure = lw["cap"].double > 0 ? max(0, min(1, ((lw["D"].double) / lw["cap"].double - 0.95) / 0.3)) : 0
        } else {
            let d = h.reduce(0) { $0 + min(3, $1["d"].double) } / Double(h.count)
            pressure = max(0, min(1, (d - 0.95) / 0.3))
        }
        let surge = (n < 10 ? 0.35 : 0.6) * pressure
        return min(1, base + surge)
    }

    static func core(_ co: Company, _ bd: Trade, _ w: World, originalOwnerHours: Double) -> CapacityResult {
        var parts: [CapacityPart] = []
        let capD = bd.normalCapacity
        let tables = w.catalog.tables
        let staff = co.staff
        let ownerF = co.managerID != nil ? managerHandsOn(co, bd, w) : co.ownerHours / 40
        let over = max(0, (co.ownerHours - 40) / 40)
        let people = w.state.people
        let ownerEff: Double
        if let mid = co.managerID {
            let m = people[mid]
            let best = staff.reduce(0.0) { max($0, StaffModel.skill($1, person: people[$1.id], salesRoles: tables.salesRoles)) }
            let ops = (m?.raw["stats"]?["ops"].isNull ?? true) ? 50 : m!.raw["stats"]!["ops"].double
            ownerEff = 0.75 + 0.5 * min(95, max(ops, best + 3)) / 100
        } else {
            ownerEff = (0.75 + 0.5 * co.ownerSkill / 100)
        }
        for (i, s) in bd.standardStaff.enumerated() {
            let nRef = s.count + (i == 0 ? bd.ownerFTE : 0)
            let capPer = capD / nRef / 0.92
            let fte = StaffModel.fullTimeEquivalents(role: s.role, staff: staff, people: people, week: w.week, salesRoles: tables.salesRoles)
            parts.append(CapacityPart(key: "role:\(s.role)", label: tables.roles[s.role]?.name ?? s.role, kind: .staff, have: fte,
                                      need: s.count * co.size, capacity: fte * capPer, capacityPerUnit: capPer))
        }
        let ownerTotal = ownerF * ownerEff
        var left = ownerTotal
        var guardCount = 0
        while left > 0.01 && !parts.isEmpty && guardCount < 40 {
            guardCount += 1
            let step = min(0.25, left)
            var mi = 0
            for i in 1..<parts.count where parts[i].capacity < parts[mi].capacity { mi = i }
            parts[mi].have += step
            parts[mi].capacity += step * parts[mi].capacityPerUnit
            parts[mi].ownerFTE += step
            left -= step
        }
        var availability = 1.0   // a required machine in repair for part of the week: the business works the rest
        for e in bd.equipment {
            let n = equipmentCount(co, e)
            let cond = equipmentCondition(co, e)
            if e.isRequired && n < 1 && n > 0.01 && equipmentCount(co, e) >= 1 {
                availability = min(availability, n)
            } else if e.isRequired && n < 1 {
                parts.append(CapacityPart(key: "eq:\(e.id)", label: e.name + " (required)", kind: .gate, have: 0, need: 1, capacity: 0, capacityPerUnit: 0))
            } else if e.limitsCapacity && e.standardCount > 0 {
                let cp = capD / e.standardCount
                parts.append(CapacityPart(key: "eq:\(e.id)", label: e.name, kind: .equip, have: n,
                                          need: max(1, jsRound(e.standardCount * co.size)), capacity: n * cp * (0.7 + 0.3 * cond), capacityPerUnit: cp))
            }
        }
        if let kind = bd.premisesKind, bd.premisesM2 > 0, tables.premises[kind] != nil, co.value("prem")["m2"].double > 0 {
            let m2 = co.value("prem")["m2"].double
            parts.append(CapacityPart(key: "prem", label: "Space (\(Int(m2)) m2)", kind: .space, have: m2,
                                      need: jsRound(bd.premisesM2 * co.size), capacity: capD * m2 / bd.premisesM2, capacityPerUnit: 0))
        }
        var cap = Double.infinity
        var bot: CapacityPart? = nil
        for p in parts where p.capacity < cap { cap = p.capacity; bot = p }
        if !cap.isFinite { cap = capD }
        cap *= Knobs.effect(co, bd, "k", w, sum: false) * DemandModel.modifier(co, "cap") * (over > 0 ? 1 + over * 0.2 : 1) * availability
        return CapacityResult(capacity: max(0, cap), parts: parts, bottleneck: bot, ownerFTE: ownerTotal)
    }

    // MARK: Steps (original `addStep('capacity', ...)`)

    static func recompute(_ r: inout CapacityResult) {
        var cap = Double.infinity
        var bot: CapacityPart? = nil
        for p in r.parts where p.capacity < cap { cap = p.capacity; bot = p }
        r.bottleneck = bot
    }

    static func applySteps(_ r: inout CapacityResult, _ co: Company, _ bd: Trade, _ w: World) {
        let noWork = Pricing.noWorkFamilies.contains(bd.family)
        // 10: small firms: the owner covers support jobs
        if bd.family == "project" && !bd.hasTrait("dev") { r.capacity *= (w.balance.priceLevelByTrade[bd.id] ?? 1).squareRoot() }
        if bd.standardStaff.count >= 2 && !noWork {
            let minOld = r.parts.map { $0.capacity }.min() ?? 0
            let mult: Double? = minOld > 0 ? r.capacity / minOld : nil
            var changed = false
            for (i, s) in bd.standardStaff.enumerated() where i > 0 {
                guard let pi = r.parts.firstIndex(where: { $0.key == "role:\(s.role)" }), !co.staff.contains(where: { $0.role == s.role }) else { continue }
                let cover = r.parts[pi].capacityPerUnit * 0.45 * (co.size <= 0.6 ? 1 : 0.4)
                if cover > r.parts[pi].capacity { r.parts[pi].capacity = cover; changed = true }
            }
            if changed, let m = mult {
                var cap = Double.infinity
                var bot: CapacityPart? = nil
                for p in r.parts where p.capacity < cap { cap = p.capacity; bot = p }
                r.capacity = max(0, cap * m)
                r.bottleneck = bot
            }
        }
        // 50: services sell hours
        if let t = hoursPerUnit[bd.id] {
            let per = 37.5 * t.productiveShare / t.hours
            if let role0 = r.parts.first(where: { $0.kind == .staff }), role0.capacityPerUnit > 0 {
                let R = max(1, per / role0.capacityPerUnit)
                let ownFTE = r.parts.reduce(0) { $0 + $1.ownerFTE }
                let ownUnits = co.managerID != nil ? ownFTE * role0.capacityPerUnit * R
                    : co.ownerHours * t.productiveShare / t.hours * (0.85 + 0.3 * co.ownerSkill / 100)
                var cap = Double.infinity
                var bot: CapacityPart? = nil
                for i in r.parts.indices {
                    switch r.parts[i].kind {
                    case .staff:
                        let p = r.parts[i]
                        r.parts[i].capacity = max(0, p.have - p.ownerFTE) * p.capacityPerUnit * R + (ownFTE > 0 ? ownUnits * p.ownerFTE / ownFTE : 0)
                    case .equip:
                        r.parts[i].capacity = max(r.parts[i].capacity * R, r.parts[i].have * 60 * t.productiveShare / t.hours)
                    case .space:
                        r.parts[i].capacity *= R
                    case .gate: break
                    }
                    if r.parts[i].capacityPerUnit != 0 { r.parts[i].capacityPerUnit *= R }
                    if r.parts[i].capacity < cap { cap = r.parts[i].capacity; bot = r.parts[i] }
                }
                if cap.isFinite {
                    r.capacity = max(0, cap * Knobs.effect(co, bd, "k", w) * DemandModel.modifier(co, "cap"))
                    r.bottleneck = bot
                }
            }
        }
        // 60: a small team covers the support jobs
        smallTeamCoversSupportJobs(&r, co, bd)
        // 70: own premises: shorter trips for mobile trades
        if mobileTrades.contains(co.type) && bd.premisesKind == "home" && co.value("prem")["m2"].double > 0 { r.capacity *= 1.08 }
        // 80: storms and snow stop outdoor work
        let c = Weather.effect(for: co, trade: bd, week: w.week, seed: w.state.seed, tables: w.balance.weather).capacity
        if r.capacity != 0 && c != 1 { r.capacity *= c }
    }

    static let mobileTrades: Set<String> = ["plumber", "electrician", "construction", "cleaning", "handy", "carclean", "event"]

    /// Hours per unit sold, and the productive share of working hours, for trades that sell time. Original: `R34.T`.
    static let hoursPerUnit: [String: (hours: Double, productiveShare: Double)] = [
        "cons": (1, 0.7), "law": (1, 0.7), "acctfirm": (1, 0.75), "mktg": (1, 0.7), "webdev": (1, 0.75), "tutor": (1, 0.8), "cleaning": (1, 0.9),
        "carclean": (1.5, 0.8), "carrepair": (2.5, 0.8), "handy": (3, 0.75), "photo": (6, 0.7), "barber": (0.75, 0.8), "drivsk": (1, 0.85),
        "physio": (0.75, 0.8), "pets": (0.5, 0.85), "estate": (50, 0.6), "dental": (0.75, 0.8), "gamestudio": (1, 0.75), "security": (1, 0.9),
    ]

    /// In a company of up to three people the owner and team also cover the support jobs. Original: R39 step.
    static func smallTeamCoversSupportJobs(_ r: inout CapacityResult, _ co: Company, _ bd: Trade) {
        if co.managerID != nil || !r.capacity.isFinite { return }
        let sp = r.parts.indices.filter { r.parts[$0].kind == .staff }
        if sp.count < 2 { return }
        let ownFTE = sp.reduce(0) { $0 + r.parts[$1].ownerFTE }
        let heads = co.staff.count + (co.ownerHours > 0 ? 1 : 0)
        if heads > 3 || heads < 1 { return }
        let minOld = r.parts.map { $0.capacity.isFinite ? $0.capacity : Double.infinity }.min() ?? 0
        let mult = minOld > 0 ? r.capacity / minOld : 1
        let coreIdx = sp[0]
        func employees(_ p: CapacityPart) -> Double { max(0, p.have - p.ownerFTE) }
        let core = r.parts[coreIdx]
        let ownCore = max(0, core.capacity - employees(core) * core.capacityPerUnit)
        let coreCap = employees(core) * core.capacityPerUnit + (core.ownerFTE > 0 ? ownCore * ownFTE / core.ownerFTE : ownFTE * core.capacityPerUnit)
        var uncovered = 0
        var covered: Set<Int> = []
        for i in sp.dropFirst() {
            if employees(r.parts[i]) < 0.5 { uncovered += 1; r.parts[i].capacity = .infinity; covered.insert(i) }
            else { r.parts[i].capacity = employees(r.parts[i]) * r.parts[i].capacityPerUnit * 1.15 }
        }
        let pen = max(0.65, 1 - 0.1 * Double(uncovered))
        r.parts[coreIdx].capacity = coreCap * pen
        var cap = Double.infinity
        var bot: CapacityPart? = nil
        for p in r.parts where p.capacity < cap { cap = p.capacity; bot = p }
        for i in covered { r.parts[i].capacity = r.parts[coreIdx].capacity }
        if !cap.isFinite { return }
        r.capacity = max(0, cap * mult)
        r.bottleneck = bot
    }
}
