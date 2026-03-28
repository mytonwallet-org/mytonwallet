
import UIKit

open class WHighlightCell: UITableViewCell {
    
    open var highlightingTime: Double = 0.1
    open var unhighlightingTime: Double = 0.5

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open var baseBackgroundColor: UIColor? = .clear {
        didSet {
            if !isHighlighted {
                backgroundColor = baseBackgroundColor
            }
        }
    }
    
    open var highlightBackgroundColor: UIColor? = nil {
        didSet {
            if isHighlighted {
                backgroundColor = highlightBackgroundColor
            }
        }
    }
    
    open override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue {
                UIView.animate(withDuration: isHighlighted ? highlightingTime : unhighlightingTime, delay: 0, options: [.allowUserInteraction]) { [self] in
                    self.backgroundColor = isHighlighted ? highlightBackgroundColor : baseBackgroundColor
                }
            }
        }
    }
    
    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = true
//        super.touchesBegan(touches, with: event)
    }
    
    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = false
//        super.touchesEnded(touches, with: event)
    }
    
    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = false
//        super.touchesCancelled(touches, with: event)
    }
    
    open override func prepareForReuse() {
        isHighlighted = false
        super.prepareForReuse()
    }
}


open class WHighlightCollectionViewCell: UICollectionViewCell {
    
    open var highlightingTime: Double = 0.1
    open var unhighlightingTime: Double = 0.5

    open var baseBackgroundColor: UIColor? = nil {
        didSet {
            if !isHighlighted {
                backgroundColor = baseBackgroundColor
            }
        }
    }
    
    open var highlightBackgroundColor: UIColor? = nil {
        didSet {
            if isHighlighted {
                backgroundColor = highlightBackgroundColor
            }
        }
    }
    
    private var oldBackground: UIColor? = nil

    open override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue {
                let defaultColor = baseBackgroundColor ?? oldBackground ?? backgroundColor
                if isHighlighted {
                    oldBackground = defaultColor
                }
                UIView.animate(withDuration: isHighlighted ? highlightingTime : unhighlightingTime,
                               delay: 0,
                               options: UIView.AnimationOptions.allowUserInteraction) {
                    self.backgroundColor = self.isHighlighted ? self.highlightBackgroundColor : defaultColor
                }
                if !isHighlighted {
                    oldBackground = nil
                }
            }
        }
    }
    
    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = true
        super.touchesBegan(touches, with: event)
    }
    
    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = false
        super.touchesEnded(touches, with: event)
    }
    
    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = false
        super.touchesCancelled(touches, with: event)
    }

    open override func prepareForReuse() {
        super.prepareForReuse()
        oldBackground = nil
        isHighlighted = false
    }
}
