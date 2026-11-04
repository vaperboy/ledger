import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// One applicant on the Applicants page: the engine's applicant (not made Identifiable), the company they answered, and what they would ask.
struct ApplicantRowItem: Identifiable {
    var id: String
    var companyID: Int
    var order: Int
    var applicant: Applicant
    var ask: Double?
    var market: Double?
}

/// The target of "Hear them out": the existing terms flow for this person and company.
struct ApplicantTalk: Identifiable, Hashable {
    var companyID: Int
    var personID: Int
    var id: String { "\(companyID)-\(personID)" }
}

enum ApplicantSort: String, CaseIterable, Hashable {
    case best = "Best match", wage = "Lowest wage ask", newest = "Newest"
}

/// Everyone who answered a job ad or agency search, in one page: a company picker and a role filter in a fixed header, then a row per applicant.
/// "Hear them out" opens the same terms page as the hire flow (`HireOnePage`). Reached from the inbox, Team, the hire page and Group Management
/// through `GameStore.openApplicants`; Back returns to where the player came from (the page is a route on the tab's stack).
struct ApplicantsView: View {
    @EnvironmentObject var store: GameStore
    @State private var companySel: Int
    @State private var roleSel: String
    @State private var sort: ApplicantSort = .best
    @State private var talk: ApplicantTalk?
    /// No list shows more than 40 rows at once (brief 9.2); `Show more` adds 40.
    @State private var limit = 40
    @State private var showHire = false

    init(companyID: Int?, role: String?) {
        _companySel = State(initialValue: companyID ?? 0)
        _roleSel = State(initialValue: role ?? "")
    }

    var body: some View {
        if let e = store.engine {
            screen(e)
        } else {
            Text("Nothing to show.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding().appScreen(title: "Applicants", tab: store.tab)
        }
    }

    // MARK: Data

    private func hasAd(_ co: Company) -> Bool {
        let today: Int = (store.engine?.state.week ?? 0) * 7 + (store.engine?.state.day ?? 0)
        for a in co.value("ads").array where JobAds.adDays - (today - a["d0"].int) > 0 { return true }
        return false
    }

    private func companies(_ e: GameEngine) -> [Company] {
        var out: [Company] = []
        for co in e.state.companies where co.status.isLive && co.type != "hold" {
            let n: Int = e.applicants(companyID: co.id).count
            if n > 0 || hasAd(co) || co.id == companySel { out.append(co) }
        }
        return out
    }

    private func roleName(_ e: GameEngine, _ companyID: Int, _ id: String) -> String {
        let named: String? = e.recommendedRoles(companyID: companyID).first(where: { (o: RoleOption) -> Bool in o.id == id })?.name
        return named ?? String(id.prefix(1).uppercased() + id.dropFirst())
    }

    private func items(_ e: GameEngine, _ cos: [Company]) -> [ApplicantRowItem] {
        var out: [ApplicantRowItem] = []
        for co in cos where companySel == 0 || co.id == companySel {
            let list: [Applicant] = e.applicants(companyID: co.id)
            for (n, a) in list.enumerated() {
                let pre: (ask: Double, market: Double)? = e.applicantAskPreview(personID: a.personID, companyID: co.id)
                out.append(ApplicantRowItem(id: "\(co.id)-\(a.personID)", companyID: co.id, order: n, applicant: a, ask: pre?.ask, market: pre?.market))
            }
        }
        return out
    }

    private func sorted(_ rows: [ApplicantRowItem]) -> [ApplicantRowItem] {
        switch sort {
        case .best:
            return rows.sorted { (x: ApplicantRowItem, y: ApplicantRowItem) -> Bool in (x.applicant.claimedExperienceYears ?? 0) > (y.applicant.claimedExperienceYears ?? 0) }
        case .wage:
            return rows.sorted { (x: ApplicantRowItem, y: ApplicantRowItem) -> Bool in (x.ask ?? x.applicant.marketMonthly) < (y.ask ?? y.applicant.marketMonthly) }
        case .newest:
            return rows.sorted { (x: ApplicantRowItem, y: ApplicantRowItem) -> Bool in x.order > y.order }
        }
    }

    // MARK: Screen

    private func screen(_ e: GameEngine) -> some View {
        let cos: [Company] = companies(e)
        let all: [ApplicantRowItem] = items(e, cos)
        var roles: [String] = []
        for r in all where !roles.contains(r.applicant.role) { roles.append(r.applicant.role) }
        let shown: [ApplicantRowItem] = sorted(all.filter { (r: ApplicantRowItem) -> Bool in roleSel.isEmpty || r.applicant.role == roleSel })
        return VStack(spacing: 0) {
            header(e, cos, all, roles)
            if shown.isEmpty {
                emptyState(e, cos)
            } else {
                list(e, shown)
            }
        }
        .navigationDestination(item: $talk) { (t: ApplicantTalk) -> HireOnePageHost in HireOnePageHost(companyID: t.companyID, personID: t.personID) }
        .navigationDestination(isPresented: $showHire) { HireWorkersView(companyID: hireTarget(cos)) }
        .appScreen(title: "Applicants", tab: store.tab)
    }

    private func hireTarget(_ cos: [Company]) -> Int {
        if companySel != 0 { return companySel }
        return cos.first?.id ?? 0
    }

    // MARK: Header

    private func header(_ e: GameEngine, _ cos: [Company], _ all: [ApplicantRowItem], _ roles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if cos.count > 1 || companySel != 0 {
                chipRow {
                    chip("All companies", on: companySel == 0) { companySel = 0; roleSel = "" }
                    ForEach(cos) { (c: Company) in
                        chip(c.name, on: companySel == c.id) { companySel = c.id; roleSel = "" }
                    }
                }
            }
            if roles.count > 1 || !roleSel.isEmpty {
                chipRow {
                    chip("All roles", on: roleSel.isEmpty) { roleSel = "" }
                    ForEach(roles, id: \.self) { (r: String) in
                        chip(roleName(e, firstCompany(all, r), r), on: roleSel == r) { roleSel = r }
                    }
                }
            }
            chipRow {
                ForEach(ApplicantSort.allCases, id: \.self) { (s: ApplicantSort) in
                    chip(s.rawValue, on: sort == s) { sort = s }
                }
            }
        }
        .padding(.horizontal, Theme.Space.margin).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func firstCompany(_ all: [ApplicantRowItem], _ role: String) -> Int {
        all.first(where: { (r: ApplicantRowItem) -> Bool in r.applicant.role == role })?.companyID ?? companySel
    }

    private func chipRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { content() }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.choose(); action() } label: {
            Text(title).font(.system(size: 12.5, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.ivory : Theme.ivoryFaint)
                .lineLimit(1)
                .padding(.horizontal, 12).frame(minHeight: 34)
                .background(Capsule().fill(on ? Theme.goldSelected : Theme.surface))
                .overlay(Capsule().strokeBorder(on ? Theme.gold : Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: List

    private func list(_ e: GameEngine, _ rows: [ApplicantRowItem]) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(rows.prefix(limit))) { (r: ApplicantRowItem) in
                    row(e, r)
                }
                if rows.count > limit {
                    QuietButton(title: "Show more", fullWidth: true) { limit += 40 }
                }
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, 4).padding(.bottom, 20)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
    }

    private func wageWords(_ r: ApplicantRowItem, _ cur: Currency) -> String {
        guard let ask = r.ask, let market = r.market, market > 0 else { return "Going rate " + cur.tidyShort(r.applicant.marketMonthly) + " a month" }
        let ratio: Double = ask / market
        var words = "asks well above the going rate"
        if ratio < 0.95 { words = "asks below the going rate" } else if ratio <= 1.05 { words = "asks about the going rate" } else if ratio <= 1.2 { words = "asks a little above the going rate" }
        return "Likely " + words + ": " + cur.tidyShort(ask) + " against " + cur.tidyShort(market) + " a month"
    }

    private func row(_ e: GameEngine, _ r: ApplicantRowItem) -> some View {
        let a: Applicant = r.applicant
        let co: Company? = e.state.company(r.companyID)
        let cur: Currency = co.map { (c: Company) -> Currency in e.currency(for: c) } ?? e.currency(for: e.state.companies[0])
        let claims: String = e.state.people[a.personID].map { (p: Person) -> String in CandidateClaims.line(e, p) } ?? a.cvImpression
        let at: String = companySel == 0 ? (" \u{00B7} " + (co?.name ?? "")) : ""
        let tag: ApplicantTalk = ApplicantTalk(companyID: r.companyID, personID: a.personID)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ThumbnailView(kind: .person, key: a.role, size: 44, initials: a.name, face: a.faceKey)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(roleName(e, r.companyID, a.role) + at).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
                }
                Spacer(minLength: 6)
            }
            Text(claims).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            Text(wageWords(r, cur)).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Hear them out", fullWidth: true) { talk = tag }
                .accessibilityIdentifier("applicant-hear-out")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    // MARK: Empty

    private func emptyState(_ e: GameEngine, _ cos: [Company]) -> some View {
        VStack(spacing: 10) {
            Text("No applicants yet").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ivory)
            Text("People answer a job ad or an agency search over the following weeks. Each reply also arrives as a message.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if hireTarget(cos) != 0 {
                Button { Haptics.tap(); showHire = true } label: {
                    Text("Post a job ad \u{203A}").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold).frame(minHeight: 36).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("applicants-post-ad")
            }
        }
        .padding(.horizontal, 28).padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The "Applicants" row with a count, for the company Team tab and Group Management: opens the Applicants page for that company.
struct ApplicantsLinkRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var companyID: Int

    var body: some View {
        let n: Int = engine.applicants(companyID: companyID).count
        Button { Haptics.tap(); store.openApplicants(companyID: companyID, role: nil) } label: {
            HStack(spacing: 6) {
                Text("Applicants").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                Spacer(minLength: 6)
                Text(n == 0 ? "None yet" : "\(n)").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(n == 0 ? Theme.ivoryFaint : Theme.gold)
                Text("\u{203A}").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.gold)
            }
            .frame(minHeight: 36).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("open-applicants")
    }
}

extension GameStore {
    /// Opens the Applicants page (all companies when `companyID` is nil; all roles when `role` is nil) on the tab the player is on, so Back
    /// returns to where they came from.
    func openApplicants(companyID: Int?, role: String?) {
        let route: CompanyRoute = .applicants(companyID ?? 0, role ?? "")
        Task { @MainActor [weak self] in self?.push(route) }
    }

    /// For an inbox message "<name> applied for <role>": the company and role it is about, else nil.
    func applicantLink(_ m: Message) -> (companyID: Int, role: String)? {
        guard m.companyID != 0, m.title.contains(" applied for ") else { return nil }
        let pid: Int = m.value("data")["pid"].int
        let role: String = engine?.state.people[pid]?.role ?? ""
        return (m.companyID, role)
    }
}
