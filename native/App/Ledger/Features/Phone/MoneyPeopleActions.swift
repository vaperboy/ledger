import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct HostingSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onlyRival: Int? = nil
    @State private var pending: PendingAction?

    private var guests: [StaffPerks.GuestOption] {
        engine.hostingGuests.filter { g in
            guard let r = onlyRival else { return true }
            if case .rival(_, let rid) = g.guest { return rid == r }
            return false
        }
    }

    private func guestRow(_ g: StaffPerks.GuestOption, _ venues: [Luxury.Piece], _ cur: Currency) -> some View {
        HStack(spacing: 12) {
            IconCircle(glyph: Glyph.people, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.title.tidyMoney).textStyle(.body)
                Text(g.detail + (g.hostedLately ? " · hosted lately" : "")).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(venues) { v in
                    Button("\(v.item.name) · \(cur.tidyShort(engine.hostingCost(pieceID: v.id) ?? 0))") { askToHost(v, g, cur) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Host").font(.system(size: 12.5, weight: .medium))
                    GlyphView(glyph: Glyph.chevron, size: 10, weight: 2, tint: Theme.gold).rotationEffect(.degrees(90))
                }
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
            }
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        let venues = engine.hostingVenues
        let list = guests
        if !venues.isEmpty && !list.isEmpty {
            let cur = engine.homeCurrency
            CardSection("Host a deal") {
                ForEach(Array(list.enumerated()), id: \.offset) { n, g in
                    if n > 0 { CardLine() }
                    guestRow(g, venues, cur)
                }
            }
            .confirmAction($pending)
        }
    }

    private func askToHost(_ v: Luxury.Piece, _ g: StaffPerks.GuestOption, _ cur: Currency) {
        let cost: Double = engine.hostingCost(pieceID: v.id) ?? 0
        let effect: String = "The evening is paid from your cash. For about three months the guests deal with you on better terms: buyers come sooner and applicants come keener."
        pending = PendingAction(title: "Host \(g.title) on \(v.item.name)?", message: effect, button: "Host for \(cur.tidyShort(cost))",
                                amount: cost, currency: cur, risk: "It does not guarantee a deal, and the effect fades.") {
            switch store.act({ $0.hostDeal(pieceID: v.id, guest: g.guest) }) {
            case .ok(let title, _)?: Haptics.success(); store.show(title, tone: "good")
            case .away?: store.show("That piece is away.", tone: "warn")
            case .wait?: store.show("You hosted on it a few weeks ago.", tone: "warn")
            case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash for the evening.", tone: "warn")
            default: store.show("Not possible.", tone: "warn")
            }
        }
    }
}

struct LendPieceSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var piece: Luxury.Piece
    private var weeks: Int { ["cars": 26, "homes": 2, "yachts": 1, "estates": 1][piece.item.category] ?? 1 }

    var body: some View {
        if let lent = engine.lentTo(pieceID: piece.id) {
            HStack(spacing: 8) {
                GlyphView(glyph: Glyph.clock, size: 15, weight: 1.4, tint: Theme.ivoryFaint)
                Text("Lent to \(lent.name) until \(GameCalendar.monthString(week: lent.until))").textStyle(.caption)
            }.padding(.top, 8)
        } else if engine.lendablePieces.contains(where: { $0.id == piece.id }) {
            let people = engine.rewardCandidates
            if !people.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        ForEach(people) { r in
                            Button("\(r.name) · \(r.companyName)\(r.isManager ? " (manager)" : "")\(r.rewardedLately ? " · rewarded lately" : "")") { lend(r) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            GlyphView(glyph: Glyph.person, size: 15, weight: 1.4)
                            Text("Lend to a manager or star worker").font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
                    }
                }.padding(.top, 8)
            }
        }
    }

    private func lend(_ r: StaffPerks.Reward) {
        switch store.act({ $0.lendPiece(pieceID: piece.id, companyID: r.companyID, staffID: r.staffID) }) {
        case .ok(let name)?:
            Haptics.success()
            store.show("\(name) has the \(piece.item.name.lowercased()). Away for about \(weeks) week\(weeks == 1 ? "" : "s").", tone: "good")
        default: store.show("Not possible.", tone: "warn")
        }
    }
}

struct FundManagerCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var amount = 0.0
    @State private var mandate = FinanceManager.Mandate.balanced
    @State private var pending: PendingAction?

    private func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    private func note(_ m: FinanceManager.Mandate) -> String {
        switch m {
        case .cautious: return "Follows about half of the market's moves. Small swings, a modest steady return."
        case .balanced: return "Follows most of the market. Moderate swings."
        case .aggressive: return "Follows the market and then some. The best years are big and so are the bad ones."
        }
    }

    private func hiredView(_ a: FinanceManager.Account, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Card(padding: 16, radius: Theme.Radius.hero) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        IconCircle(glyph: Glyph.person)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).textStyle(.headline)
                            Text("Fund manager · \(a.mandate.title) · fee \(pct(a.fee)) a year").textStyle(.caption)
                        }
                    }
                    Text(cur.tidyShort(a.balance)).textStyle(.display).minimumScaleFactor(0.8).lineLimit(2)
                    Text("\(a.result >= 0 ? "+" : "−")\(pct(abs(a.result))) on \(cur.tidyShort(a.cost)) handed over").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.change(a.result))
                }
            }
            CardSection("Move money") {
                AmountField(title: "Amount", currency: cur, amount: $amount)
                HStack(spacing: 8) {
                    QuietButton(title: "Add", fullWidth: true) { addMoney(cur) }
                    QuietButton(title: "Take out", fullWidth: true) { takeOut(cur) }
                    QuietButton(title: "Let go", tint: Theme.loss, fullWidth: true) { askToLetGo() }
                }
                Text("A gain is taxed as a capital gain when you take it out. The fee is taken from the balance, so a weak year can leave you with less than you put in.").textStyle(.caption, tint: Theme.inkFaint)
            }
        }
    }

    private func addMoney(_ cur: Currency) {
        let a = amount
        if a > 0, store.act({ $0.addToFundManager(a) }) == true { Haptics.success(); store.show("\(cur.tidyShort(a)) added to what \(engine.fundManager?.name ?? "the manager") invests.", tone: "good"); amount = 0 }
        else { Haptics.warning(); store.show(a > 0 ? "Not enough cash on the current account." : "Enter an amount first.", tone: "warn") }
    }

    private func takeOut(_ cur: Currency) {
        let a = amount
        if a > 0, store.act({ $0.withdrawFromFundManager(a) }) == true { Haptics.success(); store.show("\(cur.tidyShort(a)) taken out and back on your account.", tone: "good"); amount = 0 }
        else { Haptics.warning(); store.show(a > 0 ? "The manager holds less than that." : "Enter an amount first.", tone: "warn") }
    }

    @ViewBuilder private func hireView(_ cur: Currency) -> some View {
        let cands = FinanceManager.candidates(engine.state)
        if cands.isEmpty {
            CardSection("Fund manager") {
                RowLine(glyph: Glyph.person, title: "Let a professional invest for you", subtitle: "They put a sum in the index and charge a yearly fee on the money they manage.")
                QuietButton(title: "Meet fund managers", fullWidth: true) {
                    let met = store.act { $0.fundManagerCandidates() } ?? []
                    if met.isEmpty { Haptics.warning(); store.show("No fund manager is available to meet right now.", tone: "warn") } else { Haptics.tap(); store.show("You met \(met.count) fund managers. Choose a mandate and an amount below.", tone: "n") }
                }
            }
        } else {
            CardSection("Fund manager") {
                Text("Mandate").capsLabel(Theme.ivoryFaint)
                SegmentedPill(items: FinanceManager.Mandate.allCases, title: { $0.title }, selection: $mandate)
                Text(note(mandate)).textStyle(.caption, tint: Theme.inkFaint)
                AmountField(title: "Amount to hand over", currency: cur, amount: $amount)
            }
            ForEach(cands, id: \.id) { c in candidateCard(c) }
            Text("Their claims may be exaggerated; how good they really are shows only in the results.").textStyle(.caption, tint: Theme.inkFaint)
        }
    }

    private func candidateCard(_ c: FinanceManager.Candidate) -> some View {
        Card(padding: 14, radius: Theme.Radius.row) {
            HStack(spacing: 12) {
                IconCircle(glyph: Glyph.person, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).textStyle(.body, weight: .medium)
                    Text("Age \(c.age) · \(GameEngine.cvImpression(claimed: c.claimedSkill, experience: c.yearsClaimed)) · fee \(pct(c.fee))").textStyle(.caption)
                }
                Spacer(minLength: 8)
                QuietButton(title: "Hire") { askToHire(c) }
            }
        }
    }

    var body: some View {
        let cur = engine.homeCurrency
        VStack(alignment: .leading, spacing: 14) {
            if let a = engine.fundManager { hiredView(a, cur) } else { hireView(cur) }
        }
        .confirmAction($pending)
    }

    private func askToHire(_ c: FinanceManager.Candidate) {
        let cur: Currency = engine.homeCurrency
        let sum: Double = amount
        let effect: String = "A fee of \(pct(c.fee)) a year on the managed money, about \(cur.tidyShort(sum * c.fee)) a year on this sum. It is invested for you without your time."
        let chosen: FinanceManager.Mandate = mandate
        pending = PendingAction(title: "Hand \(cur.tidyShort(sum)) to \(c.name)?", message: effect, button: "Hire, \(chosen.title.lowercased()) mandate",
                                amount: sum, currency: cur, risk: "It can lose value, more under an aggressive mandate, and the fee is due even in a bad year.") {
            switch store.act({ $0.hireFundManager(personID: c.id, mandate: chosen, amount: sum) }) {
            case .ok?: Haptics.success(); store.show("\(c.name) now manages your money.", tone: "good"); amount = 0
            case .notEnoughCash?: Haptics.warning(); store.show("You don't have that much available.", tone: "warn")
            case .tooSmall?: store.show("Enter an amount first.", tone: "warn")
            default: store.show("Not possible.", tone: "warn")
            }
        }
    }

    private func askToLetGo() {
        pending = PendingAction(title: "Let the fund manager go?", message: "All the managed money comes back to your account now. A gain is taxed as a capital gain when it comes back to you.", button: "Let go", destructive: true) {
            if store.act({ $0.dismissFundManager() }) == true { Haptics.warning(); store.show("The fund manager is gone. The managed money is back in your account.", tone: "n") }
            else { store.show("You have no fund manager.", tone: "warn") }
        }
    }
}
