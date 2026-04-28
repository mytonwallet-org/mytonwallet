import SwiftUI
import WalletCore
import WalletContext

public struct ChainIcon: View {
    public enum Style: CaseIterable {
        case s12, s14, s16, sDefault
    }

    public enum Separator: Equatable {
        case none
        case hairline
        case fixed(CGFloat)
        case custom(String)
    }
    
    public let chain: ApiChain
    public let style: Style
    public let color: Color?
    private let customFont: Font?
    private let customUIKitFont: UIFont?

    public init(_ chain: ApiChain, style: Style, color: Color? = nil) {
        self.chain = chain
        self.style = style
        self.color = color
        self.customFont = nil
        self.customUIKitFont = nil
    }

    public init(_ chain: ApiChain, font: Font, color: Color? = nil) {
        self.chain = chain
        self.style = .sDefault
        self.color = color
        self.customFont = font
        self.customUIKitFont = nil
    }

    public init(_ chain: ApiChain, font: Font, uiFont: UIFont, color: Color? = nil) {
        self.chain = chain
        self.style = .sDefault
        self.color = color
        self.customFont = font
        self.customUIKitFont = uiFont
    }
    
    private var symbolName: String? {
        styleData.symbolName(for: chain)
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
                    .font(preferredFont)
                    .imageScale(.small)
                    .foregroundStyle(color)
            } else {
                symbolImage
                    .font(preferredFont)
                    .imageScale(.small)
            }
        }
    }
    
    public var text: Text {
        guard let symbolImage else { return Text("") }
        let t = Text(symbolImage).font(preferredFont)
        if let color { return t.foregroundColor(color) }
        return t
    }

    public func prepended(to text: Text, separator: Separator = .none) -> Text {
        guard let symbolImage else { return text }
        var iconText = Text(symbolImage).font(preferredFont)
        if let color { iconText = iconText.foregroundColor(color) }
        return Text("\(iconText)\(separator.text(font: preferredFont, uiFont: preferredUIKitFont))\(text)")
    }
    
    public func prepended(to attr: NSAttributedString, separator: Separator = .none) -> NSAttributedString {
        var font = preferredUIKitFont
        if attr.length > 0, let firstFont = attr.attributes(at: 0, effectiveRange: nil)[.font] as? UIFont {
            font = firstFont
        }
        guard var image = styleData.uiImageForChain(chain, font: font) else { return attr }
        if let color {
            image = image.withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
        }

        let textAttachment = NSTextAttachment(image: image)
        let result = NSMutableAttributedString(attachment: textAttachment)

        result.append(separator.attributedString(font: font))
        
        result.append(attr)
        return result
    }
}

private extension ChainIcon.Separator {

    func text(font: Font, uiFont: UIFont) -> Text {
        switch self {
        case .none:
            Text("")
        case .hairline:
            Text("\u{200A}").font(font)
        case .fixed(let width):
            Text(Self.hairlineString(width: width, uiFont: uiFont)).font(font)
        case .custom(let string):
            Text(string).font(font)
        }
    }

    func attributedString(font: UIFont) -> NSAttributedString {
        switch self {
        case .none:
            NSAttributedString()
        case .hairline:
            NSAttributedString(string: "\u{200A}", attributes: [.font: font])
        case .fixed(let width):
            Self.fixedWidthString(width: width)
        case .custom(let string):
            NSAttributedString(string: string, attributes: [.font: font])
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
}

private extension ChainIcon {
    
    var preferredFont: Font { customFont ?? Font(preferredUIKitFont) }
    var preferredUIKitFont: UIFont { customUIKitFont ?? styleData.preferredUIKitFont }

    struct StyleData {
        let preferredUIKitFont: UIFont
        let symbolPrefix: String = "inline.chain."
        
        func symbolName(for chain: ApiChain) -> String? {
            let name = "\(symbolPrefix)\(chain.rawValue)"
            return UIImage.airBundleOptional(name) == nil ? nil : name
        }
        
        func uiImageForChain(_ chain: ApiChain, font: UIFont) -> UIImage? {
            guard let symbolName = symbolName(for: chain) else { return nil }
            let configuration = UIImage.SymbolConfiguration(font: font, scale: .small)
            return UIImage.airBundleOptional(symbolName)?
                .withConfiguration(configuration)
                .withRenderingMode(.alwaysTemplate)
        }
    }

    var styleData: StyleData {
        return switch style {
        case .s12: .init(
                preferredUIKitFont: .systemFont(ofSize: 12),
            )
        case .s14: .init(
                preferredUIKitFont: .systemFont(ofSize: 14, weight: .semibold),
            )
        case .s16: .init(
                preferredUIKitFont: .systemFont(ofSize: 16),
            )
        case .sDefault: .init(
                preferredUIKitFont: .systemFont(ofSize: 17),
            )
        }
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview("ChainIcon") {
    
    struct PrependTile: UIViewRepresentable {
        let icon: ChainIcon
        let address: String

        func makeUIView(context: Context) -> UILabel {
            let label = UILabel()
            label.numberOfLines = 0
            return label
        }

        func updateUIView(_ uiView: UILabel, context: Context) {
            let base = NSAttributedString(string: address, attributes: [.font: icon.styleData.preferredUIKitFont])
            uiView.attributedText = icon.prepended(to: base, separator: .hairline)
            uiView.textColor = .secondaryLabel
        }
    }

    let chains: [ApiChain] = [.ton, .tron, .solana, .other("other_chain")]

    return ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(ChainIcon.Style.allCases, id: \.self) { style in

                VStack(alignment: .leading, spacing: 8) {
                    Text("Style: \(String(describing: style))").font(.headline)

                    // NSAttributedString prepend
                    ForEach(chains, id: \.self) { chain in
                        let icon = ChainIcon(chain, style: style)

                        HStack {
                            PrependTile(icon: icon, address: "EQAG0273409823")
                            PrependTile(icon: icon, address: "@\(chain.rawValue)_domain")
                        }
                    }

                    // Text prepend
                    ForEach(chains, id: \.self) { chain in
                        let icon = ChainIcon(chain, style: style, color: .red)

                        HStack {
                            icon.prepended(to: Text("EQAG0273409823").font(icon.preferredFont), separator: .hairline)
                            icon.prepended(to: Text("@\(chain.rawValue)_domain").font(icon.preferredFont), separator: .hairline)
                        }
                    }

                    // SwiftUI Text interpolation
                    ForEach(chains, id: \.self) { chain in
                        let icon = ChainIcon(chain, style: style)
                        let ownColorIcon = ChainIcon(chain, style: style, color: .green)

                        Text("Inlined \(icon.text), \(icon.text.foregroundColor(.blue)), \(ownColorIcon.text) into a text")
                            .font(icon.preferredFont)
                            .foregroundColor(Color(.orange))
                    }
                    
                    // Swift-UI stand-alone
                    HStack {
                        ForEach(chains, id: \.self) { chain in
                            ChainIcon(chain, style: style)
                            ChainIcon(chain, style: style, color: .purple)
                            ChainIcon(chain, style: style).foregroundColor(.orange)
                        }
                        Text("Some text")
                    }
                    .foregroundStyle(.primary)
                    .background(Color.blue.opacity(0.1))
                }
            }
        }
        .padding()
    }
}
#endif
