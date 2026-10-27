import SwiftUI
import Charts
import GameCore
import Businesses
import Countries
import Simulation

/// Customers, in three tabs: how happy they are (rating, happy against unhappy, stars, the trend of the reviews and what they wrote),
/// who buys (consumers against businesses, key accounts, credit check, contracts) and how safe their data is (IT security).
struct CompanyCustomers: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var tab: CustomerTab = .mood
    @State private var showAll = false

    enum CustomerTab: String, CaseIterable, Identifiable {
        case mood, buyers, security
        var id: String { rawValue }
        var title: String {
            switch self {
            case .mood: return "Satisfaction"
            case .buyers: return "Buyers"
            case .security: return "Security"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            MoreHeader(glyph: Glyph.person, title: "Customers", blurb: "How happy they are, who buys from you and how safe their data is.")
            SegmentedPill(items: CustomerTab.allCases, title: { (t: CustomerTab) in t.title }, selection: $tab)
            tabContent
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .mood: mood
        case .buyers: buyers
        case .security: security
        }
    }

    // MARK: Satisfaction

    private struct TrendPoint: Identifiable { var id: Int; var monthsAgo: Int; var stars: Double }

    private struct StarBar: Identifiable { var id: Int; var count: Int }

    @ViewBuilder private var mood: some View {
        let r: ReviewSummary = engine.reviewSummary(company, limit: max(1, company.value("rv41").array.count))
        moodHero(r)
        if r.count > 0 {
            loyaltyStrip(r)
            trendBlock(r)
            starsBlock(r)
            reviewsBlock(r)
        } else {
            Card(padding: 12, radius: Theme.Radius.row) {
                Text("Reviews arrive once customers come. Quality and reputation decide the stars.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func moodHero(_ r: ReviewSummary) -> some View {
        let big: String = r.enough ? String(format: "%.1f", r.rating) : "–"
        let tint: Color = !r.enough ? Theme.ivoryFaint : (r.rating >= 4 ? Theme.gain : (r.rating >= 3 ? Theme.gold : Theme.loss))
        let items: [KeyFigures.Item] = [
            .init(label: "Reviews", value: "\(r.count)"),
            .init(label: "Reputation", value: "\(Int(company.reputation.rounded()))"),
        ]
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(big).font(.serifTitle(38)).foregroundStyle(tint)
                    Text("/ 5").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
                    Spacer()
                    Text(r.enough ? r.word : "No rating yet").font(.system(size: 12.5, weight: .medium)).foregroundStyle(tint)
                }
                FigureStrip(items: items, columns: 2)
            }
        }
    }

    /// Happy (4 and 5 stars), neutral (3) and unhappy (1 and 2) as one strip. Shares of the reviews written, not of all customers.
    private func loyaltyStrip(_ r: ReviewSummary) -> some View {
        let total: Double = Double(max(1, r.count))
        let h: [Int] = r.histogram
        let happy: Double = Double((h.count > 4 ? h[3] + h[4] : 0)) / total
        let neutral: Double = Double(h.count > 2 ? h[2] : 0) / total
        let unhappy: Double = Double((h.count > 1 ? h[0] + h[1] : 0)) / total
        return MoreBlock(title: "Happy and unhappy", trailing: {
            Text("of reviews written").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        Capsule().fill(Theme.gain).frame(width: max(2, g.size.width * CGFloat(happy)))
                        Capsule().fill(Theme.gold.opacity(0.6)).frame(width: max(2, g.size.width * CGFloat(neutral)))
                        Capsule().fill(Theme.loss).frame(width: max(2, g.size.width * CGFloat(unhappy)))
                    }
                }.frame(height: 8)
                StatStrip(cells: [
                    .init(label: "Happy", value: String(format: "%.0f%%", happy * 100), tint: Theme.gain),
                    .init(label: "Neutral", value: String(format: "%.0f%%", neutral * 100)),
                    .init(label: "Unhappy", value: String(format: "%.0f%%", unhappy * 100), tint: unhappy > 0.25 ? Theme.loss : Theme.ivory),
                ], ruled: false)
            }
        }
    }

    /// The average of the stars given in each month of reviews. Customers who quietly leave are not counted one by one: a falling line is the warning.
    private func trendPoints(_ r: ReviewSummary) -> [TrendPoint] {
        let groups: [Int: [ReviewLine]] = Dictionary(grouping: r.lines, by: { $0.weeksAgo / 4 })
        return groups.keys.sorted(by: >).map { (m: Int) -> TrendPoint in
            let lines: [ReviewLine] = groups[m] ?? []
            let avg: Double = Double(lines.reduce(0) { $0 + $1.stars }) / Double(max(1, lines.count))
            return TrendPoint(id: m, monthsAgo: m, stars: avg)
        }
    }

    @ViewBuilder private func trendBlock(_ r: ReviewSummary) -> some View {
        let pts: [TrendPoint] = trendPoints(r)
        MoreBlock(title: "Mood over time", trailing: {
            Text("average stars a month").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }) {
            if pts.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Chart(pts) { (p: TrendPoint) in
                        LineMark(x: .value("Months ago", -p.monthsAgo), y: .value("Stars", p.stars))
                            .foregroundStyle(Theme.gold).lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).interpolationMethod(.monotone)
                        PointMark(x: .value("Months ago", -p.monthsAgo), y: .value("Stars", p.stars))
                            .foregroundStyle(p.stars >= 3.5 ? Theme.gold : Theme.loss).symbolSize(26)
                    }
                    .chartXAxis(.hidden)
                    .chartYScale(domain: 1...5)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: [1, 3, 5]) { (v: AxisValue) in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                            AxisValueLabel().font(.system(size: 9.5)).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                    .frame(height: 96)
                    Text("Customers who simply stop coming are not counted one by one. A falling line is the warning.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
            } else {
                Text("The line needs reviews from at least two different months.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func starsBlock(_ r: ReviewSummary) -> some View {
        let bars: [StarBar] = r.histogram.enumerated().map { (i: Int, c: Int) in StarBar(id: i + 1, count: c) }
        return MoreBlock("Stars given") {
            Chart(bars) { (b: StarBar) in
                BarMark(x: .value("Stars", "\(b.id)★"), y: .value("Reviews", b.count))
                    .foregroundStyle(b.id >= 4 ? Theme.gain : (b.id == 3 ? Theme.gold : Theme.loss))
                    .cornerRadius(3)
                    .annotation(position: .top) { Text("\(b.count)").font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.ivoryMuted) }
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks { (_: AxisValue) in AxisValueLabel().font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted) } }
            .frame(height: 110)
        }
    }

    private func reviewsBlock(_ r: ReviewSummary) -> some View {
        let shown: [ReviewLine] = showAll ? r.lines : Array(r.lines.prefix(6))
        return MoreBlock(title: "What they wrote", card: false, trailing: {
            if r.lines.count > 6 {
                Button(showAll ? "Show fewer" : "Show all") { showAll.toggle() }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
            }
        }) {
            ForEach(shown) { (line: ReviewLine) in
                EntityCard { reviewCard(line) }
            }
        }
    }

    private func reviewCard(_ line: ReviewLine) -> some View {
        let stars: String = String(repeating: "★", count: line.stars) + String(repeating: "☆", count: max(0, 5 - line.stars))
        let when: String = line.weeksAgo == 0 ? "This week" : "\(line.weeksAgo) wk ago"
        let who: String = (line.flag.isEmpty ? "" : line.flag + " ") + "\(line.who), \(line.age)"
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(stars).font(.system(size: 12)).foregroundStyle(Theme.gold)
                Spacer()
                Text(when).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }
            Text(line.text.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            Text(who).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    // MARK: Buyers

    @ViewBuilder private var buyers: some View {
        segments
        accounts
        creditCheck
        CompanyContracts(engine: engine, company: company)
    }

    /// Who the sales go to: private customers against businesses (the trade's own split), as one bar.
    @ViewBuilder private var segments: some View {
        if let t = engine.tradeInfo(companyID: company.id) {
            let biz: Double = min(1, max(0, t.businessShare))
            MoreBlock("Who buys") {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { g in
                        HStack(spacing: 2) {
                            if biz < 1 { Capsule().fill(Theme.gold).frame(width: max(2, g.size.width * CGFloat(1 - biz))) }
                            if biz > 0 { Capsule().fill(Theme.slateBlue).frame(width: max(2, g.size.width * CGFloat(biz))) }
                        }
                    }.frame(height: 8)
                    StatStrip(cells: [
                        .init(label: "Private customers", value: String(format: "%.0f%%", (1 - biz) * 100), tint: Theme.gold),
                        .init(label: "Businesses", value: String(format: "%.0f%%", biz * 100)),
                    ], ruled: false)
                    if biz == 0 {
                        Text("This trade sells to private customers only, so there are no key accounts.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
        }
    }

    @ViewBuilder private var accounts: some View {
        let info = engine.keyAccountInfo(company)
        if info.allowed || !info.accounts.isEmpty {
            MoreBlock(title: "Key accounts", card: false, trailing: {
                Text("\(info.accounts.count) of \(info.limit)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    if info.accounts.isEmpty {
                        Card(padding: 12, radius: Theme.Radius.row) {
                            Text("Larger buyers ask to place regular orders once you are known and well regarded. A manager signs them; otherwise the offer waits in the inbox.")
                                .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                    ForEach(info.accounts, id: \.id) { (a: KeyAccounts.Account) in
                        EntityCard { AccountRow(engine: engine, company: company, account: a) }
                    }
                }
            }
        }
    }

    /// Only for trades that invoice businesses: checking a buyer's credit before selling on account costs a little and cuts unpaid invoices.
    @ViewBuilder private var creditCheck: some View {
        if let t = engine.tradeInfo(companyID: company.id), t.businessShare > 0, company.status.isLive {
            let on = company.value("flags")["ccheck"].bool
            MoreBlock(title: "Credit check", trailing: { Text(on ? "on" : "off").font(.system(size: 11)).foregroundStyle(on ? Theme.gain : Theme.ivoryFaint) }) {
                Toggle(isOn: Binding(get: { on }, set: { v in
                    _ = store.act { $0.setCreditCheck(companyID: company.id, on: v) }
                    store.show(v ? "Buyers' credit is checked before you sell on account." : "Credit checks switched off.", tone: "n")
                })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Check buyers before selling on account").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Text("Costs about 0.4% of what you invoice to businesses. Benefit: unpaid invoices become about 70% less likely. Risk of leaving it off: a bad debt is written off in full.")
                            .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }.tint(Theme.gold)
            }
        }
    }

    // MARK: IT security

    private var security: some View {
        let c = engine.cyberInfo(company)
        let cur = engine.currency(for: company)
        return MoreBlock(title: "IT security", trailing: {
            Text("1 in \(Int((1 / max(0.002, c.yearOdds)).rounded())) a year").font(.system(size: 11)).foregroundStyle(c.yearOdds > 0.1 ? Theme.loss : Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                FigureStrip(items: [
                    .init(label: "Protection", value: Cyber.levels[c.status.level].name, sub: cur.tidyShort(c.monthlyNow) + " a month"),
                    .init(label: "Stopped", value: "\(c.status.blocked)", sub: "attacks caught"),
                    .init(label: "Cyber insurance", value: c.insured ? "Yes" : "No", tint: c.insured ? Theme.gain : Theme.ivory),
                ])
                if company.managerID != nil {
                    CardLine()
                    HStack {
                        Text(c.status.managerPicks ? "Your manager picks the level, keeps the backups and books the training." : "Your choice stands.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        Spacer()
                        if !c.status.managerPicks { Button("Leave it to the manager") { store.act { $0.leaveCyberToManager(companyID: company.id) }; store.saved("your manager now picks the IT protection") }.buttonStyle(TinyButtonStyle(tint: Theme.gold)) }
                    }
                }
                ForEach(Cyber.levels.indices, id: \.self) { (i: Int) in
                    CardLine()
                    levelRow(i, c: c, cur: cur)
                }
                CardLine()
                HStack {
                    Button(c.status.backups ? "Offline backups: on" : "Offline backups: off") { Haptics.tap(); store.settle(store.act { $0.toggleBackups(companyID: company.id) }, c.status.backups ? "Offline backups switched off." : "Offline backups switched on.") }
                        .buttonStyle(TinyButtonStyle(tint: c.status.backups ? Theme.gold : Theme.ivoryMuted))
                    Spacer()
                    Button((c.status.trainedUntil ?? 0) > engine.state.week ? "Staff trained" : "Train staff · " + cur.tidyShort(c.trainingCost)) {
                        let r = store.act { $0.trainStaff(companyID: company.id) }
                        if case .refused(let why)? = r { store.show(why, tone: "warn") } else if r != nil { Haptics.success(); store.show("Staff training booked.", tone: "good") }
                    }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
                }
                if let last = c.status.log.first {
                    Text("Last: \(last.text)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func levelRow(_ i: Int, c: CyberInfo, cur: Currency) -> some View {
        let on: Bool = c.status.level == i
        let costText: String = i == 0 ? "Free" : cur.tidyShort(c.levelCosts[i]) + "/mo"
        let done: String = "Cyber protection: \(Cyber.levels[i].name)."
        return Button {
            Haptics.choose()
            store.settle(store.act { $0.setCyberLevel(companyID: company.id, level: i) }, done, same: "That protection level is already in place.")
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Cyber.levels[i].name).font(.system(size: 13.5, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.gold : Theme.ivory)
                    Text(Cyber.levels[i].text).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(costText).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                GlyphView(glyph: on ? Glyph.check : Glyph.ring, size: 14, weight: 1.6, tint: on ? Theme.gold : Theme.ivoryFaint)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct AccountRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var account: KeyAccounts.Account
    @State private var pending: PendingAction?
    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                IconCircle(glyph: Glyph.person, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text("\(Rivals.relationshipWord(account.relationship)) · since week \(account.sinceWeek) · paid you \(cur.tidyShort(account.totalPaid))")
                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    if account.owed > 0 || account.lateRun > 0 {
                        Text((account.owed > 0 ? "Still owes you \(cur.tidyShort(account.owed)) on invoices" : "Nothing owed now")
                             + (account.lateRun > 0 ? " · paid late \(account.lateRun) time\(account.lateRun == 1 ? "" : "s") in a row. Late payment earns interest where the country allows it." : ""))
                            .font(.system(size: 11)).foregroundStyle(account.lateRun > 0 ? Theme.caution : Theme.ivoryFaint)
                    }
                    let profile = engine.keyAccountProfile(account)
                    Text("Runs a \(profile.tradeName.lowercased())" + (profile.inputName.map { profile.canBuy ? ". You can buy \($0.lowercased()) from them." : ". Get to know them to buy \($0.lowercased()) from them." } ?? ""))
                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                Text(account.discount == 0 ? "Full price" : "\(account.discount)% off").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            }
            Text("Discount for this buyer").capsLabel(Theme.ivoryFaint)
            WrapRow {
                Group {
                    ForEach(KeyAccounts.discounts, id: \.self) { d in
                        Button("\(d)%") { store.act { $0.setAccountDiscount(companyID: company.id, accountID: account.id, percent: d) }; store.saved("\(account.name): \(d == 0 ? "full price" : "\(d)% off")") }
                            .buttonStyle(TinyButtonStyle(tint: account.discount == d ? Theme.gold : Theme.ivoryFaint))
                    }
                }
            }
            HStack {
                Button("Dinner · " + cur.tidyShort(cur.scaledPrice(6000))) {
                    let r = store.act { $0.meetAccount(companyID: company.id, accountID: account.id) }
                    switch r {
                    case .wait?: store.show("You met recently. Give it a few weeks.", tone: "warn")
                    case .cash?: store.show("Not enough cash for the dinner.", tone: "warn")
                    default: Haptics.success(); store.show("Dinner with \(account.name). The relationship is warmer.", tone: "good")
                    }
                }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
                Spacer()
                Button("End contract…") {
                    pending = PendingAction(title: "End the contract with \(account.name)?",
                                            message: "Their regular orders stop at once and you would have to win them over again to get them back." + (account.owed > 0 ? " They still owe you \(cur.tidyShort(account.owed)) on invoices." : ""),
                                            button: "End contract", destructive: true) {
                        if store.act({ $0.dropAccount(companyID: company.id, accountID: account.id) }) == true { Haptics.warning(); store.show("Contract with \(account.name) ended.", tone: "n") }
                        else { store.show("That contract is already gone.", tone: "warn") }
                    }
                }.buttonStyle(TinyButtonStyle(tint: Theme.loss))
            }
        }
        .confirmAction($pending)
    }
}
