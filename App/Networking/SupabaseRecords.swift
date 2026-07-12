import Foundation

struct FamilyRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let weeklyBaseAllowanceCents: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case weeklyBaseAllowanceCents = "weekly_base_allowance_cents"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FamilyMemberRecord: Codable, Identifiable, Sendable {
    let familyId: UUID
    let userId: UUID
    let role: String
    let displayName: String
    let createdAt: Date

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case familyId = "family_id"
        case userId = "user_id"
        case role
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

struct ChildProfileRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let familyId: UUID
    let displayName: String
    let phoneE164: String?
    let linkedUserId: UUID?
    let createdByParentId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case displayName = "display_name"
        case phoneE164 = "phone_e164"
        case linkedUserId = "linked_user_id"
        case createdByParentId = "created_by_parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChildInviteRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let familyId: UUID
    let childProfileId: UUID
    let childName: String
    let phoneE164: String?
    let createdByParentId: UUID?
    let status: String
    let expiresAt: Date
    let acceptedAt: Date?
    let acceptedChildUserId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case childProfileId = "child_profile_id"
        case childName = "child_name"
        case phoneE164 = "phone_e164"
        case createdByParentId = "created_by_parent_id"
        case status
        case expiresAt = "expires_at"
        case acceptedAt = "accepted_at"
        case acceptedChildUserId = "accepted_child_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ParentInviteRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let familyId: UUID
    let parentName: String
    let phoneE164: String?
    let createdByParentId: UUID?
    let status: String
    let expiresAt: Date
    let acceptedAt: Date?
    let acceptedParentUserId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case parentName = "parent_name"
        case phoneE164 = "phone_e164"
        case createdByParentId = "created_by_parent_id"
        case status
        case expiresAt = "expires_at"
        case acceptedAt = "accepted_at"
        case acceptedParentUserId = "accepted_parent_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChoreDefinitionRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let familyId: UUID
    let childId: UUID
    let title: String
    let shortTitle: String
    let description: String?
    let instructions: String?
    let expectedEvidence: String?
    let deductionCents: Int
    let verificationMode: String
    let recurrence: RecurrencePayload
    let dueWindowMinutes: Int
    let reminderOffsetsMinutes: [Int]
    let isPaused: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case childId = "child_id"
        case title
        case shortTitle = "short_title"
        case description
        case instructions
        case expectedEvidence = "expected_evidence"
        case deductionCents = "deduction_cents"
        case verificationMode = "verification_mode"
        case recurrence
        case dueWindowMinutes = "due_window_minutes"
        case reminderOffsetsMinutes = "reminder_offsets_minutes"
        case isPaused = "is_paused"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TaskOccurrenceRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let choreDefinitionId: UUID
    let childId: UUID
    let weekId: UUID
    let scheduledAt: Date
    let dueAt: Date
    let expiresAt: Date
    let status: String
    let submissionId: UUID?
    let deductionLedgerEntryId: UUID?
    let excuseReason: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case choreDefinitionId = "chore_definition_id"
        case childId = "child_id"
        case weekId = "week_id"
        case scheduledAt = "scheduled_at"
        case dueAt = "due_at"
        case expiresAt = "expires_at"
        case status
        case submissionId = "submission_id"
        case deductionLedgerEntryId = "deduction_ledger_entry_id"
        case excuseReason = "excuse_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct LedgerEntryRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let weekId: UUID
    let childId: UUID
    let createdBy: UUID?
    let entryType: String
    let title: String
    let amountCents: Int
    let relatedOccurrenceId: UUID?
    let note: String?
    let isVoided: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case weekId = "week_id"
        case childId = "child_id"
        case createdBy = "created_by"
        case entryType = "entry_type"
        case title
        case amountCents = "amount_cents"
        case relatedOccurrenceId = "related_occurrence_id"
        case note
        case isVoided = "is_voided"
        case createdAt = "created_at"
    }
}

struct RecurrencePayload: Codable, Sendable {
    let type: String
    let times: [String]?
    let weekdays: [Int]?
    let rule: String?
    let dueAt: Date?

    enum CodingKeys: String, CodingKey {
        case type
        case times
        case weekdays
        case rule
        case dueAt = "due_at"
    }
}
