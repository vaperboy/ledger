import SwiftUI
import GameCore
import Businesses
import Simulation

/// The one signing popup (chain, franchise, trademark and licence applications): who it goes to, what it says, the fee and the wait, a box to
/// confirm the terms and a signature drawn with a finger. Clear and Send are pinned under the body, so they never scroll away; Send is on
/// only when the box is ticked and a signature is drawn. A tap outside does not close it.
struct SignPopup: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var to: String
    var note: String
    var fee: String
    var wait: String
    var button: String
    /// A line under the signature box (what happens after sending); empty for none.
    var caption: String = ""
    /// True: the popup closes, then `onSend` runs. False: `onSend` closes it itself.
    var closesFirst: Bool = true
    var onSend: () -> Void
    var onClose: () -> Void
    @State private var agreed = false
    @State private var strokes: [[CGPoint]] = []

    var body: some View {
        VStack(alignment: .leading, spacing: PopupSpace.block) {
            Text("To: " + to).popupText(.subtitle)
            if !note.isEmpty { Text(note).popupText(.body) }
            PopupSection {
                PopupRow(label: "Fee", value: fee)
                PopupRow(label: "Answer expected", value: wait)
            }
            Button { Haptics.choose(); agreed.toggle() } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square").foregroundStyle(agreed ? P.accent : P.inkFaint).font(.system(size: 20)).accessibilityHidden(true)
                    Text("I confirm that the details are true and I accept the terms of this application.").popupText(.body).multilineTextAlignment(.leading)
                }
            }.buttonStyle(PressableStyle()).accessibilityValue(agreed ? "Checked" : "Unchecked")
            SignaturePad(strokes: $strokes)
            if !caption.isEmpty { Text(caption).popupText(.caption) }
        }
        .centerSheetTitle(title)
        .centerSheetLocked()
        .popupFooter {
            PopupFooter(cancel: "Clear", action: button, onCancel: { strokes = [] }, onAction: { send() },
                        cancelEnabled: !strokes.isEmpty, actionEnabled: agreed && !strokes.isEmpty)
        }
    }

    private func send() {
        if closesFirst { onClose(); onSend() } else { onSend() }
    }
}
