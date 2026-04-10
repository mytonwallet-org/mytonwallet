import SwiftUI
import WalletCore
import WalletContext

public struct ChainIcon: View {
    public enum Style: CaseIterable {
        case s12, s14, s16, sDefault
    }
    
    public let chain: ApiChain
    public let style: Style
    public let color: Color?

    public init(_ chain: ApiChain, style: Style, color: Color? = nil) {
        self.chain = chain
        self.style = style
        self.color = color
    }
    
    private var image: Image? {
        guard let image = styleData.imageForChain(chain, resize: true) else { return nil }
        return Image(uiImage: image)
    }
    
    @ViewBuilder
    public var body: some View {
        if let image = self.image {
            if let color {
                image.foregroundStyle(color)
            } else {
                image
            }
        }
    }
    
    public var text: Text {
        guard let image = self.image else { return Text("") }
        let t = Text(image).baselineOffset(styleData.baselineOffset)
        if let color { return t.foregroundColor(color) }
        return t
    }

    /// Uses a narrow non-breakable space as a separator
    public func prepended(to text: Text) -> Text {
        guard let image = self.image else { return text }
        var iconText = Text(image).baselineOffset(styleData.baselineOffset)
        if let color { iconText = iconText.foregroundColor(color) }
        return Text("\(iconText)\u{202F}\(text)")
    }
    
    /// Uses a narrow non-breakable space as a separator
    public func prepended(to attr: NSAttributedString) -> NSAttributedString {
        let styleData = self.styleData
        guard let image = styleData.imageForChain(chain) else { return attr }

        let textAttachment = NSTextAttachment(image: image)
        textAttachment.bounds = styleData.bounds
        let result = NSMutableAttributedString(attachment: textAttachment)

        if let color {
            result.addAttribute(.foregroundColor, value: UIColor(color), range: NSRange(location: 0, length: result.length))
        }

        var spaceAttributes: [NSAttributedString.Key: Any] = [.font: styleData.preferredUIKitFont]
        if attr.length > 0 {
            let firstAttributes = attr.attributes(at: 0, effectiveRange: nil)
            if let font = firstAttributes[.font] {
                spaceAttributes[.font] = font
            }
        }
        result.append(NSAttributedString(string: "\u{202F}", attributes: spaceAttributes))
        
        result.append(attr)
        return result
    }
}

private extension ChainIcon {
    
    var preferredFont: Font { Font(styleData.preferredUIKitFont) }

    struct StyleData {
        let bounds: CGRect
        let preferredUIKitFont: UIFont
        let imagePrefix: String = "inline_chain_"
        
        func imageForChain(_ chain: ApiChain, resize: Bool = false) -> UIImage? {
            let imageName = "\(imagePrefix)\(chain.rawValue)"
            guard var image = UIImage.airBundleOptional(imageName) else {
                return nil
            }
            if resize {
                image = image.resizedToFit(size: CGSize(width: bounds.width, height: bounds.height))
            }
            return image.withRenderingMode(.alwaysTemplate)
        }
        
        var baselineOffset: CGFloat { bounds.origin.y }
    }

    var styleData: StyleData {
        return switch style {
        case .s12: .init(
                bounds: .init(x: 0, y: -2.5, width: 13, height: 13),
                preferredUIKitFont: .systemFont(ofSize: 12),
            )
        case .s14: .init(
                bounds: .init(x: 0, y: -2.8, width: 15, height: 15),
                preferredUIKitFont: .systemFont(ofSize: 14, weight: .semibold),
            )
        case .s16: .init(
                bounds: .init(x: 0, y: -3.0, width: 17, height: 17),
                preferredUIKitFont: .systemFont(ofSize: 16),
            )
        case .sDefault: .init(
                bounds: .init(x: 0, y: -3.5, width: 18, height: 18),
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
            uiView.attributedText = icon.prepended(to: base)
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
                            icon.prepended(to: Text("EQAG0273409823").font(icon.preferredFont))
                            icon.prepended(to: Text("@\(chain.rawValue)_domain").font(icon.preferredFont))
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
