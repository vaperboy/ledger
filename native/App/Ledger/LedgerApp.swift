import SwiftUI
import UIKit

@main
struct LedgerApp: App {
    @StateObject private var store = GameStore()
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var statusBar = StatusBarScheme.shared
    @State private var entitlements: Entitlements
    @State private var purchases: PurchaseManager
    @State private var ads: AdCoordinator
    @State private var online = OnlineSession()

    init() {
        let ent = Entitlements()
        _entitlements = State(initialValue: ent)
        _purchases = State(initialValue: PurchaseManager(entitlements: ent))
        _ads = State(initialValue: AdCoordinator(entitlements: ent))
        let ivory = UIColor(red: 0.937, green: 0.914, blue: 0.875, alpha: 1)
        let faint = UIColor(red: 0.424, green: 0.416, blue: 0.384, alpha: 1), gold = UIColor(red: 0.812, green: 0.694, blue: 0.522, alpha: 1)
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(red: 0.051, green: 0.059, blue: 0.067, alpha: 1)
        tabs.shadowColor = ivory.withAlphaComponent(0.09)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = faint; item.normal.titleTextAttributes = [.foregroundColor: faint]
            item.selected.iconColor = gold; item.selected.titleTextAttributes = [.foregroundColor: gold]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        let serif = UIFont.systemFont(ofSize: 18, weight: .medium).fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 18) } ?? UIFont.systemFont(ofSize: 18)
        let bars = UINavigationBarAppearance()
        bars.configureWithTransparentBackground()
        bars.titleTextAttributes = [.foregroundColor: ivory, .font: serif]
        bars.largeTitleTextAttributes = [.foregroundColor: ivory]
        UINavigationBar.appearance().standardAppearance = bars
        UINavigationBar.appearance().compactAppearance = bars
        UINavigationBar.appearance().scrollEdgeAppearance = bars
        UITableViewCell.appearance().backgroundColor = UIColor(red: 0.067, green: 0.075, blue: 0.082, alpha: 1)
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-popupGallery") {
                PopupGallery().popupHost().preferredColorScheme(.dark)
            } else {
            RootView()
                .modifier(PaywallHost())
                .modifier(PurchaseHost())
                .environmentObject(store)
                .environment(entitlements)
                .environment(purchases)
                .environment(ads)
                .environment(online)
                .task { purchases.start() }
                .task { OnlineWiring.install(); await online.start(); await OnlineDirectoryCache.refresh(from: online.service); store.syncPlayerCompanies() }
                .task(id: online.isSignedIn && scenePhase == .active) {
                    if online.isSignedIn && scenePhase == .active { await online.runPresence(store: store) }
                }
                .onOpenURL { url in if online.receive(url: url) { store.openApp(.profile) } }
                .preferredColorScheme(statusBar.light ? .light : .dark)
                .tint(Theme.gold)
                .toggleStyle(LedgerToggleStyle())
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { store.scheduleReminders(); store.noteLeaving(); Task { await online.shareProgress(from: store.engine) } }
                    if phase == .active { store.syncPlayerCompanies(); Reminders.cancelAll(); store.showReturnRecap(); Task { await purchases.refreshEntitlements() } }
                }
            }
        }
    }
}
