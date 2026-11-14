import SwiftUI
import Simulation

/// The one field for codes: gift codes, beta keys and administrator codes, checked by the server. App Store offer codes
/// open Apple's own sheet from here too.
struct RedeemCodeCard: View {
    var startCode: String = ""
    var onGift: (ServerGiftReward) -> Void = { (_: ServerGiftReward) in }
    var onAppleCode: (() -> Void)?
    @Environment(OnlineSession.self) private var online
    private let session = StoreSession.shared
    @State private var code = ""
    @State private var working = false
    @State private var result: StoreSession.CodeResult?
    @FocusState private var focused: Bool

    init(startCode: String = "", onGift: @escaping (ServerGiftReward) -> Void = { (_: ServerGiftReward) in }, onAppleCode: (() -> Void)? = nil) {
        self.startCode = startCode
        self.onGift = onGift
        self.onAppleCode = onAppleCode
        _code = State(initialValue: startCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Type or paste a code you were given, such as a gift code or a beta key.").textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.s) {
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
                PasteButton(payloadType: String.self) { (strings: [String]) in
                    if let pasted = strings.first { code = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("redeem-code-paste")
            }
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
        case .some(.gift): return ("Gift received.", true)
        case .some(.betaUsed): return ("This account has already used a beta key. The code was not used.", false)
        case .some(.giftUsed): return ("This account has already used this code.", false)
        case .some(.expired): return ("This code has expired.", false)
        case .some(.owned): return ("You already have everything in this code. The code was not used.", false)
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
            case .gift(let reward):
                Haptics.success()
                code = ""
                onGift(reward)
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

/// The row near the top of the Store that leads to the code field: tap to type a code, or paste one straight in.
struct RedeemGiftRow: View {
    /// Opens the code field, filled with a pasted code or empty.
    var open: (String) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Button { Haptics.tap(); open("") } label: {
                HStack(spacing: Theme.Space.m) {
                    RewardTile(kind: .box, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Redeem gift code").textStyle(.headline)
                        Text("Got a code? Enter it here.").textStyle(.caption)
                    }
                    Spacer(minLength: Theme.Space.s)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Redeem gift code")
            .accessibilityIdentifier("store-redeem")
            PasteButton(payloadType: String.self) { (strings: [String]) in
                if let pasted = strings.first { open(pasted.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("store-redeem-paste")
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.inset))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .padding(.horizontal, Theme.Space.m)
    }
}

extension ServerGiftReward {
    /// The coloured reward tiles for what a gift code gave: gold, boxes, then new cosmetics.
    var tiles: [StoreReward] {
        var out: [StoreReward] = []
        if gold > 0 { out.append(StoreReward.gold(gold)) }
        for kind in BoxKind.allCases {
            if let n = boxes[kind.rawValue], n > 0 { out.append(StoreReward.boxes(n, kind)) }
        }
        for id in items {
            let name: String = GoldCosmetics.cosmetic(id)?.item.title ?? "Item"
            out.append(StoreReward(kind: .cosmetic, amount: "+1", caption: name))
        }
        return out
    }
}

/// The popup after a gift code: the rewards as coloured tiles.
struct GiftReceivedCard: View {
    var reward: ServerGiftReward
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("YOU GOT").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.8))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: Theme.Space.s, alignment: .top)], alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(reward.tiles) { (r: StoreReward) in RewardIcon(reward: r, size: 52) }
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(StoreColors.violet)))
            Button { Haptics.tap(); onDone() } label: { StorePriceLabel(text: "Done") }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("gift-done")
        }
    }
}
