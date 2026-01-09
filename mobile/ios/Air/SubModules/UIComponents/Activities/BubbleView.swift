
import SwiftUI
import UIKit
import WalletContext

private let errorColor = UIColor(light: "#F86C64", dark: "#E85C54")

public final class BubbleView: UIView {
    
    public enum Direction {
        case incoming
        case outgoing
        
        fileprivate var color: UIColor {
            switch self {
            case .incoming: .airBundle("ActivityGreen")
            case .outgoing: .airBundle("ActivityBlue")
            }
        }
        
        fileprivate var transform: CATransform3D {
            switch self {
            case .incoming: CATransform3DIdentity
            case .outgoing: CATransform3DMakeRotation(.pi, 0, 0, 1)
            }
        }
    }
    
    public var fontSize: CGFloat = 16.0
    
    public var lineLimit: Int {
        get { label.numberOfLines }
        set { label.numberOfLines = newValue }
    }
    
    private let bubbleLayer: CAShapeLayer = CAShapeLayer()
    let label = UILabel()
    private var direction: Direction = .incoming
    private var isError: Bool = false
    
    public init() {
        super.init(frame: .zero)
        setup()
//        setComment("Gift for You")
//        setComment("Hello! It's very long comment! How are\nyou, friend?")
//        setEncryptedComment()
//        setDirection(.outgoing)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
//        backgroundColor = .blue
        
        layer.addSublayer(bubbleLayer)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        label.numberOfLines = 3
        label.textColor = .white
        label.setContentHuggingPriority(.required, for: .vertical)
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12 + 1),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12 - 1),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        
        setDirection(.incoming, isError: false)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        UIView.performWithoutAnimation {
            var bubbleBounds = bounds
            if bubbleBounds.height <= 40 {
                bubbleBounds.size.height = 32
            }
            bubbleBounds = bubbleBounds.offsetBy(dx: direction == .incoming ? -4 : 4, dy: 0)
            if bubbleBounds != bubbleLayer.frame {
                bubbleLayer.frame = bubbleBounds
                bubbleLayer.path = makeShape(bounds: bubbleLayer.bounds)
            }
        }
    }

    private func makeShape(bounds: CGRect) -> CGPath {
        if bounds.height > 40 {
            return makePathMultiline(width: bounds.width, height: bounds.height)
        } else {
            return makePathSingleLine(width: bounds.width)
        }
    }
    
    public func setComment(_ text: String, direction: Direction, isError: Bool) {
        let attr = NSMutableAttributedString()
        
        _sharedSetText(attr: attr, text: text.trimmingCharacters(in: .whitespacesAndNewlines), font: .systemFont(ofSize: fontSize))
        
        label.transform = .init(translationX: 0, y: 0.333)
        
        setDirection(direction, isError: isError)
    }
    
    public func setEncryptedComment(direction: Direction, isError: Bool) {
        
        let attr = NSMutableAttributedString()

        let attachment = NSTextAttachment()
        attachment.image = .airBundle("CommentLock").withBaselineOffset(fromBottom: 2.5)
        let imageString = NSAttributedString(attachment: attachment)
        attr.append(imageString)

        attr.appendSpacer(2)
        
        _sharedSetText(attr: attr, text: lang("Encrypted Message"), font: .italicSystemFont(ofSize: fontSize))
        
        label.transform = .init(translationX: 0, y: -0.333)
        
        setDirection(direction, isError: isError)
    }
    
    private func _sharedSetText(attr: NSMutableAttributedString, text: String, font: UIFont) {
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: -0.12,
        ]
        attr.append(NSAttributedString(string: text, attributes: textAttributes))
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = 17
        paragraphStyle.maximumLineHeight = 17
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let fullRange = NSRange(location: 0, length: attr.length)
        attr.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        label.attributedText = attr
        setNeedsLayout()
    }
    
    private func setDirection(_ direction: Direction, isError: Bool) {
        self.direction = direction
        self.isError = isError
        bubbleLayer.fillColor =  isError ? errorColor.cgColor : direction.color.cgColor
        bubbleLayer.transform = direction.transform
        setNeedsLayout()
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        bubbleLayer.fillColor =  isError ? errorColor.cgColor : direction.color.cgColor
    }
}


// MARK: - Paths

private let tail: CGPath = {
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 23.0,   y: 0.0))
    tail.addLine(to: CGPoint(x: 31.0, y: 0.0))     // H31
    tail.addLine(to: CGPoint(x: 31.0, y: 8.0))     // V8
    tail.addLine(to: CGPoint(x: 16.0, y: 8.0))     // H16
    tail.addLine(to: CGPoint(x: 4.0,  y: 8.0))     // H4
    
    // C4 2 0 0.5 0 0.5
    tail.addCurve(
        to: CGPoint(x: 0.0,    y: 0.5),
        control1: CGPoint(x: 4.0,  y: 2.0),
        control2: CGPoint(x: 0.0,  y: 0.5)
    )
    
    // C10 0.5 10.75 4.25 10.75 4.25
    tail.addCurve(
        to: CGPoint(x: 10.75, y: 4.25),
        control1: CGPoint(x: 10.0, y: 0.5),
        control2: CGPoint(x: 10.75, y: 4.25)
    )
    
    // C10.75 4.25 13 0 23 0
    tail.addCurve(
        to: CGPoint(x: 23.0,  y: 0.0),
        control1: CGPoint(x: 10.75, y: 4.25),
        control2: CGPoint(x: 13.0,  y: 0.0)
    )
    
    tail.closeSubpath()
    return tail
}()

private let tailMask: CGPath = {
    UIBezierPath.init(rect: .init(x: 0, y: 0, width: 31, height: 8)).cgPath
}()

private func makePathSingleLine(width: CGFloat) -> CGPath {
    
    let bottomLeftCorner = UIBezierPath(roundedRect: .init(x: 4, y: -24, width: width + 44, height: 56), cornerRadius: 18)
    
    let rightCorners = UIBezierPath(roundedRect: .init(x: -20, y: 0, width: width + 24, height: 32), cornerRadius: 16)
    
    let path = bottomLeftCorner.cgPath
        .subtracting(tailMask)
        .union(tail)
        .intersection(rightCorners.cgPath)

    return path
}

private func makePathMultiline(width: CGFloat, height: CGFloat) -> CGPath {
    
    let rect = CGRect(x: 4, y: 0, width: width, height: height)
    
    let rightCorners = UIBezierPath(roundedRect: rect, cornerRadius: 16)

    let topRightCorner = UIBezierPath(rect: .init(x: 4, y: 0, width: 30, height: 22))
    
    let path = rightCorners.cgPath
        .union(topRightCorner.cgPath)
        .subtracting(tailMask)
        .union(tail)
    
    return path
}


// MARK: - Helpers

fileprivate extension NSMutableAttributedString {
     func appendSpacer(_ width: Double) {
         let space = NSTextAttachment(image: UIImage())
         space.bounds = CGRect(x:0, y: 0, width: width, height: 0)
         append(NSAttributedString(attachment: space))
    }
}


// MARK: - SwiftUI support

public struct SBubbleView: UIViewRepresentable {
    
    public enum Content {
        case comment(String)
        case encryptedComment
    }
    
    var content: Content
    var direction: BubbleView.Direction
    var isError: Bool
    
    public init(content: Content, direction: BubbleView.Direction, isError: Bool) {
        self.content = content
        self.direction = direction
        self.isError = isError
    }
    
    public func makeUIView(context: Context) -> BubbleView {
        let bubbleView = BubbleView()
        bubbleView.fontSize = 17
        bubbleView.lineLimit = 30
        return bubbleView
    }
    
    public func updateUIView(_ bubbleView: BubbleView, context: Context) {
        switch content {
        case .comment(let string):
            bubbleView.setComment(string, direction: direction, isError: isError)
        case .encryptedComment:
            bubbleView.setEncryptedComment(direction: direction, isError: isError)
        }
    }
    
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView bubbleView: BubbleView, context: Context) -> CGSize? {
        
        let horizontalPadding = (12.0 + 1.0) * 2.0 // Label leading/trailing constraints: (12 + 1) on each side

        var layoutSize = UIView.layoutFittingCompressedSize
        
        if let proposedWidth = proposal.width {
            bubbleView.label.preferredMaxLayoutWidth = max(0, proposedWidth - horizontalPadding)
            layoutSize.width = proposedWidth
        } else {
            bubbleView.label.preferredMaxLayoutWidth = 0
        }

        let calculatedSize = bubbleView.systemLayoutSizeFitting(layoutSize)
        
        return calculatedSize
    }
}

