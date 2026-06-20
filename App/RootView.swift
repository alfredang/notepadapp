import SwiftUI
import SwiftData

/// Top-level router. A bottom tab bar switches between the notebook dashboard,
/// starred notebooks, a feedback shortcut, and the about screen. Opening a
/// notebook pushes the editor within the active tab's navigation stack.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]

    var body: some View {
        TabView {
            DashboardView(viewModel: DashboardViewModel(repository: NotebookRepository(context: modelContext)))
                .tabItem { Label("Notebooks", systemImage: "books.vertical") }

            DashboardView(
                viewModel: DashboardViewModel(repository: NotebookRepository(context: modelContext), favoritesOnly: true),
                title: "Favorites"
            )
            .tabItem { Label("Favorites", systemImage: "star") }

            FeedbackView()
                .tabItem { Label("Feedback", systemImage: "bubble.left.and.bubble.right") }

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .task { syncSettingsToLocalDefaults() }
        .onChange(of: settingsRecords.map(\.updatedAt)) { _, _ in
            syncSettingsToLocalDefaults()
        }
    }

    private func syncSettingsToLocalDefaults() {
        AppSettingsSync.migrateLocalDefaultsIfNeeded(records: settingsRecords, context: modelContext)
        if let settings = AppSettingsSync.current(from: settingsRecords) {
            AppSettingsSync.applyToUserDefaults(settings)
        }
    }
}
