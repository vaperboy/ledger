import SwiftUI
import GameCore
import Businesses
import Simulation

struct SignPopup: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var to: String
    var note: String
    var fee: String
    var wait: String
    var button: String
    var caption: String = ""
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
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square").foregroundStyle(agreed ? P.accent : P.inkFaint).font(.system(size: Theme.Icon.medium)).accessibilityHidden(true)
                    Text("I confirm that the details are true and I accept the terms of this application.").popupText(.body).multilineTextAlignment(.leading)
                }
                .frame(minHeight: 44, alignment: .topLeading).contentShape(Rectangle())
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
