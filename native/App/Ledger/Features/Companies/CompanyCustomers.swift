import SwiftUI
import GameCore
import Businesses
import Simulation

/// Customers: what they say (reviews, one system for every trade), the business customers (key accounts) and IT security.
struct CompanyCustomers: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            reviews
            accounts
            security
        }
    }

    // MARK: Reviews

    private var reviews: some View {
        let r = engine.reviewSummary(company, limit: showAll ? 30 : 6)
        return LedgerSection(title: "Reviews", trailing: {
            Text(r.enough ? r.word : "No rating yet").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                KeyFigures(items: [
                    .init(label: "Rating", value: r.enough ? String(format: "%.1f / 5", r.rating) : "–"),
                    .init(label: "Reviews", value: "\(r.count)"),
                    .init(label: "Reputation", value: "\(Int(company.reputation.rounded()))"),
                ])
                if r.count > 0 {
                    let top = max(1, r.histogram.max() ?? 1)
                    ForEach((1...5).reversed(), id: \.self) { s in
                        RateBar(label: "\(s) star\(s == 1 ? "" : "s")", fraction: Double(r.histogram[s - 1]) / Double(top), tint: s >= 4 ? Theme.gain : s == 3 ? Theme.gold : Theme.loss)
                    }
                    ForEach(r.lines) { line in
                        Hairline()
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(String(repeating: "★", count: line.stars) + String(repeating: "☆", count: 5 - line.stars)).font(.system(size: 12)).foregroundStyle(Theme.gold)
                                Spacer()
                                Text(line.weeksAgo == 0 ? "This week" : "\(line.weeksAgo) wk ago").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Text(line.text).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                            Text("\(line.who), \(line.age)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                    if r.count > 6 {
                        Button(showAll ? "Show fewer" : "Show more") { showAll.toggle() }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                    }
                } else {
                    Text("Reviews arrive once customers come. Quality and reputation decide the stars.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    // MARK: Business customers

    @ViewBuilder private var accounts: some View {
        let info = engine.keyAccountInfo(company)
        if info.allowed || !info.accounts.isEmpty {
            LedgerSection(title: "Business customers", trailing: {
                Text("\(info.accounts.count) of \(info.limit)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                VStack(alignment: .leading, spacing: 0) {
                    if info.accounts.isEmpty {
                        Text("Larger buyers ask to place regular orders once you are known and well regarded. A manager signs them; otherwise the offer waits in the inbox.")
                            .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                    }
                    ForEach(Array(info.accounts.enumerated()), id: \.element.id) { n, a in
                        if n > 0 { Hairline() }
                        AccountRow(engine: engine, company: company, account: a)
                    }
                }
            }
        }
    }

    // MARK: IT security

    private var security: some View {
        let c = engine.cyberInfo(company)
        let cur = engine.currency(for: company)
        return LedgerSection(title: "IT security", trailing: {
            Text("1 in \(Int((1 / max(0.002, c.yearOdds)).rounded())) a year").font(.system(size: 11)).foregroundStyle(c.yearOdds > 0.1 ? Theme.loss : Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                KeyFigures(items: [
                    .init(label: "Protection", value: Cyber.levels[c.status.level].name, sub: cur.short(c.monthlyNow) + " a month"),
                    .init(label: "Stopped", value: "\(c.status.blocked)", sub: "attacks caught"),
                    .init(label: "Cyber insurance", value: c.insured ? "Yes" : "No", tint: c.insured ? Theme.gain : Theme.ivory),
                ])
                ForEach(Cyber.levels.indices, id: \.self) { i in
                    Hairline()
                    Button { store.act { $0.setCyberLevel(companyID: company.id, level: i) }; Haptics.choose() } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Cyber.levels[i].name).font(.system(size: 13.5, weight: c.status.level == i ? .semibold : .regular)).foregroundStyle(c.status.level == i ? Theme.gold : Theme.ivory)
                                Text(Cyber.levels[i].text).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Text(i == 0 ? "Free" : cur.short(c.levelCosts[i]) + "/mo").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Hairline()
                HStack {
                    Button(c.status.backups ? "Offline backups: on" : "Offline backups: off") { store.act { $0.toggleBackups(companyID: company.id) }; Haptics.tap() }
                        .buttonStyle(QuietButtonStyle(tint: c.status.backups ? Theme.gold : Theme.ivoryMuted))
                    Spacer()
                    Button((c.status.trainedUntil ?? 0) > engine.state.week ? "Staff trained" : "Train staff · " + cur.short(c.trainingCost)) {
                        let r = store.act { $0.trainStaff(companyID: company.id) }
                        if case .refused(let why)? = r { store.show(why, tone: "warn") } else { Haptics.success() }
                    }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                }
                if let last = c.status.log.first {
                    Text("Last: \(last.text)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }
}

private struct AccountRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var account: KeyAccounts.Account
    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text("\(Rivals.relationshipWord(account.relationship)) · since week \(account.sinceWeek) · paid you \(cur.short(account.totalPaid))")
                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                Text(account.discount == 0 ? "Full price" : "\(account.discount)% off").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(KeyAccounts.discounts, id: \.self) { d in
                        Button("\(d)%") { store.act { $0.setAccountDiscount(companyID: company.id, accountID: account.id, percent: d) } }
                            .buttonStyle(QuietButtonStyle(tint: account.discount == d ? Theme.gold : Theme.ivoryFaint))
                    }
                }
            }
            HStack {
                Button("Dinner · " + cur.short(cur.scaledPrice(6000))) {
                    let r = store.act { $0.meetAccount(companyID: company.id, accountID: account.id) }
                    switch r {
                    case .wait?: store.show("You met recently. Give it a few weeks.", tone: "warn")
                    case .cash?: store.show("Not enough cash for the dinner.", tone: "warn")
                    default: Haptics.success()
                    }
                }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                Spacer()
                Button("End contract") { store.act { $0.dropAccount(companyID: company.id, accountID: account.id) } }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
            }
        }.padding(.vertical, 8)
    }
}
