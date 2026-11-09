import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

private struct PurposeHeader: View {
    var glyph: String
    var title: String
    var note: String = ""
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            LedgerGlyph(glyph: glyph, size: Theme.Icon.medium, tint: tint)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).textStyle(.headline)
                if !note.isEmpty { Text(note).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ConsequenceNote: View {
    var cost: String
    var benefit: String
    var risk: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            line(Glyph.cost, "Cost", cost, Theme.inkSoft)
            line(Glyph.market, "Benefit", benefit, Theme.gain)
            line(Glyph.warning, "Risk", risk, Theme.warn)
        }
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Hairline() }
    }

    private func line(_ glyph: String, _ label: String, _ text: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            LedgerGlyph(glyph: glyph, size: Theme.Icon.small, tint: tint).padding(.top, 1)
            (Text(label + "  ").font(.system(size: 11.5, weight: .semibold)).foregroundColor(tint)
             + Text(text).font(.system(size: 11.5)).foregroundColor(Theme.ivoryMuted))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GoalsBlock<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Hairline() }
    }
}

struct CompanyTargetsCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    private static let names = ["rev": "Sales", "profit": "Profit", "rating": "Rating", "util": "How busy", "aware": "Awareness"]
    private func value(_ key: String, _ v: Double, _ cur: Currency) -> String { key == "rev" || key == "profit" ? cur.tidyShort(v) : String(format: "%.0f", v) }
    private func share(_ now: Double, _ target: Double) -> Double { target > 0 ? min(1, max(0, now / target)) : 0 }

    private func setterNote(_ st: ManagerTargets.Status) -> String { st.setter.isOwner ? "set by you" : "set by \(st.setter.title.lowercased())" }

    private func directionNote(_ st: ManagerTargets.Status) -> String {
        guard let key = st.direction, let d = ManagerModel.Direction(rawValue: key) else {
            return "No direction given: the targets are a fair aim from last year and the market."
        }
        return "Direction: \(d.title). The targets lean that way. " + d.text
    }

    var body: some View {
        if let st = engine.targetStatus(companyID: company.id) {
            let cur = engine.currency(for: company)
            TeamGroup(title: "Goals", trailing: {
                Text(setterNote(st)).textStyle(.caption, tint: Theme.inkFaint)
            }) {
                monthCard(st, cur)
                budgetCard(st, cur)
                historyCard(st, cur)
            }
        }
    }

    private func monthCard(_ st: ManagerTargets.Status, _ cur: Currency) -> some View {
        GoalsBlock {
            VStack(alignment: .leading, spacing: 12) {
                PurposeHeader(glyph: Glyph.goals, title: "This month", note: "Where each target stands")
                Text(directionNote(st)).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                if st.standing.isEmpty {
                    Text("No targets this month yet.").textStyle(.body, tint: Theme.inkSoft)
                }
                ForEach(st.standing, id: \.key) { s in standingRow(s, cur) }
            }
        }
    }

    private func standingRow(_ s: ManagerTargets.Standing, _ cur: Currency) -> some View {
        let tint: Color = s.onTrack ? Theme.gain : Theme.caution
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.names[s.key] ?? s.key).textStyle(.body, tint: Theme.ink)
                Spacer(minLength: 8)
                Text("\(value(s.key, s.now, cur)) of \(value(s.key, s.target, cur))").textStyle(.caption, tint: tint, numeric: true)
                GlyphView(glyph: s.onTrack ? Glyph.check : Glyph.clock, size: 13, weight: 1.8, tint: tint)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(tint).frame(width: max(3, g.size.width * CGFloat(share(s.now, s.target))))
                }
            }.frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func budgetCard(_ st: ManagerTargets.Status, _ cur: Currency) -> some View {
        if let b = st.budget {
            GoalsBlock {
                VStack(alignment: .leading, spacing: 12) {
                    PurposeHeader(glyph: Glyph.reports, title: "Budget \(b.year)", note: b.by.isEmpty ? "The year's aim" : "Drafted by \(b.by)")
                    RateBar(label: "Sales", fraction: share(b.doneRev, b.rev))
                    Text("\(cur.tidyShort(b.doneRev)) of \(cur.tidyShort(b.rev))").textStyle(.caption, tint: Theme.inkFaint, numeric: true)
                    RateBar(label: "Profit", fraction: share(b.doneProfit, b.profit), tint: b.doneProfit < 0 ? Theme.loss : Theme.gold)
                    Text("\(cur.tidyShort(b.doneProfit)) of \(cur.tidyShort(b.profit))").textStyle(.caption, tint: b.doneProfit < 0 ? Theme.loss : Theme.inkFaint, numeric: true)
                    if b.approved {
                        HStack(spacing: 6) {
                            GlyphView(glyph: Glyph.check, size: 13, weight: 1.8, tint: Theme.gain)
                            Text("Approved").textStyle(.caption, tint: Theme.gain)
                        }
                    } else {
                        approval(b, cur)
                    }
                }
            }
        }
    }

    private func approval(_ b: ManagerTargets.Status.Budget, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLine()
            Text("Waiting for your approval. These become the numbers the manager is judged on this year.")
                .textStyle(.caption, tint: Theme.warn, weight: .medium).fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Approve the yearly budget") {
                if store.act({ $0.approveBudget(companyID: company.id) }) == true {
                    Haptics.success()
                    store.outcome(chosen: "Approve the yearly budget", result: "Budget \(b.year) approved: sales \(cur.tidyShort(b.rev)), profit \(cur.tidyShort(b.profit)).")
                } else {
                    Haptics.warning()
                    store.show("The budget could not be approved now.", tone: "warn")
                }
            }
            .accessibilityIdentifier("approve-yearly-budget")
        }
    }

    @ViewBuilder private func historyCard(_ st: ManagerTargets.Status, _ cur: Currency) -> some View {
        if !st.log.isEmpty {
            GoalsBlock {
                VStack(alignment: .leading, spacing: 10) {
                    PurposeHeader(glyph: Glyph.calendar, title: "Last months", note: "Targets met each month, oldest first")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], alignment: .leading, spacing: 10) {
                        ForEach(Array(st.log.enumerated()), id: \.offset) { _, l in monthPips(l) }
                    }
                }
            }
        }
    }

    private func monthPips(_ l: ManagerTargets.Status.LogLine) -> some View {
        let tint: Color = l.met == 3 ? Theme.gain : l.met == 0 ? Theme.loss : Theme.caution
        return VStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i < l.met ? tint : Theme.hairline).frame(width: 12, height: 18)
                }
            }
            Text("\(l.met) of 3").font(.system(size: 10.5)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct CompanyPerksPopup: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var onClose: () -> Void

    private func recipientLine(_ r: CompanyCarPerk.Recipient, _ cur: Currency) -> String {
        let role = r.role == "Manager" ? "manager" : "team lead"
        guard let car = r.carName else { return "\(r.name) · \(role) · car arrives next week" }
        return "\(r.name) · \(role) · \(car), lease \(cur.tidyShort(r.monthlyLease)) a month"
    }

    private func fewer(_ p: StaffPerks.Perk) -> String {
        let f: Double = 1 - p.quitFactor
        return f >= 0.2 ? "much fewer" : f >= 0.1 ? "fewer" : "slightly fewer"
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let cur: Currency = e.currency(for: co)
            let total: Double = e.staffPerksMonthlyTotal(companyID: companyID)
            VStack(alignment: .leading, spacing: 10) {
                Text(total > 0 ? "\(cur.tidyShort(total)) a month for everyone who works here." : "A perk is for every worker and starts the moment you switch it on.")
                    .popupText(.subtitle)
                VStack(spacing: 0) { perkRows(e, co, cur) }
            }
            .centerSheetTitle("Perks")
        } else {
            Color.clear.onAppear { onClose() }
        }
    }

    @ViewBuilder private func perkRows(_ e: GameEngine, _ co: Company, _ cur: Currency) -> some View {
        let options: [StaffPerks.Perk] = e.staffPerkOptions
        ForEach(Array(options.enumerated()), id: \.element.id) { n, p in
            if n > 0 { CardLine() }
            perkRow(e, co, p, cur)
        }
    }

    private func perkRow(_ e: GameEngine, _ co: Company, _ p: StaffPerks.Perk, _ cur: Currency) -> some View {
        let on: Bool = e.staffPerkIsOn(companyID: companyID, perk: p.id)
        let cost: String = cur.tidyShort(e.staffPerkMonthlyCost(companyID: companyID, perk: p.id))
        let costLine: String = on ? "Costs \(cost) a month while it is on" : "Would cost \(cost) a month"
        let binding = Binding<Bool>(get: { on }, set: { _ in toggle(p, cur) })
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).popupText(.button)
                    Text(p.detail.tidyMoney).popupText(.caption)
                    Text(costLine + " · " + fewer(p) + " people leave").popupText(on ? .effect : .caption)
                }
                Spacer(minLength: 8)
                LedgerSwitch(isOn: binding)
                    .accessibilityIdentifier("perk-" + p.id)
            }
            if p.id == "car" && on {
                ForEach(e.companyCarRecipients(companyID: companyID)) { r in
                    Text(recipientLine(r, cur)).popupText(.caption)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func toggle(_ p: StaffPerks.Perk, _ cur: Currency) {
        let r = store.act { $0.toggleStaffPerk(companyID: companyID, perk: p.id) } ?? nil
        Haptics.tap()
        if r == true {
            let cost: String = cur.tidyShort(store.engine?.staffPerkMonthlyCost(companyID: companyID, perk: p.id) ?? 0)
            store.show("\(p.name) is on for everyone: \(cost) a month.", tone: "good")
        } else if r == false {
            store.show("\(p.name) switched off.", tone: "n")
        } else {
            Haptics.warning()
            store.show("Not possible right now.", tone: "warn")
        }
    }
}

struct SuccessorSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        let waiting = engine.successorCandidates(companyID: company.id)
        let fee: String = cur.tidyShort(ManagerModel.searchFee(currency: cur))
        VStack(alignment: .leading, spacing: 10) {
            PurposeHeader(glyph: Glyph.search, title: "Succession", note: waiting.isEmpty ? "Find someone before they leave" : "Candidates for the handover")
            if waiting.isEmpty {
                ConsequenceNote(cost: "the executive search fee, \(fee).",
                                benefit: "four candidates to choose from before the handover, so the company is not left without a manager.",
                                risk: "none may suit, and the fee is not refunded.")
                QuietButton(title: "Find a successor · \(fee)…", fullWidth: true) { askToSearch(cur) }
            } else {
                CandidateHireList(people: waiting.filter { $0.employerID == 0 }, emptyText: "Everyone on the list has taken another job. Search again.") { p in
                    let request = HireRequest(post: .manager, companyID: company.id, personID: p.id, roleTitle: "Manager")
                    CandidateHireRow(person: p, currency: cur, subtitle: CandidateClaims.line(engine, p), market: engine.goingRate(for: .manager, companyID: company.id), request: request, roleKey: "manager") {
                        ManagerCandidateChecks(person: p, companyID: company.id, currency: cur)
                    }
                }
            }
        }
        .confirmAction($pending)
    }

    private func askToSearch(_ cur: Currency) {
        let feeAmount: Double = ManagerModel.searchFee(currency: cur)
        let fee: String = cur.tidyShort(feeAmount)
        pending = PendingAction(title: "Start the search?", message: "Three people from the trade and one generalist. The list stays for about six months.", button: "Pay \(fee) and search",
                                amount: feeAmount, currency: cur, risk: "None may suit, and the fee is not refunded.", tone: .info, icon: "magnifyingglass") {
            if let list = store.act({ $0.findSuccessor(companyID: company.id) }) ?? nil, !list.isEmpty { Haptics.success(); store.show("\(list.count) candidates found. Search paid: \(fee).", tone: "good") }
            else { Haptics.warning(); store.show("The search found no one, or the company cannot pay \(fee).", tone: "warn") }
        }
    }
}
