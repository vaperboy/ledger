import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct TradeAssociationScreen: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @ObservedObject private var directory: AssociationStore = AssociationStore.shared
    @State private var consequence: AssociationChoice?
    @State private var shownMembers: AssociationClub?
    @State private var problem: String?
    @State private var openPlayer: AssociationMembersPopup.PlayerPick?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            ScrollView {
                content(e, co)
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: "Trade association", subtitle: co.name, tab: .group)
            .centerSheet(item: $consequence, category: .medium, tone: .info) { (c: AssociationChoice) in
                AssociationConsequencePopup(companyID: companyID, choice: c) { consequence = nil; problem = $0 }.environmentObject(store)
            }
            .centerSheet(item: $shownMembers, title: "Members", category: .medium, tone: .neutral) { (c: AssociationClub) in
                AssociationMembersPopup(club: c, includesYou: AssociationChoice.isMember(e, companyID, c)) { (id: String) in shownMembers = nil; openPlayer = AssociationMembersPopup.PlayerPick(id: id) }
            }
            .navigationDestination(item: $openPlayer) { (p: AssociationMembersPopup.PlayerPick) in PlayerProfileView(playerID: p.id) }
            .task { syncMembers(e, co) }
        } else {
            EmptyState(glyph: Glyph.home, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        let cur: Currency = e.currency(for: co)
        let standing: AssociationStanding = AssociationStanding(co)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if let p = problem { InlineMessage(text: p) }
            if let m = TradeAssociations.membership(e.state, companyID: co.id) {
                memberCard(e, m, standing, cur)
                standardsCard(m.club, standing)
                discountCard(m.club, members: m.members, cur: cur, saved: m.saved)
                membersRow(m.club, count: m.members)
                Button { consequence = AssociationChoice(club: m.club, join: false) } label: { Text("Leave this club") }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true)).accessibilityIdentifier("assoc-leave")
            } else {
                Text("Clubs for \(e.tradeName(co)) in \(OnlineCountry.name(co.countryCode)) and across trades. A company belongs to one club at a time.")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                ForEach(AssociationCatalogue.clubs(tradeName: e.tradeName(co), region: co.countryCode)) { (c: AssociationClub) in
                    clubCard(c, standing, cur, banned: nil)
                }
            }
        }
    }

    private func memberCard(_ e: GameEngine, _ m: AssociationMembership, _ x: AssociationStanding, _ cur: Currency) -> some View {
        let toNext: Int = AssociationEnforcement.cycleWeeks - ((e.state.week - m.joinedWeek) % AssociationEnforcement.cycleWeeks)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Your club").capsLabel(Theme.ivoryFaint)
            Text(m.club.name).textStyle(.title)
            Text(standingWord(m.strikes)).textStyle(.body, tint: m.strikes == 0 ? Theme.gain : Theme.loss).fixedSize(horizontal: false, vertical: true)
            Hairline()
            HStack {
                Text("Monthly fee").textStyle(.body, tint: Theme.inkSoft)
                Spacer()
                Text(cur.tidyShort(m.club.monthlyFee)).textStyle(.body, numeric: true)
            }
            HStack {
                Text("Saved on supplies so far").textStyle(.body, tint: Theme.inkSoft)
                Spacer()
                ArrowAmount(gain: m.saved, format: { cur.tidyDisplay($0) })
            }
            Text("The next fee and standards check come in \(toNext) \(toNext == 1 ? "week" : "weeks").").textStyle(.caption, tint: Theme.inkFaint)
        }
        .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
    }

    private func standingWord(_ strikes: Int) -> String {
        switch strikes {
        case 0: return "In good standing."
        case 1: return "Warned. Put the record right before the next check or a fine follows."
        default: return "Fined. Another miss means removal from the club."
        }
    }

    private func standardsCard(_ club: AssociationClub, _ x: AssociationStanding) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Standards, and your record today").capsLabel(Theme.ivoryFaint)
            ForEach(club.standards, id: \.self) { (s: AssociationStandard) in
                let ok: Bool = s.isMet(x)
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    GlyphView(glyph: ok ? Glyph.arrowIn : Glyph.arrowOut, size: 14, weight: 1.8, tint: ok ? Theme.gain : Theme.loss).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.rule).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                        Text(ok ? "You meet this." : "You do not meet this today.").textStyle(.caption, tint: ok ? Theme.gain : Theme.loss)
                    }
                }
            }
        }
        .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
    }

    private func discountCard(_ club: AssociationClub, members: Int, cur: Currency, saved: Double?) -> some View {
        let rate: Double = GroupPurchasing.rate(members: members, cap: club.discountCap)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Group buying").capsLabel(Theme.ivoryFaint)
            Text(GroupPurchasing.words(members: members, rate: rate, cap: club.discountCap)).textStyle(.body).fixedSize(horizontal: false, vertical: true)
            Text("The discount applies to catalogue supply lines and never goes above \(percent(club.discountCap)) in this club.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
    }

    private func membersRow(_ club: AssociationClub, count: Int) -> some View {
        LedgerRow(leading: .glyph(Glyph.suppliers), leadingTint: Theme.inkSoft, title: "Members",
                  subtitle: "\(count) \(count == 1 ? "member" : "members") buy together", identifier: "assoc-members") { shownMembers = club }
            .padding(.horizontal, Theme.Space.m).glassSurface()
    }

    private func clubCard(_ c: AssociationClub, _ x: AssociationStanding, _ cur: Currency, banned: Int?) -> some View {
        let n: Int = directory.pooledMembers(of: c, includingYou: false)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).textStyle(.title)
                Text((c.tradeName == nil ? "Open to every trade" : "For \(c.tradeName ?? "")") + " · \(cur.tidyShort(c.monthlyFee)) a month")
                    .textStyle(.caption, tint: Theme.inkSoft)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Members must").textStyle(.caption, tint: Theme.inkFaint)
                ForEach(c.standards, id: \.self) { (s: AssociationStandard) in
                    Text("· " + s.rule).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(GroupPurchasing.words(members: n, rate: GroupPurchasing.rate(members: n, cap: c.discountCap), cap: c.discountCap))
                .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.s) {
                Button { shownMembers = c } label: { Text("See members") }
                    .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("assoc-see-\(c.id)")
                Button { consequence = AssociationChoice(club: c, join: true) } label: { Text("Join") }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("assoc-join-\(c.id)")
            }
        }
        .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading).glassSurface()
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) percent" }

    private func syncMembers(_ e: GameEngine, _ co: Company) {
        guard let m = TradeAssociations.membership(e.state, companyID: co.id) else { return }
        let n: Int = directory.pooledMembers(of: m.club, includingYou: true)
        guard n != m.members else { return }
        _ = store.act { (g: inout GameEngine) in g.update { s, _, _ in TradeAssociations.setMembers(&s, companyID: co.id, members: n) } }
    }
}

struct TradeAssociationRows: View {
    var engine: GameEngine
    var entity: GroupEntity

    var body: some View {
        let cos: [Company] = entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in
            c.status == .open && CompanyDetailView.availableSections(c, engine).contains(.operations)
        }
        if !cos.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("TRADE ASSOCIATION").capsLabel()
                ForEach(cos) { (c: Company) in
                    NavigationLink { TradeAssociationScreen(companyID: c.id) } label: {
                        CardRow(glyph: Glyph.suppliers, title: cos.count > 1 ? c.name : "Trade association",
                                subtitle: TradeAssociations.membership(engine.state, companyID: c.id).map { (m: AssociationMembership) -> String in "Member of \(m.club.name)" } ?? "Join for group buying")
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("group-association-\(c.id)")
                }
            }
        }
    }
}

struct AssociationChoice: Identifiable, Equatable {
    var club: AssociationClub
    var join: Bool
    var id: String { club.id + (join ? ".join" : ".leave") }

    static func isMember(_ e: GameEngine, _ companyID: Int, _ club: AssociationClub) -> Bool {
        TradeAssociations.membership(e.state, companyID: companyID)?.club.id == club.id
    }
}

struct AssociationConsequencePopup: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var choice: AssociationChoice
    var done: (String?) -> Void

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let cur: Currency = e.currency(for: co)
            let lines: [String] = choice.join ? joinLines(e, co, cur) : leaveLines(e)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(choice.club.name).popupText(.subtitle)
                VStack(alignment: .leading, spacing: PopupSpace.row) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { (_: Int, l: String) in
                        Text("· " + l).popupText(.body)
                    }
                }
            }
            .centerSheetTitle(choice.join ? "If you join, this will happen" : "If you leave, this will happen")
            .popupFooter {
                PopupFooter(cancel: "Not now", action: choice.join ? "Join \(choice.club.name)" : "Leave the club", tone: choice.join ? .normal : .destructive,
                            onCancel: { done(nil) }, onAction: { act(e, co) }, cancelID: "assoc-cancel", actionID: "assoc-confirm")
            }
        }
    }

    private func joinLines(_ e: GameEngine, _ co: Company, _ cur: Currency) -> [String] {
        let members: Int = AssociationStore.shared.pooledMembers(of: choice.club, includingYou: true)
        var lines: [String] = TradeAssociations.joinPreview(choice.club, members: members, standing: AssociationStanding(co))
        lines[0] = "The first monthly fee, \(cur.tidyShort(choice.club.monthlyFee)), is taken from \(co.name) now, then every fourth week."
        return lines
    }

    private func leaveLines(_ e: GameEngine) -> [String] {
        guard let m = TradeAssociations.membership(e.state, companyID: companyID) else { return [] }
        return TradeAssociations.leavePreview(m)
    }

    private func act(_ e: GameEngine, _ co: Company) {
        let id: Int = companyID, club: AssociationClub = choice.club, trade: String = e.tradeName(co)
        if choice.join {
            let members: Int = AssociationStore.shared.pooledMembers(of: club, includingYou: true)
            let result: JoinResult? = store.act { (g: inout GameEngine) -> JoinResult in
                var r: JoinResult = .joined
                g.update { s, _, _ in r = TradeAssociations.join(&s, companyID: id, club: club, members: members, tradeName: trade) }
                return r
            }
            if case .refused(let why)? = result { done(why) } else { done(nil) }
        } else {
            _ = store.act { (g: inout GameEngine) in g.update { s, _, _ in TradeAssociations.leave(&s, companyID: id) } }
            done(nil)
        }
    }
}

struct AssociationMembersPopup: View {
    var club: AssociationClub
    var includesYou: Bool
    var onOpen: (String) -> Void

    struct PlayerPick: Identifiable, Hashable { var id: String }

    var body: some View {
        let rows: [AssociationMemberRow] = AssociationStore.shared.service.members(of: club)
        VStack(alignment: .leading, spacing: 0) {
            Text(club.name).popupText(.subtitle).padding(.bottom, Theme.Space.s)
            if rows.isEmpty && !includesYou {
                Text("No members yet.").popupText(.body)
            }
            if includesYou {
                LedgerRow(leading: .initials("You"), title: "You", subtitle: "A member of this club")
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { (n: Int, r: AssociationMemberRow) in
                if n > 0 || includesYou { Hairline() }
                LedgerRow(leading: .initials(r.profile.initials), title: r.profile.displayName,
                          subtitle: [r.line, r.profile.level.map { "Level \($0)" }, OnlineCountry.name(r.profile.countryCode)].compactMap { $0 }.joined(separator: " · "),
                          identifier: "assoc-member-\(r.id)") { onOpen(r.id) }
            }
        }
    }
}
