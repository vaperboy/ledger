import Foundation
import GameCore
import Countries
import Finance

public enum DeskStories {

    public static let demandRange = 0.94...1.06
    public static let weeksRange = 2...5
    public static let moodRange = -4.0...4.0, pointRange = -3.0...3.0
    public static let maxPay = 0.08, maxGain = 0.05
    public static let storiesPerChapter = 3

    public struct Option: Equatable, Sendable {
        public var label: String, hint: String
        public var days: Int
        var result: String, fx: JSONValue, chance: Double?, fxBad: JSONValue, resultBad: String
    }
    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String, chapter: String, kind: String, title: String, text: String
        public var fits: [String]
        public var options: [Option]
    }
    public struct Chapter: Identifiable, Equatable, Sendable {
        public var id: String, name: String, blurb: String, need: Int, fact: String, cover: String, rewardTitle: String
    }

    static let book: (chapters: [Chapter], items: [Item]) = {
        guard let url = Bundle.module.url(forResource: "desk", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return ([], []) }
        let chapters = j["chapters"].array.map {
            Chapter(id: $0["id"].string, name: $0["name"].string, blurb: $0["blurb"].string, need: $0["need"].isNull ? storiesPerChapter : $0["need"].int,
                    fact: $0["fact"].string, cover: $0["cover"].string, rewardTitle: $0["reward"].string)
        }
        let items = j["items"].array.map { i in
            Item(id: i["id"].string, chapter: i["ch"].string, kind: i["kind"].string, title: i["t"].string, text: i["s"].string, fits: i["fam"].array.map { $0.string },
                 options: i["o"].array.map { o in
                     Option(label: o["l"].string, hint: o["h"].string, days: max(1, min(3, o["d"].int)), result: o["r"].string, fx: o["fx"],
                            chance: o["p"].isNull ? nil : o["p"].double, fxBad: o["fxb"], resultBad: o["rb"].string)
                 })
        }
        return (chapters, items)
    }()

    public static var chapters: [Chapter] { book.chapters }
    public static var items: [Item] { book.items }
    public static func item(_ id: String) -> Item? { book.items.first { $0.id == id } }

    public static func isOpen(_ s: GameState) -> Bool { Unlocks.isOpen(s, "desk") }

    static func liveCompanies(_ s: GameState) -> [Company] {
        s.companies.filter { $0.status == .open && $0.type != "club" }
    }

    static func fits(_ it: Item, _ co: Company, _ data: GameData) -> Bool {
        let fam = data.catalog[co.type]?.family ?? ""
        return it.fits.contains("any") || it.fits.contains(co.type) || it.fits.contains(fam)
    }

    static func dayNumber(_ s: GameState) -> Int { GameCalendar.startDay + s.week * 7 + s.day }

    static func notebook(_ s: GameState) -> JSONValue { s.rest["desk"]?["nb"] ?? .object([:]) }

    static func pickToday(_ s: GameState, realDay: Int, data: GameData) -> (Item, Int)? {
        let cos = liveCompanies(s)
        let nb = notebook(s)
        let fitting = book.items.filter { it in cos.contains { fits(it, $0, data) } }
        guard !fitting.isEmpty else { return nil }
        var pool = fitting.filter { nb[$0.id].isNull }
        if pool.isEmpty {
            let oldest = fitting.map { nb[$0.id]["rd"].int }.min() ?? 0
            pool = fitting.filter { nb[$0.id]["rd"].int == oldest }
        }
        var done: [String: Int] = [:]
        for it in book.items where !nb[it.id].isNull { done[it.chapter, default: 0] += 1 }
        let weights = pool.map { 1.0 / Double(1 + (done[$0.chapter] ?? 0)) }
        var h = HashedRandom("\(s.seed):desk:\(realDay)")
        var pick = h.next() * weights.reduce(0, +)
        var chosen = pool[0]
        for (i, it) in pool.enumerated() { if pick < weights[i] { chosen = it; break }; pick -= weights[i] }
        let cands = cos.filter { fits(chosen, $0, data) }
        let co = cands[Int(h.next() * Double(cands.count)) % cands.count]
        return (chosen, co.id)
    }

    public struct Today: Equatable, Sendable {
        public var item: Item
        public var companyID: Int
        public var companyName: String
        public var picked: Int?
        public var text: String
    }

    public static func waiting(_ s: GameState, realDay: Int) -> Bool {
        guard isOpen(s) else { return false }
        if let c = s.rest["desk"]?["cur"], !c.isNull, c["day"].int == realDay { return c["pick"].int < 0 }
        return !liveCompanies(s).isEmpty
    }

    public static func today(_ s: GameState, realDay: Int) -> Today? {
        guard isOpen(s), let c = s.rest["desk"]?["cur"], !c.isNull, c["day"].int == realDay, let it = item(c["id"].string) else { return nil }
        let name = s.company(c["co"].int)?.name ?? "your company"
        return Today(item: it, companyID: c["co"].int, companyName: name, picked: c["pick"].int >= 0 ? c["pick"].int : nil, text: fill(it.text, name))
    }

    static func fill(_ text: String, _ name: String) -> String { text.replacingOccurrences(of: "{co}", with: name) }

    @discardableResult
    public static func open(_ s: inout GameState, realDay: Int, data: GameData) -> Today? {
        guard isOpen(s) else { return nil }
        if today(s, realDay: realDay) == nil {
            guard let (it, cid) = pickToday(s, realDay: realDay, data: data) else { return nil }
            var d = s.rest["desk"] ?? .object([:])
            d["cur"] = .object(["day": .number(Double(realDay)), "id": .string(it.id), "co": .number(Double(cid)), "pick": -1])
            s.rest["desk"] = d
        }
        return today(s, realDay: realDay)
    }

    public struct Choice: Equatable, Sendable {
        public var chosen: String, told: String
        public var days: Int
    }

    @discardableResult
    public static func choose(_ s: inout GameState, option idx: Int, realDay: Int, data: GameData) -> Choice? {
        guard let t = today(s, realDay: realDay), t.picked == nil, t.item.options.indices.contains(idx) else { return nil }
        let o = t.item.options[idx]
        var d = s.rest["desk"] ?? .object([:])
        var cur = d["cur"]; cur["pick"] = .number(Double(idx)); d["cur"] = cur
        var pend = d["pend"].array
        pend.append(.object(["id": .string(t.item.id), "co": .number(Double(t.companyID)), "pick": .number(Double(idx)),
                             "due": .number(Double(dayNumber(s) + o.days)), "rd": .number(Double(realDay))]))
        d["pend"] = .array(pend)
        d["n"] = .number(Double(d["n"].int + 1))
        s.rest["desk"] = d
        return Choice(chosen: o.label, told: o.days == 1 ? "Done. You will hear how it went tomorrow morning." : "Done. You will hear how it went in \(o.days) days.", days: o.days)
    }

    public static func runDay(_ s: inout GameState, data: GameData) {
        guard var d = s.rest["desk"], !d["pend"].array.isEmpty else { return }
        let today = dayNumber(s)
        let all = d["pend"].array
        let due = all.filter { $0["due"].int <= today }
        guard !due.isEmpty else { return }
        d["pend"] = .array(all.filter { $0["due"].int > today })
        s.rest["desk"] = d
        for p in due { resolve(&s, p, data: data) }
    }

    static func resolve(_ s: inout GameState, _ p: JSONValue, data: GameData) {
        guard let it = item(p["id"].string), it.options.indices.contains(p["pick"].int) else { return }
        let o = it.options[p["pick"].int]
        let cid = p["co"].int
        let name = s.company(cid)?.name ?? "your company"
        var worked = true
        if let c = o.chance { worked = HashedRandom.first("\(s.seed):deskroll:\(it.id):\(p["due"].int)") < c }
        let fx = worked ? o.fx : o.fxBad
        let result = fill(worked || o.resultBad.isEmpty ? o.result : o.resultBad, name)
        if let ci = s.companyIndex(cid), s.companies[ci].status == .open { apply(&s, ci, fx, data: data) }
        let ok = worked ? 1 : -1
        var dk = s.rest["desk"] ?? .object([:])
        var nb = dk["nb"]
        nb[it.id] = .object(["pick": .number(Double(p["pick"].int)), "co": .number(Double(cid)), "rd": .number(Double(p["rd"].int)), "gw": .number(Double(s.week)),
                             "res": .string(result), "ok": .number(Double(ok))])
        dk["nb"] = nb
        s.rest["desk"] = dk
        s.addMessage(from: "Desk", title: "\(it.title): how it turned out", body: result, companyID: cid, tone: o.chance == nil ? "n" : (worked ? "good" : "bad"))
        checkChapter(&s, it.chapter)
    }

    static func apply(_ s: inout GameState, _ ci: Int, _ fx: JSONValue, data: GameData) {
        guard !fx.isNull else { return }
        let co = s.companies[ci]
        func mult(_ key: String, _ modKey: String) {
            let v = fx[key]
            guard !v.isNull else { return }
            let m = clamp(v[0].double, demandRange.lowerBound, demandRange.upperBound)
            let w = min(weeksRange.upperBound, max(weeksRange.lowerBound, v[1].int + 1))
            Engagement.addModifier(&s, ci, key: modKey, multiplier: m, weeks: w)
        }
        mult("dem", "dem")
        mult("cost", "cogsup")
        if fx["rep"].double != 0 { s.companies[ci].reputation = clamp(co.reputation + clamp(fx["rep"].double, pointRange.lowerBound, pointRange.upperBound), 0, 100) }
        if fx["aware"].double != 0 { s.companies[ci].awareness = clamp(co.awareness + clamp(fx["aware"].double, pointRange.lowerBound, pointRange.upperBound), 0, 100) }
        if fx["mood"].double != 0 {
            let mood = co.value("mood").isNull ? 60 : co.num("mood")
            s.companies[ci].set("mood", clamp(mood + clamp(fx["mood"].double, moodRange.lowerBound, moodRange.upperBound), 0, 100))
        }
        if fx["pay"].double > 0 {
            _ = Payments.companyPays(&s, companyID: co.id, amount: Engagement.spend(s, co, share: min(maxPay, fx["pay"].double), data: data), category: "oth", label: "Desk")
        }
        if fx["gain"].double > 0 {
            Payments.companyReceives(&s, companyID: co.id, amount: Engagement.spend(s, co, share: min(maxGain, fx["gain"].double), data: data), category: "rev", label: "Desk")
        }
    }

    public struct Story: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String, kind: String
        public var chosen: String, result: String
        public var week: Int, companyName: String
        public var luck: Int
    }
    public struct ChapterPage: Identifiable, Equatable, Sendable {
        public var id: String
        public var chapter: Chapter
        public var stories: [Story]
        public var finished: Bool { stories.count >= chapter.need }
        public var week: Int?
    }

    static func checkChapter(_ s: inout GameState, _ chapterID: String) {
        guard let ch = book.chapters.first(where: { $0.id == chapterID }) else { return }
        let nb = notebook(s)
        let n = book.items.filter { $0.chapter == chapterID && !nb[$0.id].isNull }.count
        guard n >= ch.need, (s.rest["desk"]?["rw"][chapterID] ?? .null).isNull else { return }
        var d = s.rest["desk"] ?? .object([:])
        d["rw"][chapterID] = .number(Double(s.week))
        s.rest["desk"] = d
        s.addMessage(from: "Desk", title: "Notebook: \(ch.name) is complete", body: "\(ch.fact) You have earned a notebook cover (\(ch.rewardTitle)).", tone: "good")
    }

    public static func pages(_ s: GameState) -> [ChapterPage] {
        let nb = notebook(s)
        return book.chapters.map { ch in
            let stories: [Story] = book.items.filter { $0.chapter == ch.id && !nb[$0.id].isNull }.map { it in
                let r = nb[it.id]
                let pick = r["pick"].int
                return Story(id: it.id, title: it.title, kind: it.kind, chosen: it.options.indices.contains(pick) ? it.options[pick].label : "", result: r["res"].string,
                             week: r["gw"].int, companyName: s.company(r["co"].int)?.name ?? "", luck: r["ok"].int == -1 ? -1 : (it.options.indices.contains(pick) && it.options[pick].chance != nil ? 1 : 0))
            }.sorted { $0.week > $1.week }
            let rw = s.rest["desk"]?["rw"][ch.id] ?? .null
            return ChapterPage(id: ch.id, chapter: ch, stories: stories, week: rw.isNull ? nil : rw.int)
        }
    }

    public static func covers(_ s: GameState) -> [String] {
        let rw = s.rest["desk"]?["rw"].object ?? [:]
        return rw.sorted { $0.value.int != $1.value.int ? $0.value.int < $1.value.int : $0.key < $1.key }.compactMap { (e: (key: String, value: JSONValue)) -> String? in book.chapters.first { $0.id == e.key }?.cover }
    }

    public static func daysPlayed(_ s: GameState) -> Int { s.rest["desk"]?["n"].int ?? 0 }

    public static func playingOut(_ s: GameState) -> [String] {
        (s.rest["desk"]?["pend"].array ?? []).compactMap { item($0["id"].string)?.title }
    }
}
