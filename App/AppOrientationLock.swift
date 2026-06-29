import UIKit

/// App-wide interface-orientation lock.
///
/// While editing, the user can pin the app to its current orientation so a
/// stray rotation doesn't reflow the page mid-stroke. The `AppDelegate` reports
/// `mask` from `application(_:supportedInterfaceOrientationsFor:)`, and
/// `lock()` / `unlock()` flip it and ask the active scene to re-evaluate.
@MainActor
enum AppOrientationLock {
    /// The orientations the app currently permits. Defaults to everything the
    /// Info.plist allows; narrowed to a single orientation while locked.
    static var mask: UIInterfaceOrientationMask = .all

    /// Pins the app to whatever orientation it is in right now.
    static func lock() {
        guard let scene = activeScene else { return }
        mask = Self.mask(for: scene.interfaceOrientation)
        apply(in: scene)
    }

    /// Releases the lock so the device can rotate freely again.
    static func unlock() {
        mask = .all
        if let scene = activeScene { apply(in: scene) }
    }

    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// Re-evaluates supported orientations and (when full-screen) snaps the
    /// device to the locked orientation.
    private static func apply(in scene: UIWindowScene) {
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }

    private static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .all
        }
    }
}
