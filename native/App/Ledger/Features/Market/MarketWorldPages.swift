import SwiftUI
import GameCore
import Businesses
import Simulation

/// The biggest companies, by sales, profit, value or growth: you, the rival groups and the rivals you face, among everyone in the
/// business register. Part of Market > World > Rankings. Original: R27.rankings (features/world/rival_groups.js).
struct CompanyRankingSection: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @State private var scope: CompanyRanking.Scope = .country
    @State private var metric: CompanyRanking.Metric = .revenue

    var body: some View {
        if let e = store.engine {
            let board = e.rankingBoard(scope: scope, metric: metric)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SegmentedPill(items: CompanyRanking.Scope.allCases, title: { scopeName($0, e) }, selection: $scope,
                              identifier: { (s: CompanyRanking.Scope) -> String in "ranking-scope-\(s.rawValue)" })
                SegmentedPill(items: CompanyRanking.Metric.allCases, title: { $0.title }, selection: $metric,
                              identifier: { (m: CompanyRanking.Metric) -> String in "ranking-metric-\(m.rawValue)" })
                if let you = board.you {
                    Text("You are #\(you.rank) of \(board.total) by \(metric.title.lowercased())").textStyle(.body, tint: P.accent, numeric: true)
                    VStack(spacing: 0) {
                        ForEach(Array(board.entries.prefix(20).enumerated()), id: \.offset) { i, en in
                            if i > 0 { Hairline().padding(.leading, 38 + Theme.Space.m) }
                            row(en, e)
                        }
                    }
                } else {
                    EmptyState(glyph: Glyph.richList, title: "Not ranked yet", message: "Open or buy a company and you appear here.", centered: false)
                }
            }
        }
    }

    private func scopeName(_ sc: CompanyRanking.Scope, _ e: GameEngine) -> String {
        switch sc { case .industries: return "Your trades"; case .country: return e.homeCountry.name; case .world: return "World" }
    }

    /// The firm key a logo is drawn for: the rival group, the named rival you face, or the entry itself; you get none (initials).
    private func logoKey(_ en: CompanyRanking.Entry) -> String {
        if en.isYou { return "" }
        if let g = en.groupID { return "group|\(g)" }
        if let c = en.rivalCompanyID, let r = en.rivalID { return "rival|co\(c)|\(r)" }
        return "firm|\(en.id)"
    }

    private func figure(_ en: CompanyRanking.Entry) -> String {
        metric == .growth ? String(format: "%+d%%", Int((en.growth * 100).rounded())) : store.short(en.figure(metric))
    }

    private func row(_ en: CompanyRanking.Entry, _ e: GameEngine) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            Text("\(en.rank)").textStyle(.headline, tint: en.isYou ? P.accent : P.inkFaint, numeric: true).frame(width: 38, alignment: .leading)
            ThumbnailView(kind: .logo, key: logoKey(en), size: 32, shape: .square, glyph: Glyph.group, initials: en.name)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(en.name + (en.isYou ? " (you)" : "")).textStyle(.headline, tint: en.isYou ? P.accent : nil).lineLimit(1)
                Text(en.isYou ? "\(en.companyCount) \(en.companyCount == 1 ? "company" : "companies")"
                     : en.rivalID != nil ? "Your rival" : "\(en.companyCount) sites").textStyle(.caption).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text(figure(en)).textStyle(.headline, numeric: true)
                if en.movement != 0 {
                    Text(en.movement > 0 ? "\u{2191} \(en.movement)" : "\u{2193} \(-en.movement)").textStyle(.caption, tint: en.movement > 0 ? P.gain : P.loss, numeric: true)
                }
            }
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
    }
}

/// How people see you, the people you know with favours and promises, what you own and where (Market > World > People and reputation).
/// Original: features/world/world_around_you.js.
struct WorldAroundView: View {
    @EnvironmentObject var store: GameStore
    /// Tells the player what the engine answered; a nil result (no game) says so rather than staying silent.
    private func report(_ r: WorldAround.ActionResult?) {
        switch r {
        case .ok(let msg)?: Haptics.success(); store.show(msg, tone: "good")
        case .refused(let why)?: Haptics.warning(); store.show(why, tone: "warn")
        case nil: store.show("No game is open.", tone: "warn")
        }
    }

    var body: some View {
        if var e = store.engine {
            let img = e.worldImage()
            let people = e.peopleYouKnow()
            let favours = e.favours().filter { $0.status == .open }
            let infl = e.mapInfluence()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    CardSection("Seen as") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(img.label).textStyle(.headline, tint: Theme.accent, weight: .semibold)
                            Text(img.text.tidyMoney).textStyle(.body, tint: Theme.inkSoft)
                            Text("Opens: " + img.opens).textStyle(.caption, tint: Theme.inkFaint)
                            Text("Risks: " + img.risks).textStyle(.caption, tint: Theme.inkFaint)
                            CardLine()
                            ForEach(img.groups) { g in
                                HStack { Text(g.name).textStyle(.body); Spacer(); Text(g.word).textStyle(.body, tint: Theme.inkSoft) }
                            }
                        }
                    }
                    CardSection("People you know") {
                        if people.isEmpty {
                            Text("You know nobody in business yet. Open a company and people will find you.").textStyle(.body, tint: Theme.inkSoft)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(people.enumerated()), id: \.element.id) { i, c in
                                    if i > 0 { CardLine() }
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(c.name).textStyle(.body)
                                            Text(c.role.rawValue + " · " + c.organisation).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                        }
                                        Spacer(minLength: 8)
                                        if c.relationship >= 64 {
                                            Button("Ask a favour") {
                                                report(store.act { $0.askForFavour(contactID: c.id) })
                                            }.buttonStyle(QuietButtonStyle(tint: Theme.gold)).accessibilityLabel("Ask \(c.name) for a favour")
                                        }
                                        Text(c.word).textStyle(.caption)
                                    }.padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    if !favours.isEmpty {
                        CardSection("Favours and promises") {
                            VStack(spacing: 0) {
                                ForEach(Array(favours.enumerated()), id: \.element.id) { i, f in
                                    if i > 0 { CardLine() }
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(f.name).textStyle(.body)
                                            Text((f.kind == .owed ? "Owes you: " : f.kind == .promise ? "You promised: " : "You owe them: ") + f.text).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                        }
                                        Spacer(minLength: 8)
                                        if f.kind != .owe {
                                            Button(f.kind == .owed ? "Call in" : "Keep it") {
                                                let calling = f.kind == .owed
                                                report(store.act { calling ? $0.callInFavour(favourID: f.id) : $0.keepPromise(favourID: f.id) })
                                            }.buttonStyle(QuietButtonStyle(tint: Theme.gold)).accessibilityLabel((f.kind == .owed ? "Call in the favour from " : "Keep your promise to ") + f.name)
                                        }
                                    }.padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    CardSection("What you own") {
                        VStack(spacing: 0) {
                            ForEach(Array(e.mapOwnership().enumerated()), id: \.element.id) { i, n in
                                if i > 0 { CardLine() }
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(n.name).textStyle(.body)
                                        Text(n.trade + (n.ownership < 100 ? " · you own \(Int(n.ownership.rounded()))%" : "")).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                    }
                                    Spacer()
                                    Text(store.short(n.value)).textStyle(.body, tint: Theme.inkSoft, numeric: true)
                                }.padding(.leading, CGFloat((n.depth - 1) * 18)).padding(.vertical, 8)
                            }
                        }
                    }
                    CardSection("Where you are") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(e.mapPresence()) { p in
                                Text(p.flag + " " + p.name).textStyle(.body, weight: .semibold)
                                ForEach(p.cities.filter { $0.companies > 0 }) { c in
                                    HStack { Text(c.name).textStyle(.body); Spacer()
                                        Text("\(c.companies) · " + c.trades.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.ivoryFaint) }
                                }
                            }
                        }
                    }
                    CardSection("Circles of influence") {
                        VStack(alignment: .leading, spacing: 6) {
                            circle("Inside", infl.inner)
                            circle("Allies", infl.allies)
                            circle("Rivals and the wary", infl.others)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
        }
    }

    private func circle(_ title: String, _ names: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).textStyle(.body)
            Spacer()
            Text(names.isEmpty ? "None yet" : names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : ""))
                .textStyle(.caption).multilineTextAlignment(.trailing)
        }
    }
}

/// The head office's data analyst: with one, market shares and forecasts come as ranges instead of a feeling.
struct DataAnalystCard: View {
    @EnvironmentObject var store: GameStore
    @State private var candidates: [Person] = []
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine {
            CardSection("Data analyst") {
                VStack(alignment: .leading, spacing: 8) {
                    if e.hasDataAnalyst {
                        Text("Your data analyst puts ranges on market shares, rivals and price forecasts.").textStyle(.caption)
                        HStack {
                            Button("Report on all companies") {
                                let r = store.act { $0.orderAnalystReport(companyID: nil) }
                                if case .refused(let why)? = r { store.show(why, tone: "warn") } else { store.show("Report sent to your inbox."); Haptics.success() }
                            }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                            Button("Let them go") {
                                pending = PendingAction(title: "Let your data analyst go?", message: "Market shares, rivals and forecasts go back to guesses until you hire another. Their desk in the main office is freed.", button: "Let go", destructive: true) {
                                    if store.act({ $0.fireDataAnalyst() }) == true { Haptics.warning(); store.show("Your data analyst has left.", tone: "n") }
                                    else { store.show("You have no data analyst.", tone: "warn") }
                                }
                            }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                        }
                    } else {
                        Text("Without an analyst you only have your own guess. A data analyst in your head office gives ranges, sharper with experience.").textStyle(.caption)
                        if candidates.isEmpty {
                            Button("Find a data analyst") { candidates = store.act { $0.dataAnalystCandidates() } ?? [] }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                        }
                        if !candidates.isEmpty {
                            CandidateHireList(people: candidates, emptyText: "") { p in
                                let request = HireRequest(post: .analyst, companyID: nil, personID: p.id, roleTitle: "Data analyst", onHired: { candidates = [] })
                                CandidateHireRow(person: p, currency: e.homeCurrency, subtitle: CandidateClaims.line(e, p), market: e.goingRate(for: .analyst), request: request)
                            }
                        }
                    }
                }
            }
            .confirmAction($pending)
        }
    }
}
