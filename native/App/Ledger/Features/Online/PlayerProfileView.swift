import SwiftUI

/// Another player's profile as the server lets this viewer see it (see `PrivacyLevel`), with Add friend, Remove, Block and Report.
struct PlayerProfileView: View {
    var playerID: String
    @Environment(OnlineSession.self) private var online
    @State private var profile: PlayerProfile?
    @State private var failure: String?
    @State private var busy = false
    @State private var pending: PendingAction?
    @State private var reporting: ReportTarget?
    @State private var reportSent = false

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            if let p = profile {
                header(p)
                if p.relation == .blocked {
                    Text("You blocked this player. They cannot send you requests.").textStyle(.body, tint: Theme.inkSoft).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                } else {
                    detailGroups(p)
                }
                actions(p)
            } else if let failure {
                Text(failure).textStyle(.body, tint: Theme.inkSoft).frame(maxWidth: .infinity).padding(.top, Theme.Space.xl)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Space.xl)
            }
        }
        .appScreen(title: profile?.displayName ?? "Player", subtitle: profile?.subline ?? "")
        .task { await load() }
        .confirmAction($pending)
        .centerSheet(item: $reporting, title: "Report player", category: .medium) { (t: ReportTarget) in
            ReportSheet(target: t) { reason, note in
                Task {
                    try? await online.service.report(t.id, reason: reason, note: note)
                    reportSent = true
                }
            }
        }
    }

    // MARK: Parts

    private func header(_ p: PlayerProfile) -> some View {
        VStack(spacing: Theme.Space.s) {
            PlayerAvatar(player: p, size: 84)
            Text(p.displayName).textStyle(.title)
            Text(p.subline).textStyle(.caption)
            if !p.badges.isEmpty {
                Text(p.badges.joined(separator: "  ·  ")).textStyle(.caption, tint: Theme.accent).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, Theme.Space.m)
    }

    @ViewBuilder private func detailGroups(_ p: PlayerProfile) -> some View {
        if p.level != nil || p.companyCount != nil || p.gameWeek != nil {
            OnlineGroup(title: "Profile") {
                if let l = p.level { OnlineLine(glyph: Glyph.achievements, title: "Level", value: "\(l)") }
                if let n = p.companyCount { Hairline(); OnlineLine(glyph: Glyph.group, title: "Companies", value: "\(n)") }
                if let w = p.gameWeek { Hairline(); OnlineLine(glyph: Glyph.stats, title: "Their game is in week", value: "\(w + 1)") }
            }
        }
        if let list = p.companies, !list.isEmpty {
            OnlineGroup(title: "Companies and how they are doing") {
                OnlineCompanyList(companies: Array(list.prefix(3)))
                if list.count > 3 {
                    Hairline()
                    NavigationLink { FriendCompaniesView(player: p) } label: { OnlineLine(glyph: Glyph.group, title: "All \(list.count) companies", chevron: true) }
                        .buttonStyle(PressableStyle())
                }
            }
        } else {
            Text(hiddenNote(p)).textStyle(.caption, tint: Theme.inkFaint).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
        if let t = p.tradesCompleted {
            OnlineGroup(title: "Trade record") { OnlineLine(glyph: Glyph.market, title: "Trades completed", value: "\(t)") }
        }
    }

    private func hiddenNote(_ p: PlayerProfile) -> String {
        if let list = p.companies, list.isEmpty { return "No companies yet." }
        switch p.privacy {
        case .everyone: return "Friends see which companies this player runs."
        case .friends: return "Only friends see this player's companies."
        case .onlyMe: return "This player keeps their profile private."
        }
    }

    private func actions(_ p: PlayerProfile) -> some View {
        VStack(spacing: Theme.Space.s) {
            switch p.relation {
            case .none:
                Button("Add friend") { run { try await online.service.sendFriendRequest(to: p.id) } }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true)).accessibilityIdentifier("profile-add-friend")
                Text("If you add \(p.displayName), they get a request. Once they accept you are friends: friends see the companies you run (as your privacy setting allows) and can be invited into a joint venture. You can remove them any time.")
                    .textStyle(.caption, tint: Theme.inkFaint).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            case .requestSent:
                Text("Friend request sent").textStyle(.body, tint: Theme.inkSoft)
                Button("Cancel request") { run { try await online.service.cancelFriendRequest(to: p.id) } }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            case .requestReceived:
                Button("Accept request") { run { try await online.service.acceptFriendRequest(from: p.id) } }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                Text("If you accept, you and \(p.displayName) are friends: friends see the companies you run (as your privacy setting allows) and can be invited into a joint venture.")
                    .textStyle(.caption, tint: Theme.inkFaint).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Decline") { run { try await online.service.declineFriendRequest(from: p.id) } }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            case .friend:
                Button("Remove friend") {
                    pending = PendingAction(title: "Remove \(p.displayName)?", message: "They no longer see your companies. You can add them again later.",
                                            button: "Remove friend", alwaysAsk: true, tone: .warning, icon: "person.fill.xmark") { run { try await online.service.removeFriend(p.id) } }
                }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            case .blocked:
                Button("Unblock") { run { try await online.service.unblockPlayer(p.id) } }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            case .you:
                EmptyView()
            }
            if p.relation != .blocked && p.relation != .you {
                Button("Block") {
                    pending = PendingAction(title: "Block \(p.displayName)?", message: "They are removed from your friends and requests, and cannot find you in search.",
                                            button: "Block", destructive: true, alwaysAsk: true) { run { try await online.service.blockPlayer(p.id) } }
                }.buttonStyle(TertiaryButtonStyle(tint: Theme.loss))
            }
            if p.relation != .you {
                if reportSent {
                    Text("Report sent. Thank you.").textStyle(.caption, tint: Theme.inkSoft)
                } else {
                    Button("Report") { reporting = ReportTarget(id: p.id, name: p.displayName) }.buttonStyle(TertiaryButtonStyle(tint: Theme.inkSoft))
                }
            }
            if let failure, profile != nil { Text(failure).textStyle(.caption, tint: Theme.loss) }
        }
        .disabled(busy)
    }

    // MARK: Calls

    private func load() async {
        do { profile = try await online.service.profile(id: playerID); failure = nil } catch { failure = (error as? LocalizedError)?.errorDescription ?? "Could not load this profile." }
    }

    private func run(_ call: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await call(); failure = nil } catch { failure = (error as? LocalizedError)?.errorDescription ?? "That did not work. Try again." }
            await load()
            busy = false
        }
    }
}

struct ReportTarget: Identifiable { var id: String; var name: String }

/// The reasons list of the report popup (centre card): pick one, add a line if you like, send.
struct ReportSheet: View {
    var target: ReportTarget
    var onSend: (ReportReason, String) -> Void
    @Environment(\.popupClose) private var popupClose
    @State private var reason: ReportReason?
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: PopupSpace.block) {
            Text("Why are you reporting \(target.name)?").popupText(.body)
            ForEach(ReportReason.allCases, id: \.self) { (r: ReportReason) in
                Button { Haptics.tap(); reason = r } label: {
                    HStack {
                        Text(r.title).popupText(.body)
                        Spacer()
                        Image(systemName: reason == r ? "largecircle.fill.circle" : "circle").foregroundStyle(reason == r ? Theme.accent : Theme.inkFaint)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(reason == r ? .isSelected : [])
            }
            TextField("Add detail (optional)", text: $note).popupField()
        }
        .centerSheetTitle("Report player")
        .popupFooter {
            PopupFooter(action: "Send report", onCancel: { popupClose?() }, onAction: {
                if let r = reason { onSend(r, note); popupClose?() }
            }, actionEnabled: reason != nil)
        }
    }
}

/// A friend's companies on a page of their own: every company with its trade, place and how it is doing.
struct FriendCompaniesView: View {
    var player: PlayerProfile

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            OnlineGroup(title: "Companies", footer: "How a company is doing is shown in words. Figures stay private.") {
                OnlineCompanyList(companies: player.companies ?? [])
            }
        }
        .appScreen(title: player.displayName, subtitle: "Companies")
    }
}
