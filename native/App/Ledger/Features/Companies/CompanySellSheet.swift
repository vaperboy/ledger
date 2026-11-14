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
        case .offers: return "Offers"
        case .auction: return "Auction"
        case .ipo: return "Go public"
        }
    }

    private static func blurb(_ m: CompanySale.Method) -> String {
        switch m {
        case .offers: return "Buyers make offers. You answer or wait."
        case .auction: return "Three weekly rounds. You set the lowest price."
        case .ipo: return "Shares list at a small discount. You keep control."
        }
    }

    private func content(_ e: GameEngine, _ co: Company) -> some View {
        let cur: Currency = e.currency(for: co)
        let pct: Int = Int(saturating: percent.rounded())
        let shown = Binding<Double>(get: { percent }, set: { (v: Double) in percent = (v / 5).rounded() * 5 })
        let q: CompanySale.Quote? = e.saleQuote(companyID: companyID, percent: pct, method: method)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("\(co.name) \u{00B7} you own \(Int(saturating: co.ownership.rounded()))%").popupText(.caption).lineLimit(1)
            LedgerSlider(value: shown, in: 10...100, step: 5, valueText: pct >= 100 ? "All of your part" : "\(pct)% of your part")
                .accessibilityIdentifier("sell-percent")
            SegmentedChoice(items: [CompanySale.Method.auction, CompanySale.Method.ipo, CompanySale.Method.offers], title: { (m: CompanySale.Method) -> String in Self.title(m) }, selection: $method)
                .accessibilityIdentifier("sell-method")
            Text(Self.blurb(method)).popupText(.caption).lineLimit(1).minimumScaleFactor(0.8)
            if let q {
                figures(q, cur)
                if let why = q.problem { InlineMessage(text: why) }
                Button(action: { ask(q, co, cur) }) { Text(buttonTitle(q, cur)) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(q.problem != nil)
                    .accessibilityIdentifier("sell-go")
            }
        }
    }

    private func figures(_ q: CompanySale.Quote, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PopupRow(label: q.method == .offers ? "Likely price" : "Expected price", value: cur.tidyShort(q.expected))
            PopupRow(label: "Fee and tax", value: "\u{2212}" + cur.tidyShort(q.fee + q.tax))
            PopupRow(label: "You get", value: cur.tidyShort(q.youGet))
            PopupRow(label: "You keep", value: q.ownershipAfter < 0.5 ? "Nothing: sold" : "\(Int(saturating: q.ownershipAfter.rounded()))%")
            if q.method == .auction { PopupRow(label: "Lowest accepted", value: cur.tidyShort(q.reserve)) }
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
