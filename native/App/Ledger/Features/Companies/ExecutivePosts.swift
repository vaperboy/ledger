import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Chain and group level management posts (group managing director, chain CEO, chain manager, regional managers), shown from Group and
/// from a company's Chain section. Same people, same rules as the Team list on a company: role + scope badge, search, hire, authority, let go.
/// `chainID == nil` is the group level. Pay comes from the chain's stores (chain levels) or from you (group level), as the engine decides.
struct ExecutivePosts: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var chainID: Int?
    @State private var searching: String?
    @State private var candidates: [Int] = []
    @State private var releasing: Post?

    struct Post: Identifiable {
        var id: String
        var level: ManagerModel.ExecLevel
        var scope: String
        var city: String?
        var regionalID: Int?
        var rec: JSONValue
    }

    private var posts: [Post] {
        guard let cid = chainID else {
            return [Post(id: "md", level: .md, scope: "group", city: nil, regionalID: nil, rec: engine.groupManagingDirector)]
        }
        let ch = engine.state.rest["chains"]?.array.first { $0["id"].int == cid } ?? .null
        var out = [Post(id: "ceo", level: .ceo56, scope: "chain", city: nil, regionalID: nil, rec: ch["ceo56"])]
        let regs = engine.regionalManagers
        let mgr = regs.first { $0["scope"].string == "chain:\(cid)" }
        out.append(Post(id: "cm", level: .chainmgr, scope: "chain", city: nil, regionalID: mgr?["id"].int, rec: mgr ?? .null))
        let cities = Set(engine.state.companies.filter { $0.status.isLive && !$0.value("chain").isNull && $0.value("chain").int == cid }.map { $0.cityID })
        for city in cities.sorted() {
            let r = regs.first { $0["scope"].string == "chain:\(cid):\(city)" }
            if let r { out.append(Post(id: "rg\(city)", level: .region, scope: "region · \(cityLabel(city))", city: city, regionalID: r["id"].int, rec: r)) }
        }
        return out
    }

    var body: some View {
        let cur = engine.homeCurrency
        let list = posts
        LedgerSection(chainID == nil ? "Group management" : "Chain management") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, p in
                    if n > 0 { Hairline() }
                    row(p, cur)
                }
                if chainID != nil { addRegional(cur) }
            }
        }
        .confirmationDialog("Let \(releasing?.level.title.lowercased() ?? "them") go?", isPresented: Binding(get: { releasing != nil }, set: { if !$0 { releasing = nil } }), titleVisibility: .visible) {
            Button("Let go", role: .destructive) {
                if let r = releasing { let ok = store.act { $0.releaseExecutive(r.level, chainID: chainID, regionalID: r.regionalID) } ?? false; Haptics.warning(); store.show(ok ? "Let go. Severance is paid." : "They had already left.", tone: ok ? "n" : "warn") }
                releasing = nil
            }
        } message: { Text("Severance of about a month's pay plus costs is paid now.") }
    }

    private func cityLabel(_ id: String) -> String { engine.state.companies.first { $0.cityID == id }.map { engine.cityName($0) } ?? id }

    @ViewBuilder private func row(_ p: Post, _ cur: Currency) -> some View {
        let person = p.rec.isNull ? nil : engine.state.people[p.rec["npc"].int]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(person?.name ?? "Vacant").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        Chip(text: "\(p.level.title) · \(p.scope)", tint: Theme.gold)
                    }
                    if person == nil { Text(p.level.text).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                if person != nil { Text(cur.short(p.rec["wage"].double)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory) }
            }
            if person != nil {
                let lvl = Int(p.rec["lvl"].double)
                HStack(spacing: 16) {
                    Menu(["Asks you", "Within limit", "Full control"][min(2, max(0, lvl))]) {
                        ForEach(0..<3, id: \.self) { l in Button(["Asks you", "Within limit", "Full control"][l]) { store.act { $0.setExecutiveAuthority(p.level, chainID: chainID, regionalID: p.regionalID, authority: l) } } }
                    }
                    if lvl == 1 {
                        Menu("Spend up to \(cur.short(p.rec["buy"].double))") {
                            ForEach([50000.0, 100000, 250000, 600000, 2000000], id: \.self) { v in Button(cur.short(cur.scaledPrice(v))) { store.act { $0.setExecutiveAuthority(p.level, chainID: chainID, regionalID: p.regionalID, buy: cur.scaledPrice(v)) } } }
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Let go") { releasing = p }.foregroundStyle(Theme.loss)
                }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
            } else {
                searchButton(p, cur)
            }
        }.padding(.vertical, 8)
    }

    @ViewBuilder private func searchButton(_ p: Post, _ cur: Currency) -> some View {
        Button("Executive search · \(cur.short(cur.scaledPrice(15000)))") {
            if let list = store.act({ $0.searchExecutive(p.level) }) ?? nil { searching = p.id; candidates = list.map { $0.id }; Haptics.tap() }
            else { store.show("Not enough cash for the search.", tone: "warn") }
        }.buttonStyle(QuietButtonStyle())
        if searching == p.id { candidateList(p, cur) }
    }

    @ViewBuilder private func candidateList(_ p: Post, _ cur: Currency) -> some View {
        ForEach(candidates, id: \.self) { id in
            if let c = engine.state.people[id] {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text("Age \(c.age) · \(String(format: "%g", c.num("exp"))) yr · \(c.str("resume"))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer(minLength: 8)
                    Menu("\(cur.short(c.askingMonthlyWage)) / mo") {
                        ForEach([1.0, 1.1], id: \.self) { f in
                            Button("Offer \(cur.short(cur.roundedStep(c.askingMonthlyWage * f, about: 500)))") { hire(p, c, cur.roundedStep(c.askingMonthlyWage * f, about: 500)) }
                        }
                    }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                }
            }
        }
    }

    /// A regional manager for a city where the chain has stores and none yet.
    @ViewBuilder private func addRegional(_ cur: Currency) -> some View {
        if let cid = chainID {
            let have = Set(engine.regionalManagers.compactMap { r -> String? in
                let parts = r["scope"].string.split(separator: ":").map(String.init)
                return parts.count == 3 && parts[1] == String(cid) ? parts[2] : nil
            })
            let open = Set(engine.state.companies.filter { $0.status.isLive && !$0.value("chain").isNull && $0.value("chain").int == cid }.map { $0.cityID }).subtracting(have).sorted()
            if !open.isEmpty {
                Hairline()
                Menu("Add a regional manager…") {
                    ForEach(open, id: \.self) { city in
                        Button(cityLabel(city)) { regionCity = city; startRegionSearch(cur) }
                    }
                }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).padding(.top, 8)
                if let city = regionCity, searching == "rg\(city)" {
                    candidateList(Post(id: "rg\(city)", level: .region, scope: "region", city: city, regionalID: nil, rec: .null), cur)
                }
            }
        }
    }

    @State private var regionCity: String?
    private func startRegionSearch(_ cur: Currency) {
        guard let city = regionCity else { return }
        if let list = store.act({ $0.searchExecutive(.region) }) ?? nil { searching = "rg\(city)"; candidates = list.map { $0.id }; Haptics.tap() }
        else { store.show("Not enough cash for the search.", tone: "warn") }
    }

    private func hire(_ p: Post, _ c: Person, _ wage: Double) {
        let city = p.city ?? regionCity
        switch store.act({ $0.hireExecutive(p.level, personID: c.id, monthlyWage: wage, chainID: chainID, city: city) }) {
        case .ok?: Haptics.success(); candidates = []; searching = nil; regionCity = nil; store.show("\(c.name) starts as \(p.level.title.lowercased()).", tone: "good")
        case .refused?: store.show("\(c.name) found that a bit low.", tone: "warn")
        default: store.show("They took another job.", tone: "warn")
        }
    }
}
