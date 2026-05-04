import SwiftUI
import WalletCore
import WalletContext

public struct ChainIcon: View {
    public enum Separator: Equatable {
        case none
        case hairline
        case fixed(CGFloat)
        case custom(String)
    }
    
    public let chain: ApiChain
    public let color: Color?

    public init(_ chain: ApiChain, color: Color? = nil) {
        self.chain = chain
        self.color = color
    }
    
    private var symbolName: String? {
        Self.symbolName(for: chain)
    }

    private var symbolImage: Image? {
        guard let symbolName else { return nil }
        return Image.airBundle(symbolName)
    }

    @ViewBuilder
    public var body: some View {
        if let symbolImage {
            if let color {
                symbolImage
                    .foregroundStyle(color)
            } else {
                symbolImage
            }
        }
    }
    
    public var text: Text {
        guard let symbolImage else { return Text("") }
        let t = Text(symbolImage)
        if let color { return t.foregroundColor(color) }
        return t
    }

    public func prepended(to text: Text, separator: Separator = .none) -> Text {
        guard let symbolImage else { return text }
        var iconText = Text(symbolImage)
        if let color {
            iconText = iconText.foregroundColor(color)
        }
        return iconText + separator.text + text
    }
    
    public func prepended(to attr: NSAttributedString, separator: Separator = .none) -> NSAttributedString {
        guard var image = Self.uiImageForChain(chain) else { return attr }
        if let color {
            image = image.withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
        }

        let textAttachment = NSTextAttachment(image: image)
        let result = NSMutableAttributedString(attachment: textAttachment)

        result.append(separator.attributedString(font: nil))
        
        result.append(attr)
        return result
    }

    public func prepended(
        to string: String,
        font: UIFont,
        attributes: [NSAttributedString.Key: Any] = [:],
        separator: Separator = .none
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if var image = Self.uiImageForChain(chain) {
            if let color {
                image = image.withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
            }
            result.append(NSAttributedString(attachment: NSTextAttachment(image: image)))
            result.append(separator.attributedString(font: nil))
        }
        result.append(NSAttributedString(string: string))

        var attributes = attributes
        attributes[.font] = font
        if result.length > 0 {
            result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
        }
        return result
    }
}

private extension ChainIcon.Separator {

    var text: Text {
        switch self {
        case .none:
            Text("")
        case .hairline:
            Text("\u{200A}")
        case .fixed(let width):
            Text(Self.hairlineString(width: width, uiFont: Self.fallbackFont))
        case .custom(let string):
            Text(string)
        }
    }

    func attributedString(font: UIFont?) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any]? = if let font {
            [.font: font]
        } else {
            nil
        }

        return switch self {
        case .none:
            NSAttributedString()
        case .hairline:
            NSAttributedString(string: "\u{200A}", attributes: attrs)
        case .fixed(let width):
            Self.fixedWidthString(width: width)
        case .custom(let string):
            NSAttributedString(string: string, attributes: attrs)
        }
    }

    static func hairlineString(width: CGFloat, uiFont: UIFont) -> String {
        guard width > 0 else { return "" }
        let hairlineWidth = max(uiFont.pointSize / 24, 0.5)
        let count = max(1, Int((width / hairlineWidth).rounded()))
        return String(repeating: "\u{200A}", count: count)
    }

    static func fixedWidthString(width: CGFloat) -> NSAttributedString {
        guard width > 0 else { return NSAttributedString() }
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: 1)).image { _ in }
        let attachment = NSTextAttachment(image: image)
        attachment.bounds = CGRect(x: 0, y: 0, width: width, height: 1)
        return NSAttributedString(attachment: attachment)
    }

    private static let fallbackFont = UIFont.systemFont(ofSize: 17)
}

private extension ChainIcon {

    static func symbolName(for chain: ApiChain) -> String? {
        let name = "inline.chain.\(chain.rawValue)"
        return UIImage.airBundleOptional(name) == nil ? nil : name
    }

    static func uiImageForChain(_ chain: ApiChain) -> UIImage? {
        guard let symbolName = symbolName(for: chain) else { return nil }
        let configuration = UIImage.SymbolConfiguration(scale: .small)
        return UIImage.airBundleOptional(symbolName)?
            .withConfiguration(configuration)
            .withRenderingMode(.alwaysTemplate)
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview("ChainIcon") {
    
    struct PrependTile: UIViewRepresentable {
        let icon: ChainIcon
        let address: String
        let font: UIFont

        func makeUIView(context: Context) -> UILabel {
            let label = UILabel()
            label.numberOfLines = 0
            return label
        }

        func updateUIView(_ uiView: UILabel, context: Context) {
            uiView.font = font
            uiView.attributedText = icon.prepended(to: address, font: font, separator: .hairline)
            uiView.textColor = .secondaryLabel
        }
    }

    let chains: [ApiChain] = [.ton, .tron, .solana, .other("other_chain")]
    let samples: [(title: String, font: Font, uiFont: UIFont)] = [
        ("12 regular", .system(size: 12), .systemFont(ofSize: 12)),
        ("14 semibold", .system(size: 14, weight: .semibold), .systemFont(ofSize: 14, weight: .semibold)),
        ("17 regular", .system(size: 17), .systemFont(ofSize: 17)),
    ]

    return ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(samples, id: \.title) { sample in

                VStack(alignment: .leading, spacing: 8) {
                    Text("Font: \(sample.title)").font(.headline)

                    // NSAttributedString prepend
                    ForEach(chains, id: \.self) { chain in
                        let icon = ChainIcon(chain)

                        HStack {
                            PrependTile(icon: icon, address: "EQAG0273409823", font: sample.uiFont)
                            PrependTile(icon: icon, address: "@\(chain.rawValue)_domain", font: sample.uiFont)
                        }
                    }

                    // Text prepend
                    ForEach(chains, id: \.self) { chain in
                        let icon = ChainIcon(chain, color: .red)

                        HStack {
                            icon.prepended(to: Text("EQAG0273409823"), separator: .hairline)
                            icon.prepended(to: Text("@\(chain.rawValue)_domain"), separator: .hairline)
                        }
                        .font(sample.font)
                        .imageScale(.small)
                    }

                    // SwiftUI Text interpolation
                    ForEach(chains, id: \.self) { chain in
                        let icon = ChainIcon(chain)
                        let ownColorIcon = ChainIcon(chain, color: .green)

                        Text("Inlined \(icon.text), \(icon.text.foregroundColor(.blue)), \(ownColorIcon.text) into a text")
                            .font(sample.font)
                            .imageScale(.small)
                            .foregroundColor(Color(.orange))
                    }
                    
                    // Swift-UI stand-alone
                    HStack {
                        ForEach(chains, id: \.self) { chain in
                            ChainIcon(chain)
                            ChainIcon(chain, color: .purple)
                            ChainIcon(chain).foregroundColor(.orange)
                        }
                        Text("Some text")
                    }
                    .font(sample.font)
                    .imageScale(.small)
                    .foregroundStyle(.primary)
                    .background(Color.blue.opacity(0.1))
                }
            }
        }
        .padding()
    }
}
#endif
