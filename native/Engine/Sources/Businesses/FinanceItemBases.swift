import Foundation
import GameCore
import Countries
import Finance

/// The product lines of each finance trade, read from the books the existing models keep (`fm` on the company, the week's `lastW`). Pure reads: no cash moves.
extension FinanceItems {
    static func knobIndex(_ co: Company, _ id: String, def: Int, max top: Int) -> Int {
        let v = co.value("knob")[id]
        return v.isNull ? def : min(top, Swift.max(0, v.int))
    }

    // MARK: Insurance: one item per cover

    static func insuranceBases(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World, mt: Double) -> [Base] {
        let fm = co.value("fm"), tables = w.catalog.tables, sp = spec["insco"]
        let prods = FinanceModel.products(tables)
        let pol = fm["pol"].double, premW = fm["premW"].double
        let lr0 = fm["lossR"].double > 0 ? fm["lossR"].double : (bd.trait("lossR") ?? 0.66)
        let cover = fm["cover"].isNull ? 1 : fm["cover"].double
        let run = 0.12 * (0.8 + 0.2 * min(1, cover))
        var wts: [Double] = [], on: [Bool] = []
        for p in prods {
            let ok = FinanceModel.isOffered(co, p.id) && Knobs.documentOK(co, p.documentID)
            let cv = clamp(FinanceModel.verifiedAgents(co, product: p.id, week: w.week, people: s.people, salesRoles: tables.salesRoles) / max(0.8, 1.2 * co.size), 0, 1)
            on.append(ok)
            wts.append(ok ? p.volume * (0.15 + 0.85 * cv) : 0)
        }
        let total = wts.reduce(0, +)
        let pols = wts.map { total > 0 ? pol * $0 / total : 0 }
        let sumPP = prods.indices.reduce(0.0) { $0 + pols[$1] * prods[$1].premium }
        let k = (pol > 0 && sumPP > 0) ? premW * 52 / sumPP : mt
        let prem = prods.indices.map { pols[$0] * k * prods[$0].premium }
        let premSum = prem.reduce(0, +)
        let lossNorm = premSum > 0 ? prods.indices.reduce(0.0) { $0 + prem[$1] * prods[$1].lossFactor } / premSum : 1
        let invInc = min(max(0, co.cash), premW * 52 * 2.5) * max(0, s.economy.policyRate - 0.008) / 52
        let creditShare = premW > 0 ? invInc / premW : 0
        let catW = co.value("flags")["catW"].double > 0
        return prods.indices.map { n in
            let p = prods[n]
            var b = Base(id: p.id, name: sp["names"][p.id].isNull ? p.name : sp["names"][p.id].string, kind: "Insurance cover", unitWord: "policy", priceUnit: "a year")
            let price = k * p.premium
            let lr = lr0 * p.lossFactor / (lossNorm > 0 ? lossNorm : 1)
            b.units = pols[n]; b.volume = pols[n] / 52; b.price = price
            b.parts = [Part(label: "Expected claims", perUnit: price * lr), Part(label: "Claims handling and running costs", perUnit: price * run)]
            b.credit = price * creditShare
            b.weight = b.volume * price
            b.size = pols[n] * price; b.sizeLabel = "Premium a year"
            b.reserve = b.size * sp["reserveShare"].double; b.reserveLabel = "Solvency capital held"
            b.riskLabel = "Claims a policy a year"; b.risk = price * lr; b.stress = price * lr * (catW ? 1 : 1.5)
            b.swing = 0.14 / sqrt(max(1, pols[n] / 1000))
            b.note = on[n] ? "Claims vary by about \(Int(saturating: (b.swing * 100).rounded()))% a year on this book; a storm year runs claims 50% higher." : "Not on offer yet: switch the cover on, get the approval and verify agents."
            return b
        }
    }

    // MARK: Bank: loan types and deposit accounts

    static func bankBases(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World, mt: Double) -> [Base] {
        let fm = co.value("fm"), sp = spec["bank"], cur = w.currency(co)
        let book = fm["book"].double, dep = fm["dep"].double
        let policy = s.economy.policyRate
        let nim = bd.trait("nim") ?? 0.031, capReq = bd.trait("capitalReq") ?? 0.16
        let wholesale = co.value("knob")["liq"].int == 1
        let loanM = (nim + 0.012) * Knobs.effect(co, bd, "t", w)
        let segKey = ["mort", "mix", "sme"][knobIndex(co, "seg", def: 1, max: 2)]
        let mix = sp["mix"][segKey].array.map { $0.double }
        let loans = sp["loans"].array
        let fNorm = loans.indices.reduce(0.0) { $0 + mix[$1] * loans[$1]["margin"].double }
        let lNorm = loans.indices.reduce(0.0) { $0 + mix[$1] * loans[$1]["loss"].double }
        let creditStaff = FinanceModel.fte(co, "credit", w, s.people) / max(0.5, 3 * co.size)
        let stress = { (d: Double) in 1 + max(0, 1 - d) * 8 }
        let baseLoss = 0.0035 * Knobs.effect(co, bd, "r", w) * stress(w.economy.demand) * (1.1 - 0.4 * min(1, creditStaff))
        let stressF = stress(sp["stressDemand"].double) / stress(w.economy.demand)
        var out: [Base] = []
        for (n, l) in loans.enumerated() {
            let avg = cur.scaledPrice(l["bal"].double)
            let bal = book * mix[n]
            let rate = policy + loanM * 0.62 * l["margin"].double / max(1e-9, fNorm)
            let lossRate = baseLoss * l["loss"].double / max(1e-9, lNorm)
            var b = Base(id: l["id"].string, name: l["n"].string, kind: "Loan", unitWord: "customer", priceUnit: "a year")
            b.units = avg > 0 ? bal / avg : 0; b.volume = b.units / 52; b.price = avg * rate
            b.parts = [Part(label: "Funding at the central bank rate", perUnit: avg * policy), Part(label: "Expected credit loss", perUnit: avg * lossRate)]
            b.weight = b.volume * b.price
            b.size = bal; b.sizeLabel = "Loan balance"
            b.reserve = bal * capReq; b.reserveLabel = "Capital held against it"
            b.riskLabel = "Credit loss a customer a year"; b.risk = avg * lossRate; b.stress = avg * lossRate * stressF
            b.swing = 0.3
            b.note = "Rate \(String(format: "%.1f", rate * 100))% on an average balance; in a downturn (demand \(Int(sp["stressDemand"].double * 100))) credit losses run \(String(format: "%.1f", stressF))x."
            out.append(b)
        }
        let depBase = max(0, policy - 0.006 + (wholesale ? 0.012 : 0))
        let deps = sp["deposits"].array
        let dNorm = deps.reduce(0.0) { $0 + $1["share"].double * $1["rate"].double }
        for d in deps {
            let avg = cur.scaledPrice(d["bal"].double)
            let bal = dep * d["share"].double
            let paid = depBase * d["rate"].double / max(1e-9, dNorm)
            var b = Base(id: d["id"].string, name: d["n"].string, kind: "Deposit account", unitWord: "customer", priceUnit: "a year")
            b.units = avg > 0 ? bal / avg : 0; b.volume = b.units / 52; b.price = avg * policy
            b.parts = [Part(label: "Interest paid to the saver", perUnit: avg * paid)]
            b.weight = b.volume * b.price
            b.size = bal; b.sizeLabel = "Deposits held"
            b.note = "Worth the central bank rate to the bank as funding; pays \(String(format: "%.1f", paid * 100))%. " + (wholesale ? "Funding is partly wholesale." : "Deposit funding only.")
            out.append(b)
        }
        return out
    }

    // MARK: Fund: one item per fee class

    static func fundBases(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World, mt: Double) -> [Base] {
        let fm = co.value("fm"), sp = spec["fund"], cur = w.currency(co)
        let aum = fm["aum"].double
        let mgmt = bd.trait("mgmt") ?? 0.015
        let knobT = Knobs.effect(co, bd, "t", w)
        let betaS = [0.9, 1.0, 0.7][knobIndex(co, "strat", def: 1, max: 2)]
        let classes = sp["classes"].array
        let norm = classes.reduce(0.0) { $0 + $1["share"].double * $1["fee"].double }
        let avg = cur.scaledPrice(sp["avgClient"].double)
        return classes.map { c in
            let rate = mgmt * knobT * c["fee"].double / max(1e-9, norm)
            let a = aum * c["share"].double
            var b = Base(id: c["id"].string, name: c["n"].string, kind: "Fee class", unitWord: "client", priceUnit: "a year")
            b.units = avg > 0 ? a / avg : 0; b.volume = b.units / 52; b.price = avg * rate
            b.weight = a
            b.size = a; b.sizeLabel = "Assets under management"
            b.riskLabel = "Fee lost if markets fall \(Int(sp["fall"].double * 100))%"
            b.risk = b.price * sp["fall"].double * c["beta"].double * betaS
            b.stress = b.risk
            b.swing = sp["fall"].double * c["beta"].double * betaS
            b.note = "Fee \(String(format: "%.2f", rate * 100))% a year. The performance fee (paid once a year on the whole fund above its high-water mark) is not in this fee."
            return b
        }
    }

    // MARK: Power: one item per tariff

    static func powerBases(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World, mt: Double) -> [Base] {
        let sp = spec["power"], lw = co.value("lastW")
        let out = lw["units"].double
        let hedge = EnergyModel.hedgeShare[knobIndex(co, "hedge", def: 0, max: 2)]
        let idx = s.economy.inflationIndex
        let dem = DemandModel.modifier(co, "dem")
        let spot = 650 * s.economy.power * idx * dem, fixed = 650 * idx * 0.95 * dem
        let running = out > 0 ? lw["cogs"].double / out : 0
        var depWeekly = 0.0
        for e in bd.allEquipment {
            let n = CapacityModel.equipmentCount(co, e)
            guard n > 0 else { continue }
            let rec = co.value("eq")[e.id]
            let cost = rec["cost"].isNull ? e.cost * n : rec["cost"].double
            depWeekly += cost / max(1, e.lifeYears) / 52
        }
        let dep = out > 0 ? depWeekly / out : 0
        let src = EnergyModel.source(of: co)
        let mw = co.value("fm")["mw"].double
        return sp["tariffs"].array.map { t in
            let isSpot = t["kind"].string == "spot"
            let frac = isSpot ? 1 - hedge : hedge * t["part"].double
            var b = Base(id: t["id"].string, name: t["n"].string, kind: "Tariff", unitWord: "MWh", priceUnit: "MWh")
            b.volume = out * frac; b.units = b.volume
            b.price = isSpot ? spot : fixed
            b.parts = [Part(label: "Running cost of the plant", perUnit: running), Part(label: "Depreciation of the plant", perUnit: dep)]
            b.weight = b.volume
            b.size = b.volume; b.sizeLabel = "MWh a week"
            b.riskLabel = isSpot ? "Revenue swing for a \(Int(sp["move"].double * 100))% move in the spot price" : "Locked price: costs and output carry the risk"
            b.risk = isSpot ? b.price * sp["move"].double : 0
            b.stress = b.risk
            b.swing = isSpot ? sp["move"].double : 0
            b.note = mw > 0 ? "Generated by \(src.name), \(Int(saturating: mw.rounded())) MW, built into the plant cost. Output follows the season." : "No output yet: the plant is not built or not ready."
            if frac == 0 && out > 0 { b.note += " Not sold now: the price strategy is \(isSpot ? "fully hedged" : "spot")." }
            return b
        }
    }

    // MARK: Oil and gas: one item per field

    static func oilBases(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World, mt: Double) -> [Base] {
        let sp = spec["oilgas"], fm = co.value("fm")
        let contracts = co.value("knob")["sell"].int == 1
        let term = contracts ? sp["termShare"].double : 0
        let dem = DemandModel.modifier(co, "dem")
        let price = EnergyModel.oilPrice(contracts: contracts, economyOil: s.economy.oil, inflationIndex: s.economy.inflationIndex) * dem
        let lift = EnergyModel.liftingCost(materials: s.economy.materials, inflationIndex: s.economy.inflationIndex)
        let fte = FinanceModel.fte(co, "offshore", w, s.people)
        let crew = min(1, fte / max(1, 10 * co.size))
        let capMod = DemandModel.modifier(co, "cap")
        var out: [Base] = []
        for f in fm["fields"].array where f["st"].string != "depleted" {
            let res = f["res"].double
            var b = Base(id: "f\(f["id"].int)", name: f["name"].string, kind: "Field", unitWord: "barrel", priceUnit: "barrel")
            b.model = .proj
            b.price = price
            let prod = f["st"].string == "prod"
            var bbl = 0.0, years = 0.0
            if prod {
                let bv = f["bv"].isNull ? res * 1000 * 190 : f["bv"].double
                let r = EnergyModel.fieldWeek(reserves: res, initialRate: f["q0"].double, age: f["age"].int, plateau: f["plat"].double, capacityModifier: capMod, crew: crew, noise: 0, bookValue: bv)
                bbl = r.barrels * 1000
                years = bbl > 0 ? res * 1000 / bbl / 52 : 0
                b.parts = [Part(label: "Lifting cost", perUnit: lift), Part(label: "Depletion of the field", perUnit: res > 0 ? bv / (res * 1000) : 0)]
                b.note = "About \(String(format: "%.0f", years)) years of output left at this rate; output declines after the plateau."
            } else {
                let capex = f["capex"].double
                b.parts = [Part(label: "Lifting cost", perUnit: lift), Part(label: "Development paid back per barrel", perUnit: res > 0 ? capex / (res * 1000) : 0)]
                b.note = "In development: first oil in \(f["wl"].int) weeks. Nothing is sold until then."
            }
            b.volume = bbl; b.units = bbl
            b.weight = bbl
            b.size = res * 1000; b.sizeLabel = "Barrels in the ground"
            b.riskLabel = "Revenue swing for a \(Int(sp["move"].double * 100))% move in the oil price"
            b.risk = price * (1 - term) * sp["move"].double
            b.stress = price * (1 - term) * 0.4
            b.swing = (1 - term) * 0.4
            out.append(b)
        }
        return out
    }

    // MARK: Holding: group services at cost plus a margin

    static func holdBases(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World, mt: Double, overhead: Double) -> [Base] {
        let sp = spec["hold"]
        let n = HoldingModel.subsidiaries(of: co.id, in: s).count
        let vol = Double(max(1, n))
        return sp["services"].array.map { x in
            var b = Base(id: x["id"].string, name: x["n"].string, kind: "Group service", unitWord: "subsidiary", priceUnit: "a week")
            let share = overhead * x["w"].double / vol
            b.units = Double(n); b.volume = vol
            b.price = share * (1 + sp["margin"].double)
            b.weight = x["w"].double
            b.size = Double(n); b.sizeLabel = "Subsidiaries served"
            b.note = "A transfer price: the fee that covers this service plus \(Int(sp["margin"].double * 100))%. It is shown against the holding's own costs and moves no cash between the companies."
            return b
        }
    }
}
