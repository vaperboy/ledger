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
                    HStack {
                        ForEach(CompanyRanking.Scope.allCases, id: \.self) { sc in
                            Button(scopeName(sc, e)) { scope = sc }.buttonStyle(QuietButtonStyle(tint: scope == sc ? Theme.gold : Theme.ivoryFaint))
                        }
                    }
                    HStack {
                        ForEach(CompanyRanking.Metric.allCases, id: \.self) { m in
                            Button(m.title) { metric = m }.buttonStyle(QuietButtonStyle(tint: metric == m ? Theme.gold : Theme.ivoryFaint))
                        }
                    }
                    if let you = board.you {
                        Text("You are number \(you.rank) of \(board.total) by \(metric.title.lowercased()).")
                            .font(.system(size: 14)).foregroundStyle(Theme.ivory)
                        LedgerSection("The biggest") {
                            VStack(spacing: 0) {
                                ForEach(Array(board.entries.prefix(20).enumerated()), id: \.offset) { i, en in
                                    if i > 0 { Hairline() }
                                    row(en, e)
                                }
                            }
                        }
                    } else {
                        Text("The ranking appears once you run a business.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Biggest companies")
            .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        if var e = store.engine {
            let img = e.worldImage()
            let people = e.peopleYouKnow()
            let favours = e.favours().filter { $0.status == .open }
            let infl = e.mapInfluence()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    LedgerSection("Seen as") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(img.label).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.gold)
                            Text(img.text.tidyMoney).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                            Text("Opens: " + img.opens).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                            Text("Risks: " + img.risks).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                            Hairline()
                            ForEach(img.groups) { g in
                                HStack { Text(g.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory); Spacer(); Text(g.word).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted) }
                            }
                        }
                    }
                    LedgerSection("People you know") {
                        if people.isEmpty {
                            Text("You know nobody in business yet. Open a company and people will find you.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(people.enumerated()), id: \.element.id) { i, c in
                                    if i > 0 { Hairline() }
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(c.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
                                            Text(c.role.rawValue + " · " + c.organisation).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                        }
                                        Spacer(minLength: 8)
                                        if c.relationship >= 64 {
                                            Button("Ask a favour") {
                                                let r = store.act { $0.askForFavour(contactID: c.id) }
                                                if case .refused(let why)? = r { store.show(why, tone: "warn") } else if case .ok(let msg)? = r { store.show(msg, tone: "good") }
                                            }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                                        }
                                        Text(c.word).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                                    }.padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    if !favours.isEmpty {
                        LedgerSection("Favours and promises") {
                            VStack(spacing: 0) {
                                ForEach(Array(favours.enumerated()), id: \.element.id) { i, f in
                                    if i > 0 { Hairline() }
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(f.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
                                            Text((f.kind == .owed ? "Owes you: " : f.kind == .promise ? "You promised: " : "You owe them: ") + f.text).font(.caption).foregroundStyle(Theme.ivoryFaint)
                                        }
                                        Spacer(minLength: 8)
                                        if f.kind != .owe {
                                            Button(f.kind == .owed ? "Call in" : "Keep it") {
                                                let r = store.act { f.kind == .owed ? $0.callInFavour(favourID: f.id) : $0.keepPromise(favourID: f.id) }
                                                if case .refused(let why)? = r { store.show(why, tone: "warn") } else if case .ok(let msg)? = r { store.show(msg, tone: "good") }
                                            }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                                        }
                                    }.padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    LedgerSection("What you own") {
                        VStack(spacing: 0) {
                            ForEach(Array(e.mapOwnership().enumerated()), id: \.element.id) { i, n in
                                if i > 0 { Hairline() }
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
                    LedgerSection("Where you are") {
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
                    LedgerSection("Circles of influence") {
                        VStack(alignment: .leading, spacing: 6) {
                            circle("Inside", infl.inner)
                            circle("Allies", infl.allies)
                            circle("Rivals and the wary", infl.others)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("World around you")
            .navigationBarTitleDisplayMode(.inline)
        }
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
            LedgerSection("Data analyst") {
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
