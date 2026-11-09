import Foundation

// The administrator calls over the Supabase RPC functions. Nothing here decides who is an administrator or what a rule may be: the server
// checks the account on every call (`admins` table) and keeps every rule inside its fixed limits.

extension SupabaseOnlineService {
    func redeemAdminCode(_ code: String) async throws -> AdminCodeResult {
        struct Answer: Decodable { var ok: Bool; var reason: String }
        let a: Answer = try decode(Answer.self, try await rpcData("redeem_admin_code", ["p_code": code]))
        switch a.reason {
        case "granted": return .granted
        case "already_admin": return .alreadyAdmin
        case "locked": return .locked
        default: return a.ok ? .granted : .invalid
        }
    }

    func adminSnapshot() async throws -> AdminSnapshot { try decode(AdminSnapshot.self, try await rpcData("admin_overview")) }

    func adminSetRule(key: String, value: Double, reason: String) async throws {
        _ = try await rpcData("admin_set_rule", ["p_key": key, "p_value": value, "p_reason": reason])
    }

    func adminDecide(id: String, approve: Bool, reason: String) async throws {
        _ = try await rpcData("admin_decide", ["p_id": id, "p_approve": approve, "p_reason": reason])
    }

    func adminAudit(before: Int?, limit: Int) async throws -> [AuditEntry] {
        var params: [String: Any] = ["p_limit": limit]
        if let before { params["p_before"] = before }
        return try decode([AuditEntry].self, try await rpcData("admin_audit_page", params))
    }
}
