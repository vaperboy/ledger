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
                if chainID == nil, !engine.groupManagingDirector.isNull {
                    let big = engine.state.rest["group"]?["big"].double ?? 0
                    Hairline()
                    Menu("Deals above \(big > 0 ? cur.tidyShort(big) : "any size") always come to you") {
                        ForEach([0.0, 250_000, 1_000_000, 5_000_000, 20_000_000], id: \.self) { v in
                            let amt = cur.scaledPrice(v)
                            Button(v == 0 ? "No limit set" : cur.tidyShort(amt)) { store.settle(store.act { $0.setGroupLimit(v == 0 ? 0 : amt) }, v == 0 ? "No group limit." : "Deals above \(cur.tidyShort(amt)) come to you.", same: "That limit is already set.") }
                        }
                    }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).padding(.top, 8)
                }
            }
        }
        .confirmationDialog("Let \(releasing?.level.title.lowercased() ?? "them") go?", isPresented: Binding(get: { releasing != nil }, set: { if !$0 { releasing = nil } }), titleVisibility: .visible) {
            Button("Let go", role: .destructive) {
                if let r = releasing { let ok = store.act { $0.releaseExecutive(r.level, chainID: chainID, regionalID: r.regionalID) } ?? false; Haptics.warning(); store.show(ok ? "Let go. Severance is paid." : "They had already left.", tone: ok ? "n" : "warn") }
                releasing = nil
            }
        } message: { Text("Severance of about a month's pay plus costs is paid now.") }
    }

    /// The entity that employs these people: the chain for chain levels, otherwise the group office (or the holding that carries it).
    private var employer: String {
        guard let cid = chainID else { return engine.groupOfficeEmployer }
        let name = engine.state.rest["chains"]?.array.first { $0["id"].int == cid }?["name"].string ?? ""
        return name.isEmpty ? "your chain" : name
    }

    private func cityLabel(_ id: String) -> String { engine.state.companies.first { $0.cityID == id }.map { engine.cityName($0) } ?? id }

    @ViewBuilder private func row(_ p: Post, _ cur: Currency) -> some View {
        let person = p.rec.isNull ? nil : engine.state.people[p.rec["npc"].int]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(person?.name ?? "Vacant").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        RoleScopeBadge(role: p.level == .md ? "Group managing director" : p.level.title, scope: p.scope)
                    }
                    Text((person == nil ? "Would be employed by " : "Employed by ") + employer).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    if person == nil { Text(p.level.text.tidyMoney).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                if person != nil { Text(cur.tidyShort(p.rec["wage"].double)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory) }
            }
            if person != nil {
                let lvl = Int(p.rec["lvl"].double)
                HStack(spacing: 16) {
                    AuthorityPicker(level: lvl, currency: cur, limit: p.rec["buy"].double,
                                    limitSteps: [50000.0, 100000, 250000, 600000, 2000000].map { cur.scaledPrice($0) },
                                    setLevel: { l in store.act { $0.setExecutiveAuthority(p.level, chainID: chainID, regionalID: p.regionalID, authority: l) } },
                                    setLimit: { v in store.act { $0.setExecutiveAuthority(p.level, chainID: chainID, regionalID: p.regionalID, buy: v) } })
                    Spacer(minLength: 0)
                    Button("Let go") { releasing = p }.foregroundStyle(Theme.loss)
                }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
            } else {
                searchButton(p, cur)
            }
        }.padding(.vertical, 8)
    }

    @ViewBuilder private func searchButton(_ p: Post, _ cur: Currency) -> some View {
        Button("Executive search · \(cur.tidyShort(ManagerModel.searchFee(currency: cur)))") {
            if let list = store.act({ $0.searchExecutive(p.level) }) ?? nil { searching = p.id; candidates = list.map { $0.id }; Haptics.tap() }
            else { store.show("Not enough cash for the search.", tone: "warn") }
        }.buttonStyle(QuietButtonStyle())
        if searching == p.id { candidateList(p, cur) }
    }

    @ViewBuilder private func candidateList(_ p: Post, _ cur: Currency) -> some View {
        CandidateHireList(people: candidates.compactMap { engine.state.people[$0] }, emptyText: "Everyone on the shortlist has taken another job. Search again.") { c in
            CandidateHireRow(person: c, currency: cur, market: engine.goingRate(for: .executive(p.level)), factors: [0.9, 1.0, 1.15, 1.3]) { wage in hire(p, c, wage) }
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

    /// The engine's answer, in the words every hiring screen uses; the shared row shows it under the candidate.
    private func hire(_ p: Post, _ c: Person, _ wage: Double) -> HireFeedback {
        let city = p.city ?? regionCity
        let r = store.act { $0.hireExecutive(p.level, personID: c.id, monthlyWage: wage, chainID: chainID, city: city) }
        let feedback = HireFeedback.from(r, name: c.name, role: p.level.title)
        if feedback.isHired { candidates = []; searching = nil; regionCity = nil }
        store.show(feedback.text, tone: feedback.isHired ? "good" : "warn")
        return feedback
    }
}
