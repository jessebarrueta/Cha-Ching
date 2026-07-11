import Foundation

public enum LedgerEntryType: String, Codable, CaseIterable, Identifiable {
    case weeklyBase = "weekly_base"
    case deduction
    case bonus
    case adjustment

    public var id: String { rawValue }
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
    public var childName: String
    public var parentName: String
    public var weeklyAllowanceCents: Int
    public var chores: [ChoreDefinition]
    public var occurrences: [TaskOccurrence]
    public var submissions: [ChoreSubmission]
    public var ledger: [LedgerEntry]
}

