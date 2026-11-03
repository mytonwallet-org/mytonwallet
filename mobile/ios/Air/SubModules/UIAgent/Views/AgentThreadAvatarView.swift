import CoreText
import UIKit
import UIComponents
import WalletContext

/// A thread avatar: the wallet avatar gradient with the thread emoji in the middle, or the Agent's mark until the
/// thread has an emoji
final class AgentThreadAvatarView: UIView {
    /// Emoji font size relative to the avatar diameter, shared by every thread avatar: Telegram draws an emoji avatar's
    /// emoji at 26 pt in its 60 pt chat list circle
    static let emojiScale: CGFloat = 26 / 60
    /// The Agent mark's design box relative to the avatar diameter: its silhouette comes out about as large as an
    /// emoji's glyph
    static let agentMarkScale: CGFloat = 0.6
    /// The silhouette within the mark's design box, which it doesn't fill evenly
    private static let agentMarkBounds = AgentSpinningTopIcon.makeSilhouette().cgPath.boundingBoxOfPath

    private let gradientLayer = CAGradientLayer()
    private let emojiLabel = AgentAvatarEmojiLabel()
    private let symbolView = UIImageView()
    private var resolveColors: (() -> [CGColor])?
    private var isShowingAgentMark = false
    private var isNews = false
    private var agentMarkSize: CGFloat = 0

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.actions = ["bounds": NSNull(), "position": NSNull(), "colors": NSNull(), "cornerRadius": NSNull()]
        layer.addSublayer(gradientLayer)
        emojiLabel.textAlignment = .center
        emojiLabel.adjustsFontSizeToFitWidth = true
        emojiLabel.minimumScaleFactor = 0.5
        addSubview(emojiLabel)
        symbolView.contentMode = .center
        symbolView.tintColor = .white
        addSubview(symbolView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(seed: String, emoji: String?) {
        isNews = false
        setLinearGradient()
        resolveColors = { seed.gradientColors }
        gradientLayer.colors = resolveColors?()
        configureContent(emoji: emoji)
    }

    /// The Agent's own gradient, as its unread mark has it, behind `image`
    func configureAgentMark(image: UIImage?) {
        isNews = false
        resolveColors = nil
        AgentMarkGradient.apply(to: gradientLayer)
        configureImage(image)
    }

    func configureNews() {
        configureAgentMark(image: AgentNewsAppearance.pulseImage)
        isNews = true
        // Figma's 40 pt avatar: radial origin (1.8182, 30.497), radius 41.99.
        gradientLayer.startPoint = CGPoint(x: 0.045455, y: 0.762425)
        gradientLayer.endPoint = CGPoint(x: 1.095205, y: 1.812175)
        gradientLayer.cornerCurve = .continuous
        setNeedsLayout()
    }

    private func setLinearGradient() {
        gradientLayer.type = .axial
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
    }

    private func configureImage(_ image: UIImage?) {
        isShowingAgentMark = false
        emojiLabel.text = nil
        emojiLabel.isHidden = true
        symbolView.image = image
        symbolView.isHidden = image == nil
    }

    /// The Agent's mark stands in for a missing emoji
    private func configureContent(emoji: String?) {
        isShowingAgentMark = false
        if let emoji = emoji?.nilIfEmpty {
            emojiLabel.text = emoji
            emojiLabel.isHidden = false
            symbolView.isHidden = true
        } else {
            emojiLabel.text = nil
            emojiLabel.isHidden = true
            isShowingAgentMark = true
            agentMarkSize = 0
            symbolView.isHidden = false
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = side * (isNews ? stockTokenCornerRadiusRatio : 0.5)
        emojiLabel.font = .systemFont(ofSize: max(1, side * Self.emojiScale))
        emojiLabel.frame = bounds
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: side * (isNews ? 21 / 40 : 0.45),
            weight: isNews ? .bold : .semibold
        )
        guard isShowingAgentMark else {
            symbolView.frame = bounds
            return
        }
        let markSize = (side * Self.agentMarkScale).rounded()
        if markSize != agentMarkSize, markSize > 0 {
            agentMarkSize = markSize
            symbolView.image = AgentSpinningTopIcon.makeTemplateImage(size: markSize)
        }
        // The silhouette, rather than its design box, sits in the middle
        let scale = markSize / AgentSpinningTopIcon.designSize
        let center = AgentSpinningTopIcon.designSize / 2
        symbolView.frame = bounds.offsetBy(
            dx: (center - Self.agentMarkBounds.midX) * scale,
            dy: (center - Self.agentMarkBounds.midY) * scale
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if let resolveColors {
            gradientLayer.colors = resolveColors()
        }
    }
}

/// The avatar's emoji, centered by its glyph's drawn bounds as Telegram centers avatar letters, rather than by the
/// font's line box
final class AgentAvatarEmojiLabel: UILabel {
    override func drawText(in rect: CGRect) {
        guard let text = text?.nilIfEmpty, let font, let context = UIGraphicsGetCurrentContext() else {
            super.drawText(in: rect)
            return
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: textColor ?? UIColor.label,
        ]))
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        // Glyphs that cannot be measured, or that overflow and need the label's shrinking, are drawn as usual
        guard !glyphBounds.isEmpty, glyphBounds.width <= bounds.width, glyphBounds.height <= bounds.height else {
            super.drawText(in: rect)
            return
        }
        let scale = max(1, traitCollection.displayScale)
        let origin = CGPoint(
            x: floor((-glyphBounds.minX + (bounds.width - glyphBounds.width) / 2) * scale) / scale,
            y: floor((-glyphBounds.minY + (bounds.height - glyphBounds.height) / 2) * scale) / scale
        )
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = origin
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

enum AgentNewsAppearance {
    static var pulseImage: UIImage? {
        UIImage(systemName: "waveform.path.ecg")
    }
}
