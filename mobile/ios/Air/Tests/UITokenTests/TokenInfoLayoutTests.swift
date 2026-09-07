import SwiftUI
import Testing
import UIKit
@testable import UIToken
import WalletCore
import WalletResources

@MainActor
@Suite("Token Info Layout", .serialized)
struct TokenInfoLayoutTests {
    @Test
    func `reconfiguring during crossfade keeps the measured hosting height`() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = TokenInfoModel(state: .loading, isExpanded: true)
        let cell = TokenInfoCell(frame: CGRect(x: 0, y: 100, width: 390, height: TokenInfoModel.collapsedHeight))
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.addSubview(cell)

        let updateHeight = { [weak cell] in
            guard let cell else { return }
            cell.frame.size.height = cell.height ?? 0
            cell.layoutIfNeeded()
        }
        cell.configure(model: model, onHeightChange: updateHeight, onUserToggleAnimationChange: { _ in })
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        model.configure(state: .details(ApiTokenDetails(
            description: String(repeating: "A long token description. ", count: 30),
            links: nil,
            marketCap: nil,
            circulatingSupply: nil,
            totalSupply: nil,
            createdAt: nil,
            volume24h: nil
        )))
        cell.modelStateDidChange()

        for _ in 0..<100 {
            window.layoutIfNeeded()
            if model.pendingPresentationRevision == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.pendingPresentationRevision == nil)
        #expect(model.presentationOverlay != nil)
        #expect(model.measuredExpandedHeight > TokenInfoModel.collapsedHeight)
        cell.configure(model: model, onHeightChange: updateHeight, onUserToggleAnimationChange: { _ in })
        updateHeight()
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()

        let host = try #require(cell.contentView.subviews.first?.subviews.first)
        #expect(abs(host.bounds.height - model.measuredExpandedHeight) < 1)
        #expect(abs(cell.bounds.height - model.measuredExpandedHeight) < 1)
    }

    @Test(arguments: [true, false])
    func `content stays at the top when the host and content heights differ`(isExpanded: Bool) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = TokenInfoModel(state: .loading, isExpanded: isExpanded)
        var contentHeight = CGFloat.zero
        var contentFrame: CGRect?
        let hostingView = UIHostingConfiguration {
            TokenInfoView(model: model) { height, _ in
                contentHeight = height
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
                contentFrame = $0
            }
        }
        .margins(.all, 0)
        .makeContentView()

        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        hostingView.frame = CGRect(x: 16, y: 100, width: 358, height: TokenInfoModel.collapsedHeight)
        controller.view.addSubview(hostingView)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let initialFrame = try #require(contentFrame)
        #expect(abs(contentHeight - TokenInfoModel.collapsedHeight) < 1)

        let details = ApiTokenDetails(
            description: String(repeating: "A long token description. ", count: 30),
            links: nil,
            marketCap: 7_580_000_000,
            circulatingSupply: nil,
            totalSupply: nil,
            createdAt: nil,
            volume24h: nil
        )
        model.configure(state: .details(details))
        hostingView.setNeedsLayout()
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        #expect(contentHeight > TokenInfoModel.collapsedHeight)
        let frame = try #require(contentFrame)
        #expect(abs(frame.minY - initialFrame.minY) < 1)

        model.updateMeasuredExpandedHeight(contentHeight)
        model.beginPresentationTransition(revision: model.layoutRevision, animated: false)
        model.setExpansionProgress(model.targetExpansionProgress)
        hostingView.frame.size.height = contentHeight
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        // During a shrinking transition the outgoing layer is taller than the new host.
        model.configure(state: .error)
        hostingView.frame.size.height = TokenInfoModel.collapsedHeight
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        #expect(abs(contentHeight - TokenInfoModel.collapsedHeight) < 1)
        let shrinkingFrame = try #require(contentFrame)
        #expect(abs(shrinkingFrame.minY - initialFrame.minY) < 1)
    }
}
