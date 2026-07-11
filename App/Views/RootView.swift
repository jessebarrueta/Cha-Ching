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
