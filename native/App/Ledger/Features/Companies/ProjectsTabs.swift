import SwiftUI
import GameCore
import Businesses
import Simulation

typealias ProjectRows = [(co: Company, board: ProjectBoard)]

/// "5 Feb": the engine's date without the year.
func shortDate(week: Int) -> String {
    GameCalendar.dateString(week: week).split(separator: " ").dropLast().joined(separator: " ")
}

private extension View {
    func projectCard(radius: CGFloat = Theme.Radius.hero) -> some View {
        self.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// A caps label with an optional right-hand note (OPEN TENDERS, THIS AND NEXT WEEK).
private struct ProjectCaps: View {
    var title: String
    var note: String = ""
    var body: some View {
        HStack {
            Text(title).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold)
            Spacer(minLength: 8)
            if !note.isEmpty { Text(note).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
        }
    }
}

/// Three figures under a hairline, separated by vertical rules (Value / Costs so far / Due).
private struct ProjectFigures: View {
    var items: [(String, String, Color)]
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { n, it in
                VStack(alignment: .leading, spacing: 1) {
                    Text(it.0).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    Text(it.1).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(it.2).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, n == 0 ? 0 : 10)
                .overlay(alignment: .leading) { if n > 0 { Rectangle().fill(Theme.hairline).frame(width: 1) } }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

// MARK: Running (ProjectsA)

struct ProjectsRunningTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: ProjectRows
    var running: [ProjectTimeline]

    var body: some View {
        let now = engine.state.week
        if rows.isEmpty {
            note("Project companies (builders, agencies, developers) list their jobs, tenders and developments here. None of your companies takes projects yet.")
        } else if running.isEmpty {
            note("Nothing is running. Requests come in through the week; marketing and a good name bring more. Open tenders are under Bids and offers. Check staff and equipment under each company's Operations if a firm cannot take work.")
        }
        ForEach(running.sorted { ($0.dueWeek ?? Int.max) < ($1.dueWeek ?? Int.max) }) { l in
            if let co = engine.state.company(l.companyID) {
                NavigationLink { ProjectTimelineDetail(lineID: l.id) } label: { card(l, co, now) }
                    .buttonStyle(.plain)
            }
        }
        if !rows.isEmpty {
            ProjectCaps(title: "PROJECT COMPANIES").padding(.top, 6)
            ForEach(rows.sorted { $0.board.outstandingPayments > $1.board.outstandingPayments }, id: \.co.id) { r in
                Button { Haptics.tap(); store.openCompany(r.co.id, section: .projects) } label: {
                    ProjectCardRow(title: r.co.name, sub: companyLine(r.board) + (!r.board.isDeveloper && r.board.outstandingPayments > 0 ? " · owed \(store.short(r.board.outstandingPayments, in: r.co))" : ""))
                }
                .buttonStyle(.plain).accessibilityIdentifier("open-project-company")
            }
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
    }

    private func companyLine(_ b: ProjectBoard) -> String {
        if b.isDeveloper { return "\(b.developments.count) \(b.developments.count == 1 ? "development" : "developments") · \(b.finishedCount) finished" }
        let open = b.tenders.filter { $0.qualifies && $0.myBid == nil }.count
        return "\(b.jobs.count) on the go · \(b.queuedJobs.count) waiting · \(open) \(open == 1 ? "tender" : "tenders") open"
    }

    static func status(_ l: ProjectTimeline) -> (String, Color) {
        if l.delayed { return (l.overdueWeeks > 0 ? "Late \(l.overdueWeeks) wk" : "Held up", Theme.caution) }
        if l.overdueWeeks > 0 { return ("Late \(l.overdueWeeks) wk", Theme.caution) }
        if (l.progress ?? 0) <= 0 && !l.stages.contains(where: { $0.state == .done && $0.name != "Taken on" && $0.name != "Booked" }) {
            return (l.kind == .development ? "Planning" : "Waiting", Theme.ivoryFaint)
        }
        return ("On track", Theme.gain)
    }

    private func card(_ l: ProjectTimeline, _ co: Company, _ now: Int) -> some View {
        let (word, tint) = Self.status(l)
        let done = l.stages.filter { $0.state == .done }.count
        let frac = min(1, max(0, l.progress ?? (l.stages.isEmpty ? 0 : Double(done) / Double(l.stages.count))))
        let cur = l.stages.first { $0.state == .current }
        let next: String = cur.map { "Next: \($0.name.lowercased())" + ($0.week.map { " \(shortDate(week: $0))" } ?? "") } ?? (done == l.stages.count ? "Complete" : "")
        let cost: (String, String) = l.costSoFar.map { ("Costs so far", store.short($0, in: co)) } ?? l.receivedSoFar.map { ("Paid so far", store.short($0, in: co)) } ?? ("Costs so far", "None yet")
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.title.tidyMoney).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                    Text("\(co.name) · \(kindWord(l.kind).lowercased()) · \(l.subtitle)").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(word).font(.system(size: 11.5)).foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
            }
            VStack(spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x26272A))
                        Capsule().fill(Theme.gold).frame(width: g.size.width * frac)
                    }
                }.frame(height: 5)
                HStack {
                    Text("\(done) of \(l.stages.count) milestones")
                    Spacer(minLength: 8)
                    Text(next).lineLimit(1)
                }.font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            ProjectFigures(items: [
                (l.kind == .development ? "Expected sales" : "Value", store.short(l.value, in: co), Theme.ivory),
                (cost.0, cost.1, Theme.ivory),
                ("Due", l.dueWeek.map { shortDate(week: $0) } ?? "No date", (l.dueWeek.map { $0 - now <= 2 } ?? false) ? Theme.caution : Theme.ivory),
            ])
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .projectCard()
        .contentShape(Rectangle())
    }
}

// MARK: Timeline (ProjectsB)

struct ProjectsTimelineTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var lines: [ProjectTimeline]

    var body: some View {
        let now = engine.state.week
        let work = lines.filter { $0.kind == .job || $0.kind == .event || $0.kind == .development }
        if work.isEmpty {
            Text("Nothing to chart yet. Jobs, events and developments appear here with their dates.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).padding(.vertical, 6)
        } else {
            ProjectWeeksChart(lines: work, now: now)
        }
        let soon: [(week: Int, stage: ProjectTimeline.Stage, line: ProjectTimeline)] = lines.flatMap { l in
            l.stages.compactMap { s in
                guard s.state != .done, let w = s.week, w >= now, w <= now + 1 else { return nil }
                return (week: w, stage: s, line: l)
            }
        }.sorted { $0.week < $1.week }
        ProjectCaps(title: "THIS AND NEXT WEEK")
        if soon.isEmpty {
            Text("No milestone falls in the next two weeks.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
        }
        ForEach(Array(soon.enumerated()), id: \.offset) { _, x in
            NavigationLink { ProjectTimelineDetail(lineID: x.line.id) } label: {
                HStack(spacing: 12) {
                    Text(shortDate(week: x.week)).font(.system(size: 12)).foregroundStyle(Theme.gold).multilineTextAlignment(.center).frame(width: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(x.stage.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text("\(x.line.title.tidyMoney) · \(x.line.companyName)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .projectCard(radius: Theme.Radius.card)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

// MARK: Bids and offers (ProjectsC)

struct ProjectsBidsTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: ProjectRows
    var openVentures: () -> Void
    @State private var openKey: String?
    @State private var priceIndex = 3
    @State private var higherQuality = false
    @State private var pending: PendingAction?
    private let prices: [Double] = [0.85, 0.9, 0.95, 1.0, 1.05, 1.1]

    private struct Tender: Identifiable { var id: String; var co: Company; var t: ProjectBoard.TenderRow }

    var body: some View {
        let open: [Tender] = rows.flatMap { r in r.board.tenders.filter { $0.qualifies && $0.myBid == nil }.map { Tender(id: "\(r.co.id)-\($0.id)", co: r.co, t: $0) } }
            .sorted { $0.t.weeksToBid < $1.t.weeksToBid }
        let sent: [Tender] = rows.flatMap { r in r.board.myTenders.filter { $0.outcome == nil }.map { Tender(id: "\(r.co.id)-\($0.id)", co: r.co, t: $0) } }
        let closing = open.filter { $0.t.weeksToBid <= 0 }.count
        let blocked = rows.reduce(0) { $0 + $1.board.tenders.filter { !$0.qualifies && $0.myBid == nil }.count }
        VStack(alignment: .leading, spacing: 12) {
            ProjectCaps(title: "OPEN TENDERS · \(open.count)", note: closing > 0 ? "\(closing) close this week" : "")
            if open.isEmpty {
                Text(rows.isEmpty ? "None of your companies takes projects yet." : "No tender is open to you right now. New ones are posted through the weeks.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(open) { x in tenderCard(x) }
            if blocked > 0 {
                Text("\(blocked) more \(blocked == 1 ? "tender needs" : "tenders need") requirements your firms do not meet yet.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryDim)
            }
            if !sent.isEmpty {
                ProjectCaps(title: "YOUR BIDS · \(sent.count)", note: "waiting for a decision").padding(.top, 6)
                ForEach(sent) { x in sentCard(x) }
            }
            ProjectCaps(title: "START SOMETHING").padding(.top, 6)
            startTiles
        }
        .confirmAction($pending)
    }

    // A tender card: budget (what it is worth), the fee to write the bid, how it is scored.
    private func tenderCard(_ x: Tender) -> some View {
        let t = x.t
        let closes = t.weeksToBid <= 0 ? "closes this week" : t.weeksToBid == 1 ? "closes next week" : "closes in \(t.weeksToBid) wk"
        let scored = t.priceWeight >= 1 ? "Price only" : "Price \(Int((t.priceWeight * 100).rounded()))%"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title.tidyMoney).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                    Text("\(x.co.name) · \(t.buyer)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(closes).font(.system(size: 12)).foregroundStyle(t.weeksToBid <= 1 ? Theme.caution : Theme.ivoryFaint)
            }
            ProjectFigures(items: [("Budget", store.short(t.worth, in: x.co), Theme.ivory), ("Fee to bid", store.short(t.bidCost, in: x.co), Theme.ivory), ("Scored on", scored, Theme.ivory)])
            HStack(spacing: 8) {
                NavigationLink { ProjectTimelineDetail(lineID: "t\(x.co.id)-\(t.id)") } label: {
                    outlined("Details", strong: false)
                }.buttonStyle(.plain)
                Button { Haptics.choose(); withAnimation(.snappy(duration: 0.2)) { openKey = openKey == x.id ? nil : x.id; priceIndex = 3; higherQuality = false } } label: {
                    outlined(openKey == x.id ? "Close" : "Place a bid ›", strong: true)
                }.buttonStyle(.plain)
            }
            if openKey == x.id { bidPanel(x) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .projectCard()
    }

    private func outlined(_ s: String, strong: Bool) -> some View {
        Text(s).font(.system(size: 13, weight: strong ? .medium : .regular)).foregroundStyle(Theme.ivory)
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(strong ? Theme.gold : Theme.borderStrong, lineWidth: 1))
            .contentShape(Rectangle())
    }

    private func bidPanel(_ x: Tender) -> some View {
        let t = x.t
        return VStack(alignment: .leading, spacing: 9) {
            Text("Your price against your list price").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            SegmentedChoice(items: Array(prices.indices), title: { "\(Int((prices[$0] * 100).rounded()))%" }, selection: $priceIndex)
            Toggle(isOn: $higherQuality) {
                Text("Commit to higher quality (costs about 3% more to deliver)").font(.system(size: 12.5)).foregroundStyle(Theme.ivory)
            }.tint(Theme.gold)
            Text("Lower prices win more often on price-heavy tenders, but you deliver at that price. Bids close in \(max(0, t.weeksToBid).weeksText); the buyer decides on \(GameCalendar.dateString(week: t.awardWeek)). Writing the bid costs \(store.money(t.bidCost, in: x.co)) even if you lose.")
                .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Send the bid", fullWidth: true) { askBid(x) }
        }
        .padding(.top, 2)
    }

    private func askBid(_ x: Tender) {
        let t = x.t
        let pf = prices[priceIndex], hq = higherQuality
        pending = PendingAction(title: "Send this bid?",
                                message: "\(t.title.tidyMoney) at \(Int((pf * 100).rounded()))% of your list price\(hq ? ", higher quality" : ""). Writing the bid costs \(store.money(t.bidCost, in: x.co)) from \(x.co.name) whether or not you win.",
                                button: "Send the bid", amount: t.bidCost, currency: engine.currency(for: x.co)) {
            let r = store.act { $0.bidOnTender(companyID: x.co.id, tenderID: t.id, priceFactor: pf, higherQuality: hq) }
            switch r {
            case .sent?: Haptics.success(); store.show("Bid sent. The result comes on \(GameCalendar.dateString(week: t.awardWeek)).", tone: "good"); openKey = nil
            case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company to write the bid.", tone: "warn")
            case .notQualified(let why)?: Haptics.warning(); store.show(why, tone: "warn")
            default: Haptics.warning(); store.show("This tender has closed.", tone: "warn")
            }
        }
    }

    private func sentCard(_ x: Tender) -> some View {
        let t = x.t
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title.tidyMoney).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                    Text("\(x.co.name) · \(t.buyer) · worth \(store.short(t.worth, in: x.co))").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(t.myBid.map { "Bid \(Int(($0 * 100).rounded()))%" } ?? "Bid sent").font(.system(size: 11.5)).foregroundStyle(Theme.gold)
            }
            Text("Decision on \(GameCalendar.dateString(week: t.awardWeek)). You can take the bid back until the bids close; a new one costs the writing fee again.")
                .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                store.settle(store.act { $0.withdrawBid(companyID: x.co.id, tenderID: t.id) }, "Your bid is withdrawn.", same: "The bid could not be taken back: the bidding has closed.")
            } label: { outlined("Take the bid back", strong: false) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .projectCard()
    }

    // START SOMETHING: four tiles; each goes to the company section that does it (a menu when several companies could).
    private var startTiles: some View {
        let developers = rows.filter { $0.board.isDeveloper }.map(\.co)
        let contractors = rows.filter { !$0.board.isDeveloper }.map(\.co)
        let landlords = engine.state.companies.filter { $0.status.isLive && engine.tradeInfo(companyID: $0.id)?.family == "rent" }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            startTile("Refurbishment", "improve a property", "M4 20 H20 M6 20 V10 L12 5 L18 10 V20", landlords, .properties, none: "No company owns property yet.")
            startTile("Developer project", "build and sell", "M5 21 V4 H15 V21 M15 9 H19 V21", developers, .projects, none: "No developer company yet.")
            startTile("Event or contract", "one-off work", "M5 5 H19 V20 H5 Z M5 10 H19 M9 3 V7 M15 3 V7", contractors, .projects, none: "No contracting or events company yet.")
            Button { Haptics.tap(); openVentures() } label: { tile("Venture", "back a startup", "M12 3 C16 6 17 11 14 16 L12 20 L10 16 C7 11 8 6 12 3") }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private func startTile(_ name: String, _ note: String, _ icon: String, _ cos: [Company], _ section: CompanySection, none: String) -> some View {
        if cos.isEmpty {
            Button { Haptics.warning(); store.show(none, tone: "warn") } label: { tile(name, note, icon).opacity(0.6) }.buttonStyle(.plain)
        } else if cos.count == 1, let c = cos.first {
            Button { Haptics.tap(); store.openCompany(c.id, section: section) } label: { tile(name, note, icon) }.buttonStyle(.plain)
        } else {
            Menu {
                ForEach(cos, id: \.id) { c in Button(c.name) { store.openCompany(c.id, section: section) } }
            } label: { tile(name, note, icon) }
        }
    }

    private func tile(_ name: String, _ note: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            GlyphView(glyph: icon, size: 18, weight: 1.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.8)
                Text(note).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .projectCard(radius: Theme.Radius.card)
        .contentShape(Rectangle())
    }
}

// MARK: Finished

struct ProjectsFinishedTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: ProjectRows

    var body: some View {
        let devs = rows.flatMap { r in r.board.finishedDevelopments.map { (co: r.co, f: $0) } }
        let results = rows.flatMap { r in r.board.myTenders.filter { $0.outcome != nil }.map { (co: r.co, t: $0) } }
        let jobsDone = rows.filter { !$0.board.isDeveloper && $0.board.finishedCount > 0 }
        if devs.isEmpty && results.isEmpty && jobsDone.isEmpty {
            Text("Nothing finished yet. Completed jobs, sold-out developments and decided tenders collect here.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).padding(.vertical, 6)
        }
        if !devs.isEmpty {
            ProjectCaps(title: "DEVELOPMENTS · \(devs.count)")
            ForEach(Array(devs.enumerated()), id: \.offset) { _, x in
                let profit = x.f.revenue - x.f.cost
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(x.f.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                        Text("\(x.co.name) · sold for \(store.short(x.f.revenue, in: x.co)) · cost \(store.short(x.f.cost, in: x.co))").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Text((profit < 0 ? "−" : "+") + store.short(abs(profit), in: x.co)).font(.figure(13.5, weight: .semibold)).foregroundStyle(profit < 0 ? Theme.loss : Theme.gain)
                }
                .padding(.horizontal, 14).padding(.vertical, 11).projectCard(radius: Theme.Radius.card)
            }
        }
        if !jobsDone.isEmpty {
            ProjectCaps(title: "JOBS AND EVENTS DONE").padding(.top, 4)
            ForEach(jobsDone, id: \.co.id) { r in
                Button { Haptics.tap(); store.openCompany(r.co.id, section: .projects) } label: {
                    ProjectCardRow(title: r.co.name, sub: "\(r.board.finishedCount) finished")
                }.buttonStyle(.plain)
            }
        }
        if !results.isEmpty {
            ProjectCaps(title: "TENDER RESULTS").padding(.top, 4)
            ForEach(Array(results.prefix(12).enumerated()), id: \.offset) { _, x in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(x.t.title.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                        Text("\(x.co.name) · \(x.t.buyer) · worth \(store.short(x.t.worth, in: x.co))").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(x.t.outcome == "won" ? "Won" : x.t.outcome == "lost" ? "Lost" : "Closed")
                        .font(.system(size: 11.5)).foregroundStyle(x.t.outcome == "won" ? Theme.gain : Theme.ivoryFaint)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
                }
                .padding(.horizontal, 14).padding(.vertical, 10).projectCard(radius: Theme.Radius.card)
            }
        }
    }
}
