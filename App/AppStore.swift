import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var chores: [ChoreDefinition]
    @Published var occurrences: [TaskOccurrence]
    @Published var submissions: [ChoreSubmission]
    @Published var ledger: [LedgerEntry]

    let familyId: UUID
    let parentId: UUID
    let childId: UUID
    let weekId: UUID
    let childName: String
    let parentName: String

    init(snapshot: SeedSnapshot = SeedData.snapshot()) {
        self.familyId = snapshot.familyId
        self.parentId = snapshot.parentId
        self.childId = snapshot.childId
        self.weekId = snapshot.weekId
        self.childName = snapshot.childName
        self.parentName = snapshot.parentName
        self.chores = snapshot.chores
        self.occurrences = snapshot.occurrences
        self.submissions = snapshot.submissions
        self.ledger = snapshot.ledger
    }

    var allowanceSummary: AllowanceSummary {
        AllowanceEngine.summary(for: ledger)
    }

    var todayOccurrences: [TaskOccurrence] {
        occurrences.sorted {
            if $0.status == $1.status {
                return $0.dueAt < $1.dueAt
            }
            return urgencyRank($0.status) < urgencyRank($1.status)
        }
    }

    var remainingCount: Int {
        occurrences.filter { $0.status == .upcoming || $0.status == .due }.count
    }

    var pendingReviewOccurrences: [TaskOccurrence] {
        occurrences.filter { $0.status.needsParentReview }
    }

    var nextDueOccurrence: TaskOccurrence? {
        occurrences
            .filter { $0.status == .upcoming || $0.status == .due }
            .sorted { $0.dueAt < $1.dueAt }
            .first
    }

    func chore(for occurrence: TaskOccurrence) -> ChoreDefinition {
        chores.first { $0.id == occurrence.choreDefinitionId } ?? chores[0]
    }

    func chore(id: UUID) -> ChoreDefinition? {
        chores.first { $0.id == id }
    }

    func submission(for occurrence: TaskOccurrence) -> ChoreSubmission? {
        submissions.first { $0.taskOccurrenceId == occurrence.id }
    }

    func submitEvidence(for occurrenceId: UUID) {
        guard let index = occurrences.firstIndex(where: { $0.id == occurrenceId }) else {
            return
        }

        let chore = chore(for: occurrences[index])
        let result = mockAIResult(for: chore)
        let submission = ChoreSubmission(
            taskOccurrenceId: occurrenceId,
            childId: childId,
            imageName: "mock-\(chore.shortTitle.lowercased().replacingOccurrences(of: " ", with: "-"))",
            aiResult: result
        )

        submissions.append(submission)
        occurrences[index].submissionId = submission.id
        occurrences[index].status = .aiReviewed
        occurrences[index].updatedAt = Date()
    }

    func approve(_ occurrence: TaskOccurrence) {
        updateOccurrence(occurrence.id) { task in
            task.status = .approved
            task.updatedAt = Date()
        }
        decideSubmission(for: occurrence, decision: .approved)
        ledger = AllowanceEngine.voidingDeduction(in: ledger, for: occurrence.id)
    }

    func reject(_ occurrence: TaskOccurrence) {
        let chore = chore(for: occurrence)
        updateOccurrence(occurrence.id) { task in
            task.status = .rejected
            task.updatedAt = Date()
        }
        decideSubmission(for: occurrence, decision: .rejected)
        addDeductionIfNeeded(for: occurrence, chore: chore)
    }

    func excuse(_ occurrence: TaskOccurrence, reason: String? = nil) {
        updateOccurrence(occurrence.id) { task in
            task.status = .excused
            task.excuseReason = reason
            task.updatedAt = Date()
        }
        decideSubmission(for: occurrence, decision: .excused, note: reason)
        ledger = AllowanceEngine.voidingDeduction(in: ledger, for: occurrence.id)
    }

    func requestRetake(_ occurrence: TaskOccurrence) {
        updateOccurrence(occurrence.id) { task in
            task.status = .due
            task.updatedAt = Date()
        }
        decideSubmission(for: occurrence, decision: .retakeRequested, note: "Please send one clearer photo.")
    }

    func requestExcuse(_ occurrence: TaskOccurrence) {
        updateOccurrence(occurrence.id) { task in
            task.status = .submitted
            task.excuseReason = "Child asked for a parent check."
            task.updatedAt = Date()
        }
    }

    func markMissed(_ occurrence: TaskOccurrence) {
        let chore = chore(for: occurrence)
        updateOccurrence(occurrence.id) { task in
            task.status = .missed
            task.updatedAt = Date()
        }
        addDeductionIfNeeded(for: occurrence, chore: chore)
    }

    func addBonus(title: String, amountCents: Int, note: String?) {
        ledger.append(
            AllowanceEngine.bonusEntry(
                weekId: weekId,
                title: title,
                amountCents: amountCents,
                note: note
            )
        )
    }

    func updateChore(_ chore: ChoreDefinition, title: String, deductionCents: Int, dueTime: String) {
        guard let index = chores.firstIndex(where: { $0.id == chore.id }) else {
            return
        }

        chores[index].title = title
        chores[index].deductionCents = deductionCents
        chores[index].dueTime = dueTime
        chores[index].updatedAt = Date()
    }

    private func updateOccurrence(_ id: UUID, mutation: (inout TaskOccurrence) -> Void) {
        guard let index = occurrences.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutation(&occurrences[index])
    }

    private func decideSubmission(for occurrence: TaskOccurrence, decision: ParentDecision.Decision, note: String? = nil) {
        guard let index = submissions.firstIndex(where: { $0.taskOccurrenceId == occurrence.id }) else {
            return
        }

        submissions[index].parentDecision = ParentDecision(
            decision: decision,
            note: note,
            parentId: parentId
        )
    }

    private func addDeductionIfNeeded(for occurrence: TaskOccurrence, chore: ChoreDefinition) {
        guard !AllowanceEngine.deductionExists(in: ledger, for: occurrence.id) else {
            return
        }

        let entry = AllowanceEngine.deductionEntry(
            weekId: weekId,
            occurrenceId: occurrence.id,
            choreTitle: chore.title,
            amountCents: chore.deductionCents
        )
        ledger.append(entry)
        updateOccurrence(occurrence.id) { task in
            task.deductionLedgerEntryId = entry.id
        }
    }

    private func mockAIResult(for chore: ChoreDefinition) -> AIReviewResult {
        if chore.title.contains("Bathroom") {
            return AIReviewResult(
                completed: nil,
                confidence: 0.62,
                reason: "The photo is partly clear, but the whole counter is not visible.",
                retakeSuggested: false
            )
        }

        return AIReviewResult(
            completed: true,
            confidence: 0.92,
            reason: "The image appears to show the expected chore evidence.",
            retakeSuggested: false
        )
    }

    private func urgencyRank(_ status: TaskOccurrenceStatus) -> Int {
        switch status {
        case .due:
            return 0
        case .aiReviewed, .submitted:
            return 1
        case .upcoming:
            return 2
        case .missed, .rejected:
            return 3
        case .approved:
            return 4
        case .excused:
            return 5
        }
    }
}
