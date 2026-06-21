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
                .tabItem { tabLabel("Notebooks", "books.vertical") }

            DashboardView(
                viewModel: DashboardViewModel(repository: NotebookRepository(context: modelContext), favoritesOnly: true),
                title: "Favorites"
            )
            .tabItem { tabLabel("Favorites", "star") }

            FeedbackView()
                .tabItem { tabLabel("Feedback", "bubble.left.and.bubble.right") }

            AboutView()
                .tabItem { tabLabel("About", "info.circle") }
        }
        .task {
            syncSettingsToLocalDefaults()
            // Pay PencilKit's one-time engine start-up cost now so the first
            // stroke on a freshly opened notebook isn't laggy (iPad editing only).
            if DeviceKind.isPad { PencilKitWarmUp.warmUp() }
        }
        .onChange(of: settingsRecords.map(\.updatedAt)) { _, _ in
            syncSettingsToLocalDefaults()
        }
        // Files handed in via AirDrop, "Open in NotePad", or the Files app.
        .onOpenURL { url in
            ExternalImport.handle(url: url, context: modelContext)
        }
    }

    /// Tab bar item. On iPad the bar floats at the top, so show icons only for a
    /// neater, more minimalist look; iPhone keeps the labelled bottom tabs.
    @ViewBuilder
    private func tabLabel(_ title: String, _ systemImage: String) -> some View {
        if DeviceKind.isPad {
            Image(systemName: systemImage).accessibilityLabel(title)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private func syncSettingsToLocalDefaults() {
        AppSettingsSync.migrateLocalDefaultsIfNeeded(records: settingsRecords, context: modelContext)
        if let settings = AppSettingsSync.current(from: settingsRecords) {
            AppSettingsSync.applyToUserDefaults(settings)
        }
    }
}
