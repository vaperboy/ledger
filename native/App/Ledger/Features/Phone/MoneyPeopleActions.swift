import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Host a deal on a yacht, jet, castle or island: investors, franchise prospects or a rival owner. Used in Group and on the rival sheet
/// (`onlyRival` limits the guests to that one rival).
struct HostingSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onlyRival: Int? = nil
    @State private var pending: (piece: Luxury.Piece, option: StaffPerks.GuestOption)?

    private var guests: [StaffPerks.GuestOption] {
        engine.hostingGuests.filter { g in
            guard let r = onlyRival else { return true }
            if case .rival(_, let rid) = g.guest { return rid == r }
            return false
        }
    }

    var body: some View {
        let venues = engine.hostingVenues
        let list = guests
        if !venues.isEmpty && !list.isEmpty {
            let cur = engine.homeCurrency
            LedgerSection("Host a deal") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { n, g in
                        if n > 0 { Hairline() }
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(g.title.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text(g.detail + (g.hostedLately ? " · hosted lately" : "")).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Menu {
                                ForEach(venues) { v in
                                    Button("\(v.item.name) · \(cur.tidyShort(engine.hostingCost(pieceID: v.id) ?? 0))") { pending = (v, g) }
                                }
                            } label: { HStack(spacing: 3) { Text("Host"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) } }
                            .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                        }.padding(.vertical, 8)
                    }
                    Text("An evening needs a piece of yours that is not away, and once a month at most on the same piece.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                }
            }
            .confirmationDialog(pending.map { "Host \($0.option.title) on \($0.piece.item.name)?" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                if let p = pending {
                    Button("Host for \(cur.tidyShort(engine.hostingCost(pieceID: p.piece.id) ?? 0))") {
                        switch store.act({ $0.hostDeal(pieceID: p.piece.id, guest: p.option.guest) }) {
                        case .ok(let title, _)?: Haptics.success(); store.show(title, tone: "good")
                        case .away?: store.show("That piece is away.", tone: "warn")
                        case .wait?: store.show("You hosted on it a few weeks ago.", tone: "warn")
                        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash for the evening.", tone: "warn")
                        default: store.show("Not possible.", tone: "warn")
                        }
                        pending = nil
                    }
                }
            } message: {
                Text("Cost: the evening is paid from your cash. Benefit: for about three months the guests deal with you on better terms (a rival takes your offers more seriously, buyers come sooner, applicants come keener). Risk: it does not guarantee a deal, and the effect fades.")
            }
        }
    }
}

/// Lend a piece to a manager or star worker, shown in the manage rows of the luxury collection.
struct LendPieceSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var piece: Luxury.Piece
    @State private var pending: StaffPerks.Reward?

    private var weeks: Int { ["cars": 26, "homes": 2, "yachts": 1, "estates": 1][piece.item.category] ?? 1 }

    var body: some View {
        if let lent = engine.lentTo(pieceID: piece.id) {
            Text("Lent to \(lent.name) until \(GameCalendar.monthString(week: lent.until))").font(.caption).foregroundStyle(Theme.ivoryFaint).padding(.top, 8)
        } else if engine.lendablePieces.contains(where: { $0.id == piece.id }) {
            let people = engine.rewardCandidates
            if !people.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        ForEach(people) { r in
                            Button("\(r.name) · \(r.companyName)\(r.isManager ? " (manager)" : "")\(r.rewardedLately ? " · rewarded lately" : "")") { pending = r }
                        }
                    } label: { HStack(spacing: 3) { Text("Lend to a manager or star worker"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) } }
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                }.padding(.top, 8)
                .confirmationDialog(pending.map { "Lend \(piece.item.name) to \($0.name)?" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                    if let r = pending {
                        Button("Lend it") {
                            switch store.act({ $0.lendPiece(pieceID: piece.id, companyID: r.companyID, staffID: r.staffID) }) {
                            case .ok(let name)?: Haptics.success(); store.show("\(name) has the \(piece.item.name.lowercased()).", tone: "good")
                            default: store.show("Not possible.", tone: "warn")
                            }
                            pending = nil
                        }
                    }
                } message: {
                    Text("Cost: the piece is away for about \(weeks) week\(weeks == 1 ? "" : "s") and wears a little, so it is worth slightly less. Benefit: a happier, more loyal manager (or a rested worker) for about half a year. Risk: a second reward within half a year counts for half.")
                }
            }
        }
    }
}

/// Your own fund manager (Group > Money > Invest): hire one with a mandate, add or take out money, let them go.
struct FundManagerCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var amount = 0.0
    @State private var mandate = FinanceManager.Mandate.balanced
    @State private var hiring: FinanceManager.Candidate?
    @State private var confirmDismiss = false

    private func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    private func note(_ m: FinanceManager.Mandate) -> String {
        switch m {
        case .cautious: return "Follows about half of the market's moves. Small swings, a modest steady return."
        case .balanced: return "Follows most of the market. Moderate swings."
        case .aggressive: return "Follows the market and then some. The best years are big and so are the bad ones."
        }
    }

    var body: some View {
        let cur = engine.homeCurrency
        LedgerSection("Fund manager") {
            VStack(alignment: .leading, spacing: 10) {
                if let a = engine.fundManager {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                            Text("\(a.mandate.title) · fee \(pct(a.fee)) a year").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(cur.tidyShort(a.balance)).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivory)
                            Text("\(a.result >= 0 ? "+" : "−")\(pct(abs(a.result))) on \(cur.tidyShort(a.cost))").font(.system(size: 11)).foregroundStyle(Theme.change(a.result))
                        }
                    }
                    AmountField(title: "Amount", currency: cur, amount: $amount)
                    HStack {
                        Button("Add") {
                            let a = amount
                            if a > 0, store.act({ $0.addToFundManager(a) }) == true { Haptics.success(); store.show("\(cur.tidyShort(a)) added to what \(engine.fundManager?.name ?? "the manager") invests.", tone: "good"); amount = 0 }
                            else { Haptics.warning(); store.show(a > 0 ? "Not enough cash on the current account." : "Enter an amount first.", tone: "warn") }
                        }.buttonStyle(QuietButtonStyle())
                        Button("Take out") {
                            let a = amount
                            if a > 0, store.act({ $0.withdrawFromFundManager(a) }) == true { Haptics.success(); store.show("\(cur.tidyShort(a)) taken out and back on your account.", tone: "good"); amount = 0 }
                            else { Haptics.warning(); store.show(a > 0 ? "The manager holds less than that." : "Enter an amount first.", tone: "warn") }
                        }.buttonStyle(QuietButtonStyle())
                        Spacer(minLength: 0)
                        Button("Let go") { confirmDismiss = true }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                    }
                    Text("A gain is taxed as a capital gain when you take it out. The fee is taken from the balance, so a weak year can leave you with less than you put in.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                } else {
                    let cands = FinanceManager.candidates(engine.state)
                    if cands.isEmpty {
                        Text("A professional invests a sum for you in the index. They charge a yearly fee on the money they manage.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        Button("Meet fund managers") {
                            let met = store.act { $0.fundManagerCandidates() } ?? []
                            if met.isEmpty { Haptics.warning(); store.show("No fund manager is available to meet right now.", tone: "warn") } else { Haptics.tap(); store.show("You met \(met.count) fund managers. Choose a mandate and an amount below.", tone: "n") }
                        }.buttonStyle(QuietButtonStyle())
                    } else {
                        Text("Mandate").capsLabel(Theme.ivoryFaint)
                        SectionTabs(items: FinanceManager.Mandate.allCases, title: { $0.title }, selection: $mandate).padding(.horizontal, -Theme.Space.margin)
                        Text(note(mandate)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                        AmountField(title: "Amount to hand over", currency: cur, amount: $amount)
                        ForEach(Array(cands.enumerated()), id: \.element.id) { n, c in
                            if n > 0 { Hairline() }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                                    Text("Age \(c.age) · says \(Int(c.claimedSkill.rounded())) skill · \(String(format: "%g", c.yearsClaimed)) yr track record · fee \(pct(c.fee))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer(minLength: 8)
                                Button("Hire") { hiring = c }.buttonStyle(QuietButtonStyle())
                            }
                        }
                        Text("Their claims may be exaggerated; the true skill is never shown.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
        }
        .confirmationDialog(hiring.map { "Hand \(cur.tidyShort(amount)) to \($0.name)?" } ?? "", isPresented: Binding(get: { hiring != nil }, set: { if !$0 { hiring = nil } }), titleVisibility: .visible) {
            if let c = hiring {
                Button("Hire, \(mandate.title.lowercased()) mandate") {
                    switch store.act({ $0.hireFundManager(personID: c.id, mandate: mandate, amount: amount) }) {
                    case .ok?: Haptics.success(); store.show("\(c.name) now manages your money.", tone: "good"); amount = 0
                    case .notEnoughCash?: Haptics.warning(); store.show("You don't have that much available.", tone: "warn")
                    case .tooSmall?: store.show("Enter an amount first.", tone: "warn")
                    default: store.show("Not possible.", tone: "warn")
                    }
                    hiring = nil
                }
            }
        } message: {
            if let c = hiring {
                Text("Cost: a fee of \(pct(c.fee)) a year on the managed money, about \(cur.tidyShort(amount * c.fee)) a year on this sum. Benefit: it is invested for you without your time. Risk: it can lose value, more under an aggressive mandate, and the fee is due even in a bad year.")
            }
        }
        .confirmationDialog("Let the fund manager go?", isPresented: $confirmDismiss, titleVisibility: .visible) {
            Button("Let go", role: .destructive) {
                if store.act({ $0.dismissFundManager() }) == true { Haptics.warning(); store.show("The fund manager is gone. The managed money is back in your account.", tone: "n") }
                else { store.show("You have no fund manager.", tone: "warn") }
            }
        } message: { Text("All the managed money comes back to your account now. A gain is taxed as a capital gain at year end.") }
    }
}

/// Let the main office's finance manager run a holding (Company > holding): spare cash into the index fund, units sold to cover a deficit.
struct HoldingFinanceManagerCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var confirm = false
    @State private var found: [Person] = []
    @State private var confirmFire = false

    private var staffEntry: JSONValue? { engine.officeStaff.first { $0["role"].string == "fin" } }

    private func blockedText(_ r: Headquarters.RoomResult) -> String {
        switch r {
        case .office: return "Set up a group office first (Group tab, Group office)."
        case .homeoffice: return "A home office has no room for one. Upgrade the group office."
        case .desks: return "The group office has no free desk."
        case .locked: return "Needs a holding company."
        default: return "Not possible right now."
        }
    }

    @ViewBuilder private var hireFlow: some View {
        let cur = engine.currency(for: company)
        let room = engine.officeRoom(role: "fin")
        let role = engine.officeRoles.first { $0.id == "fin" }
        if let e = staffEntry {
            let id = e["id"].int
            Text("Hired: \(e["name"].string), \(cur.tidyShort(e["wage"].double)) a month, paid by the group.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            ForEach(engine.officePaperwork(personID: id), id: \.key) { item in
                HStack {
                    Text(item.text.tidyMoney).font(.system(size: 11.5)).foregroundStyle(item.done ? Theme.ivoryFaint : Theme.ivory)
                    Spacer(minLength: 8)
                    if !item.done { Button("Done") { store.act { $0.tickOfficePaperwork(personID: id, item: item.key) } }.buttonStyle(QuietButtonStyle()) }
                }
            }
            Button("Let go") { confirmFire = true }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
        } else if room == .ok {
            Text("Wage about \(cur.tidyShort(cur.scaledPrice(role?.monthlyPay ?? 82000))) a month, more for a better one. Effect: \(role?.text ?? "Runs your holding companies.")").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            if found.isEmpty {
                HStack {
                    Button("Ask around, free") { search(.network) }.buttonStyle(QuietButtonStyle())
                    Button("Job ad, \(cur.tidyShort(cur.scaledPrice(1500)))") { search(.ad) }.buttonStyle(QuietButtonStyle())
                    Button("Agency, \(cur.tidyShort(cur.scaledPrice(12000)))") { search(.agency) }.buttonStyle(QuietButtonStyle())
                }
                Text("An agency checks references; with the others the paperwork is yours to verify.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            } else {
                CandidateHireList(people: found, emptyText: "Nobody to meet now.") { c in
                    CandidateHireRow(person: c, currency: cur, subtitle: "Age \(c.age) · says \(Int(c.claimedSkill.rounded())) skill\(c.flag("checked") ? " · references checked" : "")",
                                     market: engine.goingRate(for: .office(role: "fin")), factors: [0.9, 1.0, 1.15, 1.3]) { wage in hire(c, wage) }
                }
            }
        } else {
            Text(blockedText(room)).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
        }
    }

    private func search(_ mode: Headquarters.SearchMode) {
        if let r = store.act({ $0.searchOffice(role: "fin", mode: mode) }) ?? nil, !r.isEmpty { found = r; Haptics.tap() }
        else { store.show("Nobody to meet now. Try again later or pay for a search.", tone: "warn") }
    }

    /// The same main-office hire as Group > Main office (`hireOffice`), reported in the same words.
    private func hire(_ c: Person, _ wage: Double) -> HireFeedback {
        let feedback = HireFeedback.from(store.act { $0.hireOffice(role: "fin", personID: c.id, monthlyWage: wage) }, name: c.name, role: "Finance manager")
        if feedback.isHired { found = [] }
        store.show(feedback.text, tone: feedback.isHired ? "good" : "warn")
        return feedback
    }

    var body: some View {
        let on = engine.holdingsRunByFinanceManager.contains(company.id)
        let cur = engine.currency(for: company)
        LedgerSection("Finance manager") {
            VStack(alignment: .leading, spacing: 8) {
                if on, let n = FinanceManager.negotiator(engine.state, holdingID: company.id) {
                    Text("\(n.name) runs this holding. Skill \(Int((n.skill * 100).rounded())) as a negotiator.").font(.system(size: 12.5)).foregroundStyle(Theme.ivory)
                } else {
                    Text(on ? "Your finance manager runs this holding." : "You run this holding yourself.").font(.system(size: 12.5)).foregroundStyle(Theme.ivory)
                }
                Text("Cost: none beyond their pay, which you already pay. Benefit: cash above \(cur.tidyShort(cur.scaledPrice(600000))) goes into the index fund each week, units are sold to cover a negative balance, and share sales are negotiated better. Risk: the index fund can fall, and selling it costs 0.66%.")
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                if staffEntry != nil { Button(on ? "Take it back" : "Let the finance manager run it") { confirm = true }.buttonStyle(QuietButtonStyle()) }
                else { Text("You have no finance manager. Hire one for the group office:").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }
                hireFlow
            }
        }
        .confirmationDialog("Let the finance manager go?", isPresented: $confirmFire, titleVisibility: .visible) {
            Button("Let go", role: .destructive) {
                if let id = staffEntry?["id"].int {
                    if store.act({ $0.fireOffice(personID: id) }) == true { Haptics.warning(); store.show("The finance manager has left. You run your holdings yourself again.", tone: "n") }
                    else { store.show("The finance manager is no longer in the group office.", tone: "warn") }
                }
            }
        } message: { Text("He stops running your holdings, and you run them yourself again.") }
        .confirmationDialog(on ? "Run \(company.name) yourself again?" : "Let the finance manager run \(company.name)?", isPresented: $confirm, titleVisibility: .visible) {
            Button(on ? "Take it back" : "Hand it over") {
                if let now = store.act({ $0.toggleHoldingFinanceManager(holdingID: company.id) }) ?? nil { Haptics.success(); store.show(now ? "Handed over." : "You run it yourself again.", tone: "n") }
                else { store.show("Hire a finance manager in the group office first.", tone: "warn") }
            }
        }
    }
}
