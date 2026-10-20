import Foundation
import GameCore
import Countries
import Finance

/// The local business paper (front page every week), interviews, and the public image they build (trust, boldness, care).
/// Originals: `paperName` (world_around_you.js), `PR`, `pressAdd`, `issue`, `QS`, `maybeInterview`, `ACTS.pr28int`, `imgWord`
/// (features/people/staff_stories_and_nemesis.js), the screen `paper40`.
public enum Press {
    public static let interviewAction = "pr28int"

    static let papers: [String: String] = ["NO": "Kvartalsposten", "SE": "Kvartalet", "DK": "Kvartalet", "PL": "Bilans Tygodnia", "LT": "Savaites Balansas", "DE": "Wirtschaftsbote",
        "UK": "The Counting House", "FR": "Le Bilan du Lundi", "ES": "El Balance", "NL": "De Weekbalans", "US": "The Weekly Ticker", "CA": "The Northern Ledger",
        "AU": "The Weekly Bottom Line", "JP": "The Tokyo Ledger", "KR": "The Seoul Ledger", "BR": "O Balanco Semanal", "CH": "Die Wochenbilanz", "MX": "El Balance Semanal",
        "AE": "The Gulf Ledger", "IT": "Il Bilancio", "FI": "Viikon Tase", "IE": "The Monday Ledger", "SG": "The Straits Ledger"]

    /// The paper is named after your city. Original: `R31.paperName` (falls back to the business weekly of the country).
    public static func paperName(_ s: GameState, data: GameData) -> String {
        let cc = s.homeCountryCode
        guard let c = data.countries[cc], let city = c.city(s.player.cityID) ?? c.cities.first else { return papers[cc] ?? "The Weekly Ledger" }
        let n = city.name
        switch cc {
        case "NO": return n + "posten"
        case "SE": return n + (n.hasSuffix("s") ? "" : "s") + "-Kuriren"
        case "DK": return n + "s Dagblad"
        case "PL": return "Kurier " + n
        case "DE": return n + "er Tageblatt"
        case "FR": return "Le Courrier de " + n
        case "ES": return "El Diario de " + n
        case "NL": return "Dagblad van " + n
        case "BR": return "Diario de " + n
        case "KR": return n + " Ilbo"
        case "JP": return "The " + n + " Shimbun"
        case "UK": return "The " + n + " Courier"
        case "AU": return "The " + n + " Chronicle"
        default: return "The " + n + " Ledger"
        }
    }

    // MARK: State

    static func state(_ s: GameState) -> JSONValue {
        s.rest["pr28"] ?? .object(["img": .object(["trust": 50, "bold": 50, "care": 50]), "iss": .array([]), "cand": .array([]), "top": .null, "lastInt": -99, "quote": .null])
    }

    public struct Image: Equatable, Sendable { public var trust: Double, bold: Double, care: Double }
    public static func image(_ s: GameState) -> Image {
        let i = state(s)["img"]; return Image(trust: i["trust"].double, bold: i["bold"].double, care: i["care"].double)
    }
    /// "Seen as trustworthy", "Seen as bold", "Seen as caring" or "Not well known yet". Original: `imgWord`.
    public static func imageWord(_ s: GameState) -> String {
        let i = image(s)
        let best = [("trust", i.trust), ("bold", i.bold), ("care", i.care)].max { $0.1 < $1.1 }!
        return best.1 < 55 ? "Not well known yet" : ["trust": "Seen as trustworthy", "bold": "Seen as bold", "care": "Seen as caring"][best.0]!
    }
    /// Move one of the three image numbers. Original: `img(k, d)`.
    public static func moveImage(_ s: inout GameState, _ key: String, by d: Double) {
        var p = state(s); var img = p["img"]
        img[key] = .number(clamp(img[key].double + d, 0, 100)); p["img"] = img; s.rest["pr28"] = p
    }

    /// A story for the next front page. Original: `pressAdd(priority, head, deck)`.
    public static func add(_ s: inout GameState, priority: Double, head: String, deck: String = "") {
        var p = state(s)
        var c = p["cand"].array
        c.append(.object(["pri": .number(priority), "head": .string(head), "deck": .string(deck), "w": .number(Double(s.week))]))
        if c.count > 30 { c.removeFirst(c.count - 30) }
        p["cand"] = .array(c); s.rest["pr28"] = p
    }

    public struct FrontPage: Equatable, Sendable { public var week: Int; public var headline: String; public var deck: String; public var side: [String] }
    public static func frontPages(_ s: GameState) -> [FrontPage] {
        state(s)["iss"].array.map { FrontPage(week: $0["w"].int, headline: $0["head"].string, deck: $0["deck"].string, side: $0["side"].array.map { $0.string }) }
    }

    // MARK: Weekly

    /// Pick the biggest story of the week for the front page. Original: `issue()`.
    static func issue(_ s: inout GameState) {
        let sur = s.player.name.split(separator: " ").last.map(String.init) ?? s.player.name
        var p = state(s)
        if !p["quote"].isNull {
            let q = p["quote"].string
            s.rest["pr28"] = p; add(&s, priority: 4.5, head: "\(sur): \"\(q)\"", deck: "An interview with \(s.player.name)."); p = state(s); p["quote"] = .null
        }
        for n in (s.rest["news"]?.array ?? []).prefix(6) where n["w"].int == s.week { s.rest["pr28"] = p; add(&s, priority: 1, head: n["t"].string); p = state(s) }
        let cands = p["cand"].array.filter { s.week - $0["w"].int <= 1 }.sorted { $0["pri"].double > $1["pri"].double }
        p["cand"] = .array([])
        if let top = cands.first {
            var iss = p["iss"].array
            iss.insert(.object(["w": .number(Double(s.week)), "head": top["head"], "deck": top["deck"], "side": .array(cands.dropFirst().prefix(4).map { $0["head"] })]), at: 0)
            if iss.count > 12 { iss.removeLast(iss.count - 12) }
            p["iss"] = .array(iss)
        }
        s.rest["pr28"] = p
    }

    static let questions: [(cond: (GameState) -> Bool, q: String, answers: [(label: String, key: String, quote: String)])] = [
        ({ s in s.companies.filter { $0.status == .open }.count >= 1 && s.rest["nem28"] != nil }, "A rival owner says you will not last. What do you say to that?",
         [("Let the results speak", "trust", "We keep our heads down and do good work. Results speak."), ("We will be number one", "bold", "By this time next year, we will be the ones they chase."), ("Our people are why we last", "care", "Our people are the reason we will be here in twenty years.")]),
        ({ s in s.companies.contains { $0.status == .open && $0.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit } < 0 } }, "One of your companies is losing money. What went wrong?",
         [("Admit the mistakes", "trust", "We got some things wrong, and we are fixing them."), ("It is an investment", "bold", "Every big business loses money on the way up."), ("We will not cut jobs", "care", "We will turn it around without laying people off.")]),
        ({ s in s.companies.filter { $0.status == .open }.count >= 2 }, "You have grown fast. What is next?",
         [("Steady growth, no drama", "trust", "One step at a time, and we pay our bills."), ("Bigger, faster, abroad", "bold", "We are just getting started. Watch this space."), ("Better jobs in this town", "care", "More good jobs here, and giving something back.")]),
        ({ _ in true }, "What is the secret of your business?",
         [("Honest prices", "trust", "Fair prices and we keep our promises."), ("Outwork everyone", "bold", "We simply work harder than the competition."), ("Happy staff, happy customers", "care", "Treat your people well and they treat the customers well.")])]

    /// A reporter asks for an interview now and then. Original: `maybeInterview`.
    static func maybeInterview(_ s: inout GameState, data: GameData) {
        let p = state(s)
        guard s.week - p["lastInt"].int >= 13, s.companies.contains(where: { $0.status == .open }), s.week >= 16, s.random.chance(0.3) else { return }
        var pp = p; pp["lastInt"] = .number(Double(s.week)); s.rest["pr28"] = pp
        var qi = questions.count - 1
        for (i, q) in questions.enumerated() where q.cond(s) && s.random.chance(0.7) { qi = i; break }
        let q = questions[qi]
        var opts: [JSONValue] = q.answers.map { .option($0.label, "\"\($0.quote)\"") }
        opts.append(.option("No comment", "Safer, but it looks like you are hiding something."))
        let paper = paperName(s, data: data)
        s.addMessage(kind: "ask", from: "A reporter at \(paper)", title: "\(paper) wants an interview", body: "\"\(q.q)\"", tone: "n", status: "open", options: opts,
                     action: interviewAction, data: .object(["q": .number(Double(qi))]), expiresWeek: s.week + 2)
    }

    /// Answer an interview. Original: `ACTS.pr28int`.
    public static func answerInterview(_ s: inout GameState, questionIndex: Int, option idx: Int) {
        guard questions.indices.contains(questionIndex) else { return }
        let q = questions[questionIndex]
        guard q.answers.indices.contains(idx) else { moveImage(&s, "trust", by: -2); return }
        let a = q.answers[idx]
        moveImage(&s, a.key, by: 7)
        for k in ["trust", "bold", "care"] where k != a.key { moveImage(&s, k, by: -1) }
        var p = state(s); p["quote"] = .string(a.quote); s.rest["pr28"] = p
        let live = s.companies.indices.filter { s.companies[$0].status == .open }
        if a.key == "bold" { for i in live { s.companies[i].awareness = min(100, s.companies[i].awareness + 2) } }
        if a.key == "care" {
            for i in live {
                if s.companies[i].managerID != nil || !s.companies[i].staff.isEmpty { s.companies[i].set("mood", min(100, (s.companies[i].value("mood").isNull ? 60 : s.companies[i].num("mood")) + 2)) }
            }
        }
        if a.key == "trust" { s.credit = min(100, s.credit + 1) }
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        maybeInterview(&s, data: data)
        issue(&s)
    }
}
