import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

struct PromiseMaker: View {
    struct Choice: Identifiable { var id: String; var title: String }
    var kinds: [StaffPromises.Kind]
    var details: [String: String]
    var benefits: [Choice]
    var percents: [Double]
    var current: Double
    var label = "Add a promise"
    var add: (StaffPromises.Draft) -> Void
    @State private var kind: StaffPromises.Kind = .salaryReview
    @State private var weeks = 13
    @State private var detail = ""
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button(open ? "Close" : label) { Haptics.tap(); open.toggle(); if let k = kinds.first, !kinds.contains(kind) { kind = k } }
                .buttonStyle(SecondaryButtonStyle(size: .compact, tint: Theme.accent)).accessibilityIdentifier("hire-add-promise")
            if open { maker }
        }
    }

    private var maker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            WrapRow(spacing: Theme.Space.xs) {
                ForEach(kinds, id: \.self) { k in
                    HireChip(title: k.title, on: kind == k) { Haptics.choose(); kind = k; detail = "" }
                }
            }
            Text((details[kind.rawValue] ?? "").tidyText).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            detailChoices
            Text("Due in").textStyle(.label)
            WrapRow(spacing: Theme.Space.xs) {
                ForEach([4, 8, 13, 26, 52], id: \.self) { w in
                    HireChip(title: HireWords.weeksText(w), on: weeks == w) { Haptics.choose(); weeks = w }
                }
            }
            let draft = StaffPromises.Draft(kind, dueInWeeks: weeks, detail: detail)
            Button("Promise \(kind.title.lowercased())") { Haptics.tap(); add(draft); open = false; detail = "" }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.accent))
                .disabled(!draft.isPlausible)
                .accessibilityIdentifier("promise-confirm")
            if !draft.isPlausible { Text("Choose what exactly is promised first.").textStyle(.caption) }
        }
    }

    @ViewBuilder private var detailChoices: some View {
        if kind == .futureBenefits {
            WrapRow(spacing: Theme.Space.xs) {
                ForEach(benefits) { c in
                    HireChip(title: c.title, on: detail == c.id) { Haptics.choose(); detail = c.id }
                }
            }
        } else if kind == .percentageChange {
            WrapRow(spacing: Theme.Space.xs) {
                ForEach(percents.filter { abs($0 - current) > 0.5 }, id: \.self) { p in
                    HireChip(title: "\(Int(p)) percent", on: detail == String(Int(p))) { Haptics.choose(); detail = String(Int(p)) }
                }
            }
        }
    }
}

extension PromiseMaker {
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
