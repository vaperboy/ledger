import SwiftUI
import GameCore
import Businesses
import Simulation

/// The biggest companies, by sales, profit, value or growth: you, the rival groups and the rivals you face, among everyone in the
/// business register. Original: R27.rankings (features/world/rival_groups.js).
struct RankingView: View {
    @EnvironmentObject var store: GameStore
    @State private var scope: CompanyRanking.Scope = .country
    @State private var metric: CompanyRanking.Metric = .revenue

    var body: some View {
        if let e = store.engine {
            let board = e.rankingBoard(scope: scope, metric: metric)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if let you = board.you {
                        HeroFigure(label: "Your place by \(metric.title.lowercased())", value: "#\(you.rank) of \(board.total)", tint: Theme.gold)
                    }
                    SegmentedPill(items: CompanyRanking.Scope.allCases, title: { scopeName($0, e) }, selection: $scope)
                    SegmentedPill(items: CompanyRanking.Metric.allCases, title: { $0.title }, selection: $metric)
                    if board.you != nil {
                        CardSection("The biggest") {
                            VStack(spacing: 0) {
                                ForEach(Array(board.entries.prefix(20).enumerated()), id: \.offset) { i, en in
                                    if i > 0 { CardLine() }
                                    row(en, e)
                                }
                            }
                        }
                    } else {
                        NoteCard(text: "The ranking is locked until you run a business. Open or buy a company and you appear here.", glyph: Glyph.richList)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
        }
    }

    private func scopeName(_ sc: CompanyRanking.Scope, _ e: GameEngine) -> String {
        switch sc { case .industries: return "Your trades"; case .country: return e.homeCountry.name; case .world: return "World" }
    }

    private func figure(_ en: CompanyRanking.Entry) -> String {
        metric == .growth ? String(format: "%+d%%", Int((en.growth * 100).rounded())) : store.short(en.figure(metric))
    }

    private func row(_ en: CompanyRanking.Entry, _ e: GameEngine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text("\(en.rank)").font(.caption.monospacedDigit()).foregroundStyle(en.isYou ? Theme.gold : Theme.ivoryFaint).frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(en.name + (en.isYou ? " (you)" : "")).font(.system(size: 14.5)).foregroundStyle(en.isYou ? Theme.gold : Theme.ivory)
                Text(en.isYou ? "\(en.companyCount) \(en.companyCount == 1 ? "company" : "companies")"
                     : en.rivalID != nil ? "Your rival" : "\(en.companyCount) sites")
                    .font(.caption).foregroundStyle(Theme.ivoryFaint)
            }
            Spacer(minLength: 8)
            Text(en.movement > 0 ? "▲" : en.movement < 0 ? "▼" : "").font(.caption).foregroundStyle(en.movement > 0 ? Theme.gain : Theme.loss)
            Text(figure(en)).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(Theme.ivory)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// How people see you, the people you know with favours and promises, and the maps. Original: features/world/world_around_you.js.
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
                    CardSection("Records") {
                        VStack(spacing: 0) {
                            recordLink(.rival, e.nemesis.map { "\($0.owner) of \($0.groupName): you \($0.wins), them \($0.losses)" } ?? "No rival has picked you yet")
                            CardLine()
                            recordLink(.topFifty, e.topFifty.map { t in t.yourRank.map { "Last January: you were number \($0) of \(t.of)" } ?? "Last January you were not on it" } ?? "Printed every January")
                            CardLine()
                            recordLink(.months, "Income, costs and profit by month, per company")
                            CardLine()
                            recordLink(.crisis, "\(e.crisisCentre.filter { $0.status == "open" }.count) waiting")
                            CardLine()
                            recordLink(.hall, e.retirementHall.isEmpty ? "Nobody has retired yet" : "\(e.retirementHall.count) retired")
                            CardLine()
                            NavigationLink {
                                NewsView().appScreen(title: "Business paper and weather", subtitle: PhoneApp.news.subtitle)
                            } label: {
                                RowLine(glyph: Glyph.news, tint: Theme.gold, title: "Business paper and weather", subtitle: "Front pages, forecasts and visitors", chevron: true)
                            }.buttonStyle(.plain)
                        }
                    }
                    CardSection("Seen as") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(img.label).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.gold)
                            Text(img.text.tidyMoney).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                            Text("Opens: " + img.opens).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                            Text("Risks: " + img.risks).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                            CardLine()
                            ForEach(img.groups) { g in
                                HStack { Text(g.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory); Spacer(); Text(g.word).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted) }
                            }
                        }
                    }
                    CardSection("People you know") {
                        if people.isEmpty {
                            Text("You know nobody in business yet. Open a company and people will find you.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(people.enumerated()), id: \.element.id) { i, c in
                                    if i > 0 { CardLine() }
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(c.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
                                            Text(c.role.rawValue + " · " + c.organisation).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                        }
                                        Spacer(minLength: 8)
                                        if c.relationship >= 64 {
                                            Button("Ask a favour") {
                                                report(store.act { $0.askForFavour(contactID: c.id) })
                                            }.buttonStyle(QuietButtonStyle(tint: Theme.gold)).accessibilityLabel("Ask \(c.name) for a favour")
                                        }
                                        Text(c.word).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
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
                                            Text(f.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
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
                                        Text(n.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
                                        Text(n.trade + (n.ownership < 100 ? " · you own \(Int(n.ownership.rounded()))%" : "")).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                    }
                                    Spacer()
                                    Text(store.short(n.value)).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                                }.padding(.leading, CGFloat((n.depth - 1) * 18)).padding(.vertical, 8)
                            }
                        }
                    }
                    CardSection("Where you are") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(e.mapPresence()) { p in
                                Text(p.flag + " " + p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ivory)
                                ForEach(p.cities.filter { $0.companies > 0 }) { c in
                                    HStack { Text(c.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory); Spacer()
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
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
        }
    }

    private func recordLink(_ page: WorldRecordsView.Page, _ preview: String) -> some View {
        NavigationLink {
            WorldRecordsView(page: page).appScreen(title: page.rawValue, subtitle: "Records of the world around you")
        } label: {
            RowLine(glyph: page.glyph, tint: Theme.gold, title: page.rawValue, subtitle: preview, chevron: true)
        }.buttonStyle(.plain)
    }

    private func circle(_ title: String, _ names: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
            Spacer()
            Text(names.isEmpty ? "None yet" : names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : ""))
                .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.trailing)
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
                        Text("Your data analyst puts ranges on market shares, rivals and price forecasts.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
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
                        Text("Without an analyst you only have your own guess. A data analyst in your head office gives ranges, sharper with experience.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                        if candidates.isEmpty {
                            Button("Find a data analyst") { candidates = store.act { $0.dataAnalystCandidates() } ?? [] }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                        }
                        if !candidates.isEmpty {
                            CandidateHireList(people: candidates, emptyText: "") { p in
                                CandidateHireRow(person: p, currency: e.homeCurrency, subtitle: "Says \(Int(p.claimedSkill.rounded())) skill · age \(p.age)",
                                                 market: e.goingRate(for: .analyst), factors: [0.9, 1.0, 1.15, 1.3]) { wage in
                                    let feedback = HireFeedback.from(store.act { $0.hireDataAnalyst(personID: p.id, monthlyWage: wage) }, name: p.name)
                                    if feedback.isHired { candidates = []; store.show(feedback.text, tone: "good") }
                                    return feedback
                                }
                            }
                        }
                    }
                }
            }
            .confirmAction($pending)
        }
    }
}
