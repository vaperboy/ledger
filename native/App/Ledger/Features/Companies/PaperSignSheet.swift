import SwiftUI
import GameCore
import Businesses
import Simulation

/// A paper application the player fills in and signs before it is sent (owner decision, 2 Nov): who it goes to, what it says, the fee and the wait,
/// a box to confirm the terms and a signature drawn with a finger. Used for chain and franchise applications; `DocumentSignSheet` does the same
/// for the documents and licences a company holds.
struct PaperSignSheet: View {
    var title: String
    var to: String
    var note: String
    var fee: String
    var wait: String
    var button: String
    var onSend: () -> Void
    var onClose: () -> Void
    @State private var agreed = false
    @State private var strokes: [[CGPoint]] = []

    var body: some View {
        GamePopup(title: title, showsClose: true, dismissOnBackdrop: false, onClose: onClose) {
            VStack(alignment: .leading, spacing: 12) {
                Text("To: " + to).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                if !note.isEmpty { Text(note).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true) }
                line("Fee", fee)
                line("Answer expected", wait)
                Button { Haptics.choose(); agreed.toggle() } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: agreed ? "checkmark.square.fill" : "square").foregroundStyle(agreed ? Theme.gold : Theme.ivoryFaint).font(.system(size: 20))
                        Text("I confirm that the details are true and I accept the terms of this application.").font(.system(size: 13)).foregroundStyle(Theme.ivory)
                            .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    }
                }.buttonStyle(PressableStyle())
                SignaturePad(strokes: $strokes)
                HStack {
                    Button("Clear") { strokes = [] }.buttonStyle(QuietButtonStyle()).disabled(strokes.isEmpty)
                    Spacer(minLength: 8)
                    Button(button) { onClose(); onSend() }.buttonStyle(ImportantButtonStyle()).disabled(!agreed || strokes.isEmpty)
                }
            }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory)
        }
    }
}
