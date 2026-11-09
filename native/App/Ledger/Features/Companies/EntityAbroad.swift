import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// "Expand abroad" for ONE company, a section of its Expansion tab: every country it can open a subsidiary in, with the engine's start-up
/// cost for this company and the weeks the registration takes (`abroadOptions`). A row opens the existing "Where to?" screen at that country,
/// where the subsidiary is registered. Only an open company that is not a franchise unit and not a holding can expand.
struct EntityAbroadSection: View {
    @EnvironmentObject var store: GameStore
    let companyID: Int
    @Environment(Entitlements.self) private var ent
    @State private var all = false
    @State private var chosen: String?

    private let columns: [TableColumn] = [
        TableColumn(title: "Country"), TableColumn(title: "Start-up", width: 84), TableColumn(title: "Weeks", width: 46)
    ]
    private let limit: Int = 8

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), co.status == .open, co.type != "hold", !co.value("franchise")["fran"].bool {
            if let lock = e.unlockItem("abroad", companyID: companyID), !lock.unlocked {
                LockedBlock(title: "Expand abroad", reason: lock.reason, progress: Double(Unlocks.monthsClosed(co)) / 12)
            } else {
                openSection(e, co, e.abroadOptions(companyID: companyID))
            }
        }
    }

    @ViewBuilder private func openSection(_ e: GameEngine, _ co: Company, _ options: [Abroad.Option]) -> some View {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) { Text("EXPAND ABROAD").capsLabel(); ProMark(feature: .expansionAbroad) }
                Text("A foreign subsidiary of \(co.name) is a new company that takes part of its brand along.")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                if options.isEmpty {
                    Text("This trade cannot be opened in any other country.").textStyle(.caption, tint: Theme.inkFaint)
                } else {
                    table(e, options)
                    if options.count > limit {
                        Button { Haptics.tap(); Motion.animate(Motion.quickAnimation) { all.toggle() } } label: {
                            Text(all ? "Show fewer" : "Show all \(options.count) countries \u{203A}")
                                .textStyle(.caption, tint: Theme.accent).frame(maxWidth: .infinity, alignment: .trailing).frame(minHeight: 32)
                        }.buttonStyle(PressableStyle())
                    }
                }
            }
            .navigationDestination(item: $chosen) { (code: String) in AbroadOptionsView(companyID: companyID, country: code) }
    }

    @ViewBuilder private func table(_ e: GameEngine, _ options: [Abroad.Option]) -> some View {
        let shown: [Abroad.Option] = all ? options : Array(options.prefix(limit))
        let have: Set<String> = Set(Abroad.foreignCountries(e.state))
        SharpTable {
            TableHeader(columns: columns)
            ForEach(shown, id: \.countryCode) { (o: Abroad.Option) in
                row(e, o, operating: have.contains(o.countryCode))
            }
        }
        .environment(\.outsidePalette, OutsidePalette.game)
    }

    private func row(_ e: GameEngine, _ o: Abroad.Option, operating: Bool) -> some View {
        let cur: Currency = e.context.currency(o.countryCode, e.state)
        let note: String = operating ? "You operate here" : (o.hasDesk ? "Head-office desk" : "")
        let values: [String] = [cur.tidyShort(o.estimatedStartCost), "\(Int(o.registrationWeeks))"]
        let code: String = o.countryCode, countryName: String = o.name
        return TableRow(columns: columns, title: o.name, note: note, values: values, valueTints: [Theme.ivory, Theme.ivoryMuted]) {
            ent.run(.expansionAbroad, "Open a company in " + countryName) { chosen = code }
        }
    }
}
