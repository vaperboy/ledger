import SwiftUI
import Charts
import GameCore
import Businesses
import Countries
import Simulation

/// Customers, a part of Stats (no header or tabs of its own): who buys first (private customers against businesses), then how they rate the
/// company (stars out of 5, a word for the reputation, happy against unhappy, stars given), key accounts, the credit check and volume
/// contracts. What customers wrote is in the Reviews app (a row links to it); IT security is where insurance is chosen
/// (Manage > Insurance and advisers).
struct CompanyCustomers: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            segments
            mood
            reviewsLink
            accounts
            creditCheck
            CompanyContracts(engine: engine, company: company)
        }
    }

    // MARK: Satisfaction

    private struct StarBar: Identifiable { var id: Int; var count: Int }

    @ViewBuilder private var mood: some View {
        let r: ReviewSummary = engine.reviewSummary(company, limit: 1)
        moodHero(r)
        if r.count > 0 {
            loyaltyStrip(r)
            starsBlock(r)
        } else {
            Card(padding: 12, radius: Theme.Radius.row) {
                Text("Reviews arrive once customers come.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func moodHero(_ r: ReviewSummary) -> some View {
        let items: [KeyFigures.Item] = [
            .init(label: "Reviews", value: "\(r.count)"),
            .init(label: "Reputation", value: StandingWords.reputation(company.reputation)),
        ]
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if r.enough {
                        StarRatingView(rating: r.rating, size: 22)
                    } else {
                        Text("No rating yet").font(.serifTitle(22)).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer()
                    if r.enough { Text(r.word).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold) }
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

    /// A link to everything customers wrote (the Reviews app, on this company).
    private var reviewsLink: some View {
        SettingsTable(heading: "Reviews") {
            SettingsTableRow(title: "What customers wrote", note: "Yours and your rivals'", value: "Reviews app") { store.openReviews(companyID: company.id) }
        }
    }

    // MARK: Buyers

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
