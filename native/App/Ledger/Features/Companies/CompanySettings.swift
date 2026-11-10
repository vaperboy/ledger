import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Events
import Simulation

struct CompanySettings: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var closeWeeks = 4
    @State private var giveUpRent = false
    @State private var pauseSubscriptions = false
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if company.status == .closed { closing(cur) }
            if company.status != .closed { closing(cur) }
            windUp(cur)
            documents(cur)
        }
        .confirmAction($pending)
    }

    @ViewBuilder private func closing(_ cur: Currency) -> some View {
        if company.status == .closed {
            CardSection(title: "Closed", trailing: {
                let left = company.int("closeW")
                Text(left > 0 && left < 999 ? "reopens in \(left) week\(left == 1 ? "" : "s")" : "until you reopen").textStyle(.caption, tint: Theme.warn)
            }) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("No sales; rent continues, wages drop to 40% after two weeks.")
                        .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                    Button("Reopen now") {
                        switch store.act({ $0.reopenCompany(companyID: company.id) }) {
                        case .ok?: Haptics.success(); store.show("\(company.name) is open again.", tone: "good")
                        case nil: break
                        default: Haptics.warning(); store.show("It is not closed.", tone: "warn")
                        }
                    }.buttonStyle(QuietButtonStyle())
                }
            }
        } else if company.status == .open {
            let notice = engine.closeNoticeTerms(companyID: company.id)
            CardSection("Close for a while") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Reopens by itself; rent continues, wages drop to 40% after two weeks.")
                        .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                    SegmentedChoice(items: [2, 4, 8, 13, 26], title: { "\($0) weeks" }, selection: $closeWeeks)
                    if let notice {
                        Toggle(isOn: $giveUpRent) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Give up the rented place").textStyle(.body)
                                Text("Three months' rent as notice (\(cur.tidyShort(notice.notice)))" + (notice.depositBack > 0 ? ", deposit of \(cur.tidyShort(notice.depositBack)) back" : "") + ". You will need new premises to reopen.")
                                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                            }
                        }.tint(Theme.gold)
                    }
                    if company.value("eq").object.values.contains(where: { !$0["sub"].isNull }) {
                        Toggle(isOn: $pauseSubscriptions) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Pause software plans").textStyle(.body)
                                Text("No charge while it is closed; the plans start again when it reopens. Your data is kept.").textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
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
        pending = PendingAction(title: "Close \(company.name) for \(weeks) weeks?", message: "No sales until it reopens; customers drift away the longer it is shut." + (giveUp ? " The lease ends now: \(cur.tidyDisplay(notice?.notice ?? 0)) notice." : ""), button: "Close", destructive: false, tone: .warning, icon: "pause.circle") {
            switch store.act({ $0.closeCompany(companyID: company.id, weeks: weeks, giveUpRent: giveUp, pauseSubscriptions: pauseSubscriptions) }) {
            case .ok?: Haptics.warning(); giveUpRent = false; store.show("\(company.name) is closed for \(weeks) weeks.", tone: "n")
            case .notOpen?: Haptics.warning(); store.show("Only an open company can be closed.", tone: "warn")
            case nil: break
            default: Haptics.warning(); store.show("It cannot be closed now.", tone: "warn")
            }
        }
    }

    @ViewBuilder private func windUp(_ cur: Currency) -> some View {
        if company.status.isLive && engine.isBranch(companyID: company.id) {
            branchExit(cur)
        }
    }

    @ViewBuilder private func branchExit(_ cur: Currency) -> some View {
        let plan = engine.branchClosurePlan(storeID: company.id), quote = engine.branchSaleQuote(storeID: company.id)
        CardSection("Close or sell this branch") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Close the branch or sell it with its site and staff; the money stays in the chain.")
                    .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                if let p = plan {
                    FlatRow(label: "Closing: cash in less costs", value: cur.tidyShort(p.net), tint: p.net >= 0 ? Theme.gain : Theme.loss, rule: false)
                    FlatRow(label: "Move to other branches / redundant", value: "\(p.transfers.count) / \(p.redundancies)")
                    Button("Close \(company.name)…") { confirmBranch(close: true, amount: p.net, cur) }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                }
                if let q = quote {
                    FlatRow(label: "A buyer pays", value: cur.tidyShort(q.price), tint: Theme.gain)
                    Button("Sell \(company.name) as a going concern…") { confirmBranch(close: false, amount: q.price, cur) }.buttonStyle(QuietButtonStyle(tint: Theme.ivory))
                }
                if plan == nil && quote == nil {
                    Text("This branch cannot leave the chain now.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func confirmBranch(close: Bool, amount: Double, _ cur: Currency) {
        let name = company.name, id = company.id
        pending = PendingAction(title: close ? "Close \(name)?" : "Sell \(name)?",
                                message: close ? "This is final. The branch is wound down into the chain (\(cur.tidyDisplay(amount)) net)." : "This is final. The buyer takes the site and the staff and pays the chain \(cur.tidyDisplay(amount)).",
                                button: close ? "Close the branch" : "Sell the branch", destructive: true) {
            let ok: Bool
            if close {
                switch store.act({ $0.closeBranch(storeID: id) }) {
                case .success?: ok = true
                case .failure(.votedDown(let pct))?:
                    Haptics.warning(); store.outcome(chosen: "Close the branch", result: "The co-owners voted it down: \(pct)% of the shares were for it. \(name) stays open.")
                    return
                default: ok = false
                }
            }
            else { if case .success = store.act({ $0.sellBranch(storeID: id) }) { ok = true } else { ok = false } }
            Haptics.warning(); store.show(ok ? (close ? "\(name) is closed." : "\(name) is sold.") : "\(name) could not leave the chain.", tone: ok ? "n" : "warn")
        }
    }

    @ViewBuilder private func documents(_ cur: Currency) -> some View {
        let lic = engine.financeOverview(companyID: company.id).licences
        if !lic.isEmpty {
            CardSection(title: "Documents and permits", trailing: { Label("held", systemImage: "checkmark").textStyle(.caption, tint: Theme.inkFaint) }) {
                VStack(spacing: 0) {
                    ForEach(Array(lic.enumerated()), id: \.element.id) { n, l in FlatRow(label: l.label, value: l.amount > 0 ? cur.tidyShort(l.amount) : "free", sub: l.detail, rule: n > 0) }
                }
            }
        }
    }
}
