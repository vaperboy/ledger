import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

struct CompanySellSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    @State private var percent = 100.0
    @State private var method: CompanySale.Method = .offers
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID) {
                content(e, co)
            } else {
                Text("This company is no longer yours.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Sell or go public")
    }

    private static func title(_ m: CompanySale.Method) -> String {
        switch m {
        case .offers: return "Take offers"
        case .auction: return "Auction"
        case .ipo: return "Go public"
        }
    }

    private static func blurb(_ m: CompanySale.Method) -> String {
        switch m {
        case .offers: return "Buyers make offers over the coming weeks. You answer, counter or wait."
        case .auction: return "Bidders compete over three weekly rounds. You set the lowest price you accept."
        case .ipo: return "Shares go on the stock exchange at a small discount. Anyone can buy them and get dividends. You keep control."
        }
    }

    private func content(_ e: GameEngine, _ co: Company) -> some View {
        let cur: Currency = e.currency(for: co)
        let pct: Int = Int(percent.rounded())
        let shown = Binding<Double>(get: { percent }, set: { (v: Double) in percent = (v / 5).rounded() * 5 })
        let q: CompanySale.Quote? = e.saleQuote(companyID: companyID, percent: pct, method: method)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(co.name).popupText(.figure)
            Text("You own \(Int(saturating: co.ownership.rounded()))%. Choose how much of your part to sell, then how.").popupText(.caption)
                .fixedSize(horizontal: false, vertical: true)
            LedgerSlider(value: shown, in: 10...100, step: 5, valueText: pct >= 100 ? "All of your part" : "\(pct)% of your part")
                .accessibilityIdentifier("sell-percent")
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(CompanySale.Method.allCases, id: \.self) { (m: CompanySale.Method) in
                    ChoiceCard(title: Self.title(m), subtitle: Self.blurb(m), selected: method == m) { method = m }
                        .accessibilityIdentifier("sell-method-\(m.rawValue)")
                }
            }
            if let q {
                figures(q, co, cur)
                if let why = q.problem { InlineMessage(text: why) }
                Button(action: { ask(q, co, cur) }) { Text(buttonTitle(q, cur)) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(q.problem != nil)
                    .accessibilityIdentifier("sell-go")
            }
        }
    }

    private func figures(_ q: CompanySale.Quote, _ co: Company, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            PopupRow(label: "Company worth", value: cur.tidyShort(q.companyValue))
            PopupRow(label: "Your part sold", value: cur.tidyShort(q.stakeValue))
            if q.method == .ipo { PopupRow(label: "Sold at", value: "\(Int(PublicCompany.discount * 100))% under fair value") }
            PopupRow(label: q.method == .offers ? "Likely price" : "Expected price", value: cur.tidyShort(q.expected))
            if q.fee > 0 { PopupRow(label: q.method == .ipo ? "Bank fee" : "Auction fee", value: "\u{2212}" + cur.tidyShort(q.fee)) }
            PopupRow(label: "Tax on the gain", value: "\u{2212}" + cur.tidyShort(q.tax))
            PopupRow(label: "You get", value: cur.tidyShort(q.youGet))
            PopupRow(label: "You keep", value: q.ownershipAfter < 0.5 ? "Nothing: the company is sold" : "\(Int(saturating: q.ownershipAfter.rounded()))% of the company")
            ForEach(Array(q.lines.enumerated()), id: \.offset) { (_: Int, line: String) in
                Text(line).popupText(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if q.method == .auction { Text("Lowest price you accept: \(cur.tidyShort(q.reserve)) for the whole company.").popupText(.caption) }
        }
    }

    private func buttonTitle(_ q: CompanySale.Quote, _ cur: Currency) -> String {
        switch q.method {
        case .offers: return "Put on the market"
        case .auction: return "Start the auction"
        case .ipo: return "Go public for about " + cur.tidyShort(q.youGet)
        }
    }

    private func ask(_ q: CompanySale.Quote, _ co: Company, _ cur: Currency) {
        let id: Int = companyID
        let pct: Int = q.pct
        let name: String = co.name
        let method: CompanySale.Method = q.method
        let all: Bool = q.ownershipAfter < 0.5
        let message: String
        switch method {
        case .offers: message = "\(name) is listed for buyers. Nothing is paid until you accept an offer."
        case .auction: message = "The auction runs three weekly rounds. Your staff hear about it. When it sells, a fee is taken."
        case .ipo: message = "New shareholders get \(pct)% of your part at a discount. The company then reports every quarter, the board decides on dividends, and big changes need a shareholder vote. This cannot be undone."
        }
        pending = PendingAction(title: method == .ipo ? "Take \(name) public?" : all ? "Sell \(name)?" : "Sell part of \(name)?", message: message,
                                button: method == .ipo ? "Go public" : "Start", destructive: method != .offers, tone: .investment, icon: "chart.pie") {
            switch store.act({ $0.startSale(companyID: id, percent: pct, method: method, reserve: q.reserve) }) {
            case .started?:
                Haptics.success()
                store.show(method == .ipo ? "\(name) is now listed on the stock exchange." : "\(name) is on the market. Watch the offers come in.", tone: "good")
                dismiss()
            case .refused(let why)?: Haptics.warning(); store.show(why, tone: "warn")
            case nil: break
            }
        }
    }
}
