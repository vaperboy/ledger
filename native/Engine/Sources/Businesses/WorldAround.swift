import Foundation
import GameCore
import Countries
import Finance

/// The world around you: how people see you (public image), the people you know (contacts by role, favours owed and promises made),
/// and the data behind the maps screen (ownership tree, presence by city, circles of influence). Rivals remembering you is in `Rivals`.
/// Original: features/world/world_around_you.js (sections 6A public image, 7 people you know, 8 maps, 9A a local paper).
/// Not ported: interviews and giving back (they feed the press group of the image: it stays at its neutral start until they exist),
/// supplier owners as contacts, a missing permit sorted by a politician (the council only speaks well of you), the week in numbers.
public enum WorldAround {
    // MARK: Public image

    public struct ImageGroup: Equatable, Identifiable {
        public var id: String
        public var name: String
        /// 0...100, nil when nobody there knows you yet.
        public var value: Double?
        public var word: String
    }

    public struct Image: Equatable {
        public var label: String
        public var text: String
        public var opens: String
        public var risks: String
        public var groups: [ImageGroup]
        public var press: Double { groups.first { $0.id == "press" }?.value ?? 50 }
        public var city: Double { groups.first { $0.id == "city" }?.value ?? 50 }
        public var bank: Double { groups.first { $0.id == "bank" }?.value ?? 50 }
    }

    static let groupWords: [String: [String]] = [
        "press": ["Hostile", "Sceptical", "Neutral", "Positive", "Admiring"],
        "bank": ["Avoid you", "Cautious", "Neutral", "Trust you", "Compete for you"],
        "staff": ["Want out", "Unhappy", "Okay", "Loyal", "Proud to work for you"],
        "rivals": ["Resent you", "Wary", "Neutral", "Respect you", "Friendly"],
        "city": ["Want you gone", "Sceptical", "Hardly know you", "Value you", "See you as a pillar"],
        "public": ["Avoid your places", "Mixed", "Fine", "Like you", "Love your places"],
    ]
    static let groupNames: [(String, String)] = [("press", "The press"), ("bank", "Bankers"), ("staff", "Your staff"), ("rivals", "Rivals"), ("city", "The city council"), ("public", "Customers")]

    static func word(_ x: Double, _ words: [String]) -> String { words[x >= 75 ? 4 : x >= 58 ? 3 : x >= 42 ? 2 : x >= 25 ? 1 : 0] }
    static func liveCompanies(_ s: GameState) -> [Company] { s.companies.filter { $0.status.isLive } }

    /// How the press, bankers, staff, rivals, the council and customers see you, and what that opens and risks. Original: `image`.
    public static func image(_ s: GameState, data: GameData) -> Image {
        let pr = s.rest["pr28"]?["img"] ?? .null
        let trust = pr["trust"].isNull ? 50 : pr["trust"].double, bold = pr["bold"].isNull ? 50 : pr["bold"].double, care = pr["care"].isNull ? 50 : pr["care"].double
        let live = liveCompanies(s), cos = live.filter { $0.status == .open }
        func avg(_ a: [Double], _ d: Double) -> Double { a.isEmpty ? d : a.reduce(0, +) / Double(a.count) }
        let give = Double(s.rest["pr28"]?["give"].array.count ?? 0)
        let fines = min(5.0, Double(live.filter { ($0.books.year["fine"] ?? 0) > 0 }.count))
        let late = 0.0
        let known = knownRivals(s)
        let pw = Double(cos.filter { !$0.value("flags")["pw"].isNull }.count)
        let fc = FinanceContext(countries: data.countries, trades: data.catalog)
        let cur = fc.homeCurrency(s)
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        let g: [String: Double?] = [
            "press": (trust + care + bold) / 3 + min(10, give * 3) - fines * 4,
            "bank": s.credit - late * 6,
            "staff": avg(cos.map { $0.value("mood").isNull ? 60 : $0.num("mood") }, 55) - late * 12,
            "rivals": known.isEmpty ? nil : avg(known.map { $0.rival.relationship }, 45),
            "city": 40 + give * 9 - fines * 6 + min(12, Double(cos.count) * 2),
            "public": avg(cos.map { $0.reputation }, 50) + give * 2,
        ]
        let agg = pw * 2
        let lowRated = Double(cos.filter { Reviews.count($0) >= 20 && Reviews.rating($0) < 3.2 }.count)
        let con = fines * 2 + late * 3 + lowRated * 2 + (trust < 40 ? 2 : 0)
        let gen = give * 2.5 + (care > 60 ? 2 : 0)
        let suc: Double = nw > cur.scaledPrice(10e6) ? 3 : nw > cur.scaledPrice(1e6) ? 2 : cos.isEmpty ? 0 : 1
        let lab: [String]
        if cos.isEmpty && nw < cur.scaledPrice(500_000) { lab = ["Unknown newcomer", "Few people have heard of you yet.", "Every door is open, but nobody is holding one for you.", "Nothing yet."] }
        else if con >= 5 && con >= agg && con >= gen { lab = ["Controversial tycoon", "People talk about you, and not kindly.", "Bold deals still happen: some partners like a fighter.", "Journalists dig, staff hesitate to join, councils say no first."] }
        else if agg >= 5 && agg >= gen { lab = ["Aggressive dealmaker", "Feared and watched. Rivals expect a fight.", "Sellers call you first; weak rivals fold faster.", "Rivals gang up, poach your people and hit back."] }
        else if gen >= 5 { lab = ["Respected philanthropist", "Known for what you give back.", "Councils, the press and good people listen to you.", "People expect you to give again; stopping is noticed."] }
        else if suc >= 2 { lab = ["Self-made entrepreneur", "Admired for building it yourself.", "Banks, investors and talent come to you.", "A big failure would be news."] }
        else { lab = ["Up-and-coming owner", "Small but noticed.", "People are curious about what you do next.", "One bad story can define you."] }
        let groups = groupNames.map { k in
            let v: Double? = g[k.0] ?? nil
            return ImageGroup(id: k.0, name: k.1, value: v, word: v.map { word($0, groupWords[k.0]!) } ?? "Do not know you yet")
        }
        return Image(label: lab[0], text: lab[1], opens: lab[2], risks: lab[3], groups: groups)
    }

    /// Rivals who have noticed you, across your markets (the groups and the independents).
    static func knownRivals(_ s: GameState) -> [(rival: Rivals.Rival, company: Company)] {
        var out: [(Rivals.Rival, Company)] = [], seen = Set<Int>()
        for co in s.companies where co.status == .open {
            for r in Rivals.rivals(s, for: co) where r.known && !seen.contains(r.id) { seen.insert(r.id); out.append((r, co)) }
        }
        return out
    }

    // MARK: A local paper

    /// The business paper is named after your city. Original: `R31.paperName`.
    public static func paperName(_ s: GameState, data: GameData) -> String? {
        let cc = s.homeCountryCode
        let cityID = s.rest["player"]?["city"].string ?? ""
        guard let n = (data.countries.city(cityID, preferring: cc) ?? data.countries[cc]?.cities.first.map { (country: data.countries[cc]!, city: $0) })?.city.name, !n.isEmpty else { return nil }
        switch cc {
        case "NO": return n + "posten"
        case "SE": return n + (n.hasSuffix("s") ? "" : "s") + "-Kuriren"
        case "DK": return n + "s Dagblad"
        case "DE": return n + "er Tageblatt"
        case "FR": return "Le Courrier de " + n
        case "ES": return "El Diario de " + n
        case "NL": return "Dagblad van " + n
        case "BR": return "Diário de " + n
        case "KR": return n + " Ilbo"
        case "JP": return "The " + n + " Shimbun"
        case "UK": return "The " + n + " Courier"
        case "AU": return "The " + n + " Chronicle"
        default: return "The " + n + " Ledger"
        }
    }

    // MARK: People you know

    public enum Role: String, CaseIterable { case executives = "Executives", investors = "Investors", bankers = "Bankers", lawyers = "Lawyers", journalists = "Journalists",
                                              politicians = "Politicians", suppliers = "Suppliers", rivalOwners = "Rival owners" }

    public struct Contact: Identifiable, Equatable {
        public var id: String
        public var name: String
        public var role: Role
        public var organisation: String
        /// 0...100
        public var relationship: Double
        public var companyID: Int?                      // a manager of this company
        public var rivalKey: String?, rivalID: Int?     // the owner of this rival
        public var word: String { relationshipWord(relationship) }
    }

    public static func relationshipWord(_ r: Double) -> String { r >= 78 ? "Trusted" : r >= 64 ? "Close" : r >= 50 ? "Friendly" : r >= 36 ? "Acquaintance" : r >= 22 ? "Cool" : "Strained" }

    static func net(_ s: GameState) -> JSONValue { s.rest["net31"] ?? .object(["g": .object([:]), "f": .array([]), "ask": -99, "n": 0]) }

    /// A contact who is part of the world: made up once, then the same person for the whole game. Original: `gen`.
    static func generated(_ s: inout GameState, data: GameData, key: String, role: Role, org: String) -> JSONValue {
        var N = net(s)
        var c = N["g"][key]
        if c.isNull {
            let country = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
            var h = HashedRandom("\(s.seed):net31:\(key)")
            let f = country.firstNames.isEmpty ? ["Alex"] : country.firstNames, l = country.lastNames.isEmpty ? ["Smith"] : country.lastNames
            c = .object(["id": .string("g:" + key), "name": .string(f[Int(h.next() * Double(f.count)) % f.count] + " " + l[Int(h.next() * Double(l.count)) % l.count]),
                         "role": .string(role.rawValue), "org": .string(org), "adj": 0])
        }
        c["org"] = .string(org)
        N["g"][key] = c
        s.rest["net31"] = N
        return c
    }

    /// Everyone you know, by role. Original: `roster`.
    public static func contacts(_ s: inout GameState, data: GameData) -> [Contact] {
        var out: [Contact] = []
        let live = liveCompanies(s)
        let I = image(s, data: data)
        for co in live {
            if let mid = co.managerID, let p = s.people[mid] {
                out.append(Contact(id: "mgr:\(co.id)", name: p.name, role: .executives, organisation: "Manager, \(co.name)",
                                   relationship: clamp((co.value("mood").isNull ? 60 : co.num("mood")) + 4, 0, 100), companyID: co.id))
            }
        }
        if !live.isEmpty {
            func add(_ key: String, _ role: Role, _ org: String, base: Double, weight: Double) {
                let c = generated(&s, data: data, key: key, role: role, org: org)
                out.append(Contact(id: c["id"].string, name: c["name"].string, role: role, organisation: org, relationship: clamp(base + weight + c["adj"].double, 0, 100)))
            }
            add("press", .journalists, paperName(s, data: data) ?? "the paper", base: 20, weight: I.press * 0.6)
            add("bank", .bankers, "Business adviser at your bank", base: 15, weight: I.bank * 0.6)
            add("pol", .politicians, "City council", base: 10, weight: I.city * 0.55)
            add("law", .lawyers, live.contains { !$0.value("law").isNull && $0.value("law")["own"].bool } ? "Partner at your law firm" : "Business lawyer", base: 30, weight: 0)
            if live.contains(where: { $0.ownership < 100 }) { add("inv", .investors, "Angel investor", base: 30, weight: 0) }
        }
        for (r, co) in knownRivals(s).prefix(6) {
            out.append(Contact(id: "riv:\(r.id)", name: r.owner, role: .rivalOwners, organisation: "Owner of \(r.name)", relationship: r.relationship, rivalKey: Rivals.key(co), rivalID: r.id))
        }
        return out
    }

    static func bump(_ s: inout GameState, _ c: Contact, _ d: Double) {
        if c.id.hasPrefix("g:") {
            let key = String(c.id.dropFirst(2))
            guard var N = s.rest["net31"], !N["g"][key].isNull else { return }
            N["g"][key]["adj"] = .number(clamp(N["g"][key]["adj"].double + d, -60, 60)); s.rest["net31"] = N
        } else if let k = c.rivalKey, let id = c.rivalID {
            Rivals.mutate(&s, key: k, id: id) { $0["rel"] = .number(clamp($0["rel"].double + d, 0, 100)) }
        } else if let cid = c.companyID, let i = s.companyIndex(cid) {
            s.companies[i].set("mood", clamp((s.companies[i].value("mood").isNull ? 60 : s.companies[i].num("mood")) + d, 0, 100))
        }
    }

    // MARK: Favours and promises

    public enum FavourKind: String { case owed, promise, owe }
    public enum FavourStatus: String { case open, done, used, broken, gone }

    public struct Favour: Identifiable, Equatable {
        public var id: Int
        public var kind: FavourKind
        public var contactID: String
        public var name: String
        public var role: String
        public var text: String
        public var week: Int, due: Int?
        public var status: FavourStatus
        public var cost: Double
    }

    public static func favours(_ s: GameState) -> [Favour] {
        (s.rest["net31"]?["f"].array ?? []).map {
            Favour(id: $0["id"].int, kind: FavourKind(rawValue: $0["k"].string) ?? .owed, contactID: $0["who"].string, name: $0["name"].string, role: $0["role"].string, text: $0["t"].string,
                   week: $0["w"].int, due: $0["due"].isNull ? nil : $0["due"].int, status: FavourStatus(rawValue: $0["st"].string) ?? .open, cost: $0["cost"].double)
        }
    }

    static let asks: [Role: (text: String, cost: Double, give: String)] = [
        .journalists: ("wants an exclusive comment on a story about local business", 0, "a friendly story about one of your companies"),
        .bankers: ("asks you to move part of your savings to the bank this quarter", 0, "better terms on your next loan"),
        .politicians: ("asks you to sponsor the city summer festival", 25000, "help with paperwork at the council"),
        .lawyers: ("asks you to recommend the firm to another owner", 0, "free help with your next fine"),
        .investors: ("asks you to mentor a young founder for an afternoon", 0, "an introduction that brings business"),
        .suppliers: ("asks you to place a larger order early to help their quarter", 15000, "a better price from now on"),
        .executives: ("asks for a long weekend off after a hard month", 0, "extra effort when it counts"),
        .rivalOwners: ("asks you to keep out of their part of town this year", 0, "a truce instead of a fight"),
    ]

    static func addFavour(_ s: inout GameState, _ f: [String: JSONValue]) {
        var N = net(s)
        var list = N["f"].array
        var rec = f
        rec["id"] = .number(Double(s.makeID()))
        list.insert(.object(rec), at: 0)
        if list.count > 40 { list.removeLast(list.count - 40) }
        N["f"] = .array(list)
        s.rest["net31"] = N
    }

    static func setFavour(_ s: inout GameState, id: Int, _ body: (inout JSONValue) -> Void) {
        guard var N = s.rest["net31"] else { return }
        var list = N["f"].array
        guard let k = list.firstIndex(where: { $0["id"].int == id }) else { return }
        body(&list[k]); N["f"] = .array(list); s.rest["net31"] = N
    }

    /// What a favour gets you. Original: `giveWhat`.
    static func giveWhat(_ s: inout GameState, _ c: Contact, data: GameData) -> String {
        let best = liveCompanies(s).filter { $0.status == .open }.max { Valuation.companyValue($0, state: s, trades: data.catalog) < Valuation.companyValue($1, state: s, trades: data.catalog) }
        switch c.role {
        case .journalists:
            if let b = best, let i = s.companyIndex(b.id) { s.companies[i].awareness = min(100, s.companies[i].awareness + 6); s.companies[i].reputation = min(100, s.companies[i].reputation + 1) }
            return "A friendly story about \(best?.name ?? "you") ran in \(paperName(s, data: data) ?? "the paper")."
        case .bankers:
            var N = net(s)
            let until = max(N["loanCut"]["until"].double, Double(s.week)) + 26
            N["loanCut"] = .object(["until": .number(until), "cut": 0.005]); s.rest["net31"] = N
            return "Your loans cost half a percentage point less for six months (until \(GameCalendar.dateString(week: Int(until), dayOffset: 0)))."
        case .politicians:
            for i in s.companies.indices where s.companies[i].status.isLive { s.companies[i].reputation = min(100, s.companies[i].reputation + 1) }
            return "Good words about you at the council."
        case .lawyers:
            var N = net(s); N["fineCut"] = 1; s.rest["net31"] = N
            return "Your next fine will be halved."
        case .investors:
            if let b = best, let i = s.companyIndex(b.id) { s.companies[i].awareness = min(100, s.companies[i].awareness + 4) }
            return "An introduction brought \(best?.name ?? "you") new business contacts."
        case .suppliers: return "Better terms from \(c.organisation.replacingOccurrences(of: "Owner of ", with: ""))."
        case .executives:
            bump(&s, c, 10)
            return "\(c.name) pulls the team through a hard month."
        case .rivalOwners:
            bump(&s, c, 12)
            return "\(c.name) agreed to keep things calm."
        }
    }

    /// Some favours pay back at once and say so; the rest are owed and can be called in. Original: `payBack`.
    @discardableResult
    static func payBack(_ s: inout GameState, _ c: Contact, give: String, data: GameData) -> String {
        if [.bankers, .lawyers, .suppliers, .journalists, .investors].contains(c.role) {
            let what = giveWhat(&s, c, data: data)
            addFavour(&s, ["k": "owed", "who": .string(c.id), "name": .string(c.name), "role": .string(c.role.rawValue), "t": .string(give), "w": .number(Double(s.week)), "st": "used"])
            s.note("\(c.name) returned the favour: \(what)", tone: "good")
            return what
        }
        addFavour(&s, ["k": "owed", "who": .string(c.id), "name": .string(c.name), "role": .string(c.role.rawValue), "t": .string(give), "w": .number(Double(s.week)), "st": "open"])
        s.note("\(c.name) owes you a favour: \(give). Call it in under People you know.", tone: "good")
        return "\(c.name) owes you one: \(give)."
    }

    // MARK: Weekly

    /// Broken promises, owed favours coming due, and now and then someone asks you for something. Original: `netWeek`.
    public static func weekly(_ s: inout GameState, data: GameData) {
        guard !liveCompanies(s).isEmpty else { return }
        var roster: [Contact]? = nil
        func people() -> [Contact] { if roster == nil { roster = contacts(&s, data: data) }; return roster! }
        for f in favours(s) where f.status == .open {
            if f.kind == .promise, let due = f.due, s.week > due {
                setFavour(&s, id: f.id) { $0["st"] = "broken" }
                if let c = people().first(where: { $0.id == f.contactID }) { bump(&s, c, -12) }
                s.note("You did not keep your promise to \(f.name): \(f.text).", tone: "bad")
            }
            if f.kind == .owe, let due = f.due, s.week >= due, !(s.rest["net31"]?["f"].array.first { $0["id"].int == f.id }?["asked"].bool ?? false) {
                setFavour(&s, id: f.id) { $0["asked"] = true }
                let text = f.text.prefix(1).uppercased() + f.text.dropFirst()
                s.addMessage(kind: "ask", from: f.name, title: "\(f.name) asks you to return the favour", body: "You owe me one. \(text)?", tone: "n", status: "open",
                             options: [.option("Return the favour"), .option("Not now")], action: "fav31", data: .object(["f": .number(Double(f.id)), "k": "back"]), expiresWeek: s.week + 2)
            }
        }
        let N = net(s)
        var h = HashedRandom("\(s.seed):net31w:\(s.week)")
        guard s.week - N["ask"].int >= 8, h.next() < 0.18 else { return }
        let open = favours(s).filter { $0.status == .open }
        let la = N["la"]
        let L = people().filter { c in
            c.relationship >= 22 && asks[c.role] != nil && !(la[c.id].double != 0 && Double(s.week) - la[c.id].double < 26) && !open.contains { $0.contactID == c.id }
        }
        guard !L.isEmpty else { return }
        let c = L[Int(h.next() * Double(L.count)) % L.count], a = asks[c.role]!
        let fc = FinanceContext(countries: data.countries, trades: data.catalog)
        let cur = fc.homeCurrency(s)
        let cost = a.cost > 0 ? cur.scaledPrice(a.cost) : 0
        var n2 = net(s); n2["ask"] = .number(Double(s.week)); n2["la"][c.id] = .number(Double(s.week)); s.rest["net31"] = n2
        s.addMessage(kind: "ask", from: c.name, title: "\(c.name) \(a.text)",
                     body: "\(c.organisation). " + (cost > 0 ? "It would cost about \(cur.display(cost)). " : "") + "Help now and they owe you one.", tone: "n", status: "open",
                     options: [.option("Help now" + (cost > 0 ? " · \(cur.display(cost))" : "")), .option("Promise to help later"), .option("Say no")],
                     action: "fav31", data: .object(["who": .string(c.id), "name": .string(c.name), "role": .string(c.role.rawValue), "t": .string(a.text.replacingOccurrences(of: "asks you to ", with: "")), "give": .string(a.give), "cost": .number(cost)]),
                     expiresWeek: s.week + 2)
    }

    /// The owner answers a request or a call to return a favour. Original: `ACTS.fav31`.
    public static func answerFavour(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        let d = m.value("data")
        if d["k"].string == "back" {
            let id = d["f"].int
            guard let f = favours(s).first(where: { $0.id == id }) else { return }
            let c = contacts(&s, data: data).first { $0.id == f.contactID }
            if idx == 0 {
                setFavour(&s, id: id) { $0["st"] = "done" }
                if let c = c { bump(&s, c, 5) }
                s.note("You returned the favour to \(f.name).", tone: "good")
            } else {
                setFavour(&s, id: id) { $0["st"] = "broken" }
                if let c = c { bump(&s, c, -15) }
                s.note("\(f.name) will remember that you did not return the favour.", tone: "bad")
            }
            return
        }
        guard let c = contacts(&s, data: data).first(where: { $0.id == d["who"].string }), let role = Role(rawValue: d["role"].string) else { return }
        _ = role
        if idx == 0 {
            if d["cost"].double > 0 { Payments.playerPays(&s, d["cost"].double, label: "Favour for \(d["name"].string)") }
            bump(&s, c, 6)
            payBack(&s, c, give: d["give"].string, data: data)
        } else if idx == 1 {
            bump(&s, c, 2)
            addFavour(&s, ["k": "promise", "who": .string(c.id), "name": d["name"], "role": d["role"], "t": d["t"], "give": d["give"], "cost": d["cost"], "w": .number(Double(s.week)),
                           "due": .number(Double(s.week + 6)), "st": "open"])
        } else {
            bump(&s, c, -3)
            if let k = c.rivalKey, let id = c.rivalID { let wk = s.week; Rivals.mutate(&s, key: k, id: id) { Rivals.remember(&$0, week: wk, text: "You turned down their request.", change: -2) } }
        }
    }

    public enum ActionResult: Equatable { case ok(String), refused(String) }

    /// Keep a promise: pay what it costs and they owe you one. Original: `ACT.fav31keep`.
    public static func keepPromise(_ s: inout GameState, favourID: Int, data: GameData) -> ActionResult {
        guard let f = favours(s).first(where: { $0.id == favourID }), f.status == .open, f.kind == .promise else { return .refused("Nothing to keep.") }
        if f.cost > 0 && s.cash < f.cost { return .refused("Not enough cash.") }
        if f.cost > 0 { Payments.playerPays(&s, f.cost, label: "Kept a promise to \(f.name)") }
        setFavour(&s, id: favourID) { $0["st"] = "done" }
        let give = s.rest["net31"]?["f"].array.first { $0["id"].int == favourID }?["give"].string ?? "help when you need it"
        var what = ""
        if let c = contacts(&s, data: data).first(where: { $0.id == f.contactID }) { bump(&s, c, 6); what = payBack(&s, c, give: give.isEmpty ? "help when you need it" : give, data: data) }
        return .ok("Promise kept. " + (what.isEmpty ? "\(f.name) owes you one." : what))
    }

    /// Call in a favour someone owes you; it is not guaranteed. Original: `ACT.fav31call`.
    public static func callIn(_ s: inout GameState, favourID: Int, data: GameData) -> ActionResult {
        guard let f = favours(s).first(where: { $0.id == favourID }), f.status == .open, f.kind == .owed else { return .refused("Nothing to call in.") }
        let tried = s.rest["net31"]?["f"].array.first { $0["id"].int == favourID }?["tried"] ?? .null
        if !tried.isNull, s.week - tried.int < 4 { return .refused("You asked recently. Give it a few weeks.") }
        guard let c = contacts(&s, data: data).first(where: { $0.id == f.contactID }) else { setFavour(&s, id: favourID) { $0["st"] = "gone" }; return .refused("They are no longer around.") }
        let I = image(s, data: data)
        let img = c.role == .journalists ? (I.press - 50) / 200 : c.role == .politicians ? (I.city - 50) / 200 : c.role == .bankers ? (I.bank - 50) / 200 : 0
        let odds = clamp(0.35 + c.relationship / 200 + img, 0.2, 0.9)
        if s.random.chance(odds) {
            setFavour(&s, id: favourID) { $0["st"] = "used" }
            return .ok(giveWhat(&s, c, data: data))
        }
        let wk = s.week
        setFavour(&s, id: favourID) { $0["tried"] = .number(Double(wk)) }
        bump(&s, c, -2)
        return .refused("\(c.name) could not help this time.")
    }

    /// Ask a close contact for a favour, which you then owe back. Original: `ACT.fav31ask`.
    public static func askFavour(_ s: inout GameState, contactID: String, data: GameData) -> ActionResult {
        guard let c = contacts(&s, data: data).first(where: { $0.id == contactID }) else { return .refused("They are not around.") }
        if c.relationship < 64 { return .refused("You need to be close to ask a favour without one owed.") }
        if favours(s).contains(where: { $0.contactID == c.id && $0.kind == .owe && $0.status == .open }) { return .refused("You already owe \(c.name) one.") }
        if s.random.chance(clamp(0.25 + c.relationship / 250, 0.2, 0.7)) {
            let what = giveWhat(&s, c, data: data)
            let t = (asks[c.role]?.text ?? "asks you to help them in return").replacingOccurrences(of: "asks you to ", with: "")
            addFavour(&s, ["k": "owe", "who": .string(c.id), "name": .string(c.name), "role": .string(c.role.rawValue), "t": .string(t), "w": .number(Double(s.week)),
                           "due": .number(Double(s.week + 8 + s.random.int(0, 12))), "st": "open"])
            return .ok(what + " You owe \(c.name.split(separator: " ").first.map(String.init) ?? c.name) one now.")
        }
        bump(&s, c, -3)
        return .refused("\(c.name) said no.")
    }

    // MARK: Maps (read models)

    public struct OwnershipNode: Identifiable, Equatable {
        public var id: Int
        public var name: String
        public var trade: String
        public var value: Double
        public var ownership: Double
        public var depth: Int
    }

    /// You, then your holdings with the companies under them, then the rest. Original: `V.map31`, "Ownership".
    public static func ownership(_ s: GameState, data: GameData) -> [OwnershipNode] {
        let cos = liveCompanies(s)
        func node(_ c: Company, _ d: Int) -> OwnershipNode {
            OwnershipNode(id: c.id, name: c.name, trade: c.type == "hold" ? "Holding" : data.catalog[c.type]?.name ?? c.type,
                          value: Valuation.companyValue(c, state: s, trades: data.catalog), ownership: c.ownership, depth: d)
        }
        var out: [OwnershipNode] = []
        for h in cos where h.type == "hold" {
            out.append(node(h, 1))
            for c in cos where c.holdingID == h.id { out.append(node(c, 2)) }
        }
        for c in cos where c.type != "hold" && !(c.holdingID != 0 && cos.contains { $0.id == c.holdingID }) { out.append(node(c, 1)) }
        return out
    }

    public struct CityTile: Identifiable, Equatable {
        public var id: String
        public var name: String
        public var companies: Int
        public var trades: [String]
        /// 0 none, 1 one company, 2 two or three, 3 four or more
        public var level: Int
    }
    public struct CountryPresence: Identifiable, Equatable {
        public var id: String
        public var name: String
        public var flag: String
        public var cities: [CityTile]
    }

    /// Where your companies are, city by city, the biggest cities first. Original: `V.map31`, "Presence".
    public static func presence(_ s: GameState, data: GameData) -> [CountryPresence] {
        let cos = liveCompanies(s)
        var codes: [String] = []
        for c in cos where !codes.contains(c.countryCode) { codes.append(c.countryCode) }
        return codes.compactMap { cc in
            guard let C = data.countries[cc] else { return nil }
            let cities = C.cities.sorted { $0.population > $1.population }.prefix(12).map { ct -> CityTile in
                let here = cos.filter { $0.countryCode == cc && $0.cityID == ct.id }
                var types: [String] = []
                for c in here { let n = c.type == "hold" ? "Holding" : data.catalog[c.type]?.name ?? c.type; if !types.contains(n) { types.append(n) } }
                return CityTile(id: ct.id, name: ct.name, companies: here.count, trades: Array(types.prefix(2)), level: here.count >= 4 ? 3 : here.count >= 2 ? 2 : here.isEmpty ? 0 : 1)
            }
            return CountryPresence(id: cc, name: C.name, flag: C.flag, cities: Array(cities))
        }
    }

    public struct Influence: Equatable {
        public var inner: [String]       // your companies
        public var allies: [String]      // contacts you are close to (50 or more)
        public var others: [String]      // the rest: rivals and the wary
        public var seenAs: String
        public init(inner: [String], allies: [String], others: [String], seenAs: String) { self.inner = inner; self.allies = allies; self.others = others; self.seenAs = seenAs }
    }

    /// Circles of influence: your companies inside, allies in the middle ring, rivals and the wary outside. Original: `V.map31`, "Influence".
    public static func influence(_ s: inout GameState, data: GameData) -> Influence {
        let R = contacts(&s, data: data)
        return Influence(inner: liveCompanies(s).map { $0.name }, allies: R.filter { $0.relationship >= 50 }.map { $0.name },
                         others: R.filter { $0.relationship < 50 }.map { $0.name }, seenAs: image(s, data: data).label)
    }

    /// The line under the people-you-know row. Original: `R31.netSub`.
    public static func contactsSummary(_ s: inout GameState, data: GameData) -> String {
        let f = favours(s).filter { $0.status == .open }
        let owed = f.filter { $0.kind == .owed }.count, prom = f.filter { $0.kind == .promise }.count
        return "\(contacts(&s, data: data).count) contacts" + (owed > 0 ? " · \(owed) owe you" : "") + (prom > 0 ? " · \(prom) promise\(prom > 1 ? "s" : "") open" : "")
    }
}
