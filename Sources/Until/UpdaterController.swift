import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater.
///
/// Distribution model: Until ships as a Developer ID-signed, notarized `.app`
/// via GitHub Releases (not the Mac App Store), so updates come through Sparkle
/// rather than the App Store. The appcast feed and the EdDSA public key that
/// authenticates each update live in Info.plist (`SUFeedURL` / `SUPublicEDKey`,
/// baked in by scripts/package-app.sh); automatic background checks are enabled
/// there too (`SUEnableAutomaticChecks`).
///
/// In an un-notarized / ad-hoc dev build Sparkle still initializes fine — it
/// just can't apply an update because the download signature won't validate,
/// which is the desired behavior for local runs.
@MainActor
final class UpdaterController {
  private let controller: SPUStandardUpdaterController

  init() {
    // startingUpdater: true kicks off the scheduled-check machinery immediately;
    // it reads the Info.plist keys and schedules the first check per
    // SUScheduledCheckInterval. No delegate needed for the default UX (Sparkle
    // shows its own "update available" window; the menubar item below is just an
    // explicit entry point).
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  /// Whether a user-initiated check can run right now (false mid-check/-install).
  var canCheckForUpdates: Bool {
    controller.updater.canCheckForUpdates
  }

  /// User-initiated check — shows Sparkle's progress/prompt UI even when a
  /// scheduled check would have stayed silent.
  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}
