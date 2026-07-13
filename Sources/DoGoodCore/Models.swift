import Foundation

public enum FamilyMemberRole: String, Codable, CaseIterable, Identifiable {
    case parent
    case child

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .parent:
            return "Parent"
        case .child:
            return "Child"
        }
    }
}

public struct FamilyMember: Identifiable, Codable, Equatable {
    public var familyId: UUID
    public var userId: UUID
    public var role: FamilyMemberRole
    public var displayName: String
    public var createdAt: Date

    public var id: UUID { userId }

    public init(
        familyId: UUID,
        userId: UUID,
        role: FamilyMemberRole,
        displayName: String,
        createdAt: Date = Date()
    ) {
        self.familyId = familyId
        self.userId = userId
        self.role = role
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

public struct ChildProfile: Identifiable, Codable, Equatable {
    public var id: UUID
    public var familyId: UUID
    public var displayName: String
    public var phoneNumber: String?
    public var linkedUserId: UUID?
    public var createdByParentId: UUID
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        familyId: UUID,
        displayName: String,
        phoneNumber: String? = nil,
        linkedUserId: UUID? = nil,
        createdByParentId: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.familyId = familyId
        self.displayName = displayName
        self.phoneNumber = phoneNumber
        self.linkedUserId = linkedUserId
        self.createdByParentId = createdByParentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ChildInviteStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case accepted
    case expired
    case revoked

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pending:
            return "Pending"
        case .accepted:
            return "Accepted"
        case .expired:
            return "Expired"
        case .revoked:
            return "Revoked"
        }
    }
}

public struct ChildInvite: Identifiable, Codable, Equatable {
    public var id: UUID
    public var familyId: UUID
    public var childProfileId: UUID
    public var childName: String
    public var phoneNumber: String?
    public var createdByParentId: UUID
    public var token: String
    public var inviteURL: URL
    public var status: ChildInviteStatus
    public var createdAt: Date
    public var expiresAt: Date
    public var acceptedAt: Date?
    public var acceptedChildUserId: UUID?

    public init(
        id: UUID = UUID(),
        familyId: UUID,
        childProfileId: UUID,
        childName: String,
        phoneNumber: String? = nil,
        createdByParentId: UUID,
        token: String,
        inviteURL: URL,
        status: ChildInviteStatus = .pending,
        createdAt: Date = Date(),
        expiresAt: Date,
        acceptedAt: Date? = nil,
        acceptedChildUserId: UUID? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.childProfileId = childProfileId
        self.childName = childName
        self.phoneNumber = phoneNumber
        self.createdByParentId = createdByParentId
        self.token = token
        self.inviteURL = inviteURL
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.acceptedAt = acceptedAt
        self.acceptedChildUserId = acceptedChildUserId
    }

    public func resolvedStatus(now: Date = Date()) -> ChildInviteStatus {
        if status == .pending, expiresAt <= now {
            return .expired
        }

        return status
    }
}

public enum ParentInviteStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case accepted
    case expired
    case revoked

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pending:
            return "Pending"
        case .accepted:
            return "Accepted"
        case .expired:
            return "Expired"
        case .revoked:
            return "Revoked"
        }
    }
}

public struct ParentInvite: Identifiable, Codable, Equatable {
    public var id: UUID
    public var familyId: UUID
    public var parentName: String
    public var phoneNumber: String?
    public var createdByParentId: UUID
    public var token: String
    public var inviteURL: URL
    public var status: ParentInviteStatus
    public var createdAt: Date
    public var expiresAt: Date
    public var acceptedAt: Date?
    public var acceptedParentUserId: UUID?

    public init(
        id: UUID = UUID(),
        familyId: UUID,
        parentName: String,
        phoneNumber: String? = nil,
        createdByParentId: UUID,
        token: String,
        inviteURL: URL,
        status: ParentInviteStatus = .pending,
        createdAt: Date = Date(),
        expiresAt: Date,
        acceptedAt: Date? = nil,
        acceptedParentUserId: UUID? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.parentName = parentName
        self.phoneNumber = phoneNumber
        self.createdByParentId = createdByParentId
        self.token = token
        self.inviteURL = inviteURL
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.acceptedAt = acceptedAt
        self.acceptedParentUserId = acceptedParentUserId
    }

    public func resolvedStatus(now: Date = Date()) -> ParentInviteStatus {
        if status == .pending, expiresAt <= now {
            return .expired
        }

        return status
    }
}

public enum LedgerEntryType: String, Codable, CaseIterable, Identifiable {
    case weeklyBase = "weekly_base"
    case deduction
    case bonus
    case adjustment

    public var id: String { rawValue }
}

public enum AllowanceCadence: String, Codable, CaseIterable, Identifiable {
    case weekly
    case everyTwoWeeks = "every_two_weeks"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .everyTwoWeeks:
            return "Every 2 weeks"
        }
    }

    public var periodTitle: String {
        switch self {
        case .weekly:
            return "This Week"
        case .everyTwoWeeks:
            return "This Pay Period"
        }
    }

    public var intervalDays: Int {
        switch self {
        case .weekly:
            return 7
        case .everyTwoWeeks:
            return 14
        }
    }
}

public enum AllowanceWeekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .sunday:
            return "Sunday"
        case .monday:
            return "Monday"
        case .tuesday:
            return "Tuesday"
        case .wednesday:
            return "Wednesday"
        case .thursday:
            return "Thursday"
        case .friday:
            return "Friday"
        case .saturday:
            return "Saturday"
        }
    }
}

public struct AllowanceSettings: Codable, Equatable {
    public var familyId: UUID
    public var baseAllowanceCents: Int
    public var cadence: AllowanceCadence
    public var allowanceWeekday: AllowanceWeekday
    public var nextAllowanceDate: Date

    public init(
        familyId: UUID,
        baseAllowanceCents: Int,
        cadence: AllowanceCadence = .weekly,
        allowanceWeekday: AllowanceWeekday = .friday,
        nextAllowanceDate: Date
    ) {
        self.familyId = familyId
        self.baseAllowanceCents = baseAllowanceCents
        self.cadence = cadence
        self.allowanceWeekday = allowanceWeekday
        self.nextAllowanceDate = nextAllowanceDate
    }

    public func nextScheduledAllowanceDate(after date: Date = Date(), calendar: Calendar = .current) -> Date {
        let anchor = calendar.startOfDay(for: nextAllowanceDate)
        let today = calendar.startOfDay(for: date)

        guard anchor < today else {
            return anchor
        }

        let elapsedDays = calendar.dateComponents([.day], from: anchor, to: today).day ?? 0
        let intervalsElapsed = elapsedDays / cadence.intervalDays
        let candidate = calendar.date(
            byAdding: .day,
            value: intervalsElapsed * cadence.intervalDays,
            to: anchor
        ) ?? anchor

        if candidate >= today {
            return candidate
        }

        return calendar.date(byAdding: .day, value: cadence.intervalDays, to: candidate) ?? today
    }

    public func withWeekday(_ weekday: AllowanceWeekday, calendar: Calendar = .current) -> AllowanceSettings {
        var updated = self
        updated.allowanceWeekday = weekday

        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nextAllowanceDate)
        components.weekday = weekday.rawValue
        if let date = calendar.date(from: components) {
            updated.nextAllowanceDate = date
        }
        return updated
    }
}

public struct LedgerEntry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var weekId: UUID
    public var type: LedgerEntryType
    public var title: String
    public var amountCents: Int
    public var relatedOccurrenceId: UUID?
    public var note: String?
    public var isVoided: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        weekId: UUID,
        type: LedgerEntryType,
        title: String,
        amountCents: Int,
        relatedOccurrenceId: UUID? = nil,
        note: String? = nil,
        isVoided: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.weekId = weekId
        self.type = type
        self.title = title
        self.amountCents = amountCents
        self.relatedOccurrenceId = relatedOccurrenceId
        self.note = note
        self.isVoided = isVoided
        self.createdAt = createdAt
    }
}

public enum TaskOccurrenceStatus: String, Codable, CaseIterable, Identifiable {
    case upcoming
    case due
    case submitted
    case aiReviewed = "ai_reviewed"
    case approved
    case rejected
    case missed
    case excused

    public var id: String { rawValue }

    public var isOpen: Bool {
        switch self {
        case .upcoming, .due:
            return true
        case .submitted, .aiReviewed, .approved, .rejected, .missed, .excused:
            return false
        }
    }

    public var needsParentReview: Bool {
        switch self {
        case .submitted, .aiReviewed, .missed, .rejected:
            return true
        case .upcoming, .due, .approved, .excused:
            return false
        }
    }
}

public enum VerificationMode: String, Codable, CaseIterable, Identifiable {
    case photoRequired = "photo_required"
    case photoOptional = "photo_optional"
    case parentOnly = "parent_only"
    case noVerification = "no_verification"

    public var id: String { rawValue }
}

public struct ChoreDefinition: Identifiable, Codable, Equatable {
    public var id: UUID
    public var familyId: UUID
    public var childId: UUID
    public var title: String
    public var shortTitle: String
    public var description: String
    public var instructions: String
    public var expectedEvidence: String
    public var deductionCents: Int
    public var verificationMode: VerificationMode
    public var dueTime: String
    public var dueWindowMinutes: Int
    public var reminderOffsetsMinutes: [Int]
    public var isPaused: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        familyId: UUID,
        childId: UUID,
        title: String,
        shortTitle: String,
        description: String,
        instructions: String,
        expectedEvidence: String,
        deductionCents: Int,
        verificationMode: VerificationMode = .photoRequired,
        dueTime: String,
        dueWindowMinutes: Int = 90,
        reminderOffsetsMinutes: [Int] = [15, 0],
        isPaused: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.title = title
        self.shortTitle = shortTitle
        self.description = description
        self.instructions = instructions
        self.expectedEvidence = expectedEvidence
        self.deductionCents = deductionCents
        self.verificationMode = verificationMode
        self.dueTime = dueTime
        self.dueWindowMinutes = dueWindowMinutes
        self.reminderOffsetsMinutes = reminderOffsetsMinutes
        self.isPaused = isPaused
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TaskOccurrence: Identifiable, Codable, Equatable {
    public var id: UUID
    public var choreDefinitionId: UUID
    public var childId: UUID
    public var weekId: UUID
    public var scheduledAt: Date
    public var dueAt: Date
    public var expiresAt: Date
    public var status: TaskOccurrenceStatus
    public var submissionId: UUID?
    public var deductionLedgerEntryId: UUID?
    public var excuseReason: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        choreDefinitionId: UUID,
        childId: UUID,
        weekId: UUID,
        scheduledAt: Date,
        dueAt: Date,
        expiresAt: Date,
        status: TaskOccurrenceStatus,
        submissionId: UUID? = nil,
        deductionLedgerEntryId: UUID? = nil,
        excuseReason: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.choreDefinitionId = choreDefinitionId
        self.childId = childId
        self.weekId = weekId
        self.scheduledAt = scheduledAt
        self.dueAt = dueAt
        self.expiresAt = expiresAt
        self.status = status
        self.submissionId = submissionId
        self.deductionLedgerEntryId = deductionLedgerEntryId
        self.excuseReason = excuseReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AIReviewResult: Codable, Equatable {
    public var completed: Bool?
    public var confidence: Double
    public var reason: String
    public var retakeSuggested: Bool
    public var retakeInstruction: String?
    public var modelName: String?
    public var reviewedAt: Date

    public init(
        completed: Bool?,
        confidence: Double,
        reason: String,
        retakeSuggested: Bool,
        retakeInstruction: String? = nil,
        modelName: String? = "mock-local-reviewer",
        reviewedAt: Date = Date()
    ) {
        self.completed = completed
        self.confidence = confidence
        self.reason = reason
        self.retakeSuggested = retakeSuggested
        self.retakeInstruction = retakeInstruction
        self.modelName = modelName
        self.reviewedAt = reviewedAt
    }
}

public struct ChoreSubmission: Identifiable, Codable, Equatable {
    public var id: UUID
    public var taskOccurrenceId: UUID
    public var childId: UUID
    public var imageName: String
    public var submittedAt: Date
    public var aiResult: AIReviewResult?
    public var parentDecision: ParentDecision?

    public init(
        id: UUID = UUID(),
        taskOccurrenceId: UUID,
        childId: UUID,
        imageName: String,
        submittedAt: Date = Date(),
        aiResult: AIReviewResult? = nil,
        parentDecision: ParentDecision? = nil
    ) {
        self.id = id
        self.taskOccurrenceId = taskOccurrenceId
        self.childId = childId
        self.imageName = imageName
        self.submittedAt = submittedAt
        self.aiResult = aiResult
        self.parentDecision = parentDecision
    }
}

public struct ParentDecision: Codable, Equatable {
    public enum Decision: String, Codable {
        case approved
        case rejected
        case excused
        case retakeRequested = "retake_requested"
    }

    public var decision: Decision
    public var note: String?
    public var decidedAt: Date
    public var parentId: UUID

    public init(decision: Decision, note: String? = nil, decidedAt: Date = Date(), parentId: UUID) {
        self.decision = decision
        self.note = note
        self.decidedAt = decidedAt
        self.parentId = parentId
    }
}

public struct SeedSnapshot {
    public var familyId: UUID
    public var parentId: UUID
    public var childId: UUID
    public var weekId: UUID
    public var familyName: String
    public var childName: String
    public var parentName: String
    public var weeklyAllowanceCents: Int
    public var allowanceSettings: AllowanceSettings
    public var members: [FamilyMember]
    public var childProfiles: [ChildProfile]
    public var childInvites: [ChildInvite]
    public var parentInvites: [ParentInvite]
    public var chores: [ChoreDefinition]
    public var occurrences: [TaskOccurrence]
    public var submissions: [ChoreSubmission]
    public var ledger: [LedgerEntry]
}
