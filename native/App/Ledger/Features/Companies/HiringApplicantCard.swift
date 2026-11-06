import SwiftUI
import Employees
import GameCore
import Countries
import Businesses
import Simulation

/// Patience is never shown as a number: only a feeling, from how much of the engine's patience is left (no rules, only wording).
enum PatienceWords {
    static func feeling(left: Int, of total: Int) -> (text: String, tint: Color) {
        let f: Double = total > 0 ? Double(left) / Double(total) : 0
        if f > 0.66 { return ("Relaxed", Theme.ink) }
        if f > 0.34 { return ("Getting impatient", Theme.warn) }
        return ("Close to walking away", Theme.loss)
    }
}

/// THE applicant row, the same on the Applicants page and the hire page: portrait, name, age, role and experience, what they are likely
/// to ask against the going rate, and "Talk terms". A tap on the row opens the CV, the first impression, references, trial notes and the
/// paid trial week. Only what the player can see before an interview is shown, in words: never a skill figure.
struct ApplicantRow: View {
    @Environment(\.outsidePalette) private var P
    var applicant: Applicant
    var roleName: String
    /// The company they answered, when the list spans several companies.
    var companyName: String = ""
    var currency: Currency
    /// The engine's ask preview for this person (`applicantAskPreview`), when there is one.
    var ask: (ask: Double, market: Double)?
    var open: Bool
    var talkIdentifier: String
    var onTap: () -> Void
    var onTrial: () -> Void
    var onTalk: () -> Void

    /// The paid trial week costs a week of the going monthly pay.
    static func trialCost(_ a: Applicant) -> Double { a.marketYearly / 12 / 4 }

    private var experienceLine: String {
        guard let y = applicant.claimedExperienceYears else { return "no experience given" }
        let n = Int(y.rounded())
        return "\(n) \(n == 1 ? "year" : "years")"
    }

    /// Likely ask in words against the going rate, else the going rate.
    private var wageLine: String {
        guard let ask, ask.market > 0 else { return "Going rate " + currency.tidyShort(applicant.marketMonthly) + " a month" }
        let ratio: Double = ask.ask / ask.market
        var words = "asks well above the going rate"
        if ratio < 0.95 { words = "asks below the going rate" } else if ratio <= 1.05 { words = "asks about the going rate" } else if ratio <= 1.2 { words = "asks a little above the going rate" }
        return "Likely " + words + ": " + currency.tidyShort(ask.ask) + " against " + currency.tidyShort(ask.market) + " a month"
    }

    var body: some View {
        let a = applicant
        let at: String = companyName.isEmpty ? "" : " \u{00B7} " + companyName
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                Button { Haptics.tap(); onTap() } label: {
                    HStack(alignment: .center, spacing: Theme.Space.m) {
                        ThumbnailView(kind: .person, key: a.role, size: 40, initials: a.name, face: a.faceKey)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(a.name.tidyText).textStyle(.headline).lineLimit(1)
                            Text("\(a.age) \u{00B7} \(roleName) \u{00B7} \(experienceLine)\(at)".tidyText).textStyle(.caption).lineLimit(2)
                            Text(wageLine.tidyText).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint(open ? "Hides the CV" : "Shows the CV and the trial week")
                Button { Haptics.tap(); onTalk() } label: { Text("Talk terms") }
                    .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                    .accessibilityIdentifier(talkIdentifier)
            }
            if open { details(a) }
        }
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title).textStyle(.caption, tint: P.inkFaint)
            Text(value.tidyText).textStyle(.body).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func details(_ a: Applicant) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                fact("CV", a.cvImpression)
                fact("Seems", a.seems)
            }
            if !a.resume.isEmpty { Text("\u{201C}\(a.resume)\u{201D}").textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
            Text(a.referencesChecked ? "References checked." : "References not checked.").textStyle(.caption, tint: P.inkFaint)
            ForEach(a.trialObservations, id: \.self) { (line: String) in
                Text(line.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if a.trialObservations.isEmpty {
                Button { Haptics.tap(); onTrial() } label: { Text("Trial week \u{00B7} \(currency.tidyShort(Self.trialCost(a)))") }
                    .buttonStyle(SecondaryButtonStyle(size: .compact))
            }
        }
        .padding(.leading, 40 + Theme.Space.m)
    }
}

/// The paid trial week, asked the same way from every applicant list.
enum ApplicantTrial {
    static func ask(_ store: GameStore, _ a: Applicant, companyID: Int, _ cur: Currency) -> PendingAction {
        let cost: Double = ApplicantRow.trialCost(a)
        let pid = a.personID
        return PendingAction(
            title: "Pay for a trial week with \(a.name)?",
            message: "Cost: \(cur.tidyShort(cost)) paid now, whatever you decide. Benefit: you see how their work really goes. Risk: one week shows only part of the picture, and they may take another job. It does not hire them.",
            button: "Pay \(cur.tidyShort(cost))", amount: cost, currency: cur) {
                if let seen = store.act({ $0.startTrialWeek(personID: pid, companyID: companyID) }) ?? nil {
                    Haptics.success(); store.show(seen.first?.text ?? "The trial week is done.", tone: "n")
                } else {
                    Haptics.warning(); store.show("Could not arrange a trial week: it was done already, or the company needs \(cur.tidyShort(cost)) in cash.", tone: "warn")
                }
            }
    }
}
