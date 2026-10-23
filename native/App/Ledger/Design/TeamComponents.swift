import SwiftUI
import GameCore
import Countries
import Businesses

// Shared pieces for people screens: one candidate-hire row and list, one authority picker, one role + scope badge, one sheet frame.
// Any hiring screen can adopt them; the engine call stays with the caller, which turns the engine's answer into a `HireFeedback`.

/// The engine's answer to a job offer in words, so every hiring screen reports it the same way.
enum HireFeedback: Equatable {
    case hired(String)
    /// Too low this time; a better offer may work.
    case declined(String)
    /// Gone or not possible (took another job, no premises, no cash).
    case unavailable(String)

    var text: String { switch self { case .hired(let t), .declined(let t), .unavailable(let t): return t } }
    var isHired: Bool { if case .hired = self { return true } else { return false } }
    var tint: Color { switch self { case .hired: return Theme.gain; case .declined: return Theme.caution; case .unavailable: return Theme.loss } }

    /// For the management offers (assistant, team posts, executives).
    static func from(_ r: ManagerModel.OfferResult?, name: String, role: String) -> HireFeedback {
        switch r {
        case .ok?: return .hired("\(name) starts as \(role.lowercased()).")
        case .refused?: return .declined("\(name) found that a bit low. Offer more or pick someone else.")
        case .taken?: return .unavailable("\(name) took another job.")
        case nil: return .unavailable("No game is loaded.")
        }
    }

    /// For hiring a store manager.
    static func from(_ r: ManagerModel.HireResult?, name: String, company: String) -> HireFeedback {
        switch r {
        case .ok?: return .hired("\(name) now runs \(company).")
        case .refused?: return .declined("\(name) declined. A better offer may change their mind.")
        case .taken?: return .unavailable("\(name) took another job.")
        case .needsPremises?: return .unavailable("A manager needs premises to run the team from. Rent a place first.")
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
    /// Multiples of the asking wage to offer (1.0 is exactly what they ask).
    var factors: [Double] = [1.0, 1.1]
    var offer: (Double) -> HireFeedback
    @ViewBuilder var extra: () -> Extra
    @State private var feedback: HireFeedback?

    private func wage(_ f: Double) -> Double { f == 1 ? person.askingMonthlyWage : currency.roundedStep(person.askingMonthlyWage * f, about: 500) }
    private func label(_ f: Double) -> String { f == 1 ? "Offer \(currency.short(wage(f)))" : "\(currency.short(wage(f))) (+\(Int(((f - 1) * 100).rounded()))%)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text(subtitle ?? defaultSubtitle).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(currency.short(person.askingMonthlyWage)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Text("asks a month").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                }
            }
            extra()
            HStack(spacing: 10) {
                ForEach(factors, id: \.self) { f in
                    Button(label(f)) {
                        let r = offer(wage(f))
                        feedback = r
                        if r.isHired { Haptics.success() } else { Haptics.warning() }
                    }
                    .buttonStyle(QuietButtonStyle(tint: f == 1 ? Theme.gold : Theme.ivoryMuted))
                }
                Spacer(minLength: 0)
            }
            if let feedback {
                Text(feedback.text).font(.system(size: 11.5)).foregroundStyle(feedback.tint).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Below what they ask they may say no; above it they are more likely to stay.").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
            }
        }
        .padding(.vertical, 8)
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
    init(person: Person, currency: Currency, subtitle: String? = nil, factors: [Double] = [1.0, 1.1], offer: @escaping (Double) -> HireFeedback) {
        self.init(person: person, currency: currency, subtitle: subtitle, factors: factors, offer: offer, extra: { EmptyView() })
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

/// Picks an authority level, with what it means under the picker.
struct AuthorityLevelPicker: View {
    var level: Int
    var set: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTabs(items: [0, 1, 2], title: { AuthorityWords.label($0) }, selection: Binding(get: { min(2, max(0, level)) }, set: { set($0) }))
                .padding(.horizontal, -Theme.Space.margin)
            Text(AuthorityWords.consequence(level)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
        }
    }
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
