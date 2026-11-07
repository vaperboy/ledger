import SwiftUI
import GameCore
import Businesses
import Countries
import Simulation

/// Sale add-ons of a car sales company (used cars or new cars): dealer warranty, car loans through the bank and insurance at the sale.
/// For each one: the setup (partner contracts and licences with their costs and review time), then on/off, the dealer's margin and prices,
/// and a live preview of what a sale brings. The rules are in `DealerAddons` (engine); this view only reads and sets.
/// Embed it in the company's settings or customers screen for trades `usedcar` and `cardealer` (`DealerAddons.supports(company)`).
struct DealerAddonsView: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var priceStep = 1
    @State private var applying: DealerAddon?

    private static let factors: [Double] = [0.5, 1, 2]
    private static let factorNames: [String] = ["Cheaper car", "Typical car", "Dearer car"]

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        VStack(alignment: .leading, spacing: 16) {
            previewBlock(cur)
            ForEach(DealerAddon.allCases) { (a: DealerAddon) in
                addonBlock(a, cur)
            }
            recordsBlock(cur)
        }
        .centerSheet(item: $applying, title: "Apply", category: .compact, tone: .info) { (a: DealerAddon) in
            applyPopup(a, cur)
        }
    }

    // MARK: Preview

    private func previewBlock(_ cur: Currency) -> some View {
        let offers: [DealerAddonOffer] = engine.dealerAddonPreview(companyID: company.id, priceFactor: Self.factors[priceStep])
        let total: Double = offers.filter { $0.active }.reduce(0) { $0 + $1.expectedNet }
        return PageGroup(title: "Expected per sale", trailing: {
            Text(total >= 0 ? "+" + cur.tidyShort(total) : "-" + cur.tidyShort(-total)).font(.system(size: 12).monospacedDigit()).foregroundStyle(total >= 0 ? Theme.gain : Theme.loss)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                SegmentedPill(items: Array(0..<Self.factors.count), title: { (i: Int) -> String in Self.factorNames[i] }, selection: $priceStep)
                FigureStrip(items: offers.map { (o: DealerAddonOffer) -> KeyFigures.Item in
                    KeyFigures.Item(label: o.addon.title, value: o.active ? signed(o.expectedNet, cur) : "Off", tint: o.active ? (o.expectedNet >= 0 ? Theme.gain : Theme.loss) : Theme.ivoryFaint,
                                    sub: o.active ? percent(o.takeRate) + " take it" : (o.setUp ? "Switched off" : "Not set up"))
                })
                Text("Added to the margin of each car sold. Switched-off add-ons do not count. Figures are averages over many customers.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: One add-on

    private func addonBlock(_ a: DealerAddon, _ cur: Currency) -> some View {
        let setup: DealerSetupStatus? = engine.dealerAddonSetup(companyID: company.id, addon: a)
        let offer: DealerAddonOffer? = engine.dealerAddonPreview(companyID: company.id, priceFactor: Self.factors[priceStep]).first { $0.addon == a }
        return PageGroup(title: a.title, trailing: { statusLabel(setup) }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(blurb(a)).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                if let s = setup {
                    switch s.phase {
                    case .approved: controls(a, offer, cur)
                    case .inReview(let weeks): reviewLines(s, weeks, cur)
                    case .rejected(let why): rejectedLines(a, s, why, cur)
                    case .notStarted: requirementLines(a, s, cur)
                    }
                }
            }
        }
    }

    private func statusLabel(_ s: DealerSetupStatus?) -> some View {
        let text: String
        var tint: Color = Theme.ivoryFaint
        switch s?.phase {
        case .approved?: text = "Set up"; tint = Theme.gain
        case .inReview(let w)?: text = "In review, \(w) \(w == 1 ? "week" : "weeks")"; tint = Theme.gold
        case .rejected?: text = "Declined"; tint = Theme.loss
        default: text = "Not set up"
        }
        return Text(text).textStyle(.caption, tint: tint)
    }

    private func blurb(_ a: DealerAddon) -> String {
        switch a {
        case .warranty: return "Repairs after the sale are paid by you. Each warranty sets aside a reserve for the claims it is expected to bring; unused reserve is released when it ends."
        case .loan: return "A bank partner finances your customers. The loan is the bank's, not yours. The bank pays you a commission on each financed sale; a declined application can lose the sale."
        case .insurance: return "Customers take their first year of insurance with the car, cheaper than buying it separately. You earn a one-time commission on that first premium."
        }
    }

    private func requirementLines(_ a: DealerAddon, _ s: DealerSetupStatus, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(s.requirements) { (r: DealerSetupRequirement) in
                CardLine()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title + (r.isLicence ? "  (licence)" : "")).textStyle(.body)
                        Text(r.detail).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(cur.tidyShort(r.cost)).textStyle(.caption, numeric: true)
                        Text("\(r.reviewWeeks) \(r.reviewWeeks == 1 ? "week" : "weeks")").textStyle(.caption, tint: Theme.inkFaint)
                    }
                }
            }
            CardLine()
            ForEach(Array(s.conditions.enumerated()), id: \.offset) { (_: Int, c: DealerSetupCondition) in
                HStack(spacing: 6) {
                    GlyphView(glyph: c.met ? Glyph.check : Glyph.ring, size: 12, weight: 1.6, tint: c.met ? Theme.gain : Theme.loss)
                    Text(c.text).font(.system(size: 12)).foregroundStyle(c.met ? Theme.ivoryMuted : Theme.loss)
                }
            }
            HStack {
                Text("Review takes \(s.reviewWeeks) weeks. Fees are not refunded if it fails.").textStyle(.caption, tint: Theme.inkFaint)
                Spacer(minLength: 8)
                Button("Apply, " + cur.tidyShort(s.totalCost)) { Haptics.tap(); applying = a }
                    .buttonStyle(TinyButtonStyle(tint: Theme.gold)).disabled(!s.canStart)
            }
        }
    }

    private func reviewLines(_ s: DealerSetupStatus, _ weeks: Int, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(s.requirements) { (r: DealerSetupRequirement) in
                HStack {
                    Text(r.title).textStyle(.caption)
                    Spacer(minLength: 8)
                    Text("Paid").textStyle(.caption, tint: Theme.inkFaint)
                }
            }
            Text(weeks == 0 ? "The answer comes this week." : "The answer comes in \(weeks) \(weeks == 1 ? "week" : "weeks").").textStyle(.caption, tint: Theme.accent)
        }
    }

    private func rejectedLines(_ a: DealerAddon, _ s: DealerSetupStatus, _ why: String, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(why).textStyle(.caption, tint: Theme.loss).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button("Apply again, " + cur.tidyShort(s.totalCost)) { Haptics.tap(); applying = a }
                    .buttonStyle(TinyButtonStyle(tint: Theme.gold)).disabled(!s.canStart)
            }
        }
    }

    private func applyPopup(_ a: DealerAddon, _ cur: Currency) -> some View {
        let s: DealerSetupStatus? = engine.dealerAddonSetup(companyID: company.id, addon: a)
        let cost: Double = s?.totalCost ?? 0
        let weeks: Int = s?.reviewWeeks ?? 0
        return PopupBody {
            Text(a.title).popupText(.title)
            Text("Paying \(cur.tidyShort(cost)) now starts the review of the contracts and registrations. It takes \(weeks) weeks. If it fails the fees are lost and you can apply again.")
                .popupText(.body)
            PopupFooter(action: "Pay and apply", tone: .expensive, onCancel: { applying = nil }, onAction: {
                applying = nil
                let r: SettingResult? = store.act { $0.startDealerAddonSetup(companyID: company.id, addon: a) }
                store.settle(r, "Application sent. The review has started.")
            })
        }
    }

    // MARK: Controls of an approved add-on

    private func controls(_ a: DealerAddon, _ offer: DealerAddonOffer?, _ cur: Currency) -> some View {
        let set: DealerAddonSettings = engine.dealerAddonSettings(companyID: company.id) ?? DealerAddonSettings()
        let on: Bool = a == .warranty ? set.warrantyOn : (a == .loan ? set.loanOn : set.insuranceOn)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(on ? "On: offered with every sale" : "Off: not offered").font(.system(size: 13)).foregroundStyle(on ? Theme.gold : Theme.ivoryMuted)
                Spacer(minLength: 8)
                Button(on ? "Switch off" : "Switch on") {
                    Haptics.tap()
                    store.settle(store.act { $0.setDealerAddonEnabled(companyID: company.id, addon: a, on: !on) }, on ? "\(a.title) switched off." : "\(a.title) switched on.")
                }.buttonStyle(TinyButtonStyle(tint: on ? Theme.ivoryMuted : Theme.gold))
            }
            switch a {
            case .warranty: warrantyControls(set)
            case .loan: commissionStepper("Your commission on the financed amount", set.loanCommission, a, 0.005)
            case .insurance: commissionStepper("Your commission on the first-year premium", set.insuranceCommission, a, 0.01)
            }
            if let o = offer { offerLines(o, cur) }
        }
    }

    private func warrantyControls(_ set: DealerAddonSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLine()
            stepper("Included with every car", "\(set.includedMonths) months", minus: { change(included: max(0, set.includedMonths - 6)) }, plus: { change(included: set.includedMonths + 6) })
            stepper("Extension offered", "\(set.extraMonths) months", minus: { change(extra: max(0, set.extraMonths - 12)) }, plus: { change(extra: set.extraMonths + 12) })
            stepper("Extension price a year", percent(set.extraRate) + " of the car price", minus: { change(rate: max(0, set.extraRate - 0.005)) }, plus: { change(rate: set.extraRate + 0.005) })
        }
    }

    private func commissionStepper(_ label: String, _ value: Double, _ a: DealerAddon, _ step: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLine()
            stepper(label, percent(value), minus: { commission(a, value - step) }, plus: { commission(a, value + step) })
            Text(a == .loan ? "The bank takes it from the customer's rate: a higher commission means a dearer loan and fewer customers choosing it. The bank's schedule allows 1 to 3 percent."
                             : "The insurer's budget for selling is fixed: what you take is what the customer does not save. The insurer's schedule allows 10 to 20 percent.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepper(_ label: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).textStyle(.caption, tint: Theme.inkFaint)
                Text(value).textStyle(.headline, numeric: true)
            }
            Spacer(minLength: 8)
            Button { Haptics.choose(); minus() } label: { Image(systemName: "minus.circle").font(.system(size: 20)).foregroundStyle(Theme.ivoryMuted) }
                .buttonStyle(PressableStyle()).accessibilityLabel("Less: " + label)
            Button { Haptics.choose(); plus() } label: { Image(systemName: "plus.circle").font(.system(size: 20)).foregroundStyle(Theme.ivoryMuted) }
                .buttonStyle(PressableStyle()).accessibilityLabel("More: " + label)
        }
    }

    private func offerLines(_ o: DealerAddonOffer, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLine()
            Text(o.detail).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("A sale of this kind brings").textStyle(.caption)
                Spacer(minLength: 8)
                Text(signed(o.expectedNet, cur)).font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(o.expectedNet >= 0 ? Theme.gain : Theme.loss)
            }
            if o.lostSaleChance > 0 {
                Text("About \(percent(o.lostSaleChance)) of sales are lost when the bank declines the customer.").textStyle(.caption, tint: Theme.loss)
            }
        }
    }

    private func change(included: Int? = nil, extra: Int? = nil, rate: Double? = nil) {
        store.act { $0.setDealerWarranty(companyID: company.id, includedMonths: included, extraMonths: extra, extraRate: rate) }
    }

    private func commission(_ a: DealerAddon, _ v: Double) {
        store.act { $0.setDealerCommission(companyID: company.id, addon: a, rate: v) }
    }

    // MARK: Records

    private func recordsBlock(_ cur: Currency) -> some View {
        let t: DealerAddonTotals = engine.dealerAddonTotals(companyID: company.id) ?? DealerAddonTotals()
        let reserve: Double = engine.dealerWarrantyReserve(companyID: company.id)
        return PageGroup("So far") {
            VStack(alignment: .leading, spacing: 8) {
                FigureStrip(items: [
                    KeyFigures.Item(label: "Warranty reserve", value: cur.tidyShort(reserve), sub: "owed for claims"),
                    KeyFigures.Item(label: "Claims paid", value: cur.tidyShort(t.claimsPaid), sub: t.claimCount.countText("claim")),
                    KeyFigures.Item(label: "Extensions sold", value: cur.tidyShort(t.warrantyRevenue), sub: t.extendedSold.countText("sale")),
                    KeyFigures.Item(label: "Loan commission", value: cur.tidyShort(t.financeCommission), sub: t.financedSales.countText("loan")),
                    KeyFigures.Item(label: "Insurance commission", value: cur.tidyShort(t.insuranceCommission), sub: t.policies.countText("policy", plural: "policies")),
                    KeyFigures.Item(label: "Loans declined", value: "\(t.financeDeclined)", tint: t.financeDeclined > 0 ? Theme.loss : Theme.ivory),
                ])
            }
        }
    }

    // MARK: Text

    private func percent(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    private func signed(_ v: Double, _ cur: Currency) -> String { v >= 0 ? "+" + cur.tidyShort(v) : "-" + cur.tidyShort(-v) }
}

/// The add-ons as a page of their own (pushed from the Sales tab of a car dealer), reading the company again from the engine.
struct DealerAddonsPage: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), DealerAddons.supports(co) {
            ScrollView {
                DealerAddonsView(engine: e, company: co)
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .appScreen(title: "Warranty, loans, insurance", subtitle: co.name, tab: .company)
        } else {
            Text("This company has no sale add-ons.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }
}
