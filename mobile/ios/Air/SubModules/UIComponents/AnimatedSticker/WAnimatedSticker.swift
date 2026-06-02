//
//  WAnimatedSticker.swift
//  UIComponents
//
//  Created by Sina on 4/7/23.
//

import UIKit
import WalletContext
import SwiftUI
@_exported import LottieKit

public class WAnimatedSticker: UIView {

    @IBInspectable
    public var animationName: String = ""

    public var renderingScale: CGFloat = 2.0 {
        didSet {
            animationView?.renderingScale = renderingScale
        }
    }

    public var playbackSpeed: Double = 1.0 {
        didSet {
            animationView?.playbackSpeed = playbackSpeed
        }
    }
    
    private(set) var animationView: LottieAnimationView? = nil
    private var animationViewWidthConstraint: NSLayoutConstraint?
    private var animationViewHeightConstraint: NSLayoutConstraint?
    private var toggleState: Bool? = nil

    override open func awakeFromNib() {
        super.awakeFromNib()
    }
    
    override open func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
    }

    private func ensureAnimationView(size: CGSize) -> LottieAnimationView {
        let animationView: LottieAnimationView
        if let existingAnimationView = self.animationView {
            animationView = existingAnimationView
        } else {
            let createdAnimationView = LottieAnimationView(frame: CGRect(origin: .zero, size: size))
            createdAnimationView.translatesAutoresizingMaskIntoConstraints = false
            createdAnimationView.renderingScale = renderingScale
            createdAnimationView.playbackSpeed = playbackSpeed
            addSubview(createdAnimationView)
            let widthConstraint = createdAnimationView.widthAnchor.constraint(equalToConstant: size.width)
            let heightConstraint = createdAnimationView.heightAnchor.constraint(equalToConstant: size.height)
            NSLayoutConstraint.activate([
                createdAnimationView.centerXAnchor.constraint(equalTo: centerXAnchor),
                createdAnimationView.centerYAnchor.constraint(equalTo: centerYAnchor),
                widthConstraint,
                heightConstraint,
            ])
            self.animationViewWidthConstraint = widthConstraint
            self.animationViewHeightConstraint = heightConstraint
            self.animationView = createdAnimationView
            animationView = createdAnimationView
        }

        animationViewWidthConstraint?.constant = size.width
        animationViewHeightConstraint?.constant = size.height
        animationView.frame = CGRect(origin: .zero, size: size)
        animationView.renderingScale = renderingScale
        animationView.layoutIfNeeded()
        return animationView
    }

    private func setup(source: LottieAnimationSource, size: CGSize, playbackMode: LottieAnimationPlaybackMode) {
        let animationView = ensureAnimationView(size: size)
        self.toggleState = nil

        do {
            try animationView.setAnimationSynchronously(
                source: source,
                playbackMode: playbackMode,
                displayFirstFrameSynchronously: true
            )
        } catch {
            return
        }
    }

    private func playToggleTransition(to isOn: Bool) {
        guard let animationView else {
            return
        }
        let targetPosition: LottieAnimationStartingPosition
        if let info = animationView.animationInfo, info.frameCount > 1 {
            let midpointProgress = Double(info.frameCount / 2) / Double(max(info.frameCount - 1, 1))
            targetPosition = isOn ? .fraction(midpointProgress) : .begin
        } else {
            targetPosition = isOn ? .fraction(0.5) : .begin
        }
        animationView.playTransition(to: targetPosition)
    }
    
    public func setup(width: Int, height: Int, playbackMode: LottieAnimationPlaybackMode, bundle: Bundle = AirBundle) {
        guard let path = bundle.path(forResource: animationName, ofType: "tgs") else {
            return
        }

        setup(source: .file(path: path), size: CGSize(width: width, height: height), playbackMode: playbackMode)
    }
    
    public func setup(localUrl: URL, width: Int, height: Int, playbackMode: LottieAnimationPlaybackMode) {
        setup(
            source: .file(path: localUrl.path(percentEncoded: false)),
            size: CGSize(width: width, height: height),
            playbackMode: playbackMode
        )
    }

    public func toggle(_ on: Bool) {
        if toggleState == on {
            return
        }
        toggleState = on
        playToggleTransition(to: on)
    }

    public func pause() {
        animationView?.pause()
    }

    public func play() {
        animationView?.play()
    }

    public func showFirstFrame() {
        pause()
        animationView?.setPlaybackMode(.still(position: .begin))
        animationView?.seek(to: .begin)
    }

    public func playOnceFromStart() {
        pause()
        animationView?.setPlaybackMode(.once)
        animationView?.playOnce()
    }
    
    public func playOnce() {
        animationView?.setPlaybackMode(.once)
        animationView?.playOnce()
    }
}


public struct WUIAnimatedSticker: UIViewRepresentable {
    
    var name: String
    var size: CGFloat
    var loop: Bool
    var playTrigger: Int
    var bundle: Bundle
    
    public init(_ name: String, size: CGFloat, loop: Bool, playTrigger: Int = 0, bundle: Bundle = AirBundle) {
        self.name = name
        self.size = size
        self.loop = loop
        self.playTrigger = playTrigger
        self.bundle = bundle
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(playTrigger: playTrigger)
    }
    
    public func makeUIView(context: Context) -> WAnimatedSticker {
        let sticker = WAnimatedSticker()
        sticker.animationName = name
        sticker.setup(width: Int(size), height: Int(size), playbackMode: loop ? .loop : .once, bundle: bundle)
        return sticker
    }
    
    public func updateUIView(_ sticker: WAnimatedSticker, context: Context) {
        if playTrigger != context.coordinator.playTrigger {
            context.coordinator.playTrigger = playTrigger
            sticker.playOnce()
        }
    }
    
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: WAnimatedSticker, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
    
    public final class Coordinator {
        var playTrigger: Int
        init(playTrigger: Int) {
            self.playTrigger = playTrigger
        }
    }
}


#Preview {
    WUIAnimatedSticker("animation_congrats", size: 144, loop: true)
}
