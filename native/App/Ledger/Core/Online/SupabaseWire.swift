import Foundation

struct SupabaseSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var createdAt: Date
    var provider: SignInProvider?

    func needsRefresh(now: Date = Date(), skew: TimeInterval = 60) -> Bool { expiresAt.timeIntervalSince(now) <= skew }
}

struct SupabaseTokenResponse: Decodable {
    struct User: Decodable {
        struct Meta: Decodable {
            var provider: String?
            var providers: [String]?
        }
        struct Identity: Decodable { var provider: String }
        var id: String
        var createdAt: Date?
        var appMetadata: Meta?
        var identities: [Identity]?
        enum CodingKeys: String, CodingKey { case id, createdAt = "created_at", appMetadata = "app_metadata", identities }
    }
    var accessToken: String
    var refreshToken: String
    var expiresIn: Double?
    var expiresAt: Double?
    var user: User
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", expiresAt = "expires_at", user
    }

    func session(now: Date = Date(), fallbackProvider: SignInProvider? = nil) -> SupabaseSession {
        let expiry: Date = expiresAt.map { Date(timeIntervalSince1970: $0) } ?? now.addingTimeInterval(expiresIn ?? 3600)
        let names: [String] = (user.identities ?? []).map { $0.provider } + (user.appMetadata?.providers ?? []) + [user.appMetadata?.provider].compactMap { $0 }
        let linked: SignInProvider? = names.compactMap { SignInProvider(rawValue: $0) }.first ?? fallbackProvider
        return SupabaseSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiry, userID: user.id,
                               createdAt: user.createdAt ?? now, provider: linked)
    }
}

enum SupabaseWire {

    static func request(base: URL, path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil,
                        apiKey: String, accessToken: String? = nil, prefer: String? = nil) -> URLRequest {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        comps.path = (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + path
        comps.queryItems = query.isEmpty ? nil : query
        var req = URLRequest(url: comps.url ?? base)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        if let accessToken { req.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        return req
    }

    static func pairFilter(_ a: String, _ b: String) -> URLQueryItem {
        URLQueryItem(name: "or", value: "(and(requester_id.eq.\(a),addressee_id.eq.\(b)),and(requester_id.eq.\(b),addressee_id.eq.\(a)))")
    }

    static func privacyWire(_ p: PrivacyLevel) -> String {
        switch p { case .everyone: return "public"; case .friends: return "friends"; case .onlyMe: return "private" }
    }

    private static func parseDate(_ s: String) -> Date? {
        let trimmed: String = s.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: trimmed) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    static func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let s: String = try decoder.singleValueContainer().decode(String.self)
            guard let d = parseDate(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
            }
            return d
        }
        return dec
    }

    static func makeEncoder() -> JSONEncoder { JSONEncoder() }

    static func mapError(status: Int, body: Data) -> OnlineError {
        let json: [String: Any] = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let message: String = ((json["message"] ?? json["msg"] ?? json["error_description"]) as? String) ?? ""
        let code: String = (json["code"] as? String) ?? (json["error_code"] as? String) ?? ""
        let hint: String = (json["details"] as? String) ?? ""

        if message.hasPrefix("name_rejected") {
            let why: String = message.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces)
            return .nameRejected(why.isEmpty ? "That name is not allowed." : why)
        }
        let key: String = message.split(separator: ":", maxSplits: 1).first.map(String.init) ?? message
        let amount: String = message.contains(":") ? message.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces) : ""
        switch key {
        case "not_signed_in": return .notSignedIn
        case "not_found": return .notFound
        case "blocked": return .blocked
        case "already_friends": return .alreadyFriends
        case "request_pending": return .requestPending
        case "cannot_target_self": return .cannotTargetYourself
        case "adult_required": return .adultRequired
        case "not_admin": return .notAdmin
        case "reason_required": return .rejected("Give a reason of at least three characters.")
        case "outside_hard_limits": return .rejected("That value is outside the fixed limits of this rule.")
        case "rules_conflict": return .rejected("That would make two rules contradict each other.")
        case "unknown_rule": return .rejected("That rule does not exist.")
        case "own_proposal": return .rejected("You cannot decide a change you proposed yourself.")
        case "not_in_office": return .rejected("The proposer no longer holds the office.")
        case "too_soon": return .rejected("Too soon after the last change of that kind.")
        case "outside_limits", "change_too_large": return .rejected("The change is outside the current tax limits.")
        case "not_eligible": return .rejected("The winner is no longer eligible for the office.")
        case "lock_up": return .rejected("The owner cannot sell shares in the first 28 days after the listing.")
        case "blackout": return .rejected("The owner cannot sell shares around the results.")
        case "outside_day_limit": return .rejected("A price can move at most 10% from the last close in a day.")
        case "holder_cap": return .rejected("No outside holder may own more than a fifth of a company.")
        case "value_jump": return .rejected("The company's value can move at most 10% a report.")
        case "invalid_value": return .rejected("That figure is not allowed.")
        case "invalid_office": return .rejected("Check the office name, city and fee.")
        case "own_office": return .rejected("You cannot hire your own office.")
        case "currency_mismatch": return .rejected("This office is paid in another currency.")
        case "already_hired": return .rejected("This office already keeps the books of that company.")
        case "already_rated": return .rejected("You have already rated this accountant.")
        case "too_early": return .rejected("Rate an accountant after a week of working together.")
        case "new_account": return .rejected("Shared deals open after the account is four weeks old.")
        case "open_contracts": return .rejected("Something is still open with other players. Try again in a moment.")
        case "price_outside_market": return .rejected("That price is far from what the market pays.")
        case "too_many_orders": return .rejected("You have too many open orders. Cancel some first.")
        case "outside_band": return .rejected("That price is outside the range around the company's value.")
        case "too_many": return .rejected("You do not hold that many shares.")
        case "too_small": return .rejected("The company is too small for this.")
        case "invalid_order", "invalid_amount", "invalid_listing", "invalid_reserve", "invalid_units", "invalid_progress": return .rejected("Check the figures and try again.")
        case "not_reportable", "invalid_event": return .rejected("That cannot be reported.")
        case "rate_limited": return .rejected("Too many requests. Try again later.")
        case "start_price_too_low": return .rejected("The starting price is too low.")
        case "too_low": return .rejected(amount.isEmpty ? "The bid is too low." : "The lowest bid now is \(amount).")
        case "not_enough_cash": return .rejected(amount.isEmpty ? "You cannot cover that bid." : "That is \(amount) more than you can bid for now.")
        case "seller_cannot_bid": return .rejected("You cannot bid on your own piece or one listed by a linked account.")
        case "already_leading": return .rejected("You already lead this auction.")
        case "not_live": return .rejected("This auction has ended.")
        case "has_bids": return .rejected("Someone has bid, so the listing cannot be taken back.")
        case "already_listed": return .rejected("This is already on offer.")
        case "gift_limit": return .rejected("You have already sent a gift today.")
        case "invalid_gift": return .rejected("That piece cannot be sent.")
        case "not_yours": return .rejected("That is not yours.")
        case "linked_account", "linked_parties", "linked_to_founder": return .rejected("Deals between accounts of the same person are not allowed.")
        case "listing_full": return .rejected("That supplier has no room left.")
        case "capacity_below_commitments": return .rejected("Capacity cannot go below what is already contracted.")
        case "deal_open": return .rejected("You already have a deal open on this.")
        case "own_listing": return .rejected("You cannot buy your own listing or one from a linked account.")
        case "offer_used": return .rejected("You have already made your offer on this.")
        case "offer_not_lower": return .rejected("An offer has to be lower than the asking price.")
        case "offer_too_low": return .rejected("That offer is too far below the asking price.")
        case "too_many_listings": return .rejected("You can have 12 listings at a time.")
        case "invalid_item": return .rejected("This item cannot be listed.")
        case "invalid_price": return .rejected("Check the price.")
        case "price_not_lower": return .rejected("The new price has to be lower than the asking price.")
        case "already_discussing": return .rejected("A price is already on the table.")
        case "invalid_action": return .rejected("That cannot be done now.")
        case "listing_closed": return .rejected("This listing is closed.")
        case "not_friends": return .rejected("Only a friend can be invited as a partner.")
        case "already_partner": return .rejected("That player is a partner already.")
        case "too_many_partners": return .rejected("The company has as many partners as it can have.")
        case "invalid_stake": return .rejected("That share is not allowed: a partner holds 2% to 49%.")
        case "worthless": return .rejected("The company is worth nothing yet, so its shares cannot be priced.")
        case "offer_open": return .rejected("An offer for these shares is already waiting for an answer.")
        case "locked": return .rejected("These shares cannot be sold yet.")
        case "meeting_open": return .rejected("An emergency meeting is already open. Let it finish first.")
        case "agenda_full": return .rejected("The next board meeting is full. Try again after it.")
        case "vote_closed", "already_closed": return .rejected("Voting has closed.")
        case "offer_expired": return .rejected("That offer is no longer open.")
        case "already_set": return .rejected("That is already how it is set.")
        case "no_partners": return .rejected("There is no board yet: the company has no partners.")
        case "invalid_agenda", "too_many_settings": return .rejected("That cannot be put to the board.")
        case "barred": return .rejected("Your account cannot trade with other players right now.")
        default:
            if key.hasPrefix("listing_") { return .rejected("That offer is not available.") }
        }
        if code == "23514", (message + hint).contains("display_name") { return .nameRejected("Use 2 to 20 letters, numbers and . - _ ' only.") }
        if code == "23505", (message + hint).contains("friendships") { return .requestPending }
        if code == "PGRST116" { return .notFound }
        if status == 401 || code == "bad_jwt" || code == "session_not_found" || code == "refresh_token_not_found"
            || code == "refresh_token_already_used" || message.localizedCaseInsensitiveContains("jwt expired") { return .notSignedIn }
        if status == 400 || status == 422, code == "invalid_credentials" || code == "bad_id_token" || code == "validation_failed" { return .notSignedIn }
        if status == 400, (json["error"] as? String) == "invalid_grant" { return .notSignedIn }
        if status == 404 { return .notFound }
        return .offline
    }

    static func linkFailure(code: String, text: String, provider: SignInProvider) -> OnlineError? {
        let lower: String = text.lowercased()
        if code == "identity_already_exists" || lower.contains("already linked") || lower.contains("already been linked") {
            let mine: Bool = !lower.isEmpty && !lower.contains("another")
            return mine ? .rejected("This \(provider.title) account is already linked to you.") : .identityTaken(provider)
        }
        if code == "email_exists" || lower.contains("email address has already been registered") {
            return .rejected("Another Ledger account already uses the email of this \(provider.title) account. Sign in the way you did before.")
        }
        if code == "manual_linking_disabled" || lower.contains("manual linking") {
            return .rejected("Linking accounts is not switched on for the server yet.")
        }
        if code == "provider_disabled" || lower.contains("provider is not enabled") || lower.contains("unsupported provider") || lower.contains("provider not enabled") {
            return .rejected("\(provider.title) linking is not set up on the server yet. Try again later.")
        }
        if code == "access_denied" || lower.contains("access_denied") || lower.contains("access denied") {
            return .cancelled
        }
        return nil
    }

    static func mapLinkError(status: Int, body: Data, provider: SignInProvider) -> OnlineError {
        let json: [String: Any] = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let text: String = ((json["msg"] ?? json["message"] ?? json["error_description"] ?? json["error"]) as? String) ?? ""
        let code: String = (json["error_code"] as? String) ?? ""
        return linkFailure(code: code, text: text, provider: provider) ?? mapError(status: status, body: body)
    }

    static func authorizationCode(from callback: URL, provider: SignInProvider) throws -> String {
        var items: [URLQueryItem] = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let fragment = callback.fragment {
            var comps = URLComponents()
            comps.query = fragment
            items += comps.queryItems ?? []
        }
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        if let code = value("code"), !code.isEmpty { return code }
        let code: String = value("error_code") ?? value("error") ?? ""
        let text: String = value("error_description") ?? ""
        throw linkFailure(code: code, text: text, provider: provider) ?? OnlineError.rejected("Linking did not finish. Try again.")
    }

    static func decodeProfile(_ data: Data) throws -> PlayerProfile { try makeDecoder().decode(PlayerProfile.self, from: data) }
}
