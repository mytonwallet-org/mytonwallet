//
//  WAnimatedLabel.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/28/24.
//

import Foundation
import UIKit
import WalletContext
import WalletCore

fileprivate let initialDelayInMs = CGFloat(150)

private struct WALCharacterRect {
    let leftOffset: CGFloat
    let yOffsetPercent: CGFloat
    let alpha: CGFloat
    let attributes: [NSAttributedString.Key: Any]
    let char: String
}

private struct WALCharacter {
    let oldLeftOffset: CGFloat
    let leftOffset: CGFloat
    var startChar: String
    let endChar: String
    let change: Change
    let totalSteps: Int
    let startFrom0Alpha: Bool
    let endWith0Alpha: Bool
    var delay: CGFloat = 0
    var charAnimationDuration: CGFloat = 1
    let startAttributes: [NSAttributedString.Key: Any]
    let endAttributes: [NSAttributedString.Key: Any]
    
    enum Change {
        case inc
        case dec
        case none
    }

    init(oldLeftOffset: CGFloat,
         leftOffset: CGFloat,
         startChar: String,
         endChar: String,
         change: Change,
         startAttributes: [NSAttributedString.Key: Any],
         endAttributes: [NSAttributedString.Key: Any]) {
        self.oldLeftOffset = oldLeftOffset
        self.leftOffset = leftOffset
        self.startChar = startChar
        self.endChar = endChar
        self.change = change
        self.startAttributes = startAttributes
        self.endAttributes = endAttributes
        
        if let startNum = Int(startChar), let endNum = Int(endChar) {
            if endNum == startNum {
                totalSteps = 10
            } else {
                totalSteps = change == .inc ?
                (endNum > startNum ? abs(endNum - startNum) : abs(endNum + 10 - startNum)) :
                (endNum < startNum ? abs(startNum - endNum) : abs(startNum + 10 - endNum))
            }
            startFrom0Alpha = false
            endWith0Alpha = false
        } else {
            if startChar == " ", let endNum = Int(endChar) {
                totalSteps = 5
                if endNum >= 5 {
                    self.startChar = "\(endNum - 5)"
                } else {
                    self.startChar = "\(endNum + 5)"
                }
                startFrom0Alpha = true
                endWith0Alpha = false
            } else if endChar == "", Int(startChar) != nil {
                totalSteps = 5
                startFrom0Alpha = false
                endWith0Alpha = true
            } else {
                totalSteps = 1
                startFrom0Alpha = false
                endWith0Alpha = false
            }
        }
    }
    
    private func norm(_ num: Int) -> Int {
        return num >= 0 ? num : 10 + num
    }
    
    private func easeInOut(_ t: CGFloat) -> CGFloat {
        return t * t * (3.0 - 2.0 * t)
    }
    
    private func interpolateAttributes(start: [NSAttributedString.Key: Any], 
                                     end: [NSAttributedString.Key: Any], 
                                     progress: CGFloat,
                                       traitCollection: UITraitCollection) -> [NSAttributedString.Key: Any] {
        var result = start
        
        // Interpolate colors
        if let startColor = (start[.foregroundColor] as? UIColor)?.resolvedColor(with: traitCollection),
           let endColor = (end[.foregroundColor] as? UIColor)?.resolvedColor(with: traitCollection) {
            var startRed: CGFloat = 0, startGreen: CGFloat = 0, startBlue: CGFloat = 0, startAlpha: CGFloat = 0
            var endRed: CGFloat = 0, endGreen: CGFloat = 0, endBlue: CGFloat = 0, endAlpha: CGFloat = 0
            
            startColor.getRed(&startRed, green: &startGreen, blue: &startBlue, alpha: &startAlpha)
            endColor.getRed(&endRed, green: &endGreen, blue: &endBlue, alpha: &endAlpha)
            
            let interpolatedColor = UIColor(
                red: startRed + (endRed - startRed) * progress,
                green: startGreen + (endGreen - startGreen) * progress,
                blue: startBlue + (endBlue - startBlue) * progress,
                alpha: startAlpha + (endAlpha - startAlpha) * progress
            )
            result[.foregroundColor] = interpolatedColor
        }
        
        // Use end font (fonts don't interpolate well)
        if let endFont = end[.font] {
            result[.font] = endFont
        }
        
        return result
    }
    
    func currentRects(elapsed: CGFloat,
                      total: CGFloat,
                      traitCollection: UITraitCollection) -> [WALCharacterRect] {
        let progress = easeInOut(min(1, max(0, (elapsed - delay) / charAnimationDuration)))
        let currentLeftOffset = leftOffset * progress + oldLeftOffset * (1 - progress)
        let currentAttributes = interpolateAttributes(
            start: startAttributes,
            end: endAttributes,
            progress: progress,
            traitCollection: traitCollection
        )
        
        guard change != .none else {
            return [WALCharacterRect(leftOffset: currentLeftOffset,
                                     yOffsetPercent: 0,
                                     alpha: 1,
                                     attributes: currentAttributes,
                                     char: "\(startChar)")]
        }
        guard totalSteps > 1, let startNum = Int(startChar) else {
            var rects = [WALCharacterRect]()
            let rect1 = WALCharacterRect(leftOffset: currentLeftOffset,
                                         yOffsetPercent: change == .inc ? progress : -progress,
                                         alpha: (endWith0Alpha ? (1 - progress) : 1) * (1 - progress),
                                         attributes: startAttributes,
                                         char: startChar)
            rects.append(rect1)
            if progress > 0 {
                let rect2 = WALCharacterRect(leftOffset: currentLeftOffset,
                                             yOffsetPercent: change == .inc ? -1 + progress : 1 - progress,
                                             alpha: (endWith0Alpha ? (1 - progress) : 1) * progress,
                                             attributes: currentAttributes,
                                             char: endChar)
                rects.append(rect2)
            }
            return rects
        }
        let currentStep = progress * CGFloat(totalSteps)
        let stepProgress = currentStep - floor(currentStep)
        let currentStepChar = "\(norm(startNum + Int(currentStep * (change == .inc ? 1 : -1))) % 10)"
        let nextStepChar = "\(norm(startNum + Int((currentStep + 1) * (change == .inc ? 1 : -1))) % 10)"
        var rects = [WALCharacterRect]()
        let rect1 = WALCharacterRect(leftOffset: currentLeftOffset,
                                     yOffsetPercent: change == .inc ? stepProgress : -stepProgress,
                                     alpha: (endWith0Alpha ? (1 - progress) : 1) * (startFrom0Alpha == true && currentStep < 1 ? 0 : 1 - stepProgress),
                                     attributes: currentAttributes,
                                     char: currentStepChar)
        rects.append(rect1)
        if progress > 0 {
            let rect2 = WALCharacterRect(leftOffset: currentLeftOffset,
                                         yOffsetPercent: change == .inc ? -1 + stepProgress : 1 - stepProgress,
                                         alpha: (endWith0Alpha ? (1 - progress) : 1) * stepProgress,
                                         attributes: currentAttributes,
                                         char: nextStepChar)
            rects.append(rect2)
        }
        return rects
    }
}

public class WAnimatedLabel: UILabel {
    
    private var characters = [WALCharacter]()
    private var characterRects = [WALCharacterRect]()
    private var charHeight = CGFloat(0)
    
    public private(set) var elapsedTime: Double = 0
    
    private var startTime = Double()
    private var displayLink: CADisplayLink?
    
    public private(set) var totalWidth = CGFloat(0)
    public private(set) var prevWidth = CGFloat(0)
    public private(set) var prevAttributedText: NSAttributedString?
    public var morphFromTop = true
    public var morphingEnabled = true
    public var tempRenderMorphingEnabled = true
    public var forceMorphLeftCharacters = false
    public var firstDelayInMs = CGFloat(0)
    public var additionalCharacterCountForTiming = 0
    public var morphingDuration = CGFloat(1.5)
    public var onWidthChange: (() -> Void)? = nil
    
    public init() {
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var _attributedText: NSAttributedString?
    
    public override var attributedText: NSAttributedString? {
        get {
            return _attributedText
        }
        set {
            guard newValue?.string != _attributedText?.string else {
                return
            }
            prevAttributedText = _attributedText
            
            tempRenderMorphingEnabled = morphingEnabled
            _attributedText = newValue
            super.attributedText = newValue
            
            attributedTextChanged()
        }
    }
    
    public override var text: String? {
        get {
            return _attributedText?.string
        }
        set {
            assertionFailure()
        }
    }
    
    public var nextLabelDelay: CGFloat {
        return initialDelayInMs * 2 * (1 - pow(0.5, 1 + CGFloat(_attributedText?.length ?? 1)))
    }
    
    private func attributedTextChanged() {
        let currentString = _attributedText?.string ?? ""
        let prevString = prevAttributedText?.string ?? ""
        
        // Calculate char height from the largest font in the attributed string
        charHeight = calculateMaxCharHeight()
        
        characters = []
        prevWidth = totalWidth
        var oldLeftOffset = prevWidth
        
        // Handle characters that are being removed
        if prevString.count > currentString.count {
            for i in stride(from: prevString.count - 1, to: currentString.count - 1, by: -1) {
                let charIndex = prevString.index(prevString.startIndex, offsetBy: i)
                let char = String(prevString[charIndex])
                let oldCharSize = getCharacterSize(char, attributes: getAttributesAt(index: i, in: prevAttributedText))
                oldLeftOffset -= oldCharSize.width
                let defaultAttributes: [NSAttributedString.Key: Any] = [
                    .font: font ?? UIFont.systemFont(ofSize: 17),
                    .foregroundColor: textColor ?? UIColor.label
                ]
                characters.insert(WALCharacter(oldLeftOffset: oldLeftOffset,
                                               leftOffset: oldLeftOffset,
                                               startChar: char,
                                               endChar: "",
                                               change: morphFromTop ? .inc : .dec,
                                               startAttributes: getAttributesAt(index: i, in: prevAttributedText),
                                               endAttributes: defaultAttributes), at: 0)
            }
        }
        
        oldLeftOffset = 0
        var leftOffset = CGFloat()
        var ignoreMorphingYet = !forceMorphLeftCharacters
        
        for i in 0..<currentString.count {
            let currentCharIndex = currentString.index(currentString.startIndex, offsetBy: i)
            let currentChar = String(currentString[currentCharIndex])
            let currentAttributes = getAttributesAt(index: i, in: _attributedText)
            
            if prevString.count > i {
                let prevCharIndex = prevString.index(prevString.startIndex, offsetBy: i)
                let prevChar = String(prevString[prevCharIndex])
                let prevAttributes = getAttributesAt(index: i, in: prevAttributedText)
                
                let character = WALCharacter(oldLeftOffset: oldLeftOffset,
                                             leftOffset: leftOffset,
                                             startChar: prevChar,
                                             endChar: currentChar,
                                             change: prevChar == currentChar && (Int(currentChar) == nil || ignoreMorphingYet) ? .none : morphFromTop ? .inc : .dec,
                                             startAttributes: prevAttributes,
                                             endAttributes: currentAttributes)
                characters.insert(character, at: i)
                if ignoreMorphingYet, character.change != .none {
                    ignoreMorphingYet = false
                }
                let oldCharSize = getCharacterSize(prevChar, attributes: prevAttributes)
                oldLeftOffset += oldCharSize.width
            } else {
                let defaultAttributes: [NSAttributedString.Key: Any] = [
                    .font: font ?? UIFont.systemFont(ofSize: 17),
                    .foregroundColor: textColor ?? UIColor.label
                ]
                characters.insert(WALCharacter(oldLeftOffset: oldLeftOffset,
                                               leftOffset: leftOffset,
                                               startChar: " ",
                                               endChar: currentChar,
                                               change: morphFromTop ? .inc : .dec,
                                               startAttributes: defaultAttributes,
                                               endAttributes: currentAttributes), at: i)
            }
            let charSize = getCharacterSize(currentChar, attributes: currentAttributes)
            leftOffset += charSize.width
        }
        totalWidth = leftOffset
        var steps = 0
        for character in characters {
            steps += character.totalSteps
        }
        for i in stride(from: characters.count - 1, to: 0, by: -1) {
            characters[i].delay = initialDelayInMs * 2 * (1 - pow(0.5, CGFloat(characters.count - 1 - i)))
            characters[i].charAnimationDuration = 1000 * morphingDuration - characters[i].delay - (CGFloat(initialDelayInMs * 2 * (1 - pow(0.5, CGFloat(i + additionalCharacterCountForTiming)))))
        }
        start()
    }
    
    private func getAttributesAt(index: Int, in attributedString: NSAttributedString?) -> [NSAttributedString.Key: Any] {
        guard let attributedString = attributedString, index < attributedString.length else {
            return [
                .font: font ?? UIFont.systemFont(ofSize: 17),
                .foregroundColor: textColor ?? UIColor.label
            ]
        }
        return attributedString.attributes(at: index, effectiveRange: nil)
    }
    
    private func getCharacterSize(_ char: String, attributes: [NSAttributedString.Key: Any]) -> CGSize {
        return char.size(withAttributes: attributes)
    }
    
    private func calculateMaxCharHeight() -> CGFloat {
        guard let attributedString = _attributedText, attributedString.length > 0 else {
            return "Leg".size(withAttributes: [.font: font ?? UIFont.systemFont(ofSize: 17)]).height
        }
        
        var maxHeight: CGFloat = 0
        attributedString.enumerateAttribute(.font, in: NSRange(location: 0, length: attributedString.length), options: []) { attribute, range, _ in
            if let font = attribute as? UIFont {
                maxHeight = max(maxHeight, font.pointSize)
            }
        }
        return maxHeight
    }
    
    public func start() {
        guard morphingEnabled else {
            stop()
            return
        }
        startTime = Date().timeIntervalSince1970 + firstDelayInMs / 1000
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(displayFrameTick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30.0, maximum: 120.0, preferred: 120.0)
        displayLink?.add(to: .current, forMode: .common)
    }
    
    public func pause() {
        displayLink?.isPaused = true
    }
    
    public func resume() {
        displayLink?.isPaused = false
    }
    
    public func finish() {
        displayLink?.isPaused = false
    }
    
    public func stop() {
        displayLink?.remove(from: .current, forMode: .common)
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc func displayFrameTick() {
        elapsedTime = max(0, 1000 * (Date().timeIntervalSince1970 - startTime))
        characterRects = characters.reduce([], { partialResult, nextChar in
            partialResult + nextChar.currentRects(
                elapsed: elapsedTime,
                total: morphingDuration * 1000,
                traitCollection: traitCollection
            )
        })
        if elapsedTime >= 1000 * morphingDuration + 2 * initialDelayInMs {
            tempRenderMorphingEnabled = false
            stop()
        }
        setNeedsDisplay()
        onWidthChange?()
    }
    
    override public func drawText(in rect: CGRect) {
        if !tempRenderMorphingEnabled || characters.count == 0 {
            super.drawText(in: rect) // doesn't
            invalidateIntrinsicContentSize()
            return
        }
        
        for characterRect in characterRects {
            var attributes = characterRect.attributes
            // Apply alpha to the color
            if let color = attributes[.foregroundColor] as? UIColor {
                attributes[.foregroundColor] = color.withAlphaComponent(color.cgColor.alpha * characterRect.alpha)
            }
            
            let font = (attributes[.font] as? UIFont) ?? .systemFont(ofSize: 40, weight: .bold)
            let charSize = getCharacterSize(characterRect.char, attributes: attributes)
            
            characterRect.char.draw(in: CGRect(x: characterRect.leftOffset,
                                               y: characterRect.yOffsetPercent * charSize.height + (charHeight - font.pointSize),
                                               width: charSize.width,
                                               height: charSize.height), withAttributes: attributes)
        }
        invalidateIntrinsicContentSize()
    }
    
    public override var intrinsicContentSize: CGSize {
        if !tempRenderMorphingEnabled {
            return super.intrinsicContentSize
        }
        return CGSize(width: max(prevWidth, totalWidth), height: super.intrinsicContentSize.height)
    }
}


#if DEBUG
@available(iOS 18, *)
#Preview {
    let amt = DecimalAmount(22391, decimals: 2, symbol: "$")
    let formattedString = amt.formatAttributed(
        format: .init(
            maxDecimals: 2,
            showPlus: false,
            showMinus: false,
            roundUp: false,
            precision: .exact
        ),
        integerFont: .systemFont(ofSize: 40, weight: .bold),
        fractionFont: .systemFont(ofSize: 30, weight: .bold),
        symbolFont: .systemFont(ofSize: 35, weight: .bold),
        integerColor: WTheme.primaryLabel,
        fractionColor: WTheme.secondaryLabel,
        symbolColor: WTheme.secondaryLabel
    )
    let l: WAnimatedLabel = {
        let l = WAnimatedLabel()
        l.attributedText = formattedString
        l.backgroundColor = .red.withAlphaComponent(0.1)
        return l
    }()
    l
}
#endif
