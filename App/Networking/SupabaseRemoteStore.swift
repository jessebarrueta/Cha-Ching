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

    func fetchFamilyMembers(familyId: UUID) async throws -> [FamilyMemberRecord] {
        try await client
            .from("family_members")
            .select()
            .eq("family_id", value: familyId.uuidString)
            .execute()
            .value
    }

    func fetchChildProfiles(familyId: UUID) async throws -> [ChildProfileRecord] {
        try await client
            .from("child_profiles")
            .select()
            .eq("family_id", value: familyId.uuidString)
            .order("created_at")
            .execute()
            .value
    }

    func fetchChildInvites(familyId: UUID) async throws -> [ChildInviteRecord] {
        try await client
            .from("child_invites")
            .select()
            .eq("family_id", value: familyId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchParentInvites(familyId: UUID) async throws -> [ParentInviteRecord] {
        try await client
            .from("parent_invites")
            .select()
            .eq("family_id", value: familyId.uuidString)
            .order("created_at", ascending: false)
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
