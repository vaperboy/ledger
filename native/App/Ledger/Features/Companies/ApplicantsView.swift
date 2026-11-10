import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

struct ApplicantRowItem: Identifiable {
    var id: String
    var companyID: Int
    var order: Int
    var applicant: Applicant
    var ask: Double?
    var market: Double?
}

struct ApplicantTalk: Identifiable, Hashable {
    var companyID: Int
    var personID: Int
    var id: String { "\(companyID)-\(personID)" }
}

enum ApplicantSort: String, CaseIterable, Hashable {
    case best = "Best match", wage = "Lowest wage ask", newest = "Newest"
}

struct ApplicantsView: View {
    @EnvironmentObject var store: GameStore
    @State private var companySel: Int
    @State private var roleSel: String
    @State private var sort: ApplicantSort = .best
    @State private var talk: ApplicantTalk?
    @State private var limit = 40
    @State private var showHire = false
    @State private var openID: String?
    @State private var pending: PendingAction?

    init(companyID: Int?, role: String?) {
        _companySel = State(initialValue: companyID ?? 0)
        _roleSel = State(initialValue: role ?? "")
    }

    var body: some View {
        if let e = store.engine {
            screen(e)
        } else {
            EmptyState(title: "Nothing to show.").appScreen(title: "Applicants", tab: store.tab)
        }
    }

    private func hasAd(_ co: Company) -> Bool {
        let today: Int = (store.engine?.state.week ?? 0) * 7 + (store.engine?.state.day ?? 0)
        for a in co.value("ads").array where JobAds.adDays - (today - a["d0"].int) > 0 { return true }
        return false
    }

    private func companies(_ e: GameEngine) -> [Company] {
        var out: [Company] = []
        for co in e.state.companies where co.status.isLive {
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

    private func screen(_ e: GameEngine) -> some View {
        let cos: [Company] = companies(e)
        let all: [ApplicantRowItem] = items(e, cos)
        var roles: [String] = []
        for r in all where !roles.contains(r.applicant.role) { roles.append(r.applicant.role) }
        let shown: [ApplicantRowItem] = sorted(all.filter { (r: ApplicantRowItem) -> Bool in roleSel.isEmpty || r.applicant.role == roleSel })
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                hero(e, cos, shown)
                filters(e, cos, all, roles)
                if shown.isEmpty { emptyState(e, cos) } else { list(e, shown) }
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        .confirmAction($pending)
        .navigationDestination(item: $talk) { (t: ApplicantTalk) -> HireOnePageHost in HireOnePageHost(companyID: t.companyID, personID: t.personID) }
        .navigationDestination(isPresented: $showHire) { HireWorkersView(companyID: hireTarget(cos)) }
        .appScreen(title: "Applicants", tab: store.tab)
    }

    private func hero(_ e: GameEngine, _ cos: [Company], _ shown: [ApplicantRowItem]) -> some View {
        let n: Int = shown.count
        let place: String = companySel == 0 ? (cos.count == 1 ? cos[0].name : "\(cos.count) companies") : (e.state.company(companySel)?.name ?? "")
        let ads: Int = cos.filter { (c: Company) -> Bool in (companySel == 0 || c.id == companySel) && hasAd(c) }.count
        let context: String = place + (ads > 0 ? " \u{00B7} \(ads) \(ads == 1 ? "ad" : "ads") running" : " \u{00B7} no ad running")
        return TeamHero(value: "\(n)", unit: n == 1 ? "applicant waiting" : "applicants waiting", context: cos.isEmpty ? "No ad running" : context)
    }

    private func hireTarget(_ cos: [Company]) -> Int {
        if companySel != 0 { return companySel }
        return cos.first?.id ?? 0
    }

    private func filters(_ e: GameEngine, _ cos: [Company], _ all: [ApplicantRowItem], _ roles: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
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
            if all.count > 1 {
                Menu {
                    ForEach(ApplicantSort.allCases, id: \.self) { (s: ApplicantSort) in
                        Button { Haptics.choose(); sort = s } label: {
                            if sort == s { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) }
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Text("Sort: " + sort.rawValue)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                }
                .menuStyle(.button)
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .padding(.leading, -Theme.Space.s)
                .accessibilityIdentifier("applicants-sort")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func firstCompany(_ all: [ApplicantRowItem], _ role: String) -> Int {
        all.first(where: { (r: ApplicantRowItem) -> Bool in r.applicant.role == role })?.companyID ?? companySel
    }

    private func chipRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        WrapRow(spacing: Theme.Space.xs) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        HireChip(title: title, on: on) { Haptics.choose(); action() }
    }

    private func list(_ e: GameEngine, _ rows: [ApplicantRowItem]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(rows.prefix(limit).enumerated()), id: \.element.id) { n, r in
                if n > 0 { PersonRowRule() }
                row(e, r)
            }
            if rows.count > limit {
                Button("Show \(min(40, rows.count - limit)) more") { limit += 40 }
                    .buttonStyle(TertiaryButtonStyle(fullWidth: true))
                    .padding(.top, Theme.Space.m)
            }
        }
    }

    private func row(_ e: GameEngine, _ r: ApplicantRowItem) -> some View {
        let a: Applicant = r.applicant
        let co: Company? = e.state.company(r.companyID)
        let cur: Currency = co.map { (c: Company) -> Currency in e.currency(for: c) } ?? e.currency(for: e.state.companies[0])
        let tag: ApplicantTalk = ApplicantTalk(companyID: r.companyID, personID: a.personID)
        let preview: (ask: Double, market: Double)? = r.ask.flatMap { (ask: Double) -> (ask: Double, market: Double)? in r.market.map { (ask: ask, market: $0) } }
        return ApplicantRow(applicant: a, roleName: roleName(e, r.companyID, a.role), companyName: companySel == 0 ? (co?.name ?? "") : "",
                            currency: cur, ask: preview, open: openID == r.id, talkIdentifier: "applicant-hear-out",
                            onTap: { Motion.animate(Motion.quickAnimation) { openID = openID == r.id ? nil : r.id } },
                            onTrial: { pending = ApplicantTrial.ask(store, a, companyID: r.companyID, cur) },
                            onTalk: { talk = tag })
    }

    private func emptyState(_ e: GameEngine, _ cos: [Company]) -> some View {
        let canHire: Bool = hireTarget(cos) != 0
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("People answer a job ad or an agency search over the following weeks. Each reply also arrives as a message.")
                .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            if canHire {
                Button("Post a job ad") { Haptics.tap(); showHire = true }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("applicants-post-ad")
            }
        }
    }
}

struct ApplicantsLinkRow: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var companyID: Int

    var body: some View {
        let n: Int = engine.applicants(companyID: companyID).count
        LedgerRow(leading: .glyph(Glyph.inbox), title: "Applicants", subtitle: "Everyone who answered an ad or an agency",
                  value: n == 0 ? "None yet" : "\(n)", valueTint: n == 0 ? P.inkFaint : P.accent, identifier: "open-applicants") {
            store.openApplicants(companyID: companyID, role: nil)
        }
    }
}

extension GameStore {
    func openApplicants(companyID: Int?, role: String?) {
        let route: CompanyRoute = .applicants(companyID ?? 0, role ?? "")
        Task { @MainActor [weak self] in self?.push(route) }
    }
}
