import SwiftUI
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

/// The store manager's sheet: the five orders an owner gives (Direction, Budget, Headcount, Pay and bonus, Replace), then what the manager did
/// and how the business is doing; or, when the post is empty, the search and the shortlist.
struct ManagerSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @Binding var candidates: [Int]
    @State private var pending: PendingAction?
    @State private var page: ManagerPage = .orders
    @State private var tab: ManagerTab = .orders

    /// The sheet's pages: the orders, the one contract talk and the staffing plan replace the orders inside the same popup (never a popup on a popup).
    enum ManagerPage { case orders, pay, headcount }

    enum ManagerTab: String, CaseIterable, Hashable { case orders = "Orders", results = "Results" }

    var body: some View {
        switch page {
        case .orders:
            PeopleSheet(title: "Manager") {
                if let e = store.engine, let co = e.state.company(companyID) {
                    let cur = e.currency(for: co)
                    if let mid = co.managerID, let m = e.state.people[mid] { manage(e, co, m, cur) } else { hire(e, co, cur) }
                } else {
                    Text("This company no longer exists.").popupText(.body)
                }
            }
            .confirmAction($pending)
        case .pay:
            if let mid = store.engine?.state.company(companyID)?.managerID {
                subpage {
                    ContractDiscussionView(companyID: companyID, personID: mid, startTopic: nil)
                        .environment(\.popupClose, backToOrders)
                }
            } else {
                Color.clear.frame(width: 0, height: 0).onAppear { page = .orders }
            }
        case .headcount:
            subpage { StaffingPlanView(companyID: companyID) }
        }
    }

    private var backToOrders: () -> Void { { page = .orders } }

    private func subpage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button { Haptics.tap(); page = .orders } label: { Text("\u{2039} Manager") }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .accessibilityLabel("Back to the manager")
            content()
        }
    }

    // MARK: Managing the manager

    @ViewBuilder private func manage(_ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        let bd = e.tradeInfo(companyID: co.id)
        let started = co.value("mgrW0").isNull ? e.state.week : co.int("mgrW0")
        let months = max(0, e.state.week - started) / 4
        let notice = co.value("mgrNotice")
        let mgrRole: String = bd.map { ManagerModel.title($0) } ?? "Manager"
        let mgrNote: String = "\(co.name) \u{00B7} age \(m.age) \u{00B7} \(String(format: "%g", m.num("exp"))) years of experience \u{00B7} \(months) month\(months == 1 ? "" : "s") in the job"
        PersonCard(name: m.name, role: mgrRole, scope: "store", note: mgrNote, wage: cur.tidyShort(co.managerMonthlyWage), chevron: false, roleKey: "manager", face: m.faceKey)
        if !notice.isNull {
            TeamBlock("Leaving") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(firstName(m)) leaves on \(GameCalendar.dateString(week: notice["w"].int, dayOffset: 0)). Hire a successor before then and they will hand over.")
                        .popupText(.risk)
                    SuccessorSection(engine: e, company: co)
                }
            }
        }
        SegmentedPill(items: ManagerTab.allCases, title: { $0.rawValue }, selection: $tab)
        switch tab {
        case .orders:
            ordersList(e, co, m, cur)
        case .results:
            digest(e, co, m)
            performance(e, co, m)
        }
    }

    private func firstName(_ m: Person) -> String { m.name.split(separator: " ").first.map(String.init) ?? "The manager" }

    // MARK: The five orders

    @ViewBuilder private func ordersList(_ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        let orders: [ManagerModel.Order] = e.managerOrders(companyID: co.id)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(orders.enumerated()), id: \.element.id) { n, o in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(o.title).textStyle(.headline)
                        Spacer(minLength: Theme.Space.s)
                        Text(o.value.tidyMoney).textStyle(.body, tint: Theme.inkSoft).multilineTextAlignment(.trailing)
                    }
                    if o.key != .budget { Text(o.detail.tidyMoney).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true) }
                    control(o.key, e, co, m, cur)
                }
                .padding(.vertical, Theme.Space.m)
                .overlay(alignment: .top) { if n > 0 { Hairline() } }
                .accessibilityIdentifier("manager-order-" + o.key.rawValue)
            }
        }
    }

    @ViewBuilder private func control(_ key: ManagerModel.Order.Key, _ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        switch key {
        case .direction:
            directionPicker(co)
        case .budget:
            budgetPicker(co, m, cur)
        case .headcount:
            Button { Haptics.tap(); page = .headcount } label: { Text("Staffing plan\u{2026}") }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .accessibilityIdentifier("manager-headcount")
        case .pay:
            Button { Haptics.tap(); page = .pay } label: { Text("Talk about pay and bonus\u{2026}") }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .accessibilityIdentifier("manager-pay-talk")
        case .replace:
            replaceControl(e, co, m, cur)
        }
    }

    /// The direction names on the segments are short; the full meaning is the order's own line.
    private static func shortTitle(_ d: ManagerModel.Direction) -> String {
        switch d {
        case .grow: return "Grow"
        case .lean: return "Lean"
        case .quality: return "Quality"
        case .cash: return "Cash"
        }
    }

    private func directionPicker(_ co: Company) -> some View {
        let current: ManagerModel.Direction? = ManagerModel.direction(of: co)
        let items: [ManagerModel.Direction?] = ManagerModel.Direction.allCases.map { (d: ManagerModel.Direction) -> ManagerModel.Direction? in d }
        let cid: Int = co.id
        return SegmentedPill(items: items,
                             title: { (d: ManagerModel.Direction?) -> String in d.map { Self.shortTitle($0) } ?? "Steady" },
                             selection: Binding<ManagerModel.Direction?>(get: { current }, set: { (d: ManagerModel.Direction?) in
                                 guard let d else { return }
                                 store.settle(store.act { $0.setDirection(companyID: cid, direction: d) }, "Direction: \(d.title).", same: "That is the direction already.")
                             }),
                             identifier: { (d: ManagerModel.Direction?) -> String in "direction-" + (d?.rawValue ?? "none") })
    }

    private func budgetPicker(_ co: Company, _ m: Person, _ cur: Currency) -> some View {
        let b: Budget = ManagerModel.budget(of: co)
        let revenue: Double = ManagerModel.recentMonthlyRevenue(co)
        let cid: Int = co.id
        let name: String = firstName(m)
        return BudgetPicker(budget: b, name: name, detail: Self.budgetLine(b, name: name, cur: cur, revenue: revenue)) { (pick: Budget) in
            store.settle(store.act { $0.setManagerBudget(companyID: cid, budget: pick) }, "Budget: \(pick.title).", same: "That budget is set already.")
        }
    }

    /// What the budget means for this manager: the plain meaning and, where there is one, the money limits.
    private static func budgetLine(_ b: Budget, name: String, cur: Currency, revenue: Double) -> String {
        switch b {
        case .tight:
            return "\(name) \(b.text): every purchase, hire and raise comes to you."
        case .normal:
            return "\(name) \(b.text): up to \(cur.tidyShort(b.spendLimit(cur, monthlyRevenue: revenue))) for one purchase or hire and \(cur.tidyShort(b.payLimit(cur, monthlyRevenue: revenue))) a month in extra pay. Above that it comes to you."
        case .free:
            return "\(name) \(b.text): no purchase, hire or raise is too big to settle without asking."
        }
    }

    /// Replacing the manager: the consequence is stated in the confirmation; with co-owners it is a vote by shares.
    @ViewBuilder private func replaceControl(_ e: GameEngine, _ co: Company, _ m: Person, _ cur: Currency) -> some View {
        let alone: Bool = e.boardIsAdvisory(companyID: co.id)
        if alone {
            QuietButton(title: "Replace\u{2026}", tint: Theme.loss) {
                pending = PendingAction(title: "Dismiss \(m.name)?",
                                        message: "Notice and severance by the country's labour law are paid now. You run \(co.name) yourself until you hire someone new.",
                                        button: "Dismiss", destructive: true, tone: .danger, icon: "person.fill.xmark") {
                    let sev = store.act { $0.dismissManager(companyID: co.id) } ?? 0
                    store.show("\(m.name) has gone. Paid \(cur.tidyDisplay(sev)) in notice and severance. You run \(co.name) yourself again.", tone: "n"); Haptics.warning()
                }
            }
            .accessibilityIdentifier("manager-replace")
        } else {
            Text("Somebody else owns part of \(co.name), so replacing the manager is a vote by shares.").textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Propose it to the owners\u{2026}", tint: Theme.loss) {
                pending = PendingAction(title: "Put replacing \(m.name) to the vote?",
                                        message: "The co-owners vote by their shares. If it fails, \(m.name) learns you tried and you cannot ask again for eight weeks.",
                                        button: "Put it to the vote", tone: .warning, icon: "hand.raised") {
                    let r: ManagerModel.CEOChange? = store.act { $0.proposeCEOChange(companyID: co.id) }
                    switch r {
                    case .dismissed?: Haptics.warning(); store.show("\(m.name) has gone. You run \(co.name) yourself again.", tone: "n")
                    case .voteFailed(let p)?: Haptics.warning(); store.show("The co-owners voted it down: \(p)% of the shares were for it.", tone: "warn")
                    case .blocked(let w)?: store.show("You asked recently. Try again in \(w) \(w == 1 ? "week" : "weeks").", tone: "warn")
                    case .refused(let why)?: store.show(why, tone: "warn")
                    case nil: break
                    }
                }
            }
            .accessibilityIdentifier("manager-replace")
        }
    }

    // MARK: What they did, and the results

    /// The manager's own report, read only: what they settled on their own that is still to be reported, else the last report they sent.
    @ViewBuilder private func digest(_ e: GameEngine, _ co: Company, _ m: Person) -> some View {
        let fresh: [String] = co.value("mgrLog").array.map { (j: JSONValue) -> String in j["t"].string }
        let report: Message? = e.state.inbox.last(where: { (x: Message) -> Bool in x.companyID == co.id && x.title.hasSuffix(": what I did") })
        let reported: [String] = report.map { (r: Message) -> [String] in
            r.body.split(separator: "\n").map { String($0) }.filter { $0.hasPrefix("\u{2022}") }.map { String($0.dropFirst(2)) }
        } ?? []
        let lines: [String] = fresh.isEmpty ? reported : fresh
        let b: Budget = ManagerModel.budget(of: co)
        TeamBlock(title: "What they did this week", trailing: {
            if fresh.isEmpty, !reported.isEmpty, let report { Text("Reported " + GameCalendar.dateString(week: report.week, dayOffset: 0)).textStyle(.caption, tint: Theme.inkFaint) }
        }) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if lines.isEmpty {
                    Text(b.actsAlone ? "Nothing to report yet." : "On a tight budget \(firstName(m)) settles nothing alone, so there is nothing to report.")
                        .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(lines.prefix(6).enumerated()), id: \.offset) { _, line in
                        Text("\u{2022} " + line.tidyMoney).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private func performance(_ e: GameEngine, _ co: Company, _ m: Person) -> some View {
        let bd = e.tradeInfo(companyID: co.id)
        TeamBlock("Results") {
            VStack(alignment: .leading, spacing: 10) {
                if let vc = e.managerVoiceCard(companyID: co.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vc.traits).font(.caption).foregroundStyle(.secondary)
                        ForEach(vc.rows.indices, id: \.self) { i in
                            HStack { Text(vc.rows[i].label); Spacer(); Text(vc.rows[i].word.capitalized).foregroundStyle(.secondary) }.font(.subheadline)
                        }
                        Text("\u{201C}\(vc.verdict)\u{201D}").font(.subheadline.italic()).padding(.top, 4)
                    }
                }
                RateBar(label: "Overall results", fraction: e.managerQuality(companyID: co.id))
                if let card = e.managerScorecard(companyID: co.id) {
                    FigureCard(items: [
                        .init(label: "Scorecard", value: CompanyManagement.scoreWord(card.score).capitalized, tint: card.score < 35 ? Theme.loss : card.score >= 65 ? Theme.gain : Theme.ivory),
                        .init(label: "Margin, 3 months", value: String(format: "%.0f%%", card.margin * 100), tint: Theme.change(card.margin)),
                        .init(label: "Reputation", value: StandingWords.reputation(Double(card.reputation))),
                        .init(label: "Quality", value: StandingWords.reputation(Double(card.quality))),
                    ], columns: 4)
                    if card.paperworkGaps > 0 { Text("\(card.paperworkGaps.peopleText) with paperwork missing \(card.paperworkGaps == 1 ? "counts" : "count") against them.").popupText(.risk) }
                    if card.fraud > 0 { Text("Fraud was found under this manager.").popupText(.risk) }
                }
                if let bd, m.str("mtype") != bd.managerType { Text("Not the ideal type for this trade.").popupText(.risk) }
                Text("How well they do shows in the scorecard and in the results of the business.").popupText(.caption)
            }
        }
    }

    // MARK: Hiring a manager

    @ViewBuilder private func hire(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        let title = e.tradeInfo(companyID: co.id).map { ManagerModel.title($0) } ?? "Manager"
        let fee = ManagerModel.searchFee(currency: cur)
        VStack(alignment: .leading, spacing: 4) {
            Text("Hire a \(title.lowercased())").popupText(.figure)
            RoleScopeBadge(role: co.name, scope: "store")
        }
        Text("Runs \(co.name) day to day: hires, prices, stock, and keeps the team up. You give the direction and the budget and step back from the work. They are not cheap, and a manager nobody checks on slowly slips.")
            .popupText(.caption)
        Button(candidates.isEmpty ? "Executive search \u{00B7} \(cur.tidyShort(fee))" : "Search again \u{00B7} \(cur.tidyShort(fee))") {
            pending = PendingAction(title: "Pay for an executive search?",
                                    message: "Cost: \(cur.tidyShort(fee)), not refunded. Benefit: a shortlist you can interview and check. Risk: none may suit.",
                                    button: "Search for \(cur.tidyShort(fee))", amount: fee, currency: cur, tone: .info, icon: "magnifyingglass") {
                if let list = store.act({ $0.searchManagers(companyID: co.id) }) ?? nil { candidates = list.map { $0.id }; Haptics.tap(); store.show("\(list.count) candidates found. Search paid: \(cur.tidyShort(fee)).", tone: "n") }
                else { Haptics.warning(); store.show("Not enough cash for the search (\(cur.tidyShort(fee))).", tone: "warn") }
            }
        }.buttonStyle(TertiaryButtonStyle(size: .compact))
        let people = candidates.compactMap { e.state.people[$0] }.filter { $0.employerID == 0 }
        CandidateHireList(people: people, emptyText: candidates.isEmpty ? "Run a search to see candidates." : "Everyone on the shortlist has taken another job. Search again.") { p in
            let request = HireRequest(post: .manager, companyID: co.id, personID: p.id, roleTitle: title, onHired: { candidates = [] })
            CandidateHireRow(person: p, currency: cur, subtitle: CandidateClaims.line(e, p, extra: ManagerModel.typeTitles[p.str("mtype")] ?? "Manager"),
                             market: e.goingRate(for: .manager, companyID: co.id), request: request, roleKey: "manager") {
                ManagerCandidateChecks(person: p, companyID: co.id, currency: cur)
            }
        }
    }
}
