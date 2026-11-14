import SwiftUI
import Simulation
import SaveSystem

struct SaveSlotsView: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @State private var rows: [SlotRow] = []
    @State private var renaming: String? = nil
    @State private var renameText = ""
    @State private var pending: PendingAction? = nil
    @State private var backedUp: Date? = CloudBackup.lastBackup

    struct SlotRow: Identifiable, Equatable {
        var id: String
        var summary: SaveSummary?
    }

    private var limit: Int { ent.effective.saveSlots(now: Date()) + SeasonModel.shared.pass.bonusSaveSlots }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(rows.count) of \(limit) slots used").textStyle(.body, tint: Theme.inkSoft)
                Spacer(minLength: 8)
                ProMark(feature: .saveSlots)
            }
            ForEach(rows) { (r: SlotRow) in slotCard(r) }
            newSlot
            if CloudConfig.iCloudReady { cloud }
        }
        .onAppear { reload() }
        .confirmAction($pending)
    }

    private func reload() {
        let all: [SlotRow] = store.slotList().map { SlotRow(id: $0.slot, summary: $0.summary) }
        rows = all.sorted { (a: SlotRow, b: SlotRow) -> Bool in
            if a.id == "current" { return true }
            if b.id == "current" { return false }
            return a.id < b.id
        }
    }

    private func detail(_ r: SlotRow) -> String {
        guard let s = r.summary else { return "Unreadable" }
        let co: String = s.companies == 1 ? "1 company" : "\(s.companies) companies"
        return "\(s.playerName) \u{00B7} week \(s.week) \u{00B7} \(co) \u{00B7} " + s.savedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func slotCard(_ r: SlotRow) -> some View {
        let isCurrent: Bool = r.id == "current"
        return Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isCurrent ? "This career" : r.id).textStyle(.headline)
                Text(detail(r)).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                if renaming == r.id {
                    renameEditor(r)
                } else if !isCurrent {
                    HStack(spacing: 8) {
                        Button("Continue") { askSwitch(r) }.buttonStyle(TinyButtonStyle()).disabled(r.summary == nil)
                        Button("Rename") { renaming = r.id; renameText = r.id }.buttonStyle(TinyButtonStyle())
                        Button("Delete") { askDelete(r) }.buttonStyle(TinyButtonStyle(tint: Theme.loss))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func renameEditor(_ r: SlotRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Slot name", text: $renameText).textFieldStyle(.plain).textStyle(.headline)
            HStack(spacing: 8) {
                Button("Rename") {
                    if store.renameSlot(r.id, to: renameText) { renaming = nil; reload() } else { store.show("That name is empty or already used.", tone: "warn") }
                }.buttonStyle(TinyButtonStyle())
                Button("Cancel") { renaming = nil }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
            }
        }
    }

    private var newSlot: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New career").textStyle(.headline)
                Text("This career is kept in its own slot and goes on from where you leave it.").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Start a new career") { ent.run(.saveSlots, "More save slots") { askNewCareer() } }
                        .buttonStyle(TinyButtonStyle()).disabled(store.engine == nil)
                    ProMark(feature: .saveSlots)
                    Spacer(minLength: 4)
                    InfoSheetButton(title: "Careers", text: "Each slot is its own career. A career always goes on from its latest day: there is no going back to an earlier save.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func askNewCareer() {
        guard rows.count < limit else { store.show("All \(limit) slots are used. Delete one first.", tone: "warn"); return }
        pending = PendingAction(title: "Start a new career?", message: "This career moves to its own slot and waits there.", button: "Start a new career", alwaysAsk: true) {
            if !store.parkForNewCareer() { store.show("This career could not be put aside.", tone: "warn") }
        }
    }

    private func askSwitch(_ r: SlotRow) {
        pending = PendingAction(title: "Continue \(r.id)?", message: "This career moves to its own slot and waits there.", button: "Continue \(r.id)", alwaysAsk: true) {
            store.switchCareer(to: r.id); reload()
        }
    }

    private func askDelete(_ r: SlotRow) {
        pending = PendingAction(title: "Delete \(r.id)?", message: "The slot is removed from this device.", button: "Delete \(r.id)", destructive: true) {
            store.deleteSlot(r.id); reload()
        }
    }

    private var cloudLine: String {
        if !CloudConfig.iCloudReady { return "Needs iCloud set-up" }
        return backedUp.map { "Last backup " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "No backup yet"
    }

    private var cloud: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Cloud backup").textStyle(.headline)
                    ProMark(feature: .cloudBackup)
                }
                Text(cloudLine).textStyle(.caption)
                HStack(spacing: 8) {
                    Button("Back up now") { ent.run(.cloudBackup, "Cloud backup") { backUp() } }
                        .buttonStyle(TinyButtonStyle()).disabled(!CloudConfig.iCloudReady || store.engine == nil)
                    Button("Restore") { ent.run(.cloudBackup, "Cloud backup") { askRestore() } }
                        .buttonStyle(TinyButtonStyle()).disabled(!CloudConfig.iCloudReady)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func backUp() {
        guard let text = store.backupText() else { return }
        if let problem = CloudBackup.back(up: text) { store.show(problem + ".", tone: "warn") }
        else { backedUp = CloudBackup.lastBackup; store.show("Backed up.", tone: "good") }
    }

    private func askRestore() {
        guard let text = CloudBackup.restoreText() else { store.show("No backup found.", tone: "warn"); return }
        pending = PendingAction(title: "Restore the backup?", message: "For a new phone: the backup opens only if it is newer than what this phone has.", button: "Restore backup", alwaysAsk: true) {
            if let problem = store.restoreBackup(text: text) { store.show(problem, tone: "warn") } else { store.show("Backup restored.", tone: "good") }
            reload()
        }
    }
}
