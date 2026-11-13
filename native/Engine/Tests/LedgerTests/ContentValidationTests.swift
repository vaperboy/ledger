import XCTest
import GameCore
@testable import Simulation

final class ContentValidationTests: XCTestCase {
    private static let native: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let hexDigits: Set<Character> = Set("0123456789abcdefABCDEF")
    private static let rarities: Set<String> = ["common", "rare", "epic", "legendary"]
    private static let motifs: Set<String> = ["rays", "rings", "dots", "stripes", "waves", "grid", "hills", "stars"]

    private func contentFiles() -> [URL] {
        var out: [URL] = []
        for root in ["Engine/Sources", "App/Ledger/Resources/Content"] {
            let base: URL = Self.native.appendingPathComponent(root)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "json" && url.path.contains("/Resources/") { out.append(url) }
        }
        return out.sorted { (a: URL, b: URL) -> Bool in a.path < b.path }
    }

    private func load(_ relative: String, _ problems: inout [String]) -> JSONValue {
        let url: URL = Self.native.appendingPathComponent(relative)
        guard let raw = try? Data(contentsOf: url) else { problems.append("\(relative): the file is missing"); return .null }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: raw) else {
            problems.append("\(relative): not valid JSON (look for a missing comma, bracket or quote)")
            return .null
        }
        return json
    }

    private func missing(_ e: JSONValue, _ field: String) -> Bool {
        if e[field].isNull { return true }
        if case .string(let s) = e[field], s.isEmpty { return true }
        return false
    }

    private func need(_ e: JSONValue, _ fields: [String], _ file: String, _ label: String, _ problems: inout [String]) {
        for f in fields where missing(e, f) { problems.append("\(file): \(label) is missing \"\(f)\"") }
    }

    private func uniqueIDs(_ list: [JSONValue], _ file: String, _ problems: inout [String]) -> Set<String> {
        var seen: Set<String> = []
        for (i, e) in list.enumerated() {
            let id: String = e["id"].string
            if id.isEmpty { problems.append("\(file): entry number \(i + 1) has no id") }
            else if !seen.insert(id).inserted { problems.append("\(file): the id \"\(id)\" is used twice") }
        }
        return seen
    }

    private func isHex(_ v: JSONValue) -> Bool {
        let s: String = v.string
        return s.count == 6 && s.allSatisfy { (c: Character) -> Bool in Self.hexDigits.contains(c) }
    }

    private func checkHex(_ list: [JSONValue], _ file: String, _ label: String, _ problems: inout [String]) {
        for c in list where !isHex(c) { problems.append("\(file): \(label) colour \"\(c.string)\" must be six hex digits such as C9A86A") }
    }

    private func checkRarity(_ e: JSONValue, _ field: String, _ file: String, _ label: String, _ problems: inout [String]) {
        if !Self.rarities.contains(e[field].string) { problems.append("\(file): \(label) has \(field) \"\(e[field].string)\"; use common, rare, epic or legendary") }
    }

    private func finish(_ problems: [String]) {
        XCTAssertTrue(problems.isEmpty, "\n" + problems.joined(separator: "\n"))
    }

    private func walkIDs(_ v: JSONValue, _ path: String, _ file: String, _ problems: inout [String]) {
        switch v {
        case .array(let items):
            let withID: [JSONValue] = items.filter { (e: JSONValue) -> Bool in if case .string = e["id"] { return true } else { return false } }
            if items.count > 1 && withID.count == items.count {
                var seen: Set<String> = []
                for e in items where !seen.insert(e["id"].string).inserted { problems.append("\(file): the id \"\(e["id"].string)\" is used twice in \(path.isEmpty ? "the list" : path)") }
            }
            for (i, e) in items.enumerated() { walkIDs(e, path + "[\(i)]", file, &problems) }
        case .object(let o):
            for (k, e) in o { walkIDs(e, path.isEmpty ? k : path + "." + k, file, &problems) }
        default:
            break
        }
    }

    func testEveryContentFileIsValidJSONWithUniqueIds() {
        var problems: [String] = []
        let files: [URL] = contentFiles()
        XCTAssertGreaterThan(files.count, 40, "content files were not found")
        for url in files {
            let name: String = url.path.replacingOccurrences(of: Self.native.path + "/", with: "")
            guard let raw = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: raw) else {
                problems.append("\(name): not valid JSON (look for a missing comma, bracket or quote)")
                continue
            }
            if json.isNull { problems.append("\(name): the file is empty") }
            walkIDs(json, "", name, &problems)
        }
        finish(problems)
    }

    func testArtifactsAndCollections() {
        let file: String = "Engine/Sources/Simulation/Resources/Content/artifacts/artifacts.json"
        var p: [String] = []
        let j: JSONValue = load(file, &p)
        let cols: [JSONValue] = j["collections"].array
        let arts: [JSONValue] = j["artifacts"].array
        let colIDs: Set<String> = uniqueIDs(cols, file, &p)
        let artIDs: Set<String> = uniqueIDs(arts, file, &p)
        let rewards: Set<String> = Set(GoldCosmetics.all.filter { $0.source == .collection }.map { $0.id })
        for c in cols {
            need(c, ["id", "name", "blurb", "reward", "look"], file, "collection \"\(c["id"].string)\"", &p)
            if !rewards.contains(c["reward"].string) { p.append("\(file): collection \"\(c["id"].string)\" has reward \"\(c["reward"].string)\", which is not a source:collection cosmetic in gold_cosmetics.json") }
            checkHex([c["look"]["top"], c["look"]["bottom"], c["look"]["ink"]], file, "collection \"\(c["id"].string)\"", &p)
            if !Self.motifs.contains(c["look"]["motif"].string) { p.append("\(file): collection \"\(c["id"].string)\" has an unknown motif \"\(c["look"]["motif"].string)\"") }
            if !arts.contains(where: { (a: JSONValue) -> Bool in a["collection"].string == c["id"].string }) { p.append("\(file): collection \"\(c["id"].string)\" has no artifacts") }
        }
        for a in arts {
            let label: String = "artifact \"\(a["id"].string)\""
            need(a, ["id", "name", "collection", "rarity", "note", "symbol"], file, label, &p)
            checkRarity(a, "rarity", file, label, &p)
            if !colIDs.contains(a["collection"].string) { p.append("\(file): \(label) is in collection \"\(a["collection"].string)\", which does not exist") }
            if CardCatalog.def(a["id"].string) != nil { p.append("\(file): \(label) has the same id as a card") }
        }
        for r in Self.rarities where !arts.contains(where: { (a: JSONValue) -> Bool in a["rarity"].string == r }) {
            p.append("\(file): there must be at least one \(r) artifact because boxes drop them")
        }
        XCTAssertEqual(artIDs.count, ArtifactCatalog.defs.count, "the engine loaded a different number of artifacts than the file holds")
        XCTAssertEqual(colIDs.count, ArtifactCatalog.everyCollection.count)
        finish(p)
    }

    func testCards() {
        let file: String = "Engine/Sources/Simulation/Resources/Content/cards/cards.json"
        var p: [String] = []
        let j: JSONValue = load(file, &p)
        let cards: [JSONValue] = j["cards"].array
        let ids: Set<String> = uniqueIDs(cards, file, &p)
        let motions: Set<String> = ["none", "shimmer", "drift", "pulse", "aurora"]
        for c in cards {
            let id: String = c["id"].string
            let label: String = "card \"\(id)\""
            need(c, ["id", "kind", "name", "rarity", "colors", "motion"], file, label, &p)
            checkRarity(c, "rarity", file, label, &p)
            checkHex(c["colors"].array, file, label, &p)
            if c["colors"].array.count < 2 { p.append("\(file): \(label) needs at least two colours") }
            if !motions.contains(c["motion"].string) { p.append("\(file): \(label) has motion \"\(c["motion"].string)\"; use none, shimmer, drift, pulse or aurora") }
            switch c["kind"].string {
            case "profile":
                if !id.hasPrefix("card.p.") { p.append("\(file): \(label) is a profile card, so its id must start with card.p.") }
            case "company":
                if !id.hasPrefix("card.c.") { p.append("\(file): \(label) is a company card, so its id must start with card.c.") }
                if missing(c, "logo") { p.append("\(file): \(label) is a company card and needs a logo (an SF Symbol name)") }
            default:
                p.append("\(file): \(label) has kind \"\(c["kind"].string)\"; use profile or company")
            }
        }
        for kind in ["profile", "company"] {
            for r in Self.rarities where !cards.contains(where: { (c: JSONValue) -> Bool in c["kind"].string == kind && c["rarity"].string == r }) {
                p.append("\(file): there must be at least one \(r) \(kind) card because card packs drop them")
            }
        }
        var last: Int = 0
        for lr in j["levelRewards"].array {
            if !ids.contains(lr["card"].string) { p.append("\(file): levelRewards names card \"\(lr["card"].string)\", which does not exist") }
            if lr["level"].int <= last { p.append("\(file): levelRewards must list levels in rising order, starting above 0 (level \(lr["level"].int))") }
            last = lr["level"].int
        }
        XCTAssertEqual(ids.count, CardCatalog.everything.count)
        finish(p)
    }

    func testCosmeticsBadgesAndThemes() {
        let file: String = "Engine/Sources/Simulation/Resources/Content/cosmetics/gold_cosmetics.json"
        let bfile: String = "Engine/Sources/Simulation/Resources/Content/cosmetics/badges_themes.json"
        var p: [String] = []
        let j: JSONValue = load(file, &p)
        let list: [JSONValue] = j["cosmetics"].array
        let ids: Set<String> = uniqueIDs(list, file, &p)
        let kinds: Set<String> = ["outfit", "face", "hair", "skin", "namePlate", "backdrop", "tradePlate", "richListFlair", "saveSlot"]
        let colRewards: Set<String> = Set(ArtifactCatalog.everyCollection.map { $0.rewardID })
        for c in list {
            let label: String = "cosmetic \"\(c["id"].string)\""
            need(c, ["id", "kind", "title", "detail", "rarity", "source", "colors"], file, label, &p)
            checkRarity(c, "rarity", file, label, &p)
            checkHex(c["colors"].array, file, label, &p)
            if !kinds.contains(c["kind"].string) { p.append("\(file): \(label) has kind \"\(c["kind"].string)\"; use outfit, face, hair, skin, namePlate, backdrop, tradePlate, richListFlair or saveSlot") }
            if !["store", "box", "collection", "plan", "free", "level", "rank", "goal"].contains(c["source"].string) { p.append("\(file): \(label) has source \"\(c["source"].string)\"; use store, box, collection, plan, free, level, rank or goal") }
            if c["art"].string.isEmpty { p.append("\(file): \(label) needs an art slot name") }
            if c["source"].string == "collection" && !colRewards.contains(c["id"].string) { p.append("\(file): \(label) is a collection reward but no collection in artifacts.json names it") }
            if c["source"].string == "store" && GoldPrices.item(c["id"].string) == nil && GoldCosmetics.storePrice(ContentFile.rarity(c["rarity"].string)) == nil { p.append("\(file): \(label) is a legendary store item and needs a price in pricing/prices.json") }
        }
        for r in Self.rarities where r != "legendary" && !list.contains(where: { (c: JSONValue) -> Bool in c["rarity"].string == r && c["source"].string != "collection" && c["kind"].string != "saveSlot" }) {
            p.append("\(file): box drops need at least one \(r) cosmetic")
        }

        var sids: Set<String> = []
        let cardIDs: Set<String> = Set(CardCatalog.everything.map { $0.id })
        let artifactIDs: Set<String> = Set(ArtifactCatalog.defs.map { $0.id })
        let sKinds: Set<String> = ["outfit", "badge", "theme", "namePlate", "backdrop", "saveSlot", "advisorLine", "richListFlair", "tradePlate", "card", "artifact", "xp", "box", "gold"]
        XCTAssertFalse(SeasonCatalog.all.isEmpty)
        for n in SeasonCatalog.all.map({ (d: SeasonDef) -> Int in d.number }) {
        let sfile: String = "Engine/Sources/Simulation/Resources/Content/season/season_\(n).json"
        let s: JSONValue = load(sfile, &p)
        let rewards: [JSONValue] = s["rewards"].array
        for id in uniqueIDs(rewards, sfile, &p) {
            if !sids.insert(id).inserted { p.append("\(sfile): the reward id \"\(id)\" is already used by another season") }
        }
        var slots: Set<String> = []
        for r in rewards {
            let label: String = "reward \"\(r["id"].string)\""
            need(r, ["id", "tier", "kind"], sfile, label, &p)
            if !(1...SeasonPass.tierCount).contains(r["tier"].int) { p.append("\(sfile): \(label) has tier \(r["tier"].int); tiers run 1 to \(SeasonPass.tierCount)") }
            if !slots.insert("\(r["premium"].bool)\(r["tier"].int)").inserted { p.append("\(sfile): \(label) shares tier \(r["tier"].int) and track with another reward") }
            if ids.contains(r["id"].string) { p.append("\(sfile): \(label) has the same id as a cosmetic in gold_cosmetics.json") }
            let kind: String = r["kind"].string
            if !sKinds.contains(kind) { p.append("\(sfile): \(label) has kind \"\(kind)\"") }
            if kind == "card" && !cardIDs.contains(r["card"].string) { p.append("\(sfile): \(label) names card \"\(r["card"].string)\", which does not exist in cards.json") }
            if kind == "artifact" && !artifactIDs.contains(r["artifact"].string) { p.append("\(sfile): \(label) names artifact \"\(r["artifact"].string)\", which does not exist in artifacts.json") }
            if kind == "artifact" && r["id"].string != r["artifact"].string { p.append("\(sfile): \(label) is an artifact reward, so its id must be the artifact id") }
            if (kind == "box" || kind == "gold" || kind == "xp") && r["amount"].int <= 0 { p.append("\(sfile): \(label) needs an amount above 0") }
            let plain: Bool = !["card", "artifact", "xp", "box", "gold"].contains(kind)
            if plain { need(r, ["title", "detail"], sfile, label, &p) }
            if !r["rarity"].isNull { checkRarity(r, "rarity", sfile, label, &p) }
            if plain && !r["colors"].isNull { checkHex(r["colors"].array, sfile, label, &p) }
        }
        }
        XCTAssertEqual(sids.count, SeasonRewards.everything.count)

        let b: JSONValue = load(bfile, &p)
        let badges: [JSONValue] = b["badges"].array
        let themes: [JSONValue] = b["themes"].array
        _ = uniqueIDs(badges, bfile, &p)
        _ = uniqueIDs(themes, bfile, &p)
        for x in badges { need(x, ["id", "title", "symbol"], bfile, "badge \"\(x["id"].string)\"", &p) }
        for x in themes {
            need(x, ["id", "title", "red", "green", "blue"], bfile, "theme \"\(x["id"].string)\"", &p)
            for k in ["red", "green", "blue"] where x[k].double < 0 || x[k].double > 1 { p.append("\(bfile): theme \"\(x["id"].string)\" has \(k) outside 0 to 1") }
        }
        if badges.first?["premium"].bool == true { p.append("\(bfile): the first badge is the default and must not be premium") }
        if themes.first?["premium"].bool == true { p.append("\(bfile): the first theme is the default and must not be premium") }
        XCTAssertEqual(badges.count, Cosmetics.badges.count)
        XCTAssertEqual(themes.count, Cosmetics.themes.count)
        finish(p)
    }

    private func checkLook(_ list: [JSONValue], _ themeIDs: Set<String>, _ file: String, _ what: String, _ problems: inout [String]) {
        for e in list {
            let label: String = "\(what) \"\(e["id"].string)\""
            if !e["theme"].isNull && !themeIDs.contains(e["theme"].string) { problems.append("\(file): \(label) has theme \"\(e["theme"].string)\", which is not in item_themes.json") }
            for f in ["founderEdition", "bound"] {
                if case .bool = e[f] { continue }
                if !e[f].isNull { problems.append("\(file): \(label) has \"\(f)\" that is not true or false") }
            }
        }
    }

    func testThemesAndSeasonFields() {
        let root: String = "Engine/Sources/Simulation/Resources/Content/"
        let tfile: String = root + "themes/item_themes.json"
        var p: [String] = []
        let themes: [JSONValue] = load(tfile, &p)["themes"].array
        let themeIDs: Set<String> = uniqueIDs(themes, tfile, &p)
        for t in themes { need(t, ["id", "name"], tfile, "theme \"\(t["id"].string)\"", &p) }
        for required in [ItemThemes.classicID, ItemThemes.founderID] where !themeIDs.contains(required) { p.append("\(tfile): the theme \"\(required)\" is missing") }
        XCTAssertGreaterThanOrEqual(themes.count, 5)
        XCTAssertEqual(themeIDs.count, ItemThemes.all.count)

        checkLook(load(root + "cards/cards.json", &p)["cards"].array, themeIDs, "cards.json", "card", &p)
        checkLook(load(root + "cosmetics/gold_cosmetics.json", &p)["cosmetics"].array, themeIDs, "gold_cosmetics.json", "cosmetic", &p)
        checkLook(load("Engine/Sources/Businesses/Resources/logo_catalogue.json", &p)["logos"].array, themeIDs, "logo_catalogue.json", "logo", &p)
        let avatars: [JSONValue] = load("App/Ledger/Resources/Content/avatars/avatars.json", &p)["avatars"].array
        checkLook(avatars, themeIDs, "avatars.json", "icon", &p)
        for a in avatars where a["unlock"].string == "season" && SeasonRewards.item(a["value"].string)?.accountBound == true && !a["bound"].bool {
            p.append("avatars.json: icon \"\(a["id"].string)\" is unlocked by a bound reward, so it must be bound too")
        }

        let bfile: String = root + "boxes/boxes.json"
        let boxes: [JSONValue] = load(bfile, &p)["boxes"].array
        checkLook(boxes, themeIDs, "boxes.json", "box", &p)
        for b in boxes {
            let want: String = b["theme"].isNull ? ItemThemes.classicID : b["theme"].string
            XCTAssertEqual(BoxKind(rawValue: b["id"].string)?.theme, want, "box \(b["id"].string) must carry the theme the file gives it")
        }

        XCTAssertFalse(SeasonCatalog.all.isEmpty)
        XCTAssertEqual(SeasonCatalog.all.map { $0.number }, Array(1...SeasonCatalog.all.count), "season files must be numbered season_1, season_2 without gaps")
        XCTAssertTrue((180...184).contains(SeasonPass.seasonDays), "a season runs half a year")
        for d in SeasonCatalog.all {
            let sfile: String = root + "season/season_\(d.number).json"
            let s: JSONValue = load(sfile, &p)
            if s["season"].int != d.number { p.append("\(sfile): \"season\" must be \(d.number)") }
            need(s, ["name", "theme"], sfile, "the season", &p)
            if !themeIDs.contains(s["theme"].string) { p.append("\(sfile): the season theme \"\(s["theme"].string)\" is not in item_themes.json") }
            if s["months"].int != SeasonCatalog.monthsPerSeason { p.append("\(sfile): \"months\" must be \(SeasonCatalog.monthsPerSeason), half a year") }
            checkLook([s], themeIDs, sfile, "season", &p)
            checkLook(s["rewards"].array, themeIDs, sfile, "reward", &p)
            XCTAssertEqual(d.days, SeasonPass.seasonDays)
            XCTAssertTrue(d.rewards.allSatisfy { ItemThemes.isKnown($0.theme) })
        }
        let first: SeasonDef? = SeasonCatalog.def(1)
        XCTAssertEqual(first?.theme, ItemThemes.founderID)
        XCTAssertEqual(first?.founderEdition, true)
        finish(p)
    }

    func testBoxesAndLevelGates() {
        let file: String = "Engine/Sources/Simulation/Resources/Content/boxes/boxes.json"
        var p: [String] = []
        let j: JSONValue = load(file, &p)
        let boxes: [JSONValue] = j["boxes"].array
        let ids: Set<String> = uniqueIDs(boxes, file, &p)
        XCTAssertEqual(ids, Set(BoxKind.allCases.map { $0.rawValue }), "boxes.json must hold exactly the box ids the game knows")
        let prizes: Set<String> = ["cosmetic", "artifact", "gold", "money", "profileCard", "companyCard"]
        for box in boxes {
            let label: String = "box \"\(box["id"].string)\""
            need(box, ["id", "title", "rows"], file, label, &p)
            let rows: [JSONValue] = box["rows"].array
            if rows.reduce(0, { (acc: Int, r: JSONValue) -> Int in acc + r["weight"].int }) != BoxOdds.totalWeight { p.append("\(file): the weights of \(label) must add up to \(BoxOdds.totalWeight)") }
            for r in rows {
                checkRarity(r, "rarity", file, label, &p)
                if !prizes.contains(r["prize"].string) { p.append("\(file): \(label) has prize \"\(r["prize"].string)\"") }
                if r["weight"].int <= 0 { p.append("\(file): \(label) has a row with no weight") }
                if (r["prize"].string == "gold" || r["prize"].string == "money") && r["amount"].int <= 0 { p.append("\(file): \(label) has a \(r["prize"].string) row without an amount") }
                let rarity: BoxRarity = ContentFile.rarity(r["rarity"].string)
                if r["prize"].string == "artifact" && ArtifactCatalog.defs(of: rarity).isEmpty { p.append("\(file): \(label) drops \(rarity.rawValue) artifacts but none exist") }
                if r["prize"].string == "profileCard" && CardCatalog.defs(.profile, rarity).isEmpty { p.append("\(file): \(label) drops \(rarity.rawValue) profile cards but none exist") }
                if r["prize"].string == "companyCard" && CardCatalog.defs(.company, rarity).isEmpty { p.append("\(file): \(label) drops \(rarity.rawValue) company cards but none exist") }
            }
        }
        for kind in BoxKind.allCases where !BoxOdds.isFair(kind) {
            p.append("\(file): box \"\(kind.rawValue)\" breaks the fairness rules (weights, cash share, gold against price)")
        }

        finish(p)
    }

    func testAvatarsAndTradeIcons() {
        let file: String = "App/Ledger/Resources/Content/avatars/avatars.json"
        var p: [String] = []
        let j: JSONValue = load(file, &p)
        let list: [JSONValue] = j["avatars"].array
        _ = uniqueIDs(list, file, &p)
        let badgeIDs: Set<String> = Set(Cosmetics.badges.map { $0.id })
        let collectionIDs: Set<String> = Set(ArtifactCatalog.everyCollection.map { $0.id })
        for a in list {
            let label: String = "icon \"\(a["id"].string)\""
            need(a, ["id", "title", "tier", "unlock", "symbol", "top", "bottom", "ink", "motif"], file, label, &p)
            checkRarity(a, "tier", file, label, &p)
            checkHex([a["top"], a["bottom"], a["ink"]], file, label, &p)
            if !Self.motifs.contains(a["motif"].string) { p.append("\(file): \(label) has motif \"\(a["motif"].string)\"; use rings, dots, hills, rays, stars, waves, stripes or grid") }
            let value: JSONValue = a["value"]
            switch a["unlock"].string {
            case "free", "gold", "pro", "plus", "proOwner", "founder":
                break
            case "rank":
                if !(1..<Career.ranks.count).contains(value.int) { p.append("\(file): \(label) needs a rank value from 1 to \(Career.ranks.count - 1)") }
            case "level":
                if value.int < 1 { p.append("\(file): \(label) needs a level value of 1 or more") }
            case "badge":
                if !badgeIDs.contains(value.string) { p.append("\(file): \(label) needs a value that is a badge id in badges_themes.json, not \"\(value.string)\"") }
            case "collection":
                if !collectionIDs.contains(value.string) { p.append("\(file): \(label) needs a value that is a collection id in artifacts.json, not \"\(value.string)\"") }
            case "season":
                if SeasonRewards.item(value.string) == nil { p.append("\(file): \(label) needs a value that is a reward id in season_1.json, not \"\(value.string)\"") }
            default:
                p.append("\(file): \(label) has unlock \"\(a["unlock"].string)\"; use free, gold, rank, level, badge, collection, season, pro, plus, proOwner or founder")
            }
        }
        if !list.contains(where: { (a: JSONValue) -> Bool in a["unlock"].string == "free" }) { p.append("\(file): at least one icon must be free") }

        let tfile: String = "App/Ledger/Resources/Content/trade_icons/trade_icons.json"
        let t: JSONValue = load(tfile, &p)
        let families: [String: JSONValue] = t["families"].object
        for (k, f) in families {
            checkHex([f["top"], f["bottom"], f["ink"]], tfile, "family \"\(k)\"", &p)
            if !Self.motifs.contains(f["motif"].string) { p.append("\(tfile): family \"\(k)\" has an unknown motif \"\(f["motif"].string)\"") }
        }
        let trades: JSONValue = load("Engine/Sources/Businesses/Resources/trades.json", &p)["trades"]
        let entries: [JSONValue] = t["trades"].array
        let iconIDs: Set<String> = uniqueIDs(entries, tfile, &p)
        for e in entries {
            need(e, ["id", "symbol", "family"], tfile, "trade icon \"\(e["id"].string)\"", &p)
            if trades[e["id"].string].isNull { p.append("\(tfile): \"\(e["id"].string)\" is not a trade id in trades.json") }
            if families[e["family"].string] == nil { p.append("\(tfile): trade icon \"\(e["id"].string)\" uses family \"\(e["family"].string)\", which is not defined") }
        }
        for id in trades.object.keys where !iconIDs.contains(id) { p.append("\(tfile): trade \"\(id)\" has no icon entry") }
        finish(p)
    }

    func testWorldContentReferences() {
        var p: [String] = []
        let tfile: String = "Engine/Sources/Businesses/Resources/trades.json"
        let trades: [String: JSONValue] = load(tfile, &p)["trades"].object
        let families: Set<String> = Set(trades.values.map { (t: JSONValue) -> String in t["fam"].string })
        let countries: [JSONValue] = load("Engine/Sources/Countries/Resources/countries.json", &p).array
        let codes: Set<String> = uniqueIDsByCode(countries, &p)
        for c in countries { need(c, ["code", "name", "currency"], "countries.json", "country \"\(c["code"].string)\"", &p) }
        for (id, t) in trades {
            if t["id"].string != id { p.append("\(tfile): the trade filed under \"\(id)\" has the id \"\(t["id"].string)\"") }
            need(t, ["n", "fam", "cat"], tfile, "trade \"\(id)\"", &p)
        }

        let efile: String = "Engine/Sources/Events/Resources/events_pack.json"
        let pack: [String: JSONValue] = load(efile, &p)["events"].object
        for (id, e) in pack {
            let label: String = "event \"\(id)\""
            need(e, ["area", "t", "b", "w", "sev"], efile, label, &p)
            if e["sev"].int < 1 || e["sev"].int > 3 { p.append("\(efile): \(label) has sev \(e["sev"].int); use 1, 2 or 3") }
            for t in e["tr"].array + e["notTr"].array where trades[t.string] == nil { p.append("\(efile): \(label) names the trade \"\(t.string)\", which is not in trades.json") }
            for f in e["fam"].array where !families.contains(f.string) { p.append("\(efile): \(label) names the family \"\(f.string)\", which no trade uses") }
            for c in e["cc"].array where !codes.contains(c.string) { p.append("\(efile): \(label) names the country \"\(c.string)\", which is not in countries.json") }
        }

        let dfile: String = "Engine/Sources/Events/Resources/decisions.json"
        let decisions: [String: JSONValue] = load(dfile, &p)["decisions"].object
        for (id, d) in decisions {
            let label: String = "decision \"\(id)\""
            need(d, ["t", "b", "opts"], dfile, label, &p)
            if d["opts"].array.isEmpty { p.append("\(dfile): \(label) needs at least one option") }
            for o in d["opts"].array where missing(o, "l") { p.append("\(dfile): \(label) has an option without a label \"l\"") }
            for t in d["notTr"].array where trades[t.string] == nil { p.append("\(dfile): \(label) names the trade \"\(t.string)\", which is not in trades.json") }
            for f in d["fam"].array where !families.contains(f.string) { p.append("\(dfile): \(label) names the family \"\(f.string)\", which no trade uses") }
        }

        let cfile: String = "Engine/Sources/Events/Resources/country_events.json"
        for (i, e) in load(cfile, &p)["events"].array.enumerated() {
            need(e, ["cc", "head", "text"], cfile, "country event number \(i + 1)", &p)
            if !codes.contains(e["cc"].string) { p.append("\(cfile): country event number \(i + 1) names the country \"\(e["cc"].string)\", which is not in countries.json") }
        }
        for k in load("Engine/Sources/Countries/Resources/city_market.json", &p)["countries"].object.keys where !codes.contains(k) { p.append("city_market.json: \"\(k)\" is not a country code in countries.json") }
        let traits: JSONValue = load("Engine/Sources/Countries/Resources/country_traits.json", &p)
        for k in traits["countries"].object.keys where !codes.contains(k) { p.append("country_traits.json: \"\(k)\" is not a country code in countries.json") }
        for k in traits["labour"].object.keys where !codes.contains(k) { p.append("country_traits.json: labour entry \"\(k)\" is not a country code in countries.json") }

        let sfile: String = "Engine/Sources/Businesses/Resources/supply_map.json"
        let supply: JSONValue = load(sfile, &p)
        let lines: [String: JSONValue] = supply["lines"].object
        let groups: Set<String> = Set(supply["groups"].array.map { (g: JSONValue) -> String in g.string })
        let order: [String] = supply["order"].array.map { (l: JSONValue) -> String in l.string }
        if Set(order) != Set(lines.keys) { p.append("\(sfile): order must list every line once") }
        for (id, l) in lines {
            if !groups.contains(l["group"].string) && !l["auto"].bool { p.append("\(sfile): line \"\(id)\" is in the group \"\(l["group"].string)\", which is not in groups") }
            for t in l["suppliers"].array where trades[t.string] == nil { p.append("\(sfile): line \"\(id)\" is supplied by \"\(t.string)\", which is not a trade id in trades.json") }
            if !["cogs", "oth", "mkt", "wages"].contains(l["category"].string) { p.append("\(sfile): line \"\(id)\" has an unknown category") }
        }
        for (k, needs) in supply["trades"].object {
            if trades[k] == nil { p.append("\(sfile): \"\(k)\" is not a trade id in trades.json") }
            for (line, e) in needs.object {
                if lines[line] == nil { p.append("\(sfile): \"\(k)\" needs the line \"\(line)\", which is not in lines") }
                for t in e["from"].array where trades[t.string] == nil { p.append("\(sfile): \"\(k)\" buys \"\(line)\" from \"\(t.string)\", which is not a trade id") }
            }
            if needs.object.values.filter({ (e: JSONValue) -> Bool in e["stock"].bool }).count > 1 { p.append("\(sfile): \"\(k)\" has more than one stock line") }
        }
        for k in trades.keys where supply["trades"][k].isNull { p.append("\(sfile): trade \"\(k)\" has no entry") }

        let lfile: String = "Engine/Sources/Businesses/Resources/logo_catalogue.json"
        for l in load(lfile, &p)["logos"].array {
            let label: String = "logo \"\(l["id"].string)\""
            need(l, ["id", "name", "how", "asset"], lfile, label, &p)
            let how: [String] = l["how"].string.split(separator: ":").map(String.init)
            let ok: Bool = l["how"].string == "free" || (how.count == 2 && how[0] == "level" && Int(how[1]) != nil) || (how.count == 2 && how[0] == "box" && Self.rarities.contains(how[1]))
                || (how.count == 2 && how[0] == "plan" && !how[1].isEmpty)
            if !ok { p.append("\(lfile): \(label) has how \"\(l["how"].string)\"; use free, level:N, plan:<perk> or box:common, box:rare, box:epic, box:legendary") }
        }
        finish(p)
    }

    private func uniqueIDsByCode(_ list: [JSONValue], _ problems: inout [String]) -> Set<String> {
        var seen: Set<String> = []
        for c in list where !seen.insert(c["code"].string).inserted { problems.append("countries.json: the code \"\(c["code"].string)\" is used twice") }
        return seen
    }
}
