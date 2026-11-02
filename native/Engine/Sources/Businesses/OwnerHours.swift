import Foundation
import GameCore
import Countries

/// The player's own hours in the companies they run themselves. There is no "Your time" setting any more: every week the hours follow what the
/// business needs. The player only chooses whether they work in a company at all (`ownOut` is set only when they step out; old saves have no key).
/// Running alone, the hours are as many as demand needs, in steps of five, never more than 80 across all companies. Burn-out starts from 65 hours
/// (`Luxury.ownerWeek`), so the 66 to 80 hour weeks of a busy one-person company wear the player down.
public enum OwnerHours {
    /// The most hours a week across all companies.
    public static let weeklyCap = 80.0
    /// Burn-out (tiredness building up) starts above this many hours a week.
    public static let burnoutFrom = 65.0
    /// The least a working owner puts in (owner decision, 2 Nov): a small company needs fewer than 40 hours, so the hours follow demand in 5 h steps up to 80.
    public static let floor = 5.0

    /// True when the player works in this company: a company they run themselves (no manager, not a holding) and have not stepped out of.
    public static func works(_ co: Company) -> Bool { co.managerID == nil && co.type != "hold" && !co.flag("ownOut") }

    /// Hours the business needs from its owner so that what it can serve meets demand (5 h steps, from `floor`), at most `room`.
    public static func needed(_ co: Company, _ bd: Trade, _ w: World, room: Double = weeklyCap) -> Double {
        let demand = DemandModel.compute(co, bd, w).customers
        var c = co
        var h = floor
        while h < min(room, weeklyCap) {
            c.ownerHours = h
            if CapacityModel.compute(c, bd, w).capacity >= demand { return h }
            h += 5
        }
        return max(0, min(room, weeklyCap))
    }

    /// Weekly: set the hours of every company the player works in. Companies with a manager or those the player stepped out of are left alone.
    public static func adjustWeek(_ s: inout GameState, data: GameData) {
        if s.rest["ownHrsFixed"]?.bool == true { return }   // a game (or a test) that sets the hours itself
        var used = 0.0
        let startups = (s.rest["founded"]?.array ?? []).filter { $0["st"].string == "live" }
        used += startups.reduce(0) { $0 + $1["sw"]["selfH"].double + $1["sw16"]["selfH"].double }
        for i in s.companies.indices {
            let co = s.companies[i]
            guard co.status.isLive, co.type != "hold" else { continue }
            if co.managerID != nil || co.flag("ownOut") { continue }
            guard co.status == .open, let bd = data.catalog[co.type] else { used += co.ownerHours; continue }
            let hours = needed(co, bd, World(state: s, data: data), room: max(0, weeklyCap - used))
            s.companies[i].ownerHours = hours
            used += hours
        }
    }
}
