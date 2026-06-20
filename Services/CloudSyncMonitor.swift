import Foundation
import CoreData
import CloudKit
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
    /// Number of import cycles that have completed (successfully) this session.
    /// Restore logic watches this to know when CloudKit has *finished* a fetch
    /// pass — distinguishing "still importing" from "imported, nothing arrived".
    private(set) var completedImports = 0
    /// Human-readable description of the last sync error, or nil when healthy.
    private(set) var lastErrorMessage: String?
    /// The user's iCloud account state for our container. `.couldNotDetermine`
    /// until the first `refreshAccountStatus()` resolves.
    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine

    /// True only once we positively know the user has no usable iCloud account,
    /// so the UI can stop "Restoring…" and prompt them to sign in instead of
    /// spinning forever on a device that can never receive data.
    var iCloudUnavailable: Bool {
        accountStatus == .noAccount || accountStatus == .restricted
    }

    private var observer: NSObjectProtocol?
    private let containerID = "iCloud.com.tertiaryinfotech.notepadapp"

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
            if isImport {
                lastImportDate = endDate
                completedImports += 1
            }
        }
    }

    /// Asks CloudKit whether the user is signed in to iCloud for our container.
    /// Cheap to call repeatedly (on launch / foreground / before a restore).
    func refreshAccountStatus() {
        CKContainer(identifier: containerID).accountStatus { status, _ in
            Task { @MainActor in CloudSyncMonitor.shared.accountStatus = status }
        }
    }
}
