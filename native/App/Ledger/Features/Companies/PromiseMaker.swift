import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// Adds one promise to a draft: what, in how many weeks, and for the kinds that need it what exactly (a benefit, a working percentage).
/// Used by the hiring terms page and by the contract discussion; the engine records and checks the promise (`StaffPromises`).
struct PromiseMaker: View {
    struct Choice: Identifiable { var id: String; var title: String }
    var kinds: [StaffPromises.Kind]
    /// What fulfils each kind, in words, by the kind's raw value.
    var details: [String: String]
    var benefits: [Choice]
    var percents: [Double]
    /// The working percentage now (a promised change must differ from it).
    var current: Double
    var label = "Add a promise"
    var add: (StaffPromises.Draft) -> Void
    @State private var kind: StaffPromises.Kind = .salaryReview
    @State private var weeks = 13
    @State private var detail = ""
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(open ? "Close" : label) { open.toggle(); if let k = kinds.first, !kinds.contains(kind) { kind = k } }
                .buttonStyle(QuietButtonStyle(tint: Theme.gold)).accessibilityIdentifier("hire-add-promise")
            if open { maker }
        }
    }

    private var maker: some View {
        VStack(alignment: .leading, spacing: 8) {
            WrapRow {
                ForEach(kinds, id: \.self) { k in
                    Button(k.title) { kind = k; detail = "" }.buttonStyle(QuietButtonStyle(tint: kind == k ? Theme.gold : Theme.ivoryMuted))
                }
            }
            Text(details[kind.rawValue] ?? "").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            detailChoices
            Text("Due in").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            WrapRow {
                ForEach([4, 8, 13, 26, 52], id: \.self) { w in
                    Button(HireWords.weeksText(w)) { weeks = w }.buttonStyle(QuietButtonStyle(tint: weeks == w ? Theme.gold : Theme.ivoryMuted))
                }
            }
            let draft = StaffPromises.Draft(kind, dueInWeeks: weeks, detail: detail)
            QuietButton(title: "Promise \(kind.title.lowercased())") { add(draft); open = false; detail = "" }
                .opacity(draft.isPlausible ? 1 : 0.4).disabled(!draft.isPlausible)
                .accessibilityIdentifier("promise-confirm")
        }
    }

    @ViewBuilder private var detailChoices: some View {
        if kind == .futureBenefits {
            WrapRow {
                ForEach(benefits) { c in
                    Button(c.title) { detail = c.id }.buttonStyle(QuietButtonStyle(tint: detail == c.id ? Theme.gold : Theme.ivoryMuted))
                }
            }
        } else if kind == .percentageChange {
            WrapRow {
                ForEach(percents.filter { abs($0 - current) > 0.5 }, id: \.self) { p in
                    Button("\(Int(p)) percent") { detail = String(Int(p)) }.buttonStyle(QuietButtonStyle(tint: detail == String(Int(p)) ? Theme.gold : Theme.ivoryMuted))
                }
            }
        }
    }
}

extension PromiseMaker {
    /// The hiring terms page: kinds, wording, benefits and percentages come from the engine's draft options.
    init(options: HireDraftOptions, current: Double, add: @escaping (StaffPromises.Draft) -> Void) {
        let plans: [Choice] = options.bonusPlans.map { Choice(id: "plan:" + $0.id, title: $0.title) }
        let exps: [Choice] = options.expenses.map { Choice(id: "exp:" + $0.id, title: $0.title) }
        let perks: [Choice] = StaffPerks.all.map { Choice(id: "perk:" + $0.id, title: $0.name) }
        var words: [String: String] = [:]
        for k in options.promiseKinds { words[k.id] = k.detail }
        self.init(kinds: options.promiseKinds.compactMap { StaffPromises.Kind(rawValue: $0.id) }, details: words, benefits: plans + exps + perks,
                  percents: options.percents, current: current, add: add)
    }
}
