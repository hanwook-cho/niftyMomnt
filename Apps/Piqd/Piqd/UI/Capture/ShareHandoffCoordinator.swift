// Apps/Piqd/Piqd/UI/Capture/ShareHandoffCoordinator.swift
// Piqd v0.5 — drafts-tray "send →" target. Wraps `UIActivityViewController`
// as the *interim* sharing surface; v0.6 replaces this with the Trusted Circle
// selector (Curve25519 + circle picker).
//
// PRD FR-SNAP-DRAFT-07 — opens the iOS share sheet for the asset. The source
// row stays in the tray after sharing (FR-SNAP-DRAFT-08); only the 24h
// ceiling or explicit user save decides lifecycle.

import UIKit

@MainActor
public final class ShareHandoffCoordinator {

    /// Excluded per Piqd's editorial constraints — these don't make sense for
    /// ephemeral Snap captures. Exposed for testing.
    public static let excludedActivityTypes: [UIActivity.ActivityType] = [
        .assignToContact,
        .print,
        .openInIBooks,
    ]

    public init() {}

    /// Present the activity sheet for `url`. `sourceView` is the row's "send →"
    /// button — used as the iPad popover anchor. iPhone presentations ignore it.
    public func share(url: URL, sourceView: UIView? = nil) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        activityVC.excludedActivityTypes = Self.excludedActivityTypes

        if let pop = activityVC.popoverPresentationController, let sourceView {
            pop.sourceView = sourceView
            pop.sourceRect = sourceView.bounds
        }

        guard let presenter = Self.topViewController() else { return }
        presenter.present(activityVC, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
