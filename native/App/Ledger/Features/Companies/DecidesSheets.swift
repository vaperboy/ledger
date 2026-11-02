import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// The four rows of "Who decides what" (Runs it, Payroll, Hiring, Spending) each open one popup with the real choices, so nothing sends the owner
/// to the company screen to find them.
enum DecideKind: String, Hashable {
    case runs = "Who runs it", payroll = "Payroll", hiring = "Hiring", spending = "Spending"
}

/// Which popup a row opens. A wrapper with an id, so the sheet can be driven by `.centerSheet(item:)`.
struct DecideRef: Identifiable, Hashable {
    var companyID: Int
    var kind: DecideKind
    var id: String { "\(companyID):\(kind.rawValue)" }
}

/// One popup (medium and large detents) for one row and one company. Every choice calls the engine's own action.
struct DecidesSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var kind: DecideKind
    @State private var showManager = false
    @State private var managerCands: [Int] = []

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID) {
                content(e, co)
            } else {
                Text("This company no longer exists.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
            }
        }
        .centerSheet(isPresented: $showManager) { ManagerSheet(companyID: companyID, candidates: $managerCands).environmentObject(store) }
    }

    private func content(_ e: GameEngine, _ co: Company) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.rawValue).font(.serifTitle(22)).foregroundStyle(Theme.ivory)
                    Text(co.name).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                }
                choices(kind, e, co)
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, 18).padding(.bottom, 20)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        .ledgerBackground()
    }

    @ViewBuilder private func choices(_ k: DecideKind, _ e: GameEngine, _ co: Company) -> some View {
        switch k {
        case .runs: runs(e, co)
        case .payroll: payroll(e, co)
        case .hiring: levels(e, co, hiring: true)
        case .spending: levels(e, co, hiring: false)
        }
    }

    private func note(_ text: String, tint: Color = Theme.ivoryMuted) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(tint).fixedSize(horizontal: false, vertical: true)
    }

    private func hasManager(_ co: Company) -> Bool { co.managerID != nil }

    private func managerName(_ e: GameEngine, _ co: Company) -> String {
        co.managerID.flatMap { (id: Int) -> String? in e.state.people[id]?.name } ?? "The manager"
    }

    // MARK: Runs it

    @ViewBuilder private func runs(_ e: GameEngine, _ co: Company) -> some View {
        if hasManager(co) {
            note("\(managerName(e, co)) runs it day to day.")
            QuietButton(title: "Open the manager", fullWidth: true) { showManager = true }
        } else {
            note(OwnerHours.works(co) ? "You run it yourself." : "No one runs it: you do not work here and there is no manager.",
                 tint: OwnerHours.works(co) ? Theme.ivoryMuted : Theme.caution)
            QuietButton(title: "Appoint a manager", fullWidth: true) { showManager = true }.accessibilityIdentifier("decide-appoint-manager")
            if co.type != "hold" { worksToggle(co) }
        }
    }

    private func worksToggle(_ co: Company) -> some View {
        let works: Bool = OwnerHours.works(co)
        let cid: Int = co.id
        return QuietButton(title: works ? "Stop working here" : "Work here myself", fullWidth: true) {
            Haptics.tap()
            _ = store.settle(store.act { $0.setWorksHere(companyID: cid, works: !works) }, works ? "You no longer work here." : "You work here again.")
        }
    }

    // MARK: Payroll

    @ViewBuilder private func payroll(_ e: GameEngine, _ co: Company) -> some View {
        if let o = e.payrollOverview(companyID: companyID) {
            if let r = o.responsibility {
                let who: String = r.who == .owner ? "You run payroll" : r.who == .manager ? "\(r.name), the manager, runs payroll" : "\(r.name), the accountant, runs payroll"
                note(who + ".", tint: r.who == .owner ? Theme.caution : Theme.ivory)
                if !r.reason.isEmpty { note(r.reason) }
            }
            if o.autoApproves { note("Your standing rule approves routine payroll the company can pay.") }
            if !o.nextPayText.isEmpty { note("Next pay day: " + o.nextPayText) }
            payrollActions(e, o)
        } else {
            note("This company has no payroll.")
        }
    }

    @ViewBuilder private func payrollActions(_ e: GameEngine, _ o: PayrollOverview) -> some View {
        let cid: Int = companyID
        if o.needsApproval && !o.isApproved {
            QuietButton(title: "Approve this payroll", fullWidth: true) {
                let r: PayrollApprovalResult? = store.act { $0.approvePayroll(companyID: cid) }
                if case .notNeeded(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") } else { Haptics.success(); store.show("Payroll approved.", tone: "good") }
            }
        }
        QuietButton(title: "Open payroll in Accounting", fullWidth: true) { dismiss(); store.openAccounting(companyID: cid, payroll: true) }
        if o.responsibility?.who == .owner {
            note("Appoint a manager, or hire an accountant, and payroll runs without you.", tint: Theme.ivoryFaint)
            QuietButton(title: "Appoint a manager", fullWidth: true) { showManager = true }
        }
    }

    // MARK: Hiring and spending

    @ViewBuilder private func levels(_ e: GameEngine, _ co: Company, hiring: Bool) -> some View {
        if hasManager(co) {
            let auth = co.value("auth")
            let lvl: Int = Int(auth["lvl"].double)
            let name: String = managerName(e, co)
            let cid: Int = co.id
            note(hiring ? "Who decides on hiring and replacing people." : "How much \(name) may spend before asking you.")
            AuthorityLevelPicker(level: lvl) { (v: Int) -> Void in
                _ = store.settle(store.act { $0.setManagerAuthority(companyID: cid, level: v) }, "\(name) now \(GameEngine.authorityText(level: v)).", same: "\(name) already works that way.")
            }
            if lvl == 1 { limits(e, co, auth, hiring: hiring) }
        } else {
            note(hiring ? "You decide on every hire: there is no manager." : "You decide on every spend: there is no manager.", tint: Theme.caution)
            QuietButton(title: "Appoint a manager", fullWidth: true) { showManager = true }
        }
    }

    @ViewBuilder private func limits(_ e: GameEngine, _ co: Company, _ auth: JSONValue, hiring: Bool) -> some View {
        let cur: Currency = e.currency(for: co)
        let cid: Int = co.id
        limitRow(hiring ? "Pay and promotions a month" : "Pay and promotions a month", auth["hire"].double, [0, 3000, 8000, 15000, 30000], cur) { (v: Double) -> Void in
            _ = store.settle(store.act { $0.setManagerAuthority(companyID: cid, pay: v) }, "Pay and promotions limit: \(cur.tidyShort(v)) a month.")
        }
        limitRow("Purchases and hires up to", auth["buy"].double, [10000, 25000, 50000, 100000, 250000], cur) { (v: Double) -> Void in
            _ = store.settle(store.act { $0.setManagerAuthority(companyID: cid, buy: v) }, "Purchases and hires limit: \(cur.tidyShort(v)).")
        }
        if !hiring {
            limitRow("Advertising a week", auth["ad"].double, [0, 1500, 3000, 7000], cur) { (v: Double) -> Void in
                _ = store.settle(store.act { $0.setManagerAuthority(companyID: cid, ad: v) }, "Advertising limit: \(cur.tidyShort(v)) a week.")
            }
        }
    }

    private func limitRow(_ label: String, _ value: Double, _ options: [Double], _ cur: Currency, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { (o: Double) -> AnyView in
                    AnyView(Button(o == 0 ? "None" : cur.tidyShort(cur.scaledPrice(o))) { set(cur.scaledPrice(o)) })
                }
            } label: {
                Text((value == 0 ? "None" : cur.tidyShort(value)) + "  ⌄").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.gold)
            }
        }
        .padding(.vertical, 4)
    }
}
