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
                    Text("Finish setting up this child account to join \(store.familyName).")
                        .font(.body)
                        .foregroundStyle(Color.mutedGray)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Invite code")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.mutedGray)
                    Text(invite.token)
                        .font(.callout.monospaced().weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.softGray.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Spacer()

                PrimaryButton(title: "Continue", systemImage: "arrow.right") {
                    store.switchSession(to: .child)
                    store.clearPendingInvite()
                    dismiss()
                }
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
}
