import Countries
import SwiftUI
import GameCore
import Finance
import Businesses
import Simulation

struct HoldButton: View {
    var title: String
    var seconds: Double
    var tint: Color
    var identifier: String
    var onDone: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var timer: Task<Void, Never>?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        Text(holding ? "Keep holding\u{2026}" : title)
            .textStyle(.body, tint: tint, weight: .medium)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(alignment: .leading) {
                GeometryReader { (g: GeometryProxy) in
                    tint.opacity(0.22).frame(width: g.size.width * progress)
                }
            }
            .background(shape.fill(tint.opacity(0.08)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(tint.opacity(0.5), lineWidth: 1))
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { (_: DragGesture.Value) in begin() }
                .onEnded { (_: DragGesture.Value) in cancel() })
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title + ", hold for \(Int(seconds)) seconds")
            .accessibilityIdentifier(identifier)
    }

    private func begin() {
        guard !holding else { return }
        holding = true
        Haptics.tap()
        withAnimation(.linear(duration: seconds)) { progress = 1 }
        timer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            holding = false
            progress = 0
            Haptics.warning()
            onDone()
        }
    }

    private func cancel() {
        timer?.cancel()
        timer = nil
        holding = false
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}

struct CompanyCloseButton: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: PendingAction?

    var body: some View {
        if company.status.isLive && !engine.isBranch(companyID: company.id) {
            HoldButton(title: "Close company", seconds: 3, tint: Theme.loss, identifier: "company-close") { ask() }
                .confirmAction($pending)
        }
    }

    private func ask() {
        let name: String = company.name
        let id: Int = company.id
        let staff: Int = company.staff.count
        let cur: Currency = engine.currency(for: company)
        let terms: GameEngine.WindUpTerms? = engine.windUpTerms(companyID: id)
        if let why = terms?.refusal {
            pending = PendingAction(title: "It cannot be closed", message: why, button: "File for bankruptcy", destructive: true, alwaysAsk: true, tone: .danger, icon: "exclamationmark.triangle") {
                if store.act({ $0.fileForBankruptcy(companyID: id) }) == true {
                    Haptics.warning()
                    store.show("\(name) is bankrupt.", tone: "warn")
                }
            }
            return
        }
        let back: Double = terms?.toOwner ?? 0
        let fromAccount: Double = terms?.fromAccount ?? 0
        let debts: String = fromAccount > 0 ? " Its debts take \(cur.tidyDisplay(fromAccount)) from your account." : ""
        pending = PendingAction(title: "Are you sure?", message: "Closing \(name) is permanent. \(staff) \(staff == 1 ? "person loses their job" : "people lose their jobs"), the assets are sold off and you receive about \(cur.tidyDisplay(back))." + debts,
                                button: "Close it for good", destructive: true, alwaysAsk: true, tone: .danger, icon: "xmark.octagon") {
            let alone: Bool = engine.boardVote(kind: "close", companyID: id).pushedThroughAlone
            if store.act({ $0.windUpCompany(companyID: id) }) == true {
                if alone { store.act { $0.recordPushedThrough(companyID: id) } }
                Haptics.warning()
                store.show("\(name) is closed down, its things sold and its debts paid." + (alone ? " The other owners did not want this." : ""), tone: "n")
            } else {
                Haptics.warning()
                store.show("\(name) could not be closed.", tone: "warn")
            }
        }
    }
}
