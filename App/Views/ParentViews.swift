import SwiftUI

struct ParentWorkspaceView: View {
    @State private var selectedTab: ParentTab = .review

    var body: some View {
        VStack(spacing: 0) {
            Picker("Parent section", selection: $selectedTab) {
                ForEach(ParentTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)

            if selectedTab == .review {
                ParentReviewQueueView()
            } else if selectedTab == .chores {
                ChoreManagementView()
            } else {
                FamilyManagementView()
            }
        }
        .background(Color.paperWhite.ignoresSafeArea())
        .navigationTitle("Parent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                DevelopmentSessionMenu()
            }
            #endif
        }
    }
}

enum ParentTab: String, CaseIterable, Identifiable {
    case review
    case chores
    case family

    var id: String { rawValue }
    var title: String {
        switch self {
        case .review:
            return "Review"
        case .chores:
            return "Chores"
        case .family:
            return "Family"
        }
    }
}

struct ParentReviewQueueView: View {
    @EnvironmentObject private var store: AppStore
    @State private var filter: ReviewFilter = .all

    private var visibleOccurrences: [TaskOccurrence] {
        switch filter {
        case .all:
            return store.occurrences.filter { $0.status.needsParentReview || $0.status == .approved || $0.status == .excused }
        case .pending:
            return store.pendingReviewOccurrences
        case .reviewed:
            return store.occurrences.filter { $0.status == .approved || $0.status == .excused || $0.status == .rejected }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Review filter", selection: $filter) {
                    ForEach(ReviewFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if visibleOccurrences.isEmpty {
                    ContentUnavailableView("Queue clear", systemImage: "checkmark.circle.fill")
                        .frame(minHeight: 280)
                } else {
                    VStack(spacing: 12) {
                        ForEach(visibleOccurrences) { occurrence in
                            ReviewCard(
                                occurrence: occurrence,
                                chore: store.chore(for: occurrence),
                                submission: store.submission(for: occurrence)
                            )
                        }
                    }
                }
            }
            .padding(22)
        }
        .refreshable {
            await store.refreshRemoteFamilyState()
        }
    }
}

enum ReviewFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case reviewed

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ReviewCard: View {
    @EnvironmentObject private var store: AppStore
    var occurrence: TaskOccurrence
    var chore: ChoreDefinition
    var submission: ChoreSubmission?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ReviewThumbnail(chore: chore)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(chore.title)
                            .font(.headline)
                            .foregroundStyle(Color.inkBlack)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        statusBadge
                    }

                    Text(submission?.submittedAt.formatted(date: .omitted, time: .shortened) ?? "No submission")
                        .font(.caption)
                        .foregroundStyle(Color.mutedGray)

                    if let result = submission?.aiResult {
                        Text("AI: \(Int(result.confidence * 100))%")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(result.confidence >= 0.85 ? .green : .warmOrange)
                    } else {
                        Text("Miss it: \(Money.dollars(-chore.deductionCents, signed: true))")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.warmOrange)
                    }
                }
            }

            if occurrence.status.needsParentReview {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SecondaryActionButton(title: "Approve", systemImage: "checkmark.circle.fill", tint: .acidLime) {
                        store.approve(occurrence)
                    }
                    SecondaryActionButton(title: "Reject", systemImage: "xmark.circle.fill", tint: .warmOrange) {
                        store.reject(occurrence)
                    }
                    SecondaryActionButton(title: "Excuse", systemImage: "hand.raised.fill", tint: .electricBlue.opacity(0.35)) {
                        store.excuse(occurrence, reason: "Parent excused")
                    }
                    SecondaryActionButton(title: "Retake", systemImage: "camera.rotate.fill", tint: .softGray) {
                        store.requestRetake(occurrence)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(occurrence.status.needsParentReview ? Color.sunYellow : Color.softGray, lineWidth: 1.5)
        )
    }

    private var statusBadge: some View {
        Text(badgeText)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(Color.inkBlack)
            .background(badgeColor, in: Capsule())
    }

    private var badgeText: String {
        switch occurrence.status {
        case .submitted, .aiReviewed:
            return "Pending"
        case .approved:
            return "Approved"
        case .rejected:
            return "Rejected"
        case .missed:
            return "Missed"
        case .excused:
            return "Excused"
        case .upcoming, .due:
            return "Open"
        }
    }

    private var badgeColor: Color {
        switch occurrence.status {
        case .submitted, .aiReviewed:
            return .sunYellow.opacity(0.45)
        case .approved:
            return .acidLime.opacity(0.55)
        case .rejected, .missed:
            return .warmOrange.opacity(0.35)
        case .excused:
            return .electricBlue.opacity(0.25)
        case .upcoming, .due:
            return .softGray
        }
    }
}

struct ReviewThumbnail: View {
    var chore: ChoreDefinition

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: thumbnailColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 76, height: 76)

            Image(systemName: iconName)
                .font(.title.weight(.bold))
                .foregroundStyle(Color.paperWhite)
        }
        .accessibilityHidden(true)
    }

    private var thumbnailColors: [Color] {
        if chore.title.contains("Dog") {
            return [.sunYellow, .warmOrange]
        }
        if chore.title.contains("Bathroom") {
            return [.electricBlue.opacity(0.62), .softGray]
        }
        return [.hotPink, .electricBlue]
    }

    private var iconName: String {
        if chore.title.contains("Dog") {
            return "pawprint.fill"
        }
        if chore.title.contains("Bathroom") {
            return "shower.fill"
        }
        return "bed.double.fill"
    }
}

struct ChoreManagementView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedChore: ChoreDefinition?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Editable development seed chores")
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedGray)

                ForEach(store.chores) { chore in
                    Button {
                        selectedChore = chore
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(chore.isPaused ? Color.softGray : Color.acidLime)
                                .frame(width: 14, height: 14)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(chore.title)
                                    .font(.headline)
                                    .foregroundStyle(Color.inkBlack)
                                Text("\(chore.dueTime) · Miss it \(Money.dollars(-chore.deductionCents, signed: true))")
                                    .font(.caption)
                                    .foregroundStyle(Color.mutedGray)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.mutedGray)
                        }
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.softGray, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
        }
        .sheet(item: $selectedChore) { chore in
            EditChoreSheet(chore: chore)
                .environmentObject(store)
        }
    }
}

struct FamilyManagementView: View {
    @EnvironmentObject private var store: AppStore
    @State private var childName = "Zoe"
    @State private var phoneNumber = ""
    @State private var parentName = "Mamma"
    @State private var parentPhoneNumber = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FamilySyncCard()
                    .environmentObject(store)

                if let syncMessage = store.inviteCreationState.message {
                    Label(syncMessage, systemImage: store.inviteCreationState.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.inviteCreationState.isSynced ? Color.inkBlack : Color.mutedGray)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            (store.inviteCreationState.isSynced ? Color.acidLime : Color.softGray).opacity(0.45),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }

                AllowanceSettingsCard()
                    .environmentObject(store)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Parents")
                        .font(.title3.weight(.heavy))

                    ForEach(store.members.filter { $0.role == .parent }) { member in
                        ParentMemberCard(member: member, isCurrentSession: member.userId == store.session.userId)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Invite Parent")
                        .font(.title3.weight(.heavy))

                    VStack(spacing: 12) {
                        TextField("Parent name", text: $parentName)
                            .textContentType(.givenName)
                            .font(.body.weight(.semibold))
                            .textFieldStyle(.roundedBorder)

                        TextField("Phone number", text: $parentPhoneNumber)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .font(.body.weight(.semibold))
                            .textFieldStyle(.roundedBorder)

                        PrimaryButton(title: "Create Parent Invite", systemImage: "person.badge.plus") {
                            Task {
                                await store.createParentInvite(parentName: parentName, phoneNumber: parentPhoneNumber)
                            }
                        }
                        .disabled(store.inviteCreationState.isWorking)
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.softGray, lineWidth: 1)
                    )
                }

                if !store.parentInvites.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Parent Links")
                            .font(.title3.weight(.heavy))

                        ForEach(store.parentInvites) { invite in
                            ParentInviteCard(invite: invite)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Children")
                        .font(.title3.weight(.heavy))

                    ForEach(store.childProfiles) { profile in
                        ChildProfileCard(profile: profile)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Invite Child")
                        .font(.title3.weight(.heavy))

                    VStack(spacing: 12) {
                        TextField("Child name", text: $childName)
                            .textContentType(.givenName)
                            .font(.body.weight(.semibold))
                            .textFieldStyle(.roundedBorder)

                        TextField("Phone number", text: $phoneNumber)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .font(.body.weight(.semibold))
                            .textFieldStyle(.roundedBorder)

                        PrimaryButton(title: "Create Child Invite", systemImage: "link.badge.plus") {
                            Task {
                                await store.createChildInvite(childName: childName, phoneNumber: phoneNumber)
                            }
                        }
                        .disabled(store.inviteCreationState.isWorking)
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.softGray, lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Child Links")
                        .font(.title3.weight(.heavy))

                    if store.childInvites.isEmpty {
                        ContentUnavailableView("No invites yet", systemImage: "message.badge")
                            .frame(minHeight: 180)
                    } else {
                        ForEach(store.childInvites) { invite in
                            ChildInviteCard(invite: invite)
                        }
                    }
                }
            }
            .padding(22)
        }
    }
}

struct FamilySyncCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var signInMethod: FamilySyncSignInMethod = .email
    @State private var email = ""
    @State private var phoneNumber = ""
    @State private var oneTimeCode = ""
    @State private var bootstrapParentName = "Daddy"
    @State private var bootstrapChildName = "Zoe"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Family Sync", systemImage: store.familySyncState.iconName)
                    .font(.title3.weight(.heavy))
                Spacer()
                if store.familySyncState.isSynced {
                    Text("Live")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(Color.inkBlack)
                        .background(Color.acidLime.opacity(0.65), in: Capsule())
                }
            }

            Text(store.familySyncState.message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(store.familySyncState.isSynced ? Color.inkBlack : Color.mutedGray)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                Picker("Sign in method", selection: $signInMethod) {
                    ForEach(FamilySyncSignInMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                switch signInMethod {
                case .email:
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.weight(.semibold))
                        .textFieldStyle(.roundedBorder)
                case .phone:
                    TextField("Phone number", text: $phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .font(.body.weight(.semibold))
                        .textFieldStyle(.roundedBorder)
                }

                if store.familySyncState.hasPendingCode {
                    TextField("One-time code", text: $oneTimeCode)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .font(.body.weight(.semibold))
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await requestCode()
                        }
                    } label: {
                        Label("Send Code", systemImage: signInMethod.iconName)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(Color.inkBlack)
                            .background(Color.sunYellow.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            await verifyCode()
                        }
                    } label: {
                        Label("Verify", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(Color.paperWhite)
                            .background(Color.inkBlack, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.familySyncState.hasPendingCode)
                }

                if store.familySyncState.needsBootstrap {
                    TextField("Parent display name", text: $bootstrapParentName)
                        .textContentType(.givenName)
                        .font(.body.weight(.semibold))
                        .textFieldStyle(.roundedBorder)

                    TextField("Child display name", text: $bootstrapChildName)
                        .textContentType(.givenName)
                        .font(.body.weight(.semibold))
                        .textFieldStyle(.roundedBorder)

                    PrimaryButton(title: "Create Remote Family", systemImage: "icloud.and.arrow.up.fill") {
                        Task {
                            await store.bootstrapRemoteFamily(
                                parentName: bootstrapParentName,
                                childName: bootstrapChildName
                            )
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await store.loadRemoteFamilyState()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .foregroundStyle(Color.inkBlack)
                            .background(Color.softGray.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if store.familySyncState.isSynced {
                        Button {
                            Task {
                                await store.signOutRemoteFamily()
                            }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .foregroundStyle(Color.inkBlack)
                                .background(Color.softGray.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .disabled(store.familySyncState.isWorking)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(store.familySyncState.isSynced ? Color.acidLime : Color.softGray, lineWidth: 1.5)
        )
    }

    private func requestCode() async {
        oneTimeCode = ""

        switch signInMethod {
        case .email:
            await store.requestFamilySyncEmailCode(email: email)
        case .phone:
            await store.requestFamilySyncCode(phoneNumber: phoneNumber)
        }
    }

    private func verifyCode() async {
        switch signInMethod {
        case .email:
            await store.verifyFamilySyncEmailCode(
                email: store.familySyncState.codeEmail ?? email,
                code: oneTimeCode
            )
        case .phone:
            await store.verifyFamilySyncCode(
                phoneNumber: store.familySyncState.codePhoneNumber ?? phoneNumber,
                code: oneTimeCode
            )
        }
    }
}

private enum FamilySyncSignInMethod: String, CaseIterable, Identifiable {
    case email
    case phone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .email:
            return "Email"
        case .phone:
            return "Phone"
        }
    }

    var iconName: String {
        switch self {
        case .email:
            return "envelope.fill"
        case .phone:
            return "message.fill"
        }
    }
}

struct AllowanceSettingsCard: View {
    @EnvironmentObject private var store: AppStore

    private var cadenceBinding: Binding<AllowanceCadence> {
        Binding {
            store.allowanceSettings.cadence
        } set: { cadence in
            store.updateAllowanceSettings(
                cadence: cadence,
                allowanceWeekday: store.allowanceSettings.allowanceWeekday,
                nextAllowanceDate: store.allowanceSettings.nextAllowanceDate
            )
        }
    }

    private var weekdayBinding: Binding<AllowanceWeekday> {
        Binding {
            store.allowanceSettings.allowanceWeekday
        } set: { weekday in
            let updated = store.allowanceSettings.withWeekday(weekday)
            store.updateAllowanceSettings(
                cadence: updated.cadence,
                allowanceWeekday: updated.allowanceWeekday,
                nextAllowanceDate: updated.nextAllowanceDate
            )
        }
    }

    private var nextDateBinding: Binding<Date> {
        Binding {
            store.allowanceSettings.nextAllowanceDate
        } set: { date in
            store.updateAllowanceSettings(
                cadence: store.allowanceSettings.cadence,
                allowanceWeekday: AllowanceWeekday(rawValue: Calendar.current.component(.weekday, from: date)) ?? store.allowanceSettings.allowanceWeekday,
                nextAllowanceDate: date
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Allowance Schedule")
                .font(.title3.weight(.heavy))

            VStack(spacing: 12) {
                Picker("Cadence", selection: cadenceBinding) {
                    ForEach(AllowanceCadence.allCases) { cadence in
                        Text(cadence.title).tag(cadence)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Allowance day", selection: weekdayBinding) {
                    ForEach(AllowanceWeekday.allCases) { weekday in
                        Text(weekday.title).tag(weekday)
                    }
                }

                if store.allowanceSettings.cadence == .everyTwoWeeks {
                    DatePicker(
                        "Next payday",
                        selection: nextDateBinding,
                        displayedComponents: .date
                    )
                }

                HStack {
                    Label("Next allowance", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.mutedGray)
                    Spacer()
                    Text(store.nextAllowanceDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Color.inkBlack)
                }

                PrimaryButton(title: "Schedule Reminders", systemImage: "bell.badge.fill") {
                    Task {
                        await store.enableLocalNotifications()
                    }
                }

                if store.notificationState != .idle {
                    Text(store.notificationState.message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.notificationState == .scheduled ? Color.inkBlack : Color.mutedGray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.softGray, lineWidth: 1)
            )
        }
    }
}

struct ParentMemberCard: View {
    var member: FamilyMember
    var isCurrentSession: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isCurrentSession ? Color.sunYellow : Color.acidLime)
                    .frame(width: 48, height: 48)
                Image(systemName: isCurrentSession ? "person.fill.checkmark" : "person.2.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.inkBlack)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(member.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.inkBlack)

                Text(isCurrentSession ? "Signed in here" : "Can review and manage chores")
                    .font(.caption)
                    .foregroundStyle(Color.mutedGray)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.softGray, lineWidth: 1)
        )
    }
}

struct ChildProfileCard: View {
    var profile: ChildProfile

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(profile.linkedUserId == nil ? Color.sunYellow : Color.acidLime)
                    .frame(width: 48, height: 48)
                Image(systemName: profile.linkedUserId == nil ? "person.crop.circle.badge.plus" : "checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.inkBlack)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(profile.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.inkBlack)

                Text(profile.linkedUserId == nil ? "Waiting for account link" : "Connected child account")
                    .font(.caption)
                    .foregroundStyle(Color.mutedGray)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.softGray, lineWidth: 1)
        )
    }
}

struct ParentInviteCard: View {
    @EnvironmentObject private var store: AppStore
    var invite: ParentInvite

    private var status: ParentInviteStatus {
        invite.resolvedStatus()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(invite.parentName)
                        .font(.headline)
                        .foregroundStyle(Color.inkBlack)
                    if let phoneNumber = invite.phoneNumber {
                        Text(phoneNumber)
                            .font(.caption)
                            .foregroundStyle(Color.mutedGray)
                    }
                }

                Spacer()

                Text(status.title)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .foregroundStyle(Color.inkBlack)
                    .background(statusColor, in: Capsule())
            }

            Text(invite.inviteURL.absoluteString)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.softGray.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if status == .pending {
                HStack(spacing: 10) {
                    ShareLink(
                        item: invite.inviteURL,
                        subject: Text("Join \(AppBrand.displayName)"),
                        message: Text("\(store.parentName) invited you to help manage \(AppBrand.displayName).")
                    ) {
                        Label("Send Message", systemImage: "message.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(Color.inkBlack)
                            .background(Color.acidLime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button {
                        store.revokeParentInvite(invite)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .frame(width: 48, height: 48)
                            .foregroundStyle(Color.inkBlack)
                            .background(Color.softGray, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityLabel("Revoke parent invite")
                }

                #if DEBUG
                Button {
                    store.markParentInviteAccepted(invite)
                } label: {
                    Label("Mark Accepted", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(Color.inkBlack)
                        .background(Color.sunYellow.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(status == .pending ? Color.sunYellow : Color.softGray, lineWidth: 1.5)
        )
    }

    private var statusColor: Color {
        switch status {
        case .pending:
            return .sunYellow.opacity(0.5)
        case .accepted:
            return .acidLime.opacity(0.55)
        case .expired:
            return .warmOrange.opacity(0.35)
        case .revoked:
            return .softGray
        }
    }
}

struct ChildInviteCard: View {
    @EnvironmentObject private var store: AppStore
    var invite: ChildInvite

    private var status: ChildInviteStatus {
        invite.resolvedStatus()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(invite.childName)
                        .font(.headline)
                        .foregroundStyle(Color.inkBlack)
                    if let phoneNumber = invite.phoneNumber {
                        Text(phoneNumber)
                            .font(.caption)
                            .foregroundStyle(Color.mutedGray)
                    }
                }

                Spacer()

                Text(status.title)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .foregroundStyle(Color.inkBlack)
                    .background(statusColor, in: Capsule())
            }

            Text(invite.inviteURL.absoluteString)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.softGray.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if status == .pending {
                HStack(spacing: 10) {
                    ShareLink(
                        item: invite.inviteURL,
                        subject: Text("Join \(AppBrand.displayName)"),
                        message: Text("\(store.parentName) invited you to join \(AppBrand.displayName).")
                    ) {
                        Label("Send Message", systemImage: "message.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(Color.inkBlack)
                            .background(Color.acidLime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button {
                        store.revokeInvite(invite)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .frame(width: 48, height: 48)
                            .foregroundStyle(Color.inkBlack)
                            .background(Color.softGray, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityLabel("Revoke invite")
                }

                #if DEBUG
                Button {
                    store.markInviteAccepted(invite)
                } label: {
                    Label("Mark Accepted", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(Color.inkBlack)
                        .background(Color.sunYellow.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(status == .pending ? Color.sunYellow : Color.softGray, lineWidth: 1.5)
        )
    }

    private var statusColor: Color {
        switch status {
        case .pending:
            return .sunYellow.opacity(0.5)
        case .accepted:
            return .acidLime.opacity(0.55)
        case .expired:
            return .warmOrange.opacity(0.35)
        case .revoked:
            return .softGray
        }
    }
}

struct EditChoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let chore: ChoreDefinition

    @State private var title: String
    @State private var deduction: String
    @State private var dueTime: String

    init(chore: ChoreDefinition) {
        self.chore = chore
        _title = State(initialValue: chore.title)
        _deduction = State(initialValue: Money.dollars(chore.deductionCents).replacingOccurrences(of: "$", with: ""))
        _dueTime = State(initialValue: chore.dueTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chore") {
                    TextField("Title", text: $title)
                    TextField("Due time", text: $dueTime)
                    TextField("Deduction", text: $deduction)
                        .keyboardType(.decimalPad)
                }
                Section("Instructions") {
                    Text(chore.instructions)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Chore")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let cents = Money.cents(fromDollarString: deduction), !title.isEmpty {
                            store.updateChore(chore, title: title, deductionCents: cents, dueTime: dueTime)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
