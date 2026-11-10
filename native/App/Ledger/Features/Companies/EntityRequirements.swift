import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct RequirementGuide: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var requirements: [Chains.Requirement]
    @State private var sheet: DocRef?
    @State private var pending: PendingAction?

    struct DocRef: Identifiable {
        var id: String
    }

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(requirements.enumerated()), id: \.element.id) { (n: Int, r: Chains.Requirement) in
                if n > 0 { CardLine() }
                row(r, cur)
            }
        }
        .confirmAction($pending)
        .centerSheet(item: $sheet) { (d: DocRef) in
            paper(d.id, cur)
        }
    }

    private func row(_ r: Chains.Requirement, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(r.title.tidyMoney).textStyle(.body, tint: Theme.ink, weight: .medium)
                Spacer(minLength: 8)
                statusChip(r.status)
            }
            if r.key == "proven" {
                provenLine(r)
            } else {
                Text(how(r)).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            action(r, cur)
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .contain)
    }

    private func statusChip(_ s: Chains.RequirementStatus) -> some View {
        switch s {
        case .done: return Chip(text: "Done", tint: Theme.gain)
        case .waiting: return Chip(text: "Waiting for review", tint: Theme.caution)
        case .missing: return Chip(text: "Missing", tint: Theme.loss)
        }
    }

    private func how(_ r: Chains.Requirement) -> String {
        r.ok ? "Nothing more to do." : r.detail.tidyMoney
    }

    private func provenLine(_ r: Chains.Requirement) -> some View {
        let p = Franchising.provenProgress(engine.state, company)
        let fraction: Double = 0.5 * min(1, Double(p.weeks) / 52) + 0.5 * Double(p.quarters) / 4
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ThinProgress(fraction: r.ok ? 1 : fraction, tint: r.ok ? Theme.gain : Theme.gold)
            Text(r.ok ? "The pilot has proved itself." : "A year of trading and four profitable quarters. Keep this company running well.")
                .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func action(_ r: Chains.Requirement, _ cur: Currency) -> some View {
        if r.status == .missing {
            switch r.key {
            case "trademark", "fran": paperAction(r, cur)
            case "ops_manual": manualAction(r, cur)
            case "support": hireAction()
            default: EmptyView()
            }
        }
    }

    private func fee(_ key: String, _ cur: Currency) -> String {
        cur.tidyShort(engine.documentFee(companyID: company.id, document: key))
    }

    private func blocked(_ r: Chains.Requirement) -> Bool {
        r.key == "fran" && requirements.contains(where: { (x: Chains.Requirement) -> Bool in x.key != "fran" && !x.ok })
    }

    @ViewBuilder private func paperAction(_ r: Chains.Requirement, _ cur: Currency) -> some View {
        let again: Bool = r.detail.hasPrefix("Refused")
        let label: String = (again ? "Apply again" : "Apply") + " \u{00B7} " + fee(r.key, cur)
        let key: String = r.key
        HStack(spacing: Theme.Space.s) {
            Button(label) { Haptics.tap(); sheet = DocRef(id: key) }
                .buttonStyle(TinyButtonStyle())
                .disabled(blocked(r))
            if blocked(r) {
                Text("After the steps above.").textStyle(.caption, tint: Theme.inkFaint)
            }
        }
    }

    private func manualAction(_ r: Chains.Requirement, _ cur: Currency) -> some View {
        let price: String = fee("ops_manual", cur)
        return Button("Write it \u{00B7} " + price) {
            Haptics.tap()
            pending = PendingAction(title: "Write the operations manual?", message: "\(company.name) writes it over a few weeks. It costs \(price) and needs no review.", button: "Write it") {
                send("ops_manual")
            }
        }
        .buttonStyle(TinyButtonStyle())
    }

    private func hireAction() -> some View {
        NavigationLink {
            HireWorkersView(companyID: company.id)
        } label: {
            Text("Hire someone")
        }
        .buttonStyle(SecondaryButtonStyle(size: .compact, tint: Theme.accent))
    }

    @ViewBuilder private func paper(_ key: String, _ cur: Currency) -> some View {
        let isMark: Bool = key == "trademark"
        SignPopup(title: isMark ? "Trademark registration" : "Franchise documents",
                       to: isMark ? "The intellectual property office" : "The franchise register",
                       note: isMark ? "Registers the brand name of \(company.name) as a trademark. It is reviewed and can be refused."
                                    : "A lawyer writes the franchise agreement and the disclosure document for \(company.name). They are reviewed before you can sell units.",
                       fee: fee(key, cur), wait: isMark ? "after a review of 4 to 8 weeks" : "after a review of some weeks", button: "Sign and send",
                       onSend: { send(key) }, onClose: { sheet = nil })
            .environment(\.outsidePalette, OutsidePalette.game).presentationBackground(.clear)
    }

    private func send(_ key: String) {
        let id: Int = company.id
        switch store.act({ $0.applyForChainDocument(companyID: id, document: key) }) {
        case .ok?: Haptics.success(); store.show(key == "ops_manual" ? "The manual is being written." : "Application sent.", tone: "good")
        case .notYet(let why)?: Haptics.warning(); store.show(why, tone: "warn")
        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company for the fee.", tone: "warn")
        default: Haptics.warning(); store.show("The application could not be sent.", tone: "warn")
        }
    }
}
