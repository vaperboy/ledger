import SwiftUI

/// The three popup categories side by side, with real popup components, for review screenshots. Opened only by the launch argument
/// `-popupGallery` (UI test `ShotsPopupTests`); never reachable in play.
struct PopupGallery: View {
    @State private var pending: PendingAction?
    @State private var medium = false
    @State private var detail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Popup gallery").font(.system(size: 28, weight: .bold, design: .serif)).foregroundStyle(Theme.ink)
                ForEach(0..<8, id: \.self) { (i: Int) in
                    HStack {
                        Text(["Café Nordic", "Bakery Oslo", "Gym Bergen", "Barber Stavanger", "Hardware Trondheim", "Law office", "Courier", "Dental"][i])
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(12 + i * 7) k").foregroundStyle(i % 3 == 0 ? Theme.loss : Theme.gain)
                    }
                    .padding(.vertical, 12)
                }
                button("Compact: buy", id: "gallery-compact-buy") {
                    pending = PendingAction(title: "Buy an espresso machine?", message: "2,400 kr. Serves 40 more customers a day.", button: "Buy",
                                            alwaysAsk: true, tone: .investment, icon: "cup.and.saucer") {}
                }
                button("Compact: let go", id: "gallery-compact-hold") {
                    pending = PendingAction(title: "Let Anna Berg go?", message: "Two weeks' notice and redundancy pay of 18 k.", button: "Let go",
                                            destructive: true, icon: "person.crop.circle.badge.minus") {}
                }
                button("Medium: supplier", id: "gallery-medium") { medium = true }
                button("Detail: acquisition", id: "gallery-detail") { detail = true }
            }
            .padding(20)
        }
        .background(Theme.page.ignoresSafeArea())
        .confirmAction($pending)
        .centerSheet(isPresented: $medium, title: "Supplier wants cash", category: .medium, tone: .warning) { mediumBody }
        .centerSheet(isPresented: $detail, title: "Buy Bakery Oslo", category: .detail, tone: .investment) { detailBody }
    }

    private func button(_ title: String, id: String, _ run: @escaping () -> Void) -> some View {
        Button(title, action: run).buttonStyle(SecondaryButtonStyle(fullWidth: true)).accessibilityIdentifier(id)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nordic Beans will only deliver if you pay up front from next week.").font(.system(size: 16)).foregroundStyle(Theme.inkSoft)
            ForEach(["Pay up front (keeps stock)", "Switch to Oslo Roasters (+6% cost)", "Negotiate 14-day terms"], id: \.self) { (o: String) in
                Button(o) { medium = false }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
        }
    }

    private var detailBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("4.2 M kr").font(.system(size: 40, weight: .semibold, design: .serif)).foregroundStyle(PopupTone.investment.color)
            Text("Asking price, 5.1x last year's profit").font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
            ForEach(["Revenue 12 mo|9.8 M", "Profit 12 mo|820 k", "Staff|14", "Lease left|6 years", "Debt taken over|1.1 M", "Your cash after|2.3 M"], id: \.self) { (r: String) in
                let parts: [String] = r.split(separator: "|").map(String.init)
                HStack { Text(parts[0]).foregroundStyle(Theme.inkSoft); Spacer(); Text(parts[1]).foregroundStyle(Theme.ink).monospacedDigit() }
                    .font(.system(size: 16))
                Hairline()
            }
            Text("The seller's manager stays for a year. Two rivals are bidding.").font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
        }
        .popupFooter {
            Button("Make an offer") { detail = false }.buttonStyle(PopupPrimaryCapsuleStyle(tone: .investment))
        }
    }
}
