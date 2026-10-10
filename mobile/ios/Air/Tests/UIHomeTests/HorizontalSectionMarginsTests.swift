import SwiftUI
import UIKit
import XCTest
import UIActivityList
import UIComponents

@MainActor
final class HorizontalSectionMarginsTests: XCTestCase {
    func testCustomSectionsShareNativeMarginsWithoutClippingOverflow() async throws {
        let host = UIViewController()
        host.viewRespectsSystemMinimumLayoutMargins = false
        let descriptor = ActivityListViewController.CustomSectionDescriptor(id: "custom", usesInsetGroupedMargins: true) { _, _ in
            UICollectionViewCell()
        }
        let layout = UICollectionViewCompositionalLayout { index, environment in
            if index == 1 { return descriptor.makeLayoutSection(layoutEnvironment: environment) }
            return .list(using: .init(appearance: .insetGrouped), layoutEnvironment: environment)
        }
        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        host.view.addSubview(collection)
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { cell, _, _ in
            var content = UIListContentConfiguration.cell()
            content.text = "Fixture"
            cell.contentConfiguration = content
        }
        let customRegistration = UICollectionView.CellRegistration<SectionOverflowProbeCell, Int> { _, _, _ in }
        let dataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collection) { collection, indexPath, item in
            if indexPath.section == 1 {
                return collection.dequeueConfiguredReusableCell(using: customRegistration, for: indexPath, item: item)
            }
            return collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        for index in 0...1 {
            snapshot.appendSections([index])
            snapshot.appendItems([index])
        }
        await dataSource.apply(snapshot, animatingDifferences: false)

        let marker = UIView()
        let hosting = LayoutMarginsHostingController(rootView: MarginProbeContent(marker: marker))
        host.addChild(hosting)
        host.view.addSubview(hosting.view)
        hosting.didMove(toParent: host)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
            for (width, left, right) in [(466.0, 84.0, 0.0), (466, 0, 84), (466, 84, 24), (466, 24, 84), (402, 0, 0), (1024, 84, 0), (1024, 0, 84)] {
                let rtl = direction == .forceRightToLeft
                host.view.semanticContentAttribute = direction
                hosting.view.semanticContentAttribute = direction
                if #available(iOS 17, *) {
                    host.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight
                    hosting.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight
                }
                host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: left, bottom: 0, right: right)
                host.view.directionalLayoutMargins = NSDirectionalEdgeInsets(
                    top: 0, leading: (rtl ? right : left) > 0 ? 0 : 20,
                    bottom: 0, trailing: (rtl ? left : right) > 0 ? 0 : 20
                )
                window.frame.size.width = width
                host.view.frame = window.bounds
                collection.frame = host.view.bounds
                hosting.view.frame = host.view.bounds
                layout.invalidateLayout()
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                window.layoutIfNeeded()
                let name = "\(width)-\(left)-\(right)-RTL=\(rtl)"
                let native = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)), name).frame
                let custom = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 1)), name).frame
                XCTAssertEqual(custom.minX, native.minX, accuracy: 1, name)
                XCTAssertEqual(custom.maxX, native.maxX, accuracy: 1, name)
                let cell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 1)), name)
                for point in [
                    CGPoint(x: 2, y: cell.bounds.height - 2),
                    CGPoint(x: 6, y: cell.bounds.height + 6),
                    CGPoint(x: cell.bounds.width - 6, y: cell.bounds.height + 6),
                ] {
                    let sample = cell.convert(point, to: collection)
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    format.preferredRange = .standard
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { context in
                        context.cgContext.translateBy(x: -sample.x, y: -sample.y)
                        collection.layer.render(in: context.cgContext)
                    }
                    let data = try XCTUnwrap(image.cgImage?.dataProvider?.data, name)
                    let pixel = try XCTUnwrap(CFDataGetBytePtr(data), name)
                    XCTAssertGreaterThan(pixel[0], 240, "Clipped overflow at \(point): \(name)")
                    XCTAssertLessThan(pixel[1], 15, "Clipped overflow at \(point): \(name)")
                    XCTAssertGreaterThan(pixel[2], 240, "Clipped overflow at \(point): \(name)")
                }
                let margins = host.view.layoutMarginsGuide.layoutFrame
                let swiftUI = marker.convert(marker.bounds, to: host.view)
                XCTAssertEqual(swiftUI.minX, margins.minX, accuracy: 1, name)
                XCTAssertEqual(swiftUI.maxX, margins.maxX, accuracy: 1, name)
            }
        }
    }
}

private final class SectionOverflowProbeCell: UICollectionViewCell {
    private let overflowView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        contentView.clipsToBounds = false
        overflowView.backgroundColor = .magenta
        contentView.addSubview(overflowView)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        overflowView.frame = contentView.bounds.insetBy(dx: -8, dy: -8)
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size.height = 100
        return attributes
    }
}

private struct MarginProbeContent: View {
    @Environment(\.horizontalContentMargins) private var margins
    let marker: UIView

    var body: some View {
        MarginMarker(view: marker).frame(height: 32).padding(margins)
    }
}

private struct MarginMarker: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
