import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// Hire workers: the hero is who is waiting (and what search is running); the people who answered come first, in the same `ApplicantRow`
/// as the Applicants page; then the role and how to look (a job ad or an agency), with the one action pinned at the bottom.
/// Applicants arrive over time as inbox messages. "Talk terms" pushes `HireOnePage`. Fees, applicants and what happens are the engine's
/// (`jobAdFee`, `postJobAd`, `agencyFee`, `engageAgency`, `applicants`).
struct HireWorkersView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    /// The role to start on, when a link asks for one.
    var startRole: String? = nil
    @State private var roleID = ""
    @State private var custom = ""
    @State private var method = Method.ad
    @State private var pending: PendingAction?
    @State private var talk: WorkerRef?
    @State private var openID: Int?

    enum Method: String, CaseIterable, Hashable { case ad = "Job ad", agency = "Agency" }

    private struct RunLine: Identifiable { var id: String; var text: String }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            screen(e, co)
        } else {
            EmptyState(title: "This company is not available.").appScreen(title: "Hire", tab: store.tab)
        }
    }

    // MARK: Role

    private func chosenRole(_ roles: [RoleOption]) -> (id: String, name: String)? {
        let typed: String = custom.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return (typed, typed) }
        let pick: String = roleID.isEmpty ? (startRole ?? "") : roleID
        if let r = roles.first(where: { (o: RoleOption) -> Bool in o.id == pick }) { return (r.id, r.name) }
        return nil
    }

    private func screen(_ e: GameEngine, _ co: Company) -> some View {
        let roles: [RoleOption] = e.recommendedRoles(companyID: companyID)
        let chosen: (id: String, name: String)? = chosenRole(roles)
        let cur: Currency = e.currency(for: co)
        let waiting: [Applicant] = e.applicants(companyID: companyID)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                hero(e, co, waiting.count, role: chosen?.id)
                if !waiting.isEmpty { applicantsSection(e, co, cur, roles, waiting) }
                roleSection(roles)
                searchSection(e, cur)
                if waiting.isEmpty {
                    Button("Applicants of all companies") { Haptics.tap(); store.openApplicants(companyID: nil, role: nil) }
                        .buttonStyle(TertiaryButtonStyle(size: .compact)).padding(.leading, -Theme.Space.s)
                }
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(e, co, cur, chosen) }
        .confirmAction($pending)
        .navigationDestination(item: $talk) { (w: WorkerRef) -> HireOnePageHost in HireOnePageHost(companyID: companyID, personID: w.id) }
        .appScreen(title: "Hire workers", subtitle: co.name, tab: store.tab)
    }

    /// The hiring state as the hero: how many people are waiting to talk terms, what is running, and the free places or why hiring is blocked.
    private func hero(_ e: GameEngine, _ co: Company, _ waiting: Int, role: String?) -> some View {
        let running: [RunLine] = runLines(e, co)
        let context: String = running.isEmpty ? "No search running. Pick a role and how to look; answers arrive here and in your inbox." : running.map { $0.text }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            TeamHero(value: "\(waiting)", unit: waiting == 1 ? "applicant waiting" : "applicants waiting", context: context)
            if let why = e.hireBlock(companyID: companyID, role: role) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(why.tidyText).textStyle(.body, tint: P.caution).fixedSize(horizontal: false, vertical: true)
                    if e.roomListing(companyID: companyID) != nil {
                        Button("Move to bigger premises") { moveForRoom() }
                            .buttonStyle(TertiaryButtonStyle(size: .compact)).padding(.leading, -Theme.Space.s)
                    }
                }
            } else if let w = e.workplaces(companyID: companyID), let free = w.free {
                Text(free == 1 ? "1 free place" : "\(free) free places").textStyle(.caption, tint: P.inkFaint)
            }
        }
    }

    private func moveForRoom() {
        let cid = companyID
        switch store.act({ $0.moveForRoom(companyID: cid) }) {
        case .ok?: Haptics.success(); store.show("Moved to bigger premises. There is room to hire.", tone: "good")
        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash to move to bigger premises.", tone: "warn")
        case .bad?: Haptics.warning(); store.show("No bigger premises could be taken now.", tone: "warn")
        case nil: break
        }
    }

    /// The roles as chips; the chosen one's effect shows under them. Any other role can be typed.
    private func roleSection(_ roles: [RoleOption]) -> some View {
        let active: String = roleID.isEmpty ? (startRole ?? "") : roleID
        let typing: Bool = !custom.trimmingCharacters(in: .whitespaces).isEmpty
        let picked: RoleOption? = typing ? nil : roles.first { (r: RoleOption) -> Bool in r.id == active }
        return TeamBlock("Which role") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                WrapRow(spacing: Theme.Space.xs) {
                    ForEach(roles) { (r: RoleOption) in
                        HireChip(title: r.filled ? r.name + " \u{2713}" : r.name, on: !typing && r.id == active) { Haptics.choose(); roleID = r.id; custom = "" }
                    }
                }
                if let picked {
                    let filled: String = picked.filled ? "Filled already. " : ""
                    if !(filled + picked.effect).isEmpty { Text((filled + picked.effect).tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
                }
                LedgerField(placeholder: "Another role, in words", text: $custom)
            }
        }
    }

    // MARK: How to look

    private func searchSection(_ e: GameEngine, _ cur: Currency) -> some View {
        let share: Int = Int(saturating: (Agency.salaryShare * 100).rounded())
        let words: String = method == .ad
            ? "The ad runs four weeks. People answer a few at a time, and each reply comes as a message."
            : "Three suggestions now and better ones over the next weeks. Costs far more than an ad, and \(share) percent of the hired person's salary for \(Agency.months) months."
        return TeamBlock("How to look") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SegmentedPill(items: Method.allCases, title: { (m: Method) -> String in m.rawValue }, selection: $method)
                Text(words).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The one action of the page, pinned under the scroll: post the ad or engage the agency, with the reason when it cannot be done yet.
    private func actionBar(_ e: GameEngine, _ co: Company, _ cur: Currency, _ chosen: (id: String, name: String)?) -> some View {
        let role: String = chosen?.id ?? ""
        let fee: Double = role.isEmpty ? 0 : (method == .ad ? e.jobAdFee(companyID: companyID, role: role) : e.agencyFee(companyID: companyID, role: role))
        let form: (companyName: String, orgNumber: String)? = e.jobAdForm(companyID: companyID)
        var why: String? = nil
        if chosen == nil { why = "Pick a role first." } else if method == .ad && form == nil { why = "This company cannot advertise now." }
        let title: String = (method == .ad ? "Post the ad" : "Engage the agency") + (role.isEmpty ? "" : " \u{00B7} " + cur.tidyShort(fee))
        return PrimaryAction(title: title, blockedReason: why, identifier: method == .ad ? "hire-post-ad" : "hire-engage-agency") {
            guard let chosen else { return }
            if method == .ad { askAd(chosen, fee, cur, form) } else { askAgency(chosen, fee, cur) }
        }
        .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.m)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        .background(P.page)
        .overlay(alignment: .top) { Hairline() }
    }

    /// The ad's company details are shown in the confirmation instead of a separate tick box.
    private func askAd(_ chosen: (id: String, name: String), _ fee: Double, _ cur: Currency, _ form: (companyName: String, orgNumber: String)?) {
        let cid = companyID, role = chosen.id, name = chosen.name.lowercased()
        let who: String = form.map { (f: (companyName: String, orgNumber: String)) -> String in
            " The ad names " + f.companyName + (f.orgNumber.isEmpty ? "." : ", organisation number " + f.orgNumber + ".")
        } ?? ""
        pending = PendingAction(title: "Post a job ad for a \(name)?", message: "Cost: \(cur.tidyShort(fee)), paid now. Benefit: applicants answer over four weeks. Risk: none may suit." + who,
                                button: "Pay \(cur.tidyShort(fee))", amount: fee, currency: cur, tone: .info, icon: "megaphone") {
            let r: JobAds.PostResult? = store.act { $0.postJobAd(companyID: cid, role: role) }
            switch r {
            case .posted(_, let n)?: Haptics.success(); store.show("Ad running. About \(n) \(n == 1 ? "person" : "people") should answer over the next weeks.", tone: "good")
            case .notEnoughCash(let f)?: Haptics.warning(); store.show("Not enough cash: the ad costs \(cur.tidyShort(f)).", tone: "warn")
            case .missingRecord(let why)?: Haptics.warning(); store.show(why, tone: "warn")
            case .notPossible(let why)?: Haptics.warning(); store.show(why, tone: "warn")
            case nil: break
            }
        }
    }

    private func askAgency(_ chosen: (id: String, name: String), _ fee: Double, _ cur: Currency) {
        let cid = companyID, role = chosen.id, name = chosen.name.lowercased()
        let share: Int = Int(saturating: (Agency.salaryShare * 100).rounded())
        pending = PendingAction(title: "Engage an agency for a \(name)?", message: "Cost: \(cur.tidyShort(fee)) now, then \(share) percent of the hired person's salary for \(Agency.months) months. Benefit: suggestions at once and better ones over weeks. Risk: it is the dearest way.",
                                button: "Pay \(cur.tidyShort(fee))", amount: fee, currency: cur, tone: .info, icon: "person.badge.plus") {
            let r: Agency.EngageResult? = store.act { $0.engageAgency(companyID: cid, role: role) }
            switch r {
            case .engaged(_, let ids)?: Haptics.success(); store.show("The agency has \(ids.count) suggestions for you now, more to follow.", tone: "good")
            case .notEnoughCash(let f)?: Haptics.warning(); store.show("Not enough cash: the agency costs \(cur.tidyShort(f)).", tone: "warn")
            case .missingRecord(let why)?: Haptics.warning(); store.show(why, tone: "warn")
            case .notPossible(let why)?: Haptics.warning(); store.show(why, tone: "warn")
            case nil: break
            }
        }
    }

    // MARK: Running searches

    private func runLines(_ e: GameEngine, _ co: Company) -> [RunLine] {
        let today: Int = e.state.week * 7 + e.state.day
        var out: [RunLine] = []
        for (n, a) in co.value("ads").array.enumerated() {
            let left: Int = JobAds.adDays - (today - a["d0"].int)
            if left > 0 { out.append(RunLine(id: "ad\(n)", text: "Ad for \(a["role"].string.lowercased()) running, \(left) days left. Applicants will come.")) }
        }
        for (n, a) in co.value("agency").array.enumerated() {
            let left: Int = Agency.laterWeeks * 7 - (today - a["d0"].int)
            if left > 0 { out.append(RunLine(id: "ag\(n)", text: "Agency looking for a \(a["role"].string.lowercased()): better suggestions are still coming.")) }
        }
        return out
    }

    // MARK: Applicants

    private func roleName(_ id: String, _ roles: [RoleOption]) -> String {
        roles.first(where: { (o: RoleOption) -> Bool in o.id == id })?.name ?? (id.prefix(1).uppercased() + id.dropFirst())
    }

    /// This company's applicants in the shared `ApplicantRow`; the Applicants page has the filters and every company.
    private func applicantsSection(_ e: GameEngine, _ co: Company, _ cur: Currency, _ roles: [RoleOption], _ list: [Applicant]) -> some View {
        TeamBlock(title: "Applicants", trailing: {
            Button("All applicants") { Haptics.tap(); store.openApplicants(companyID: companyID, role: nil) }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
        }) {
            VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.personID) { n, a in
                        if n > 0 { PersonRowRule() }
                        ApplicantRow(applicant: a, roleName: roleName(a.role, roles), currency: cur,
                                     ask: e.applicantAskPreview(personID: a.personID, companyID: companyID),
                                     open: openID == a.personID, talkIdentifier: "hire-talk-terms",
                                     onTap: { Motion.animate(Motion.quickAnimation) { openID = openID == a.personID ? nil : a.personID } },
                                     onTrial: { pending = ApplicantTrial.ask(store, a, companyID: companyID, cur) },
                                     onTalk: { talk = WorkerRef(id: a.personID) })
                }
            }
        }
    }
}

/// The page a tapped applicant opens: the one-page terms and salary talk, for this company's worker post.
struct HireOnePageHost: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var personID: Int

    var body: some View {
        if let e = store.engine, let p = e.state.people[personID] {
            let named: String? = e.recommendedRoles(companyID: companyID).first(where: { (o: RoleOption) -> Bool in o.id == p.role })?.name
            let title: String = named ?? String(p.role.prefix(1).uppercased() + p.role.dropFirst())
            HireOnePage(request: HireRequest(post: .worker(role: p.role), companyID: companyID, personID: personID, roleTitle: title))
        } else {
            EmptyState(glyph: Glyph.person, title: "This person is no longer on the market.")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).ledgerBackground()
        }
    }
}
