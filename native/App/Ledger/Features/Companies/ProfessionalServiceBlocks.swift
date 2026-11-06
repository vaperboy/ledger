import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Item block: the professional-service page of an item (cons, tutor, photo, law, acctfirm, mktg). Shows the hourly rate against fair value with a
/// live profit or loss slider, the job price, who does the hours, utilisation, write-offs, client type and retainers, booking lead time.
/// It draws nothing for an item that is not a service type of these trades.
struct ProfessionalServiceBlock: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var itemID: String
    /// The rate being dragged (per billable hour, or per unit for goods); nil = the item's own price.
    @State private var draftRate: Double?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let base = ProfessionalServices.economics(e.state, companyID: companyID, itemID: itemID, data: e.data) {
            let cur: Currency = e.currency(for: co)
            let per: Double = base.isGoods ? 1 : base.hoursPerBlock
            let eco: ProfessionalServices.Economics = draftRate.flatMap { (r: Double) -> ProfessionalServices.Economics? in
                ProfessionalServices.economics(e.state, companyID: companyID, itemID: itemID, price: r * per, data: e.data)
            } ?? base
            TeamGroup(base.isGoods ? "Goods" : "Service") {
                Card(padding: 14, radius: Theme.Radius.row) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(eco.text).font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                        KeyFigures(items: figures(eco, cur))
                        rateSlider(eco, per, cur)
                        verdict(eco, cur)
                        details(eco, cur)
                    }
                }
            }
        }
    }

    // MARK: Parts

    private func figures(_ eco: ProfessionalServices.Economics, _ cur: Currency) -> [KeyFigures.Item] {
        let reading = itemProfitReading(eco.live, cur)
        if eco.isGoods {
            return [
                .init(label: "Price", value: itemAmount(eco.blockPrice, cur), sub: "each"),
                .init(label: "Cost", value: itemAmount(eco.unitCost, cur), sub: "each"),
                .init(label: "Margin now", value: reading.text, tint: reading.tint),
            ]
        }
        return [
            .init(label: "Hourly rate", value: itemAmount(eco.hourlyRate, cur), sub: "fair " + itemAmount(eco.fairHourly, cur)),
            .init(label: "Per " + eco.unit, value: itemAmount(eco.jobPrice, cur), sub: hoursText(eco.hoursPerJob)),
            .init(label: "Cost an hour", value: itemAmount(eco.costPerHour, cur), sub: "pay, consumables, write-offs"),
            .init(label: "Margin an hour", value: reading.text.replacingOccurrences(of: "profit ", with: "").replacingOccurrences(of: "loss ", with: ""), tint: reading.tint),
        ]
    }

    private func hoursText(_ h: Double) -> String {
        h == h.rounded() ? "\(Int(h)) h" : String(format: "%.1f h", h)
    }

    private func rateSlider(_ eco: ProfessionalServices.Economics, _ per: Double, _ cur: Currency) -> some View {
        let lo: Double = eco.sliderLow
        let hi: Double = eco.sliderHigh
        let rate: Double = eco.blockPrice / per
        let amount = Binding<Double>(get: { min(max(rate, lo), hi) }, set: { (v: Double) in draftRate = v })
        return VStack(alignment: .leading, spacing: 6) {
            if hi > lo {
                LedgerSlider(value: amount, in: lo...hi, onEditingChanged: { (editing: Bool) in
                    if !editing { commit((draftRate ?? rate) * per) }
                })
                .tint(Theme.gold)
                .accessibilityIdentifier("service-rate")
                ProfitBand(lo: lo, hi: hi, cost: eco.breakEvenHourly, price: rate)
                TypedPriceField(price: rate, range: lo...hi, cur: cur, unit: eco.isGoods ? "each" : "per hour",
                                hint: { (v: Double) -> String? in
                    let lp = ItemModels.liveProfit(price: v, cost: eco.breakEvenHourly)
                    return lp.outcome == .breakEven ? "At this price you break even." : "At this price: \(lp.word) \(itemAmount(lp.amount, cur)) " + (eco.isGoods ? "on each one." : "an hour.")
                }, onSet: { (v: Double) in commit(v * per) })
            }
            Text((eco.isGoods ? "Price " : "Hourly rate ") + itemAmount(rate, cur) + ", " + String(format: "%.0f%%", eco.priceVsFair * 100) + " of fair value. Break-even "
                 + itemAmount(eco.breakEvenHourly, cur) + (eco.isGoods ? "." : " an hour."))
                .font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func verdict(_ eco: ProfessionalServices.Economics, _ cur: Currency) -> some View {
        let weekly = ItemModels.liveProfit(price: eco.weeklyProfit, cost: 0)
        let word: String = weekly.outcome == .loss ? "loss" : (weekly.outcome == .profit ? "profit" : "break-even")
        let tint: Color = weekly.outcome == .loss ? Theme.loss : (weekly.outcome == .profit ? Theme.gain : Theme.ivoryMuted)
        return HStack(alignment: .firstTextBaseline) {
            Text("At this rate, a normal week").font(.subheadline).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            Text(weekly.outcome == .breakEven ? word : word + " " + itemAmount(eco.weeklyProfit, cur))
                .font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(tint)
        }
    }

    @ViewBuilder private func details(_ eco: ProfessionalServices.Economics, _ cur: Currency) -> some View {
        VStack(spacing: 0) {
            if !eco.isGoods {
                FlatRow(label: "Done by", value: eco.roleLabel, rule: false)
                FlatRow(label: "Hours sold a week", value: String(format: "%.0f", eco.billedHours),
                        sub: eco.capacityHours > 0 ? String(format: "of %.0f the team can bill", eco.capacityHours) : "")
                FlatRow(label: "Jobs a week", value: String(format: "%.1f", eco.jobsPerWeek), sub: "each " + hoursText(eco.hoursPerJob))
                if let u = eco.utilisation {
                    FlatRow(label: "Utilisation", value: String(format: "%.0f%%", min(u, 1) * 100), sub: String(format: "planned %.0f%%; quiet weeks make each hour dearer", eco.plannedUtilisation * 100))
                }
                FlatRow(label: "Booked ahead", value: "\(eco.leadDays) days")
            } else {
                FlatRow(label: "In stock", value: "\(eco.stock)", sub: eco.onOrder > 0 ? "\(eco.onOrder) on order" : "", rule: false)
            }
            FlatRow(label: "Clients", value: eco.clientLabel)
            if let n = eco.clients {
                FlatRow(label: "Retainer clients", value: String(format: "%.0f", n), sub: String(format: "%.1f%% leave each month", eco.churn * 100))
            }
            if eco.writeOffShare > 0 {
                FlatRow(label: "Written off", value: itemAmount(eco.weeklyWriteOff, cur), sub: String(format: "%.0f%% never collected, a week", eco.writeOffShare * 100))
            }
        }
    }

    private func commit(_ price: Double) {
        let id: Int = companyID
        let item: String = itemID
        let r = store.act { $0.setItemPrice(companyID: id, itemID: item, price: price) }
        draftRate = nil
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
    }
}
