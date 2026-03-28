import UIKit

private enum AgentBubbleBackgroundMetrics {
    static let cornerRadius: CGFloat = 20
    static let tailSize = CGSize(width: 22.153, height: 26.9084)
    static let tailAttachmentHeight: CGFloat = 20
    static let tailBottomOverflow = tailSize.height - tailAttachmentHeight
}

final class AgentBubbleBackgroundView: UIView {
    enum Direction {
        case incoming
        case outgoing
    }

    struct CornerRadii {
        let topLeft: CGFloat
        let topRight: CGFloat
        let bottomRight: CGFloat
        let bottomLeft: CGFloat

        static func uniform(_ radius: CGFloat) -> CornerRadii {
            CornerRadii(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
        }
    }

    let contentView = UIView()
    nonisolated static let tailBottomOverflow = AgentBubbleBackgroundMetrics.tailBottomOverflow

    private let bodyView = UIView()
    private let bodyMaskLayer = CAShapeLayer()
    private let tailView = UIView()
    private let tailLayer = CAShapeLayer()

    private lazy var incomingTailLeadingConstraint = tailView.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor)
    private lazy var outgoingTailTrailingConstraint = tailView.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor)
    private lazy var tailTopConstraint = tailView.topAnchor.constraint(equalTo: bodyView.bottomAnchor, constant: -AgentBubbleBackgroundMetrics.tailAttachmentHeight)
    private lazy var bodyBottomConstraint = bodyView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AgentBubbleBackgroundMetrics.tailBottomOverflow)
    private lazy var tailHeightConstraint = tailView.heightAnchor.constraint(equalToConstant: AgentBubbleBackgroundMetrics.tailSize.height)

    private var direction: Direction = .incoming
    private var fillColor: UIColor = .clear
    private var usesTintColor = false
    private var cornerRadii = CornerRadii.uniform(AgentBubbleBackgroundMetrics.cornerRadius)
    private var showsTail = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        direction: Direction,
        fillColor: UIColor,
        usesTintColor: Bool = false,
        showsTail: Bool = true,
        cornerRadii: CornerRadii = .uniform(AgentBubbleBackgroundMetrics.cornerRadius)
    ) {
        self.direction = direction
        self.fillColor = fillColor
        self.usesTintColor = usesTintColor
        self.showsTail = showsTail
        self.cornerRadii = cornerRadii

        applyCurrentFillColor()

        incomingTailLeadingConstraint.isActive = direction == .incoming
        outgoingTailTrailingConstraint.isActive = direction == .outgoing
        tailView.isHidden = !showsTail
        bodyBottomConstraint.constant = showsTail ? -AgentBubbleBackgroundMetrics.tailBottomOverflow : 0
        tailTopConstraint.constant = showsTail ? -AgentBubbleBackgroundMetrics.tailAttachmentHeight : 0
        tailHeightConstraint.constant = showsTail ? AgentBubbleBackgroundMetrics.tailSize.height : 0

        setNeedsLayout()
    }

    func previewPath() -> UIBezierPath {
        layoutIfNeeded()

        let path = UIBezierPath()
        path.append(Self.roundedPath(in: bodyView.frame, radii: cornerRadii))

        guard showsTail else { return path }

        let tailPath = Self.previewTailPath(in: tailView.bounds, mirrored: direction == .incoming)
        tailPath.apply(
            CGAffineTransform(
                translationX: tailView.frame.minX,
                y: tailView.frame.minY
            )
        )
        path.append(tailPath)

        return path
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        performWithoutImplicitAnimations {
            bodyMaskLayer.frame = bodyView.bounds
            bodyMaskLayer.path = Self.roundedPath(in: bodyView.bounds, radii: cornerRadii).cgPath
            tailLayer.frame = tailView.bounds
            tailLayer.path = showsTail ? Self.tailPath(in: tailView.bounds, mirrored: direction == .incoming) : nil
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyCurrentFillColor()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyCurrentFillColor()
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        tintAdjustmentMode = .normal

        bodyView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.layer.mask = bodyMaskLayer
        addSubview(bodyView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.addSubview(contentView)

        tailView.translatesAutoresizingMaskIntoConstraints = false
        tailView.backgroundColor = .clear
        tailView.isUserInteractionEnabled = false
        tailView.layer.addSublayer(tailLayer)
        addSubview(tailView)

        NSLayoutConstraint.activate([
            bodyView.topAnchor.constraint(equalTo: topAnchor),
            bodyView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyBottomConstraint,

            contentView.topAnchor.constraint(equalTo: bodyView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),

            tailTopConstraint,
            tailView.widthAnchor.constraint(equalToConstant: AgentBubbleBackgroundMetrics.tailSize.width),
            tailHeightConstraint,
            tailView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        configure(direction: .incoming, fillColor: .clear)
    }

    private func applyCurrentFillColor() {
        let resolvedFillColor = fillColor.resolvedColor(with: traitCollection)
        let appliedFillColor = usesTintColor
            ? tintColor.withAlphaComponent(resolvedFillColor.cgColor.alpha)
            : resolvedFillColor
        performWithoutImplicitAnimations {
            bodyView.backgroundColor = appliedFillColor
            tailLayer.fillColor = appliedFillColor.cgColor
        }
    }

    private func performWithoutImplicitAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    private static func roundedPath(in bounds: CGRect, radii: CornerRadii) -> UIBezierPath {
        let width = max(bounds.width, 0)
        let height = max(bounds.height, 0)

        let topLeft = min(radii.topLeft, min(width, height) / 2)
        let topRight = min(radii.topRight, min(width, height) / 2)
        let bottomRight = min(radii.bottomRight, min(width, height) / 2)
        let bottomLeft = min(radii.bottomLeft, min(width, height) / 2)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: topLeft, y: 0))
        path.addLine(to: CGPoint(x: width - topRight, y: 0))

        if topRight > 0 {
            path.addArc(
                withCenter: CGPoint(x: width - topRight, y: topRight),
                radius: topRight,
                startAngle: -.pi / 2,
                endAngle: 0,
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: width, y: height - bottomRight))
        if bottomRight > 0 {
            path.addArc(
                withCenter: CGPoint(x: width - bottomRight, y: height - bottomRight),
                radius: bottomRight,
                startAngle: 0,
                endAngle: .pi / 2,
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: bottomLeft, y: height))
        if bottomLeft > 0 {
            path.addArc(
                withCenter: CGPoint(x: bottomLeft, y: height - bottomLeft),
                radius: bottomLeft,
                startAngle: .pi / 2,
                endAngle: .pi,
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: 0, y: topLeft))
        if topLeft > 0 {
            path.addArc(
                withCenter: CGPoint(x: topLeft, y: topLeft),
                radius: topLeft,
                startAngle: .pi,
                endAngle: -.pi / 2,
                clockwise: true
            )
        }

        path.close()
        return path
    }

    private static func tailPath(in bounds: CGRect, mirrored: Bool) -> CGPath {
        let path = outgoingTailPath(in: bounds)
        guard mirrored else { return path.cgPath }

        var transform = CGAffineTransform(translationX: bounds.width, y: 0).scaledBy(x: -1, y: 1)
        return path.cgPath.copy(using: &transform) ?? path.cgPath
    }

    private static func outgoingTailPath(in bounds: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let scaleX = bounds.width / AgentBubbleBackgroundMetrics.tailSize.width
        let scaleY = bounds.height / AgentBubbleBackgroundMetrics.tailSize.height

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scaleX, y: y * scaleY)
        }

        path.move(to: point(22.153, 0))
        path.addCurve(
            to: point(14.153, 16),
            controlPoint1: point(22.153, 6.5424),
            controlPoint2: point(19.010, 12.3511)
        )
        path.addCurve(
            to: point(13.455, 25.3561),
            controlPoint1: point(10.423, 18.8554),
            controlPoint2: point(11.317, 22.4828)
        )
        path.addCurve(
            to: point(12.974, 26.9084),
            controlPoint1: point(13.862, 25.9040),
            controlPoint2: point(13.630, 26.7207)
        )
        path.addCurve(
            to: point(12.348, 26.8634),
            controlPoint1: point(12.767, 26.9676),
            controlPoint2: point(12.544, 26.9520)
        )
        path.addCurve(
            to: point(2.505, 20.8690),
            controlPoint1: point(8.458, 25.1080),
            controlPoint2: point(5.684, 23.3351)
        )
        path.addCurve(
            to: point(0, 20),
            controlPoint1: point(1.788, 20.3123),
            controlPoint2: point(0.908, 20)
        )
        path.close()

        return path
    }

    private static func previewTailPath(in bounds: CGRect, mirrored: Bool) -> UIBezierPath {
        let path = outgoingTailPath(in: bounds)
        guard mirrored else { return path }

        path.apply(CGAffineTransform(translationX: bounds.width, y: 0).scaledBy(x: -1, y: 1))
        return path.reversing()
    }
}
