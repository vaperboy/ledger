import Foundation
import GameCore
import Countries
import Employees

/// Paperwork for new people, inspection fines, commission mishaps and hidden talent.
/// Originals: `ONB_BASE`, `ONB_X`, `ONB_ROLE`, `onbMissing`, `staffExtra`, `managerOnboard` (engine/people/staff_extras.js).
public enum StaffExtras {
    public static let baseItems: [(key: String, text: String)] = [
        ("contract", "Employment contract signed"), ("tax", "Tax deduction registered"), ("areg", "Employment reported to the authorities"),
        ("ins", "Injury insurance and pension set up"), ("hms", "Workplace safety introduction given"),
    ]
    static let roleItem: [String: String] = [
        "food": "Food hygiene training documented", "police": "Police certificate", "drive": "Driving licence checked", "cert": "Trade certificate verified",
        "health": "Health authorisation verified", "guard": "Security guard approval", "avi": "Aviation licence verified", "fin": "Financial authorisation checked",
    ]
    static let roleKind: [String: String] = [
        "cook": "food", "chef": "food", "baker": "food", "barista": "food", "waiter": "food", "bartender": "food", "guard": "guard",
        "physio": "health", "dentist": "health", "dentnurse": "health", "lawyer": "cert", "elec": "cert", "plumb": "cert", "carp": "cert", "mech": "cert",
        "driver": "drive", "truckd": "drive", "driverB": "drive", "courier": "drive", "instr": "drive", "pilot": "avi", "fo": "avi", "cabin": "avi",
        "banker": "fin", "broker": "fin", "agent": "fin", "underw": "fin", "groom": "police", "tutor": "police", "trainer": "police",
    ]
    static let seriousItems: Set<String> = ["police", "cert", "avi", "fin"]

    /// Everything the paperwork for this role consists of.
    public static func items(role: String) -> [(key: String, text: String)] {
        var l = baseItems
        if let k = roleKind[role], let text = roleItem[k] { l.append((k, text)) }
        return l
    }

    /// Items not yet done for this person.
    public static func missing(_ m: StaffMember) -> [(key: String, text: String)] {
        guard !m.value("onb").isNull else { return [] }
        let done = m.value("onb")
        return items(role: m.role).filter { !done[$0.key].bool && done[$0.key].double == 0 }
    }

    public static func tick(_ m: inout StaffMember, key: String) {
        var o = m.value("onb"); o[key] = .number(1); m.set("onb", o)
    }

    public struct Outcome {
        public var fines: [(amount: Double, note: String)] = []
        public var reputationLoss = 0.0
        public var notes: [(text: String, tone: String)] = []
        public var left = false
        public var managerLearnsPaperwork = false
    }

    /// One person, one week. Original: `staffExtra`. Returns what happened; the caller books fines and notes.
    public static func week(_ m: inout StaffMember, person n: inout Person, week: Int, random r: inout DeterministicRandom,
                            companyUtilisation util: Double?, hasManager: Bool, managerLearned: Bool) -> Outcome {
        var out = Outcome()
        let miss = missing(m)
        if !miss.isEmpty, week - m.hiredWeek >= 3 {
            for it in miss where r.chance(0.009) {
                let f = jsRound(r.range(6000, 20000) * (seriousItems.contains(it.key) ? 2 : 1))
                out.fines.append((f, "Inspectors fined {co} {fine}: \"\(it.text)\" missing for \(n.name)."))
                out.reputationLoss += 1
                if hasManager && !managerLearned { out.managerLearnsPaperwork = true }
            }
        }
        if m.commissionMode == "com" {
            if r.chance(0.003) {
                let f = jsRound(r.range(10000, 40000))
                out.fines.append((f, "A customer complaint about pushy selling by \(n.name) cost {co} {fine}."))
                out.reputationLoss += 1.5
            }
            if r.chance(0.004 + ((util ?? 1) < 0.5 ? 0.01 : 0)) {
                out.notes.append(("\(n.name) left {co} after a slow month on commission.", "bad"))
                out.left = true
                return out
            }
        }
        // Hidden potential: some young people with the right character grow faster.
        let goodCharacter = ["driven", "steady", "loyal"].contains(n.str("pers"))
        if n.flag("golden") && goodCharacter && (week - m.hiredWeek) % 4 == 3 {
            m.skillGain = clamp(m.skillGain + 1.6, -10, 30)
            if week - m.hiredWeek == 19 && !n.flag("rev") {
                n.set("rev", 1)
                out.notes.append(("\(n.name) at {co} is turning into a real star.", "good"))
            }
        }
        return out
    }
}
