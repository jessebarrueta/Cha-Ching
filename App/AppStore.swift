import Foundation
import SwiftUI
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class AppStore: ObservableObject {
    @Published var session: AppSession
    @Published var members: [FamilyMember]
    @Published var childProfiles: [ChildProfile]
    @Published var childInvites: [ChildInvite]
    @Published var parentInvites: [ParentInvite]
    @Published var pendingInvite: PendingInvite?
    @Published var inviteAcceptanceState: InviteAcceptanceState
    @Published var inviteCreationState: InviteCreationState
    @Published var chores: [ChoreDefinition]
    @Published var occurrences: [TaskOccurrence]
    @Published var submissions: [ChoreSubmission]
    @Published var ledger: [LedgerEntry]
    @Published var allowanceSettings: AllowanceSettings
    @Published var notificationState: NotificationState

    private let inviteAcceptanceService: InviteAcceptanceServicing
    private let remoteStore: SupabaseRemoteStore
    private let settingsStore: UserDefaults
    private let allowanceSettingsKey = "chaching.allowanceSettings"

    let familyId: UUID
    let parentId: UUID
    let childId: UUID
    let weekId: UUID
    let familyName: String
    let childName: String
    let parentName: String

    init(
        snapshot: SeedSnapshot = SeedData.snapshot(),
        inviteAcceptanceService: InviteAcceptanceServicing = SupabaseInviteAcceptanceService(),
        remoteStore: SupabaseRemoteStore = SupabaseRemoteStore(),
        settingsStore: UserDefaults = .standard
    ) {
        self.familyId = snapshot.familyId
        self.parentId = snapshot.parentId
        self.childId = snapshot.childId
        self.weekId = snapshot.weekId
        self.familyName = snapshot.familyName
        self.childName = snapshot.childName
        self.parentName = snapshot.parentName
        self.inviteAcceptanceService = inviteAcceptanceService
        self.remoteStore = remoteStore
        self.settingsStore = settingsStore
        self.session = AppSession(userId: snapshot.parentId, role: .parent, displayName: snapshot.parentName)
        self.members = snapshot.members
        self.childProfiles = snapshot.childProfiles
        self.childInvites = snapshot.childInvites
        self.parentInvites = snapshot.parentInvites
        self.pendingInvite = nil
        self.inviteAcceptanceState = .idle
        self.inviteCreationState = .idle
        self.chores = snapshot.chores
        self.occurrences = snapshot.occurrences
        self.submissions = snapshot.submissions
        self.ledger = snapshot.ledger
        self.allowanceSettings = Self.loadAllowanceSettings(from: settingsStore, key: allowanceSettingsKey) ?? snapshot.allowanceSettings
        self.notificationState = .idle
        publishWidgetSnapshot()
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

    var allowancePeriodTitle: String {
        allowanceSettings.cadence.periodTitle
    }

    var nextAllowanceDate: Date {
        allowanceSettings.nextScheduledAllowanceDate()
    }

    var allowanceRequestMessage: String {
        let amount = Money.dollars(allowanceSummary.currentTotalCents)
        if allowanceSummary.hasRolloverDebt {
            return "Hi \(parentName), my \(AppBrand.displayName) allowance closed at $0.00 this period. I will start next period reduced by \(Money.dollars(allowanceSummary.rolloverDebtCents))."
        }

        return "Hi \(parentName), I finished my \(AppBrand.displayName) chores and earned \(amount). Can you send my allowance when you have a chance?"
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

    func createChildInvite(childName: String, phoneNumber: String?) async {
        let trimmedName = childName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let normalizedPhone = phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usablePhone = normalizedPhone?.isEmpty == false ? normalizedPhone : nil
        let childProfileId = upsertChildProfile(named: trimmedName, phoneNumber: usablePhone)
        let token = makeInviteToken(for: trimmedName, prefix: "child")
        let now = Date()
        let expiresAt = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        let invite = ChildInvite(
            familyId: familyId,
            childProfileId: childProfileId,
            childName: trimmedName,
            phoneNumber: usablePhone,
            createdByParentId: parentId,
            token: token,
            inviteURL: AppBrand.inviteURL(token: token),
            createdAt: now,
            expiresAt: expiresAt
        )

        inviteCreationState = .creating
        childInvites.insert(invite, at: 0)

        do {
            let profileRecord = try await remoteStore.upsertChildProfile(
                id: childProfileId,
                familyId: familyId,
                displayName: trimmedName,
                phoneNumber: usablePhone,
                createdByParentId: nil
            )
            applyChildProfileRecord(profileRecord)

            let inviteRecord = try await remoteStore.createChildInvite(
                id: invite.id,
                familyId: familyId,
                childProfileId: childProfileId,
                childName: trimmedName,
                phoneNumber: usablePhone,
                createdByParentId: nil,
                token: token,
                expiresAt: expiresAt
            )
            applyChildInviteRecord(inviteRecord, token: token)
            inviteCreationState = .synced("Child invite synced with Supabase.")
        } catch {
            inviteCreationState = .localOnly("Invite is ready to share here. Supabase sync needs parent sign-in.")
            debugPrint("Child invite sync failed:", error.localizedDescription)
        }
    }

    func createParentInvite(parentName: String, phoneNumber: String?) async {
        let trimmedName = parentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        let normalizedPhone = phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usablePhone = normalizedPhone?.isEmpty == false ? normalizedPhone : nil
        let token = makeInviteToken(for: trimmedName, prefix: "parent")
        let now = Date()
        let expiresAt = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        let invite = ParentInvite(
            familyId: familyId,
            parentName: trimmedName,
            phoneNumber: usablePhone,
            createdByParentId: session.userId,
            token: token,
            inviteURL: AppBrand.inviteURL(token: token),
            createdAt: now,
            expiresAt: expiresAt
        )

        inviteCreationState = .creating
        parentInvites.insert(invite, at: 0)

        do {
            let inviteRecord = try await remoteStore.createParentInvite(
                id: invite.id,
                familyId: familyId,
                parentName: trimmedName,
                phoneNumber: usablePhone,
                createdByParentId: nil,
                token: token,
                expiresAt: expiresAt
            )
            applyParentInviteRecord(inviteRecord, token: token)
            inviteCreationState = .synced("Parent invite synced with Supabase.")
        } catch {
            inviteCreationState = .localOnly("Invite is ready to share here. Supabase sync needs parent sign-in.")
            debugPrint("Parent invite sync failed:", error.localizedDescription)
        }
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

    func submitEvidence(for occurrenceId: UUID, jpegData: Data? = nil) async {
        if let jpegData {
            do {
                try await submitRemoteEvidence(for: occurrenceId, jpegData: jpegData)
                return
            } catch {
                debugPrint("Remote evidence submission failed:", error.localizedDescription)
            }
        }

        submitMockEvidence(for: occurrenceId)
    }

    private func submitRemoteEvidence(for occurrenceId: UUID, jpegData: Data) async throws {
        guard let index = occurrences.firstIndex(where: { $0.id == occurrenceId }) else {
            return
        }

        let submissionId = UUID()
        let occurrence = occurrences[index]
        let imagePath = try await remoteStore.uploadEvidenceJPEG(
            familyId: familyId,
            occurrenceId: occurrenceId,
            submissionId: submissionId,
            jpegData: jpegData
        )

        _ = try await remoteStore.createChoreSubmission(
            id: submissionId,
            occurrenceId: occurrenceId,
            childId: occurrence.childId,
            imagePath: imagePath
        )

        let reviewResponse = try await remoteStore.reviewEvidence(submissionId: submissionId)
        let submission = ChoreSubmission(
            id: reviewResponse.submissionId,
            taskOccurrenceId: reviewResponse.taskOccurrenceId,
            childId: occurrence.childId,
            imageName: imagePath,
            aiResult: reviewResponse.aiResult.localResult
        )

        upsertSubmission(submission)
        occurrences[index].submissionId = submission.id
        occurrences[index].status = .aiReviewed
        occurrences[index].updatedAt = Date()
        publishWidgetSnapshot()
    }

    private func submitMockEvidence(for occurrenceId: UUID) {
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

        upsertSubmission(submission)
        occurrences[index].submissionId = submission.id
        occurrences[index].status = .aiReviewed
        occurrences[index].updatedAt = Date()
        publishWidgetSnapshot()
    }

    func approve(_ occurrence: TaskOccurrence) {
        updateOccurrence(occurrence.id) { task in
            task.status = .approved
            task.updatedAt = Date()
        }
        decideSubmission(for: occurrence, decision: .approved)
        ledger = AllowanceEngine.voidingDeduction(in: ledger, for: occurrence.id)
        publishWidgetSnapshot()
    }

    func reject(_ occurrence: TaskOccurrence) {
        let chore = chore(for: occurrence)
        updateOccurrence(occurrence.id) { task in
            task.status = .rejected
            task.updatedAt = Date()
        }
        decideSubmission(for: occurrence, decision: .rejected)
        addDeductionIfNeeded(for: occurrence, chore: chore)
        publishWidgetSnapshot()
    }

    func excuse(_ occurrence: TaskOccurrence, reason: String? = nil) {
        updateOccurrence(occurrence.id) { task in
            task.status = .excused
            task.excuseReason = reason
            task.updatedAt = Date()
        }
        decideSubmission(for: occurrence, decision: .excused, note: reason)
        ledger = AllowanceEngine.voidingDeduction(in: ledger, for: occurrence.id)
        publishWidgetSnapshot()
    }

    func requestRetake(_ occurrence: TaskOccurrence) {
        updateOccurrence(occurrence.id) { task in
            task.status = .due
            task.updatedAt = Date()
        }
        decideSubmission(for: occurrence, decision: .retakeRequested, note: "Please send one clearer photo.")
        publishWidgetSnapshot()
    }

    func requestExcuse(_ occurrence: TaskOccurrence) {
        updateOccurrence(occurrence.id) { task in
            task.status = .submitted
            task.excuseReason = "Child asked for a parent check."
            task.updatedAt = Date()
        }
        publishWidgetSnapshot()
    }

    func markMissed(_ occurrence: TaskOccurrence) {
        let chore = chore(for: occurrence)
        updateOccurrence(occurrence.id) { task in
            task.status = .missed
            task.updatedAt = Date()
        }
        addDeductionIfNeeded(for: occurrence, chore: chore)
        publishWidgetSnapshot()
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
        publishWidgetSnapshot()
    }

    func updateAllowanceSettings(
        cadence: AllowanceCadence,
        allowanceWeekday: AllowanceWeekday,
        nextAllowanceDate: Date
    ) {
        allowanceSettings.cadence = cadence
        allowanceSettings.allowanceWeekday = allowanceWeekday
        allowanceSettings.nextAllowanceDate = Calendar.current.startOfDay(for: nextAllowanceDate)
        saveAllowanceSettings()
        publishWidgetSnapshot()

        Task {
            await refreshNotificationScheduleIfAuthorized()
        }
    }

    func enableLocalNotifications() async {
        notificationState = .requesting

        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])

            guard granted else {
                notificationState = .denied
                return
            }

            try await scheduleLocalNotifications()
            notificationState = .scheduled
        } catch {
            notificationState = .failed(error.localizedDescription)
        }
    }

    func refreshNotificationScheduleIfAuthorized() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        do {
            try await scheduleLocalNotifications()
            notificationState = .scheduled
        } catch {
            notificationState = .failed(error.localizedDescription)
        }
    }

    private func scheduleLocalNotifications() async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: localNotificationIdentifiers())

        for chore in chores where !chore.isPaused {
            guard let dueDate = Self.dateToday(for: chore.dueTime) else {
                continue
            }

            for offset in chore.reminderOffsetsMinutes {
                guard let fireDate = Calendar.current.date(byAdding: .minute, value: -offset, to: dueDate) else {
                    continue
                }

                var components = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
                components.second = 0

                let content = UNMutableNotificationContent()
                content.title = offset > 0 ? "Chore due soon" : "Chore due now"
                content.body = offset > 0
                    ? "\(chore.title) is due in \(offset) minutes."
                    : "\(chore.title) is due now."
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(
                    identifier: choreNotificationIdentifier(choreId: chore.id, offsetMinutes: offset),
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
            }
        }

        let allowanceDate = nextAllowanceDate
        var allowanceComponents: DateComponents
        if allowanceSettings.cadence == .weekly {
            allowanceComponents = Calendar.current.dateComponents([.weekday], from: allowanceDate)
        } else {
            allowanceComponents = Calendar.current.dateComponents([.year, .month, .day], from: allowanceDate)
        }
        allowanceComponents.hour = 9
        allowanceComponents.minute = 0
        allowanceComponents.second = 0

        let allowanceContent = UNMutableNotificationContent()
        allowanceContent.title = "Allowance day"
        allowanceContent.body = "\(childName)'s \(AppBrand.displayName) total is ready to review."
        allowanceContent.sound = .default

        let allowanceTrigger = UNCalendarNotificationTrigger(
            dateMatching: allowanceComponents,
            repeats: allowanceSettings.cadence == .weekly
        )
        let allowanceRequest = UNNotificationRequest(
            identifier: allowanceNotificationIdentifier,
            content: allowanceContent,
            trigger: allowanceTrigger
        )
        try await center.add(allowanceRequest)
    }

    private func localNotificationIdentifiers() -> [String] {
        var identifiers = chores.flatMap { chore in
            chore.reminderOffsetsMinutes.map {
                choreNotificationIdentifier(choreId: chore.id, offsetMinutes: $0)
            }
        }
        identifiers.append(allowanceNotificationIdentifier)
        return identifiers
    }

    private var allowanceNotificationIdentifier: String {
        "chaching.allowance.\(familyId.uuidString)"
    }

    private func choreNotificationIdentifier(choreId: UUID, offsetMinutes: Int) -> String {
        "chaching.chore.\(choreId.uuidString).offset.\(offsetMinutes)"
    }

    func updateChore(_ chore: ChoreDefinition, title: String, deductionCents: Int, dueTime: String) {
        guard let index = chores.firstIndex(where: { $0.id == chore.id }) else {
            return
        }

        chores[index].title = title
        chores[index].deductionCents = deductionCents
        chores[index].dueTime = dueTime
        chores[index].updatedAt = Date()
        publishWidgetSnapshot()

        Task {
            await refreshNotificationScheduleIfAuthorized()
        }
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

    private func upsertSubmission(_ submission: ChoreSubmission) {
        if let index = submissions.firstIndex(where: { $0.id == submission.id }) {
            submissions[index] = submission
        } else if let index = submissions.firstIndex(where: { $0.taskOccurrenceId == submission.taskOccurrenceId }) {
            submissions[index] = submission
        } else {
            submissions.append(submission)
        }
    }

    private func applyChildProfileRecord(_ record: ChildProfileRecord) {
        let profile = ChildProfile(
            id: record.id,
            familyId: record.familyId,
            displayName: record.displayName,
            phoneNumber: record.phoneE164,
            linkedUserId: record.linkedUserId,
            createdByParentId: record.createdByParentId ?? parentId,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )

        if let index = childProfiles.firstIndex(where: { $0.id == record.id }) {
            childProfiles[index] = profile
        } else {
            childProfiles.append(profile)
        }
    }

    private func applyChildInviteRecord(_ record: ChildInviteRecord, token: String) {
        let invite = ChildInvite(
            id: record.id,
            familyId: record.familyId,
            childProfileId: record.childProfileId,
            childName: record.childName,
            phoneNumber: record.phoneE164,
            createdByParentId: record.createdByParentId ?? parentId,
            token: token,
            inviteURL: AppBrand.inviteURL(token: token),
            status: ChildInviteStatus(rawValue: record.status) ?? .pending,
            createdAt: record.createdAt,
            expiresAt: record.expiresAt,
            acceptedAt: record.acceptedAt,
            acceptedChildUserId: record.acceptedChildUserId
        )

        if let index = childInvites.firstIndex(where: { $0.id == record.id }) {
            childInvites[index] = invite
        } else {
            childInvites.insert(invite, at: 0)
        }
    }

    private func applyParentInviteRecord(_ record: ParentInviteRecord, token: String) {
        let invite = ParentInvite(
            id: record.id,
            familyId: record.familyId,
            parentName: record.parentName,
            phoneNumber: record.phoneE164,
            createdByParentId: record.createdByParentId ?? parentId,
            token: token,
            inviteURL: AppBrand.inviteURL(token: token),
            status: ParentInviteStatus(rawValue: record.status) ?? .pending,
            createdAt: record.createdAt,
            expiresAt: record.expiresAt,
            acceptedAt: record.acceptedAt,
            acceptedParentUserId: record.acceptedParentUserId
        )

        if let index = parentInvites.firstIndex(where: { $0.id == record.id }) {
            parentInvites[index] = invite
        } else {
            parentInvites.insert(invite, at: 0)
        }
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

    private static func dateToday(for time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        guard let parsedTime = formatter.date(from: time) else {
            return nil
        }

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: parsedTime)
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        dayComponents.hour = timeComponents.hour
        dayComponents.minute = timeComponents.minute
        return calendar.date(from: dayComponents)
    }

    private static let widgetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static func loadAllowanceSettings(from store: UserDefaults, key: String) -> AllowanceSettings? {
        guard let data = store.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(AllowanceSettings.self, from: data)
    }

    private func saveAllowanceSettings() {
        guard let data = try? JSONEncoder().encode(allowanceSettings) else {
            return
        }

        settingsStore.set(data, forKey: allowanceSettingsKey)
    }

    private func publishWidgetSnapshot() {
        let summary = allowanceSummary
        let nextOccurrence = nextDueOccurrence
        let nextChore = nextOccurrence.map { chore(for: $0) }
        let snapshot = ChaChingWidgetSnapshot(
            updatedAt: Date(),
            periodTitle: allowancePeriodTitle,
            childName: childName,
            currentCents: summary.currentTotalCents,
            baseCents: summary.weeklyBaseCents,
            rolloverDebtCents: summary.rolloverDebtCents,
            choresLeft: remainingCount,
            nextChoreTitle: nextChore?.shortTitle ?? "All done",
            nextChoreTime: nextOccurrence.map { Self.widgetTimeFormatter.string(from: $0.dueAt) } ?? "Nice work"
        )

        guard ChaChingWidgetSharedState.saveSnapshot(snapshot) else {
            return
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: ChaChingWidgetSharedState.widgetKind)
        #endif
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

private extension RemoteAIReviewResult {
    var localResult: AIReviewResult {
        AIReviewResult(
            completed: completed,
            confidence: confidence,
            reason: reason,
            retakeSuggested: retakeSuggested,
            retakeInstruction: retakeInstruction,
            modelName: modelName,
            reviewedAt: reviewedAt
        )
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

enum InviteCreationState: Equatable {
    case idle
    case creating
    case synced(String)
    case localOnly(String)

    var isWorking: Bool {
        if case .creating = self {
            return true
        }
        return false
    }

    var message: String? {
        switch self {
        case .idle, .creating:
            return nil
        case .synced(let message), .localOnly(let message):
            return message
        }
    }

    var iconName: String {
        switch self {
        case .idle, .creating:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.icloud.fill"
        case .localOnly:
            return "icloud.slash.fill"
        }
    }

    var isSynced: Bool {
        if case .synced = self {
            return true
        }
        return false
    }
}

enum NotificationState: Equatable {
    case idle
    case requesting
    case scheduled
    case denied
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "Reminders are not enabled yet."
        case .requesting:
            return "Requesting notification permission..."
        case .scheduled:
            return "Chore and allowance reminders are scheduled."
        case .denied:
            return "Notifications are off. You can enable them in iOS Settings."
        case .failed(let message):
            return message
        }
    }
}
