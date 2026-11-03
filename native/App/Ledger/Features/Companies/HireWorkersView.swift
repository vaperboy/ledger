import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// "Hire the <role>": pick the role (the trade's own jobs and the recommended extras, or any role in words), then how to search (a job ad or an
/// agency), then read the people who answer. Applicants arrive over time as inbox messages; this page lists them as they come. A tap on "Talk terms"
/// pushes `HireOnePage` (no sheet rises from the bottom). Fees, applicants and what happens are the engine's (`jobAdFee`, `postJobAd`,
/// `agencyFee`, `engageAgency`, `applicants`).
struct HireWorkersView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    /// The role to start on, when a link asks for one.
    var startRole: String? = nil
    @State private var roleID = ""
    @State private var custom = ""
    @State private var method = Method.ad
    @State private var confirmedForm = false
    @State private var pending: PendingAction?
    @State private var talk: WorkerRef?
    @State private var openID: Int?

    enum Method: String, CaseIterable, Hashable { case ad = "Job ad", agency = "Agency" }

    private struct RunLine: Identifiable { var id: String; var text: String }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            screen(e, co)
        } else {
            Text("This company is not available.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding().appScreen(title: "Hire", tab: store.tab)
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
        var title = "Hire the worker"
        if let c = chosen { title = "Hire the " + c.name.lowercased() }
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                placesNote(e)
                roleSection(roles)
                if let chosen { searchSection(e, co, cur, chosen) }
                runningSection(e, co)
                applicantsSection(e, co, cur, roles)
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .confirmAction($pending)
        .navigationDestination(item: $talk) { (w: WorkerRef) -> HireOnePageHost in HireOnePageHost(companyID: companyID, personID: w.id) }
        .appScreen(title: title, subtitle: co.name, tab: store.tab)
    }

    @ViewBuilder private func placesNote(_ e: GameEngine) -> some View {
        if let why = e.hireBlock(companyID: companyID) {
            Text(why).font(.system(size: 12.5)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
        } else if let w = e.workplaces(companyID: companyID), let free = w.free {
            Text(free == 1 ? "1 free place" : "\(free) free places").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    private func roleSection(_ roles: [RoleOption]) -> some View {
        let active: String = roleID.isEmpty ? (startRole ?? "") : roleID
        let typing: Bool = !custom.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            Text("Which role").capsLabel()
            ForEach(roles) { (r: RoleOption) -> AnyView in
                AnyView(roleRow(r, selected: !typing && r.id == active))
            }
            TextField("Another role, in words", text: $custom).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                .textInputAutocapitalization(.sentences).autocorrectionDisabled()
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(Theme.surfaceTable))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(typing ? Theme.gold : Theme.border, lineWidth: 1))
        }
    }

    private func roleRow(_ r: RoleOption, selected: Bool) -> some View {
        Button { Haptics.choose(); roleID = r.id; custom = "" } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    if !r.effect.isEmpty { Text(r.effect).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 6)
                if r.filled { Text("Filled").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(selected ? Theme.goldSelected : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(selected ? Theme.gold : Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: How to search

    private func searchSection(_ e: GameEngine, _ co: Company, _ cur: Currency, _ chosen: (id: String, name: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to look").capsLabel()
            SegmentedPill(items: Method.allCases, title: { (m: Method) -> String in m.rawValue }, selection: $method)
            if method == .ad { adBlock(e, cur, chosen) } else { agencyBlock(e, cur, chosen) }
        }
    }

    private func adBlock(_ e: GameEngine, _ cur: Currency, _ chosen: (id: String, name: String)) -> some View {
        let fee: Double = e.jobAdFee(companyID: companyID, role: chosen.id)
        let form: (companyName: String, orgNumber: String)? = e.jobAdForm(companyID: companyID)
        return VStack(alignment: .leading, spacing: 8) {
            Text("The ad runs four weeks. People answer a few at a time, and each reply comes as a message.")
                .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            if let form {
                field("Company name", form.companyName)
                field("Organisation number", form.orgNumber)
                Toggle("These details are right", isOn: $confirmedForm).font(.system(size: 13)).foregroundStyle(Theme.ivory).tint(Theme.gold)
            }
            QuietButton(title: "Post the ad \u{00B7} " + cur.tidyShort(fee), fullWidth: true) { askAd(chosen, fee, cur) }
                .opacity(form != nil && confirmedForm ? 1 : 0.4).disabled(!(form != nil && confirmedForm))
                .accessibilityIdentifier("hire-post-ad")
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(Theme.surfaceTable))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func agencyBlock(_ e: GameEngine, _ cur: Currency, _ chosen: (id: String, name: String)) -> some View {
        let fee: Double = e.agencyFee(companyID: companyID, role: chosen.id)
        let share: Int = Int((Agency.salaryShare * 100).rounded())
        return VStack(alignment: .leading, spacing: 8) {
            Text("Three suggestions now and better ones over the next weeks. Costs far more than an ad, and \(share) percent of the hired person's salary for \(Agency.months) months.")
                .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Engage the agency \u{00B7} " + cur.tidyShort(fee), fullWidth: true) { askAgency(chosen, fee, cur) }
                .accessibilityIdentifier("hire-engage-agency")
        }
    }

    private func askAd(_ chosen: (id: String, name: String), _ fee: Double, _ cur: Currency) {
        let cid = companyID, role = chosen.id, name = chosen.name.lowercased()
        pending = PendingAction(title: "Post a job ad for a \(name)?", message: "Cost: \(cur.tidyShort(fee)), paid now. Benefit: applicants answer over four weeks. Risk: none may suit.",
                                button: "Pay \(cur.tidyShort(fee))", amount: fee, currency: cur) {
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
        let share: Int = Int((Agency.salaryShare * 100).rounded())
        pending = PendingAction(title: "Engage an agency for a \(name)?", message: "Cost: \(cur.tidyShort(fee)) now, then \(share) percent of the hired person's salary for \(Agency.months) months. Benefit: suggestions at once and better ones over weeks. Risk: it is the dearest way.",
                                button: "Pay \(cur.tidyShort(fee))", amount: fee, currency: cur) {
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

    @ViewBuilder private func runningSection(_ e: GameEngine, _ co: Company) -> some View {
        let lines: [RunLine] = runLines(e, co)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines) { (l: RunLine) -> AnyView in
                    AnyView(HStack(spacing: 8) {
                        Image(systemName: "clock").font(.system(size: 12)).foregroundStyle(Theme.gold)
                        Text(l.text).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    })
                }
            }
        }
    }

    // MARK: Applicants

    private func roleName(_ id: String, _ roles: [RoleOption]) -> String {
        roles.first(where: { (o: RoleOption) -> Bool in o.id == id })?.name ?? (id.prefix(1).uppercased() + id.dropFirst())
    }

    @ViewBuilder private func applicantsSection(_ e: GameEngine, _ co: Company, _ cur: Currency, _ roles: [RoleOption]) -> some View {
        let list: [Applicant] = e.applicants(companyID: companyID)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Applicants").capsLabel()
                Spacer(minLength: 6)
                if !list.isEmpty { Text("\(list.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
                Button { Haptics.tap(); store.openApplicants(companyID: companyID, role: nil) } label: {
                    Text("Open page \u{203A}").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold).frame(minHeight: 32).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
            if list.isEmpty {
                Text("No one yet. Post an ad or engage an agency; answers arrive here and in your inbox.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(list) { (a: Applicant) -> AnyView in
                AnyView(HiringApplicantCard(applicant: a, roleName: roleName(a.role, roles), currency: cur, companyID: companyID, open: openID == a.personID,
                                            trialCost: a.marketYearly / 12 / 4,
                                            onTap: { openID = openID == a.personID ? nil : a.personID },
                                            onTrial: { askTrial(a, a.marketYearly / 12 / 4, cur) },
                                            onTalk: { talk = WorkerRef(id: a.personID) }))
            }
        }
    }

    private func askTrial(_ a: Applicant, _ cost: Double, _ cur: Currency) {
        let cid = companyID, pid = a.personID
        pending = PendingAction(
            title: "Pay for a trial week with \(a.name)?",
            message: "Cost: \(cur.tidyShort(cost)) paid now, whatever you decide. Benefit: you see how their work really goes. Risk: one week shows only part of the picture, and they may take another job. It does not hire them.",
            button: "Pay \(cur.tidyShort(cost))", amount: cost, currency: cur) {
                if let seen = store.act({ $0.startTrialWeek(personID: pid, companyID: cid) }) ?? nil {
                    Haptics.success(); store.show(seen.first?.text ?? "The trial week is done.", tone: "n")
                } else {
                    Haptics.warning(); store.show("Could not arrange a trial week: it was done already, or the company needs \(cur.tidyShort(cost)) in cash.", tone: "warn")
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
            Text("This person is no longer on the market.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).ledgerBackground()
        }
    }
}
