import UIKit

public final class OverlappingIconStackView: UIView {
    public let iconSize: CGFloat

    private let maximumSpacing: CGFloat
    private let minimumSpacing: CGFloat
    private let spacingDecay: Double
    private let cutoutGap: CGFloat
    private var imageViews: [UIImageView] = []

    public init(
        iconSize: CGFloat,
        maximumSpacing: CGFloat? = nil,
        minimumSpacing: CGFloat? = nil,
        spacingDecay: Double = 0.12,
        cutoutGap: CGFloat? = nil
    ) {
        self.iconSize = iconSize
        self.maximumSpacing = maximumSpacing ?? iconSize * 13 / 14
        self.minimumSpacing = minimumSpacing ?? iconSize * 2 / 7
        self.spacingDecay = spacingDecay
        self.cutoutGap = cutoutGap ?? iconSize / 18 * 0.7
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(images: [UIImage]) {
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = images.map { image in
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.layer.cornerRadius = iconSize / 2
            imageView.layer.masksToBounds = true
            return imageView
        }
        for imageView in imageViews.reversed() {
            addSubview(imageView)
        }
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        let spacings = spacings(iconCount: imageViews.count, availableWidth: bounds.width)
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let direction: CGFloat = isRightToLeft ? -1 : 1
        var x = isRightToLeft ? bounds.width - iconSize : 0

        for (index, imageView) in imageViews.enumerated() {
            imageView.frame = CGRect(
                x: x,
                y: (bounds.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            if index < spacings.count {
                x += direction * spacings[index]
            }
        }
        updateMasks()
    }

    public static func makeImage(
        images: [UIImage],
        iconSize: CGFloat,
        spacing: CGFloat,
        cutoutGap: CGFloat,
        canvasSize: CGSize? = nil,
        contentOffset: CGPoint = .zero
    ) -> UIImage? {
        guard !images.isEmpty else { return nil }

        let width = iconSize + CGFloat(images.count - 1) * spacing
        let contentSize = CGSize(width: width, height: iconSize)
        let stackView = OverlappingIconStackView(
            iconSize: iconSize,
            maximumSpacing: spacing,
            minimumSpacing: spacing,
            cutoutGap: cutoutGap
        )
        stackView.frame = CGRect(origin: .zero, size: contentSize)
        stackView.configure(images: images)
        stackView.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvasSize ?? contentSize, format: format).image { context in
            context.cgContext.translateBy(x: contentOffset.x, y: contentOffset.y)
            stackView.layer.render(in: context.cgContext)
        }
    }

    private func updateMasks() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, imageView) in imageViews.enumerated() {
            guard index > 0 else {
                imageView.layer.mask = nil
                continue
            }

            let previousImageView = imageViews[index - 1]
            let offset = previousImageView.frame.minX - imageView.frame.minX
            let path = UIBezierPath(ovalIn: imageView.bounds)
            path.append(UIBezierPath(ovalIn: CGRect(
                x: offset - cutoutGap,
                y: -cutoutGap,
                width: iconSize + 2 * cutoutGap,
                height: iconSize + 2 * cutoutGap
            )))

            let mask = CAShapeLayer()
            mask.fillRule = .evenOdd
            mask.frame = imageView.bounds
            mask.path = path.cgPath
            imageView.layer.mask = mask
        }
        CATransaction.commit()
    }

    private func spacings(iconCount: Int, availableWidth: CGFloat) -> [CGFloat] {
        guard iconCount > 1 else { return [] }

        let spacingCount = iconCount - 1
        let availableSpacing = max(0, availableWidth - iconSize)
        let uniformWidth = maximumSpacing * CGFloat(spacingCount)
        let uniformSpacings = Array(repeating: maximumSpacing, count: spacingCount)
        guard availableSpacing < uniformWidth else {
            return uniformSpacings
        }

        let tightenedSpacings = (0..<spacingCount).map { tightenedSpacing(after: $0) }
        let tightenedWidth = tightenedSpacings.reduce(0, +)
        guard availableSpacing > tightenedWidth, tightenedWidth < uniformWidth else {
            guard tightenedWidth > 0 else { return Array(repeating: 0, count: spacingCount) }
            let scale = availableSpacing / tightenedWidth
            return tightenedSpacings.map { $0 * scale }
        }

        let tightening = (uniformWidth - availableSpacing) / (uniformWidth - tightenedWidth)
        return tightenedSpacings.map { maximumSpacing + tightening * ($0 - maximumSpacing) }
    }

    private func tightenedSpacing(after index: Int) -> CGFloat {
        minimumSpacing
            + (maximumSpacing - minimumSpacing) * CGFloat(exp(-spacingDecay * Double(index)))
    }
}
