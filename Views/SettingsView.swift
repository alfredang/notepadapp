import SwiftUI

/// App settings and defaults.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("allowsFingerDrawing") private var allowsFingerDrawing = false
    @AppStorage(PencilDoubleTapAction.storageKey) private var pencilDoubleTapAction = PencilDoubleTapAction.eraser.rawValue
    @AppStorage(AppDefaults.penWidthKey) private var defaultPenWidth = 2.0
    @AppStorage(AppDefaults.eraserWidthKey) private var defaultEraserWidth = 20.0
    @AppStorage(AppDefaults.surfaceKey) private var defaultSurface = PaperSurface.blackboard.rawValue
    @AppStorage(AppDefaults.patternKey) private var defaultPattern = PaperPattern.blank.rawValue
    @AppStorage("showPageNumbers") private var showPageNumbers = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Pencil") {
                    Toggle("Allow finger drawing", isOn: $allowsFingerDrawing)
                    Text("When off, fingers pan and zoom while Apple Pencil draws.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Double-tap Pencil", selection: $pencilDoubleTapAction) {
                        ForEach(PencilDoubleTapAction.allCases) { action in
                            Text(action.title).tag(action.rawValue)
                        }
                    }
                    Text("Choose what a double-tap (or squeeze) on your Apple Pencil does.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Defaults") {
                    Picker("Default pen width", selection: $defaultPenWidth) {
                        ForEach(ToolDefaults.penSizes, id: \.self) { size in
                            Text("\(Int(size)) px").tag(Double(size))
                        }
                    }
                    Picker("Default eraser size", selection: $defaultEraserWidth) {
                        ForEach(ToolDefaults.eraserSizes, id: \.self) { size in
                            Text("\(Int(size)) px").tag(Double(size))
                        }
                    }
                    Toggle("Show page numbers", isOn: $showPageNumbers)
                }
                Section("Default Template") {
                    Text("Applied to new notebooks. Existing notebooks keep their template.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Surface", selection: $defaultSurface) {
                        ForEach(PaperSurface.allCases) { surface in
                            Text(surface.displayName).tag(surface.rawValue)
                        }
                    }
                    Picker("Pattern", selection: $defaultPattern) {
                        ForEach(PaperPattern.allCases) { pattern in
                            Text(pattern.displayName).tag(pattern.rawValue)
                        }
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: "1.0")
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
}
