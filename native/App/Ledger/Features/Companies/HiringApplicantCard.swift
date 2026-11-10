import SwiftUI
import Employees
import GameCore
import Countries
import Businesses
import Simulation

enum PatienceWords {
    static func feeling(left: Int, of total: Int) -> (text: String, tint: Color) {
        let f: Double = total > 0 ? Double(left) / Double(total) : 0
        if f > 0.66 { return ("Relaxed", Theme.ink) }
        if f > 0.34 { return ("Getting impatient", Theme.warn) }
        return ("Close to walking away", Theme.loss)
    }
}

struct ApplicantRow: View {
    @Environment(\.outsidePalette) private var P
    var applicant: Applicant
    var roleName: String
    var currency: Currency
    var ask: (ask: Double, market: Double)?
    var open: Bool
    var talkIdentifier: String
    var onTap: () -> Void
    var onTrial: () -> Void
    var onTalk: () -> Void

    static func trialCost(_ a: Applicant) -> Double { a.marketYearly / 12 / 4 }

    private var experienceLine: String {
        guard let y = applicant.claimedExperienceYears else { return "no experience given" }
        let n = Int(saturating: y.rounded())
        return "\(n) \(n == 1 ? "year" : "years")"
    }

    private var wageWords: String {
        guard let ask, ask.market > 0 else { return "going rate" }
        let ratio: Double = ask.ask / ask.market
        if ratio < 0.95 { return "below the rate" }
        if ratio <= 1.05 { return "about the rate" }
        if ratio <= 1.2 { return "a bit above" }
        return "well above"
    }

    private var wageFigure: Double { ask.map { $0.ask } ?? applicant.marketMonthly }

    var body: some View {
        let a = applicant
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.xs) {
                Button { Haptics.tap(); onTalk() } label: {
                    HStack(alignment: .center, spacing: Theme.Space.m) {
                        ThumbnailView(kind: .person, key: a.role, size: ThinPersonRow.portrait, initials: a.name, face: a.faceKey)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(a.name.tidyText).textStyle(.headline).lineLimit(1)
                            Text("\(a.age) \u{00B7} \(roleName) \u{00B7} \(experienceLine)".tidyText).textStyle(.caption).lineLimit(2)
                        }
                        Spacer(minLength: Theme.Space.s)
                        VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                            Text(currency.tidyShort(wageFigure)).textStyle(.headline, numeric: true).lineLimit(1)
                            Text(wageWords).textStyle(.caption, tint: P.inkFaint).lineLimit(1)
                        }
                        .frame(maxWidth: 120, alignment: .trailing)
                    }
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Opens the terms talk")
                .accessibilityIdentifier(talkIdentifier)
                Button { Haptics.tap(); onTap() } label: {
                    LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
                        .rotationEffect(.degrees(open ? -90 : 90))
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(open ? "Hide the CV" : "Show the CV and the trial week")
            }
            if open { details(a) }
        }
        .padding(.vertical, Theme.Space.xs)
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
                Button { Haptics.tap(); onTrial() } label: { Text("Pay for a trial week \u{00B7} \(currency.tidyShort(Self.trialCost(a)))") }
                    .buttonStyle(TertiaryButtonStyle(size: .compact)).padding(.leading, -Theme.Space.s)
            }
        }
        .padding(.leading, ThinPersonRow.portrait + Theme.Space.m)
        .padding(.bottom, Theme.Space.s)
    }
}

@MainActor
enum ApplicantTrial {
    static func ask(_ store: GameStore, _ a: Applicant, companyID: Int, _ cur: Currency) -> PendingAction {
        let cost: Double = ApplicantRow.trialCost(a)
        let pid = a.personID
        return PendingAction(
            title: "Pay for a trial week with \(a.name)?",
            message: "Cost: \(cur.tidyShort(cost)) paid now, whatever you decide. Benefit: you see how their work really goes. Risk: one week shows only part of the picture, and they may take another job. It does not hire them.",
            button: "Pay \(cur.tidyShort(cost))", amount: cost, currency: cur, tone: .info, icon: "calendar") {
                if let seen = store.act({ $0.startTrialWeek(personID: pid, companyID: companyID) }) ?? nil {
                    Haptics.success(); store.show(seen.first?.text ?? "The trial week is done.", tone: "n")
                } else {
                    Haptics.warning(); store.show("Could not arrange a trial week: it was done already, or the company needs \(cur.tidyShort(cost)) in cash.", tone: "warn")
                }
            }
    }
}
