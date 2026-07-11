import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Today", systemImage: "house.fill")
            }

            NavigationStack {
                EarningsView()
            }
            .tabItem {
                Label("Earnings", systemImage: "chart.bar.fill")
            }

            NavigationStack {
                ParentWorkspaceView()
            }
            .tabItem {
                Label("Parent", systemImage: "checklist.checked")
            }

            NavigationStack {
                WidgetPreviewView()
            }
            .tabItem {
                Label("Widgets", systemImage: "rectangle.grid.2x2.fill")
            }
        }
        .tint(.inkBlack)
    }
}

