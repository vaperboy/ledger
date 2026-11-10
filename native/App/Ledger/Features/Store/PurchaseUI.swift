import SwiftUI
import Simulation

struct PurchaseButton: View {
    @Environment(PurchaseManager.self) private var purchases
    var item: PurchaseItem
    var title: String = ""
    var showsPrice: Bool = true
    var minHeight: CGFloat = 40
    var leave: (() -> Void)? = nil
    var identifier: String = ""

    var body: some View {
        let manager: PurchaseManager = purchases
        let price: String? = manager.price(item)
        let busy: Bool = manager.inFlight == item
        let target: PurchaseItem = item
        let closer: (() -> Void)? = leave
        return Button {
            Haptics.tap()
            if let closer {
                closer()
                StorePurchase.afterPopup { manager.request(target) }
            } else {
                manager.request(target)
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                if busy { ProgressView().controlSize(.small).tint(Theme.accentInk) }
                Text(label(price: price, busy: busy)).textStyle(.headline, tint: Theme.accentInk, numeric: true).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, Theme.Space.l).frame(minHeight: minHeight)
            .background(Capsule().fill(Theme.accent))
        }
        .buttonStyle(PressableStyle())
        .disabled(manager.isBusy || price == nil)
        .opacity(price == nil ? 0.55 : 1)
        .accessibilityIdentifier(identifier)
    }

    private func label(price: String?, busy: Bool) -> String {
        if busy { return "Working..." }
        guard let price else { return purchases.catalogLoaded ? "Unavailable" : "..." }
        if title.isEmpty { return price }
        return showsPrice ? title + " · " + price : title
    }
}

struct PurchaseNoticeCard: View {
    var notice: PurchaseNotice
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.popupClose) private var popupClose
    @Environment(\.dismiss) private var systemDismiss

    private var tone: PopupTone {
        switch notice.kind {
        case .success: return .success
        case .info: return .info
        case .failure: return .danger
        }
    }

    private func close() { if let c = popupClose { c() } else { systemDismiss() } }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Text(notice.title).textStyle(.title, tint: tone.color).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(notice.lines.enumerated()), id: \.offset) { (_: Int, line: String) in
                Text(line).textStyle(.body, tint: Theme.inkSoft).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("purchase-notice")
        .popupFooter {
            if let item = notice.retry {
                VStack(spacing: Theme.Space.s) {
                    Button { close(); Task { await purchases.buy(item) } } label: { Text("Retry payment") }
                        .buttonStyle(PopupPrimaryCapsuleStyle(tone: .neutral))
                        .accessibilityIdentifier("purchase-notice-retry")
                    Button { close() } label: { Text("No thanks").textStyle(.caption, tint: Theme.inkFaint).frame(minHeight: 36) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("purchase-notice-dismiss")
                }
            } else {
                Button { close() } label: { Text("Done") }
                    .buttonStyle(PopupPrimaryCapsuleStyle(tone: tone == .danger ? .neutral : tone))
                    .accessibilityIdentifier("purchase-notice-done")
            }
        }
    }
}

struct PurchaseHost: ViewModifier {
    @Environment(PurchaseManager.self) private var purchases

    func body(content: Content) -> some View {
        let confirmation: Binding<PendingAction?> = Binding(get: { purchases.confirmation }, set: { purchases.confirmation = $0 })
        let notice: Binding<PurchaseNotice?> = Binding(get: { purchases.notice }, set: { purchases.notice = $0 })
        return content
            .confirmAction(confirmation)
            .centerSheet(item: notice, title: "Purchase", category: .compact, tone: .prestige) { (n: PurchaseNotice) in
                PurchaseNoticeCard(notice: n)
            }
    }
}
