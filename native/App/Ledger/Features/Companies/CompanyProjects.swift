import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The order book of a project company: jobs on the go and waiting, tenders to bid for, and for a real-estate developer
/// the developments (zoning, building, selling) and the sheet that starts a new one. Everything is read from
/// `engine.projectBoard` and changed through the engine's project actions; no money is worked out here.
struct CompanyProjects: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        if let board = engine.projectBoard(companyID: company.id) {
            if board.isDeveloper {
                DevelopmentList(engine: engine, company: company, board: board)
            } else {
                JobList(engine: engine, company: company, board: board)
            }
        } else {
            Text("This business does not take projects.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
        }
    }
}

// MARK: Jobs, tenders

private struct JobList: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var board: ProjectBoard
    @State private var openTender: Int? = nil
    @State private var priceIndex = 3
    @State private var higherQuality = false
    private let prices: [Double] = [0.85, 0.9, 0.95, 1.0, 1.05, 1.1]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            KeyFigures(items: [
                .init(label: board.isEvent ? "Booked" : "Booked ahead", value: board.weeksBooked < 0.2 ? "Nothing yet" : String(format: "%.1f wk", board.weeksBooked),
                      tint: board.weeksBooked > 3 ? Theme.caution : Theme.ivory, sub: "\(Int(board.bookedHours.rounded())) of \(Int(board.hoursPerWeek.rounded())) h a week"),
                .init(label: "Still to be paid", value: store.short(board.outstandingPayments, in: company), sub: "on jobs in hand"),
                .init(label: board.isEvent ? "Delivered" : "Finished", value: "\(board.finishedCount)", sub: "since opening"),
            ])
            LedgerSection(title: board.isEvent ? "Bookings" : "Jobs on the go", trailing: {
                Text("last week \(board.lastWeekTaken) of \(board.lastWeekRequests) requests taken").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                if board.jobs.isEmpty && board.queuedJobs.isEmpty {
                    Text(board.hoursPerWeek > 0 ? "Nothing booked yet. Requests come in through the week; marketing and a good name bring more." : "The firm cannot take work yet: check staff and equipment under Operations.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                }
                VStack(spacing: 0) {
                    ForEach(Array(board.jobs.enumerated()), id: \.element.id) { n, j in
                        jobRow(j)
                        if n < board.jobs.count - 1 || !board.queuedJobs.isEmpty { Hairline() }
                    }
                    if !board.queuedJobs.isEmpty {
                        Text("Waiting their turn").capsLabel(Theme.ivoryFaint).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10).padding(.bottom, 4)
                        ForEach(Array(board.queuedJobs.enumerated()), id: \.element.id) { n, j in
                            jobRow(j)
                            if n < board.queuedJobs.count - 1 { Hairline() }
                        }
                    }
                }
                Text(board.isEvent
                     ? "Clients pay 30% when they book and the rest after the event. Preparation goes to the nearest date first; a booking is turned away when the team cannot prepare it in time."
                     : "Short jobs are paid when finished. Big or long jobs pay 30% at the start, 40% halfway and the rest at the end. Business clients then pay their invoices after a few weeks. New requests are turned away when you are booked more than three weeks ahead.")
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
            tenders
        }
    }

    private func jobRow(_ j: ProjectBoard.JobRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(j.title.tidyMoney).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Text(subtitle(j)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(store.short(j.value, in: company)).font(.figure(13.5, weight: .semibold)).foregroundStyle(Theme.ivory)
                    Text("margin before pay \(Int((j.margin * 100).rounded()))%").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                }
            }
            if j.started {
                RateBar(label: "\(Int(j.hoursDone.rounded())) of \(Int(j.hours.rounded())) h", fraction: j.progress, tint: j.held ? Theme.caution : Theme.gain)
                if j.held { Text("Held up").font(.system(size: 11)).foregroundStyle(Theme.caution) }
            }
        }
        .padding(.vertical, 9)
    }

    private func subtitle(_ j: ProjectBoard.JobRow) -> String {
        var parts = [j.client]
        if let w = j.dueWeek, board.isEvent { parts.append("on \(GameCalendar.dateString(week: w))") }
        else { parts.append("\(Int(j.quotedHours.rounded())) h"); if j.isPublic { parts.append("public client") } }
        if j.paid > 0 { parts.append("paid \(store.short(j.paid, in: company))") }
        return parts.joined(separator: " · ")
    }

    // Tenders: buyers publish work; the best score on price and quality wins.
    @ViewBuilder private var tenders: some View {
        if ProjectTenders.catalog[company.type] != nil {
            LedgerSection(title: "Tenders", trailing: {
                if board.hasManager {
                    Button { store.act { $0.setManagerBids(companyID: company.id, on: !board.managerBids) }; Haptics.choose() } label: {
                        Text(board.managerBids ? "Manager bids: on" : "Manager bids: off").font(.system(size: 11.5)).foregroundStyle(Theme.gold)
                    }.buttonStyle(.plain)
                }
            }) {
                Text("Buyers publish work, firms bid, and the best score wins: price against quality in the buyer's own weights. Writing a bid costs money even when you lose.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                if board.tenders.isEmpty {
                    Text("Nothing is open for tender right now. New ones come every few weeks.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                }
                VStack(spacing: 0) {
                    ForEach(Array(board.tenders.enumerated()), id: \.element.id) { n, t in
                        tenderRow(t)
                        if n < board.tenders.count - 1 { Hairline() }
                    }
                }
                let results = board.myTenders.filter { $0.outcome != nil }
                if !results.isEmpty {
                    Text("Results").capsLabel(Theme.ivoryFaint).padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(results.prefix(5).enumerated()), id: \.element.id) { n, t in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.title.tidyMoney).font(.system(size: 13)).foregroundStyle(Theme.ivory).lineLimit(1)
                                    Text(t.buyer).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                                }
                                Spacer()
                                Chip(text: t.outcome == "won" ? "Won" : t.outcome == "lost" ? "Lost" : "Closed", tint: t.outcome == "won" ? Theme.gain : Theme.ivoryMuted)
                            }.padding(.vertical, 8)
                            if n < min(5, results.count) - 1 { Hairline() }
                        }
                    }
                }
            }
        }
    }

    private func tenderRow(_ t: ProjectBoard.TenderRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { openTender = openTender == t.id ? nil : t.id }
                Haptics.choose()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title.tidyMoney).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                        Text("\(t.buyer) · about \(store.short(t.worth, in: company))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                        if let r = t.requirement, !t.qualifies { Text("Needs \(r)").font(.system(size: 11)).foregroundStyle(Theme.caution) }
                    }
                    Spacer(minLength: 8)
                    if let b = t.myBid { Chip(text: "Bid \(Int((b * 100).rounded()))%", tint: Theme.gold) }
                    else { Text("\(t.weeksToBid) wk to bid").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.gold) }
                }
            }.buttonStyle(.plain)
            if openTender == t.id { tenderSheet(t) }
        }
        .padding(.vertical, 9)
    }

    private func tenderSheet(_ t: ProjectBoard.TenderRow) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            valueRow("Scored on", t.priceWeight >= 1 ? "Price only" : "Price \(Int((t.priceWeight * 100).rounded()))% · quality \(Int(((1 - t.priceWeight) * 100).rounded()))%")
            valueRow("Bids close", "in \(t.weeksToBid.weeksText) · award \(GameCalendar.dateString(week: t.awardWeek))")
            valueRow("Writing the bid costs", store.money(t.bidCost, in: company))
            if t.myBid != nil {
                Text("Your bid is in. You can take it back until the bids close; sending a new one costs the writing fee again.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                Button("Take the bid back") { store.settle(store.act { $0.withdrawBid(companyID: company.id, tenderID: t.id) }, "Your bid is withdrawn.", same: "The bid could not be taken back: the bidding has closed.") }
                    .buttonStyle(SmallOutlineButtonStyle())
            } else if !t.qualifies {
                Text("The firm does not meet the buyer's requirements yet.").font(.system(size: 11.5)).foregroundStyle(Theme.caution)
            } else {
                Text("Your price against your list price").capsLabel(Theme.ivoryFaint)
                SectionTabs(items: Array(prices.indices), title: { "\(Int((prices[$0] * 100).rounded()))%" }, selection: $priceIndex).padding(.horizontal, -Theme.Space.margin)
                Toggle(isOn: $higherQuality) {
                    Text("Commit to higher quality (costs about 3% more to deliver)").font(.system(size: 12.5)).foregroundStyle(Theme.ivory)
                }.tint(Theme.gold)
                Text("Lower prices win more often on price-heavy tenders, but you deliver at that price.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                Button("Send the bid") {
                    let r = store.act { $0.bidOnTender(companyID: company.id, tenderID: t.id, priceFactor: prices[priceIndex], higherQuality: higherQuality) }
                    switch r {
                    case .sent?: Haptics.success(); store.show("Bid sent. The result comes on \(GameCalendar.dateString(week: t.awardWeek)).", tone: "good"); openTender = nil
                    case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company to write the bid.", tone: "warn")
                    case .notQualified(let why)?: Haptics.warning(); store.show(why, tone: "warn")
                    default: Haptics.warning(); store.show("This tender has closed.", tone: "warn")
                    }
                }.buttonStyle(SmallGoldButtonStyle())
            }
        }
        .padding(.bottom, 4)
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: Developments

private struct DevelopmentList: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var board: ProjectBoard
    @State private var sizeIndex = 2
    @State private var financed = true
    @State private var showStart = false
    private let sizes: [(name: String, factor: Double)] = [("Small", 0.4), ("Half", 0.5), ("Full", 1.0)]

    var body: some View {
        let active = board.developments
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            KeyFigures(items: [
                .init(label: "Running", value: "\(active.count)", sub: "developments"),
                .init(label: "Tied up in work", value: store.short(active.reduce(0) { $0 + $1.workInProgress }, in: company), sub: "land and building so far"),
                .init(label: "Finished", value: "\(board.finishedCount)", sub: "sold out"),
            ])
            LedgerSection(title: "Developments", trailing: {
                Button { withAnimation(.snappy(duration: 0.2)) { showStart.toggle() }; Haptics.choose() } label: {
                    Text(showStart ? "Close" : "Start a project").font(.system(size: 11.5)).foregroundStyle(Theme.gold)
                }.buttonStyle(.plain)
            }) {
                if showStart { startSheet }
                if active.isEmpty && !showStart {
                    Text("No project yet. Buy land and wait for zoning (about six months, and it can be refused), build (about 16 months), then sell the units. The first income arrives roughly two years after you start, so keep cash for the wait.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    ForEach(Array(active.enumerated()), id: \.element.id) { n, p in
                        projectRow(p)
                        if n < active.count - 1 { Hairline() }
                    }
                }
                Text("Zoning can be rejected or delayed. Building costs overrun. Sales depend on the housing market.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }
            if !board.finishedDevelopments.isEmpty {
                LedgerSection("Finished") {
                    VStack(spacing: 0) {
                        ForEach(Array(board.finishedDevelopments.enumerated()), id: \.element.id) { n, f in
                            let profit = f.revenue - f.cost
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                                    Text("sold for \(store.short(f.revenue, in: company)) · cost \(store.short(f.cost, in: company))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer(minLength: 8)
                                Text((profit < 0 ? "−" : "+") + store.short(abs(profit), in: company)).font(.figure(13.5, weight: .semibold)).foregroundStyle(profit < 0 ? Theme.loss : Theme.gain)
                            }.padding(.vertical, 8)
                            if n < board.finishedDevelopments.count - 1 { Hairline() }
                        }
                    }
                }
            }
        }
    }

    private var startSheet: some View {
        let size = sizes[sizeIndex].factor
        let q = engine.developmentQuote(companyID: company.id, size: size, financed: financed)
        return VStack(alignment: .leading, spacing: 9) {
            SectionTabs(items: Array(sizes.indices), title: { sizes[$0].name }, selection: $sizeIndex).padding(.horizontal, -Theme.Space.margin)
            Toggle(isOn: $financed) { Text("Construction loan (up to 70% of the building)").font(.system(size: 12.5)).foregroundStyle(Theme.ivory) }.tint(Theme.gold)
            if let q {
                row("Land", store.short(q.land, in: company))
                row("Building", store.short(q.build, in: company))
                row("Units", "\(q.units) at about \(store.short(q.unitPrice, in: company))")
                row("Cash needed now", store.money(q.cashNow, in: company))
                if q.financed { row("Loan", store.short(q.loanAmount, in: company)) }
                row("Brings in, if all sold", store.short(q.expectedRevenue, in: company))
            }
            Button("Buy the land and start") {
                switch store.act({ $0.startDevelopment(companyID: company.id, size: size, financed: financed) }) {
                case .started?: Haptics.success(); store.show("Project started. Zoning takes about six months.", tone: "good"); showStart = false
                case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company.", tone: "warn")
                case .loanRefused?: Haptics.warning(); store.show("The bank will not lend that much. Try a smaller project or fund it with equity.", tone: "warn")
                default: Haptics.warning(); store.show("The company must be open to start a project.", tone: "warn")
                }
            }.buttonStyle(SmallGoldButtonStyle())
        }
        .padding(.bottom, 6)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory)
        }
    }

    private func stageText(_ p: ProjectBoard.DevelopmentRow) -> String {
        switch p.stage {
        case "zoning": return "Zoning · \(p.weeksLeft) wk left"
        case "build": return "Building · \(p.weeksLeft) wk left" + (p.delayWeeks > 0 ? " · held up" : "")
        case "sell": return "Selling"
        default: return "Done"
        }
    }

    private func projectRow(_ p: ProjectBoard.DevelopmentRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Text(stageText(p)).font(.system(size: 11)).foregroundStyle(p.delayWeeks > 0 ? Theme.caution : Theme.ivoryFaint)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(p.sold) / \(p.units) sold").font(.figure(13.5, weight: .semibold)).foregroundStyle(Theme.ivory)
                    Text("land \(store.short(p.land, in: company)) · build \(store.short(p.build, in: company))").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                }
            }
            RateBar(label: "Sold", fraction: p.units > 0 ? Double(p.sold) / Double(p.units) : 0, tint: Theme.gain)
            if p.loanBalance > 0 { Text("Construction loan \(store.short(p.loanBalance, in: company)), repaid from 70% of each sale").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
            HStack {
                Text("Price per unit \(store.short(p.unitPrice * p.priceMultiplier, in: company))").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted)
                Spacer()
                ForEach([0.9, 1.0, 1.1], id: \.self) { m in
                    Button {
                        store.act { $0.setDevelopmentPrice(companyID: company.id, projectID: p.id, multiplier: m) }; Haptics.choose()
                    } label: {
                        Text(m == 0.9 ? "−10%" : m == 1.0 ? "Standard" : "+10%").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(abs(p.priceMultiplier - m) < 0.001 ? Theme.ivory : Theme.ivoryFaint)
                            .padding(.bottom, 2).overlay(alignment: .bottom) { if abs(p.priceMultiplier - m) < 0.001 { Rectangle().fill(Theme.gold).frame(height: 1) } }
                    }.buttonStyle(.plain).padding(.leading, 8)
                }
            }
        }
        .padding(.vertical, 9)
    }
}
