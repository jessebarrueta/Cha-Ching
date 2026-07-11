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
            } else {
                ChoreManagementView()
            }
        }
        .background(Color.paperWhite.ignoresSafeArea())
        .navigationTitle("Parent")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum ParentTab: String, CaseIterable, Identifiable {
    case review
    case chores

    var id: String { rawValue }
    var title: String {
        switch self {
        case .review:
            return "Review"
        case .chores:
            return "Chores"
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

