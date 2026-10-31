import SwiftUI
import GameCore
import Countries
import Simulation

// Accounting > Settings: who has access to THIS company's accounting. Named users only (owner decision): nobody has access unless the owner adds them,
// the accountant included, and access to one company never opens another. The owner sees and changes it; everyone else sees a locked screen.
// The engine enforces every level (`accountingLevel`, `canAccess`), and the owner can preview what a named user sees. There are no integrations or
// accounting-method settings because the game does not model them.

extension AccountingLevel {
    /// What a level lets a person do, in plain words.
    var summary: String {
        switch self {
        case .none: return "No access to this company's accounting."
        case .view: return "Reads transactions, invoices, suppliers and documents."
        case .payroll: return "Reads everything, plus payroll, payslips and timesheets."
        case .full: return "Payroll and bookkeeping: notes, paying invoices, sending invoices."
        case .owner: return "Everything, including who has access."
        }
    }
    static let grantable: [AccountingLevel] = [.view, .payroll, .full]
}

struct AcctSettings: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let roster = e.accountingRoster(companyID: co.id, user: m.user) {
                        access(roster.granted, co)
                        company(e, co)
                    } else {
                        AcctLocked(section: "Settings")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 40)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        }
    }

    private func access(_ granted: [AccountingUser], _ co: Company) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Access management")
            AcctPanel {
                AcctRow(initials: AcctRow.initials(store.engine?.state.player.name ?? "You"), title: "You", subtitle: "Owner", valueNote: "Full access", identifier: "acct-access-owner")
                ForEach(granted) { (u: AccountingUser) in
                    VStack(spacing: 0) {
                        AcctDivider()
                        AcctRow(initials: AcctRow.initials(u.name), title: u.name, subtitle: u.role.capitalized, valueNote: u.level.title, identifier: "acct-access-user") { m.push(.access(u.id)) }
                    }
                }
            }
            if granted.isEmpty {
                Text("No one else has access to \(co.name). Add the accountant or a manager if they should see the books.").font(.system(size: 12.5)).foregroundStyle(P.inkSoft).padding(.horizontal, 2)
            }
            AcctPrimaryButton(title: "Add user", identifier: "acct-access-add") { m.push(.addUser) }
            Text("Access is per company: giving someone access here does not open the other companies in your group.").font(.system(size: 11.5)).foregroundStyle(P.inkFaint).padding(.horizontal, 2)
        }
    }

    private func company(_ e: GameEngine, _ co: Company) -> some View {
        let stats: CompanyOverviewStats? = e.companyOverviewStats(companyID: co.id)
        return VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Company")
            AcctPanel(padding: 14) {
                FlatRow(label: "Legal form", value: stats?.legalForm ?? (co.form == .limited ? "Limited company" : "Sole trader"), rule: false)
                if let since = stats?.incorporatedSince { FlatRow(label: "Registered since", value: since) }
                FlatRow(label: "Appointed accountant", value: stats?.accountant ?? "None")
                FlatRow(label: "Owner access", value: AccountingLevel.owner.title)
            }
        }
    }
}

/// One named user's access: the level, a preview of what they see, and removal.
struct AcctAccessDetail: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel
    var userID: String
    @State private var level: AccountingLevel = .view
    @State private var loaded: Bool = false
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let roster = e.accountingRoster(companyID: co.id, user: m.user) {
                        if let person = (roster.granted + roster.candidates).first(where: { $0.id == userID }) {
                            header(person)
                            levels(person)
                            actions(person, co)
                        } else {
                            AcctNotice(glyph: Glyph.info, title: "This person is no longer part of \(co.name)", message: "Go back to the list.")
                        }
                    } else {
                        AcctLocked(section: "Settings")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 40)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .confirmAction($pending)
            .onAppear {
                if !loaded {
                    let current: AccountingLevel = e.accountingLevel(companyID: co.id, user: userID)
                    level = current == .none ? .view : (current == .owner ? .full : current)
                    loaded = true
                }
            }
        }
    }

    private func header(_ p: AccountingUser) -> some View {
        AcctPanel(padding: 16) {
            HStack(spacing: 12) {
                Text(AcctRow.initials(p.name)).font(.system(size: 14, weight: .semibold)).foregroundStyle(P.onAccent)
                    .frame(width: 44, height: 44).background(Circle().fill(P.accent))
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name).font(.system(size: 16, weight: .medium)).foregroundStyle(P.ink)
                    Text(p.role.capitalized + " \u{00B7} now: " + p.level.title).font(.system(size: 12.5)).foregroundStyle(P.inkFaint)
                }
                Spacer(minLength: 8)
            }
        }
    }

    private func levels(_ p: AccountingUser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Access level")
            ForEach(AccountingLevel.grantable, id: \.rawValue) { (l: AccountingLevel) in
                AcctChoice(title: l.title, subtitle: l.summary, selected: level == l, identifier: "acct-level-" + String(l.rawValue)) { level = l }
            }
            AcctPrimaryButton(title: p.level == .none ? "Give access" : "Save access", identifier: "acct-access-save") { save(p) }
        }
    }

    private func actions(_ p: AccountingUser, _ co: Company) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if p.level != .none {
                AcctSecondaryButton(title: "See what they see", identifier: "acct-access-preview") {
                    m.user = p.id
                    m.userName = p.name
                    m.goHome()
                    Haptics.choose()
                }
                AcctSecondaryButton(title: "Remove access", tint: P.loss, identifier: "acct-access-remove") { confirmRemove(p, co) }
            }
        }
    }

    private func save(_ p: AccountingUser) {
        let id: Int = m.companyID
        let target: String = p.id
        let chosen: AccountingLevel = level
        let result: AccessChange? = store.act({ (e: inout GameEngine) -> AccessChange in e.setAccountingAccess(companyID: id, userID: target, level: chosen) })
        switch result {
        case .changed?:
            Haptics.success()
            store.show("\(p.name) now has \(chosen.title.lowercased()) access to this company.", tone: "good")
            m.pop()
        case .unchanged?:
            store.show("\(p.name) already has that access.", tone: "n")
        case .refused(let why)?:
            Haptics.warning()
            store.show(why, tone: "warn")
        case nil:
            break
        }
    }

    private func confirmRemove(_ p: AccountingUser, _ co: Company) {
        let id: Int = co.id
        let target: String = p.id
        let name: String = p.name
        pending = PendingAction(title: "Remove \(name)'s access?", message: "\(name) can no longer open the accounting of \(co.name). You can add them again later.", button: "Remove access", destructive: true) {
            let result: AccessChange? = store.act({ (e: inout GameEngine) -> AccessChange in e.removeAccountingAccess(companyID: id, userID: target) })
            switch result {
            case .changed?:
                Haptics.success()
                store.show("\(name) no longer has access.", tone: "good")
                m.pop()
            case .unchanged?:
                store.show("\(name) had no access.", tone: "n")
            case .refused(let why)?:
                Haptics.warning()
                store.show(why, tone: "warn")
            case nil:
                break
            }
        }
    }
}

/// Add a user: the people of this company (and its accountant) who do not have access yet.
struct AcctAddUser: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let roster = e.accountingRoster(companyID: co.id, user: m.user) {
                        if roster.candidates.isEmpty {
                            AcctNotice(glyph: Glyph.people, title: "No one to add",
                                       message: "Everyone who works for \(co.name), and its accountant, already has access. Hire a manager or appoint an accountant to add more people.")
                        } else {
                            Text("Choose who should see the books of \(co.name).").font(.system(size: 13)).foregroundStyle(P.inkSoft).padding(.horizontal, 2)
                            AcctPanel {
                                ForEach(Array(roster.candidates.enumerated()), id: \.element.id) { n, u in
                                    VStack(spacing: 0) {
                                        if n > 0 { AcctDivider() }
                                        AcctRow(initials: AcctRow.initials(u.name), title: u.name, subtitle: u.role.capitalized, identifier: "acct-candidate-row") { m.push(.access(u.id)) }
                                    }
                                }
                            }
                        }
                    } else {
                        AcctLocked(section: "Settings")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 40)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        }
    }
}
