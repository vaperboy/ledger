import SwiftUI
import GameCore
import Businesses
import Countries
import Simulation

/// Customers: what they say (reviews, one system for every trade), the business customers (key accounts) and IT security.
struct CompanyCustomers: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            MoreHeader(glyph: Glyph.stats, title: "Customers", blurb: "What customers say, who buys in bulk, unpaid invoices and how safe your IT is.")
            reviews
            accounts
            creditCheck
            CompanyContracts(engine: engine, company: company)
            security
        }
    }

    // MARK: Reviews

    private var reviews: some View {
        let r = engine.reviewSummary(company, limit: showAll ? 30 : 6)
        return MoreBlock(title: "Reviews", trailing: {
            Text(r.enough ? r.word : "No rating yet").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                FigureStrip(items: [
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
                            Text(line.text.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                            Text((line.flag.isEmpty ? "" : line.flag + " ") + "\(line.who), \(line.age)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                    if r.count > 6 {
                        Button(showAll ? "Show fewer" : "Show more") { showAll.toggle() }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
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
            MoreBlock(title: "Business customers", card: false, trailing: {
                Text("\(info.accounts.count) of \(info.limit) key accounts").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
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

    // MARK: Credit check

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
                    Hairline()
                    HStack {
                        Text(c.status.managerPicks ? "Your manager picks the level, keeps the backups and books the training." : "Your choice stands.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        Spacer()
                        if !c.status.managerPicks { Button("Leave it to the manager") { store.act { $0.leaveCyberToManager(companyID: company.id) }; store.saved("your manager now picks the IT protection") }.buttonStyle(TinyButtonStyle(tint: Theme.gold)) }
                    }
                }
                ForEach(Cyber.levels.indices, id: \.self) { (i: Int) in
                    Hairline()
                    levelRow(i, c: c, cur: cur)
                }
                Hairline()
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
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.caption).foregroundStyle(on ? Theme.gold : Theme.ivoryFaint)
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
