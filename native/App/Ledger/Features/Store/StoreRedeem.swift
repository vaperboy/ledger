import SwiftUI
import Simulation

/// The one field for codes: beta keys and administrator codes, checked by the server. App Store offer codes open
/// Apple's own sheet from here too.
struct RedeemCodeCard: View {
    var onAppleCode: (() -> Void)?
    @Environment(OnlineSession.self) private var online
    private let session = StoreSession.shared
    @State private var code = ""
    @State private var working = false
    @State private var result: StoreSession.CodeResult?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Type a code you were given, such as a beta key.").textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            TextField("LEDGER-XXXX-XXXX-XXXX", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.system(.body, design: .monospaced).weight(.medium))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { redeem() }
                .padding(.horizontal, Theme.Space.m).frame(minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.inset))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? Theme.accent : Theme.line, lineWidth: 1))
                .accessibilityLabel("Code")
                .accessibilityIdentifier("redeem-code-field")
            if let line = message { Text(line.text).textStyle(.body, tint: line.good ? Theme.gain : Theme.loss, weight: .semibold).fixedSize(horizontal: false, vertical: true) }
            Button { redeem() } label: {
                HStack(spacing: Theme.Space.s) {
                    if working { ProgressView().tint(StoreColors.priceInk) }
                    StorePriceLabel(text: "Redeem")
                }
            }
            .buttonStyle(PressableStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
            .accessibilityIdentifier("redeem-code-submit")
            if let onAppleCode {
                Button { Haptics.tap(); onAppleCode() } label: {
                    Text("Redeem an App Store offer code").textStyle(.body, tint: Theme.accent, weight: .semibold).frame(minHeight: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("store-redeem-apple")
            }
        }
    }

    private var canSubmit: Bool { !working && code.filter { $0.isLetter || $0.isNumber }.count >= 12 }

    private var message: (text: String, good: Bool)? {
        switch result {
        case .some(.admin): return ("This account is now an administrator: unlimited gold, every cosmetic, the full pass and every feature open.", true)
        case .some(.alreadyAdmin): return ("This account is already an administrator. The code was not used.", true)
        case .some(.beta(let gold)): return ("Thank you for testing! \(StoreText.gold(gold)) added.", true)
        case .some(.betaUsed): return ("This account has already used a beta key. The code was not used.", false)
        case .some(.invalid): return ("That code is not valid or has been used.", false)
        case .some(.locked): return ("Too many tries. Wait an hour and try again.", false)
        case .some(.offline): return (session.problem ?? "Codes need a connection. Try again when you are online.", false)
        case .none: return nil
        }
    }

    private func redeem() {
        guard canSubmit else { return }
        focused = false
        working = true
        Task {
            let r: StoreSession.CodeResult = await session.redeemCode(code)
            working = false
            result = r
            switch r {
            case .admin, .beta:
                Haptics.success()
                code = ""
                await online.refreshStatus()
            default:
                Haptics.warning()
            }
        }
    }
}
