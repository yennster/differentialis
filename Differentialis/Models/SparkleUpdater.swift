import Foundation
import AppKit
import Observation
import Sparkle

/// What the banner needs to know about a pending update, distilled from Sparkle's
/// `SUAppcastItem` so the UI layer never imports Sparkle directly.
struct AvailableUpdate: Equatable {
    let version: String     // marketing version, e.g. "0.2.0"
    let notes: String       // release-note text from the appcast (may be empty)
    let releaseURL: URL     // opened by the banner's "Notes" button

    init(from item: SUAppcastItem) {
        version = item.displayVersionString
        notes = item.itemDescription ?? ""
        releaseURL = item.releaseNotesURL
            ?? item.fullReleaseNotesURL
            ?? URL(string: "https://github.com/yennster/differentialis/releases")!
    }
}

/// Sparkle-backed updater that performs real in-app updates — download → EdDSA-verify →
/// swap the app bundle → relaunch — instead of opening the DMG in a browser.
///
/// Sparkle does the heavy lifting; we keep Differentialis's own Liquid Glass `UpdateBanner`
/// as the notification UI via Sparkle's "gentle reminders" (`SPUStandardUserDriverDelegate`).
/// When a scheduled check finds a newer version we suppress Sparkle's standard alert and
/// publish `available` to drive the banner; the banner's "Update" button hands control back
/// to Sparkle to download and install.
///
/// The `SPUStandardUserDriverDelegate` callbacks are declared `nonisolated` because the
/// protocol isn't main-actor isolated; Sparkle invokes them on the main thread, so each one
/// re-enters the main actor via `assumeIsolated` to touch our state safely.
@MainActor
@Observable
final class SparkleUpdater: NSObject, SPUStandardUserDriverDelegate {
    /// Non-nil when a newer version is waiting; drives `UpdateBanner`.
    var available: AvailableUpdate?
    /// Mirrors Sparkle's `canCheckForUpdates`; drives the "Check for Updates…" menu item.
    var canCheckForUpdates = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    /// The item Sparkle is currently offering, so "Skip" can remember it.
    @ObservationIgnored private var pendingItem: SUAppcastItem?
    private let defaults = UserDefaults.standard

    /// Build number (`CFBundleVersion`) the user chose to skip; suppressed on background checks.
    private var skippedBuild: String? {
        get { defaults.string(forKey: "skippedUpdateBuild") }
        set { defaults.set(newValue, forKey: "skippedUpdateBuild") }
    }

    override init() {
        super.init()
        // Delegates are wired at construction; `startingUpdater: true` begins the scheduled
        // background checks immediately (SUEnableAutomaticChecks in Info.plist skips the
        // first-launch "check automatically?" prompt).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self)
        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            self?.canCheckForUpdates = updater.canCheckForUpdates
        }
    }

    private var updater: SPUUpdater { controller.updater }

    // MARK: - Commands

    /// Manual check (menu / ⌘…). Uses Sparkle's standard UI, including "you're up to date".
    func checkForUpdates() { controller.checkForUpdates(nil) }

    /// Banner "Update": hide our banner and let Sparkle take over the download/install/relaunch.
    func installAvailable() {
        available = nil
        controller.checkForUpdates(nil)
    }

    /// Banner "Notes".
    func openReleaseNotes() {
        guard let update = available else { return }
        NSWorkspace.shared.open(update.releaseURL)
    }

    /// Banner "Skip": don't surface this build again on background checks.
    func skipAvailable() {
        skippedBuild = pendingItem?.versionString
        available = nil
    }

    /// Banner "Later": dismiss for now; the next scheduled check will offer it again.
    func dismissAvailable() { available = nil }

    // MARK: - SPUStandardUserDriverDelegate (gentle reminders)

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Tell Sparkle not to show its own alert for scheduled updates — we use our banner.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                          andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            pendingItem = update
            // When Sparkle is handling the UI itself (a user-initiated check), leave it alone.
            guard !handleShowingUpdate else { return }
            // Honor "Skip" only for automatic background checks.
            if !state.userInitiated, update.versionString == skippedBuild { return }
            available = AvailableUpdate(from: update)
        }
    }

    /// The user engaged with the update elsewhere (e.g. Sparkle's UI took over) — clear our banner.
    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { available = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            available = nil
            pendingItem = nil
        }
    }
}
