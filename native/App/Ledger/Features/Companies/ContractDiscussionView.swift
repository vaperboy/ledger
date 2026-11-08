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
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var personID: Int
    var startTopic: ContractTalk.Topic? = nil

    @State private var topic: ContractTalk.Topic = .payRise
    @State private var choice = ""
    @State private var percent = 0.06
    @State private var pay = 0.0
    @State private var hours = 30.0
    @State private var workPercent = 100.0
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
                contractCard(e, cur)
                topics(e)
                editor(e, co, cur)
                preview(e, co, cur)
                if !reply.isEmpty { SpeechBubble(text: reply, mine: false) }
                send(e, co, n, cur)
                if termsOpen(e) { promiseSection(e, co, n) }
                historySection(e)
            } else {
                Text("This person no longer works here.").foregroundStyle(Theme.ivoryMuted)
            }
        }
        .confirmAction($pending)
        .onAppear { seed() }
        .onChange(of: topic) { _, _ in resetChoice() }
    }

    // MARK: Who and what

    /// Bonus plans, benefits and promises open once the company has five staff or a manager; a request already on the table stays answerable.
    private func termsOpen(_ e: GameEngine) -> Bool { e.staffTermsUnlocked(companyID: companyID) }
    private func extra(_ t: ContractTalk.Topic) -> Bool { t == .bonus || t == .benefits }

    private func isEmployee(_ co: Company) -> Bool { co.managerID == personID || co.staff.contains { $0.id == personID } }
    private func first(_ n: Person) -> String { n.name.split(separator: " ").first.map(String.init) ?? n.name }

    private func header(_ e: GameEngine, _ co: Company, _ n: Person, _ cur: Currency) -> some View {
        let isManager = co.managerID == personID
        let m = co.staff.first { $0.id == personID }
        let pay = isManager ? co.managerMonthlyWage : (m?.monthlyWage ?? 0)
        let role = isManager ? "Manager" : (m.map { $0.role.prefix(1).uppercased() + $0.role.dropFirst() } ?? "")
        let hours: String = m?.weeklyHours.map { "\(Int(saturating: $0.rounded())) h a week \u{00B7} " } ?? ""
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                ThumbnailView(kind: .person, key: isManager ? "manager" : (m?.role ?? "helper"), size: 44, initials: n.name, face: n.faceKey)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(n.name.tidyText).textStyle(.headline).lineLimit(1)
                    Text("\(role) at \(co.name)".tidyText).textStyle(.caption).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            TeamHero(label: "Pay now", value: cur.tidyShort(pay), unit: "a month",
                     context: hours + (e.contractHandler(companyID: companyID).flatMap { (h) -> String? in
                        isManager ? nil : "\(h.name) may settle up to \(cur.tidyShort(h.payLimit)) a month (\(h.level >= 2 ? "free budget" : "normal budget")); above that it comes to you."
                     } ?? "Every change is agreed here."))
        }
    }

    /// Their request, or the talk you started and they answered with a counter.
    @ViewBuilder private func open(_ e: GameEngine, _ co: Company, _ n: Person, _ talk: ContractTalk.Talk, _ cur: Currency) -> some View {
        if talk.isRequest {
            let pv = e.contractPreview(companyID: companyID, personID: personID, proposal: talk.proposal, asRequest: true)
            TeamBlock("Their request") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(talk.reason.isEmpty ? "A request about \(talk.proposal.topic.title.lowercased())." : talk.reason).popupText(.body)
                    AskOfferCard(label: talk.proposal.topic.title, figure: requestFigure(talk, cur), note: "What \(first(n)) asks for", outlined: true)
                    if talk.delayUntil > 0 { Text("You said you would answer by week \(talk.delayUntil). If you do not, \(first(n)) feels turned down.").popupText(.risk) }
                    consequenceLines(pv, cur)
                    partWay(talk, cur)
                    WrapRow {
                        Button("Agree") { answer(.accept, e, n, cur, pv) }.buttonStyle(SecondaryButtonStyle(size: .compact, tint: Theme.accent))
                        if talk.delayUntil == 0 { Button("Delay \(ContractTalk.delayWeeks) weeks") { answer(.delay, e, n, cur, pv) }.buttonStyle(TertiaryButtonStyle(size: .compact, tint: Theme.inkSoft)) }
                        Button("Decline") { answer(.decline, e, n, cur, pv) }.buttonStyle(TertiaryButtonStyle(size: .compact, tint: Theme.loss))
                    }
                    if termsOpen(e) {
                        promiseMaker(e, label: "Promise instead") { draft in
                            show(store.act { $0.contractRespond(companyID: companyID, personID: personID, decision: .promise(draft)) }, "Promise instead")
                        }
                    }
                    if e.contractHandler(companyID: companyID) != nil {
                        Button("Leave it to the manager") {
                            show(store.act { $0.contractLeaveToManager(companyID: companyID, personID: personID) }, "Leave it to the manager")
                        }.buttonStyle(TertiaryButtonStyle(size: .compact, tint: Theme.inkSoft))
                    }
                }
            }
        } else if talk.proposal.amount > 0 {
            TeamBlock("\(first(n))'s last word") {
                VStack(alignment: .leading, spacing: 8) {
                    Text((talk.isFinal ? "Their final word: " : "They ask: ") + requestFigure(talk, cur)).popupText(.body)
                    partWay(talk, cur)
                    Button("Drop this talk") {
                        _ = store.act { $0.contractWithdraw(personID: personID) }
                        reply = ""
                        store.outcome(chosen: "Drop this talk", result: "Talk dropped. Nothing changes for \(first(n)).")
                    }.buttonStyle(TertiaryButtonStyle(size: .compact, tint: Theme.inkSoft))
                }
            }
        }
    }

    /// Quick counters between your last offer and their ask (a quarter, half, three quarters of the way); the editor below takes any exact figure.
    @ViewBuilder private func partWay(_ t: ContractTalk.Talk, _ cur: Currency) -> some View {
        let p = t.proposal
        if [.payRise, .promotion, .hours].contains(p.topic), p.amount > 0 {
            let from = t.offered > 0 ? t.offered : (p.topic == .hours ? p.amount : 0)
            Text("Meet them part way").popupText(.caption)
            WrapRow {
                ForEach([0.25, 0.5, 0.75], id: \.self) { share in
                    let v = from + (p.amount - from) * share
                    HireChip(title: p.topic == .payRise ? "+\(String(format: "%.1f", v * 100))%" : p.topic == .hours ? "\(Int(saturating: v.rounded())) h" : cur.tidyShort(cur.roundedStep(v, about: 500)), on: false) {
                        Haptics.choose()
                        topic = p.topic
                        switch p.topic {
                        case .payRise: percent = max(0.005, (v * 200).rounded() / 200)
                        case .promotion: pay = cur.roundedStep(v, about: 500)
                        default: hours = max(5, v.rounded()); choice = "hours"
                        }
                    }
                }
            }
            Text("Or set an exact figure below with the stepper or the field.").popupText(.caption)
        }
    }

    private func requestFigure(_ t: ContractTalk.Talk, _ cur: Currency) -> String {
        let p = t.proposal
        switch p.topic {
        case .payRise: return "+\(String(format: "%.1f", p.amount * 100))% on their pay"
        case .promotion: return "\(cur.tidyDisplay(p.amount)) a month for the new post"
        case .hours: return "\(Int(saturating: p.amount.rounded())) hours a week"
        case .payBasis: return "A fixed monthly salary"
        default: return p.topic.title
        }
    }

    // MARK: Topics and the editor

    private func topics(_ e: GameEngine) -> some View {
        let unlocked: Bool = termsOpen(e)
        let asked: ContractTalk.Topic? = e.contractTalk(personID: personID)?.proposal.topic
        let list = e.contractTopics(companyID: companyID, personID: personID).filter { unlocked || !extra($0.topic) || $0.topic == asked }
        return TeamBlock("Discuss") {
            VStack(alignment: .leading, spacing: 8) {
                WrapRow(spacing: Theme.Space.xs) {
                    ForEach(list) { t in
                        HireChip(title: t.topic.title, on: topic == t.topic) { Haptics.choose(); topic = t.topic }
                            .disabled(!t.available)
                            .opacity(t.available ? 1 : 0.45)
                    }
                }
                if let t = list.first(where: { $0.topic == topic }), !t.available { Text(t.why.tidyMoney).popupText(.risk) }
            }
        }
    }

    @ViewBuilder private func editor(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        let options = e.contractChoices(companyID: companyID, personID: personID, topic: topic)
        let isManager = co.managerID == personID
        TeamBlock(topic.title) {
            VStack(alignment: .leading, spacing: 10) {
                switch topic {
                case .payRise:
                    steps([0.03, 0.06, 0.10, 0.15], current: percent) { percent = $0 }
                    Stepper("Raise: +\(String(format: "%.1f", percent * 100))%", value: $percent, in: 0.005...0.5, step: 0.005).popupText(.body)
                case .promotion:
                    pick(options)
                    AmountField(title: "Monthly pay offered", currency: cur, amount: $pay)
                    Picker("Authority", selection: $authority) {
                        Text("Asks you first").tag(0); Text("Within limits").tag(1); Text("Full control").tag(2)
                    }.pickerStyle(.segmented)
                case .hours:
                    pick(options)
                    if choice == "percent" { percentEditor() }
                    if choice == "hours" { Stepper("\(Int(hours)) hours a week", value: $hours, in: 5...60, step: 5).popupText(.body) }
                case .payBasis:
                    pick(options)
                    if choice == "mix" || choice == "com" { steps(PayPlans.rateSteps, current: rate) { rate = $0 }; Text("Commission: \(Int(saturating: (rate * 100).rounded()))% of their sales.").popupText(.caption) }
                case .bonus:
                    if !isManager && !options.isEmpty {
                        Text("A bonus plan is paid through payroll with the employer's charges, like wages: a share for every target the company meets, a year-end bonus when the budget is met, and a reward for the better half of the team in a month without a loss.").popupText(.caption)
                        pick(options)
                        if choice == "commission" { steps(PayPlans.rateSteps, current: rate) { rate = $0 } }
                    } else {
                        Text(isManager ? "A share of each month's profit, on top of the salary. A share is not cut here." : "Their commission share of their own sales.").popupText(.caption)
                        steps(isManager ? [0.05, 0.1, 0.15, 0.2, 0.3] : PayPlans.rateSteps, current: rate) { rate = $0 }
                    }
                case .term:
                    Text("A permanent contract has no end date. A fixed term ends on its date unless you renew it; you are asked a few weeks before. Someone who wants security may not take a fixed term.").popupText(.caption)
                    pick(options)
                case .benefits:
                    pick(options)
                    if let on = options.first(where: { $0.id == choice })?.on { Text(on ? "It is on now: confirming switches it off." : "It is off now: confirming switches it on.").popupText(.caption) }
                case .notice:
                    Text("Extra weeks of notice on top of the law, owed both ways: they work them if they resign, you pay them if you let them go without cause.").popupText(.caption)
                    WrapRow {
                        ForEach([0] + ContractTalk.noticeExtraChoices, id: \.self) { w in
                            HireChip(title: w == 0 ? "Law only" : "+\(w) wk", on: weeks == w) { Haptics.choose(); weeks = w }
                        }
                    }
                case .move:
                    pick(options)
                }
            }
        }
    }

    private func steps(_ values: [Double], current: Double, _ set: @escaping (Double) -> Void) -> some View {
        WrapRow {
            ForEach(values, id: \.self) { v in
                HireChip(title: "\(Int(saturating: (v * 100).rounded()))%", on: abs(current - v) < 0.0001) { Haptics.choose(); set(v) }
            }
        }
    }

    @ViewBuilder private func pick(_ options: [ContractTalk.Choice]) -> some View {
        if options.isEmpty { Text("Nothing to choose here.").popupText(.body) }
        ForEach(Array(options.enumerated()), id: \.element.id) { n, o in
            if n > 0 { Hairline() }
            Button { choice = o.id; if topic == .promotion, let ask = promotionAsk(o.id) { pay = ask } } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(o.title.tidyMoney).popupText(.body)
                        Text(o.detail.tidyMoney).popupText(.caption)
                    }
                    Spacer()
                    LedgerGlyph(glyph: choice == o.id ? Glyph.check : Glyph.ring, size: 14, tint: choice == o.id ? Theme.accent : Theme.inkFaint)
                }.padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(PressableStyle())
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
        case .hours: return .init(.hours, amount: choice == "percent" ? workPercent : hours, choice: choice.isEmpty ? "percent" : choice)
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
        TeamBlock("What it means") { consequenceLines(pv, cur) }
    }

    @ViewBuilder private func consequenceLines(_ c: ContractTalk.Consequences, _ cur: Currency) -> some View {
        if !c.blocked.isEmpty {
            Text(c.blocked).popupText(.risk)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                costRows(c, cur)
                hoursRows(c)
                words(c)
                if c.mayRefuse {
                    Label("They may well say no to this. You find out when you put it to them.", systemImage: "exclamationmark.bubble")
                        .popupText(.risk)
                }
                ForEach(c.lines, id: \.self) { Text($0).popupText(.body) }
                notes(c)
            }
        }
    }

    private func signed(_ v: Double, _ cur: Currency) -> String { (v > 0 ? "+" : "") + cur.tidyShort(v) }

    /// Employer cost of the whole company's people before and after, the difference a month and a year, and this person's own difference.
    @ViewBuilder private func costRows(_ c: ContractTalk.Consequences, _ cur: Currency) -> some View {
        FlatRow(label: "People cost a month, with employer charges", value: "\(cur.tidyShort(c.costBefore)) \u{2192} \(cur.tidyShort(c.costAfter))", rule: false)
        FlatRow(label: "Difference", value: "\(signed(c.costPerMonth, cur)) a month", sub: "\(signed(c.costPerYear, cur)) a year", tint: c.costPerMonth > 0 ? Theme.loss : c.costPerMonth < 0 ? Theme.gain : Theme.ivory)
        if c.employerBefore != nil && c.employerAfter != nil {
            FlatRow(label: "This person, a month", value: signed(c.personMonthlyDifference, cur), sub: "\(signed(c.personAnnualDifference, cur)) a year")
        }
    }

    @ViewBuilder private func hoursRows(_ c: ContractTalk.Consequences) -> some View {
        if c.hoursBefore > 0 || c.hoursAfter > 0 {
            let d: Double = c.hoursDifference
            let diff: String = d == 0 ? "no change" : (d > 0 ? "+" : "") + HireWords.hours(d).replacingOccurrences(of: " a week", with: "")
            FlatRow(label: "Hours a week", value: "\(String(format: "%g", c.hoursBefore)) \u{2192} \(String(format: "%g", c.hoursAfter))", sub: diff)
        }
    }

    /// Payroll and operational impact and how the person may react, all in words.
    @ViewBuilder private func words(_ c: ContractTalk.Consequences) -> some View {
        if !c.payrollImpact.isEmpty { FlatRow(label: "Payroll", value: "", sub: c.payrollImpact) }
        if !c.operationalImpact.isEmpty { FlatRow(label: "The business", value: "", sub: c.operationalImpact) }
        if let after = c.quitRiskAfter {
            FlatRow(label: "How they may react", value: after.words, sub: c.quitRiskBefore.map { "Now: " + $0.words } ?? "", tint: after == .unlikely ? Theme.ivory : Theme.caution)
        }
        if let d = c.quitRiskIfDeclined { FlatRow(label: "If you decline", value: d.words, tint: d == .unlikely ? Theme.ivory : Theme.loss) }
    }

    @ViewBuilder private func notes(_ c: ContractTalk.Consequences) -> some View {
        ForEach(c.peers, id: \.self) { Label($0, systemImage: "person.2").popupText(.caption) }
        ForEach(c.labour, id: \.self) { Label($0, systemImage: "doc.text").popupText(.caption) }
        ForEach(c.risks, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").popupText(.risk) }
    }

    @ViewBuilder private func send(_ e: GameEngine, _ co: Company, _ n: Person, _ cur: Currency) -> some View {
        let p = currentProposal(e)
        let pv = e.contractPreview(companyID: companyID, personID: personID, proposal: p)
        let talk = e.contractTalk(personID: personID)
        let answering = talk?.isRequest == true && talk?.proposal.topic == topic
        let sendable: Bool = pv.blocked.isEmpty
        // The send button is pinned under the long discussion so it never scrolls out of reach.
        Color.clear.frame(height: 0)
            .popupFooter {
                VStack(spacing: Theme.Space.xs) {
                PopupOptionButton(title: answering ? "Answer with this offer" : "Put it to \(first(n))", highlighted: true) {
                    pending = PendingAction(
                        title: answering ? "Answer \(first(n)) with this?" : "Put this to \(first(n))?",
                        message: summary(pv, cur),
                        button: answering ? "Send answer" : "Put it to \(first(n))", tone: .info, icon: "doc.text") {
                            let label: String = answering ? "Send answer" : "Put it to \(first(n))"
                            if answering { show(store.act { $0.contractRespond(companyID: companyID, personID: personID, decision: .counter(counterValue(p))) }, label) }
                            else { show(store.act { $0.contractPropose(companyID: companyID, personID: personID, proposal: p) }, label) }
                        }
                }
                .disabled(!sendable).opacity(sendable ? 1 : 0.4)
                // Says why it cannot be sent right under the greyed button.
                if !sendable { Text(pv.blocked.tidyText).popupText(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
                }
            }
    }

    /// The figure that goes with a counter, in the unit of the topic.
    private func counterValue(_ p: ContractTalk.Proposal) -> Double { p.topic == .promotion || p.topic == .payRise || p.topic == .hours ? p.amount : p.amount }

    private func summary(_ c: ContractTalk.Consequences, _ cur: Currency) -> String {
        var parts = ["Cost a month: " + signed(c.costPerMonth, cur) + ", a year: " + signed(c.costPerYear, cur) + "."]
        if c.hoursBefore > 0 || c.hoursAfter > 0 { parts.append("Hours a week: \(String(format: "%g", c.hoursBefore)) to \(String(format: "%g", c.hoursAfter)).") }
        if !c.payrollImpact.isEmpty { parts.append(c.payrollImpact) }
        if !c.operationalImpact.isEmpty { parts.append(c.operationalImpact) }
        if let after = c.quitRiskAfter { parts.append("They would be " + after.words + ".") }
        if c.mayRefuse { parts.append("They may refuse.") }
        parts += c.risks
        parts += c.labour.prefix(2)
        return parts.joined(separator: " ")
    }

    private func answer(_ d: ContractTalk.Decision, _ e: GameEngine, _ n: Person, _ cur: Currency, _ pv: ContractTalk.Consequences) {
        let (title, button): (String, String) = d == .accept ? ("Agree to \(first(n))'s request?", "Agree") : d == .delay ? ("Delay your answer?", "Delay") : ("Decline \(first(n))'s request?", "Decline")
        pending = PendingAction(title: title, message: d == .decline ? summary(pv, cur) + " They feel turned down." : d == .delay ? "You have \(ContractTalk.delayWeeks) weeks to answer. If the answer does not come, it counts as a decline. " + summary(pv, cur) : summary(pv, cur),
                                button: button, tone: d == .decline ? .warning : .info, icon: "doc.text") {
            show(store.act { $0.contractRespond(companyID: companyID, personID: personID, decision: d) }, button)
        }
    }

    /// Tells the reply to what the player chose (`chosen`) in the outcome popup; a counter or an unwilling answer stays in the talk.
    private func show(_ r: ContractTalk.Reply?, _ chosen: String) {
        guard let r else { store.show("No game is loaded.", tone: "warn"); return }
        switch r {
        case .agreed(let t), .settled(let t): Haptics.success(); store.outcome(chosen: chosen, result: t); reply = ""
        case .counter(let amount, _, let t):
            reply = t; Haptics.tap()
            if topic == .payRise { percent = amount } else if topic == .promotion { pay = amount }
        case .delayed(_, let t): Haptics.tap(); store.outcome(chosen: chosen, result: t); reply = ""
        case .declined(let t): Haptics.warning(); store.outcome(chosen: chosen, result: t); reply = ""
        case .unwilling(let t): Haptics.warning(); reply = t
        case .resigned(let t): Haptics.warning(); store.outcome(chosen: chosen, result: t); reply = ""
        case .notPossible(let t): Haptics.warning(); reply = t; store.show(t, tone: "warn")
        }
        if let e = store.engine, let co = e.state.company(companyID), !isEmployee(co) { dismiss() }
    }

    // MARK: Working percentage, the current contract, promises and history

    private func percentEditor() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WrapRow {
                ForEach([20.0, 50.0, 80.0, 100.0], id: \.self) { v in
                    HireChip(title: "\(Int(v)) percent", on: abs(workPercent - v) < 0.0001) { Haptics.choose(); workPercent = v }
                }
            }
            Stepper("Other: \(HireWords.percentText(workPercent))", value: $workPercent, in: 10...100, step: 5).popupText(.body)
            Text(HireWords.hours(workPercent / 100 * StaffModel.fullWeekHours)).popupText(.caption)
        }
    }

    @ViewBuilder private func contractCard(_ e: GameEngine, _ cur: Currency) -> some View {
        if let c = e.employmentContract(companyID: companyID, personID: personID) {
            TeamBlock("Current contract") {
                VStack(alignment: .leading, spacing: 0) {
                    FlatRow(label: "Type", value: c.typeLabel, sub: c.payBasisLabel, rule: false)
                    FlatRow(label: "Working", value: HireWords.percentText(c.workingPercent), sub: HireWords.hours(c.contractedHoursPerWeek))
                    FlatRow(label: "Started", value: GameCalendar.dateString(week: c.startWeek))
                    if let end = c.endWeek { FlatRow(label: "Ends", value: GameCalendar.dateString(week: end), sub: c.renewalQuestionWeek.map { "You are asked about renewing from " + GameCalendar.dateString(week: $0) } ?? "") }
                    if !c.seasonText.isEmpty { FlatRow(label: "Season", value: c.seasonText) }
                    FlatRow(label: "Notice", value: "\(HireWords.weeksText(c.resignationNoticeWeeks)) from them", sub: "From you: \(String(format: "%g", c.employerNoticeWeeks)) weeks without cause")
                }
            }
        }
    }

    private func promiseBenefits(_ e: GameEngine) -> [PromiseMaker.Choice] {
        let plans: [ContractTalk.Choice] = e.contractChoices(companyID: companyID, personID: personID, topic: .bonus).filter { $0.id.hasPrefix("plan:") }
        let others: [ContractTalk.Choice] = e.contractChoices(companyID: companyID, personID: personID, topic: .benefits).filter { c in
            (c.id.hasPrefix("perk:") && c.id.split(separator: ":").count == 2) || c.id.hasPrefix("exp:")
        }
        return (plans + others).map { PromiseMaker.Choice(id: $0.id, title: $0.title) }
    }

    private func promiseMaker(_ e: GameEngine, label: String, _ add: @escaping (StaffPromises.Draft) -> Void) -> PromiseMaker {
        var words: [String: String] = [:]
        for k in StaffPromises.Kind.allCases { words[k.rawValue] = k.fulfilledBy }
        return PromiseMaker(kinds: StaffPromises.Kind.allCases, details: words, benefits: promiseBenefits(e), percents: [20, 50, 80, 100], current: workPercent, label: label, add: add)
    }

    /// A promise made here goes to Company > Team > Promises, where its date, status and consequences are kept.
    @ViewBuilder private func promiseSection(_ e: GameEngine, _ co: Company, _ n: Person) -> some View {
        TeamBlock("Promise") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Instead of deciding now, promise \(first(n)) something by a date. It is kept in the Promises list.").popupText(.caption)
                promiseMaker(e, label: "Make a promise") { draft in
                    show(store.act { $0.promise(companyID: companyID, personID: personID, draft: draft) }, "Make a promise")
                }
            }
        }
    }

    @ViewBuilder private func historySection(_ e: GameEngine) -> some View {
        let entries: [ContractHistory.Entry] = Array(e.contractHistory(companyID: companyID, personID: personID).reversed())
        TeamBlock("Contract history") {
            VStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty { Text("No changes yet.").popupText(.caption) }
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, h in
                    FlatRow(label: h.text, value: GameCalendar.dateString(week: h.week), rule: i > 0)
                }
            }
        }
    }

    // MARK: Defaults

    private func seed() {
        guard !seeded, let e = store.engine, let co = e.state.company(companyID) else { return }
        seeded = true
        let talk = e.contractTalk(personID: personID)
        topic = startTopic ?? talk?.proposal.topic ?? .payRise
        if !e.staffTermsUnlocked(companyID: companyID), extra(topic), talk?.proposal.topic != topic { topic = .payRise }
        if let m = co.staff.first(where: { $0.id == personID }) { hours = m.weeklyHours ?? 30 }
        if let c = e.employmentContract(companyID: companyID, personID: personID) { workPercent = max(10, min(100, c.workingPercent.rounded())) }
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
