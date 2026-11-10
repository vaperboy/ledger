import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct HoldingDivisionSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.popupClose) private var popupClose
    var holdingID: Int
    var companyID: Int
    @State private var hostID: Int?
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let h = e.state.company(holdingID), let c = e.state.company(companyID) {
                content(e, h, c)
            } else {
                Text("This company is not available.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Fold it into the holding as a division")
    }

    private func hosts(_ e: GameEngine) -> [Company] {
        let all: [(company: Company, percent: Double, tier: HoldingStakes.Tier)] = e.holdingStakes(holdingID: holdingID)
        return all.filter { (s: (company: Company, percent: Double, tier: HoldingStakes.Tier)) -> Bool in
            s.company.id != companyID && s.percent >= 99.9 && !HoldingStakes.isDivision(s.company)
        }.map { (s: (company: Company, percent: Double, tier: HoldingStakes.Tier)) -> Company in s.company }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ h: Company, _ c: Company) -> some View {
        let cur: Currency = e.currency(for: h)
        let t: HoldingStakes.DivisionTerms = e.holdingDivisionTerms(holdingID: holdingID, companyID: companyID, hostID: hostID)
        let options: [Company] = hosts(e)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(c.name).popupText(.figure)
            if !options.isEmpty {
                Text("Where it joins").popupText(.subtitle)
                VStack(spacing: 0) {
                    PopupChoiceRow(title: h.name, subtitle: hostID == nil ? "Chosen" : "The holding itself", identifier: "holding-division-host-holding") { hostID = nil }
                    ForEach(options) { (o: Company) in
                        PopupChoiceRow(title: o.name, subtitle: hostID == o.id ? "Chosen" : "A company the holding owns outright", identifier: "holding-division-host-\(o.id)") { hostID = o.id }
                    }
                }
            }
            Text(t.allowed ? t.summary : t.reason).popupText(t.allowed ? .body : .risk).fixedSize(horizontal: false, vertical: true)
            if t.allowed {
                PopupRow(label: "Joins", value: t.hostName)
                PopupRow(label: "Value that stays in the group", value: cur.tidyShort(t.value))
                PopupRow(label: "Cash that stays with it", value: cur.tidyShort(t.cash))
                PopupRow(label: "People who stay", value: "\(t.staff)")
                Text("Nothing is paid. It stops being a separate company, so the holding can no longer buy or sell shares of it.").popupText(.caption).fixedSize(horizontal: false, vertical: true)
                Button("Fold it in as a division") { askDivision(t) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("holding-division-go")
            }
        }
    }

    private func askDivision(_ t: HoldingStakes.DivisionTerms) {
        let host: Int? = hostID
        let name: String = t.companyName
        pending = PendingAction(title: "Make \(name) a division of \(t.hostName)?", message: t.summary, button: "Make division", destructive: true,
                                risk: "It cannot be undone.") {
            let r: Result<HoldingStakes.DivisionTerms, HoldingStakes.Failure>? = store.act { (e: inout GameEngine) -> Result<HoldingStakes.DivisionTerms, HoldingStakes.Failure> in
                e.holdingMakeDivision(holdingID: holdingID, companyID: companyID, hostID: host)
            }
            switch r {
            case .success(let d)?:
                Haptics.success(); store.show("\(name) is now a division of \(d.hostName).", tone: "good"); popupClose?()
            case .failure(let f)?:
                Haptics.warning(); store.show(f.reason, tone: "warn")
            case nil:
                store.show("It could not be done now.", tone: "warn")
            }
        }
    }
}
