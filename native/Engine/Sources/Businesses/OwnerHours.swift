import Foundation
import GameCore
import Countries

public enum OwnerHours {
    public static let weeklyCap = 80.0
    public static let burnoutFrom = 65.0
    public static let floor = 5.0

    public static func works(_ co: Company) -> Bool { co.managerID == nil && co.type != "hold" && !co.flag("ownOut") }

    public static func needed(_ co: Company, _ bd: Trade, _ w: World, room: Double = weeklyCap) -> Double {
        var present = co
        present.ownerHours = max(co.ownerHours, 40)
        let demand = DemandModel.compute(present, bd, w).customers
        var c = co
        var h = floor
        while h < min(room, weeklyCap) {
            c.ownerHours = h
            if CapacityModel.compute(c, bd, w).capacity >= demand { return h }
            h += 5
        }
        return max(0, min(room, weeklyCap))
    }

    public static func adjustWeek(_ s: inout GameState, data: GameData) {
        if s.rest["ownHrsFixed"]?.bool == true { return }
        var used = 0.0
        let startups = (s.rest["founded"]?.array ?? []).filter { $0["st"].string == "live" }
        used += startups.reduce(0) { $0 + $1["sw"]["selfH"].double + $1["sw16"]["selfH"].double }
        for i in s.companies.indices {
            let co = s.companies[i]
            guard co.status.isLive, co.type != "hold" else { continue }
            if co.managerID != nil || co.flag("ownOut") { continue }
            guard co.status == .open, let bd = data.catalog[co.type] else { used += co.ownerHours; continue }
            let hours = needed(co, bd, World(state: s, data: data), room: max(0, Gates.ownerHoursCap(s) - used))
            s.companies[i].ownerHours = hours
            used += hours
        }
    }
}
