import UIKit

@MainActor
enum ContextMenuPresenter {
    @discardableResult
    static func present(
        configuration: ContextMenuConfiguration,
        from sourceView: UIView,
        presentation: ContextMenuPresentationMode = .overlay,
        presentationReference: ContextMenuPresentationReference? = nil
    ) -> (any ContextMenuPresentationSession)? {
        guard let window = sourceView.window else {
            return nil
        }
        let configuration = configuration.resolved(for: sourceView)
        let resolvedPresentationReference = presentationReference ?? ContextMenuPresentationReference.from(view: sourceView)
        let sourceUserInterfaceStyle = ContextMenuVisuals.resolvedUserInterfaceStyle(for: sourceView.traitCollection)
        let sourceUserInterfaceLayoutDirection = sourceView.effectiveUserInterfaceLayoutDirection

        let usesRegularWidthLayout: Bool = switch sourceView.traitCollection.horizontalSizeClass {
        case .regular:
            true
        case .compact:
            false
        case .unspecified:
            window.traitCollection.horizontalSizeClass == .regular
        @unknown default:
            false
        }

        switch presentation.resolved(usesRegularWidthLayout: usesRegularWidthLayout) {
        case .overlay:
            return self.presentOverlay(
                configuration: configuration,
                sourceView: sourceView,
                window: window,
                presentationReference: resolvedPresentationReference,
                sourceUserInterfaceStyle: sourceUserInterfaceStyle,
                sourceUserInterfaceLayoutDirection: sourceUserInterfaceLayoutDirection
            )
        case .zoomPopover:
            if #available(iOS 26.0, *),
               let transitionSourceView = resolvedPresentationReference.transitionSourceView,
               let presentingViewController = self.presentingViewController(for: sourceView) {
                let popoverViewController = ContextMenuPopoverViewController(
                    configuration: configuration,
                    sourceView: transitionSourceView,
                    sourceUserInterfaceStyle: sourceUserInterfaceStyle,
                    sourceUserInterfaceLayoutDirection: sourceUserInterfaceLayoutDirection
                )
                presentingViewController.present(popoverViewController, animated: true)
                return popoverViewController
            }

            return self.presentOverlay(
                configuration: configuration,
                sourceView: sourceView,
                window: window,
                presentationReference: resolvedPresentationReference,
                sourceUserInterfaceStyle: sourceUserInterfaceStyle,
                sourceUserInterfaceLayoutDirection: sourceUserInterfaceLayoutDirection
            )
        case .zoomSheet:
            if #available(iOS 26.0, *),
               let transitionSourceView = resolvedPresentationReference.transitionSourceView,
               let presentingViewController = self.presentingViewController(for: sourceView) {
                let sheetViewController = ContextMenuSheetViewController(
                    configuration: configuration,
                    sourceView: transitionSourceView,
                    sourceUserInterfaceStyle: sourceUserInterfaceStyle,
                    sourceUserInterfaceLayoutDirection: sourceUserInterfaceLayoutDirection
                )
                let sheetHost = configuration.sheetNavigationControllerProvider?(sheetViewController)
                    ?? sheetViewController
                sheetViewController.configurePresentation(on: sheetHost, sourceView: transitionSourceView)
                presentingViewController.present(sheetHost, animated: true)
                return sheetViewController
            }

            return self.presentOverlay(
                configuration: configuration,
                sourceView: sourceView,
                window: window,
                presentationReference: resolvedPresentationReference,
                sourceUserInterfaceStyle: sourceUserInterfaceStyle,
                sourceUserInterfaceLayoutDirection: sourceUserInterfaceLayoutDirection
            )
        }
    }

    private static func presentOverlay(
        configuration: ContextMenuConfiguration,
        sourceView: UIView,
        window: UIWindow,
        presentationReference: ContextMenuPresentationReference,
        sourceUserInterfaceStyle: UIUserInterfaceStyle,
        sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection
    ) -> ContextMenuOverlayView {
        let overlayView = ContextMenuOverlayView(
            configuration: configuration,
            sourceRectInWindow: presentationReference.anchorRectInWindow,
            appearanceSourceView: sourceView,
            portalSourceView: presentationReference.portalSourceView,
            portalMaskRectInWindow: presentationReference.portalMaskRectInWindow,
            portalMask: presentationReference.portalMask,
            portalShowsBackdropCutout: presentationReference.portalShowsBackdropCutout,
            portalAppliesRightToLeftTransformCorrection: presentationReference.portalAppliesRightToLeftTransformCorrection,
            sourceUserInterfaceStyle: sourceUserInterfaceStyle,
            sourceUserInterfaceLayoutDirection: sourceUserInterfaceLayoutDirection
        )
        overlayView.frame = window.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlayView)
        overlayView.activatePresentationIfNeeded()
        return overlayView
    }

    private static func presentingViewController(for sourceView: UIView) -> UIViewController? {
        var responder: UIResponder? = sourceView
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return self.topPresentedViewController(from: viewController)
            }
            responder = currentResponder.next
        }

        guard let rootViewController = sourceView.window?.rootViewController else {
            return nil
        }
        return self.topPresentedViewController(from: rootViewController)
    }

    private static func topPresentedViewController(from rootViewController: UIViewController) -> UIViewController {
        var viewController = rootViewController
        while let presentedViewController = viewController.presentedViewController,
              !presentedViewController.isBeingDismissed {
            viewController = presentedViewController
        }
        return viewController
    }
}
