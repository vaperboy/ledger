import Foundation
import GameCore
import Countries
import Employees

/// A real work log for every employee. Each week the weekly staff simulation (`StaffRoutine`, `StaffWeek`, `StaffProfile.trackWeek`)
/// records what happened to this person's work: hours worked against hours contracted, assigned and completed tasks, mistakes, late arrivals, days lost
/// to sickness, initiative taken, times they needed guidance, and whether they told you what you needed to know or went quiet. The log keeps the last
/// 26 weeks as one compact row per week (`wlog` on the staff record). Performance feedback is composed from those rows only, never from a rating:
/// "Completed most assigned work, but needed regular guidance." is said because the log has many tasks done and many calls for guidance.
/// How the events arise: from the same factors that already drive the simulated business (skill, learning curve, tiredness, personality, pay and
/// treatment); the draws use a hash of the person and the week, not the game's random stream, so a week replays the same and nothing else moves.
public enum WorkLog {
    /// One week of work. Stored as an array of numbers in this order.
    public struct Week: Equatable, Sendable {
        public var week = 0
        public var hoursContracted = 0.0
        public var hoursWorked = 0.0
        public var tasksAssigned = 0
        public var tasksDone = 0
        public var mistakes = 0
        public var late = 0
        public var sickWeek = false
        public var initiative = 0
        public var guidance = 0
        public var informed = 0
        public var silent = 0
        public var complaints = 0

        var json: JSONValue {
            .array([week, Int(hoursContracted * 4), Int(hoursWorked * 4), tasksAssigned, tasksDone, mistakes, late, sickWeek ? 1 : 0, initiative, guidance, informed, silent, complaints]
                .map { .number(Double($0)) })
        }
        init(json j: JSONValue) {
            let a = j.array.map { $0.int }
            func at(_ i: Int) -> Int { i < a.count ? a[i] : 0 }
            week = at(0); hoursContracted = Double(at(1)) / 4; hoursWorked = Double(at(2)) / 4; tasksAssigned = at(3); tasksDone = at(4); mistakes = at(5); late = at(6)
            sickWeek = at(7) == 1; initiative = at(8); guidance = at(9); informed = at(10); silent = at(11); complaints = at(12)
        }
        init(week: Int) { self.week = week }
    }

    static let key = "wlog"
    public static let weeksKept = 26
    /// Feedback looks at this many recent weeks.
    public static let window = 13
    /// Fewest weeks of work the log needs before it says anything about someone.
    public static let minimumWeeks = 4

    public static func weeks(_ m: StaffMember) -> [Week] { m.value(key).array.map { Week(json: $0) } }

    static func store(_ weeks: [Week], _ m: inout StaffMember) {
        let kept = weeks.suffix(weeksKept)
        m.set(key, .array(kept.map { $0.json }))
    }

    /// The row of this week on the record (made when missing), changed by `f`.
    static func edit(_ m: inout StaffMember, week: Int, _ f: (inout Week) -> Void) {
        var all = weeks(m)
        if let i = all.firstIndex(where: { $0.week == week }) { f(&all[i]) }
        else { var w = Week(week: week); f(&w); all.append(w); all.sort { $0.week < $1.week } }
        store(all, &m)
    }

    /// A late arrival or a complaint noted by the quarterly tracker.
    static func note(_ m: inout StaffMember, week: Int, late: Int = 0, complaints: Int = 0) {
        edit(&m, week: week) { $0.late += late; $0.complaints += complaints }
    }

    // MARK: The week's events

    /// Everything that can go on in one person's week, as numbers: the simulation behind the log. `skill` is the person's real skill including what they have
    /// learned; it moves the odds of events, it is never printed.
    struct Inputs {
        var id: Int, week: Int
        var contracted: Double, worked: Double
        var skill: Double, experience: Double
        var ramp: Double, tiredFactor: Double
        var personality: String
        var flag: String
        var sick: Bool, offSeason: Bool
        var disengaged: Bool
        var limitedByPeople: Bool
    }

    static let initiativeBase: [String: Double] = ["driven": 0.30, "steady": 0.12, "loyal": 0.16, "arrogant": 0.10, "lazy": 0.03, "restless": 0.10]
    static let silenceBase: [String: Double] = ["driven": 0.03, "steady": 0.03, "loyal": 0.02, "arrogant": 0.07, "lazy": 0.07, "restless": 0.06]

    static func simulate(_ i: Inputs) -> Week {
        var w = Week(week: i.week)
        w.hoursContracted = i.contracted
        if i.offSeason { return w }
        if i.sick { w.sickWeek = true; return w }
        var r = HashedRandom("wl:\(i.id):\(i.week)")
        w.hoursWorked = i.worked
        let assigned = max(1, Int((i.contracted / 5).rounded()))
        // Overtime when the business is limited by people means more work gets handed over.
        let handed = i.limitedByPeople && i.worked > i.contracted ? assigned + Int(((i.worked - i.contracted) / 5).rounded()) : assigned
        w.tasksAssigned = handed
        let pace = i.ramp * i.tiredFactor * (0.78 + 0.45 * i.skill / 100) * (i.flag == "lazy" ? 0.82 : 1) * (i.disengaged ? 0.88 : 1)
        let pDone = clamp(0.62 + 0.36 * pace, 0.2, 0.995)
        let pMistake = clamp(0.20 - i.skill / 600 - min(i.experience, 15) * 0.004 + (1 - i.tiredFactor) * 0.5 + (1 - i.ramp) * 0.2 + (i.flag == "lazy" ? 0.05 : 0) + (i.disengaged ? 0.04 : 0), 0.01, 0.4)
        let pGuide = clamp(0.5 - i.skill / 200 - min(i.experience, 15) * 0.008 + (1 - i.ramp) * 0.45, 0.04, 0.85)
        for _ in 0..<handed {
            if r.next() < pDone {
                w.tasksDone += 1
                if r.next() < pMistake { w.mistakes += 1 }
                if r.next() < pGuide * 0.5 { w.guidance += 1 }
            }
        }
        let late = i.flag == "late" ? 0.45 : i.flag == "lazy" ? 0.06 : 0.015 + (i.disengaged ? 0.03 : 0)
        if r.next() < late { w.late += 1 }
        let init0 = (initiativeBase[i.personality] ?? 0.12) * (0.6 + i.skill / 120) * (i.ramp >= 1 ? 1 : 0.4) * i.tiredFactor * (i.disengaged ? 0.3 : 1)
        if r.next() < init0 || (i.limitedByPeople && i.worked > i.contracted * 1.05 && r.next() < 0.3) { w.initiative += 1 }
        let quiet = (silenceBase[i.personality] ?? 0.04) + (i.disengaged ? 0.25 : 0) + (i.flag == "conflict" ? 0.06 : 0)
        if r.next() < quiet { w.silent += 1 } else if r.next() < 0.3 { w.informed += 1 }
        return w
    }

    /// Record this week for a team member, from what the simulation says happened. Called once a week from `StaffRoutine`.
    static func record(_ m: inout StaffMember, person n: Person, week: Int, contracted: Double, worked: Double, skill: Double, limitedByPeople: Bool, tiredFactor: Double,
                       ramp: Double, sick: Bool) {
        var wk = simulate(Inputs(id: m.id, week: week, contracted: contracted, worked: worked, skill: skill, experience: n.num("exp"), ramp: ramp, tiredFactor: tiredFactor,
                                 personality: n.str("pers"), flag: m.str("flag"), sick: sick, offSeason: m.isOffSeason, disengaged: StaffBehaviour.isDisengaged(m),
                                 limitedByPeople: limitedByPeople))
        // keep what the tracker noted earlier in the week
        if let old = weeks(m).first(where: { $0.week == week }) { wk.late += old.late; wk.complaints += old.complaints }
        edit(&m, week: week) { $0 = wk }
    }

    // MARK: Feedback

    public struct Observation: Equatable, Sendable, Identifiable {
        /// "Work quality", "Reliability", "Speed", "Mistakes", "Initiative", "Communication", "Independence", "Completed work".
        public var aspect: String
        public var text: String
        public var id: String { aspect }
    }

    public struct Feedback: Equatable, Sendable {
        public var weeksObserved: Int
        /// One sentence per aspect that the log has something to say about; empty when there is too little to go on.
        public var observations: [Observation]
        /// The sentences joined: what to say about them in a line.
        public var summary: String
        public var enoughToJudge: Bool
    }

    static func times(_ n: Int) -> String {
        switch n { case 1: return "once"; case 2: return "twice"; case 3: return "three times"; case 4: return "four times"; default: return "several times" }
    }

    /// Feedback from the last `window` weeks of the log. Sentences say what happened, from the counts; no number is shown.
    public static func feedback(_ m: StaffMember, week: Int) -> Feedback {
        let recent = weeks(m).filter { week - $0.week < window && $0.hoursContracted > 0 }
        let worked = recent.filter { !$0.sickWeek }
        guard worked.count >= minimumWeeks else {
            return Feedback(weeksObserved: worked.count, observations: [], summary: "Too early to say: they have not worked enough weeks yet to judge.", enoughToJudge: false)
        }
        return compose(recent: recent, worked: worked, trial: false)
    }

    static func compose(recent: [Week], worked: [Week], trial: Bool) -> Feedback {
        let assigned = worked.reduce(0) { $0 + $1.tasksAssigned }, done = worked.reduce(0) { $0 + $1.tasksDone }
        let mistakes = worked.reduce(0) { $0 + $1.mistakes }, late = worked.reduce(0) { $0 + $1.late }
        let sick = recent.filter { $0.sickWeek }.count, init0 = worked.reduce(0) { $0 + $1.initiative }
        let guide = worked.reduce(0) { $0 + $1.guidance }, silent = worked.reduce(0) { $0 + $1.silent }, informed = worked.reduce(0) { $0 + $1.informed }
        let complaints = worked.reduce(0) { $0 + $1.complaints }
        let hoursW = worked.reduce(0) { $0 + $1.hoursWorked }, hoursC = worked.reduce(0) { $0 + $1.hoursContracted }
        let ratio = assigned > 0 ? Double(done) / Double(assigned) : 1
        let errRate = done > 0 ? Double(mistakes) / Double(done) : 0
        let guideRate = done > 0 ? Double(guide) / Double(done) : 0
        let n = worked.count
        var obs: [Observation] = []
        func add(_ a: String, _ t: String) { obs.append(Observation(aspect: a, text: t)) }
        let tail = trial ? " in the trial week" : ""
        // completed work and speed
        if ratio >= 0.95 { add("Completed work", "Completed all the work assigned\(tail).") }
        else if ratio >= 0.85 { add("Completed work", "Completed most assigned work\(tail)" + (guideRate >= 0.3 ? ", but needed regular guidance." : ".")) }
        else if ratio >= 0.7 { add("Completed work", "Got through only part of the assigned work\(tail); some of it was left for others.") }
        else { add("Completed work", "Left much of the assigned work undone\(tail).") }
        // speed: output over the hours they were there, and over time they finished more than the hours would suggest
        let throughput = hoursC > 0 ? Double(done) / (hoursC / 5) : 1
        if throughput >= 1.0 && ratio >= 0.9 { add("Speed", "Works quickly; tasks are done well within the hours.") }
        else if ratio < 0.8 { add("Speed", "Works slowly; the work piles up.") }
        // mistakes
        if errRate <= 0.03 { add("Mistakes", "Made hardly any mistakes\(tail).") }
        else if errRate <= 0.1 { add("Mistakes", "Made a few mistakes that had to be corrected\(tail).") }
        else { add("Mistakes", "Made frequent mistakes\(tail): work often had to be redone.") }
        // independence
        if guideRate >= 0.3 { add("Independence", "Often needed guidance before moving on.") }
        else if guideRate <= 0.08 && done >= 6 { add("Independence", "Works independently and rarely needs checking.") }
        // reliability
        if !trial {
            var rel: [String] = []
            if late >= 1 { rel.append("was late \(times(late))") }
            if sick >= 2 { rel.append("was off sick on \(sick) weeks") }
            if complaints >= 1 { rel.append("drew \(complaints == 1 ? "a complaint" : "complaints") from customers or colleagues") }
            if rel.isEmpty && hoursW >= hoursC * 0.95 { add("Reliability", "Reliable: turned up on time and put in the hours.") }
            else if !rel.isEmpty { add("Reliability", "Mostly there, but " + rel.joined(separator: " and ") + ".") }
        } else if late >= 1 { add("Reliability", "Arrived late in the trial week.") }
        // initiative
        if init0 >= max(2, n / 4) { add("Initiative", "Takes initiative: proposed improvements and covered extra work without being asked.") }
        else if init0 == 0 && n >= 8 { add("Initiative", "Does what is asked and no more.") }
        // communication
        if silent >= max(2, n / 5) { add("Communication", "Often said nothing about problems until they had grown.") }
        else if informed >= max(2, n / 6) && silent <= 1 { add("Communication", "Keeps you informed and raises problems early.") }
        return Feedback(weeksObserved: n, observations: obs, summary: obs.map { $0.text }.joined(separator: " "), enoughToJudge: true)
    }

    /// A paid trial week for a candidate: one week of simulated work as the log would record it, with observations in the same words. The candidate's real
    /// skill moves the events; only the events are reported.
    public static func trialObservations(person n: Person, role: String, week: Int, rampStart: Double = 0.75) -> [Observation] {
        let hours = StaffModel.fullWeekHours
        // five days of work give five looks at the same person, so the picture is a little firmer than one draw
        var days: [Week] = []
        for d in 0..<5 {
            var w = simulate(Inputs(id: n.id &* 31 &+ d, week: week &+ d, contracted: hours / 5 * 5, worked: hours, skill: n.skill, experience: n.num("exp"), ramp: rampStart, tiredFactor: 1,
                                    personality: n.str("pers"), flag: n.trait ?? "", sick: false, offSeason: false, disengaged: false, limitedByPeople: false))
            w.hoursContracted = hours / 5
            days.append(w)
        }
        let merged = days.reduce(into: Week(week: week)) { a, b in
            a.hoursContracted += b.hoursContracted; a.hoursWorked += b.hoursWorked; a.tasksAssigned += b.tasksAssigned; a.tasksDone += b.tasksDone; a.mistakes += b.mistakes
            a.late += b.late; a.initiative += b.initiative; a.guidance += b.guidance; a.informed += b.informed; a.silent += b.silent
        }
        var f = compose(recent: [merged], worked: [merged], trial: true).observations
        f.removeAll { $0.aspect == "Initiative" || $0.aspect == "Communication" && merged.informed + merged.silent == 0 }
        return f
    }
}
