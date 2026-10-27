import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// One line of a talk, as a speech bubble: theirs on the left, yours on the right (champagne).
struct SpeechBubble: View {
    var text: String
    var mine: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: mine ? 16 : 4, bottomTrailingRadius: mine ? 4 : 16, topTrailingRadius: 16, style: .continuous)
        HStack(spacing: 0) {
            if mine { Spacer(minLength: 44) }
            Text(text.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(shape.fill(mine ? Theme.goldSelected : Theme.surface))
                .overlay(shape.strokeBorder(mine ? Theme.gold : Theme.border, lineWidth: 1))
            if !mine { Spacer(minLength: 44) }
        }
    }
}

/// "THEY ASK" and "YOUR OFFER" side by side: a small-caps label, a serif figure and a note under it. The offer card is outlined in champagne.
struct AskOfferCard: View {
    var label: String
    var figure: String
    var note: String
    var noteTint: Color = Theme.ivoryMuted
    var outlined = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).capsLabel(Theme.gold)
            Text(figure).font(.serifTitle(24)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.system(size: 11.5)).foregroundStyle(noteTint).lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(outlined ? Theme.gold : Theme.border, lineWidth: 1))
    }
}

/// The Negotiation screen for a job offer. Their ask beside your offer, how patient they are, the talk as speech bubbles and "Your next move" rows
/// with what each costs a year (wages plus employer charges, from the engine). Every offer can hire at once, so each is confirmed with that cost.
/// The answer is the engine's (`GameEngine.hire`): accepted, a figure of their own, an insult, or they leave. Nothing is invented here.
struct HiringNegotiationView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var personID: Int

    private struct Line: Identifiable { let id = UUID(); var mine: Bool; var text: String }
    private struct Move: Identifiable {
        let id = UUID()
        var title: String
        var detail: String
        var cost: String
        var tint: Color
        var amount: Double?    // nil = walk away
    }

    @State private var name = ""
    @State private var roleName = ""
    @State private var lines: [Line] = []
    @State private var offer = 0.0
    @State private var lastOffer = 0.0
    @State private var counter: Double?
    @State private var isFinal = false
    @State private var offended = false
    @State private var gone = false
    @State private var hired = false
    @State private var draft = HireTermsDraft()
    @State private var pending: PendingAction?
    @State private var seeded = false

    private var first: String { name.split(separator: " ").first.map(String.init) ?? name }

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID) {
                if let a = e.applicant(personID: personID, companyID: companyID), !gone, !hired { talk(e, co, a) }
                else { ended(co, e.currency(for: co)) }
            } else {
                Text("This company is not available.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding()
            }
        }
        .appScreen(title: name.isEmpty ? "Terms" : name, subtitle: [roleName, store.engine?.state.company(companyID)?.name ?? "", "terms"].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "), tab: store.tab)
        .confirmAction($pending)
        .onAppear { seed() }
    }

    // MARK: The talk

    @ViewBuilder private func talk(_ e: GameEngine, _ co: Company, _ a: Applicant) -> some View {
        let cur: Currency = e.currency(for: co)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                cards(a, cur)
                patience(e)
                VStack(spacing: 8) { ForEach(lines) { SpeechBubble(text: $0.text, mine: $0.mine) } }
                moves(e, a, cur)
                figure(e, a, cur)
                DisclosureGroup("Contract terms \u{00B7} \(draft.summary)") {
                    HireTermsEditor(engine: e, company: co, role: a.role, draft: $draft).padding(.top, 6)
                }
                .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                if draft.isCommissionOnly {
                    Text("Commission only has no base wage, so the yearly cost cannot be shown: you pay a share of what they sell.").font(.system(size: 11.5)).foregroundStyle(Theme.caution)
                }
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
        }
    }

    private func yearly(_ monthly: Double, _ cur: Currency) -> String { cur.tidyShort(monthly * 12) }

    private func cards(_ a: Applicant, _ cur: Currency) -> some View {
        let askShown: Double = counter ?? a.askMonthly
        let askVersus: Double = a.marketMonthly > 0 ? askShown / a.marketMonthly - 1 : 0
        let askNote = HiringFigures.versusMarket(askVersus)
        let offerVersus: Double = a.marketMonthly > 0 ? offer / a.marketMonthly - 1 : 0
        let offerNote = HiringFigures.versusMarket(offerVersus)
        return HStack(spacing: 10) {
            AskOfferCard(label: counter == nil ? "THEY ASK" : "THEY WOULD TAKE", figure: yearly(askShown, cur), note: askNote.text, noteTint: askNote.tint)
            AskOfferCard(label: "YOUR OFFER", figure: yearly(offer, cur), note: offerNote.text, noteTint: offerNote.tint, outlined: true)
        }
    }

    /// How they feel, from what they have said in this talk (not a hidden number): open, listening, offended, on their last word.
    private func patience(_ e: GameEngine) -> some View {
        let t = e.hiringTalk(personID: personID, companyID: companyID)
        let level: Int
        let word: String
        let tint: Color
        if isFinal { level = 3; word = "On their last word"; tint = Theme.caution }
        else if offended { level = 2; word = "Took that badly"; tint = Theme.caution }
        else if t.isOpen || counter != nil { level = 2; word = "Listening"; tint = Theme.gold }
        else { level = 1; word = "Open to a deal"; tint = Theme.gold }
        let foot: String = isFinal ? "This is their last word: an offer below it ends the talk and they take another job."
            : "Each offer below what they would take uses up some of their patience. They may walk away, and then they are gone."
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("HOW \(first.uppercased()) FEELS").capsLabel(Theme.gold)
                Spacer()
                Text(word).font(.system(size: 12)).foregroundStyle(Theme.ivory)
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i < level ? tint : Theme.border).frame(height: 6)
                }
            }
            Text(foot).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    // MARK: Moves

    private func costText(_ e: GameEngine, _ monthly: Double, _ cur: Currency) -> String {
        if draft.isCommissionOnly { return "sales share" }
        guard let c = e.hiringYearlyCost(companyID: companyID, monthlyWage: monthly) else { return "" }
        return "\(cur.tidyShort(c.yearlyTotal))/yr"
    }

    private func moveList(_ e: GameEngine, _ a: Applicant, _ cur: Currency) -> [Move] {
        func make(_ title: String, _ detail: String, _ amount: Double, tint: Color = Theme.ivory) -> Move {
            Move(title: title, detail: detail, cost: costText(e, amount, cur), tint: tint, amount: amount)
        }
        var out: [Move] = []
        if let c = counter {
            out.append(make("Accept \(yearly(c, cur))", "They start straight away at their figure.", c, tint: Theme.caution))
            if lastOffer > 0 && lastOffer < c {
                let mid: Double = cur.roundedStep(lastOffer + (c - lastOffer) * 0.5, about: 500)
                if mid > lastOffer && mid < c { out.append(make("Meet half way at \(yearly(mid, cur))", "Between your last offer and theirs.", mid)) }
            }
            if lastOffer > 0 {
                var m = make("Stand firm at \(yearly(lastOffer, cur))", isFinal ? "It is their last word: standing firm ends the talk." : "The same offer again. They may refuse or lose patience.", lastOffer, tint: Theme.loss)
                m.cost = "risk"
                out.append(m)
            }
            out.append(Move(title: "Walk away", detail: "Leave the table. Nothing changes; they may talk again later.", cost: "none", tint: Theme.ivoryMuted, amount: nil))
        } else {
            out.append(make("Offer market pay", "\(yearly(a.marketMonthly, cur)) a year, the going rate for the job.", a.marketMonthly))
            out.append(make("Offer what they ask", "Hire at their asking pay, \(yearly(a.askMonthly, cur)) a year.", a.askMonthly, tint: Theme.caution))
            let under: Double = cur.roundedStep(a.marketMonthly * 0.9, about: 500)
            out.append(make("Open a little under market", "\(yearly(under, cur)) a year. Cheaper, but they may counter, refuse or lose patience.", under, tint: Theme.loss))
        }
        return out
    }

    @ViewBuilder private func moves(_ e: GameEngine, _ a: Applicant, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR NEXT MOVE").capsLabel(Theme.gold)
            ForEach(moveList(e, a, cur)) { m in
                Button { choose(m, e, cur) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                            Text(m.detail).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Text(m.cost).font(.system(size: 13).monospacedDigit()).foregroundStyle(m.tint).lineLimit(1)
                        GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Any figure of your own: step it or type it (a monthly wage), then offer it.
    private func figure(_ e: GameEngine, _ a: Applicant, _ cur: Currency) -> some View {
        let step: Double = cur.stepSize(about: 500)
        return VStack(alignment: .leading, spacing: 6) {
            Text("OR NAME YOUR OWN FIGURE").capsLabel(Theme.gold)
            Stepper("\(yearly(offer, cur)) a year", onIncrement: { offer += step }, onDecrement: { offer = max(step, offer - step) })
                .font(.system(size: 13)).foregroundStyle(Theme.ivory)
            DisclosureGroup("Type an exact monthly figure") { AmountField(title: "Monthly pay", currency: cur, amount: $offer) }
                .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            QuietButton(title: "Offer \(yearly(offer, cur)) a year", fullWidth: true) {
                choose(Move(title: "", detail: "", cost: "", tint: Theme.ivory, amount: offer), e, cur)
            }
        }
    }

    // MARK: Sending an offer

    private func choose(_ m: Move, _ e: GameEngine, _ cur: Currency) {
        guard let amount = m.amount else { dismiss(); return }
        offer = amount
        let cost = e.hiringYearlyCost(companyID: companyID, monthlyWage: amount)
        var message = "If \(first) accepts, they start at once"
        if draft.isCommissionOnly {
            message += " with no base wage: you pay a share of what they sell, plus employer charges on it."
        } else if let c = cost {
            message += " and the company pays \(cur.tidyShort(c.yearlyTotal)) a year with employer charges (\(cur.tidyShort(c.yearlyWages)) in wages and \(cur.tidyShort(c.yearlyOnCosts)) in charges)."
            if c.liftedToMinimum { message += " The offer is lifted to the country's minimum wage." }
        }
        message += " Terms: \(draft.summary). If not, they may name a figure of their own, take offence or lose patience."
        pending = PendingAction(title: "Offer \(yearly(amount, cur)) a year to \(first)?", message: message, button: "Make the offer") { send(amount, e, cur) }
    }

    private func send(_ amount: Double, _ e: GameEngine, _ cur: Currency) {
        let terms: Hiring.Terms = draft.terms(busyMonths: e.busyMonths(companyID: companyID))
        let pid = personID, cid = companyID
        let result: Hiring.HireResult? = store.act { $0.hire(personID: pid, companyID: cid, monthlyWage: amount, terms: terms) }
        lastOffer = amount
        lines.append(Line(mine: true, text: "I can offer \(yearly(amount, cur)) a year, \(draft.summary)."))
        let fb = HireFeedback.from(result, name: name)
        switch result {
        case .ok?:
            hired = true; Haptics.success()
            lines.append(Line(mine: false, text: "Deal. I will start straight away."))
            store.show(fb.text, tone: "good")
        case .countered(let c)?:
            counter = c.amount; isFinal = c.isFinal; offended = false; Haptics.tap()
            lines.append(Line(mine: false, text: c.isFinal ? "\(yearly(c.amount, cur)) a year is as low as I will go." : "I would take it for \(yearly(c.amount, cur)) a year."))
        case .refused?:
            offended = true; Haptics.warning()
            lines.append(Line(mine: false, text: "That is not a serious offer. Come closer to what the job pays."))
        case .walkedAway?, .taken?:
            gone = true; Haptics.warning()
            lines.append(Line(mine: false, text: result == .taken ? "I have taken another job." : "I have lost patience. I am taking another job."))
            store.show(fb.text, tone: "warn")
        case .planRefused?:
            Haptics.warning()
            lines.append(Line(mine: false, text: "I will not take the job on those terms, but I am still looking. Offer a salary or a permanent contract."))
        case nil:
            store.show(fb.text, tone: "warn")
        }
    }

    // MARK: Done

    @ViewBuilder private func ended(_ co: Company, _ cur: Currency) -> some View {
        let message: String = hired ? "\(name) has joined \(co.name)." : "\(name) is no longer on the market."
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 8) { ForEach(lines) { SpeechBubble(text: $0.text, mine: $0.mine) } }
                Text(message).font(.system(size: 14, weight: .medium)).foregroundStyle(hired ? Theme.gain : Theme.ivoryMuted)
                if hired { Text("Contract: \(draft.summary). Pay is \(lastOffer > 0 ? yearly(lastOffer, cur) + " a year" : "as agreed").").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }
                QuietButton(title: "Back to hiring", fullWidth: true) { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
        }
    }

    // MARK: Start

    private func seed() {
        guard !seeded, let e = store.engine, let a = e.applicant(personID: personID, companyID: companyID) else { return }
        seeded = true
        name = a.name
        roleName = e.data.catalog.tables.roles[a.role]?.name ?? a.role
        let cur: Currency = e.state.company(companyID).map { e.currency(for: $0) } ?? e.homeCurrency
        let t = e.hiringTalk(personID: personID, companyID: companyID)
        offer = t.lastOffer > 0 ? t.lastOffer : a.marketMonthly
        lastOffer = t.lastOffer
        if t.standingCounter > 0 { counter = t.standingCounter }
        var opening = "I would want about \(yearly(a.askMonthly, cur)) a year for this."
        if t.isOpen, t.standingCounter > 0 { opening = "We spoke before: I said \(yearly(t.standingCounter, cur)) a year." }
        lines = [Line(mine: false, text: opening)]
    }
}
