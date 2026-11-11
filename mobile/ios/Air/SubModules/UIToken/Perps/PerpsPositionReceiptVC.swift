import Perception
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
public final class PerpsPositionReceiptVC: WViewController, UISheetPresentationControllerDelegate {
    public var onVisibilityChanged: ((Bool) -> Void)?
    private static let compactDetent = UISheetPresentationController.Detent.Identifier("perpsReceipt")
    public var data: PerpsPositionReceiptDisplayData { presentation.data }
    private let onShare: (() -> Void)?
    private let onStatus: (() -> Void)?
    private let presentation: PerpsPositionReceiptPresentation
    private var compactContentHeight: CGFloat = 264
    private var presentationMode: SheetPresentationMode?
    private var contentLayout: AssetDetailsView?

    public init(data: PerpsPositionReceiptDisplayData, onShare: (() -> Void)? = nil, onStatus: (() -> Void)? = nil) {
        self.presentation = PerpsPositionReceiptPresentation(data: data)
        self.onShare = onShare
        self.onStatus = onStatus
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private var receiptSheet: UISheetPresentationController? {
        (navigationController ?? self).sheetPresentationController
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        updatePresentationMode()
        view.backgroundColor = .air.sheetBackground
        configureNavigationItemWithTransparentBackground()
        let presentation = presentation
        navigationItem.titleView = HostingView {
            WithPerceptionTracking {
                NavigationHeader { Text(presentation.data.title) } subtitle: {
                    Text(presentation.data.timestamp.dateTimeString).textStyle(.footnote, content: .technical)
                        + Text(presentation.detailsExpanded
                               ? (presentation.data.event.outcome?.heldDuration.map { " · " + L10n.perpsHeld(duration: $0) } ?? "")
                               : "")
                            .textStyle(.footnote)
                }
            }
        }
        navigationItem.hidesBackButton = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        let content = addHostingController(PerpsPositionReceiptView(
            presentation: presentation, onDetails: { [weak self] in self?.showDetails() },
            onShare: onShare, onHeightChange: { [weak self] in self?.contentHeightChanged($0) }
        ))
        AssetDetailsView.prepare(content)
        let layout = AssetDetailsView(sections: [content.view], footer: nil, background: .air.sheetBackground)
        contentLayout = layout
        layout.scrollView.isScrollEnabled = presentation.detailsExpanded
        layout.install(in: view)
        addCustomNavigationBarBackground(color: .air.sheetBackground)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePresentationMode()
        onVisibilityChanged?(true)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onVisibilityChanged?(false)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updatePresentationMode()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePresentationMode()
    }

    public func prepareForPresentation(from presenter: UIViewController) {
        updatePresentationMode(sheetPresentationMode(presentingFrom: presenter))
    }

    public func update(data: PerpsPositionReceiptDisplayData) {
        let animated = viewIfLoaded?.window != nil && AppStorageHelper.animations
            && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
        withAnimation(animated ? .default : nil) {
            presentation.data = data
        }
    }

    /// Called alongside ProtectedAction's content replacement, as in ActivityDetailsVC.
    public func animateToCollapsed() {
        updatePresentationMode()
        guard let sheet = receiptSheet else { return }
        sheet.animateChanges {
            sheet.detents = presentation.canCollapse ? makeDetents() : [.large()]
            sheet.selectedDetentIdentifier = presentation.canCollapse ? Self.compactDetent : .large
            sheet.prefersGrabberVisible = presentation.canCollapse
            setDetailsExpanded(!presentation.canCollapse)
        }
    }

    private func updatePresentationMode() {
        updatePresentationMode(sheetPresentationMode)
    }

    private func updatePresentationMode(_ mode: SheetPresentationMode?) {
        guard let mode, mode != presentationMode else { return }
        let replacingConfirmation = presentationMode == nil && (navigationController?.viewControllers.count ?? 1) > 1
        presentationMode = mode
        presentation.canCollapse = mode == .bottomAttached
        setDetailsExpanded(!presentation.canCollapse || replacingConfirmation)
        (navigationController ?? self).preferredContentSize = mode == .floating ? CGSize(width: 580, height: 720) : .zero
        guard let sheet = receiptSheet else { return }
        sheet.delegate = self
        sheet.prefersGrabberVisible = presentation.canCollapse
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        if #available(iOS 26.1, *) { sheet.backgroundEffect = UIColorEffect(color: .air.sheetBackground) }
        sheet.detents = presentation.canCollapse ? makeDetents() : [.large()]
        sheet.selectedDetentIdentifier = presentation.canCollapse && !replacingConfirmation ? Self.compactDetent : .large
    }

    private func makeDetents() -> [UISheetPresentationController.Detent] {
        return [.custom(identifier: Self.compactDetent) { [weak self] context in
            // The summary sits 8 points into the scroll content, below the 44-point navigation bar.
            min((self?.compactContentHeight ?? 264) + 52, context.maximumDetentValue)
        }, .large()]
    }

    private func contentHeightChanged(_ height: CGFloat) {
        guard presentation.canCollapse, !presentation.detailsExpanded, abs(compactContentHeight - height) > 0.5 else { return }
        compactContentHeight = height
        if let sheet = receiptSheet, viewIfLoaded?.window != nil, !(navigationController ?? self).isBeingPresented {
            sheet.animateChanges { sheet.invalidateDetents() }
        } else {
            receiptSheet?.invalidateDetents()
        }
    }

    private func showDetails() {
        if data.status.message != nil, let onStatus { onStatus() }
        else { toggleDetails() }
    }

    private func toggleDetails() {
        guard presentation.canCollapse else { return }
        guard let sheet = receiptSheet else {
            setDetailsExpanded(!presentation.detailsExpanded)
            return
        }
        let expands = !presentation.detailsExpanded
        setDetailsExpanded(expands)
        sheet.animateChanges {
            sheet.selectedDetentIdentifier = expands ? .large : Self.compactDetent
            sheet.prefersGrabberVisible = !expands
        }
    }

    public func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        setDetailsExpanded(sheetPresentationController.selectedDetentIdentifier != Self.compactDetent)
        sheetPresentationController.prefersGrabberVisible = !presentation.detailsExpanded
    }

    private func setDetailsExpanded(_ expanded: Bool) {
        presentation.detailsExpanded = expanded
        contentLayout?.scrollView.isScrollEnabled = expanded
        if !expanded, let scroll = contentLayout?.scrollView {
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
        }
    }
}
