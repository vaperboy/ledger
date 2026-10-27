import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Giving back (C3): sponsor the club, a scholarship, a park, a hospital wing, or endow a foundation. Paid from your own cash, not a
/// company's. Each gift raises your standing in one city (a little more demand there, up to +6%), adds to your legacy and moves your
/// public image. All figures come from `Giving` through `GameEngine`; this screen only chooses and reports.
struct GivingView: View {
    @EnvironmentObject var store: GameStore
    @State private var pending: PendingAction?
    @State private var placeKey = ""
    @State private var endowment = 0

    var body: some View {
        ScrollView {
            if let e = store.engine {
                let places = e.givingPlaces
                let place = places.first { $0.key == placeKey } ?? places.first
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    summary(e)
                    if let place {
                        LedgerSection(title: "Gifts", trailing: { cityPicker(places, current: place) }) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Standing in \(place.name): \(Int(place.standing.rounded())) of 100. It fades slowly; more standing brings a little more demand to your companies there.")
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
                                ForEach(Array(e.giftOptions.enumerated()), id: \.element.id) { n, g in
                                    if n > 0 { Hairline() }
                                    giftRow(e, g, place)
                                }
                            }
                        }
                    } else {
                        LedgerSection("Gifts") {
                            Text("You need a city to give to: open a company or choose a home city first.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                    foundationSection(e)
                    marksSection(e)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 900).frame(maxWidth: .infinity)
            }
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
        .appScreen(title: "Giving back", subtitle: "Gifts, sponsorships and your foundation", tab: .group)
        .confirmAction($pending)
    }

    // MARK: Summary

    private func summary(_ e: GameEngine) -> some View {
        let cur = e.homeCurrency
        let f = e.foundation
        return KeyFigures(items: [
            .init(label: "Your cash", value: cur.tidyShort(e.state.cash), sub: "gifts come from you, not a company"),
            .init(label: "Gifts made", value: "\(e.givingMarks.count)", sub: "\(e.givingMarks.filter { $0.yearly }.count) renew each year"),
            .init(label: "Foundation", value: f.map { cur.tidyShort($0.capital) } ?? "None", sub: f.map { "gave \(cur.tidyShort($0.given)) so far" } ?? "not started"),
        ])
    }

    private func cityPicker(_ places: [Giving.Place], current: Giving.Place) -> some View {
        Group {
            if places.count > 1 {
                Menu {
                    ForEach(places, id: \.key) { p in Button(p.name) { placeKey = p.key } }
                } label: { Text("\(current.name)  ⌄").font(.system(size: 12)).foregroundStyle(Theme.gold) }
            } else {
                Text(current.name).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Gifts

    private func giftRow(_ e: GameEngine, _ g: Giving.Gift, _ place: Giving.Place) -> some View {
        let cur = e.homeCurrency
        let cost = e.giftCost(g.id)
        let done = e.giftDone(g.id, place: place)
        let short = e.state.cash < cost
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(g.name).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                if g.yearly { Chip(text: "Every year", tint: Theme.gold) }
                Spacer(minLength: 8)
                Text(cur.tidyShort(cost) + (g.yearly ? " / yr" : "")).font(.system(size: 14).monospacedDigit()).foregroundStyle(short && !done ? Theme.loss : Theme.ivory)
            }
            Text(g.detail.tidyMoney).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            Text("Standing in \(place.name) +\(Int(g.standing)) · legacy +\(Int(g.legacy))").font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted)
            if done {
                Text("Done in \(place.name).").font(.system(size: 11.5)).foregroundStyle(Theme.gain)
            } else {
                Button(g.yearly ? "Sponsor" : "Give") {
                    pending = PendingAction(
                        title: "\(g.name) in \(place.name)?",
                        message: "Costs \(cur.tidyDisplay(cost)) from your own cash" + (g.yearly ? ", and again every year; if you cannot pay one year the sponsorship ends." : ", once.")
                            + " Your standing in \(place.name) rises by about \(Int(g.standing)) and your legacy by \(Int(g.legacy)). It cannot be undone, and there is no financial return except the small demand lift in that city.",
                        button: g.yearly ? "Sponsor" : "Give") { give(g, place) }  // irreversible: no amount, so it always asks
                }.buttonStyle(QuietButtonStyle(tint: Theme.gold)).disabled(short)
                if short { Text("Short by \(cur.tidyShort(cost - e.state.cash)).").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
            }
        }.padding(.vertical, 10)
    }

    private func give(_ g: Giving.Gift, _ place: Giving.Place) {
        guard let r = store.act({ $0.give(giftID: g.id, countryCode: place.countryCode, cityID: place.cityID) }) else { return }
        switch r {
        case .ok: Haptics.success(); store.show("\(store.engine?.givingMarks.first?.name ?? g.name). Standing in \(place.name) rose.", tone: "good")
        case .notEnoughCash: Haptics.warning(); store.show("Not enough cash for that gift.", tone: "warn")
        case .alreadyDone: store.show("Already done there.", tone: "warn")
        case .unknown: store.show("That gift is not available.", tone: "warn")
        }
    }

    // MARK: Foundation

    @ViewBuilder private func foundationSection(_ e: GameEngine) -> some View {
        let cur = e.homeCurrency
        LedgerSection("Foundation") {
            if let f = e.foundation {
                VStack(alignment: .leading, spacing: 6) {
                    FlatRow(label: "Endowment", value: cur.tidyShort(f.capital), rule: false)
                    FlatRow(label: "Given so far", value: cur.tidyShort(f.given))
                    FlatRow(label: "Next yearly grant", value: cur.tidyShort(f.capital * 0.04), sub: "about 4% of the endowment, spread over the cities you work in")
                    Text("The capital stays; only the yearly grant is given. It adds legacy and goodwill every year and cannot be withdrawn.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                let steps = [1.0, 5, 20, 50].map { e.homeCurrency.scaledPrice($0 * 1e6) }.map { ($0 / 1000).rounded() * 1000 }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Put money in once and it gives about 4% of the endowment every year, for good. Your name goes on it, your legacy and your image grow, and the money is gone from your cash for good.")
                        .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    Picker("Endowment", selection: $endowment) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { n, v in Text(cur.tidyShort(v)).tag(n) }
                    }.pickerStyle(.segmented)
                    let amount = steps[min(endowment, steps.count - 1)]
                    Text("Yearly grant: about \(cur.tidyShort(amount * 0.04)).").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    Button("Start the foundation") {
                        pending = PendingAction(
                            title: "Endow a foundation with \(cur.tidyShort(amount))?",
                            message: "\(cur.tidyDisplay(amount)) leaves your cash for good. It then gives about \(cur.tidyDisplay(amount * 0.04)) a year to schools, clubs and people in need in the cities you work in. It adds legacy and improves your public image. You cannot take the money back or add to it later.",
                            button: "Start the foundation", destructive: true) {
                            switch store.act({ $0.startFoundation(amount: amount) }) {
                            case .ok?: Haptics.success(); store.show("The foundation is started with \(cur.tidyShort(amount)).", tone: "good")
                            case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash for that endowment.", tone: "warn")
                            case .alreadyDone?: store.show("You already have a foundation.", tone: "warn")
                            default: store.show("It could not be started.", tone: "warn")
                            }
                        }
                    }.buttonStyle(QuietButtonStyle(tint: Theme.gold)).disabled(e.state.cash < amount)
                    if e.state.cash < amount { Text("Short by \(cur.tidyShort(amount - e.state.cash)).").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
                }
            }
        }
    }

    // MARK: Marks

    @ViewBuilder private func marksSection(_ e: GameEngine) -> some View {
        let marks = e.givingMarks
        LedgerSection("Your marks") {
            if marks.isEmpty {
                Text("Nothing yet. Each gift leaves a named mark here and in your legacy.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(marks.enumerated()), id: \.offset) { n, m in
                        if n > 0 { Hairline() }
                        HStack(alignment: .firstTextBaseline) {
                            Text(m.name).font(.system(size: 13)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text((m.yearly ? "Yearly · " : "") + GameCalendar.dateString(week: m.week)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }.padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
