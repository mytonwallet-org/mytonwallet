import SwiftUI
import Testing
import UIKit
import WalletResources
@testable import UIToken

@Suite(.serialized) @MainActor
struct AssetInfoLayoutTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func aChangeTooWideForOneLineWrapsInsteadOfTruncating() throws {
        func height(width: CGFloat, previous: String, value: String) -> CGFloat {
            let row = AssetInfoMetricRow(title: "Liquidation Price", info: "Hint", value: value, previousValue: previous)
            return UIHostingController(rootView: row).sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        }
        #expect(height(width: 340, previous: "$108 002.01", value: "≈ $108 950.12") > 60)
        #expect(height(width: 700, previous: "$108 002.01", value: "≈ $108 950.12") == 48)
        #expect(height(width: 340, previous: "$1", value: "$2") == 48)

        let renderer = ImageRenderer(content: AssetInfoMetricRow(title: "Liquidation Price", info: "Hint",
                                                                 value: "≈ $108 950.12", previousValue: "$108 002.01")
            .frame(width: 340)
            .background(Color.white))
        renderer.scale = 2
        Attachment.record(try #require(renderer.uiImage?.pngData()), named: "liquidation-price-change.png")
    }

    /// A section that grows is measured while its host still has the previous height; centered, it would move.
    @Test func hostedSectionStaysAtTheTopWhileItsHostCatchesUp() async throws {
        let section = GrowingSection()
        let controller = UIHostingController(rootView: GrowingSectionView(section: section))
        AssetDetailsView.prepare(controller)
        let container = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 800))
        window.rootViewController = container
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        container.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
        ])
        controller.didMove(toParent: container)
        for height: CGFloat in [100, 40, 160] {
            section.height = height
            try await Task.sleep(for: .milliseconds(150))
            container.view.layoutIfNeeded()
            #expect(controller.view.bounds.height == height)
        }
        #expect(controller.sizeThatFits(in: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)).height == 160)
        #expect(!section.tops.isEmpty)
        #expect(section.tops.allSatisfy { $0 == 0 })
    }
}

@Observable private final class GrowingSection {
    var height: CGFloat = 100
    @ObservationIgnored var tops: [CGFloat] = []
}

private struct GrowingSectionView: View {
    let section: GrowingSection

    var body: some View {
        Color.clear.frame(height: section.height)
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { section.tops.append($0) }
            .alignedToHostTop()
    }
}
