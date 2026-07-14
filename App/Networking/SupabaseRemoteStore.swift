import Foundation
import CryptoKit
import Supabase

struct SupabaseRemoteStore: Sendable {
    var client: SupabaseClient = SupabaseClientProvider.shared

    func currentSession() async throws -> Session {
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)
        return session
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func fetchMembershipsForCurrentUser(userId: UUID) async throws -> [FamilyMemberRecord] {
        try await client
            .from("family_members")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchFamilies() async throws -> [FamilyRecord] {
        try await client
            .from("families")
            .select()
            .execute()
            .value
    }

    func fetchFamily(id: UUID) async throws -> FamilyRecord {
        try await client
            .from("families")
            .select()
            .eq("id", value: id.uuidString)
            .single()
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

    func fetchWeeks(familyId: UUID, childId: UUID) async throws -> [WeekRecord] {
        try await client
            .from("weeks")
            .select()
            .eq("family_id", value: familyId.uuidString)
            .eq("child_id", value: childId.uuidString)
            .order("starts_at", ascending: false)
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

    func fetchOccurrences(weekId: UUID) async throws -> [TaskOccurrenceRecord] {
        try await client
            .from("task_occurrences")
            .select()
            .eq("week_id", value: weekId.uuidString)
            .order("due_at")
            .execute()
            .value
    }

    func fetchChoreSubmissions(childId: UUID) async throws -> [ChoreSubmissionRecord] {
        try await client
            .from("chore_submissions")
            .select()
            .eq("child_id", value: childId.uuidString)
            .order("submitted_at", ascending: false)
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

    func bootstrapPreviewFamily(
        parentName: String,
        childName: String,
        familyName: String?
    ) async throws -> BootstrapFamilyResponse {
        let responses: [BootstrapFamilyResponse] = try await client
            .rpc(
                "bootstrap_preview_family",
                params: BootstrapFamilyParams(
                    parentDisplayName: parentName,
                    childDisplayName: childName,
                    familyDisplayName: familyName
                )
            )
            .execute()
            .value

        guard let response = responses.first else {
            throw SupabaseRemoteStoreError.emptyBootstrapResponse
        }

        return response
    }

    func upsertChildProfile(
        id: UUID,
        familyId: UUID,
        displayName: String,
        phoneNumber: String?,
        createdByParentId: UUID?
    ) async throws -> ChildProfileRecord {
        let payload = ChildProfileUpsert(
            id: id,
            familyId: familyId,
            displayName: displayName,
            phoneE164: normalizedPhoneNumber(phoneNumber),
            createdByParentId: createdByParentId
        )

        return try await client
            .from("child_profiles")
            .upsert(payload, onConflict: "id")
            .select()
            .single()
            .execute()
            .value
    }

    func createChildInvite(
        id: UUID,
        familyId: UUID,
        childProfileId: UUID,
        childName: String,
        phoneNumber: String?,
        createdByParentId: UUID?,
        token: String,
        expiresAt: Date
    ) async throws -> ChildInviteRecord {
        let payload = ChildInviteInsert(
            id: id,
            familyId: familyId,
            childProfileId: childProfileId,
            childName: childName,
            phoneE164: normalizedPhoneNumber(phoneNumber),
            createdByParentId: createdByParentId,
            tokenHash: sha256Hex(token),
            expiresAt: iso8601String(from: expiresAt)
        )

        return try await client
            .from("child_invites")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func createParentInvite(
        id: UUID,
        familyId: UUID,
        parentName: String,
        phoneNumber: String?,
        createdByParentId: UUID?,
        token: String,
        expiresAt: Date
    ) async throws -> ParentInviteRecord {
        let payload = ParentInviteInsert(
            id: id,
            familyId: familyId,
            parentName: parentName,
            phoneE164: normalizedPhoneNumber(phoneNumber),
            createdByParentId: createdByParentId,
            tokenHash: sha256Hex(token),
            expiresAt: iso8601String(from: expiresAt)
        )

        return try await client
            .from("parent_invites")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func uploadEvidenceJPEG(
        familyId: UUID,
        occurrenceId: UUID,
        submissionId: UUID,
        jpegData: Data
    ) async throws -> String {
        let path = "\(familyId.uuidString)/\(occurrenceId.uuidString)/\(submissionId.uuidString).jpg"
        let response = try await client.storage
            .from(SupabaseConfig.evidenceBucketName)
            .upload(
                path,
                data: jpegData,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        return response.path
    }

    func createChoreSubmission(
        id: UUID,
        occurrenceId: UUID,
        childId: UUID,
        imagePath: String
    ) async throws -> ChoreSubmissionRecord {
        let payload = ChoreSubmissionInsert(
            id: id,
            taskOccurrenceId: occurrenceId,
            childId: childId,
            imagePath: imagePath
        )

        return try await client
            .from("chore_submissions")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func reviewEvidence(submissionId: UUID) async throws -> ReviewEvidenceResponse {
        try await client.functions.invoke(
            "review-evidence",
            options: FunctionInvokeOptions(
                method: .post,
                body: ReviewEvidenceRequest(submissionId: submissionId)
            )
        )
    }

    func decideSubmission(
        occurrenceId: UUID,
        decision: ParentDecision.Decision,
        note: String?
    ) async throws -> ParentReviewDecisionResponse {
        let responses: [ParentReviewDecisionResponse] = try await client
            .rpc(
                "decide_chore_submission",
                params: ParentReviewDecisionParams(
                    targetOccurrenceId: occurrenceId,
                    targetDecision: decision.rawValue,
                    targetNote: note
                )
            )
            .execute()
            .value

        guard let response = responses.first else {
            throw SupabaseRemoteStoreError.emptyParentReviewDecisionResponse
        }

        return response
    }

    private func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func normalizedPhoneNumber(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("+") {
            let digits = trimmed.dropFirst().filter(\.isNumber)
            return digits.count >= 8 ? "+\(digits)" : nil
        }

        let digits = trimmed.filter(\.isNumber)
        if digits.count == 10 {
            return "+1\(digits)"
        }
        if digits.count == 11, digits.first == "1" {
            return "+\(digits)"
        }
        return nil
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

enum SupabaseRemoteStoreError: LocalizedError {
    case emptyBootstrapResponse
    case emptyParentReviewDecisionResponse

    var errorDescription: String? {
        switch self {
        case .emptyBootstrapResponse:
            return "Supabase did not return a family after bootstrapping."
        case .emptyParentReviewDecisionResponse:
            return "Supabase did not return the reviewed task."
        }
    }
}

private struct BootstrapFamilyParams: Encodable {
    let parentDisplayName: String
    let childDisplayName: String
    let familyDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case parentDisplayName = "parent_display_name"
        case childDisplayName = "child_display_name"
        case familyDisplayName = "family_display_name"
    }
}

private struct ChildProfileUpsert: Encodable {
    let id: UUID
    let familyId: UUID
    let displayName: String
    let phoneE164: String?
    let createdByParentId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case displayName = "display_name"
        case phoneE164 = "phone_e164"
        case createdByParentId = "created_by_parent_id"
    }
}

private struct ChildInviteInsert: Encodable {
    let id: UUID
    let familyId: UUID
    let childProfileId: UUID
    let childName: String
    let phoneE164: String?
    let createdByParentId: UUID?
    let tokenHash: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case childProfileId = "child_profile_id"
        case childName = "child_name"
        case phoneE164 = "phone_e164"
        case createdByParentId = "created_by_parent_id"
        case tokenHash = "token_hash"
        case expiresAt = "expires_at"
    }
}

private struct ParentInviteInsert: Encodable {
    let id: UUID
    let familyId: UUID
    let parentName: String
    let phoneE164: String?
    let createdByParentId: UUID?
    let tokenHash: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case parentName = "parent_name"
        case phoneE164 = "phone_e164"
        case createdByParentId = "created_by_parent_id"
        case tokenHash = "token_hash"
        case expiresAt = "expires_at"
    }
}

private struct ChoreSubmissionInsert: Encodable {
    let id: UUID
    let taskOccurrenceId: UUID
    let childId: UUID
    let imagePath: String

    enum CodingKeys: String, CodingKey {
        case id
        case taskOccurrenceId = "task_occurrence_id"
        case childId = "child_id"
        case imagePath = "image_path"
    }
}

private struct ReviewEvidenceRequest: Encodable {
    let submissionId: UUID

    enum CodingKeys: String, CodingKey {
        case submissionId = "submission_id"
    }
}

private struct ParentReviewDecisionParams: Encodable {
    let targetOccurrenceId: UUID
    let targetDecision: String
    let targetNote: String?

    enum CodingKeys: String, CodingKey {
        case targetOccurrenceId = "target_occurrence_id"
        case targetDecision = "target_decision"
        case targetNote = "target_note"
    }
}
