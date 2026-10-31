import FixaKit
import SafariServices
import SwiftUI
import UIKit

/// The kommun's own pages (contact page, web form, information) open in an in-app Safari view, so the
/// resident comes back to Fixa with one tap. Only https pages on the adapter's `allowedWebHosts` do;
/// every other URL (other sites, `tel:`, `mailto:`) goes to the system as before.
enum KommunWeb {
    /// Opens `url`: in the in-app Safari view when `spec` allows it, else through the system.
    static func open(_ url: URL, spec: AdapterSpec?) {
        if spec?.opensInApp(url) == true, present(url) { return }
        UIApplication.shared.open(url)
    }

    /// Presents `url` in an `SFSafariViewController` over whatever is on screen (sheets included).
    /// False when there is no window to present from.
    @discardableResult
    static func present(_ url: URL) -> Bool {
        guard let top = topViewController() else { return false }
        let safari = SFSafariViewController(url: url)
        safari.dismissButtonStyle = .done
        safari.preferredControlTintColor = UIColor(Fx.Color.sea)
        top.present(safari, animated: true)
        return true
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

extension View {
    /// Routes `openURL` and `Link` in this view through `KommunWeb.open`: the kommun's pages open in
    /// the in-app Safari view, everything else as before.
    func kommunWebLinks(spec: AdapterSpec) -> some View {
        environment(\.openURL, OpenURLAction { url in
            spec.opensInApp(url) && KommunWeb.present(url) ? .handled : .systemAction
        })
    }
}
