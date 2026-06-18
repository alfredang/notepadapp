import Foundation
import SwiftData

/// User preferences that should follow the user through iCloud after reinstall
/// or when moving to a new device.
@Model
final class AppSettings {
    var key: String = "primary"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var allowsFingerDrawing: Bool = false
    var pencilDoubleTapActionRaw: String = PencilDoubleTapAction.eraser.rawValue
    var defaultPenWidth: Double = 2
    var defaultEraserWidth: Double = 20
    var defaultPaperSurfaceRaw: String = PaperSurface.blackboard.rawValue
    var defaultPaperPatternRaw: String = PaperPattern.blank.rawValue
    var showPageNumbers: Bool = true

    init(
        key: String = "primary",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        allowsFingerDrawing: Bool = false,
        pencilDoubleTapActionRaw: String = PencilDoubleTapAction.eraser.rawValue,
        defaultPenWidth: Double = 2,
        defaultEraserWidth: Double = 20,
        defaultPaperSurfaceRaw: String = PaperSurface.blackboard.rawValue,
        defaultPaperPatternRaw: String = PaperPattern.blank.rawValue,
        showPageNumbers: Bool = true
    ) {
        self.key = key
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.allowsFingerDrawing = allowsFingerDrawing
        self.pencilDoubleTapActionRaw = pencilDoubleTapActionRaw
        self.defaultPenWidth = defaultPenWidth
        self.defaultEraserWidth = defaultEraserWidth
        self.defaultPaperSurfaceRaw = defaultPaperSurfaceRaw
        self.defaultPaperPatternRaw = defaultPaperPatternRaw
        self.showPageNumbers = showPageNumbers
    }

    func touch(_ date: Date = .now) {
        updatedAt = date
    }
}

@MainActor
enum AppSettingsSync {
    static let settingsKey = "primary"
    private static let localMigrationKey = "didMigrateLocalSettingsToCloud"

    static func current(from records: [AppSettings]) -> AppSettings? {
        records
            .filter { $0.key == settingsKey }
            .max { $0.updatedAt < $1.updatedAt }
    }

    static func migrateLocalDefaultsIfNeeded(records: [AppSettings], context: ModelContext) {
        if let settings = current(from: records) {
            applyToUserDefaults(settings)
            return
        }
        guard UserDefaults.standard.bool(forKey: localMigrationKey) == false,
              hasLocalDefaultsToMigrate else {
            return
        }

        let settings = AppSettings(
            allowsFingerDrawing: UserDefaults.standard.object(forKey: "allowsFingerDrawing") as? Bool ?? false,
            pencilDoubleTapActionRaw: UserDefaults.standard.string(forKey: PencilDoubleTapAction.storageKey)
                ?? PencilDoubleTapAction.eraser.rawValue,
            defaultPenWidth: AppDefaults.penWidth.doubleValue,
            defaultEraserWidth: AppDefaults.eraserWidth.doubleValue,
            defaultPaperSurfaceRaw: AppDefaults.paperSurface.rawValue,
            defaultPaperPatternRaw: AppDefaults.paperPattern.rawValue,
            showPageNumbers: UserDefaults.standard.object(forKey: "showPageNumbers") as? Bool ?? true
        )
        context.insert(settings)
        try? context.save()
        UserDefaults.standard.set(true, forKey: localMigrationKey)
        applyToUserDefaults(settings)
    }

    static func createDefault(in context: ModelContext) -> AppSettings {
        if let settings = fetchCurrent(in: context) {
            applyToUserDefaults(settings)
            return settings
        }

        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
        applyToUserDefaults(settings)
        return settings
    }

    private static func fetchCurrent(in context: ModelContext) -> AppSettings? {
        let descriptor = FetchDescriptor<AppSettings>()
        let records = (try? context.fetch(descriptor)) ?? []
        return current(from: records)
    }

    static func applyToUserDefaults(_ settings: AppSettings) {
        UserDefaults.standard.set(settings.allowsFingerDrawing, forKey: "allowsFingerDrawing")
        UserDefaults.standard.set(settings.pencilDoubleTapActionRaw, forKey: PencilDoubleTapAction.storageKey)
        UserDefaults.standard.set(settings.defaultPenWidth, forKey: AppDefaults.penWidthKey)
        UserDefaults.standard.set(settings.defaultEraserWidth, forKey: AppDefaults.eraserWidthKey)
        UserDefaults.standard.set(settings.defaultPaperSurfaceRaw, forKey: AppDefaults.surfaceKey)
        UserDefaults.standard.set(settings.defaultPaperPatternRaw, forKey: AppDefaults.patternKey)
        UserDefaults.standard.set(settings.showPageNumbers, forKey: "showPageNumbers")
    }

    private static var hasLocalDefaultsToMigrate: Bool {
        UserDefaults.standard.object(forKey: "allowsFingerDrawing") != nil
            || UserDefaults.standard.object(forKey: PencilDoubleTapAction.storageKey) != nil
            || UserDefaults.standard.object(forKey: AppDefaults.penWidthKey) != nil
            || UserDefaults.standard.object(forKey: AppDefaults.eraserWidthKey) != nil
            || UserDefaults.standard.object(forKey: AppDefaults.surfaceKey) != nil
            || UserDefaults.standard.object(forKey: AppDefaults.patternKey) != nil
            || UserDefaults.standard.object(forKey: "showPageNumbers") != nil
    }
}

private extension CGFloat {
    var doubleValue: Double { Double(self) }
}
