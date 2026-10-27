import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Where a home-based company works: at home (no rent) or in a workshop or office of its own. Shown in Operations for the trades that
/// start at home. Moving in, and moving back, are confirmed with what they cost or return.
struct CompanyWorkplaceSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: PendingAction?

    var body: some View {
        if engine.isHomeTrade(companyID: company.id), company.status.isLive, let word = engine.homeTradePlaceWord(companyID: company.id) {
            let cur = engine.currency(for: company)
            let prem = company.value("prem")
            let atHome = engine.isWorkingFromHome(companyID: company.id)
            let heads = PremisesExtras.heads(company)
            LedgerSection(title: "Where you work", trailing: {
                Text(atHome ? "At home" : (prem["owned"].bool ? "Your own \(word)" : "Rented \(word)")).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if atHome {
                        Text("\(heads) \(heads == 1 ? "person works" : "people work") from home. No rent, no deposit.")
                            .font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        if engine.hasOutgrownHome(companyID: company.id) {
                            Text("The team has outgrown the kitchen table. Every week morale and quality slip (more from six people). A \(word) of its own stops that.")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("From four people working from home, morale and quality start to slip. Move into a \(word) before then, or when the work needs the space.")
                                .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                        }
                        NavigationLink { WorkplaceMoveView(companyID: company.id) } label: {
                            HStack {
                                Text("Find a \(word)").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.gold)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }.padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    } else {
                        let name = prem["lname"].string
                        Text("\(name.isEmpty ? "A \(word)" : name) · \(Int(prem["m2"].double)) m²" + (prem["owned"].bool ? " · owned" : " · \(cur.tidyShort(prem["rent"].double * prem["m2"].double / 12)) a month"))
                            .font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        if let q = engine.moveHomeQuote(companyID: company.id) {
                            Text(q.isOwned ? "Working from home again sells the building at today's value and pays off the mortgage." : "Working from home again ends the lease and returns the deposit.")
                                .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                            Button("Work from home again") { moveHome(q, cur) }.buttonStyle(QuietButtonStyle())
                        }
                    }
                }
            }
            .confirmAction($pending)
        }
    }

    private func moveHome(_ q: (isOwned: Bool, proceeds: Double, shortfall: Double), _ cur: Currency) {
        let id = company.id
        let msg = q.isOwned
            ? "The building is sold at today's value and the mortgage is paid off: \(cur.tidyShort(q.proceeds)) comes back to the company" + (q.shortfall > 0 ? ", but the mortgage is more than the building is worth, so the company pays the \(cur.tidyShort(q.shortfall)) difference." : ".")
            : "The lease ends and the deposit of \(cur.tidyShort(q.proceeds)) comes back to the company. The fit-out you paid for is not refunded."
        pending = PendingAction(title: "Work from home again?", message: msg + " Everyone works from home; a team of four or more loses morale and quality every week.", button: "Move home", destructive: true) {
            if store.act({ $0.giveUpPremises(companyID: id) }) == true { Haptics.success(); store.show("Everyone works from home again.", tone: "n") }
            else { Haptics.warning(); store.show("It could not be given up.", tone: "warn") }
        }
    }
}

/// The places a home-based company can move into: rent or buy, with what each costs now and every month, and what the company can afford.
struct WorkplaceMoveView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let word = e.homeTradePlaceWord(companyID: companyID) {
            let cur = e.currency(for: co)
            let listings = e.premisesListings(companyID: companyID)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(co.name) has \(cur.tidyShort(co.cash)) in the company account. Renting needs a deposit (three months, returned when you leave) and the fit-out; buying needs 35% down and the fit-out, with a 15-year mortgage on the rest.")
                            .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    if listings.isEmpty {
                        Text("No \(word) is on offer in this city right now. The list changes every half year.").font(.bodyText).foregroundStyle(Theme.ivoryFaint)
                    }
                    ForEach(listings) { l in
                        if let t = e.premisesTerms(companyID: companyID, listing: l) {
                            let rentUp = t.deposit + t.fitOut, buyUp = t.downPayment + t.fitOut
                            LedgerSection(l.name) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 10) {
                                        ThumbnailView(kind: .premises, key: e.data.catalog[co.type]?.premisesKind ?? "office", size: 36, shape: .square)
                                        Text("\(Int(l.squareMetres)) m² · \(l.landlord)").font(.caption).foregroundStyle(Theme.ivoryFaint)
                                    }
                                    FlatRow(label: "Rent", value: cur.tidyShort(t.monthlyRent) + " a month", sub: "Deposit \(cur.tidyShort(t.deposit)) and fit-out \(cur.tidyShort(t.fitOut)): \(cur.tidyShort(rentUp)) now", rule: false)
                                    FlatRow(label: "Buy", value: cur.tidyShort(t.purchasePrice), sub: "\(cur.tidyShort(buyUp)) now (down payment and fit-out), the rest a 15-year mortgage")
                                    HStack {
                                        option("Rent", co.cash >= rentUp, rentUp - co.cash, cur) { ask(l, t, buy: false, word: word, cur: cur) }
                                        option("Buy", co.cash >= buyUp, buyUp - co.cash, cur) { ask(l, t, buy: true, word: word, cur: cur) }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .appScreen(title: "Find a \(word)", subtitle: "Rent or buy", tab: .company)
            .confirmAction($pending)
        } else {
            Text("This company is not available.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func option(_ title: String, _ affordable: Bool, _ missing: Double, _ cur: Currency, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(title, action: action).buttonStyle(QuietButtonStyle()).disabled(!affordable)
            if !affordable { Text("needs \(cur.tidyShort(missing)) more").font(.caption2).foregroundStyle(Theme.caution) }
        }
    }

    private func ask(_ l: CompanySetup.Listing, _ t: CompanySetup.PremisesTerms, buy: Bool, word: String, cur: Currency) {
        let id = companyID
        let now = buy ? t.downPayment + t.fitOut : t.deposit + t.fitOut
        let msg = buy
            ? "\(cur.tidyShort(now)) leaves the company now (down payment \(cur.tidyShort(t.downPayment)) and fit-out \(cur.tidyShort(t.fitOut))); a 15-year mortgage covers the other \(cur.tidyShort(t.purchasePrice - t.downPayment)). No rent. Everyone moves in from this week, so the home-working morale and quality loss stops."
            : "\(cur.tidyShort(now)) leaves the company now (deposit \(cur.tidyShort(t.deposit)), returned when you leave, and fit-out \(cur.tidyShort(t.fitOut))). Then \(cur.tidyShort(t.monthlyRent)) a month in rent. Everyone moves in from this week."
        pending = PendingAction(title: (buy ? "Buy " : "Rent ") + l.name + "?", message: msg, button: buy ? "Buy it" : "Rent it") {
            switch store.act({ $0.takePremises(companyID: id, listing: l, buy: buy) }) {
            case .ok?: Haptics.success(); store.show((buy ? "Bought " : "Rented ") + l.name + ". The team has moved in.", tone: "good"); dismiss()
            case .notEnoughCash?: Haptics.warning(); store.show("The company does not have enough cash for that.", tone: "warn")
            default: Haptics.warning(); store.show("Not possible.", tone: "warn")
            }
        }
    }
}
