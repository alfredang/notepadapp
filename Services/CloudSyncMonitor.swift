import Foundation
import CoreData
import Observation

/// Observes the SwiftData store's underlying CloudKit mirroring events so the UI
/// can show live sync status and refresh when remote changes land.
///
/// SwiftData is built on `NSPersistentCloudKitContainer`, which posts
/// `eventChangedNotification` for every setup / import / export cycle. We surface
/// those as a simple `isSyncing` flag plus a `lastImportDate` the dashboard
/// watches to re-fetch (so notebooks created on another device appear without a
/// relaunch). Note: on a *Debug* build the remote-change push never arrives
/// (development APNs vs. Production CloudKit), so the import that drives
/// `lastImportDate` fires on launch / foreground / manual sync rather than live.
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()

    /// True while an import / export / setup event is in flight.
    private(set) var isSyncing = false
    /// End time of the last successful *import* (remote → local). Changes here
    /// signal the UI to re-fetch and surface newly synced data.
    private(set) var lastImportDate: Date?
    /// Human-readable description of the last sync error, or nil when healthy.
    private(set) var lastErrorMessage: String?

    private var observer: NSObjectProtocol?

    private init() {
        // The event isn't Sendable, so extract the few primitives we need inside
        // the delivery closure and hand only those to the main actor.
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let inProgress = event.endDate == nil
            let isImport = event.type == .import
            let endDate = event.endDate
            let errorDesc = event.error?.localizedDescription
            Task { @MainActor in
                CloudSyncMonitor.shared.apply(inProgress: inProgress, isImport: isImport,
                                              endDate: endDate, errorDesc: errorDesc)
            }
        }
    }

    private func apply(inProgress: Bool, isImport: Bool, endDate: Date?, errorDesc: String?) {
        guard !inProgress else {            // event just started
            isSyncing = true
            return
        }
        isSyncing = false
        if let errorDesc {
            lastErrorMessage = errorDesc
        } else {
            lastErrorMessage = nil
            if isImport { lastImportDate = endDate }
        }
    }
}
