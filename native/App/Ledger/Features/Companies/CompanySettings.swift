import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Events
import Simulation

/// The company itself: its legal form, its name, closing it for a while, and winding it up. Each action shows what it costs and
/// what follows before it is confirmed, and reports the engine's answer. Original: money.js 'legal' and 'close', rename_and_rebrand.js,
/// owner_hours_clients_assistants.js (`clgo`, `reopen`), engine `convertToAS` and `windUp`.
struct CompanySettings: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var newName = ""
    @State private var closeWeeks = 4
    @State private var giveUpRent = false
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            legalForm(cur)
            rename(cur)
            closing(cur)
            windUp(cur)
            documents(cur)
        }
        .confirmAction($pending)
    }

    // MARK: Legal form

    @ViewBuilder private func legalForm(_ cur: Currency) -> some View {
        LedgerSection(title: "Legal form", trailing: { Text(company.form == .limited ? "Limited company" : "Sole trader").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }) {
            if let cost = engine.convertToLimitedCost(companyID: company.id) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("As a sole trader the profit is yours and taxed on your personal return, and you are liable for every debt. A limited company pays company tax, pays you by salary or dividends, and its debts stay with it unless you guarantee them.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    FlatRow(label: "Registration fee", value: cur.short(cost.registrationFee), sub: "paid from your account", rule: false)
                    FlatRow(label: "Share capital", value: cur.short(cost.shareCapital), sub: "moves from your account into the company")
                    Button("Convert to a limited company…") { confirmConvert(cost, cur) }.buttonStyle(QuietButtonStyle())
                }
            } else {
                Text("A limited company: debts stay with the company unless you guaranteed them; you are paid by salary or dividends (You and owners).")
                    .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func confirmConvert(_ cost: (registrationFee: Double, shareCapital: Double), _ cur: Currency) {
        let total = cost.registrationFee + cost.shareCapital
        pending = PendingAction(title: "Convert \(company.name) to a limited company?", message: "\(cur.display(total)) leaves your account (\(cur.display(cost.shareCapital)) of it becomes the company's share capital). From then on profit pays company tax and money comes out as salary or dividends. This cannot be undone.", button: "Convert") {
            switch store.act({ $0.convertToLimited(companyID: company.id) }) {
            case .ok?: Haptics.success(); store.show("\(company.name) is now a limited company.", tone: "good")
            case .notEnoughCash?: Haptics.warning(); store.show("You need \(cur.display(total)) in your own account.", tone: "warn")
            case .alreadyLimited?: store.show("It is already a limited company.", tone: "n")
            default: store.show("Not possible.", tone: "warn")
            }
        }
    }

    // MARK: Name

    @ViewBuilder private func rename(_ cur: Currency) -> some View {
        let cost = engine.renameCost(companyID: company.id)
        let inChain = engine.chainOf(companyID: company.id) != nil
        LedgerSection(title: "Name", trailing: { Text(company.name).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(1) }) {
            if inChain {
                Text("This store carries its chain's name. Rebranding the whole chain is done from the chain.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    TextField("New name", text: $newName).font(.system(size: 14)).foregroundStyle(Theme.ivory).autocorrectionDisabled()
                        .padding(.horizontal, 10).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Color.white.opacity(0.05)))
                    Text("New signs and paperwork cost \(cur.display(cost)) from company cash. About a third of the people who knew the old name lose track of you.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    Button("Rename…") { confirmRename(cost, cur) }.buttonStyle(QuietButtonStyle()).disabled(newName.trimmingCharacters(in: .whitespaces).count < 2)
                }
            }
        }
    }

    private func confirmRename(_ cost: Double, _ cur: Currency) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        pending = PendingAction(title: "Rename to \u{201C}\(name)\u{201D}?", message: "Costs \(cur.display(cost)) and some awareness: customers have to learn the new name.", button: "Rename") {
            switch store.act({ $0.renameCompany(companyID: company.id, to: name) }) {
            case .ok?: Haptics.success(); newName = ""; store.show("Now called \(name).", tone: "good")
            case .tooShort?: store.show("Choose a different name of at least two letters.", tone: "warn")
            case .nameTaken?: store.show("Another company already has that name.", tone: "warn")
            case .notEnoughCash?: Haptics.warning(); store.show("The company needs \(cur.display(cost)) in cash.", tone: "warn")
            case .partOfChain?: store.show("A chain store carries the chain's name.", tone: "warn")
            default: store.show("Not possible.", tone: "warn")
            }
        }
    }

    // MARK: Closing for a while

    @ViewBuilder private func closing(_ cur: Currency) -> some View {
        if company.status == .closed {
            LedgerSection(title: "Closed", trailing: {
                let left = company.int("closeW")
                Text(left > 0 && left < 999 ? "reopens in \(left) week\(left == 1 ? "" : "s")" : "until you reopen").font(.system(size: 11.5)).foregroundStyle(Theme.caution)
            }) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("No sales while closed. Rent, the accountant and part of the running costs continue; wages are paid in full for two weeks, then 40%.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    Button("Reopen now") {
                        switch store.act({ $0.reopenCompany(companyID: company.id) }) {
                        case .ok?: Haptics.success(); store.show("\(company.name) is open again.", tone: "good")
                        default: store.show("It is not closed.", tone: "warn")
                        }
                    }.buttonStyle(QuietButtonStyle())
                }
            }
        } else if company.status == .open && company.type != "hold" {
            let notice = engine.closeNoticeTerms(companyID: company.id)
            LedgerSection("Close for a while") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("For a refit, a quiet season or to stop losses. It reopens by itself after the weeks you choose. Rent and the accountant continue; wages are paid in full for two weeks, then 40%.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    SectionTabs(items: [2, 4, 8, 13, 26], title: { "\($0) weeks" }, selection: $closeWeeks).padding(.horizontal, -Theme.Space.margin)
                    if let notice {
                        Toggle(isOn: $giveUpRent) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Give up the rented place").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text("Three months' rent as notice (\(cur.short(notice.notice)))" + (notice.depositBack > 0 ? ", deposit of \(cur.short(notice.depositBack)) back" : "") + ". You will need new premises to reopen.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                            }
                        }.tint(Theme.gold)
                    }
                    Button("Close for \(closeWeeks) weeks…") { confirmClose(notice, cur) }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private func confirmClose(_ notice: (notice: Double, depositBack: Double)?, _ cur: Currency) {
        let weeks = closeWeeks, giveUp = giveUpRent && notice != nil
        pending = PendingAction(title: "Close \(company.name) for \(weeks) weeks?", message: "No sales until it reopens; customers drift away the longer it is shut." + (giveUp ? " The lease ends now: \(cur.display(notice?.notice ?? 0)) notice." : ""), button: "Close", destructive: true) {
            switch store.act({ $0.closeCompany(companyID: company.id, weeks: weeks, giveUpRent: giveUp) }) {
            case .ok?: Haptics.warning(); giveUpRent = false; store.show("\(company.name) is closed for \(weeks) weeks.", tone: "n")
            case .notOpen?: store.show("Only an open company can be closed.", tone: "warn")
            default: store.show("Not possible.", tone: "warn")
            }
        }
    }

    // MARK: Winding up

    @ViewBuilder private func windUp(_ cur: Currency) -> some View {
        if company.status.isLive {
            let back = engine.windUpEstimate(companyID: company.id)
            let debts = CompanyFigures.debts(company, loans: engine.state.loans)
            LedgerSection("Close down for good") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Everything is sold at about 55% of its book value, loans and unpaid bills are paid first, and everyone who works here is let go." + (company.form == .soleTrader ? " As a sole trader you cover any shortfall yourself." : " Loans you guaranteed become yours."))
                        .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    FlatRow(label: "Debts and bills paid first", value: cur.short(debts), tint: debts > 0 ? Theme.loss : Theme.ivory, rule: false)
                    FlatRow(label: "Left for you (your share)", value: cur.short(back), tint: back > 0 ? Theme.gain : Theme.ivoryMuted)
                    if CompanySale.canSell(engine.state, companyID: company.id) {
                        Text("Selling as a going concern usually fetches more: see You and owners.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                    Button("Wind up \(company.name)…") { confirmWindUp(back, cur) }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                }
            }
        }
    }

    private func confirmWindUp(_ back: Double, _ cur: Currency) {
        let name = company.name, staff = company.staff.count
        pending = PendingAction(title: "Wind up \(name)?", message: "This is final. \(staff) \(staff == 1 ? "person loses their job" : "people lose their jobs"), the assets are sold off and you receive about \(cur.display(back)).", button: "Wind up for good", destructive: true) {
            if store.act({ $0.windUpCompany(companyID: company.id) }) == true {
                Haptics.warning(); store.show("\(name) is closed down and its things sold.", tone: "n")
            } else {
                store.show("\(name) could not be wound up.", tone: "warn")
            }
        }
    }

    // MARK: Documents

    @ViewBuilder private func documents(_ cur: Currency) -> some View {
        let lic = engine.financeOverview(companyID: company.id).licences
        if !lic.isEmpty {
            LedgerSection(title: "Documents and permits", trailing: { Text("✓ held").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(spacing: 0) {
                    ForEach(Array(lic.enumerated()), id: \.element.id) { n, l in FlatRow(label: l.label, value: l.amount > 0 ? cur.short(l.amount) : "free", sub: l.detail, rule: n > 0) }
                }
            }
        }
    }
}
