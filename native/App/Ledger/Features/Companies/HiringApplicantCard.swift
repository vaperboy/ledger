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
        if f > 0.66 { return ("Relaxed", Theme.ivory) }
        if f > 0.34 { return ("Getting impatient", Theme.caution) }
        return ("Close to walking away", Theme.loss)
    }
}

/// One applicant: portrait, name, age / role / experience, the market pay for the role, how the CV reads and the first impression. The selected card
/// opens to the CV line and the actions. Only what the player can see before an interview is shown, in words: never a skill figure, never their ask
/// (they name it in the salary talk).
struct HiringApplicantCard: View {
    var applicant: Applicant
    var roleName: String
    var currency: Currency
    var companyID: Int
    var open: Bool
    var trialCost: Double
    var onTap: () -> Void
    var onTrial: () -> Void
    var onTalk: () -> Void

    private var experienceLine: String {
        guard let y = applicant.claimedExperienceYears else { return "no experience given" }
        let n = Int(y.rounded())
        return "\(n) \(n == 1 ? "year" : "years")"
    }

    var body: some View {
        let a = applicant
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onTap) { summary(a) }.buttonStyle(PressableStyle())
            if open { details(a) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(open ? Theme.gold : Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func summary(_ a: Applicant) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ThumbnailView(kind: .person, key: applicant.role, size: 40, initials: a.name, face: a.faceKey)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text("\(a.age) \u{00B7} \(roleName) \u{00B7} \(experienceLine)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(currency.tidyShort(a.marketYearly)).font(.system(size: 15, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Text("market pay a year").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                fact("CV", a.cvImpression)
                fact("Seems", a.seems)
            }
        }
        .contentShape(Rectangle())
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            Text(value).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func details(_ a: Applicant) -> some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
        VStack(alignment: .leading, spacing: 6) {
            if !a.resume.isEmpty { Text("\u{201C}\(a.resume)\u{201D}").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
            Text(a.referencesChecked ? "References checked." : "References not checked.").font(.system(size: 12)).foregroundStyle(Theme.ivoryDim)
            ForEach(a.trialObservations, id: \.self) { line in
                Text(line).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        HStack(spacing: 8) {
            if a.trialObservations.isEmpty {
                Button(action: onTrial) { actionLabel("Trial week \u{00B7} \(currency.tidyShort(trialCost))", strong: false) }.buttonStyle(PressableStyle())
            }
            Button { Haptics.tap(); onTalk() } label: { actionLabel("Talk terms \u{203A}", strong: true) }
                .buttonStyle(PressableStyle()).accessibilityIdentifier("hire-talk-terms")
        }
    }

    private func actionLabel(_ title: String, strong: Bool) -> some View {
        Text(title).font(.system(size: 13.5, weight: strong ? .medium : .regular)).foregroundStyle(Theme.ivory)
            .frame(maxWidth: .infinity, minHeight: 28).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(strong ? Theme.gold : Theme.borderStrong, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
