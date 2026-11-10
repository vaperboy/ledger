import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct ElectionScreen: View {
    var e: GameEngine
    var r: CountryRead
    var back: () -> Void
    @EnvironmentObject var store: GameStore
    @State private var standing = false
    @State private var pick: String? = nil
    private let P: OutsidePalette = .ballot

    private var election: Election? { r.gov.election }
    private var citizen: GovCitizen { GovernmentBridge.citizen(e.state, r.world) }

    private var phase: Int {
        guard let el = election else { return -1 }
        switch el.status {
        case .nomination: return 0
        case .voting: return 1
        case .counted: return 2
        case .closed: return el.winner == nil ? -1 : 3
        }
    }

    var body: some View {
        Group {
            if standing {
                StandForm(e: e, r: r) { standing = false }
            } else {
                CivicPage(spacing: 18) {
                    CivicHeader(title: "Election", subtitle: "President of \(r.name)", onBack: back)
                    sheetHead
                    stateBlock
                    if let el = election, !el.candidates.isEmpty { ballotPaper(el) }
                    if let pk = pick, let el = election, el.status == .voting, let c = el.candidates.first(where: { $0.account == pk }) { voteBar(c) }
                    rules
                }
            }
        }
        .outsideScreen(.ballot)
        .accessibilityIdentifier("country-election")
    }

    private var sheetHead: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(P.ink).frame(height: 4)
            Text("OFFICIAL BALLOT").font(.system(size: 11, weight: .bold)).tracking(2.4).foregroundStyle(P.inkFaint)
            Text("Election of the president").font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
            steps
            Text(timeLine).textStyle(.body).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(P.ink).frame(height: 1)
        }
    }

    private var steps: some View {
        let names: [String] = ["Nominate", "Vote", "Count", "Result"]
        return HStack(alignment: .top, spacing: 0) {
            ForEach(0..<4, id: \.self) { (i: Int) in
                VStack(spacing: 6) {
                    ZStack {
                        Circle().strokeBorder(i <= phase ? P.accent : P.lineStrong.opacity(0.4), lineWidth: 2)
                        if i < phase || phase == 3 {
                            Circle().fill(P.accent)
                            GlyphView(glyph: Glyph.check, size: 14, weight: 2.4, tint: P.onAccent)
                        }
                        else if i == phase { Circle().fill(P.accent).frame(width: 12, height: 12) }
                    }
                    .frame(width: 28, height: 28)
                    Text(names[i]).font(.system(size: 11, weight: i == phase ? .bold : .medium)).foregroundStyle(i <= phase ? P.ink : P.inkFaint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase >= 0 ? "Step \(min(phase, 3) + 1) of 4: \(names[min(phase, 3)])" : "No election under way")
    }

    private var timeLine: String {
        guard let el = election else { return noElectionLine }
        switch el.status {
        case .nomination: return "Nominations close in \(CivicWords.weeks(max(0, el.nominateUntil - r.week))), then voting opens for \(CivicWords.weeks(Politics.votingWeeks))."
        case .voting: return "Voting closes in \(CivicWords.weeks(max(0, el.votingUntil - r.week))). The count is shown only after that."
        case .counted: return "The votes are counted. An administrator must confirm the result before the winner takes office."
        case .closed: return el.winner == nil ? noElectionLine : "The result is final."
        }
    }

    private var noElectionLine: String {
        if let o = r.gov.office { return "\(o.name) holds the office until \(CivicWords.date(o.termEnd)). A new cycle opens when the term ends." }
        return "No vote is under way. A new cycle opens soon after the last one ends."
    }

    @ViewBuilder private var stateBlock: some View {
        if let el = election {
            switch el.status {
            case .nomination: nominationBlock(el)
            case .voting: votingBlock(el)
            case .counted, .closed: resultBlock(el)
            }
        }
    }

    private func nominationBlock(_ el: Election) -> some View {
        let mine: Bool = el.candidates.contains { $0.account == r.account }
        let fee: Double = GovernmentBridge.candidacyFee(e.state, country: r.code, context: e.context)
        return VStack(alignment: .leading, spacing: 10) {
            if mine {
                Text("You are a candidate.").textStyle(.headline)
                Text("Withdrawing does not return the fee.").textStyle(.caption)
                Button("Withdraw") { withdraw() }.buttonStyle(SecondaryButtonStyle(tint: P.loss))
            } else {
                Text("Stand for president").font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
                Text("The fee is \(r.cur.tidyDisplay(fee)). It goes to the treasury and is never given back, win or lose.").textStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                let ok: Bool = Politics.mayStand(citizen, country: r.code)
                PrimaryAction(title: "Stand as a candidate", blockedReason: ok ? nil : "You cannot stand: you must live here, be at least \(Politics.candidateMinAgeWeeks) weeks into the game, and not be barred.", identifier: "election-stand") {
                    standing = true
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(P.ink, lineWidth: 1.5))
    }

    private func votingBlock(_ el: Election) -> some View {
        let voted: Bool = r.gov.hasVoted(r.account)
        let may: Bool = Politics.mayVote(citizen, country: r.code)
        return VStack(alignment: .leading, spacing: 6) {
            if voted {
                Text("Your vote is cast.").textStyle(.headline, tint: P.gain)
                Text("One account, one vote. It cannot be changed.").textStyle(.caption)
            } else if !may {
                Text("You cannot vote in this election.").textStyle(.headline, tint: P.loss)
                Text("Voters must live here, be at least \(Politics.voterMinAgeWeeks) weeks into the game, and not be barred.").textStyle(.caption)
            } else {
                Text("Mark one box.").textStyle(.headline)
                Text("Tap a candidate, then confirm. You vote once.").textStyle(.caption)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(P.ink, lineWidth: 1.5))
    }

    private func resultBlock(_ el: Election) -> some View {
        let winner: ElectionCandidate? = el.winner.flatMap { (w: String) -> ElectionCandidate? in el.candidates.first { $0.account == w } }
        return VStack(alignment: .leading, spacing: 8) {
            if let w = winner {
                Text(el.confirmed ? "Elected" : "Leads the count").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(P.accent2)
                Text(r.shown(w.name, account: w.account)).font(.system(size: 28, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
                Text(el.confirmed ? "Confirmed by an administrator. The term runs \(Government.termWeeks) weeks." : "Waiting for an administrator to confirm.")
                    .textStyle(.body)
            } else {
                Text("No winner").font(.system(size: 24, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
                Text("The office stays vacant until the next cycle.").textStyle(.body)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(P.accent2, lineWidth: 2))
    }

    private func ballotPaper(_ el: Election) -> some View {
        let counts: [String: Int] = Dictionary(uniqueKeysWithValues: (r.gov.tally() ?? []).map { ($0.account, $0.votes) })
        let total: Int = max(1, counts.values.reduce(0, +))
        let canVote: Bool = el.status == .voting && !r.gov.hasVoted(r.account) && Politics.mayVote(citizen, country: r.code)
        return VStack(alignment: .leading, spacing: 0) {
            Text("CANDIDATES").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(P.inkFaint).padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(el.candidates.enumerated()), id: \.element.account) { (i: Int, c: ElectionCandidate) in
                    if i > 0 { Rectangle().fill(P.ink).frame(height: 1) }
                    candidateRow(c, votes: counts[c.account], total: total, selectable: canVote)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(P.ink, lineWidth: 1.5))
        }
    }

    private func candidateRow(_ c: ElectionCandidate, votes: Int?, total: Int, selectable: Bool) -> some View {
        let marked: Bool = pick == c.account
        let row = HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 3).strokeBorder(P.ink, lineWidth: 2)
                if marked { GlyphView(glyph: Glyph.check, size: 22, weight: 2.6, tint: P.accent) }
            }
            .frame(width: 30, height: 30).opacity(selectable || marked ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(r.shown(c.name, account: c.account)).font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
                    if c.account == r.account { CivicTag(text: "You", tint: P.accent) }
                }
                if !c.manifesto.isEmpty { Text(c.manifesto).textStyle(.body).fixedSize(horizontal: false, vertical: true) }
                if c.promises.isEmpty {
                    Text("No promises made.").textStyle(.caption, tint: P.inkFaint)
                } else {
                    ForEach(Array(c.promises.enumerated()), id: \.offset) { (_: Int, p: CampaignPromise) in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\u{2022}").foregroundStyle(P.accent)
                            Text(CivicWords.promise(p, trades: tradeName)).textStyle(.caption, tint: P.inkSoft)
                        }
                    }
                    if !c.promisesApproved { Text("Promises are waiting for an administrator.").textStyle(.caption, tint: P.caution) }
                }
                if let v = votes {
                    HStack(spacing: 8) {
                        GeometryReader { (g: GeometryProxy) in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(P.cardDeep)
                                Rectangle().fill(P.accent).frame(width: g.size.width * CGFloat(v) / CGFloat(total))
                            }
                        }
                        .frame(height: 8)
                        Text("\(v)").font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(P.ink)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14).contentShape(Rectangle())
        return Group {
            if selectable {
                Button {
                    Haptics.choose()
                    pick = marked ? nil : c.account
                } label: { row }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(marked ? .isSelected : [])
            } else {
                row
            }
        }
    }

    private func voteBar(_ c: ElectionCandidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vote for \(r.shown(c.name, account: c.account))?").textStyle(.headline)
            Text("You can vote once and it cannot be changed. How the votes stand stays hidden until voting closes.").textStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Not yet") { pick = nil }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
                Button("Cast my vote") { cast(c) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(P.cardDeep))
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOW IT WORKS").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(P.inkFaint)
            Text("Nominations run \(CivicWords.weeks(Politics.nominationWeeks)), voting \(CivicWords.weeks(Politics.votingWeeks)), and a term is \(CivicWords.weeks(Government.termWeeks)). A candidate may make up to \(Politics.maxPromises) promises, each checked against what the office can really do. An administrator confirms promises and the result.")
                .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tradeName(_ id: String) -> String { e.data.catalog.trades[id]?.name ?? id }

    private func cast(_ c: ElectionCandidate) {
        let country: String = r.code
        let account: String = c.account
        let ok: Bool = store.govRun { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in
            try GovernmentBridge.vote(&s, country: country, for: account)
        }
        pick = nil
        guard ok else { return }
        Haptics.success()
        store.outcome(chosen: "Voted for \(r.shown(c.name, account: c.account))", result: "Your vote is cast. The count shows after voting closes.")
    }

    private func withdraw() {
        let country: String = r.code
        store.govRun { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in
            try GovernmentBridge.act(&s, country: country) { (g: inout Government, acct: String, wk: Int) -> Void in
                try g.withdraw(account: acct, week: wk)
            }
        }
    }
}

struct PromiseDraft: Equatable {
    var kind: CampaignPromise.Kind
    var on = false
    var value: Double
    var tradeID = ""

    var promise: CampaignPromise { CampaignPromise(kind: kind, value: value, tradeID: kind == .priceSupport ? tradeID : nil) }

    var title: String {
        switch kind { case .transferTax: return "Transfer tax"; case .gainsTax: return "Gains tax"; case .priceSupport: return "Price support" }
    }

    static func start(_ kind: CampaignPromise.Kind, policy: GovPolicy) -> PromiseDraft {
        func away(_ cur: Double, _ range: ClosedRange<Double>) -> Double {
            let up: Double = cur + GovPolicy.step
            return ((up <= range.upperBound + 1e-9 ? up : cur - GovPolicy.step) * 10_000).rounded() / 10_000
        }
        switch kind {
        case .transferTax: return PromiseDraft(kind: kind, value: away(policy.transferTax, GovPolicy.transferRange))
        case .gainsTax: return PromiseDraft(kind: kind, value: away(policy.gainsTax, GovPolicy.gainsRange))
        case .priceSupport: return PromiseDraft(kind: kind, value: 0.05)
        }
    }
}

struct StandForm: View {
    var e: GameEngine
    var r: CountryRead
    var done: () -> Void
    @EnvironmentObject var store: GameStore
    @State private var manifesto = ""
    @State private var drafts: [PromiseDraft]
    @State private var confirming = false
    private let P: OutsidePalette = .ballot

    init(e: GameEngine, r: CountryRead, done: @escaping () -> Void) {
        self.e = e
        self.r = r
        self.done = done
        let pol: GovPolicy = r.gov.policy
        _drafts = State(initialValue: [PromiseDraft.start(.transferTax, policy: pol), PromiseDraft.start(.gainsTax, policy: pol), PromiseDraft.start(.priceSupport, policy: pol)])
    }

    private var chosen: [CampaignPromise] { drafts.filter { $0.on }.map { $0.promise } }
    private var fee: Double { GovernmentBridge.candidacyFee(e.state, country: r.code, context: e.context) }

    private func problem(_ d: PromiseDraft) -> String? {
        Politics.realismProblem(d.promise, policy: r.gov.policy, treasury: r.gov.treasury.balance)
    }

    private var blocked: String? {
        if !Politics.mayStand(GovernmentBridge.citizen(e.state, r.world), country: r.code) { return "You cannot stand: you must live here, be far enough into the game, and not be barred." }
        for d in drafts where d.on { if let p = problem(d) { return d.title + ": " + p } }
        if e.state.cash < fee { return "You need \(r.cur.tidyDisplay(fee)) in cash." }
        return nil
    }

    var body: some View {
        CivicPage(spacing: 18) {
            CivicHeader(title: confirming ? "Confirm" : "Stand for president", subtitle: "Nomination form", onBack: { if confirming { confirming = false } else { done() } })
            if confirming { confirmPage } else { form }
        }
        .accessibilityIdentifier("country-stand")
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MANIFESTO").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(P.inkFaint)
                TextField("Say in a few words what you stand for", text: $manifesto, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 16)).foregroundStyle(P.ink)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 4).fill(P.card))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.ink, lineWidth: 1.5))
                    .onChange(of: manifesto) { _, v in if v.count > Politics.manifestoLimit { manifesto = String(v.prefix(Politics.manifestoLimit)) } }
                Text("\(manifesto.count) of \(Politics.manifestoLimit)").textStyle(.caption, tint: P.inkFaint)
            }
            Text("PROMISES, UP TO \(Politics.maxPromises)").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(P.inkFaint)
            ForEach(drafts.indices, id: \.self) { (i: Int) in promiseCard(i) }
            PrimaryAction(title: "Continue", blockedReason: blocked, identifier: "stand-continue") { confirming = true }
        }
    }

    private func promiseCard(_ i: Int) -> some View {
        let d: PromiseDraft = drafts[i]
        let err: String? = d.on ? problem(d) : nil
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $drafts[i].on) {
                Text(d.title).font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
            }
            .tint(P.accent)
            if d.on {
                HStack {
                    Text(d.kind == .priceSupport ? "Share of sales" : "Rate promised").textStyle(.body)
                    Spacer(minLength: 8)
                    CivicStepper(value: $drafts[i].value, range: range(d.kind), step: GovPolicy.step, format: CivicWords.pct1, tint: P.accent, ink: P.ink, fill: P.cardDeep)
                }
                if d.kind == .priceSupport { tradeMenu(i) }
                if let err {
                    HStack(alignment: .top, spacing: 8) {
                        GlyphView(glyph: Glyph.warning, size: 16, weight: 1.8, tint: P.loss)
                        Text(err).textStyle(.caption, tint: P.loss).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(hint(d)).textStyle(.caption, tint: P.inkFaint)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 4).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(d.on ? P.ink : P.line, lineWidth: d.on ? 1.5 : 1))
    }

    private func range(_ k: CampaignPromise.Kind) -> ClosedRange<Double> {
        switch k { case .transferTax: return GovPolicy.transferRange; case .gainsTax: return GovPolicy.gainsRange; case .priceSupport: return GovPriceSupport.percentRange }
    }

    private func hint(_ d: PromiseDraft) -> String {
        switch d.kind {
        case .transferTax: return "Now \(CivicWords.pct1(r.gov.policy.transferTax)). A term allows two steps of one point."
        case .gainsTax: return "Now \(CivicWords.pct1(r.gov.policy.gainsTax)). A term allows two steps of one point."
        case .priceSupport: return "The state adds this share of a company's weekly sales, within a budget."
        }
    }

    private func tradeMenu(_ i: Int) -> some View {
        let trades: [Trade] = e.supportTrades()
        let current: String = trades.first { $0.id == drafts[i].tradeID }?.name ?? "Choose a trade"
        return Menu {
            ForEach(trades) { (t: Trade) in
                Button(t.name) { drafts[i].tradeID = t.id }
            }
        } label: {
            HStack {
                Text(current).textStyle(.body, tint: drafts[i].tradeID.isEmpty ? P.inkFaint : P.ink)
                Spacer(minLength: 8)
                GlyphView(glyph: Glyph.chevronDown, size: 14, weight: 2, tint: P.inkFaint)
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 4).fill(P.cardDeep))
        }
    }

    private var confirmPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("If you stand").font(.system(size: 24, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
            VStack(alignment: .leading, spacing: 10) {
                line("You pay \(r.cur.tidyDisplay(fee)) now.")
                line("The fee is never returned: not if you lose, not if you withdraw.")
                line("Your name and promises go on the public ballot.")
                line(chosen.isEmpty ? "You make no promises." : "You are held to \(chosen.count) promise\(chosen.count == 1 ? "" : "s"). The number you keep is published when your term ends.")
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.ink, lineWidth: 1.5))
            CivicHoldButton(title: "stand", tint: P.accent, ink: P.ink, identifier: "stand-confirm") { submit() }
            Button("Back to the form") { confirming = false }.buttonStyle(TertiaryButtonStyle(fullWidth: true))
        }
    }

    private func line(_ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\u{2022}").foregroundStyle(P.accent)
            Text(t).textStyle(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() {
        let country: String = r.code
        let words: String = manifesto.trimmingCharacters(in: .whitespacesAndNewlines)
        let promises: [CampaignPromise] = chosen
        let fee: Double = self.fee
        let ok: Bool = store.govRun { (s: inout GameState, _: GameData, c: FinanceContext) -> Void in
            try GovernmentBridge.stand(&s, country: country, manifesto: words, promises: promises, context: c)
        }
        guard ok else { confirming = false; return }
        Haptics.success()
        store.outcome(chosen: "Stood for president", result: "You paid \(r.cur.tidyDisplay(fee)). Your name is on the ballot.")
        done()
    }
}
