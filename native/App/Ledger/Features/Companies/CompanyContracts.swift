import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Volume contracts with business customers and the volume tenders on offer, inside Customers. Everything is read from the engine
/// (`volumeContracts`, `contractLoad`, `contractDetail`, `ProjectTenders.openTenders`) and changed through `endContract` and
/// `bidOnTender`; the engine works out the money. Contract offers from customers arrive in the inbox (`signContract` is used by tenders).
struct CompanyContracts: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var openContract: Int? = nil
    @State private var ending: Int? = nil
    @State private var openTender: Int? = nil
    @State private var priceIndex = 3
    @State private var higherQuality = false
    private let prices: [Double] = [0.85, 0.9, 0.95, 1.0, 1.05, 1.1]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            contracts
            tenders
        }
    }

    // MARK: Contracts

    @ViewBuilder private var contracts: some View {
        let list = engine.volumeContracts(companyID: company.id)
        let orders = engine.bookedOrders(companyID: company.id)
        if !list.isEmpty || !orders.isEmpty {
            let load = engine.contractLoad(companyID: company.id)
            LedgerSection(title: "Volume contracts", trailing: {
                Text("\(Int((load.capacityShare * 100).rounded()))% of capacity").font(.system(size: 11)).foregroundStyle(load.capacityShare > 0.8 ? Theme.caution : Theme.ivoryFaint)
            }) {
                VStack(alignment: .leading, spacing: 0) {
                    if !list.isEmpty {
                        Text("\(String(format: "%.1f", load.units)) units a week are promised. A shop that cannot serve them gets warnings, then a penalty, and in the end loses the contract.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
                    }
                    ForEach(Array(list.enumerated()), id: \.element.id) { n, c in
                        if n > 0 { Hairline() }
                        contractRow(c)
                    }
                    if !orders.isEmpty {
                        if !list.isEmpty { Hairline() }
                        Text("Booked orders").capsLabel(Theme.ivoryFaint).padding(.top, 8).padding(.bottom, 4)
                        ForEach(Array(orders.enumerated()), id: \.offset) { _, o in
                            row("\(o.customer) · \(String(format: "%.1f", o.units)) units", "week \(o.week)")
                        }
                    }
                }
            }
        }
    }

    private func contractRow(_ c: VolumeContracts.Contract) -> some View {
        let d = engine.contractDetail(companyID: company.id, contractID: c.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { openContract = openContract == c.id ? nil : c.id; ending = nil }
                Haptics.choose()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                        Text("\(c.customer) · \(String(format: "%.1f", c.units)) a week · \(c.reliabilityWord.lowercased()) payer")
                            .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if c.warnings > 0 { Chip(text: "\(Int(c.warnings)) warning\(Int(c.warnings) == 1 ? "" : "s")", tint: Theme.caution) }
                    else if let d { Text("\(d.weeksLeft) wk left").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.ivoryMuted) }
                }
            }.buttonStyle(.plain)
            if openContract == c.id, let d {
                contractSheet(c, d)
            }
        }.padding(.vertical, 9)
    }

    private func contractSheet(_ c: VolumeContracts.Contract, _ d: VolumeContracts.Detail) -> some View {
        let discountText: String = c.discount > 0.0005 ? " · \(Int((c.discount * 100).rounded()))% below list" : c.discount < -0.0005 ? " · above list" : ""
        let extText: String = c.extensionsLeft > 0 ? " · \(c.extensionsLeft) extension\(c.extensionsLeft == 1 ? "" : "s") left" : ""
        return VStack(alignment: .leading, spacing: 8) {
            row("Price per unit", store.money(d.price, in: company) + discountText)
            row("Worth a year", store.short(d.worthAYear, in: company))
            row("Term", "\(d.weeksLeft.weeksText) left" + extText)
            row("Customer pays after", c.paymentWeeks.weeksText)
            row("Unpaid invoices", store.short(d.outstanding, in: company))
            row("Warnings", "\(Int(c.warnings)) of 12" + (c.higherQuality ? " · higher quality promised" : ""))
            Text("Risks: a customer can go under (its unpaid invoices are lost), walk away from poor quality or not renew. Below 85% served, warnings build up: a penalty at six, the contract is cancelled at twelve.")
                .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            if ending == c.id {
                Text("Ending it now costs a penalty of about \(store.short(0.4 * d.price * c.units, in: company)) (10% of four weeks' business) and hurts your name.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Keep it") { ending = nil }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                    Spacer()
                    Button("End the contract") {
                        let ok = store.act { $0.endContract(companyID: company.id, contractID: c.id) }
                        if ok == true { Haptics.warning(); openContract = nil } else { store.show("The contract could not be ended.", tone: "warn") }
                        ending = nil
                    }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                }
            } else {
                HStack { Spacer(); Button("End early") { ending = c.id; Haptics.tap() }.buttonStyle(QuietButtonStyle(tint: Theme.loss)) }
            }
        }
    }

    // MARK: Tenders (project companies show theirs in Projects)

    @ViewBuilder private var tenders: some View {
        if engine.projectBoard(companyID: company.id) == nil, ProjectTenders.catalog[company.type] != nil {
            let open = ProjectTenders.openTenders(engine.state, for: company).filter { $0.isVolume }
            if !open.isEmpty {
                LedgerSection(title: "Volume tenders", trailing: {
                    Text("\(open.count) open").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Buyers want a set volume every week. Bid a price against your list price; the best score on price and quality wins. Writing a bid costs money even when you lose.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
                        ForEach(Array(open.enumerated()), id: \.element.id) { n, t in
                            if n > 0 { Hairline() }
                            tenderRow(t)
                        }
                    }
                }
            }
        }
    }

    private func tenderRow(_ t: ProjectTenders.Tender) -> some View {
        let q = ProjectTenders.qualification(t, company, week: engine.state.week)
        let mine = t.bid(of: company.id)
        let weeksToBid = max(0, t.closesWeek - engine.state.week)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { openTender = openTender == t.id ? nil : t.id }
                Haptics.choose()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                        Text("\(t.buyer) · \(String(format: "%.1f", t.unitsPerWeek)) a week for \(t.years) years").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                        if !q.ok, let r = q.reason { Text(r).font(.system(size: 11)).foregroundStyle(Theme.caution) }
                    }
                    Spacer(minLength: 8)
                    if let b = mine { Chip(text: "Bid \(Int((b.priceFactor * 100).rounded()))%", tint: Theme.gold) }
                    else { Text("\(weeksToBid) wk to bid").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.gold) }
                }
            }.buttonStyle(.plain)
            if openTender == t.id { tenderSheet(t, qualifies: q.ok, hasBid: mine != nil, weeksToBid: weeksToBid) }
        }.padding(.vertical, 9)
    }

    private func tenderSheet(_ t: ProjectTenders.Tender, qualifies: Bool, hasBid: Bool, weeksToBid: Int) -> some View {
        let pf = prices[min(max(0, priceIndex), prices.count - 1)]
        let lw = company.value("lastW")
        let cap = lw["cap"].double
        let share = cap > 0 ? t.unitsPerWeek / cap : 0
        let room = max(0, 1 - lw["util"].double)
        let overCapacity = cap > 0 && t.unitsPerWeek > cap * room
        let load = engine.contractLoad(companyID: company.id)
        let payWeeks = t.isPublicBuyer ? 4 : 6
        let years = Double(max(1, t.years))
        let capText: String = cap > 0 ? "\(Int((share * 100).rounded()))% (with contracts \(Int(((load.capacityShare + share) * 100).rounded()))%)" : "\(String(format: "%.1f", t.unitsPerWeek)) units a week"
        let priceText: String = "\(Int((pf * 100).rounded()))% of list" + (pf < 1 ? " · \(Int(((1 - pf) * 100).rounded()))% discount" : "")
        let termText: String = "\(t.years) years" + (t.extensions > 0 ? ", up to \(t.extensions) one-year extensions" : "")
        return VStack(alignment: .leading, spacing: 8) {
            row("Scored on", t.priceWeight >= 1 ? "Price only" : "Price \(Int((t.priceWeight * 100).rounded()))% · quality \(Int(((1 - t.priceWeight) * 100).rounded()))%")
            row("Your price", priceText)
            row("Worth a year at your price", store.short(t.worth * pf / years, in: company))
            row("Term", termText)
            row("Buyer pays after", payWeeks.weeksText)
            row("Takes of your capacity", capText)
            row("Bids close", "in \(weeksToBid.weeksText) · award \(GameCalendar.dateString(week: t.awardWeek))")
            row("Writing the bid costs", store.money(t.bidCost, in: company))
            Text(riskText(t, overCapacity: overCapacity)).font(.system(size: 11)).foregroundStyle(overCapacity ? Theme.caution : Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            if hasBid {
                Text("Your bid is in. You can take it back until the bids close; sending a new one costs the writing fee again.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                Button("Take the bid back") { store.act { $0.withdrawBid(companyID: company.id, tenderID: t.id) }; Haptics.tap() }.buttonStyle(SmallOutlineButtonStyle())
            } else if !qualifies {
                Text("The firm does not meet the buyer's requirements yet.").font(.system(size: 11.5)).foregroundStyle(Theme.caution)
            } else {
                Text("Your price against your list price").capsLabel(Theme.ivoryFaint)
                SectionTabs(items: Array(prices.indices), title: { "\(Int((prices[$0] * 100).rounded()))%" }, selection: $priceIndex).padding(.horizontal, -Theme.Space.margin)
                Toggle(isOn: $higherQuality) {
                    Text("Commit to higher quality (costs about 3% more to deliver)").font(.system(size: 12.5)).foregroundStyle(Theme.ivory)
                }.tint(Theme.gold)
                Button("Send the bid") {
                    let r = store.act { $0.bidOnTender(companyID: company.id, tenderID: t.id, priceFactor: pf, higherQuality: higherQuality) }
                    switch r {
                    case .sent?: Haptics.success(); store.show("Bid sent. The result comes on \(GameCalendar.dateString(week: t.awardWeek)).", tone: "good"); openTender = nil
                    case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company to write the bid.", tone: "warn")
                    case .notQualified(let why)?: Haptics.warning(); store.show(why, tone: "warn")
                    default: Haptics.warning(); store.show("This tender has closed.", tone: "warn")
                    }
                }.buttonStyle(SmallGoldButtonStyle())
            }
        }.padding(.bottom, 4)
    }

    private func riskText(_ t: ProjectTenders.Tender, overCapacity: Bool) -> String {
        var s = t.isPublicBuyer ? "A public buyer is a solid payer." : "A private buyer is a less certain payer: it can go under and its unpaid invoices are lost."
        s += " If you cannot serve the volume (below 85%) you get warnings, a penalty at six and lose the contract and some reputation at twelve."
        if overCapacity { s += " This is more than the room you have left, so a manager would not bid for it." }
        return s
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory).multilineTextAlignment(.trailing)
        }
    }
}
