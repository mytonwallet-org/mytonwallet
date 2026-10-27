import XCTest
import UIKit
import WalletContext
import WalletCore
import WalletResources
@testable import UIComponents

@MainActor
final class MtwCardAccountLineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    func testEmojiKeepsNativeColorsForEveryCardStyle() throws {
        let view = MtwCardAccountLineView()
        for nft in cards {
            for name in ["🌈", "👩🏽‍💻", "🇬🇧", "1️⃣", "❤️", "👨‍👩‍👧‍👦"] {
                configure(view, name: name, width: 300, nft: nft)
                let label = try nameLabel(in: view)
                let reference = UILabel(frame: label.bounds)
                reference.font = label.font
                reference.text = name
                reference.textColor = .white
                reference.alpha = label.alpha
                let host = UIView(frame: reference.bounds)
                host.addSubview(reference)
                let rect = label.convert(label.bounds, to: view)
                XCTAssertEqual(try pixels(snapshot(view, rect: rect)), try pixels(snapshot(host)), "Native colors: \(name), \(String(describing: nft?.metadata?.mtwCardType))")
            }
        }
    }

    func testRenamingResizingAndChangingStyleMatchesFreshRendering() throws {
        let view = MtwCardAccountLineView()
        for rtl in [false, true] {
            for nft in cards {
                for width in [300.0, 130, 420] {
                    for name in ["A 🌈", "Savings 👩🏽‍💻 with a very long name that must truncate", "🇬🇧 Travel", "عائلتي ❤️", "A 🌈"] {
                        configure(view, name: name, width: width, nft: nft, rtl: rtl)
                        let fresh = MtwCardAccountLineView()
                        configure(fresh, name: name, width: width, nft: nft, rtl: rtl)
                        let actual = snapshot(view)
                        let expected = snapshot(fresh)
                        if try pixels(actual) != pixels(expected) {
                            for (name, image) in [("Reused", actual), ("Fresh", expected)] {
                                let attachment = XCTAttachment(image: image)
                                attachment.name = name
                                attachment.lifetime = .keepAlways
                                add(attachment)
                            }
                        }
                        XCTAssertEqual(try pixels(actual), try pixels(expected), "Stale paint after changing to \(name), width \(width), RTL \(rtl), card \(String(describing: nft?.metadata?.mtwCardType))")
                        XCTAssertEqual(view.addressesButton.accessibilityLabel, name)
                        let label = try nameLabel(in: view)
                        XCTAssertEqual(label.lineBreakMode, .byTruncatingTail)
                        XCTAssertLessThanOrEqual(label.frame.width, view.addressesButton.bounds.width)
                    }
                }
            }
        }
        view.prepareForReuse()
        configure(view, name: "Reused 🌈", width: 300, nft: cards[2])
        let fresh = MtwCardAccountLineView()
        configure(fresh, name: "Reused 🌈", width: 300, nft: cards[2])
        XCTAssertEqual(try pixels(snapshot(view)), try pixels(snapshot(fresh)))
    }

    func testTextGradientStaysAlignedWithMaskedIcons() throws {
        let view = MtwCardAccountLineView()
        for rtl in [false, true] {
            for nft in cards {
                for name in ["Wallet", "A much longer wallet name to truncate", "短い名前", "عائلتي"] {
                    configure(view, name: name, width: 200, nft: nft, rtl: rtl)
                    let label = try nameLabel(in: view)
                    let foreground = try XCTUnwrap(view.addressesButton.subviews.compactMap { $0 as? MtwCardForegroundView }.first)
                    let mask = try XCTUnwrap(foreground.mask)
                    let actual = try pixels(snapshot(view))
                    let color = label.textColor
                    mask.addSubview(label)
                    label.textColor = .white
                    let original = try pixels(snapshot(view))
                    view.addressesButton.addSubview(label)
                    label.textColor = color
                    XCTAssertEqual(actual.count, original.count)
                    let error = zip(actual, original).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
                    XCTAssertLessThan(Double(error) / Double(actual.count), 0.15, "Gradient alignment: \(name), RTL \(rtl)")
                }
            }
        }
    }

    private var cards: [ApiNft?] {
        [nil] + ApiMtwCardType.allCases.map { type in
            var nft = ApiNft.sampleMtwCard
            nft.address = "test-card-\(type.rawValue)"
            nft.metadata?.mtwCardType = type
            return nft
        } + [darkCard]
    }

    private var darkCard: ApiNft {
        var nft = ApiNft.sampleMtwCard
        nft.address = "test-card-standard-dark"
        nft.metadata?.mtwCardType = .standard
        nft.metadata?.mtwCardTextType = .dark
        return nft
    }

    private func configure(_ view: MtwCardAccountLineView, name: String, width: CGFloat, nft: ApiNft?, rtl: Bool = false) {
        let account = MAccount(id: "0-mainnet", title: name, type: .hardware,
                               byChain: [.ton: AccountChain(address: "UQDQ7EXuEywyezyEWzfNkHZTSbe8qbPKETFYHr_KTZnnJ-xL")])
        view.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        view.frame = CGRect(x: 0, y: 0, width: width, height: 40)
        view.configure(address: account.addressLine(orderedChains: account.orderedChains), name: name,
                       showsName: true, isTemporary: false, nft: nft)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func nameLabel(in view: MtwCardAccountLineView) throws -> UILabel {
        try XCTUnwrap(view.addressesButton.subviews.compactMap { $0 as? UILabel }.first)
    }

    private func snapshot(_ view: UIView, rect: CGRect? = nil) -> UIImage {
        view.layoutIfNeeded()
        let rect = rect ?? view.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            view.layer.render(in: context.cgContext)
        }
    }

    private func pixels(_ image: UIImage) throws -> Data {
        let image = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        // Compare visible pixels, excluding any alignment padding between rows.
        let rowBytes = image.width * image.bitsPerPixel / 8
        var pixels = Data(capacity: rowBytes * image.height)
        for row in 0..<image.height {
            let start = row * image.bytesPerRow
            pixels.append(data[start..<(start + rowBytes)])
        }
        return pixels
    }
}
