import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// A met or missed requirement of a brand: the title, what is needed and what the dealership has.
struct CarStandardRow: View {
    var standard: CarBrandContract.Standard
    var rule = true

    var body: some View {
        FlatRow(label: standard.title, value: standard.have + " of " + standard.need, sub: standard.ok ? "Met" : "Not met",
                tint: standard.ok ? Theme.gain : Theme.loss, rule: rule)
    }
}

/// Brand contracts of a vehicle dealership: the brands on offer with their terms while there is no contract, and the running contract
/// (terms, results, renewal, leaving early) while there is one.
struct CarBrandScreen: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var companyID: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let co = e.state.company(companyID) {
                    VStack(alignment: .leading, spacing: 18) {
                        if let a = e.carBrandContract(companyID: companyID) {
                            CarContractView(companyID: companyID, active: a, currency: e.currency(for: co))
                        } else {
                            CarBrandList(companyID: companyID, terms: e.carBrandTerms(companyID: companyID), currency: e.currency(for: co))
                        }
                    }.padding(16)
                }
            }
            .ledgerBackground()
            .navigationTitle("Brand contract").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// The brands that sell in this country, as cards. A tap opens the terms.
struct CarBrandList: View {
    var companyID: Int
    var terms: [CarBrandContract.Terms]
    var currency: Currency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A brand contract replaces the distributor: you sell only that brand, at the brand's dealer margin, for the whole term. Leaving early costs a penalty. The brand reviews you every year and offers a renewal only if it is happy.")
                .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            ForEach(terms, id: \.brand.id) { (t: CarBrandContract.Terms) in
                NavigationLink { CarBrandTermsView(companyID: companyID, brandID: t.brand.id) } label: { card(t) }.buttonStyle(PressableStyle())
            }
        }
    }

    private func card(_ t: CarBrandContract.Terms) -> some View {
        HStack(alignment: .center, spacing: 12) {
            IconCircle(glyph: Glyph.group, size: 42, tint: t.allMet ? Theme.gold : Theme.ivoryMuted)
            VStack(alignment: .leading, spacing: 4) {
                Text(t.brand.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                HStack(spacing: 5) {
                    TeamBadge(text: t.brand.segment, tint: Theme.gold)
                    TeamBadge(text: "\(t.years) years")
                }
                Text(t.allMet ? "You meet the standards." : "Not yet: " + t.unmet.map { $0.title.lowercased() }.joined(separator: ", "))
                    .font(.system(size: 12)).foregroundStyle(t.allMet ? Theme.gain : Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Currency.percent(t.margin + t.bonus, decimals: 1)).font(.system(size: 14.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                Text("dealer margin").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
            }
            GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// The terms of one brand and the button to sign.
struct CarBrandTermsView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var brandID: String
    @State private var pending: PendingAction?

    var body: some View {
        ScrollView {
            if let e = store.engine, let co = e.state.company(companyID), let t = e.carBrandTerms(companyID: companyID).first(where: { $0.brand.id == brandID }) {
                content(t, e.currency(for: co))
            }
        }
        .ledgerBackground()
        .navigationTitle(CarBrands.brand(brandID)?.name ?? "Brand").navigationBarTitleDisplayMode(.inline)
        .confirmAction($pending)
    }

    @ViewBuilder private func content(_ t: CarBrandContract.Terms, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t.brand.blurb).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            MoreBlock("Terms") {
                VStack(alignment: .leading, spacing: 0) {
                    FlatRow(label: "Term", value: "\(t.years) years", rule: false)
                    FlatRow(label: "Dealer margin", value: Currency.percent(t.margin, decimals: 1), sub: "Taken off the list price on every invoice.")
                    FlatRow(label: "Volume bonus", value: Currency.percent(t.bonus, decimals: 1), sub: "Of the list value you sold, paid after a yearly review if you reach the target.")
                    FlatRow(label: "Yearly target", value: "\(t.target) cars")
                    FlatRow(label: "Leaving early", value: cur.tidyShort(t.exitPenalty), sub: "Less the later you leave.")
                }
            }
            MoreBlock("Minimum standards") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(t.standards.enumerated()), id: \.element.id) { (item: (offset: Int, element: CarBrandContract.Standard)) in
                        CarStandardRow(standard: item.element, rule: item.offset > 0)
                    }
                }
            }
            MoreBlock("Range", card: false) {
                Text(t.brand.models.map { $0.name }.joined(separator: ", ")).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
            }
            Button { ask(t) } label: { Text(t.allMet ? "Sign the contract" : "Standards not met").frame(maxWidth: .infinity) }
                .buttonStyle(GoldButtonStyle()).disabled(!t.allMet)
        }.padding(16)
    }

    private func ask(_ t: CarBrandContract.Terms) {
        let message: String = "You sell only \(t.brand.name) for \(t.years) years at a \(Currency.percent(t.margin, decimals: 1)) dealer margin, with a target of \(t.target) cars a year. The distributor is closed to you until the contract ends. Leaving early costs a penalty."
        pending = PendingAction(title: "Sign with \(t.brand.name)?", message: message, button: "Sign", alwaysAsk: true) {
            let r = store.act { $0.carBrandSign(companyID: companyID, brandID: brandID) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else { Haptics.success(); store.show("Signed with \(t.brand.name).", tone: "good"); dismiss() }
        }
    }
}

/// The running contract: terms, this year's results, the brand's last review, a renewal offer and the way out.
struct CarContractView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var active: CarBrandContract.Active
    var currency: Currency
    @State private var pending: PendingAction?

    var body: some View {
        let a = active
        VStack(alignment: .leading, spacing: 18) {
            if let o = a.offer { renewal(o) }
            MoreBlock("Contract") {
                VStack(alignment: .leading, spacing: 0) {
                    FlatRow(label: "Brand", value: a.brand.name, rule: false)
                    FlatRow(label: "Ends", value: GameCalendar.dateString(week: a.end, dayOffset: 0), sub: "\(a.weeksLeft) weeks left")
                    FlatRow(label: "Dealer margin", value: Currency.percent(a.margin, decimals: 1))
                    FlatRow(label: "Volume bonus", value: Currency.percent(a.bonus, decimals: 1))
                }
            }
            results(a)
            MoreBlock("Standards") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(a.standards.enumerated()), id: \.element.id) { (item: (offset: Int, element: CarBrandContract.Standard)) in
                        CarStandardRow(standard: item.element, rule: item.offset > 0)
                    }
                }
            }
            Button("Leave the contract · penalty \(currency.tidyShort(a.exitPenalty))") { askToLeave(a) }.buttonStyle(TinyButtonStyle(tint: Theme.loss))
        }
        .confirmAction($pending)
    }

    private func results(_ a: CarBrandContract.Active) -> some View {
        MoreBlock("Results this year") {
            VStack(alignment: .leading, spacing: 0) {
                FlatRow(label: "Cars sold", value: "\(a.sold) of \(a.target)", sub: "Year began \(GameCalendar.dateString(week: a.yearStart, dayOffset: 0)). 1.00 pace is on target.", rule: false)
                FlatRow(label: "Pace", value: String(format: "%.2f", a.pace), tint: a.pace >= 1 ? Theme.gain : (a.pace >= 0.6 ? Theme.ivory : Theme.loss))
                FlatRow(label: "Warnings", value: "\(a.warnings) of 2", sub: "A second warning ends the contract.", tint: a.warnings > 0 ? Theme.loss : Theme.ivory)
                if let r = a.last {
                    FlatRow(label: "Last review", value: String(format: "%.0f", r.ratio * 100) + " percent of target", sub: r.outcome)
                    if r.bonus > 0 { FlatRow(label: "Bonus paid", value: currency.tidyShort(r.bonus), tint: Theme.gain) }
                }
            }
        }
    }

    private func renewal(_ o: CarBrandContract.Offer) -> some View {
        MoreBlock("Renewal offer") {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(active.brand.name) is happy with your results and offers a new term.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
                FlatRow(label: "New term", value: "\(o.years) years", rule: false)
                FlatRow(label: "Dealer margin", value: Currency.percent(o.margin, decimals: 1))
                FlatRow(label: "Yearly target", value: "\(o.target) cars")
                HStack(spacing: 10) {
                    Button("Not now") { _ = store.act { $0.carBrandDeclineRenewal(companyID: companyID) } }.buttonStyle(GreyOutlineButtonStyle())
                    Button("Renew") { renew() }.buttonStyle(QuietButtonStyle())
                }.padding(.top, 10)
            }
        }
    }

    private func renew() {
        let r = store.act { $0.carBrandRenew(companyID: companyID) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else { Haptics.success(); store.show("Contract renewed.", tone: "good") }
    }

    private func askToLeave(_ a: CarBrandContract.Active) {
        let message: String = "You pay \(currency.tidyShort(a.exitPenalty)) and the contract with \(a.brand.name) ends now. Cars you already have stay yours. You can order from the distributor again."
        pending = PendingAction(title: "Leave the brand contract?", message: message, button: "Pay \(currency.tidyShort(a.exitPenalty)) and leave", destructive: true) {
            let r = store.act { $0.carBrandLeave(companyID: companyID) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else { Haptics.success(); store.show("You left the contract.", tone: "warn") }
        }
    }
}
