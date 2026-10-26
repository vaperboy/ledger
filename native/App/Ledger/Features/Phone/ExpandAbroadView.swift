import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// Expand abroad: pick one of your running companies, then a country. Shows the start-up cost, the wait for registration, the brand it
/// carries over and the compliance risk before a foreign subsidiary is registered. Reached from "New company". Logic: `Abroad`.
struct ExpandAbroadView: View {
    @EnvironmentObject var store: GameStore
    @State private var search = ""

    var body: some View {
        if let e = store.engine {
            let all = e.state.companies.filter { $0.status == .open && !$0.value("franchise")["fran"].bool && $0.type != "hold" }
            let list = all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("A foreign subsidiary is a new limited company in another country. It starts in set-up, takes part of your brand with it, and has to register and get local permits before it opens. Registration fees and share capital come from your own cash.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    if all.isEmpty {
                        LedgerSection("Which company") {
                            Text("Only an open company that is not a franchise unit and not a holding can expand abroad. You have none yet.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                        }
                    } else {
                        LedgerSection("Which company") {
                            VStack(spacing: 0) {
                                if all.count > 6 { TextField("Search companies", text: $search).textFieldStyle(.plain).padding(.vertical, 8) }
                                ForEach(Array(list.enumerated()), id: \.element.id) { n, co in
                                    if n > 0 { Hairline() }
                                    NavigationLink { AbroadOptionsView(companyID: co.id) } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(co.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                                                Text(co.reputation < 35 ? "Brand too weak (\(Int(co.reputation)) of 35 needed)" : "Brand \(Int(co.reputation))").font(.system(size: 11)).foregroundStyle(co.reputation < 35 ? Theme.caution : Theme.ivoryFaint)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                        }.padding(.vertical, 9).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Expand abroad").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AbroadOptionsView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let options = e.abroadOptions(companyID: companyID)
            let have = Set(Abroad.foreignCountries(e.state))
            let weak = co.reputation < 35
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(co.name).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                        Text("You have \(e.homeCurrency.tidyDisplay(Payments.liquid(e.state))) in cash and savings.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                    }
                    if weak {
                        Text("The brand is too weak (\(Int(co.reputation)) of 35 needed). Build its reputation at home first.").font(.caption).foregroundStyle(Theme.caution)
                    }
                    LedgerSection("Where") {
                        VStack(spacing: 0) {
                            if options.isEmpty { Text("This trade cannot be opened in any other country.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
                            ForEach(Array(options.enumerated()), id: \.element.countryCode) { n, o in
                                if n > 0 { Hairline() }
                                optionRow(e, co, o, present: have.contains(o.countryCode), weak: weak)
                            }
                        }
                    }
                    Text("Brand carried over: about 55% of the reputation and 40% of the awareness of \(co.name). Each country you operate in sets new rules from time to time; a head-office desk for that country handles them, without one a late change is fined.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Where to?").navigationBarTitleDisplayMode(.inline)
            .confirmAction($pending)
        }
    }

    private func optionRow(_ e: GameEngine, _ co: Company, _ o: Abroad.Option, present: Bool, weak: Bool) -> some View {
        let cur = e.context.currency(o.countryCode, e.state)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(o.name).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                if present { Chip(text: "You operate here", tint: Theme.gold) }
                Spacer()
                Text(cur.tidyShort(o.estimatedStartCost)).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivory)
            }
            Text("Registration about \(Int(o.registrationWeeks)) weeks" + (o.hasDesk ? " (your head-office desk there speeds it up)" : " (slower without a head-office desk there)")).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            Button("Register in \(o.name)") {
                pending = PendingAction(title: "Register \(co.name) in \(o.name)?",
                                        message: "Start-up cost about \(cur.tidyDisplay(o.estimatedStartCost)), taken from your own cash and savings once the company is registered. It is a separate limited company that must finish the foreign registration (about \(Int(o.registrationWeeks)) weeks) and get local permits before it opens. " + (o.hasDesk ? "" : "Without a head-office desk for \(o.name), new local rules can bring fines. ") + "Most new foreign operations run at a loss for a while.",
                                        button: "Register") {
                    switch store.act({ $0.expandAbroad(companyID: co.id, countryCode: o.countryCode) }) {
                    case .success(let id)?: Haptics.success(); store.show("Registered in \(o.name). Complete the registration, then open.", tone: "good"); store.openCompany(id)
                    case .failure(.brandTooWeak)?: Haptics.warning(); store.show("The brand is too weak to go abroad yet.", tone: "warn")
                    case .failure(.banned(let why))?: store.show(why, tone: "bad")
                    case .failure(.cannotStart(_))?: Haptics.warning(); store.show("It could not be started: check your cash for the registration costs.", tone: "warn")
                    case .failure(.notOpen)?: store.show("The company must be open to expand.", tone: "warn")
                    default: store.show("Not possible there.", tone: "warn")
                    }
                }
            }.buttonStyle(QuietButtonStyle()).disabled(weak)
        }.padding(.vertical, 9)
    }
}
