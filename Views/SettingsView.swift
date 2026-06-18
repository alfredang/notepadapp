import SwiftUI
import SwiftData

/// App settings and defaults.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    private let defaultPatterns: [PaperPattern] = [.blank, .grid, .lined]

    private var settings: AppSettings {
        if let settings = AppSettingsSync.current(from: settingsRecords) {
            return settings
        }
        return AppSettingsSync.createDefault(in: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Pencil") {
                    Toggle("Allow finger drawing", isOn: settingBinding(\.allowsFingerDrawing))
                    Text("When off, fingers pan and zoom while Apple Pencil draws.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Double-tap Pencil", selection: settingBinding(\.pencilDoubleTapActionRaw)) {
                        ForEach(PencilDoubleTapAction.allCases) { action in
                            Text(action.title).tag(action.rawValue)
                        }
                    }
                    Text("Choose what a double-tap (or squeeze) on your Apple Pencil does.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Defaults") {
                    Picker("Default pen width", selection: settingBinding(\.defaultPenWidth)) {
                        ForEach(ToolDefaults.penSizes, id: \.self) { size in
                            Text("\(Int(size)) px").tag(Double(size))
                        }
                    }
                    Picker("Default eraser size", selection: settingBinding(\.defaultEraserWidth)) {
                        ForEach(ToolDefaults.eraserSizes, id: \.self) { size in
                            Text("\(Int(size)) px").tag(Double(size))
                        }
                    }
                    Toggle("Show page numbers", isOn: settingBinding(\.showPageNumbers))
                    Toggle("Show date and time stamp", isOn: settingBinding(\.showDateTimeStamp))
                }
                Section("Default Template") {
                    Text("Applied to new notebooks. Existing notebooks keep their template.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Mode", selection: settingBinding(\.defaultPaperLayoutRaw)) {
                        ForEach(PaperLayout.allCases) { layout in
                            Text(layout.displayName).tag(layout.rawValue)
                        }
                    }
                    Picker("Surface", selection: settingBinding(\.defaultPaperSurfaceRaw)) {
                        ForEach(PaperSurface.allCases) { surface in
                            Text(surface.displayName).tag(surface.rawValue)
                        }
                    }
                    Picker("Pattern", selection: settingBinding(\.defaultPaperPatternRaw)) {
                        ForEach(defaultPatterns) { pattern in
                            Text(pattern.displayName).tag(pattern.rawValue)
                        }
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Platform", value: "iPadOS 18+")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func settingBinding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                let settings = settings
                settings[keyPath: keyPath] = newValue
                settings.touch()
                try? modelContext.save()
                AppSettingsSync.applyToUserDefaults(settings)
            }
        )
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
