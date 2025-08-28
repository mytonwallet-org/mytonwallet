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
private let CHANGE_SPEED_INTERVAL = 3.0

private let LIGHT_COLOR = UIColor.airBundle("ShyColorLight")
private let DARK_COLOR = UIColor.airBundle("ShyColorDark")
private let ADAPTIVE_COLOR = UIColor.airBundle("ShyColorAdaptive")


public final class ShyMask: UIView, WThemedView {

    public enum Theme {
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
    private var updateTimer: Timer?
    private var widthConstraint: NSLayoutConstraint?
    private var currentColor: CGColor {
        switch theme {
        case .light:
            return LIGHT_COLOR.cgColor
        case .dark:
            return DARK_COLOR.cgColor
        case .adaptive:
            return ADAPTIVE_COLOR.resolvedColor(with: .current).cgColor
        case .color(let color):
            return color.resolvedColor(with: .current).cgColor
        }
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
        startUpdates()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        updateTimer?.invalidate()
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

    public func updateTheme() {
        for layer in cellLayers {
            layer.backgroundColor = currentColor
        }
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if cellLayers.first?.backgroundColor != currentColor {
            updateTheme()
        }
    }
    
    public func startUpdates() {
        if updateTimer == nil || updateTimer?.isValid == false {
            updateTimer = Timer.scheduledTimer(withTimeInterval: CHANGE_SPEED_INTERVAL, repeats: true) { [weak self] _ in
                self?.updateAllAnimations()
            }
            updateTimer?.tolerance = 1.0
        }
    }
    
    public func pauseUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func updateAllAnimations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        for layer in cellLayers {
            updateAnimation(for: layer)
        }
        
        CATransaction.commit()
    }
    
    private func updateAnimation(for layer: CALayer) {
        guard let existingAnimation = layer.animation(forKey: "opacityAnimation") as? CAKeyframeAnimation,
              let presentationLayer = layer.presentation() else {
            startAnimation(for: layer)
            return
        }
        
        let currentOpacity = presentationLayer.opacity
        
        let elapsedTime = CACurrentMediaTime() - existingAnimation.beginTime
        let normalizedTime = Float(elapsedTime.truncatingRemainder(dividingBy: existingAnimation.duration)) / Float(existingAnimation.duration)
        
        // Determine which keyframe segment we're in
        guard let keyTimes = existingAnimation.keyTimes, keyTimes.count == 4, let values = existingAnimation.values as? [Float], values.count == 4 else {
            assertionFailure("Invalid animation structure")
            return
        }
        let isIncreasing: Bool
        if normalizedTime < keyTimes[1].floatValue {
            isIncreasing = values[1] > currentOpacity
        } else if normalizedTime < keyTimes[2].floatValue {
            isIncreasing = values[2] > currentOpacity
        } else {
            isIncreasing = values[3] > currentOpacity
        }
        
        // Set the layer's model value to the current opacity and start a new animation
        layer.opacity = currentOpacity
        startAnimation(for: layer, isIncreasing: isIncreasing, duration: DURATION.randomElement()!)
    }
    
    private func startAnimation(for layer: CALayer, isIncreasing: Bool? = nil, duration: Float? = nil) {
        
        layer.removeAnimation(forKey: "opacityAnimation")
        
        let currentOpacity = layer.opacity
        let animDuration = duration ?? DURATION.randomElement()!
        let animIsIncreasing = isIncreasing ?? Bool.random()
        
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
    }
    
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: ShyMask, context: Context) -> CGSize {
        return CGSize(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
    }
}
