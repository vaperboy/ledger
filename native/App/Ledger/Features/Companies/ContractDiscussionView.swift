import SwiftUI
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

/// THE contract discussion with one employee: the only screen where pay rises, promotions, hours, pay basis, bonus plans, benefits, notice and moves
/// are agreed, for workers and for the store manager. It replaces the raise menu, the promotion sheet, the contract menu and the manager's raise,
/// move and profit-share buttons. Either side opens it: you from the staff profile or the manager card, the person with a request (which also
/// reaches the Inbox, where agree / delay / decline run the same engine path).
///
/// No rule lives here. The engine (`ContractTalk`) decides what can be discussed, what each choice costs, how the quit risk moves, what the country's
/// labour data requires, and what the person answers. The screen shows the preview before anything is confirmed and the answer after.
struct ContractDiscussionView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var personID: Int
    var startTopic: ContractTalk.Topic? = nil

    @State private var topic: ContractTalk.Topic = .payRise
    @State private var choice = ""
    @State private var percent = 0.06
    @State private var pay = 0.0
    @State private var hours = 30.0
    @State private var rate = 0.05
    @State private var weeks = 0
    @State private var authority = 1
    @State private var reply = ""
    @State private var pending: PendingAction?
    @State private var seeded = false

    var body: some View {
        PeopleSheet(title: "Contract discussion") {
            if let e = store.engine, let co = e.state.company(companyID), let n = e.state.people[personID], isEmployee(co) {
                let cur = e.currency(for: co)
                header(e, co, n, cur)
                if let talk = e.contractTalk(personID: personID) { open(e, co, n, talk, cur) }
                topics(e)
                editor(e, co, cur)
                preview(e, co, cur)
                if !reply.isEmpty { Text(reply).font(.system(size: 13)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true) }
                send(e, co, n, cur)
            } else {
                Text("This person no longer works here.").foregroundStyle(Theme.ivoryMuted)
            }
        }
        .confirmAction($pending)
        .onAppear { seed() }
        .onChange(of: topic) { _, _ in resetChoice() }
    }

    // MARK: Who and what

    private func isEmployee(_ co: Company) -> Bool { co.managerID == personID || co.staff.contains { $0.id == personID } }
    private func first(_ n: Person) -> String { n.name.split(separator: " ").first.map(String.init) ?? n.name }

    private func header(_ e: GameEngine, _ co: Company, _ n: Person, _ cur: Currency) -> some View {
        let isManager = co.managerID == personID
        let m = co.staff.first { $0.id == personID }
        let pay = isManager ? co.managerMonthlyWage : (m?.monthlyWage ?? 0)
        let role = isManager ? "Manager" : (m.map { $0.role.prefix(1).uppercased() + $0.role.dropFirst() } ?? "")
        return VStack(alignment: .leading, spacing: 4) {
            Text(n.name).font(.serifTitle(22)).foregroundStyle(Theme.ivory)
            Text("\(role) at \(co.name) · \(cur.tidyShort(pay)) a month" + (m?.weeklyHours.map { " · \(Int($0.rounded())) h a week" } ?? ""))
                .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            if let h = e.contractHandler(companyID: companyID), !isManager {
                Text("\(h.name) may handle these within \(cur.tidyShort(h.payLimit)) a month of extra pay and promotions (\(h.level >= 2 ? "full control" : "within limits")). Above that it comes to you.")
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Their request, or the talk you started and they answered with a counter.
    @ViewBuilder private func open(_ e: GameEngine, _ co: Company, _ n: Person, _ talk: ContractTalk.Talk, _ cur: Currency) -> some View {
        if talk.isRequest {
            let pv = e.contractPreview(companyID: companyID, personID: personID, proposal: talk.proposal, asRequest: true)
            LedgerSection("\(first(n)) asks") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(talk.reason.isEmpty ? "A request about \(talk.proposal.topic.title.lowercased())." : talk.reason).font(.system(size: 13)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                    Text(requestFigure(talk, cur)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold)
                    if talk.delayUntil > 0 { Text("You said you would answer by week \(talk.delayUntil). If you do not, \(first(n)) feels turned down.").font(.system(size: 11.5)).foregroundStyle(Theme.caution) }
                    consequenceLines(pv, cur)
                    partWay(talk, cur)
                    HStack(spacing: 10) {
                        Button("Agree") { answer(.accept, e, n, cur, pv) }.buttonStyle(QuietButtonStyle())
                        if talk.delayUntil == 0 { Button("Delay \(ContractTalk.delayWeeks) weeks") { answer(.delay, e, n, cur, pv) }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted)) }
                        Button("Decline") { answer(.decline, e, n, cur, pv) }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                    }
                    if e.contractHandler(companyID: companyID) != nil {
                        Button("Leave it to the manager") {
                            show(store.act { $0.contractLeaveToManager(companyID: companyID, personID: personID) })
                        }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                    }
                    Text("To answer with a figure of your own, set it below and send it. They may ask for more; they will not turn a raise down.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if talk.proposal.amount > 0 {
            LedgerSection("\(first(n))'s last word") {
                VStack(alignment: .leading, spacing: 8) {
                    Text((talk.isFinal ? "Their final word: " : "They ask: ") + requestFigure(talk, cur)).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                    partWay(talk, cur)
                }
            }
        }
    }

    /// Quick counters between your last offer and their ask (a quarter, half, three quarters of the way); the editor below takes any exact figure.
    @ViewBuilder private func partWay(_ t: ContractTalk.Talk, _ cur: Currency) -> some View {
        let p = t.proposal
        if [.payRise, .promotion, .hours].contains(p.topic), p.amount > 0 {
            let from = t.offered > 0 ? t.offered : (p.topic == .hours ? p.amount : 0)
            HStack(spacing: 8) {
                Text("Meet them part way").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                ForEach([0.25, 0.5, 0.75], id: \.self) { share in
                    let v = from + (p.amount - from) * share
                    Button(p.topic == .payRise ? "+\(String(format: "%.1f", v * 100))%" : p.topic == .hours ? "\(Int(v.rounded())) h" : cur.tidyShort(cur.roundedStep(v, about: 500))) {
                        topic = p.topic
                        switch p.topic {
                        case .payRise: percent = max(0.005, (v * 200).rounded() / 200)
                        case .promotion: pay = cur.roundedStep(v, about: 500)
                        default: hours = max(5, v.rounded()); choice = "hours"
                        }
                    }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                }
            }
            Text("Or set an exact figure below with the stepper or the field.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    private func requestFigure(_ t: ContractTalk.Talk, _ cur: Currency) -> String {
        let p = t.proposal
        switch p.topic {
        case .payRise: return "+\(String(format: "%.1f", p.amount * 100))% on their pay"
        case .promotion: return "\(cur.display(p.amount)) a month for the new post"
        case .hours: return "\(Int(p.amount.rounded())) hours a week"
        case .payBasis: return "A fixed monthly salary"
        default: return p.topic.title
        }
    }

    // MARK: Topics and the editor

    private func topics(_ e: GameEngine) -> some View {
        let list = e.contractTopics(companyID: companyID, personID: personID)
        return LedgerSection("Discuss") {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(list) { t in
                        Button(t.topic.title) { topic = t.topic }
                            .buttonStyle(QuietButtonStyle(tint: !t.available ? Theme.ivoryFaint : topic == t.topic ? Theme.gold : Theme.ivoryMuted))
                            .disabled(!t.available)
                    }
                }
                if let t = list.first(where: { $0.topic == topic }), !t.available { Text(t.why).font(.system(size: 11.5)).foregroundStyle(Theme.caution) }
            }
        }
    }

    @ViewBuilder private func editor(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        let options = e.contractChoices(companyID: companyID, personID: personID, topic: topic)
        let isManager = co.managerID == personID
        LedgerSection(topic.title) {
            VStack(alignment: .leading, spacing: 10) {
                switch topic {
                case .payRise:
                    Text("A raise they will notice is about 6 to 7 points; a smaller one is taken, but they stay unhappy.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted)
                    steps([0.03, 0.06, 0.10, 0.15], current: percent) { percent = $0 }
                    Stepper("Raise: +\(String(format: "%.1f", percent * 100))%", value: $percent, in: 0.005...0.5, step: 0.005).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                case .promotion:
                    pick(options)
                    AmountField(title: "Monthly pay offered", currency: cur, amount: $pay)
                    Picker("Authority", selection: $authority) {
                        Text("Asks you first").tag(0); Text("Within limits").tag(1); Text("Full control").tag(2)
                    }.pickerStyle(.segmented)
                case .hours:
                    pick(options)
                    if choice == "hours" { Stepper("\(Int(hours)) hours a week", value: $hours, in: 5...60, step: 5).font(.system(size: 13)).foregroundStyle(Theme.ivory) }
                case .payBasis:
                    pick(options)
                    if choice == "mix" || choice == "com" { steps(PayPlans.rateSteps, current: rate) { rate = $0 }; Text("Commission: \(Int((rate * 100).rounded()))% of their sales.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }
                case .bonus:
                    if !isManager && !options.isEmpty {
                        Text("A bonus plan is paid through payroll with the employer's charges, like wages: a share for every target the company meets, a year-end bonus when the budget is met, and a reward for the better half of the team in a month without a loss.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                        pick(options)
                        if choice == "commission" { steps(PayPlans.rateSteps, current: rate) { rate = $0 } }
                    } else {
                        Text(isManager ? "A share of each month's profit, on top of the salary. A share is not cut here." : "Their commission share of their own sales.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted)
                        steps(isManager ? [0.05, 0.1, 0.15, 0.2, 0.3] : PayPlans.rateSteps, current: rate) { rate = $0 }
                    }
                case .term:
                    Text("A permanent contract has no end date. A fixed term ends on its date unless you renew it; you are asked a few weeks before. Someone who wants security may not take a fixed term.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    pick(options)
                case .benefits:
                    pick(options)
                    if let on = options.first(where: { $0.id == choice })?.on { Text(on ? "It is on now: confirming switches it off." : "It is off now: confirming switches it on.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted) }
                case .notice:
                    Text("Extra weeks of notice on top of the law, owed both ways: they work them if they resign, you pay them if you let them go without cause.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        ForEach([0] + ContractTalk.noticeExtraChoices, id: \.self) { w in
                            Button(w == 0 ? "Law only" : "+\(w) wk") { weeks = w }.buttonStyle(QuietButtonStyle(tint: weeks == w ? Theme.gold : Theme.ivoryMuted))
                        }
                    }
                case .move:
                    pick(options)
                }
            }
        }
    }

    private func steps(_ values: [Double], current: Double, _ set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { v in
                Button("\(Int((v * 100).rounded()))%") { set(v) }.buttonStyle(QuietButtonStyle(tint: abs(current - v) < 0.0001 ? Theme.gold : Theme.ivoryMuted))
            }
        }
    }

    @ViewBuilder private func pick(_ options: [ContractTalk.Choice]) -> some View {
        if options.isEmpty { Text("Nothing to choose here.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
        ForEach(Array(options.enumerated()), id: \.element.id) { n, o in
            if n > 0 { Hairline() }
            Button { choice = o.id; if topic == .promotion, let ask = promotionAsk(o.id) { pay = ask } } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(o.title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Text(o.detail).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: choice == o.id ? "checkmark" : "circle").font(.system(size: 11)).foregroundStyle(choice == o.id ? Theme.gold : Theme.ivoryFaint)
                }.padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    private func promotionAsk(_ post: String) -> Double? {
        store.engine?.contractChoices(companyID: companyID, personID: personID, topic: .promotion).first { $0.id == post }?.amount
    }

    // MARK: The proposal, its consequences and sending it

    private func currentProposal(_ e: GameEngine) -> ContractTalk.Proposal {
        switch topic {
        case .payRise: return .init(.payRise, amount: percent)
        case .promotion: return .init(.promotion, amount: pay, choice: choice, terms: .init(authority: authority))
        case .hours: return .init(.hours, amount: hours, choice: choice.isEmpty ? "hours" : choice)
        case .payBasis: return .init(.payBasis, amount: (choice == "mix" || choice == "com") ? rate : 0, choice: choice)
        case .bonus: return choice.hasPrefix("plan:") ? .init(.bonus, choice: choice) : .init(.bonus, amount: rate)
        case .term: return .init(.term, choice: choice)
        case .benefits:
            let on = e.contractChoices(companyID: companyID, personID: personID, topic: .benefits).first { $0.id == choice }?.on ?? false
            return .init(.benefits, amount: on ? 0 : 1, choice: choice)
        case .notice: return .init(.notice, amount: Double(weeks))
        case .move: return .init(.move, choice: choice)
        }
    }

    @ViewBuilder private func preview(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        let pv = e.contractPreview(companyID: companyID, personID: personID, proposal: currentProposal(e))
        LedgerSection("What it means") { consequenceLines(pv, cur) }
    }

    @ViewBuilder private func consequenceLines(_ c: ContractTalk.Consequences, _ cur: Currency) -> some View {
        if !c.blocked.isEmpty {
            Text(c.blocked).font(.system(size: 12.5)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                FlatRow(label: "Cost a month, with employer charges", value: (c.costPerMonth >= 0 ? "+" : "") + cur.tidyShort(c.costPerMonth), tint: c.costPerMonth > 0 ? Theme.loss : Theme.ivory, rule: false)
                if let b = c.quitYearBefore, let a = c.quitYearAfter {
                    FlatRow(label: "Chance they hand in notice within a year", value: "\(Int((b * 100).rounded()))% → \(Int((a * 100).rounded()))%", tint: a > b ? Theme.loss : Theme.ivory)
                }
                if let d = c.quitYearIfDeclined { FlatRow(label: "If you decline", value: "\(Int((d * 100).rounded()))%", tint: Theme.loss) }
                ForEach(c.lines, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true) }
                ForEach(c.peers, id: \.self) { Label($0, systemImage: "person.2").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
                ForEach(c.labour, id: \.self) { Label($0, systemImage: "doc.text").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
                ForEach(c.risks, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.system(size: 11.5)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    @ViewBuilder private func send(_ e: GameEngine, _ co: Company, _ n: Person, _ cur: Currency) -> some View {
        let p = currentProposal(e)
        let pv = e.contractPreview(companyID: companyID, personID: personID, proposal: p)
        let talk = e.contractTalk(personID: personID)
        let answering = talk?.isRequest == true && talk?.proposal.topic == topic
        Button(answering ? "Answer with this offer" : "Put it to \(first(n))") {
            pending = PendingAction(
                title: answering ? "Answer \(first(n)) with this?" : "Put this to \(first(n))?",
                message: summary(pv, cur),
                button: answering ? "Send answer" : "Put it to \(first(n))") {
                    if answering { show(store.act { $0.contractRespond(companyID: companyID, personID: personID, decision: .counter(counterValue(p))) }) }
                    else { show(store.act { $0.contractPropose(companyID: companyID, personID: personID, proposal: p) }) }
                }
        }
        .buttonStyle(GoldButtonStyle())
        .disabled(!pv.blocked.isEmpty)
    }

    /// The figure that goes with a counter, in the unit of the topic.
    private func counterValue(_ p: ContractTalk.Proposal) -> Double { p.topic == .promotion || p.topic == .payRise || p.topic == .hours ? p.amount : p.amount }

    private func summary(_ c: ContractTalk.Consequences, _ cur: Currency) -> String {
        var parts = ["Cost a month: " + (c.costPerMonth >= 0 ? "+" : "") + cur.tidyShort(c.costPerMonth) + "."]
        if let b = c.quitYearBefore, let a = c.quitYearAfter { parts.append("Chance they hand in notice within a year: \(Int((b * 100).rounded()))% to \(Int((a * 100).rounded()))%.") }
        parts += c.risks
        parts += c.labour.prefix(2)
        return parts.joined(separator: " ")
    }

    private func answer(_ d: ContractTalk.Decision, _ e: GameEngine, _ n: Person, _ cur: Currency, _ pv: ContractTalk.Consequences) {
        let (title, button): (String, String) = d == .accept ? ("Agree to \(first(n))'s request?", "Agree") : d == .delay ? ("Delay your answer?", "Delay") : ("Decline \(first(n))'s request?", "Decline")
        pending = PendingAction(title: title, message: d == .decline ? summary(pv, cur) + " They feel turned down." : d == .delay ? "You have \(ContractTalk.delayWeeks) weeks to answer. If the answer does not come, it counts as a decline. " + summary(pv, cur) : summary(pv, cur),
                                button: button, destructive: d == .decline) {
            show(store.act { $0.contractRespond(companyID: companyID, personID: personID, decision: d) })
        }
    }

    private func show(_ r: ContractTalk.Reply?) {
        guard let r else { store.show("No game is loaded.", tone: "warn"); return }
        switch r {
        case .agreed(let t), .settled(let t): Haptics.success(); store.show(t, tone: "good"); reply = ""
        case .counter(let amount, _, let t):
            reply = t; Haptics.tap()
            if topic == .payRise { percent = amount } else if topic == .promotion { pay = amount }
        case .delayed(_, let t): store.show(t, tone: "n"); reply = ""
        case .declined(let t): Haptics.warning(); store.show(t, tone: "warn"); reply = ""
        case .unwilling(let t): Haptics.warning(); reply = t
        case .resigned(let t): Haptics.warning(); store.show(t, tone: "bad"); reply = ""
        case .notPossible(let t): reply = t
        }
        if let e = store.engine, let co = e.state.company(companyID), !isEmployee(co) { dismiss() }
    }

    // MARK: Defaults

    private func seed() {
        guard !seeded, let e = store.engine, let co = e.state.company(companyID) else { return }
        seeded = true
        let talk = e.contractTalk(personID: personID)
        topic = startTopic ?? talk?.proposal.topic ?? .payRise
        if let m = co.staff.first(where: { $0.id == personID }) { hours = m.weeklyHours ?? 30 }
        if let t = talk {
            if t.proposal.topic == .payRise { percent = max(0.005, t.proposal.amount) }
            if t.proposal.topic == .hours { hours = t.proposal.amount }
            if t.proposal.topic == .promotion { pay = t.proposal.amount; authority = t.proposal.terms.authority; choice = t.proposal.choice }
        }
        if talk?.proposal.topic != topic || choice.isEmpty { resetChoice() }
        else if topic == .hours { choice = talk?.proposal.choice ?? "hours" }
    }

    private func resetChoice() {
        guard let e = store.engine else { return }
        let options = e.contractChoices(companyID: companyID, personID: personID, topic: topic)
        choice = options.first?.id ?? ""
        if topic == .promotion, let ask = promotionAsk(choice) { pay = ask }
        if topic == .bonus, let co = e.state.company(companyID) { rate = co.managerID == personID ? max(0.05, co.managerProfitBonus) : max(0.02, co.staff.first { $0.id == personID }?.commissionRate ?? 0.05) }
        reply = ""
    }
}
