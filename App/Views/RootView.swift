import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.isParentSession {
                ParentShellView()
            } else {
                ChildShellView()
            }
        }
        .tint(.inkBlack)
        .onOpenURL { url in
            store.handleIncomingURL(url)
        }
        .sheet(item: $store.pendingInvite) { invite in
            InviteLandingSheet(invite: invite)
                .environmentObject(store)
        }
    }
}

struct ChildShellView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Today", systemImage: "house.fill")
            }

            NavigationStack {
                EarningsView(allowsBonusActions: false)
            }
            .tabItem {
                Label("Earnings", systemImage: "chart.bar.fill")
            }

            NavigationStack {
                WidgetPreviewView()
            }
            .tabItem {
                Label("Widgets", systemImage: "rectangle.grid.2x2.fill")
            }
        }
    }
}

struct ParentShellView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ParentWorkspaceView()
            }
            .tabItem {
                Label("Parent", systemImage: "checklist.checked")
            }

            NavigationStack {
                EarningsView(allowsBonusActions: true)
            }
            .tabItem {
                Label("Earnings", systemImage: "chart.bar.fill")
            }

            NavigationStack {
                WidgetPreviewView()
            }
            .tabItem {
                Label("Widgets", systemImage: "rectangle.grid.2x2.fill")
            }
        }
    }
}

struct DevelopmentSessionMenu: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Menu {
            ForEach(FamilyMemberRole.allCases) { role in
                Button {
                    store.switchSession(to: role)
                } label: {
                    Label(role.title, systemImage: role == .parent ? "person.2.fill" : "face.smiling")
                }
            }
        } label: {
            Image(systemName: store.isParentSession ? "person.2.fill" : "face.smiling")
        }
        .accessibilityLabel("Switch preview role")
    }
}

struct InviteLandingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    var invite: PendingInvite
    @State private var phoneNumber = ""
    @State private var smsCode = ""
    @State private var hasRequestedCode = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.sunYellow, .acidLime],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 180)

                    MascotCluster(scale: 0.72)
                        .offset(x: 8, y: 12)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("You're invited")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("Sign in with this phone to join \(store.familyName) as \(invite.kind.roleTitle.lowercased()).")
                        .font(.body)
                        .foregroundStyle(Color.mutedGray)
                }

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Phone number", text: $phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .font(.body.weight(.semibold))
                        .textFieldStyle(.roundedBorder)

                    if shouldShowCodeField {
                        TextField("Text code", text: $smsCode)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .font(.body.weight(.semibold))
                            .textFieldStyle(.roundedBorder)
                    }

                    if let errorMessage = store.inviteAcceptanceState.errorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.warmOrange)
                    }

                    if let displayName = store.inviteAcceptanceState.acceptedDisplayName {
                        Label("\(displayName) is connected as \(store.inviteAcceptanceState.acceptedRole?.title ?? invite.kind.roleTitle)", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color.green)
                    }

                    PrimaryButton(title: primaryButtonTitle, systemImage: primaryButtonIcon) {
                        performPrimaryAction()
                    }
                    .disabled(store.inviteAcceptanceState.isWorking)
                }

                #if DEBUG
                VStack(alignment: .leading, spacing: 8) {
                    Text(invite.token)
                        .font(.caption.monospaced().weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.softGray.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button {
                        store.switchSession(to: .child)
                        store.clearPendingInvite()
                        dismiss()
                    } label: {
                        Label("Preview as Child", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.inkBlack)
                    }
                    .buttonStyle(.plain)
                }
                #endif

                Spacer()
            }
            .padding(22)
            .background(Color.paperWhite.ignoresSafeArea())
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        store.clearPendingInvite()
                        dismiss()
                    }
                }
            }
        }
    }

    private var primaryButtonTitle: String {
        switch store.inviteAcceptanceState {
        case .requestingCode:
            return "Sending Code"
        case .codeSent, .failed:
            return shouldShowCodeField ? "Accept Invite" : "Send Code"
        case .accepting:
            return "Accepting"
        case .accepted:
            return "Continue"
        case .idle:
            return "Send Code"
        }
    }

    private var primaryButtonIcon: String {
        switch store.inviteAcceptanceState {
        case .accepted:
            return "arrow.right"
        case .codeSent, .accepting:
            return "checkmark.circle.fill"
        case .idle, .requestingCode, .failed:
            return shouldShowCodeField ? "checkmark.circle.fill" : "message.fill"
        }
    }

    private var shouldShowCodeField: Bool {
        switch store.inviteAcceptanceState {
        case .codeSent, .accepting, .accepted:
            return true
        case .idle, .requestingCode, .failed:
            return hasRequestedCode
        }
    }

    private func performPrimaryAction() {
        if store.inviteAcceptanceState.acceptedDisplayName != nil {
            store.clearPendingInvite()
            dismiss()
            return
        }

        if hasRequestedCode {
            Task {
                await store.acceptPendingInvite(phoneNumber: phoneNumber, code: smsCode)
            }
        } else {
            Task {
                await store.requestInviteSMSCode(phoneNumber: phoneNumber)
                if case .codeSent = store.inviteAcceptanceState {
                    hasRequestedCode = true
                }
            }
        }
    }
}

private extension PendingInviteKind {
    var roleTitle: String {
        switch self {
        case .child:
            return "Child"
        case .parent:
            return "Parent"
        }
    }
}
