import SwiftUI
import GameCore
import Simulation

extension GameStore {
    var groupReviewReady: ReviewOffer? {
        guard !isAdvancing, !popupOpen, unlockQueue.isEmpty else { return nil }
        return engine?.reviewOffer
    }

    func deferGroupReview() { act { (e: inout GameEngine) -> Bool in e.deferReview(); return true } }

    func setGroupReview(_ kinds: [TargetKind]) {
        let r: ReviewChoice? = act { (e: inout GameEngine) -> ReviewChoice? in e.setReviewTargets(kinds) } ?? nil
        guard let r else { return }
        Haptics.success()
        outcome(chosen: r.chosen, result: r.result)
    }

    func skipGroupReview() {
        let next: String = engine?.reviewOffer?.nextLabel ?? "the next quarter"
        act { (e: inout GameEngine) -> Bool in e.skipReview(); return true }
        outcome(chosen: "No targets this quarter", result: "Nothing is graded. The next review comes when \(next) closes.")
    }
}

extension View {
    func groupReviewPopup(_ store: GameStore) -> some View {
        let offer: ReviewOffer? = store.groupReviewReady
        return hostedPopup(key: "review-" + (offer?.label ?? ""), priority: .report, active: offer != nil, onClose: { store.deferGroupReview() }) {
            if let o = store.groupReviewReady { GroupReviewPopup(offer: o).environmentObject(store) }
        }
    }
}

struct ReviewMove: View {
    var now: Double
    var before: Double?
    var lowerIsBetter = false

    var body: some View {
        if let b = before, let share = ReportMath.share(now, b), abs(share) >= 0.005 {
            let up: Bool = share > 0
            let good: Bool = lowerIsBetter ? !up : up
            HStack(spacing: Theme.Space.xs) {
                StockArrow(up: up, good: good)
                Text(String(format: "%.0f%%", abs(share) * 100)).popupText(.rowValue)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((up ? "up " : "down ") + String(format: "%.0f percent", abs(share) * 100))
        } else if before != nil {
            Text("level").popupText(.caption)
        }
    }
}

struct GroupReviewPopup: View {
    @EnvironmentObject var store: GameStore
    var offer: ReviewOffer
    @State private var picked: [TargetKind] = []

    private var f: QuarterFigures { offer.figures }
    private var p: QuarterFigures? { offer.previous }

    var body: some View {
        GamePopup(title: "Quarterly review", showsClose: true, category: .detail, tone: .info, onClose: { store.deferGroupReview() }) {
            PopupBody {
                Text(offer.label).popupText(.subtitle)
                quarter
                if let g = offer.graded { lastTargets(g) }
                choose
                PopupOptionButton(title: picked.count == 1 ? "Set this target" : "Set these targets", highlighted: !picked.isEmpty, identifier: "review-set") {
                    if !picked.isEmpty { store.setGroupReview(picked) }
                }
                PopupOptionButton(title: "Not now", identifier: "review-later") { store.deferGroupReview() }
                PopupOptionButton(title: "Skip this quarter", identifier: "review-skip") { store.skipGroupReview() }
            }
        }
    }

    private func row(_ label: String, value: String, move: ReviewMove? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).popupText(.rowLabel)
            Spacer(minLength: PopupSpace.row)
            if let move { move }
            Text(value).popupText(.rowValue)
        }
    }

    private var quarter: some View {
        VStack(alignment: .leading, spacing: PopupSpace.row) {
            row("Sales", value: store.short(f.sales), move: ReviewMove(now: f.sales, before: p?.sales))
            row("Profit after tax", value: store.short(f.profit), move: ReviewMove(now: f.profit, before: p?.profit))
            if let share = f.costShare {
                row("Costs against sales", value: String(format: "%.0f%%", share * 100), move: ReviewMove(now: share, before: p?.costShare, lowerIsBetter: true))
            }
            row("Cash in the group", value: store.short(f.cashEnd), move: ReviewMove(now: f.cashEnd, before: p?.cashEnd))
            row("People on the payroll", value: "\(f.staff)", move: ReviewMove(now: Double(f.staff), before: p.map { Double($0.staff) }))
            HStack(alignment: .firstTextBaseline) {
                Text("What customers think of you").popupText(.rowLabel)
                Spacer(minLength: PopupSpace.row)
                opinion
            }
            if f.companies >= 2, !f.bestName.isEmpty {
                row("Best company", value: f.bestName)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(Theme.surface))
    }

    @ViewBuilder private var opinion: some View {
        switch f.opinionMove {
        case 1: HStack(spacing: Theme.Space.xs) { StockArrow(up: true, good: true); Text("Improving").popupText(.rowValue) }
        case -1: HStack(spacing: Theme.Space.xs) { StockArrow(up: false, good: false); Text("Slipping").popupText(.rowValue) }
        default: Text("Steady").popupText(.rowValue)
        }
    }

    private func lastTargets(_ g: QuarterRecord) -> some View {
        VStack(alignment: .leading, spacing: PopupSpace.row) {
            Text("Your targets for \(g.label)").popupText(.title)
            ForEach(g.targets) { (t: ReviewTarget) in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).popupText(.body)
                        Text(t.resultText).popupText(.caption)
                    }
                    Spacer(minLength: PopupSpace.row)
                    GradeWord(grade: t.grade)
                }
            }
            if let grade = g.grade {
                HStack { Text("The quarter").popupText(.rowLabel); Spacer(); GradeWord(grade: grade) }
                Text(g.note).popupText(.caption)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(Theme.surface))
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: PopupSpace.row) {
            Text("Targets for \(offer.nextLabel)").popupText(.title)
            Text("Pick one or two. They are graded when the quarter closes.").popupText(.caption)
            ForEach(offer.options) { (t: ReviewTarget) in
                Button { toggle(t.kind) } label: { option(t) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("review-target-" + t.kind.rawValue)
            }
        }
    }

    private func option(_ t: ReviewTarget) -> some View {
        let on: Bool = picked.contains(t.kind)
        return HStack(alignment: .top, spacing: PopupSpace.block) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? Theme.accent : Theme.inkFaint)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).popupText(.body)
                Text(t.goalText + ". " + t.stretchText + ".").popupText(.caption).fixedSize(horizontal: false, vertical: true)
                Text("Now: " + t.nowText).popupText(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(on ? Theme.accentWash : Theme.surface))
    }

    private func toggle(_ k: TargetKind) {
        Haptics.tap()
        if let i = picked.firstIndex(of: k) { picked.remove(at: i); return }
        picked.append(k)
        if picked.count > 2 { picked.removeFirst() }
    }
}
