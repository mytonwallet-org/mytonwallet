//
//  WReplacableLabel.swift
//  UIComponents
//
//  Created by Sina on 6/23/24.
//

import UIKit
import WalletContext

@MainActor
public class WReplacableLabel: UIView {

    public let label = UILabel()
    public var leadingPadding = CGFloat()

    private let trimCharacters: CharacterSet = {
        var c = CharacterSet.whitespacesAndNewlines
        c.insert(Unicode.Scalar(UInt32(0xfffc))!) // 65532, OBJECT REPLACEMENT CHARACTER
        return c
    }()
    
    override init(frame: CGRect) {
        
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setup() {
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.allowsDefaultTighteningForTruncation = true 
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    public override var intrinsicContentSize: CGSize {
        return label.intrinsicContentSize
    }
    
    private var trimmedText: String? {
        (label.attributedText?.string ?? label.text)?.trimmingCharacters(in: trimCharacters)
    }

    public func fadeIn() {
        label.alpha = 0
        label.transform = CGAffineTransform(translationX: 0, y: 10)
        invalidateIntrinsicContentSize()
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.5, delay: 0, options: [], animations: {
            self.label.alpha = 1
            self.label.transform = .identity
        })
    }

    private func setTextWithPadding(text: String) {
        guard leadingPadding > 0 else {
            label.text = text
            return
        }
        let attr = NSMutableAttributedString()
        let spacerAttachment = NSTextAttachment()
        spacerAttachment.image = UIImage()
        spacerAttachment.bounds = CGRect.init(x: 0, y: 0, width: leadingPadding, height: 0)
        attr.append(NSAttributedString(attachment: spacerAttachment))
        attr.append(NSAttributedString(
            string: text,
            attributes: [
                .font: label.font ?? .systemFont(ofSize: 15),
                .foregroundColor: label.textColor ?? WTheme.primaryLabel
            ]
        ))
        label.attributedText = attr
    }

    var animatingTextTo: String? = nil
    
    public func setText(_ text: String,
                        animatedWithDuration: TimeInterval?,
                        animateResize: Bool,
                        wasHidden: Bool = false,
                        beforeNewTextAppearance: (() -> Void)? = nil) {
        
        if text == trimmedText || text == animatingTextTo?.trimmingCharacters(in: trimCharacters) {
            return
        }
        guard let animatedWithDuration else {
            beforeNewTextAppearance?()
            animatingTextTo = nil
            setTextWithPadding(text: text)
            invalidateIntrinsicContentSize()
            return
        }
        let isLonger = text.count > (label.attributedText?.string ?? label.text)?.count ?? 0

        // Fade out and move left
        animatingTextTo = text
        func setNewText() {
            beforeNewTextAppearance?()
            // Set the new text and reset the transform
            self.animatingTextTo = nil
            self.setTextWithPadding(text: text)
            self.label.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)

            // Fade in and grow
            func fadeInAndGrow() {
                UIViewPropertyAnimator.runningPropertyAnimator(withDuration: animatedWithDuration,
                                                               delay: 0,
                                                               options: [],
                                                               animations: {
                    self.label.alpha = 1
                    self.label.transform = .identity
                    if !isLonger {
                        self.invalidateIntrinsicContentSize()
                    }
                    self.superview?.setNeedsLayout()
                    self.superview?.layoutIfNeeded()
                })
            }

            if !animateResize {
                self.invalidateIntrinsicContentSize()
                self.superview?.setNeedsLayout()
                self.superview?.layoutIfNeeded()
                fadeInAndGrow()
            } else if isLonger {
                // text is longer, first open-up space!
                UIView.animate(withDuration: wasHidden ? 0 : 0.2) {
                    self.invalidateIntrinsicContentSize()
                    self.superview?.setNeedsLayout()
                    self.superview?.layoutIfNeeded()
                } completion: { _ in
                    fadeInAndGrow()
                }
            } else {
                // text is shorter, can invalidateIntrinsicContentSize and animate text at the same time!
                fadeInAndGrow()
            }
        }
        if wasHidden {
            UIView.performWithoutAnimation { // Workaround to fix possible glitches when tapping on wallet card view to expand it.
                setNewText()
            }
        } else {
            UIViewPropertyAnimator.runningPropertyAnimator(withDuration: animatedWithDuration,
                                                           delay: 0, options: [.beginFromCurrentState], animations: {
                self.label.alpha = 0
                self.label.transform = CGAffineTransform(translationX: 0, y: -12)
            }) { _ in
                setNewText()
            }
        }
    }
}
