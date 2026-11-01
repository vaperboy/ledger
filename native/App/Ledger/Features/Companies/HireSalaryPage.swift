import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// PAGE 2 of the hiring flow: the salary negotiation. Your offer, their ask (only once they have named it: "Hear their ask", or a counter-offer), the
/// market pay (the button "Offer market pay"), the actual hourly wage and the total annual employer cost of the offer, live. The numbers come from the
/// engine's `hireSalaryTalk`, computed by the code that books the hire, so what is shown is what is applied. The answer to an offer is the engine's
/// (`hireOffer`): hired, a figure of their own, a refusal, or they walk away.
struct HireSalaryPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var request: HireRequest
    @ObservedObject var model: HireFlowModel
    /// The terms of page 1 as they stand now.
    var termsOf: () -> Hiring.Terms
    var commissionOnly: Bool
    @State private var pending: PendingAction?

    private var hourFactor: Double { StaffModel.fullWeekHours * 52 / 12 }
    private var first: String { HireWords.first(store.engine?.state.people[request.personID]?.name ?? "They") }

    var body: some View {
        Group {
            if let e = store.engine, let person = e.state.people[request.personID] {
                if model.hired || model.gone { ended(e, person) } else if person.employerID != 0 { gone(person) } else { talk(e, person) }
            } else {
                Text("This person is no longer on the market.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding()
            }
        }
        .appScreen(title: store.engine?.state.people[request.personID]?.name ?? "Salary", subtitle: "\(request.roleTitle) \u{00B7} salary", tab: store.tab)
        .confirmAction($pending)
    }

    // MARK: The talk

    private func currency(_ e: GameEngine) -> Currency {
        if let id = request.companyID, let co = e.state.company(id) { return e.currency(for: co) }
        return e.homeCurrency
    }

    private func salaryTalk(_ e: GameEngine) -> HireSalaryTalk? {
        e.hireSalaryTalk(post: request.post, companyID: request.companyID, chainID: request.chainID, personID: request.personID, terms: termsOf(), offer: model.offerSet ? model.offer : nil)
    }

    @ViewBuilder private func talk(_ e: GameEngine, _ person: Person) -> some View {
        let cur: Currency = currency(e)
        if let t = salaryTalk(e) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    figures(t, cur)
                    if !model.lines.isEmpty { VStack(spacing: 8) { ForEach(model.lines) { SpeechBubble(text: $0.text, mine: $0.mine) } } }
                    moves(e, t, cur)
                    ownFigure(e, t, cur)
                    costBreakdown(t, cur)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        } else {
            Text("\(first) is no longer on the market.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding()
        }
    }

    // MARK: Your offer, their ask, market pay

    private func yearlyLine(_ b: EmployerCost.Breakdown, _ cur: Currency) -> String {
        "\(cur.tidyShort(b.grossAnnualWage)) a year at \(HireWords.percentText(b.workingPercentage * 100))"
    }

    private func figures(_ t: HireSalaryTalk, _ cur: Currency) -> some View {
        let yours: String = HireWords.hourly(t.hourlyWage, cur) + " an hour"
        let market: String = HireWords.hourly(t.marketHourlyWage, cur) + " an hour"
        return VStack(alignment: .leading, spacing: 10) {
            Card(padding: 14, radius: Theme.Radius.hero) {
                VStack(alignment: .leading, spacing: 0) {
                    FlatRow(label: "Your offer", value: yours, sub: yearlyLine(t.employerCost, cur), tint: Theme.gold, rule: false)
                    askRow(t, cur)
                    FlatRow(label: "Market pay", value: market, sub: yearlyLine(t.marketEmployerCost, cur))
                }
            }
            if t.liftedToMinimum { Text("Your offer is lifted to the country's minimum wage.").font(.system(size: 11.5)).foregroundStyle(Theme.caution) }
            Text("How \(first) feels: \(t.mood)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            if t.theirAsk != nil {
                ForEach(t.reasons, id: \.self) { Text($0).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    @ViewBuilder private func askRow(_ t: HireSalaryTalk, _ cur: Currency) -> some View {
        if let b = t.askEmployerCost {
            FlatRow(label: "Their ask", value: HireWords.hourly(b.grossHourlyWage, cur) + " an hour", sub: yearlyLine(b, cur), tint: Theme.caution)
        } else {
            FlatRow(label: "Their ask", value: "Not said yet", sub: "They name it when you ask, or when they answer an offer.", tint: Theme.ivoryFaint)
        }
    }

    // MARK: Moves

    @ViewBuilder private func moves(_ e: GameEngine, _ t: HireSalaryTalk, _ cur: Currency) -> some View {
        LedgerSection("Your next move") {
            VStack(alignment: .leading, spacing: 8) {
                if t.theirAsk == nil {
                    move("Hear their ask", "They tell you what they expect for these terms.", id: "hire-hear-ask") { hearAsk(e, t, cur) }
                }
                move(t.marketPayLabel, "\(HireWords.hourly(t.marketHourlyWage, cur)) an hour, the going rate for the post.", id: "hire-offer-market") { choose(t.marketPay, t, e, cur) }
                if t.canOfferTheirAsk, let ask = t.theirAsk {
                    move("Offer what they ask", "Hire at \(HireWords.hourly(ask / hourFactor, cur)) an hour.", id: "hire-offer-ask") { choose(ask, t, e, cur) }
                }
                move("Walk away", "Leave the table. Nothing changes; they may talk again later.", id: "hire-walk-away") { dismiss() }
            }
        }
    }

    private func move(_ title: String, _ detail: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier(id)
    }

    /// Any figure of your own: step it or type it (a monthly wage for a full week), then offer it.
    private func ownFigure(_ e: GameEngine, _ t: HireSalaryTalk, _ cur: Currency) -> some View {
        let step: Double = cur.stepSize(about: 500)
        let shown: Double = model.offerSet ? model.offer : t.yourOffer
        return LedgerSection("Or name your own figure") {
            VStack(alignment: .leading, spacing: 8) {
                Stepper("\(HireWords.hourly(shown / hourFactor, cur)) an hour", onIncrement: { model.offer = shown + step; model.offerSet = true },
                        onDecrement: { model.offer = max(step, shown - step); model.offerSet = true })
                    .font(.system(size: 13)).foregroundStyle(Theme.ivory)
                DisclosureGroup("Type an exact monthly figure for a full week") {
                    AmountField(title: "Monthly pay", currency: cur, amount: Binding(get: { shown }, set: { model.offer = $0; model.offerSet = true }))
                }
                .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                if let why = t.termsProblem { Text(why).font(.system(size: 12)).foregroundStyle(Theme.caution) }
                QuietButton(title: "Offer \(HireWords.hourly(shown / hourFactor, cur)) an hour", fullWidth: true) { choose(shown, t, e, cur) }
                    .accessibilityIdentifier("hire-make-offer")
            }
        }
    }

    // MARK: What it costs

    @ViewBuilder private func costBreakdown(_ t: HireSalaryTalk, _ cur: Currency) -> some View {
        let b: EmployerCost.Breakdown = t.employerCost
        let totalValue: String = commissionOnly ? "Sales share" : cur.tidyShort(t.annualEmployerCost)
        let monthly: String = cur.tidyShort(t.monthlyEmployerCost) + " a month"
        let totalSub: String = commissionOnly ? "No base wage: you pay a share of what they sell." : monthly
        LedgerSection("What it costs you") {
            VStack(alignment: .leading, spacing: 0) {
                FlatRow(label: "Gross wages a year", value: cur.tidyShort(b.grossAnnualWage), sub: "\(HireWords.hours(t.hoursPerWeek)), \(HireWords.percentText(t.workingPercent))", rule: false)
                FlatRow(label: "Employer taxes and contributions", value: cur.tidyShort(b.employerTaxesAndContributions * 12))
                if b.insurance > 0 { FlatRow(label: "Insurance", value: cur.tidyShort(b.insurance * 12)) }
                if b.paidLeaveCover > 0 { FlatRow(label: "Paid leave cover", value: cur.tidyShort(b.paidLeaveCover * 12)) }
                if b.benefits + b.otherCosts > 0 { FlatRow(label: "Benefits and other costs", value: cur.tidyShort((b.benefits + b.otherCosts) * 12)) }
                FlatRow(label: "Total employer cost a year", value: totalValue, sub: totalSub, tint: Theme.gold)
            }
        }
    }

    // MARK: Actions

    private func hearAsk(_ e: GameEngine, _ t: HireSalaryTalk, _ cur: Currency) {
        let pid = request.personID
        let post = request.post, cid = request.companyID, chain = request.chainID
        let terms = termsOf()
        let amount: Double? = store.act { $0.hearTheirAsk(post: post, companyID: cid, chainID: chain, personID: pid, terms: terms) } ?? nil
        guard let amount else { store.show("\(first) is no longer on the market.", tone: "warn"); return }
        Haptics.tap()
        model.lines.append(HireLine(mine: false, text: "I would want about \(HireWords.hourly(amount / hourFactor, cur)) an hour for this."))
    }

    private func choose(_ amount: Double, _ t: HireSalaryTalk, _ e: GameEngine, _ cur: Currency) {
        model.offer = amount; model.offerSet = true
        let b = e.hireSalaryTalk(post: request.post, companyID: request.companyID, chainID: request.chainID, personID: request.personID, terms: termsOf(), offer: amount)
        let totalCost: Double = b?.annualEmployerCost ?? t.annualEmployerCost
        let annual: String = commissionOnly ? "a share of what they sell" : cur.tidyShort(totalCost) + " a year in total employer cost"
        let hourly: String = HireWords.hourly(b?.hourlyWage ?? t.hourlyWage, cur)
        var message: String = "If \(first) accepts, they start at once at \(hourly) an hour; the company pays \(annual)."
        if b?.liftedToMinimum == true { message += " The offer is lifted to the country's minimum wage." }
        message += " If not, they may name a figure of their own, take offence or lose patience."
        pending = PendingAction(title: "Offer \(hourly) an hour to \(first)?", message: message, button: "Make the offer") { send(amount, cur) }
    }

    private func send(_ amount: Double, _ cur: Currency) {
        let post = request.post, cid = request.companyID, chain = request.chainID, city = request.city, pid = request.personID
        let terms = termsOf()
        let result: HireOutcome? = store.act { $0.hireOffer(post: post, companyID: cid, chainID: chain, city: city, personID: pid, monthlyWage: amount, terms: terms) }
        guard let result else { store.show("No game is loaded.", tone: "warn"); return }
        let name: String = store.engine?.state.people[pid]?.name ?? first
        let said = HireOutcomeWords.line(result, name: name, cur: cur, hourFactor: hourFactor)
        model.lines.append(HireLine(mine: true, text: "I can offer \(HireWords.hourly(amount / hourFactor, cur)) an hour."))
        model.lines.append(HireLine(mine: false, text: said.text))
        switch result {
        case .hired:
            model.hired = true; model.closing = "\(name) has joined as \(request.roleTitle.lowercased())."
            Haptics.success(); store.show(model.closing, tone: "good"); request.onHired()
        case .countered: Haptics.tap()
        case .refused, .termsRefused, .blocked: Haptics.warning(); if case .blocked = result { store.show(said.text, tone: "warn") }
        case .walkedAway, .taken:
            model.gone = true; model.closing = said.text; Haptics.warning(); store.show(said.text, tone: "warn")
        }
    }

    // MARK: Ended

    private func gone(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(first) has taken another job.").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivoryMuted)
            QuietButton(title: "Done", fullWidth: true) { model.finished = true }
        }
        .padding(Theme.Space.margin)
    }

    private func ended(_ e: GameEngine, _ person: Person) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(spacing: 8) { ForEach(model.lines) { SpeechBubble(text: $0.text, mine: $0.mine) } }
                Text(model.closing).font(.system(size: 14, weight: .medium)).foregroundStyle(model.hired ? Theme.gain : Theme.ivoryMuted)
                QuietButton(title: "Done", fullWidth: true) { model.finished = true }.accessibilityIdentifier("hire-done")
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
        }
    }
}
