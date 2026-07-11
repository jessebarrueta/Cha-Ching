import Foundation
import Supabase

struct SupabaseRemoteStore: Sendable {
    var client: SupabaseClient = SupabaseClientProvider.shared

    func fetchFamilies() async throws -> [FamilyRecord] {
        try await client
            .from("families")
            .select()
            .execute()
            .value
    }

    func fetchChores(familyId: UUID) async throws -> [ChoreDefinitionRecord] {
        try await client
            .from("chore_definitions")
            .select()
            .eq("family_id", value: familyId.uuidString)
            .order("title")
            .execute()
            .value
    }

    func fetchLedger(weekId: UUID) async throws -> [LedgerEntryRecord] {
        try await client
            .from("ledger_entries")
            .select()
            .eq("week_id", value: weekId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
}

