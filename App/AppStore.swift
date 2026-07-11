import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var session: AppSession
    @Published var members: [FamilyMember]
    @Published var childProfiles: [ChildProfile]
    @Published var childInvites: [ChildInvite]
    @Published var chores: [ChoreDefinition]
    @Published var occurrences: [TaskOccurrence]
    @Published var submissions: [ChoreSubmission]
    @Published var ledger: [LedgerEntry]

    let familyId: UUID
    let parentId: UUID
    let childId: UUID
    let weekId: UUID
    let familyName: String
    let childName: String
    let parentName: String

    init(snapshot: SeedSnapshot = SeedData.snapshot()) {
        self.familyId = snapshot.familyId
        self.parentId = snapshot.parentId
        self.childId = snapshot.childId
        self.weekId = snapshot.weekId
        self.familyName = snapshot.familyName
        self.childName = snapshot.childName
        self.parentName = snapshot.parentName
        self.session = AppSession(userId: snapshot.parentId, role: .parent, displayName: snapshot.parentName)
        self.members = snapshot.members
        self.childProfiles = snapshot.childProfiles
        self.childInvites = snapshot.childInvites
        self.chores = snapshot.chores
        self.occurrences = snapshot.occurrences
        self.submissions = snapshot.submissions
        self.ledger = snapshot.ledger
    }

    var activeRole: FamilyMemberRole {
        session.role
    }

    var isParentSession: Bool {
        activeRole == .parent
    }

    var isChildSession: Bool {
        activeRole == .child
    }

    var activeChildProfile: ChildProfile? {
        childProfiles.first { $0.id == childId }
    }

    var latestInvite: ChildInvite? {
        childInvites.sorted { $0.createdAt > $1.createdAt }.first
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

    func switchSession(to role: FamilyMemberRole) {
        switch role {
        case .parent:
            session = AppSession(userId: parentId, role: .parent, displayName: parentName)
        case .child:
            session = AppSession(userId: childId, role: .child, displayName: childName)
        }
    }

    func createChildInvite(childName: String, phoneNumber: String?) {
        let trimmedName = childName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let normalizedPhone = phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usablePhone = normalizedPhone?.isEmpty == false ? normalizedPhone : nil
        let childProfileId = upsertChildProfile(named: trimmedName, phoneNumber: usablePhone)
        let token = makeInviteToken(for: trimmedName)
        let now = Date()
        let invite = ChildInvite(
            familyId: familyId,
            childProfileId: childProfileId,
            childName: trimmedName,
            phoneNumber: usablePhone,
            createdByParentId: parentId,
            token: token,
            inviteURL: AppBrand.inviteURL(token: token),
            createdAt: now,
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        )

        childInvites.insert(invite, at: 0)
    }

    func revokeInvite(_ invite: ChildInvite) {
        updateInvite(invite.id) { invite in
            invite.status = .revoked
        }
    }

    func markInviteAccepted(_ invite: ChildInvite) {
        let now = Date()
        updateInvite(invite.id) { invite in
            invite.status = .accepted
            invite.acceptedAt = now
            invite.acceptedChildUserId = childId
        }

        if !members.contains(where: { $0.userId == childId && $0.role == .child }) {
            members.append(
                FamilyMember(
                    familyId: familyId,
                    userId: childId,
                    role: .child,
                    displayName: invite.childName
                )
            )
        }

        updateChildProfile(invite.childProfileId) { profile in
            profile.linkedUserId = childId
            profile.updatedAt = now
        }
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

    private func updateInvite(_ id: UUID, mutation: (inout ChildInvite) -> Void) {
        guard let index = childInvites.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutation(&childInvites[index])
    }

    private func updateChildProfile(_ id: UUID, mutation: (inout ChildProfile) -> Void) {
        guard let index = childProfiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutation(&childProfiles[index])
    }

    private func upsertChildProfile(named childName: String, phoneNumber: String?) -> UUID {
        if let index = childProfiles.firstIndex(where: { $0.displayName.caseInsensitiveCompare(childName) == .orderedSame }) {
            childProfiles[index].phoneNumber = phoneNumber
            childProfiles[index].updatedAt = Date()
            return childProfiles[index].id
        }

        let profile = ChildProfile(
            familyId: familyId,
            displayName: childName,
            phoneNumber: phoneNumber,
            createdByParentId: parentId
        )
        childProfiles.append(profile)
        return profile.id
    }

    private func makeInviteToken(for childName: String) -> String {
        let namePrefix = childName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(12)
        return "\(namePrefix)-\(UUID().uuidString.prefix(8).lowercased())"
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

struct AppSession: Equatable {
    var userId: UUID
    var role: FamilyMemberRole
    var displayName: String
}
