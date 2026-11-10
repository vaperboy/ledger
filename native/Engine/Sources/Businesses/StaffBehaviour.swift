import Foundation
import GameCore
import Countries
import Employees

public enum StaffBehaviour {
    public static func isDisengaged(_ m: StaffMember) -> Bool { !m.value("dis").isNull }
    public static func isSilent(_ m: StaffMember) -> Bool { !m.value("silentW").isNull }

    static func reasons(_ m: StaffMember, gap: Double, week: Int) -> [String] {
        var out: [String] = []
        if gap > 0.1 { out.append("pay") }
        let denied = m.int("denied")
        if denied != 0 && week - denied < 26 { out.append("refused") }
        if StaffPromises.letDown(m, week: week) { out.append("promise") }
        if m.tiredness >= 60 { out.append("tired") }
        return out
    }

    static func reasonText(_ r: String) -> String {
        switch r {
        case "pay": return "I am paid less than people doing this job elsewhere."
        case "refused": return "What I asked for was turned down and nothing has changed."
        case "promise": return "What was promised to me has not happened."
        default: return "The hours have been wearing me down."
        }
    }

    public enum Style: String, Sendable { case professional, blunt, hinting, flat }

    public static func style(of n: Person) -> Style {
        switch n.str("pers") {
        case "arrogant": return .blunt
        case "restless": return .hinting
        case "lazy": return .flat
        default: return .professional
        }
    }

    public enum Update: Equatable, Sendable {
        case voiced(reason: String, style: Style)
        case disengaged
        case wentQuiet
        case recovered
    }

    static func update(_ m: inout StaffMember, person n: Person, gap: Double, week: Int) -> Update? {
        let why = reasons(m, gap: gap, week: week)
        var uw = m.int("uw")
        if why.isEmpty { uw = max(0, uw - 1) } else { uw = min(40, uw + (why.contains("refused") || why.contains("promise") ? 2 : 1)) }
        if uw > 0 { m.set("uw", uw) } else { m.raw.removeValue(forKey: "uw") }
        let r = HashedRandom.first("beh:\(m.id):\(week)")
        if isDisengaged(m), uw <= 2 {
            m.raw.removeValue(forKey: "dis"); m.raw.removeValue(forKey: "silentW")
            return .recovered
        }
        if !isDisengaged(m), uw >= 10 {
            m.set("dis", week)
            return .disengaged
        }
        if !isDisengaged(m), !isSilent(m), uw >= 4, let top = why.first, week - m.int("voiced") >= 13 || m.value("voiced").isNull {
            if r < 0.6 || uw >= 6 { m.set("voiced", week); return .voiced(reason: top, style: style(of: n)) }
        }
        if isDisengaged(m), !isSilent(m), uw >= 16, ["arrogant", "restless", "lazy"].contains(n.str("pers")), r < 0.08 {
            m.set("silentW", week)
            return .wentQuiet
        }
        return nil
    }

    static func message(for u: Update, name: String, company: String) -> (title: String, body: String, tone: String)? {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        switch u {
        case .voiced(let reason, let style):
            let line = reasonText(reason)
            switch style {
            case .professional: return ("\(first) would like a word", "I would like to talk about how things are going. \(line) I want this to work, so I am raising it now. You can talk it through from my profile.", "n")
            case .blunt: return ("\(first) is not happy", "I will be straight with you. \(line) If nothing changes, I will look elsewhere.", "bad")
            case .hinting: return ("\(first) mentions other options", "\(line) To be honest, I have been looking at what else is out there.", "bad")
            case .flat: return ("\(first) has a complaint", "\(line) It is what it is.", "n")
            }
        case .disengaged: return ("\(first) seems to have lost interest", "\(first) still turns up at \(company) but does the minimum now. Work from them is slower and more is missed.", "bad")
        case .wentQuiet: return ("\(first) has stopped raising things", "\(first) no longer says what is on their mind. Expect it to come out as a resignation, not a conversation.", "bad")
        case .recovered: return ("\(first) is engaged again", "Things at \(company) have improved for \(first) and the work shows it.", "good")
        }
    }

    static func resignationNotice(_ m: StaffMember, person n: Person, week: Int, standardNotice: Int) -> (weeks: Int, abrupt: Bool) {
        guard isDisengaged(m) || m.int("uw") >= 8 else { return (standardNotice, false) }
        let base = ["restless": 0.28, "arrogant": 0.22, "lazy": 0.12].first { n.str("pers") == $0.key }?.value ?? 0.08
        let chance = base * (isDisengaged(m) ? 1.4 : 1)
        if HashedRandom.first("abrupt:\(m.id):\(week)") < chance { return (1, true) }
        return (standardNotice, false)
    }

    static func afterRefusal(_ s: inout GameState, companyIndex ci: Int, staffID: Int) -> String? {
        guard let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }), let n = s.people[staffID] else { return nil }
        var st = s.companies[ci].staff
        st[k].set("uw", min(40, st[k].int("uw") + 3))
        let reaction: String?
        switch style(of: n) {
        case .blunt: st[k].set("uw", min(40, st[k].int("uw") + 3)); reaction = "reacted sharply, and made it clear it will not be forgotten"
        case .hinting: reaction = "said nothing much, but started to mention other jobs"
        case .flat: reaction = "shrugged it off and did less afterwards"
        case .professional: reaction = nil
        }
        s.companies[ci].staff = st
        return reaction
    }
}
