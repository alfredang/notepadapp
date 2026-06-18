import SwiftUI
import SwiftData

/// Top-level router. Shows the dashboard; opening a notebook pushes the editor.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]

    var body: some View {
        DashboardView(viewModel: DashboardViewModel(repository: NotebookRepository(context: modelContext)))
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
