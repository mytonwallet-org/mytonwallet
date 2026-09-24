import SwiftUI
import UIKit
import WalletContext

private let FROM: Float = 0.07
private let TO: Float = 0.25
private let RANGE: Float = TO - FROM
private let DURATION = [
    RANGE / (0.0001 * 60),
    RANGE / (0.0001 * 60),
    RANGE / (0.00001 * 60),
    RANGE / (0.0003 * 60),
    RANGE / (0.0001 * 60),
    RANGE / (0.0025 * 60),
]

private let LIGHT_COLOR = UIColor.airBundle("ShyColorLight")
private let DARK_COLOR = UIColor.airBundle("ShyColorDark")
private let ADAPTIVE_COLOR = UIColor.airBundle("ShyColorAdaptive")


public final class ShyMask: UIView {

    public enum Theme: Sendable {
        case light
        case dark
        case adaptive
        case color(UIColor)
    }
    
    private(set) public var cols: Int
    public let rows: Int
    public let cellSize: CGFloat
    public var theme: Theme = .adaptive

    private var cellLayers: [CALayer] = []
    private var widthConstraint: NSLayoutConstraint?
    private var currentColor: CGColor {
        theme.color.resolvedColor(with: .current).cgColor
    }

    public init(cols: Int, rows: Int, cellSize: CGFloat, theme: Theme) {
        self.cols = cols
        self.rows = rows
        self.cellSize = cellSize
        self.theme = theme
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: CGFloat(cols) * cellSize)
        NSLayoutConstraint.activate([
            widthConstraint!,
            heightAnchor.constraint(equalToConstant: CGFloat(rows) * cellSize)
        ])
        
        setupLayers()
        updateTheme()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayers() {
        backgroundColor = .clear
        
        for _ in 0..<rows {
            for _ in 0..<cols {
                let layer = CALayer()
                
                layer.opacity = Float.random(in: FROM...TO)
                
                self.layer.addSublayer(layer)
                cellLayers.append(layer)
                
                startAnimation(for: layer)
            }
        }
        _layoutCells()
    }
    
    private func _layoutCells() {
        for row in 0..<rows {
            for col in 0..<cols {
                cellLayers[row*cols + col].frame = CGRect(
                    x: CGFloat(col) * cellSize,
                    y: CGFloat(row) * cellSize,
                    width: cellSize,
                    height: cellSize
                )
            }
        }
    }

    private func updateTheme() {
        for layer in cellLayers {
            layer.backgroundColor = currentColor
        }
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if cellLayers.first?.backgroundColor != currentColor {
            updateTheme()
        }
    }
    
    // Random phases and speeds remain on Core Animation; account swipes need no
    // timer-driven sampling of presentation layers or animation replacement.
    private func startAnimation(for layer: CALayer) {
        
        layer.removeAnimation(forKey: "opacityAnimation")
        
        let currentOpacity = layer.opacity
        let animDuration = DURATION.randomElement()!
        let animIsIncreasing = Bool.random()
        
        let currentNormalized = (currentOpacity - FROM) / RANGE
        
        // Create keyframe animation with 4 points: current → TO/FROM → FROM/TO → current
        let keyframeAnimation = CAKeyframeAnimation(keyPath: "opacity")
        
        var keyValues: [Float]
        var keyTimes: [NSNumber]
        
        if animIsIncreasing {
            keyValues = [currentOpacity, TO, FROM, currentOpacity]
            
            let timeToReachTO = (1.0 - currentNormalized) * 0.5 // normalized to 0...1 from 0...2
            
            keyTimes = [
                0,
                NSNumber(value: timeToReachTO),
                NSNumber(value: timeToReachTO + 0.5),
                1.0
            ]
        } else {
            keyValues = [currentOpacity, FROM, TO, currentOpacity]
            
            let timeToReachFROM = currentNormalized * 0.5
            
            keyTimes = [
                0,
                NSNumber(value: timeToReachFROM),
                NSNumber(value: timeToReachFROM + 0.5),
                1.0
            ]
        }
        
        keyframeAnimation.values = keyValues
        keyframeAnimation.keyTimes = keyTimes
        
        keyframeAnimation.duration = CFTimeInterval(animDuration) * 2
        keyframeAnimation.repeatCount = .infinity
        keyframeAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        
        layer.add(keyframeAnimation, forKey: "opacityAnimation")
    }
    
    public override var intrinsicContentSize: CGSize {
        return CGSize(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
    }
    
    public func setCols(_ newCols: Int) {
        guard newCols > 0, newCols != cols else { return }
        
        let oldCols = cols
        let oldCells = rows * oldCols
        
        self.cols = newCols
        let newCells = rows * newCols
        
        // Update width constraint
        widthConstraint?.constant = CGFloat(newCols) * cellSize
        setNeedsLayout()
        
        // Update cell visibility and positions
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        let newLayers = newCells - cellLayers.count
        if newLayers > 0 {
            for _ in 0..<newLayers {
                let layer = CALayer()
                
                let randomOpacity = Float.random(in: FROM...TO)
                layer.backgroundColor = currentColor
                layer.opacity = randomOpacity
                
                self.layer.addSublayer(layer)
                cellLayers.append(layer)
                
                startAnimation(for: layer)
            }
        }
            
        if newCells > oldCells {
            for layer in cellLayers[..<newCells] {
                layer.isHidden = false
            }
        } else {
            for layer in cellLayers[newCells...] {
                layer.isHidden = true
            }
        }
        _layoutCells()
        
        CATransaction.commit()
        invalidateIntrinsicContentSize()
    }

    public func setTheme(_ newTheme: Theme) {
        theme = newTheme
        updateTheme()
    }
}

public extension ShyMask.Theme {
    var color: UIColor {
        switch self {
        case .light:
            LIGHT_COLOR
        case .dark:
            DARK_COLOR
        case .adaptive:
            ADAPTIVE_COLOR
        case .color(let color):
            color
        }
    }
}

// MARK: - SwiftUI support

public struct WUIShyMask: UIViewRepresentable {
    public var cols: Int
    public var rows: Int
    public var cellSize: CGFloat
    public var theme: ShyMask.Theme
    
    public init(cols: Int, rows: Int, cellSize: CGFloat, theme: ShyMask.Theme = .adaptive) {
        self.cols = cols
        self.rows = rows
        self.cellSize = cellSize
        self.theme = theme
    }
    
    public func makeUIView(context: Context) -> ShyMask {
        ShyMask(cols: cols, rows: rows, cellSize: cellSize, theme: theme)
    }
    
    public func updateUIView(_ uiView: ShyMask, context: Context) {
        uiView.setCols(cols)
        uiView.setTheme(theme)
    }
    
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: ShyMask, context: Context) -> CGSize {
        return CGSize(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
    }
}
