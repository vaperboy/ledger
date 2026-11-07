import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Event chains: what happens some weeks after a lawsuit, a breakdown, a resignation, a supplier failure, a cyber attack,
/// a failed inspection or a lucky break. No new systems: a trigger queues a follow-up (`AftermathQueue`), and when it falls due
/// the follow-up is fired as an ordinary event (`EventEngine.fire`), so it reaches the Inbox with costs, deadline and default,
/// is decided by a manager if one has authority, takes the cheapest answer when ignored, and changes state through `EventEngine.apply`.
/// Every queued follow-up and every outcome is also written to the week's report with `s.note(..., companyID:)`.
///
/// Chains (trigger -> follow-up, delay):
///  1 lawsuit lost -> reviews dip (now), insurer reprices `premium` (2 wk)        2 big lawsuit lost -> `copycat` claim (7 wk)
///  3 quick fix of kit -> `relapse` (4-6 wk)      4 worker leaves -> capacity drop (now) and `hire` (2 wk)   5 worker leaves -> `headhunt` (4 wk)
///  6 supplier bankrupt/dearer -> `negotiate` (6-8 wk)      7 supplier bankrupt, waited -> `shortage` (2 wk)
///  8 cyber attack -> `secreview` (3 wk)      9 failed inspection -> `reinspect` (4 wk)
/// 10 new rival -> `distressed` rival for sale (8 wk)   11 big order taken -> `bulk` standing deal (6 wk)   12 roadworks over -> `premises` offer (8 wk)
public enum Aftermath {
    static let prefix = "aft_"

    /// The follow-up events, as data in the same shape as events.json.
    static let templates: [String: String] = [
        "premium": #"{"t":"The insurer reprices {n} after the lost court case.","cat":"none","tone":"bad","exp":3,"opts":[{"l":"Accept the new terms","d":"Free today. Insurance bill +20% for 26 weeks.","fx":{"premUp":0.2,"premWeeks":26}},{"l":"Shop around with a broker","d":"Small broker fee now, bill only +8% for 26 weeks. Slow but safe.","fx":{"cash":-4000,"premUp":0.08,"premWeeks":26}},{"l":"Put a risk-control plan in place","d":"Training and signage cost a fifth of a week's sales; bill +5% for 26 weeks and quality +2.","fx":{"cash":{"expr":"-wk * 0.2"},"premUp":0.05,"premWeeks":26,"q":2}}]}"#,
        "relapse": #"{"t":"{eq} at {n} is acting up again after the quick fix.","cat":"prop","tone":"bad","exp":3,"opts":[{"l":"Overhaul or replace it","d":"Costs most now, back to like-new. Ends the problem.","fx":{"cash":{"expr":"-max(6000, eqv * 0.12)"},"fixeq":2}},{"l":"Patch it again","d":"Cheap, but it will only hold to the usual condition. Risk of another failure later.","fx":{"cash":{"expr":"-max(2000, eqv * 0.03)"},"fixeq":1}},{"l":"Keep running it as it is","d":"Free now. Capacity -25% for 4 weeks, and customers drift away for about 8 weeks (demand -7%, reputation down).","fx":{"cap":[0.75,4],"dem":[0.93,8],"rep":-1}}]}"#,
        "hire": #"{"t":"{n} is a person short since the resignation.","cat":"none","tone":"bad","exp":3,"opts":[{"l":"Wait and let the others cope","d":"Free. Service slips: demand -5% for 6 weeks.","fx":{"dem":[0.95,6],"rep":-0.5}},{"l":"Pay overtime","d":"About a third of a week's payroll. Capacity +5% for 4 weeks.","fx":{"cash":{"expr":"-pay * 0.3"},"cap":[1.05,4]}},{"l":"Use a staffing agency","d":"A full week's payroll plus fee. Capacity +10% for 3 weeks while you recruit.","fx":{"cash":{"expr":"-pay * 1.2"},"cap":[1.1,3]}}]}"#,
        "headhunt": #"{"t":"A rival has made a job offer to your best remaining person at {n}.","cat":"none","tone":"bad","exp":3,"opts":[{"l":"Let them go","d":"Free now. Capacity -10% for 4 weeks and you lose the person.","fx":{"quit":1,"cap":[0.9,4]}},{"l":"Counter-offer with a raise","d":"Raise 10% for good plus a signing sweetener. 90% chance they stay.","fx":{"raise":0.1,"stay":0.9,"cash":{"expr":"-pay * 0.1"}}},{"l":"Offer a retention bonus","d":"A third of a week's payroll once. 60% chance they stay.","fx":{"cash":{"expr":"-pay * 0.3"},"stay":0.6,"raise":0}}]}"#,
        "negotiate": #"{"t":"The supplier of {n} wants to settle terms after the disruption.","cat":"none","tone":"n","exp":3,"opts":[{"l":"Do nothing","d":"Free. Costs stay up about 6% for 8 weeks.","fx":{"price":[1.06,8]}},{"l":"Sign a 26-week fixed-price contract","d":"Deposit now. Costs only +3% for 26 weeks, even if the market rises.","fx":{"cash":-3000,"price":[1.03,26]}},{"l":"Audition a cheaper new supplier","d":"Trial order now. 60%: costs 3% below today's for 20 weeks. 40%: quality slips, reputation falls and costs +4%.","fx":{"cash":-2000,"gamble":{"p":0.6,"ok":{"price":[0.97,20]},"bad":{"q":-3,"rep":-1,"price":[1.04,8]}}}}]}"#,
        "shortage": #"{"t":"Stock is running short at {n} while the supplier trouble drags on.","cat":"none","tone":"bad","exp":2,"opts":[{"l":"Ration and take back-orders","d":"Free. Demand -10% for 3 weeks and reputation falls.","fx":{"dem":[0.9,3],"rep":-1}},{"l":"Buy at a wholesaler","d":"Cash-and-carry prices: a twentieth of a week's sales, costs +4% for 3 weeks, demand -4%.","fx":{"cash":{"expr":"-wk * 0.05"},"dem":[0.96,3],"price":[1.04,3]}},{"l":"Buy emergency stock at spot prices","d":"An eighth of a week's sales, costs +8% for 4 weeks. Shelves stay full.","fx":{"cash":{"expr":"-wk * 0.12"},"price":[1.08,4]}}]}"#,
        "secreview": #"{"t":"The attack on {n} showed where the gaps are. What do you fix?","cat":"none","tone":"bad","exp":3,"opts":[{"l":"Leave it","d":"Free. Attackers mark you as a soft target: attack odds x1.8 for 26 weeks.","fx":{"cyberTarget":1}},{"l":"Train the staff","d":"About a tenth of a week's sales. Trained staff cut odds by a quarter for a year.","fx":{"cash":{"expr":"-max(1500, wk * 0.1)"},"cyberTrain":1}},{"l":"Upgrade security and train","d":"Over half a week's sales now, then the monthly fee of managed security. Odds fall to a quarter.","fx":{"cash":{"expr":"-wk * 0.6"},"cyberLvl":2,"cyberTrain":1}}]}"#,
        "reinspect": #"{"t":"The inspectors are coming back to {n} to check the fixes.","cat":"none","tone":"bad","exp":3,"opts":[{"l":"Ignore it","d":"Free. 65% chance of a repeat fine, reputation -3 and a warning that scares customers for 6 weeks.","fx":{"gamble":{"p":0.65,"ok":{"fine":15000,"rep":-3,"warn":1},"bad":{}}}},{"l":"Quick self-check","d":"Small cost. 55% pass and reputation +0.5; 45% a fine and reputation -2.","fx":{"cash":-1500,"gamble":{"p":0.55,"ok":{"rep":0.5},"bad":{"fine":12000,"rep":-2}}}},{"l":"Hire a consultant and fix it all","d":"Costs 15% of a week's sales (min 5,000). Quality +2, reputation +0.5, passes.","fx":{"cash":{"expr":"-max(5000, wk * 0.15)"},"q":2,"rep":0.5}}]}"#,
        "distressed": #"{"t":"A struggling rival near {n} is selling up. Offers close soon.","cat":"none","tone":"good","exp":3,"opts":[{"l":"Pass","d":"Free. Someone else takes the customers.","fx":{}},{"l":"Make a small offer for the customer list","d":"Half a week's sales. 50%: demand +12% for 10 weeks. 50%: they refuse, money lost.","fx":{"cash":{"expr":"-wk * 0.5"},"gamble":{"p":0.5,"ok":{"dem":[1.12,10]},"bad":{}}}},{"l":"Buy the customers and stock","d":"Three weeks of sales. Demand +18% for 12 weeks and awareness +6, but you need spare capacity.","fx":{"cash":{"expr":"-wk * 3"},"dem":[1.18,12],"aware":6,"needCap":1}}]}"#,
        "bulk": #"{"t":"The big customer wants a standing supply deal with {n}. Reply within two weeks.","cat":"none","tone":"good","exp":2,"opts":[{"l":"Decline","d":"Free. They go elsewhere.","fx":{}},{"l":"Hold out for a fair price","d":"50%: demand +20% for 20 weeks. 50%: they walk, nothing changes.","fx":{"gamble":{"p":0.5,"ok":{"dem":[1.2,20]},"bad":{}}}},{"l":"Sign at a keen price","d":"Lower prices for good, demand +25% for 26 weeks. Needs spare capacity or you cannot deliver.","fx":{"pr":-1,"dem":[1.25,26],"needCap":1}}]}"#,
        "premises": #"{"t":"The landlord of {n} makes an offer now the roadworks are over.","cat":"none","tone":"good","exp":3,"opts":[{"l":"Decline","d":"Free. Nothing changes.","fx":{}},{"l":"Negotiate a rent break","d":"60%: a rebate of most of a week's sales. 40%: the landlord stands firm.","fx":{"gamble":{"p":0.6,"ok":{"cash":{"expr":"wk * 0.8"}},"bad":{}}}},{"l":"Renovate and relaunch","d":"A week and a half of sales, landlord pays half. Quality +3, awareness +6, demand +8% for 26 weeks.","fx":{"cash":{"expr":"-wk * 1.5"},"q":3,"aware":6,"dem":[1.08,26]}}]}"#,
    ]


    static func event(_ kind: String) -> GameEvent? {
        guard let src = templates[kind], let json = try? JSONDecoder().decode(JSONValue.self, from: Data(src.utf8)) else { return nil }
        return GameEvent(id: prefix + kind, json: json)
    }

    static func jitter(_ s: GameState, _ id: Int, _ tag: String, _ n: Int) -> Int {
        var h = HashedRandom("\(s.seed):aft:\(s.week):\(id):\(tag)")
        return min(n - 1, Int(h.next() * Double(n)))
    }

    // MARK: Triggers

    static func queue(_ s: inout GameState, _ i: Int, _ kind: String, delay: Int, why: String) {
        let co = s.companies[i]
        if AftermathQueue.schedule(&s, companyID: co.id, kind: kind, delay: delay) {
            s.note("\(co.name): \(why) A follow-up is due in about \(delay) weeks.", tone: "n", companyID: co.id)
        }
    }

    /// Called after any event's effects are applied (answered, taken by default, or chosen by a manager).
    static func afterEffects(_ s: inout GameState, _ i: Int, event e: GameEvent, fx: JSONValue, data: GameData) {
        extras(&s, i, fx: fx, data: data)
        let co = s.companies[i]
        switch e.id {
        case "g_break", "pr_machine", "l_break":
            if fx["fixeq"].double == 1 { queue(&s, i, "relapse", delay: 4 + jitter(s, co.id, e.id, 3), why: "The quick fix may not hold.") }
        case "g_supbust":
            if !fx["price"].isNull { queue(&s, i, "negotiate", delay: 6 + jitter(s, co.id, e.id, 3), why: "The new supplier will want terms.") }
            if !fx["cap"].isNull { queue(&s, i, "shortage", delay: 2, why: "Shelves will run low while you wait.") }
        case "g_supply":
            if fx["price"][0].double > 1 { queue(&s, i, "negotiate", delay: 8, why: "The supplier will come back to settle terms.") }
        case "g_offer":
            if fx["dem"][0].double >= 1.15 { queue(&s, i, "bulk", delay: 6, why: "The customer may want a standing deal.") }
        case "g_rival", "r_priceWar":
            queue(&s, i, "distressed", delay: 8 + jitter(s, co.id, e.id, 4), why: "A weaker competitor may be forced to sell.")
        case "g_roadwork":
            queue(&s, i, "premises", delay: 8, why: "The landlord may make an offer when the works end.")
        default: break
        }
        if fx["quit"].bool {
            EventEngine.addModifier(&s, i, key: "cap", multiplier: 0.9, weeks: 5)
            s.note("\(co.name) loses a worker: capacity -10% for 5 weeks.", tone: "bad", companyID: co.id)
            queue(&s, i, "hire", delay: 2, why: "The vacancy needs covering.")
            queue(&s, i, "headhunt", delay: 4, why: "The rival who took your worker may come back for another.")
        }
    }

    /// Effects of the follow-ups that no existing effect covers: dearer insurance and cyber protection.
    static func extras(_ s: inout GameState, _ i: Int, fx: JSONValue, data: GameData) {
        let co = s.companies[i]
        if fx["premUp"].double != 0 {
            var f = s.companies[i].value("flags")
            f["premUp"] = fx["premUp"]; f["premUntil"] = .number(Double(s.week) + fx["premWeeks"].double)
            s.companies[i].set("flags", f)
            s.note("\(co.name): insurance premiums +\(Int((fx["premUp"].double * 100).rounded()))% for \(fx["premWeeks"].int) weeks.", tone: "bad", companyID: co.id)
        }
        if fx["cyberLvl"].double != 0 || fx["cyberTrain"].bool || fx["cyberTarget"].bool {
            var c = s.companies[i].value("cy56")
            var said: [String] = []
            if fx["cyberLvl"].double != 0 && c["lvl"].int < fx["cyberLvl"].int { c["lvl"] = fx["cyberLvl"]; said.append("security raised to managed") }
            if fx["cyberTrain"].bool { c["tr"] = .number(Double(s.week)); said.append("staff trained") }
            if fx["cyberTarget"].bool { c["target"] = .number(Double(s.week + 26)); said.append("left open: attackers see an easy target for 26 weeks") }
            s.companies[i].set("cy56", c)
            s.note("\(co.name): \(said.joined(separator: ", ")).", tone: fx["cyberTarget"].bool ? "bad" : "good", companyID: co.id)
        }
    }

    // MARK: Weekly

    /// Fire what has fallen due. Called every week before decisions expire.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for item in AftermathQueue.takeDue(&s) {
            guard let i = s.companyIndex(item.companyID), s.companies[i].status == .open else { continue }
            let co = s.companies[i]
            let country = fc.country(of: co, s)
            let ctx = EventEngine.context(for: co, data: data, country: country)
            if item.kind == "copycat" {
                s.note("\(co.name): the lost case encourages another customer to claim.", tone: "bad", companyID: co.id)
                Lawsuits.begin(&s, companyIndex: i, weeklyRevenue: ctx.wk, data: data)
                continue
            }
            if item.kind == "headhunt" && co.staff.isEmpty { continue }
            guard let e = event(item.kind) else { continue }
            EventEngine.fire(&s, companyIndex: i, e, ctx: ctx, data: data, context: fc)
        }
    }
}
