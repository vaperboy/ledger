import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

struct HireRequest: Identifiable {
    let id = UUID()
    var post: HirePost
    var companyID: Int?
    var chainID: Int? = nil
    var city: String? = nil
    var personID: Int
    var roleTitle: String
    var onHired: () -> Void = {}
}

struct HireDraft: Equatable {
    enum Kind: String, Hashable { case permanent, seasonal, temporary }
    enum Pay: String, Hashable { case usual, hour, fix }
    enum Plan: String, Hashable, CaseIterable {
        case salary = "Salary", mix = "Salary and commission", com = "Commission only"
        var id: String? { self == .salary ? nil : self == .mix ? "mix" : "com" }
    }

    var kind = Kind.permanent
    var percent = 100.0
    var weeks = 26
    var seasonIDs: Set<String> = []
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

struct HireLine: Identifiable, Equatable {
    let id = UUID()
    var mine: Bool
    var text: String
}

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

enum HireWords {
    static func hourly(_ v: Double, _ cur: Currency) -> String {
        let local: Double = v / cur.rate
        if local >= 100 { return cur.tidyDisplay(v) }
        let sy: String = cur.country.currencySymbol
        let number: String = String(format: "%.2f", local)
        let behind: Bool = (sy.count == 3 && sy.allSatisfy { $0.isUppercase && $0.isASCII }) || sy == "kr" || sy == "z\u{0142}"
        return behind ? number + "\u{00A0}" + sy : sy + number
    }

    static func first(_ name: String) -> String { name.split(separator: " ").first.map(String.init) ?? name }

    static func hours(_ h: Double) -> String { String(format: "%g", (h * 10).rounded() / 10) + " hours a week" }

    static func percentText(_ p: Double) -> String { String(format: "%g", (p * 10).rounded() / 10) + " percent" }

    static func weeksText(_ w: Int) -> String { w == 1 ? "1 week" : "\(w) weeks" }
}

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

struct SpeechBubble: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var mine: Bool

    var body: some View {
        let big: CGFloat = Theme.Radius.large, small: CGFloat = Theme.Space.xs
        let shape = UnevenRoundedRectangle(topLeadingRadius: big, bottomLeadingRadius: mine ? big : small, bottomTrailingRadius: mine ? small : big, topTrailingRadius: big, style: .continuous)
        HStack(spacing: 0) {
            if mine { Spacer(minLength: 44) }
            Text(text.tidyMoney).textStyle(.body).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                .background(shape.fill(mine ? P.accentWash : P.surface))
            if !mine { Spacer(minLength: 44) }
        }
    }
}

struct AskOfferCard: View {
    @Environment(\.outsidePalette) private var P
    var label: String
    var figure: String
    var note: String
    var noteTint: Color = Theme.inkSoft
    var outlined = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(label).textStyle(.label)
            Text(figure).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7)
            Text(note.tidyText).textStyle(.caption, tint: noteTint).lineLimit(2)
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(outlined ? P.accentWash : P.surface))
    }
}

struct CandidateHireRow<Extra: View>: View {
    @Environment(\.openHire) private var openHire
    @Environment(\.outsidePalette) private var P
    var person: Person
    var currency: Currency
    var subtitle: String
    var market: Double
    var request: HireRequest
    var roleKey: String = "candidate"
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                ThumbnailView(kind: .person, key: roleKey, size: 36, initials: person.name, face: person.faceKey)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(person.name.tidyText).textStyle(.headline)
                    Text(subtitle.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                    Text("Going rate " + currency.tidyShort(market) + " a month").textStyle(.caption, tint: P.inkFaint)
                }
                Spacer(minLength: Theme.Space.s)
                Button { Haptics.tap(); openHire(request) } label: { Text("Talk terms") }
                    .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                    .accessibilityIdentifier("hire-talk-terms")
            }
            extra()
        }
        .padding(.vertical, Theme.Space.s)
    }
}

extension CandidateHireRow where Extra == EmptyView {
    init(person: Person, currency: Currency, subtitle: String, market: Double, request: HireRequest, roleKey: String = "candidate") {
        self.init(person: person, currency: currency, subtitle: subtitle, market: market, request: request, roleKey: roleKey, extra: { EmptyView() })
    }
}

private struct OpenHireKey: EnvironmentKey {
    static let defaultValue: (HireRequest) -> Void = { _ in }
}

extension EnvironmentValues {
    var openHire: (HireRequest) -> Void {
        get { self[OpenHireKey.self] }
        set { self[OpenHireKey.self] = newValue }
    }
}

struct HireFlowSheet: View {
    var request: HireRequest
    var body: some View {
        HireOnePage(request: request, embedded: true)
    }
}

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
                Text(title).capsLabel(Theme.inkFaint)
                Spacer()
                if !people.isEmpty { Text("\(people.count)").textStyle(.caption, tint: Theme.inkFaint, numeric: true) }
            }
            if people.isEmpty {
                EmptyState(glyph: Glyph.people, title: emptyText, centered: false).padding(.top, Theme.Space.s)
            }
            ForEach(Array(people.enumerated()), id: \.element.id) { n, p in
                if n > 0 { Hairline() }
                row(p)
            }
        }
        .environment(\.openHire, { r in open = r })
        .centerSheet(item: $open, category: .detail, tone: .info) { r in HireFlowSheet(request: r).environmentObject(store) }
    }
}

enum CandidateClaims {
    static func line(_ engine: GameEngine, _ p: Person, extra: String = "") -> String {
        var parts: [String] = ["Age \(p.age)"]
        let years: Double? = engine.claimedExperienceYears(personID: p.id)
        parts.append(GameEngine.cvImpression(claimed: p.claimedSkill, experience: years))
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: " \u{00B7} ")
    }
}

struct HireChip: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.tidyText).textStyle(.body, tint: on ? P.ink : P.inkSoft, weight: on ? .semibold : .regular).lineLimit(1)
                .padding(.horizontal, Theme.Space.m).frame(minHeight: 34)
                .background(Capsule().fill(on ? P.accentWash : P.inset))
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
    }
}
