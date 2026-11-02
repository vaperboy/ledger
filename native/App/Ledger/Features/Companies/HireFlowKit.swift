import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

// The ONE hiring flow of the game (Stage 3, spec 5.3C): every hire (workers, managers, assistants, team heads, executives, office staff, the analyst)
// goes through page 1 (`HireTermsPage`, the contract terms) and page 2 (`HireSalaryPage`, the salary negotiation). This file holds what both pages
// share: the request, the draft of the terms, the model that keeps the draft when the player goes back from page 2 to page 1, and a few formatters.
// No game rule lives here: the engine (`hireDraftOptions`, `hireTermsProblem`, `hireSalaryTalk`, `hearTheirAsk`, `hireOffer`) decides and prices.

/// Who is being hired into which post. `onHired` lets the list the player came from refresh itself. The flow is shown in a sheet owned by the list
/// (`CandidateHireList`, or the Hiring screen), which stays on screen when a row disappears because the person was hired.
struct HireRequest: Identifiable {
    let id = UUID()
    var post: HirePost
    var companyID: Int?
    var chainID: Int? = nil
    var city: String? = nil
    var personID: Int
    /// The post in words for messages ("Assistant manager", "Barista").
    var roleTitle: String
    var onHired: () -> Void = {}
}

/// The terms of page 1, as the player has set them. `terms(...)` turns them into the engine's `Hiring.Terms`.
struct HireDraft: Equatable {
    enum Kind: String, Hashable { case permanent, seasonal, temporary }
    enum Pay: String, Hashable { case usual, hour, fix }
    /// The pay plan of a seller (salary, salary and commission, commission only).
    enum Plan: String, Hashable, CaseIterable {
        case salary = "Salary", mix = "Salary and commission", com = "Commission only"
        var id: String? { self == .salary ? nil : self == .mix ? "mix" : "com" }
    }

    var kind = Kind.permanent
    var percent = 100.0
    var weeks = 26
    var seasonIDs: Set<String> = []
    /// 0 = the job returns every year, 1 or 2 = it ends after that many seasons.
    var seasonCount = 0
    var pay = Pay.usual
    var plan = Plan.salary
    var rate = 0.0
    var ownCar = false
    var bonusPlan: String? = nil
    var expenses: Set<String> = []
    var promises: [StaffPromises.Draft] = []
    var expectations: Set<String> = []

    func seasonMonths(busy: [Int]) -> [Int] {
        let chosen: [Int] = StaffTalks.seasons.filter { seasonIDs.contains($0.id) }.flatMap { $0.months }
        if !chosen.isEmpty { return Array(Set(chosen)).sorted() }
        return busy.isEmpty ? [6, 7, 8] : busy
    }

    /// The engine's terms for this draft. `worker` posts carry the working percentage, contract kind and pay basis; the others are full-time posts.
    func terms(worker: Bool, sells: Bool, busy: [Int]) -> Hiring.Terms {
        var t = Hiring.Terms()
        if worker {
            t.percent = percent
            if kind == .seasonal { t.seasonMonths = seasonMonths(busy: busy); t.seasonCount = seasonCount }
            if kind == .temporary { t.fixedTermWeeks = weeks }
            if pay == .hour { t.basis = "hour" } else if pay == .fix { t.basis = "fix" }
            if sells, let planID = plan.id { t.payPlan = planID; t.commissionRate = rate }
            t.ownCar = ownCar
            t.bonusPlan = bonusPlan
            t.expenseItems = expenses.sorted()
        }
        t.promises = promises
        t.expectations = expectations.sorted()
        return t
    }

    func isCommissionOnly(sells: Bool) -> Bool { sells && plan == .com }
}

/// One line of the salary talk, as a speech bubble.
struct HireLine: Identifiable, Equatable {
    let id = UUID()
    var mine: Bool
    var text: String
}

/// Kept by page 1 and read by page 2, so going back from the salary page keeps every term and the talk so far.
final class HireFlowModel: ObservableObject {
    @Published var draft = HireDraft()
    @Published var offer = 0.0
    @Published var offerSet = false
    @Published var lines: [HireLine] = []
    @Published var hired = false
    @Published var gone = false
    @Published var finished = false
    @Published var closing = ""
}

/// Money and words the two pages share.
enum HireWords {
    /// An hourly wage with pence where the currency has small units ("£14.20"), a whole amount otherwise.
    static func hourly(_ v: Double, _ cur: Currency) -> String {
        let local: Double = v / cur.rate
        if local >= 100 { return cur.tidyDisplay(v) }
        let sy: String = cur.country.currencySymbol
        let number: String = String(format: "%.2f", local)
        let behind: Bool = (sy.count == 3 && sy.allSatisfy { $0.isUppercase && $0.isASCII }) || sy == "kr" || sy == "z\u{0142}"
        return behind ? number + "\u{00A0}" + sy : sy + number
    }

    static func first(_ name: String) -> String { name.split(separator: " ").first.map(String.init) ?? name }

    /// "37.5 hours a week" / "7.5 hours a week".
    static func hours(_ h: Double) -> String { String(format: "%g", (h * 10).rounded() / 10) + " hours a week" }

    static func percentText(_ p: Double) -> String { String(format: "%g", (p * 10).rounded() / 10) + " percent" }

    static func weeksText(_ w: Int) -> String { w == 1 ? "1 week" : "\(w) weeks" }
}

/// What the engine says in words about a hire's outcome, the same on every screen.
enum HireOutcomeWords {
    static func line(_ o: HireOutcome, name: String, cur: Currency, hourFactor: Double) -> (text: String, tone: String) {
        let first: String = HireWords.first(name)
        switch o {
        case .hired: return ("Deal. \(first) will start straight away.", "good")
        case .countered(let amount, let isFinal):
            let figure: String = HireWords.hourly(amount / hourFactor, cur)
            return (isFinal ? "\(figure) an hour is as low as I will go." : "I would take it for \(figure) an hour.", "n")
        case .refused: return ("That is not a serious offer. Come closer to what the job pays.", "warn")
        case .walkedAway: return ("\(first) has lost patience and taken another job.", "warn")
        case .taken: return ("\(first) has taken another job.", "warn")
        case .termsRefused(let why): return (why, "warn")
        case .blocked(let why): return (why, "warn")
        }
    }
}

/// One line of a talk, as a speech bubble: theirs on the left, yours on the right (champagne).
struct SpeechBubble: View {
    var text: String
    var mine: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: mine ? 16 : 4, bottomTrailingRadius: mine ? 4 : 16, topTrailingRadius: 16, style: .continuous)
        HStack(spacing: 0) {
            if mine { Spacer(minLength: 44) }
            Text(text.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(shape.fill(mine ? Theme.goldSelected : Theme.surface))
                .overlay(shape.strokeBorder(mine ? Theme.gold : Theme.border, lineWidth: 1))
            if !mine { Spacer(minLength: 44) }
        }
    }
}

/// A small-caps label, a serif figure and a note under it, in a bordered card (the contract discussion uses it for a request).
struct AskOfferCard: View {
    var label: String
    var figure: String
    var note: String
    var noteTint: Color = Theme.ivoryMuted
    var outlined = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).capsLabel(Theme.gold)
            Text(figure).font(.serifTitle(24)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.system(size: 11.5)).foregroundStyle(noteTint).lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(outlined ? Theme.gold : Theme.border, lineWidth: 1))
    }
}

/// One candidate of any shortlist: who they are, what they claim in words, the going rate for the post, optional checks (`extra`), and one way on:
/// "Talk terms", which opens the two-page flow. Their own ask is never shown here; they name it in the salary talk.
struct CandidateHireRow<Extra: View>: View {
    @Environment(\.openHire) private var openHire
    var person: Person
    var currency: Currency
    var subtitle: String
    /// The going rate for the post, a month for a full week.
    var market: Double
    var request: HireRequest
    var roleKey: String = "candidate"
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ThumbnailView(kind: .person, key: roleKey, size: 36, initials: person.name, face: person.faceKey)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(currency.tidyShort(market)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Text("market pay a month").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
            extra()
            Button { Haptics.tap(); openHire(request) } label: {
                HStack {
                    Text("Talk terms").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    Spacer(minLength: 6)
                    GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.gold)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("hire-talk-terms")
        }
        .padding(.vertical, 8)
    }
}

extension CandidateHireRow where Extra == EmptyView {
    init(person: Person, currency: Currency, subtitle: String, market: Double, request: HireRequest, roleKey: String = "candidate") {
        self.init(person: person, currency: currency, subtitle: subtitle, market: market, request: request, roleKey: roleKey, extra: { EmptyView() })
    }
}

/// How a row asks its list to open the hiring flow.
private struct OpenHireKey: EnvironmentKey {
    static let defaultValue: (HireRequest) -> Void = { _ in }
}

extension EnvironmentValues {
    var openHire: (HireRequest) -> Void {
        get { self[OpenHireKey.self] }
        set { self[OpenHireKey.self] = newValue }
    }
}

/// The frame of the hiring flow: its own navigation stack, so page 2 is pushed on page 1 and Back returns to it.
struct HireFlowSheet: View {
    var request: HireRequest
    private var isWorker: Bool { if case .worker = request.post { return true }; return false }
    /// Workers get the one-page terms and salary talk; the other posts keep the two pages.
    var body: some View {
        PopupNavStack {
            if isWorker { HireOnePage(request: request) } else { HireTermsPage(request: request) }
        }
    }
}

/// A shortlist of candidates with a heading and a real empty state. It owns the sheet of the hiring flow for its rows.
struct CandidateHireList<Row: View>: View {
    @EnvironmentObject var store: GameStore
    @State private var open: HireRequest?
    var people: [Person]
    var title = "Candidates"
    var emptyText: String
    @ViewBuilder var row: (Person) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).capsLabel(Theme.ivoryFaint)
                Spacer()
                if !people.isEmpty { Text("\(people.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
            }
            if people.isEmpty {
                Text(emptyText).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(people.enumerated()), id: \.element.id) { n, p in
                if n > 0 { Hairline() }
                row(p)
            }
        }
        .environment(\.openHire, { r in open = r })
        .centerSheet(item: $open) { r in HireFlowSheet(request: r).environmentObject(store) }
    }
}

/// What a candidate says about themselves on the CV, in words only: age, the years claimed and how the CV reads.
enum CandidateClaims {
    static func line(_ engine: GameEngine, _ p: Person, extra: String = "") -> String {
        var parts: [String] = ["Age \(p.age)"]
        let years: Double? = engine.claimedExperienceYears(personID: p.id)
        parts.append(GameEngine.cvImpression(claimed: p.claimedSkill, experience: years))
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: " \u{00B7} ")
    }
}
