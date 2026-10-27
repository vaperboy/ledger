import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The way into hiring from a company's Team tab: one card that opens the Hiring screen.
struct HiringEntry: View {
    var company: Company
    var body: some View {
        NavigationLink {
            HiringView(companyID: company.id)
        } label: {
            CardRow(glyph: Glyph.person, title: "Hire someone", subtitle: "Job ad, network or agency; see who applies and talk terms")
        }
        .buttonStyle(.plain)
    }
}

/// "Hire a <role>" (new look, option A: cards). Pick the role, choose how to look (job ad, network, agency; the fee is the engine's), run the search,
/// and read the applicants as cards. Nothing here changes a wage: terms are talked on the Negotiation screen, and hiring is confirmed there.
struct HiringView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var role = ""
    @State private var mode: Hiring.SearchMode = .ads
    @State private var found: [Int] = []
    @State private var searched = false
    @State private var openID: Int?
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            screen(e, co)
        } else {
            Text("This company is not available.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding().appScreen(title: "Hire", tab: store.tab)
        }
    }

    private func roleLabel(_ id: String) -> String { id.prefix(1).uppercased() + id.dropFirst() }

    @ViewBuilder private func screen(_ e: GameEngine, _ co: Company) -> some View {
        let roles: [String] = e.hireableRoles(companyID: companyID)
        let activeRole: String = role.isEmpty ? (roles.first ?? "") : role
        let board: HiringBoard? = activeRole.isEmpty ? nil : e.hiringBoard(companyID: companyID, role: activeRole, personIDs: found)
        let roleName: String = board?.roleName ?? ""
        let trade: String = e.tradeInfo(companyID: companyID)?.name ?? ""
        let subtitle: String = [co.name, trade, e.cityName(co)].filter { !$0.isEmpty }.joined(separator: " · ")
        let cur: Currency = e.currency(for: co)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let board {
                    if roles.count > 1 {
                        SectionTabs(items: roles, title: { roleLabel($0) }, selection: roleBinding(activeRole)).padding(.horizontal, -18)
                    }
                    SegmentedPill(items: board.searches.map { $0.mode }, title: { m in board.searches.first { $0.mode == m }?.title ?? "" }, selection: $mode)
                    infoCard(e, board, cur)
                    if activeRole == "mktan" {
                        let v = e.marketAnalystVerdict(companyID: companyID)
                        Text(v.title + ". " + v.text).font(.system(size: 12)).foregroundStyle(v.ok ? Theme.ivoryMuted : Theme.caution)
                    }
                    searchButton(board, cur, activeRole)
                    applicants(e, co, board, cur)
                } else {
                    Text("This trade has no staff roles to hire for.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                }
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
        }
        .confirmAction($pending)
        .appScreen(title: roleName.isEmpty ? "Hire" : "Hire a \(roleName.lowercased())", subtitle: subtitle, tab: store.tab)
    }

    private func roleBinding(_ active: String) -> Binding<String> {
        Binding(get: { active }, set: { role = $0; found = []; searched = false; openID = nil })
    }

    // MARK: Info card and search

    private func feeText(_ o: HiringSearchOption, _ cur: Currency) -> String { o.fee > 0 ? cur.tidyShort(o.fee) : "free" }

    private func infoCard(_ e: GameEngine, _ board: HiringBoard, _ cur: Currency) -> some View {
        let option: HiringSearchOption? = board.searches.first { $0.mode == mode }
        let note: String = option?.note ?? ""
        let fee: String = option.map { feeText($0, cur) } ?? "free"
        let count: String
        if searched {
            let n: Int = board.applicants.count
            count = "\(n) \(n == 1 ? "applicant" : "applicants") this week."
        } else if let o = option {
            count = "It brings \(o.applicantsMin) to \(o.applicantsMax) people."
        } else {
            count = ""
        }
        let market: String = "Market pay for this role: \(cur.tidyShort(board.marketYearly)) a year."
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(Theme.gold).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(note) \(count)").foregroundStyle(Theme.ivoryMuted)
                Text(market).foregroundStyle(Theme.ivory)
                Text("This search: \(fee).").foregroundStyle(Theme.ivoryMuted)
            }
            .font(.system(size: 12)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func searchButton(_ board: HiringBoard, _ cur: Currency, _ activeRole: String) -> some View {
        let option: HiringSearchOption? = board.searches.first { $0.mode == mode }
        let title: String = option.map { "\(searched ? "Search again" : "Run") the \($0.title.lowercased()) · \(feeText($0, cur))" } ?? "Search"
        return QuietButton(title: title, fullWidth: true) { search(activeRole, board.roleName) }
    }

    private func search(_ activeRole: String, _ roleName: String) {
        let m = mode
        let cid = companyID
        let people: [Person] = store.act { $0.searchWorkers(companyID: cid, role: activeRole, mode: m) } ?? []
        found = people.map { $0.id }
        searched = true
        openID = found.first
        let how: String = m == .ads ? "The job ad" : m == .network ? "Your network" : "The agency"
        if people.isEmpty { Haptics.warning(); store.show("\(how) found no one suitable for \(roleName.lowercased()).", tone: "warn") }
        else { Haptics.tap(); store.show("\(how) found \(people.count) \(people.count == 1 ? "candidate" : "candidates") for \(roleName.lowercased()).", tone: "n") }
    }

    // MARK: Applicants

    @ViewBuilder private func applicants(_ e: GameEngine, _ co: Company, _ board: HiringBoard, _ cur: Currency) -> some View {
        if board.applicants.isEmpty {
            let text: String = searched ? "Nobody left on the list: they found other jobs, or the search found no one. Search again."
                : "Run a search to see who applies."
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
        }
        ForEach(board.applicants) { a in
            HiringApplicantCard(applicant: a, roleName: board.roleName, currency: cur, companyID: companyID, open: openID == a.personID,
                                trialCost: board.marketMonthly / 4,
                                onTap: { openID = openID == a.personID ? nil : a.personID },
                                onTrial: { askTrial(a, board.marketMonthly / 4, cur) })
        }
    }

    private func askTrial(_ a: Applicant, _ cost: Double, _ cur: Currency) {
        let cid = companyID, pid = a.personID
        pending = PendingAction(
            title: "Pay for a trial week with \(a.name)?",
            message: "Cost: \(cur.tidyShort(cost)) paid now, whatever you decide. Benefit: you see about how good their work really is. Risk: the reading is approximate, and they may take another job. It does not hire them.",
            button: "Pay \(cur.tidyShort(cost))", amount: cost, currency: cur) {
                if let seen = store.act({ $0.startTrialWeek(personID: pid, companyID: cid) }) ?? nil {
                    Haptics.success(); store.show("After a week their work looks like \(Int(seen)) skill.", tone: "n")
                } else {
                    Haptics.warning(); store.show("Could not arrange a trial week: it was done already, or the company needs \(cur.tidyShort(cost)) in cash.", tone: "warn")
                }
            }
    }
}

/// Patience is never shown as a number: only a feeling, from how much of the engine's patience is left (no rules, only wording).
enum PatienceWords {
    static func feeling(left: Int, of total: Int) -> (text: String, tint: Color) {
        let f: Double = total > 0 ? Double(left) / Double(total) : 0
        if f > 0.66 { return ("Relaxed", Theme.ivory) }
        if f > 0.34 { return ("Getting impatient", Theme.caution) }
        return ("Close to walking away", Theme.loss)
    }
}

/// How an ask or an offer compares with the market, in words and colour: "3% above market" amber, "8% below market" green, "14% above market" red.
enum HiringFigures {
    static func versusMarket(_ v: Double, wording: String = "market") -> (text: String, tint: Color) {
        let pct = Int((abs(v) * 100).rounded())
        if pct == 0 { return ("at \(wording)", Theme.ivoryMuted) }
        if v > 0 { return ("\(pct)% above \(wording)", v >= 0.10 ? Theme.loss : Theme.caution) }
        return ("\(pct)% below \(wording)", Theme.gain)
    }

    static func initials(_ name: String) -> String {
        let letters: [String] = name.split(separator: " ").compactMap { $0.first.map { String($0) } }
        return (letters.first ?? "") + (letters.count > 1 ? (letters.last ?? "") : "")
    }
}

/// One applicant (option A): initials circle, name, age / role / experience, the ask against the market, the claimed skill, claimed experience and
/// first impression. The selected card opens to the CV line and the two actions. Only what the player can see before an interview is shown:
/// the skill is what they claim, never the true one.
struct HiringApplicantCard: View {
    var applicant: Applicant
    var roleName: String
    var currency: Currency
    var companyID: Int
    var open: Bool
    var trialCost: Double
    var onTap: () -> Void
    var onTrial: () -> Void

    private var experienceLine: String {
        guard let y = applicant.claimedExperienceYears else { return "no experience given" }
        let n = Int(y.rounded())
        return "\(n) \(n == 1 ? "year" : "years")"
    }

    var body: some View {
        let a = applicant
        let versus = HiringFigures.versusMarket(a.askVersusMarket)
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onTap) { summary(a, versus) }.buttonStyle(.plain)
            if open { details(a) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(open ? Theme.gold : Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func summary(_ a: Applicant, _ versus: (text: String, tint: Color)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(HiringFigures.initials(a.name)).font(.system(size: 14)).foregroundStyle(Theme.gold)
                    .frame(width: 40, height: 40).background(Circle().fill(Theme.divider))
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text("\(a.age) · \(roleName) · \(experienceLine)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(currency.tidyShort(a.askYearly)).font(.system(size: 15, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Text(versus.text).font(.system(size: 11)).foregroundStyle(versus.tint)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skill").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.border).frame(height: 4)
                            Capsule().fill(Theme.gold).frame(width: g.size.width * CGFloat(min(1, max(0, a.claimedSkill / 100))), height: 4)
                        }
                    }.frame(height: 4).padding(.top, 5).padding(.bottom, 4)
                }.frame(maxWidth: .infinity, alignment: .leading)
                fact("Experience", a.claimedExperienceYears.map { "\(Int($0.rounded())) \(Int($0.rounded()) == 1 ? "yr" : "yrs") claimed" } ?? "none given")
                fact("Seems", a.seems)
            }
        }
        .contentShape(Rectangle())
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            Text(value).font(.system(size: 12.5)).foregroundStyle(Theme.ivory)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func details(_ a: Applicant) -> some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
        VStack(alignment: .leading, spacing: 6) {
            if !a.resume.isEmpty { Text("\u{201C}\(a.resume)\u{201D}").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
            let claim: String = a.claimedExperienceYears.map { "Claims \(Int($0.rounded())) \(Int($0.rounded()) == 1 ? "year" : "years")" } ?? "No experience given"
            Text(claim + (a.referencesChecked ? "; references checked." : "; not checked.")).font(.system(size: 12)).foregroundStyle(Theme.ivoryDim)
            if let t = a.trialSkill {
                Text("After a trial week their work looked like skill \(Int(t.rounded())), give or take a few points.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            }
        }
        HStack(spacing: 8) {
            if a.trialSkill == nil {
                Button(action: onTrial) { actionLabel("Trial week · \(currency.tidyShort(trialCost))", strong: false) }.buttonStyle(.plain)
            }
            NavigationLink { HiringNegotiationView(companyID: companyID, personID: a.personID) } label: { actionLabel("Talk terms \u{203A}", strong: true) }
                .buttonStyle(.plain)
        }
    }

    private func actionLabel(_ title: String, strong: Bool) -> some View {
        Text(title).font(.system(size: 13.5, weight: strong ? .medium : .regular)).foregroundStyle(Theme.ivory)
            .frame(maxWidth: .infinity, minHeight: 28).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(strong ? Theme.gold : Theme.borderStrong, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
