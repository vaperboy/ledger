import SwiftUI
import GameCore
import Businesses
import Simulation

typealias ProjectRows = [(co: Company, board: ProjectBoard)]

/// "5 Feb": the engine's date without the year.
func shortDate(week: Int) -> String {
    GameCalendar.dateString(week: week).split(separator: " ").dropLast().joined(separator: " ")
}

/// A section label with an optional right-hand note (Open tenders, This and next week).
private struct ProjectCaps: View {
    var title: String
    var note: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).capsLabel()
            Spacer(minLength: Theme.Space.s)
            if !note.isEmpty { Text(note).textStyle(.caption, tint: Theme.inkFaint) }
        }
        .padding(.top, Theme.Space.s)
    }
}

/// Three figures under a hairline, separated by vertical rules (Value / Costs so far / Due).
private struct ProjectFigures: View {
    var items: [(String, String, Color)]
    var body: some View {
        FigureRow(items: items.map { (it: (String, String, Color)) -> KeyFigures.Item in KeyFigures.Item(label: it.0, value: it.1, tint: it.2) }, columns: max(1, items.count), combineCells: true)
            .padding(.top, Theme.Space.s)
            .overlay(alignment: .top) { Hairline() }
    }
}

/// Items of one list stacked flat with a hairline between them (no box around each).
private struct ProjectList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    var data: Data
    @ViewBuilder var row: (Data.Element) -> Row
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { (n: Int, x: Data.Element) in
                if n > 0 { Hairline() }
                row(x).padding(.vertical, Theme.Space.m)
            }
        }
    }
}

/// The status word of a project as a tinted pill.
private func projectPillTone(_ tint: Color) -> AcctPill.Tone {
    tint == Theme.gain ? .good : (tint == Theme.warn ? .warn : (tint == Theme.loss ? .bad : .neutral))
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
            EmptyState(glyph: Glyph.projects, title: "No project companies yet", message: "Builders, agencies and developers list their jobs, tenders and developments here.")
        } else if running.isEmpty {
            EmptyState(glyph: Glyph.projects, title: "Nothing is running", message: "Requests come in through the week; marketing and a good name bring more. Open tenders are under Bids and offers. If a firm cannot take work, check its staff and equipment under Operations.")
        }
        ProjectList(data: running.sorted { ($0.dueWeek ?? Int.max) < ($1.dueWeek ?? Int.max) }) { (l: ProjectTimeline) in
            if let co = engine.state.company(l.companyID) {
                NavigationLink { ProjectTimelineDetail(lineID: l.id) } label: { card(l, co, now) }
                    .buttonStyle(PressableStyle())
            }
        }
        if !rows.isEmpty {
            ProjectCaps(title: "Project companies")
            VStack(spacing: 0) {
                ForEach(Array(rows.sorted { $0.board.outstandingPayments > $1.board.outstandingPayments }.enumerated()), id: \.element.co.id) { (n: Int, r: (co: Company, board: ProjectBoard)) in
                    if n > 0 { Hairline() }
                    ProjectCardRow(title: r.co.name, sub: companyLine(r.board) + (!r.board.isDeveloper && r.board.outstandingPayments > 0 ? " · owed \(store.short(r.board.outstandingPayments, in: r.co))" : ""))
                }
            }
        }
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
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.title.tidyMoney).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(2)
                    Text("\(co.name) · \(kindWord(l.kind).lowercased()) · \(l.subtitle)").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                AcctPill(text: word, tone: projectPillTone(tint))
            }
            VStack(spacing: Theme.Space.xs) {
                OrgProgressBar(fraction: frac, milestones: done)
                HStack {
                    Text("\(done) of \(l.stages.count) milestones").orgTextSwap(done).orgPulse(done)
                    Spacer(minLength: Theme.Space.s)
                    Text(next).lineLimit(1).orgTextSwap(next)
                }.textStyle(.caption, tint: Theme.inkFaint)
            }
            ProjectFigures(items: [
                (l.kind == .development ? "Expected sales" : "Value", store.short(l.value, in: co), Theme.ivory),
                (cost.0, cost.1, Theme.ivory),
                ("Due", l.dueWeek.map { shortDate(week: $0) } ?? "No date", (l.dueWeek.map { $0 - now <= 2 } ?? false) ? Theme.caution : Theme.ivory),
            ])
        }
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
            EmptyState(glyph: Glyph.projects, title: "Nothing to chart yet", message: "Jobs, events and developments appear here with their dates.")
        } else {
            ProjectWeeksChart(lines: work, now: now)
        }
        let soon: [(week: Int, stage: ProjectTimeline.Stage, line: ProjectTimeline)] = lines.flatMap { l in
            l.stages.compactMap { s in
                guard s.state != .done, let w = s.week, w >= now, w <= now + 1 else { return nil }
                return (week: w, stage: s, line: l)
            }
        }.sorted { $0.week < $1.week }
        ProjectCaps(title: "This and next week")
        if soon.isEmpty {
            EmptyState(title: "No milestone in the next two weeks", centered: false)
        }
        ForEach(Array(soon.enumerated()), id: \.offset) { n, x in
            if n > 0 { Hairline() }
            NavigationLink { ProjectTimelineDetail(lineID: x.line.id) } label: {
                HStack(spacing: Theme.Space.m) {
                    Text(shortDate(week: x.week)).textStyle(.caption, tint: Theme.accent).multilineTextAlignment(.center).frame(width: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(x.stage.name).textStyle(.body, tint: Theme.ink, weight: .medium)
                        Text("\(x.line.title.tidyMoney) · \(x.line.companyName)").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.s)
                    LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }.buttonStyle(PressableStyle())
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
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ProjectCaps(title: "Open tenders · \(open.count)", note: closing > 0 ? "\(closing) close this week" : "")
            if open.isEmpty {
                EmptyState(title: rows.isEmpty ? "No project companies yet" : "No open tender for you",
                           message: rows.isEmpty ? "None of your companies takes projects yet." : "New ones are posted through the weeks.", centered: false)
            }
            ProjectList(data: open) { (x: Tender) in tenderCard(x) }
            if blocked > 0 {
                Text("\(blocked) more \(blocked == 1 ? "tender needs" : "tenders need") requirements your firms do not meet yet.").textStyle(.caption, tint: Theme.inkFaint)
            }
            if !sent.isEmpty {
                ProjectCaps(title: "Your bids · \(sent.count)", note: "waiting for a decision")
                ProjectList(data: sent) { (x: Tender) in sentCard(x) }
            }
            VenturesGlance(open: openVentures)
        }
        .confirmAction($pending)
    }

    // A tender card: budget (what it is worth), our cost estimate, how many rivals bid. Fee and scoring are in the bid panel and Details.
    private func tenderCard(_ x: Tender) -> some View {
        let t = x.t
        let closes = t.weeksToBid <= 0 ? "closes this week" : t.weeksToBid == 1 ? "closes next week" : "closes in \(t.weeksToBid) wk"
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title.tidyMoney).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(2)
                    Text("\(x.co.name) · \(t.buyer)").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                Text(closes).textStyle(.caption, tint: t.weeksToBid <= 1 ? Theme.warn : Theme.inkFaint)
            }
            ProjectFigures(items: [("Budget", store.short(t.worth, in: x.co), Theme.ivory), ("Your cost est.", t.costEstimate.map { store.short($0, in: x.co) } ?? "n/a", Theme.ivory), ("Rivals bidding", t.rivals, Theme.ivory)])
            HStack(spacing: Theme.Space.s) {
                NavigationLink { ProjectTimelineDetail(lineID: "t\(x.co.id)-\(t.id)") } label: { Text("Details") }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                Button { Haptics.choose(); Motion.animate(Motion.quickAnimation) { openKey = openKey == x.id ? nil : x.id; priceIndex = 3; higherQuality = false } } label: {
                    Text(openKey == x.id ? "Close" : "Place a bid")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.accent))
            }
            if openKey == x.id { bidPanel(x) }
        }
    }

    private func bidPanel(_ x: Tender) -> some View {
        let t = x.t
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Your price against your list price").textStyle(.caption, tint: Theme.inkFaint)
            SegmentedChoice(items: Array(prices.indices), title: { "\(Int((prices[$0] * 100).rounded()))%" }, selection: $priceIndex)
            Toggle(isOn: $higherQuality) {
                Text("Commit to higher quality (costs about 3% more to deliver)").textStyle(.caption, tint: Theme.ink)
            }.tint(Theme.accent).frame(minHeight: 44)
            Text("Lower prices win more often on price-heavy tenders, but you deliver at that price. Bids close in \(max(0, t.weeksToBid).weeksText); the buyer decides on \(GameCalendar.dateString(week: t.awardWeek)). Writing the bid costs \(store.money(t.bidCost, in: x.co)) even if you lose.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            Button("Send the bid") { Haptics.tap(); askBid(x) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
        }
        .padding(.top, Theme.Space.xxs)
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
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title.tidyMoney).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(2)
                    Text("\(x.co.name) · \(t.buyer) · worth \(store.short(t.worth, in: x.co))").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                Text(t.myBid.map { "Bid \(Int(($0 * 100).rounded()))%" } ?? "Bid sent").textStyle(.caption, tint: Theme.accent)
            }
            Text("Decision on \(GameCalendar.dateString(week: t.awardWeek)). You can take the bid back until the bids close; a new one costs the writing fee again.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                store.settle(store.act { $0.withdrawBid(companyID: x.co.id, tenderID: t.id) }, "Your bid is withdrawn.", same: "The bid could not be taken back: the bidding has closed.")
            } label: { Text("Take the bid back") }.buttonStyle(SecondaryButtonStyle(size: .compact))
        }
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
            EmptyState(glyph: Glyph.projects, title: "Nothing finished yet", message: "Completed jobs, sold-out developments and decided tenders collect here.")
        }
        if !devs.isEmpty {
            ProjectCaps(title: "Developments · \(devs.count)")
            ForEach(Array(devs.enumerated()), id: \.offset) { n, x in
                let profit = x.f.revenue - x.f.cost
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(x.f.name).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(1)
                        Text("\(x.co.name) · sold for \(store.short(x.f.revenue, in: x.co)) · cost \(store.short(x.f.cost, in: x.co))").textStyle(.caption, tint: Theme.inkFaint).lineLimit(2)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Text((profit < 0 ? "−" : "+") + store.short(abs(profit), in: x.co)).textStyle(.headline, tint: profit < 0 ? Theme.loss : Theme.gain, numeric: true, weight: .semibold)
                }
                .padding(.vertical, Theme.Space.m)
                .overlay(alignment: .top) { if n > 0 { Hairline() } }
            }
        }
        if !jobsDone.isEmpty {
            ProjectCaps(title: "Jobs and events done")
            ForEach(jobsDone, id: \.co.id) { r in
                ProjectCardRow(title: r.co.name, sub: "\(r.board.finishedCount) finished")
            }
        }
        if !results.isEmpty {
            ProjectCaps(title: "Tender results")
            ForEach(Array(results.prefix(12).enumerated()), id: \.offset) { n, x in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(x.t.title.tidyMoney).textStyle(.body, tint: Theme.ink).lineLimit(1)
                        Text("\(x.co.name) · \(x.t.buyer) · worth \(store.short(x.t.worth, in: x.co))").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.s)
                    AcctPill(text: x.t.outcome == "won" ? "Won" : x.t.outcome == "lost" ? "Lost" : "Closed", tone: x.t.outcome == "won" ? .good : .neutral)
                }
                .padding(.vertical, Theme.Space.m)
                .overlay(alignment: .top) { if n > 0 { Hairline() } }
            }
        }
    }
}
