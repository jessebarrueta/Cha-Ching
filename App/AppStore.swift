import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var session: AppSession
    @Published var members: [FamilyMember]
    @Published var childProfiles: [ChildProfile]
    @Published var childInvites: [ChildInvite]
    @Published var parentInvites: [ParentInvite]
    @Published var pendingInvite: PendingInvite?
    @Published var inviteAcceptanceState: InviteAcceptanceState
    @Published var chores: [ChoreDefinition]
    @Published var occurrences: [TaskOccurrence]
    @Published var submissions: [ChoreSubmission]
    @Published var ledger: [LedgerEntry]

    private let inviteAcceptanceService: InviteAcceptanceServicing

    let familyId: UUID
    let parentId: UUID
    let childId: UUID
    let weekId: UUID
    let familyName: String
    let childName: String
    let parentName: String

    init(
        snapshot: SeedSnapshot = SeedData.snapshot(),
        inviteAcceptanceService: InviteAcceptanceServicing = SupabaseInviteAcceptanceService()
    ) {
        self.familyId = snapshot.familyId
        self.parentId = snapshot.parentId
        self.childId = snapshot.childId
        self.weekId = snapshot.weekId
        self.familyName = snapshot.familyName
        self.childName = snapshot.childName
        self.parentName = snapshot.parentName
        self.inviteAcceptanceService = inviteAcceptanceService
        self.session = AppSession(userId: snapshot.parentId, role: .parent, displayName: snapshot.parentName)
        self.members = snapshot.members
        self.childProfiles = snapshot.childProfiles
        self.childInvites = snapshot.childInvites
        self.parentInvites = snapshot.parentInvites
        self.pendingInvite = nil
        self.inviteAcceptanceState = .idle
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

    func handleIncomingURL(_ url: URL) {
        guard let token = inviteToken(from: url) else {
            return
        }

        pendingInvite = PendingInvite(token: token, url: url)
        inviteAcceptanceState = .idle
    }

    func clearPendingInvite() {
        pendingInvite = nil
        inviteAcceptanceState = .idle
    }

    func requestInviteSMSCode(phoneNumber: String) async {
        guard let normalizedPhoneNumber = Self.normalizedPhoneNumber(phoneNumber) else {
            inviteAcceptanceState = .failed(InviteAcceptanceError.invalidPhoneNumber.localizedDescription)
            return
        }

        inviteAcceptanceState = .requestingCode

        do {
            try await inviteAcceptanceService.requestSMSCode(phoneNumber: normalizedPhoneNumber)
            inviteAcceptanceState = .codeSent(phoneNumber: normalizedPhoneNumber)
        } catch {
            inviteAcceptanceState = .failed(error.localizedDescription)
        }
    }

    func acceptPendingInvite(phoneNumber: String, code: String) async {
        guard let pendingInvite else {
            inviteAcceptanceState = .failed(InviteAcceptanceError.missingInvite.localizedDescription)
            return
        }

        guard let normalizedPhoneNumber = Self.normalizedPhoneNumber(phoneNumber) else {
            inviteAcceptanceState = .failed(InviteAcceptanceError.invalidPhoneNumber.localizedDescription)
            return
        }

        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            inviteAcceptanceState = .failed(InviteAcceptanceError.invalidCode.localizedDescription)
            return
        }

        inviteAcceptanceState = .accepting

        do {
            _ = try await inviteAcceptanceService.verifySMSCode(
                phoneNumber: normalizedPhoneNumber,
                code: trimmedCode
            )

            switch pendingInvite.kind {
            case .parent:
                let acceptedInvite = try await inviteAcceptanceService.acceptParentInvite(token: pendingInvite.token)
                applyAcceptedParentInvite(acceptedInvite, token: pendingInvite.token)
                inviteAcceptanceState = .accepted(displayName: acceptedInvite.parentName, role: .parent)
            case .child:
                let acceptedInvite = try await inviteAcceptanceService.acceptChildInvite(token: pendingInvite.token)
                applyAcceptedChildInvite(acceptedInvite, token: pendingInvite.token)
                inviteAcceptanceState = .accepted(displayName: acceptedInvite.childName, role: .child)
            }
        } catch {
            inviteAcceptanceState = .failed(error.localizedDescription)
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
        let token = makeInviteToken(for: trimmedName, prefix: "child")
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

    func createParentInvite(parentName: String, phoneNumber: String?) {
        let trimmedName = parentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let normalizedPhone = phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usablePhone = normalizedPhone?.isEmpty == false ? normalizedPhone : nil
        let token = makeInviteToken(for: trimmedName, prefix: "parent")
        let now = Date()
        let invite = ParentInvite(
            familyId: familyId,
            parentName: trimmedName,
            phoneNumber: usablePhone,
            createdByParentId: session.userId,
            token: token,
            inviteURL: AppBrand.inviteURL(token: token),
            createdAt: now,
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        )

        parentInvites.insert(invite, at: 0)
    }

    func revokeInvite(_ invite: ChildInvite) {
        updateInvite(invite.id) { invite in
            invite.status = .revoked
        }
    }

    func revokeParentInvite(_ invite: ParentInvite) {
        updateParentInvite(invite.id) { invite in
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

    func markParentInviteAccepted(_ invite: ParentInvite) {
        let now = Date()
        let acceptedParentId = UUID()
        updateParentInvite(invite.id) { invite in
            invite.status = .accepted
            invite.acceptedAt = now
            invite.acceptedParentUserId = acceptedParentId
        }

        if !members.contains(where: { $0.userId == acceptedParentId && $0.role == .parent }) {
            members.append(
                FamilyMember(
                    familyId: familyId,
                    userId: acceptedParentId,
                    role: .parent,
                    displayName: invite.parentName
                )
            )
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

    private func updateParentInvite(_ id: UUID, mutation: (inout ParentInvite) -> Void) {
        guard let index = parentInvites.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutation(&parentInvites[index])
    }

    private func updateChildProfile(_ id: UUID, mutation: (inout ChildProfile) -> Void) {
        guard let index = childProfiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutation(&childProfiles[index])
    }

    private func applyAcceptedChildInvite(_ acceptedInvite: AcceptedChildInvite, token: String) {
        let now = Date()

        if let index = childInvites.firstIndex(where: { $0.token == token }) {
            childInvites[index].status = .accepted
            childInvites[index].acceptedAt = now
            childInvites[index].acceptedChildUserId = acceptedInvite.acceptedChildUserId
        }

        if let index = childProfiles.firstIndex(where: { $0.id == acceptedInvite.childProfileId }) {
            childProfiles[index].linkedUserId = acceptedInvite.acceptedChildUserId
            childProfiles[index].updatedAt = now
        } else {
            childProfiles.append(
                ChildProfile(
                    id: acceptedInvite.childProfileId,
                    familyId: acceptedInvite.familyId,
                    displayName: acceptedInvite.childName,
                    linkedUserId: acceptedInvite.acceptedChildUserId,
                    createdByParentId: parentId,
                    updatedAt: now
                )
            )
        }

        if !members.contains(where: { $0.userId == acceptedInvite.acceptedChildUserId && $0.role == .child }) {
            members.append(
                FamilyMember(
                    familyId: acceptedInvite.familyId,
                    userId: acceptedInvite.acceptedChildUserId,
                    role: .child,
                    displayName: acceptedInvite.childName
                )
            )
        }

        session = AppSession(
            userId: acceptedInvite.acceptedChildUserId,
            role: .child,
            displayName: acceptedInvite.childName
        )
    }

    private func applyAcceptedParentInvite(_ acceptedInvite: AcceptedParentInvite, token: String) {
        let now = Date()

        if let index = parentInvites.firstIndex(where: { $0.token == token }) {
            parentInvites[index].status = .accepted
            parentInvites[index].acceptedAt = now
            parentInvites[index].acceptedParentUserId = acceptedInvite.acceptedParentUserId
        }

        if !members.contains(where: { $0.userId == acceptedInvite.acceptedParentUserId && $0.role == .parent }) {
            members.append(
                FamilyMember(
                    familyId: acceptedInvite.familyId,
                    userId: acceptedInvite.acceptedParentUserId,
                    role: .parent,
                    displayName: acceptedInvite.parentName
                )
            )
        }

        session = AppSession(
            userId: acceptedInvite.acceptedParentUserId,
            role: .parent,
            displayName: acceptedInvite.parentName
        )
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

    private func makeInviteToken(for inviteeName: String, prefix: String) -> String {
        let namePrefix = inviteeName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(12)
        return "\(prefix)-\(namePrefix)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func inviteToken(from url: URL) -> String? {
        guard url.host == "enormousbrain.com" else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 3,
              pathComponents[0] == "cha-ching",
              pathComponents[1] == "invite" else {
            return nil
        }

        let token = pathComponents[2].trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private static func normalizedPhoneNumber(_ rawValue: String) -> String? {
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

struct PendingInvite: Identifiable, Equatable {
    var token: String
    var url: URL

    var id: String { token }

    var kind: PendingInviteKind {
        token.hasPrefix("parent-") ? .parent : .child
    }
}

enum PendingInviteKind: Equatable {
    case child
    case parent
}

enum InviteAcceptanceState: Equatable {
    case idle
    case requestingCode
    case codeSent(phoneNumber: String)
    case accepting
    case accepted(displayName: String, role: FamilyMemberRole)
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .requestingCode, .accepting:
            return true
        case .idle, .codeSent, .accepted, .failed:
            return false
        }
    }

    var errorMessage: String? {
        if case .failed(let message) = self {
            return message
        }
        return nil
    }

    var acceptedDisplayName: String? {
        if case .accepted(let displayName, _) = self {
            return displayName
        }
        return nil
    }

    var acceptedRole: FamilyMemberRole? {
        if case .accepted(_, let role) = self {
            return role
        }
        return nil
    }
}
