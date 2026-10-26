import SwiftUI
import GameCore
import Countries
import Businesses

// Shared pieces for people screens: one candidate-hire row and list, one authority picker, one role + scope badge, one sheet frame.
// Any hiring screen can adopt them; the engine call stays with the caller, which turns the engine's answer into a `HireFeedback`.

/// The engine's answer to a job offer in words, so every hiring screen reports it the same way.
enum HireFeedback: Equatable {
    case hired(String)
    /// An insult or a flat no this time; a better offer may work.
    case declined(String)
    /// Gone or not possible (took another job, lost patience, no premises, no cash).
    case unavailable(String)
    /// They name their own figure (a monthly wage in accounting units): accept it, counter, or walk away. The engine may make it a fair one or not;
    /// the going rate shown on the row is what to judge it against.
    case countered(Double, String)

    var text: String { switch self { case .hired(let t), .declined(let t), .unavailable(let t), .countered(_, let t): return t } }
    var isHired: Bool { if case .hired = self { return true } else { return false } }
    var counterAmount: Double? { if case .countered(let a, _) = self { return a } else { return nil } }
    var tint: Color { switch self { case .hired: return Theme.gain; case .declined, .countered: return Theme.caution; case .unavailable: return Theme.loss } }

    /// The words for a counter, the same on every screen.
    static func counter(_ c: Negotiation.Counter, name: String) -> HireFeedback {
        .countered(c.amount, c.isFinal ? "\(name) says this is as low as they will go." : "\(name) would take the job for this much.")
    }
    static func insulted(_ name: String) -> HireFeedback { .declined("\(name) took that as an insult and named no figure. Come closer to the going rate or pick someone else.") }
    static func lostPatience(_ name: String) -> HireFeedback { .unavailable("\(name) lost patience and took another job.") }

    /// For the management offers (assistant, team posts, executives).
    static func from(_ r: ManagerModel.OfferResult?, name: String, role: String) -> HireFeedback {
        switch r {
        case .ok?: return .hired("\(name) starts as \(role.lowercased()).")
        case .refused?: return insulted(name)
        case .taken?: return .unavailable("\(name) took another job.")
        case .countered(let c)?: return counter(c, name: name)
        case .walkedAway?: return lostPatience(name)
        case nil: return .unavailable("No game is loaded.")
        }
    }

    /// For hiring workers (`GameEngine.hire`, any terms).
    static func from(_ r: Hiring.HireResult?, name: String) -> HireFeedback {
        switch r {
        case .ok?: return .hired("\(name) has joined.")
        case .refused?: return insulted(name)
        case .taken?: return .unavailable("\(name) took another job.")
        case .countered(let c)?: return counter(c, name: name)
        case .walkedAway?: return lostPatience(name)
        case .planRefused?: return .declined("\(name) will not take the job on those terms (commission only, or a fixed term) but is still looking. Offer a salary or a permanent contract.")
        case nil: return .unavailable("No game is loaded.")
        }
    }

    /// For hiring a store manager.
    static func from(_ r: ManagerModel.HireResult?, name: String, company: String) -> HireFeedback {
        switch r {
        case .ok?: return .hired("\(name) now runs \(company).")
        case .refused?: return insulted(name)
        case .taken?: return .unavailable("\(name) took another job.")
        case .needsPremises?: return .unavailable("A manager needs premises to run the team from. Rent a place first.")
        case .countered(let c)?: return counter(c, name: name)
        case .walkedAway?: return lostPatience(name)
        case nil: return .unavailable("No game is loaded.")
        }
    }

    /// For a main-office role (`hireOffice`).
    static func from(_ r: Headquarters.HireResult?, name: String, role: String) -> HireFeedback {
        switch r {
        case .ok?: return .hired("\(name) joins as \(role.lowercased()). Complete the paperwork.")
        case .refuse?: return insulted(name)
        case .taken?: return .unavailable("\(name) took another job.")
        case .countered(let c)?: return counter(c, name: name)
        case .walkedAway?: return lostPatience(name)
        case .blocked(_)?: return .unavailable("There is no room for that role.")
        case nil: return .unavailable("No game is loaded.")
        }
    }

    /// For the head-office data analyst (`hireDataAnalyst`).
    static func from(_ r: MarketMap.HQHire?, name: String) -> HireFeedback {
        switch r {
        case .ok?: return .hired("\(name) starts as your data analyst.")
        case .refused?: return insulted(name)
        case .taken?: return .unavailable("\(name) took another job.")
        case .have?: return .unavailable("You already have a data analyst.")
        case .countered(let c)?: return counter(c, name: name)
        case .walkedAway?: return lostPatience(name)
        case nil: return .unavailable("No game is loaded.")
        }
    }
}

/// One candidate: who they are, what they ask, optional checks (interview, references), and offers at the asking wage and above.
/// The result of the last offer stays under the row until the next one.
struct CandidateHireRow<Extra: View>: View {
    var person: Person
    var currency: Currency
    /// Defaults to "Age · years of experience · résumé".
    var subtitle: String? = nil
    /// The going rate for the role. When set, the discussion starts from it: the row shows it instead of the person's asking wage (which stays
    /// hidden) and offers are multiples of it, so the same rate is offered to anyone and skill decides who takes it.
    var market: Double? = nil
    /// Multiples of the asking wage (or of the market rate when `market` is set) to offer; 1.0 is that amount.
    var factors: [Double] = [1.0, 1.1]
    var offer: (Double) -> HireFeedback
    @ViewBuilder var extra: () -> Extra
    @State private var feedback: HireFeedback?
    @State private var lastOffer: Double = 0
    /// The figure typed or stepped for a counter of your own (accounting units); 0 until set.
    @State private var customCounter: Double = 0

    private var reference: Double { market ?? person.askingMonthlyWage }
    private func wage(_ f: Double) -> Double { f == 1 ? reference : currency.roundedStep(reference * f, about: 500) }
    private func label(_ f: Double) -> String { f == 1 ? "Offer \(currency.tidyShort(wage(f)))" : "\(currency.tidyShort(wage(f))) (\(f > 1 ? "+" : "")\(Int(((f - 1) * 100).rounded()))%)" }

    /// Make an offer and keep the answer under the row.
    private func submit(_ amount: Double) {
        lastOffer = amount
        let r = offer(amount)
        feedback = r
        if r.isHired { Haptics.success() } else { Haptics.warning() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(subtitle ?? defaultSubtitle).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(currency.tidyShort(reference)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Text(market == nil ? "asks a month" : "going rate a month").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
            extra()
            if let counter = feedback?.counterAmount {
                counterControls(counter)
            } else {
                HStack(spacing: 10) {
                    ForEach(factors, id: \.self) { f in
                        Button(label(f)) { submit(wage(f)) }
                            .buttonStyle(QuietButtonStyle(tint: f == 1 ? Theme.gold : Theme.ivoryMuted))
                    }
                    Spacer(minLength: 0)
                }
            }
            if let feedback {
                Text(feedback.text).font(.system(size: 11.5)).foregroundStyle(feedback.tint).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(market == nil ? "Below what they ask they may say no; above it they are more likely to stay."
                     : "You open at the going rate for the job. Some people take it gladly or for less; others want more and may name their own figure, and a weak candidate may cost more than they are worth. Push too hard and they walk away.").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
            }
        }
        .padding(.vertical, 8)
    }

    /// Their counter: take it, answer with a figure between your last offer and theirs, or leave the table.
    @ViewBuilder private func counterControls(_ counter: Double) -> some View {
        HStack(spacing: 10) {
            Button("Accept \(currency.tidyShort(counter))") { submit(counter) }
                .buttonStyle(QuietButtonStyle(tint: Theme.gold))
            Menu("Counter") {
                ForEach([0.25, 0.5, 0.75], id: \.self) { share in
                    let amount = currency.roundedStep(lastOffer + (counter - lastOffer) * share, about: 500)
                    Button("\(currency.tidyShort(amount))") { submit(amount) }
                }
            }
            .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ivoryMuted)
            Button("Walk away") { feedback = .declined("You left the table. They may talk again later if you come back.") }
                .buttonStyle(QuietButtonStyle(tint: Theme.loss))
            Spacer(minLength: 0)
        }
        customCounterControls(counter)
    }

    /// Your own figure for the counter: step it up or down, or type it. Any figure is allowed; the person answers it like any other offer.
    @ViewBuilder private func customCounterControls(_ counter: Double) -> some View {
        let step = currency.stepSize(about: 500)
        let shown = customCounter > 0 ? customCounter : currency.roundedStep(lastOffer + (counter - lastOffer) * 0.5, about: 500)
        VStack(alignment: .leading, spacing: 4) {
            Stepper("Your figure: \(currency.tidyShort(shown)) a month", onIncrement: { customCounter = shown + step }, onDecrement: { customCounter = max(step, shown - step) })
                .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            DisclosureGroup("Type an exact figure") {
                AmountField(title: "Monthly pay", currency: currency, amount: $customCounter)
            }.font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            Button("Counter with \(currency.tidyShort(shown))") { submit(shown) }
                .buttonStyle(QuietButtonStyle(tint: Theme.gold))
        }
    }

    private var defaultSubtitle: String {
        var parts = ["Age \(person.age)"]
        let exp = person.num("exp")
        if exp > 0 { parts.append("\(String(format: "%g", exp)) yr") }
        let r = person.str("resume")
        if !r.isEmpty { parts.append(r) }
        return parts.joined(separator: " · ")
    }
}

extension CandidateHireRow where Extra == EmptyView {
    init(person: Person, currency: Currency, subtitle: String? = nil, market: Double? = nil, factors: [Double] = [1.0, 1.1], offer: @escaping (Double) -> HireFeedback) {
        self.init(person: person, currency: currency, subtitle: subtitle, market: market, factors: factors, offer: offer, extra: { EmptyView() })
    }
}

/// A shortlist of candidates with a heading and a real empty state.
struct CandidateHireList<Row: View>: View {
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
    }
}

/// The words for authority levels, the same on every screen: 0 asks you, 1 within limits, 2 full control.
enum AuthorityWords {
    static let labels = ["Asks you", "Within limits", "Full control"]
    static func label(_ level: Int) -> String { labels[min(2, max(0, level))] }
    static func consequence(_ level: Int) -> String {
        ["Every decision and spend comes to you as a message. Safe, but you will be asked a lot.",
         "Handles things up to the limits you set; anything bigger comes to you.",
         "Decides everything on their own. Fewer messages; you see results, not choices."][min(2, max(0, level))]
    }
}

/// Picks an authority level, with what it means under the picker. The same `AuthorityPicker` as the executive posts, without a spend limit.
struct AuthorityLevelPicker: View {
    var level: Int
    var set: (Int) -> Void
    var body: some View { AuthorityPicker(level: level, style: .full, setLevel: set) }
}

/// Role plus scope (store, company, chain, region, group) as one badge, as on every management list.
struct RoleScopeBadge: View {
    var role: String
    var scope: String
    var body: some View { Chip(text: "\(role) · \(scope)", tint: scope == "store" || scope == "company" ? Theme.gold : Theme.goldLight) }
}

/// One row of a management list: the person (or "Vacant"), their role + scope badge, one line on what matters now, and the pay.
/// The whole row is the button that opens the post's sheet.
struct ManagementRow: View {
    var name: String?
    var role: String
    var scope: String
    var line: String
    var lineTint: Color = Theme.ivoryFaint
    var wage: String?
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name ?? "Vacant").font(.system(size: 13.5, weight: .medium)).foregroundStyle(name == nil ? Theme.ivoryMuted : Theme.ivory).lineLimit(1)
                RoleScopeBadge(role: role, scope: scope)
                if !line.isEmpty { Text(line).font(.system(size: 11)).foregroundStyle(lineTint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            if let wage { Text(wage).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory) }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The frame of a people sheet: its own navigation bar with Done, a scroll view and the page background.
struct PeopleSheet<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) { content() }
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .ledgerBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(Theme.gold) } }
        }
    }
}
