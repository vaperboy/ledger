import SwiftUI
import Charts
import GameCore
import Countries
import Businesses
import Simulation

struct CompanyContracts: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var showTenders = false
    @State private var openContract: Int? = nil
    @State private var ending: Int? = nil
    @State private var openTender: Int? = nil
    @State private var priceIndex = 3
    @State private var higherQuality = false
    @State private var pending: PendingAction?
    private let prices: [Double] = [0.85, 0.9, 0.95, 1.0, 1.05, 1.1]

    private struct Span: Identifiable {
        var id: String
        var start: Int
        var end: Int
        var warned: Bool
    }

    var body: some View {
        let open: [ProjectTenders.Tender] = openVolumeTenders
        let any: Bool = !engine.volumeContracts(companyID: company.id).isEmpty || !engine.bookedOrders(companyID: company.id).isEmpty
        PageGroup(title: "Volume contracts", spacing: Theme.Space.m, trailing: { EmptyView() }) {
            if any { summary }
            if !open.isEmpty {
                LedgerRow(leading: .glyph(Glyph.reports), leadingTint: Theme.inkSoft, title: "Tenders", subtitle: "Volume contracts you can bid for",
                          value: "\(open.count)", valueNote: "open", identifier: "contracts-tenders") { showTenders = true }
            }
            running
        }
        .navigationDestination(isPresented: $showTenders) {
            SettingsPage(title: "Tenders", subtitle: company.name) { tenders(openVolumeTenders) }
                .confirmAction($pending)
        }
    }

    private var openVolumeTenders: [ProjectTenders.Tender] {
        guard engine.projectBoard(companyID: company.id) == nil, ProjectTenders.catalog[company.type] != nil else { return [] }
        return ProjectTenders.openTenders(engine.state, for: company).filter { $0.isVolume }
    }

    @ViewBuilder private var summary: some View {
        let list = engine.volumeContracts(companyID: company.id)
        let load = engine.contractLoad(companyID: company.id)
        let details: [VolumeContracts.Detail] = list.compactMap { engine.contractDetail(companyID: company.id, contractID: $0.id) }
        let worth: Double = details.reduce(0) { $0 + $1.worthAYear }
        let unpaid: Double = details.reduce(0) { $0 + $1.outstanding }
        let share: Double = load.capacityShare
        let cells: [StatStrip.Cell] = [
            StatStrip.Cell(label: "Contracts", value: "\(list.count)"),
            StatStrip.Cell(label: "Worth a year", value: store.short(worth, in: company)),
            StatStrip.Cell(label: "Unpaid invoices", value: store.short(unpaid, in: company), tint: unpaid > 0 ? Theme.caution : Theme.ivory)
        ]
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Promised each week").capsLabel()
                    Spacer(minLength: 8)
                    GlyphView(glyph: Glyph.reports, size: 16, weight: 1.6)
                }
                Text("\(String(format: "%.1f", load.units)) units").font(.hero(30)).foregroundStyle(Theme.ivory)
                RateBar(label: "Of capacity", fraction: share, tint: share > 0.8 ? Theme.caution : Theme.gold)
                StatStrip(cells: cells)
            }
        }
    }

    @ViewBuilder private var running: some View {
        let list = engine.volumeContracts(companyID: company.id).sorted { $0.endWeek < $1.endWeek }
        let orders = engine.bookedOrders(companyID: company.id)
        if list.isEmpty && orders.isEmpty {
            Text("None yet. Offers from business customers arrive in the Inbox.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
        if !list.isEmpty {
            timelineCard(list)
            Text("Units not served bring warnings, then a penalty.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
            ForEach(list) { c in contractCard(c) }
        }
        if !orders.isEmpty { ordersCard(orders) }
    }

    private func timelineCard(_ list: [VolumeContracts.Contract]) -> some View {
        let now: Int = engine.state.week
        let spans: [Span] = list.map { Span(id: "\($0.id)", start: $0.startWeek, end: $0.endWeek, warned: $0.warnings > 0) }
        let first: Int = min(now, spans.map { $0.start }.min() ?? now)
        let last: Int = max(now + 1, spans.map { $0.end }.max() ?? now + 1)
        let nextEnd: String = GameCalendar.dateString(week: list.first?.endWeek ?? now)
        return Card(padding: 14, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Terms and expiry").capsLabel()
                    Spacer(minLength: 8)
                    Text("Next ends \(nextEnd)").textStyle(.caption, tint: Theme.inkFaint)
                }
                Chart {
                    ForEach(spans) { s in
                        BarMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end), y: .value("Contract", s.id), height: .fixed(7))
                            .foregroundStyle(s.warned ? Theme.caution : Theme.gold)
                            .cornerRadius(3)
                    }
                    RuleMark(x: .value("Now", now))
                        .foregroundStyle(Theme.ivory.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXScale(domain: first...last)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                        AxisValueLabel {
                            if let w = v.as(Int.self) { Text(GameCalendar.dateString(week: w)).textStyle(.caption, tint: Theme.inkFaint) }
                        }
                    }
                }
                .frame(height: CGFloat(spans.count) * 15 + 26)
            }
        }
    }

    private func ordersCard(_ orders: [(customer: String, units: Double, week: Int)]) -> some View {
        Card(padding: 14, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    GlyphView(glyph: Glyph.clock, size: 15, weight: 1.6)
                    Text("Booked orders").capsLabel()
                }
                ForEach(Array(orders.enumerated()), id: \.offset) { n, o in
                    if n > 0 { CardLine() }
                    row("\(o.customer) · \(String(format: "%.1f", o.units)) units", GameCalendar.dateString(week: o.week))
                }
            }
        }
    }

    private func contractCard(_ c: VolumeContracts.Contract) -> some View {
        let d = engine.contractDetail(companyID: company.id, contractID: c.id)
        let isOpen: Bool = openContract == c.id
        let worth: String = d.map { store.short($0.worthAYear, in: company) } ?? ""
        let endsText: String = "Ends \(GameCalendar.dateString(week: c.endWeek))"
        let warned: Bool = c.warnings > 0
        let edge: Color = warned ? Theme.caution.opacity(0.6) : Theme.border
        let iconTint: Color = warned ? Theme.caution : Theme.gold
        let warnText: String = "\(Int(c.warnings)) warning\(Int(c.warnings) == 1 ? "" : "s")"
        let sub: String = "\(c.customer)\(c.buyerIsPlayer ? " (a player)" : "") · \(String(format: "%.1f", c.units)) a week · \(c.reliabilityWord.lowercased()) payer"
        return Card(padding: 12, radius: Theme.Radius.row, stroke: edge) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Motion.animate(Motion.quickAnimation) { openContract = isOpen ? nil : c.id; ending = nil }
                    Haptics.choose()
                } label: {
                    HStack(spacing: 12) {
                        IconCircle(glyph: warned ? Glyph.warning : Glyph.reports, size: 38, tint: iconTint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                            Text(sub).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(worth).textStyle(.headline, numeric: true)
                            Text(endsText).textStyle(.caption)
                            if warned { Chip(text: warnText, tint: Theme.caution) }
                        }
                        GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim).rotationEffect(.degrees(isOpen ? -90 : 90))
                    }.contentShape(Rectangle())
                }.buttonStyle(PressableStyle())
                if isOpen, let d {
                    CardLine()
                    contractSheet(c, d)
                }
            }
        }
    }

    private func contractSheet(_ c: VolumeContracts.Contract, _ d: VolumeContracts.Detail) -> some View {
        let discountText: String = c.discount > 0.0005 ? " · \(Int(saturating: (c.discount * 100).rounded()))% below list" : c.discount < -0.0005 ? " · above list" : ""
        let extText: String = c.extensionsLeft > 0 ? " · \(c.extensionsLeft) extension\(c.extensionsLeft == 1 ? "" : "s") left" : ""
        return VStack(alignment: .leading, spacing: 8) {
            row("Price per unit", store.money(d.price, in: company) + discountText)
            row("Worth a year", store.short(d.worthAYear, in: company))
            row("Term", "\(d.weeksLeft.weeksText) left" + extText)
            row("Customer pays after", c.paymentWeeks.weeksText)
            row("Unpaid invoices", store.short(d.outstanding, in: company))
            row("Warnings", "\(Int(c.warnings)) of 12" + (c.higherQuality ? " · higher quality promised" : ""))
            Text("Below 85% served: a penalty at 6 warnings, cancelled at 12.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            if ending == c.id {
                Text("Ending it now costs a penalty of about \(store.short(0.4 * d.price * c.units, in: company)) (10% of four weeks' business) and hurts your name.")
                    .textStyle(.caption, tint: Theme.loss).fixedSize(horizontal: false, vertical: true)
                HStack {
                    QuietButton(title: "Keep it", tint: Theme.ivoryMuted) { ending = nil }
                    Spacer()
                    QuietButton(title: "End the contract", tint: Theme.loss) {
                        let ok = store.act { $0.endContract(companyID: company.id, contractID: c.id) }
                        if ok == true { Haptics.warning(); openContract = nil; store.show("Contract with \(c.customer) ended. Penalty about \(store.short(0.4 * d.price * c.units, in: company)).", tone: "n") }
                        else { Haptics.warning(); store.show("The contract could not be ended.", tone: "warn") }
                        ending = nil
                    }
                }
            } else {
                HStack { Spacer(); QuietButton(title: "End early", tint: Theme.loss) { ending = c.id } }
            }
        }
    }

    private func tenders(_ open: [ProjectTenders.Tender]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Best price and quality wins; a bid costs money even when it loses.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
            ForEach(open, id: \.id) { t in tenderCard(t) }
        }
    }

    private func tenderCard(_ t: ProjectTenders.Tender) -> some View {
        let q = ProjectTenders.qualification(t, company, week: engine.state.week)
        let mine = t.bid(of: company.id)
        let weeksToBid = max(0, t.closesWeek - engine.state.week)
        let isOpen: Bool = openTender == t.id
        let edge: Color = mine != nil ? Theme.gold.opacity(0.7) : Theme.border
        let sub: String = "\(t.buyer) · \(String(format: "%.1f", t.unitsPerWeek)) a week for \(t.years) years"
        let award: String = "Award \(GameCalendar.dateString(week: t.awardWeek))"
        return Card(padding: 12, radius: Theme.Radius.row, stroke: edge) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Motion.animate(Motion.quickAnimation) { openTender = isOpen ? nil : t.id }
                    Haptics.choose()
                } label: {
                    HStack(spacing: 12) {
                        IconCircle(glyph: Glyph.clock, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title.tidyMoney).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                            Text(sub).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2).multilineTextAlignment(.leading)
                            if !q.ok, let r = q.reason { Text(r).textStyle(.caption, tint: Theme.warn).multilineTextAlignment(.leading) }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            if let b = mine { Chip(text: "Bid \(Int(saturating: (b.priceFactor * 100).rounded()))%", tint: Theme.gold) }
                            else { Text("\(weeksToBid) wk to bid").textStyle(.caption, tint: Theme.accent, numeric: true) }
                            Text(award).textStyle(.caption)
                        }
                        GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim).rotationEffect(.degrees(isOpen ? -90 : 90))
                    }.contentShape(Rectangle())
                }.buttonStyle(PressableStyle())
                if isOpen {
                    CardLine()
                    tenderSheet(t, qualifies: q.ok, hasBid: mine != nil, weeksToBid: weeksToBid)
                }
            }
        }
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
        let capText: String = cap > 0 ? "\(Int(saturating: (share * 100).rounded()))% (with contracts \(Int(saturating: ((load.capacityShare + share) * 100).rounded()))%)" : "\(String(format: "%.1f", t.unitsPerWeek)) units a week"
        let priceText: String = "\(Int(saturating: (pf * 100).rounded()))% of list" + (pf < 1 ? " · \(Int(saturating: ((1 - pf) * 100).rounded()))% discount" : "")
        let termText: String = "\(t.years) years" + (t.extensions > 0 ? ", up to \(t.extensions) one-year extensions" : "")
        return VStack(alignment: .leading, spacing: 8) {
            row("Scored on", t.priceWeight >= 1 ? "Price only" : "Price \(Int(saturating: (t.priceWeight * 100).rounded()))% · quality \(Int(saturating: ((1 - t.priceWeight) * 100).rounded()))%")
            row("Your price", priceText)
            row("Worth a year at your price", store.short(t.worth * pf / years, in: company))
            row("Term", termText)
            row("Buyer pays after", payWeeks.weeksText)
            row("Takes of your capacity", capText)
            row("Bids close", "in \(weeksToBid.weeksText) · award \(GameCalendar.dateString(week: t.awardWeek))")
            row("Writing the bid costs", store.money(t.bidCost, in: company))
            Text(riskText(t, overCapacity: overCapacity)).font(.system(size: 11)).foregroundStyle(overCapacity ? Theme.caution : Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            if hasBid {
                Text("Bid sent.").textStyle(.caption, tint: Theme.inkFaint)
                QuietButton(title: "Take the bid back") { store.settle(store.act { $0.withdrawBid(companyID: company.id, tenderID: t.id) }, "Your bid is withdrawn.", same: "The bid could not be taken back: the bidding has closed.") }
            } else if !qualifies {
                Text("The firm does not meet the buyer's requirements yet.").textStyle(.caption, tint: Theme.warn)
            } else {
                Text("Your price against your list price").capsLabel(Theme.ivoryFaint)
                SegmentedPill(items: Array(prices.indices), title: { "\(Int(saturating: (prices[$0] * 100).rounded()))%" }, selection: $priceIndex)
                Toggle(isOn: $higherQuality) {
                    Text("Commit to higher quality (costs about 3% more to deliver)").textStyle(.caption, tint: Theme.ink)
                }.tint(Theme.gold)
                QuietButton(title: "Send the bid…") {
                    let hq = higherQuality
                    pending = PendingAction(title: "Bid \(Int(saturating: (pf * 100).rounded()))% of list?", message: "Writing the bid costs \(store.money(t.bidCost, in: company)) even if you lose. Worth about \(store.short(t.worth * pf / years, in: company)) a year if you win; the result comes on \(GameCalendar.dateString(week: t.awardWeek)).",
                                            button: "Send for \(store.short(t.bidCost, in: company))", amount: t.bidCost, currency: engine.currency(for: company), tone: .warning, icon: "doc.text") {
                        let r = store.act { $0.bidOnTender(companyID: company.id, tenderID: t.id, priceFactor: pf, higherQuality: hq) }
                        switch r {
                        case .sent?: Haptics.success(); store.show("Bid sent at \(Int(saturating: (pf * 100).rounded()))% of list. The result comes on \(GameCalendar.dateString(week: t.awardWeek)).", tone: "good"); openTender = nil
                        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company to write the bid (\(store.short(t.bidCost, in: company))).", tone: "warn")
                        case .notQualified(let why)?: Haptics.warning(); store.show(why, tone: "warn")
                        case nil: break
                        default: Haptics.warning(); store.show("This tender has closed.", tone: "warn")
                        }
                    }
                }
            }
        }
    }

    private func riskText(_ t: ProjectTenders.Tender, overCapacity: Bool) -> String {
        var s = t.isPublicBuyer ? "A public buyer is a solid payer." : "A private buyer is a less certain payer: it can go under and its unpaid invoices are lost."
        s += " If you cannot serve the volume (below 85%) you get warnings, a penalty at six and lose the contract and some reputation at twelve."
        if overCapacity { s += " This is more than the room you have left, so a manager would not bid for it." }
        return s
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).textStyle(.caption)
            Spacer(minLength: 8)
            Text(value).textStyle(.caption, tint: Theme.ink, numeric: true).multilineTextAlignment(.trailing)
        }
    }
}
