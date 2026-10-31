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
                VStack(alignment: .leading, spacing: 14) {
                    NoteCard(text: "A foreign subsidiary is a new limited company in another country. It starts in set-up, takes part of your brand with it, and has to register and get local permits before it opens. Registration fees and share capital come from your own cash.", glyph: Glyph.world)
                    if all.isEmpty {
                        NoteCard(text: "Only an open company that is not a franchise unit and not a holding can expand abroad. You have none yet.")
                    } else {
                        companyList(list, showSearch: all.count > 6)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: "Expand abroad", subtitle: "A subsidiary of one of your companies", tab: .company)
        }
    }

    @ViewBuilder private func companyList(_ list: [Company], showSearch: Bool) -> some View {
        Text("Which company").capsLabel().padding(.horizontal, 2)
        if showSearch {
            TextField("Search companies", text: $search).textFieldStyle(.plain).font(.system(size: 14.5))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(Theme.surfaceTable))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        ForEach(list, id: \.id) { co in
            NavigationLink { AbroadOptionsView(companyID: co.id) } label: { companyCard(co) }.buttonStyle(.plain)
        }
    }

    /// A company with a brand gauge that ends at the 35 points needed to go abroad.
    private func companyCard(_ co: Company) -> some View {
        let weak: Bool = co.reputation < 35
        let fraction: Double = min(1, max(0, co.reputation / 35))
        return Card(padding: 14, radius: Theme.Radius.row) {
            HStack(spacing: 12) {
                IconCircle(glyph: Glyph.group)
                VStack(alignment: .leading, spacing: 6) {
                    Text(co.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    RateBar(label: weak ? "Brand, 35 needed" : "Brand \(Int(co.reputation))", fraction: fraction, tint: weak ? Theme.caution : Theme.gain)
                }
                GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim)
            }
        }
    }
}

/// The countries a company can go to, compared in one sharp table; the chosen row opens its details and the Register button below.
struct AbroadOptionsView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var chosen: String?
    @State private var pending: PendingAction?

    private let columns: [TableColumn] = [
        TableColumn(title: "Country"), TableColumn(title: "Start-up", width: 84), TableColumn(title: "Weeks", width: 46)
    ]

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let options = e.abroadOptions(companyID: companyID)
            let have = Set(Abroad.foreignCountries(e.state))
            let weak = co.reputation < 35
            let liquid = Payments.liquid(e.state)
            let pick: Abroad.Option? = options.first { $0.countryCode == chosen }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HeroFigure(label: "Cash and savings", value: e.homeCurrency.tidyDisplay(liquid), note: "Registration and share capital come from this.")
                    if weak { NoteCard(text: "The brand is too weak (\(Int(co.reputation)) of 35 needed). Build its reputation at home first.", glyph: Glyph.warning, tint: Theme.caution) }
                    countryTable(e, options, have, liquid)
                    if let pick { detail(e, co, pick, liquid: liquid, weak: weak) }
                    Text("Brand carried over: about 55% of the reputation and 40% of the awareness of \(co.name). Each country you operate in sets new rules from time to time; a head-office desk for that country handles them, without one a late change is fined.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: "Where to?", subtitle: "Pick the country for \(co.name)", tab: .company)
            .confirmAction($pending)
        }
    }

    @ViewBuilder private func countryTable(_ e: GameEngine, _ options: [Abroad.Option], _ have: Set<String>, _ liquid: Double) -> some View {
        if options.isEmpty {
            NoteCard(text: "This trade cannot be opened in any other country.")
        } else {
            SharpTable {
                TableHeader(columns: columns)
                ForEach(options, id: \.countryCode) { o in
                    let cur = e.context.currency(o.countryCode, e.state)
                    let short: Bool = o.estimatedStartCost > liquid
                    TableRow(columns: columns, title: o.name, note: have.contains(o.countryCode) ? "You operate here" : (o.hasDesk ? "Head-office desk" : ""),
                             values: [cur.tidyShort(o.estimatedStartCost), "\(Int(o.registrationWeeks))"],
                             valueTints: [short ? Theme.caution : Theme.ivory, Theme.ivoryMuted],
                             selected: chosen == o.countryCode) { chosen = o.countryCode }
                }
            }
        }
    }

    private func detail(_ e: GameEngine, _ co: Company, _ o: Abroad.Option, liquid: Double, weak: Bool) -> some View {
        let cur = e.context.currency(o.countryCode, e.state)
        let affordable = o.estimatedStartCost <= liquid
        let deskNote = o.hasDesk ? "Your head-office desk there speeds registration up." : "Slower without a head-office desk there."
        return CardSection("Open in \(o.name)") {
            RowLine(glyph: Glyph.clock, title: "Registration about \(Int(o.registrationWeeks)) weeks", subtitle: deskNote)
            CardLine()
            RowLine(glyph: affordable ? Glyph.check : Glyph.warning, tint: affordable ? Theme.gain : Theme.caution,
                    title: affordable ? "You can cover this from cash and savings." : "More than your cash and savings today",
                    subtitle: affordable ? "" : "Registration would fail until you have the money.")
            QuietButton(title: "Register in \(o.name) for about \(cur.tidyShort(o.estimatedStartCost))", fullWidth: true) { register(co, o, cur) }
                .disabled(weak).opacity(weak ? 0.4 : 1)
        }
    }

    private func register(_ co: Company, _ o: Abroad.Option, _ cur: Currency) {
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
    }
}
