import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The row in Operations that opens the insurance and advisers screen, with a one-line summary of where the company stands.
struct CoverageEntryRow: View {
    var engine: GameEngine
    var company: Company

    var body: some View {
        let o = engine.coverageOverview(companyID: company.id)
        let cur = engine.currency(for: company)
        NavigationLink {
            CompanyCoverageScreen(companyID: company.id)
        } label: {
            CardRow(glyph: Glyph.reports, title: "Insurance and advisers", subtitle: summary(o, cur))
        }
        .buttonStyle(.plain)
    }

    private func summary(_ o: CoverageOverview?, _ cur: Currency) -> String {
        guard let o else { return "Policies, insurer, law firm and accountant" }
        if o.activeCount == 0 { return "Not insured. Pick an insurer, then the policies you want." }
        return "\(o.activeCount) of \(o.policies.count) policies · \(cur.tidyShort(o.weeklyPremiums * 52 / 12)) a month"
    }
}

/// Insurance policies and the three advisers of one company: insurer, law firm and accountant. Summary first, then the choices.
struct CompanyCoverageScreen: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let o = e.coverageOverview(companyID: companyID) {
            let cur = e.currency(for: co)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    MoreHeader(glyph: Glyph.reports, title: co.name, blurb: "Insurance and advisers")
                    FigureCard(items: [
                        .init(label: "Policies on", value: "\(o.activeCount) of \(o.policies.count)", tint: o.activeCount == 0 ? Theme.caution : Theme.ivory),
                        .init(label: "Premiums", value: cur.tidyShort(o.weeklyPremiums * 52 / 12), sub: "a month"),
                        .init(label: "Advisers", value: cur.tidyShort(o.lawMonthly + (o.accountant?.monthlyFee ?? 0)), sub: "a month in fees")
                    ])
                    policies(e, co, o, cur)
                    providers(e, co, o, .insurer, "Insurer", cur, empty: "No insurer yet. Policies cannot be switched on without one.")
                    providers(e, co, o, .law, "Law firm", cur, empty: "No law firm on retainer. Legal matters are handled at full cost.")
                    providers(e, co, o, .accountant, "Accountant", cur, empty: "No accountant chosen.")
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .appScreen(title: "Insurance", subtitle: "Policies, insurer, law firm and accountant", tab: .company)
            .confirmAction($pending)
            .task { store.act { $0.prepareAdvisers(companyID: companyID) } }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    // MARK: Policies

    @ViewBuilder private func policies(_ e: GameEngine, _ co: Company, _ o: CoverageOverview, _ cur: Currency) -> some View {
        CardSection("Policies") {
            VStack(alignment: .leading, spacing: 0) {
                if o.insurer == nil {
                    Text("Choose an insurer below first. Without one a policy cannot be switched on.").font(.caption).foregroundStyle(Theme.caution).padding(.bottom, 6)
                } else {
                    Text("Tap a policy to switch it on or off. The cost is shown before you confirm.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.bottom, 6)
                }
                ForEach(Array(o.policies.enumerated()), id: \.element.id) { n, p in
                    if n > 0 { CardLine() }
                    Button { toggle(p, co, cur, hasInsurer: o.insurer != nil) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                            GlyphView(glyph: p.isOn ? Glyph.check : Glyph.ring, size: 16, weight: 1.6, tint: p.isOn ? Theme.gain : Theme.ivoryFaint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text(p.blurb.tidyMoney).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(cur.tidyShort(p.weeklyPremium * 52 / 12)).font(.system(size: 13).monospacedDigit()).foregroundStyle(p.isOn ? Theme.ivory : Theme.ivoryMuted)
                                Text(p.isOn ? "a month · on" : "a month · off").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                            }
                        }.padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Text("A covered loss is paid after a deductible of about \(cur.tidyShort(cur.scaledPrice(10000))); now and then the insurer pays only part. Premiums scale with revenue (property cover with what you own) and with your insurer's price factor. Anything uninsured comes out of company cash.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
            }
        }
    }

    private func toggle(_ p: InsurancePolicyRow, _ co: Company, _ cur: Currency, hasInsurer: Bool) {
        let id = companyID
        let name = p.name
        let run: () -> Void = {
            switch store.act({ $0.toggleInsurancePolicy(companyID: id, product: p.id) }) {
            case .done?: Haptics.success(); store.show(p.isOn ? "\(name) switched off." : "\(name) is on. It costs about \(cur.tidyShort(p.weeklyPremium * 52 / 12)) a month.", tone: p.isOn ? "n" : "good")
            case .needInsurer?: Haptics.warning(); store.show("Choose an insurer first.", tone: "warn")
            default: Haptics.warning(); store.show("That policy could not be changed.", tone: "warn")
            }
        }
        if p.isOn {
            pending = PendingAction(title: "Switch off \(name)?", message: "You save about \(cur.tidyShort(p.weeklyPremium * 52 / 12)) a month, but losses of this kind are no longer covered and come out of company cash.", button: "Switch off", run: run)
        } else if !hasInsurer {
            Haptics.warning(); store.show("Choose an insurer first.", tone: "warn")
        } else {
            pending = PendingAction(title: "Switch on \(name)?", message: "\(p.blurb) Costs about \(cur.tidyShort(p.weeklyPremium * 52 / 12)) a month from company cash, starting this week, until you switch it off.", button: "Switch on", run: run)
        }
    }

    // MARK: Providers

    @ViewBuilder private func providers(_ e: GameEngine, _ co: Company, _ o: CoverageOverview, _ kind: Advisers.Kind, _ title: String, _ cur: Currency, empty: String) -> some View {
        let current: AdviserOption? = currentAdviser(kind, o)
        let choices = e.adviserChoices(companyID: companyID, kind: kind)
        CardSection(title) {
            VStack(alignment: .leading, spacing: 0) {
                if let current {
                    Text("Now: \(current.name)").font(.system(size: 13)).foregroundStyle(Theme.ivory).padding(.bottom, 4)
                } else {
                    Text(empty).font(.caption).foregroundStyle(Theme.ivoryMuted).padding(.bottom, 4)
                }
                if choices.isEmpty {
                    Text("No \(title.lowercased()) is on offer in this country right now.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                }
                ForEach(Array(choices.enumerated()), id: \.element.id) { n, a in
                    if n > 0 { CardLine() }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Text(detail(a, cur)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        if a.isCurrent { Chip(text: "Yours", tint: Theme.gain) }
                        else { Button(current == nil ? "Hire" : "Switch") { hire(a, current, cur) }.buttonStyle(QuietButtonStyle()) }
                    }.padding(.vertical, 9)
                }
                if current != nil, kind != .accountant {
                    CardLine()
                    Button("Drop \(title.lowercased())") { drop(kind, title, current!, cur) }.buttonStyle(QuietButtonStyle(tint: Theme.loss)).padding(.top, 8)
                }
            }
        }
    }

    private func currentAdviser(_ kind: Advisers.Kind, _ o: CoverageOverview) -> AdviserOption? {
        switch kind {
        case .insurer: return o.insurer
        case .law: return o.lawFirm
        default: return o.accountant
        }
    }

    private func detail(_ a: AdviserOption, _ cur: Currency) -> String {
        var parts = [String(format: "rated %.1f", a.rating)]
        if let r = a.reviews { parts.append("\(r) reviews") }
        if a.kind == .insurer {
            if let f = a.premiumFactor { parts.append(f < 1 ? "premiums \(Int(((1 - f) * 100).rounded()))% under standard" : f > 1 ? "premiums \(Int(((f - 1) * 100).rounded()))% over standard" : "standard premiums") }
            if let p = a.payoutReliability { parts.append("pays claims in full \(Int((p * 100).rounded()))% of the time") }
        } else {
            parts.append("\(cur.tidyShort(a.monthlyFee)) a month")
            if let e = a.errorRate { parts.append("books wrong \(Int((e * 100).rounded()))% of the time") }
        }
        if a.ownFirmID != nil { parts.append("your own firm") }
        return parts.joined(separator: " · ")
    }

    private func hire(_ a: AdviserOption, _ current: AdviserOption?, _ cur: Currency) {
        let id = companyID
        let cost = a.kind == .insurer ? "Premiums change with the insurer's price factor." : "\(cur.tidyShort(a.monthlyFee)) a month from company cash."
        let verb = current == nil ? "Hire" : "Switch to"
        pending = PendingAction(title: "\(verb) \(a.name)?", message: cost + (current != nil ? " \(current!.name) is dropped." : "") + (a.ownFirmID != nil ? " Your fees go to your own firm." : ""), button: current == nil ? "Hire" : "Switch") {
            let r = store.act { (e: inout GameEngine) -> Advisers.Result in
                if let firm = a.ownFirmID { return e.chooseOwnAdviser(companyID: id, kind: a.kind, firmID: firm) }
                return e.chooseAdviser(companyID: id, kind: a.kind, providerID: a.id)
            }
            if r == .done { Haptics.success(); store.show("\(a.name) hired.", tone: "good") }
            else { Haptics.warning(); store.show("That provider is no longer available.", tone: "warn") }
        }
    }

    private func drop(_ kind: Advisers.Kind, _ title: String, _ current: AdviserOption, _ cur: Currency) {
        let id = companyID
        let tail = kind == .insurer ? " Policies stay switched on but are no longer backed by a named insurer: claims are paid less reliably (93%) and at standard premiums." : " You save the monthly fee, and legal matters cost more."
        pending = PendingAction(title: "Drop \(current.name)?", message: "The \(title.lowercased()) leaves.\(tail)", button: "Drop", destructive: true) {
            if store.act({ $0.chooseAdviser(companyID: id, kind: kind, providerID: 0) }) == .removed { store.show("\(current.name) dropped.", tone: "n") }
            else { store.show("Could not drop it.", tone: "warn") }
        }
    }
}
