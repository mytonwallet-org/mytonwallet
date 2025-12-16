//
//  WAnimatedSticker.swift
//  UIComponents
//
//  Created by Sina on 4/7/23.
//

import UIKit
import GZip
import RLottieBinding
import WalletContext
import SwiftUI

public class WAnimatedSticker: UIView {

    @IBInspectable
    public var animationName: String = ""
    
    private(set) var animatedSticker: AnimatedStickerNode? = nil

    override open func awakeFromNib() {
        super.awakeFromNib()
    }
    
    override open func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
    }
    
    // setup animation data
    public func setup(width: Int, height: Int, playbackMode: AnimatedStickerPlaybackMode) {
        // load the animation
        guard let path = AirBundle.path(forResource: animationName, ofType: "tgs") else {
            return
        }

        // add animated sticker to the view
        animatedSticker = AnimatedStickerNode()
        animatedSticker?.translatesAutoresizingMaskIntoConstraints = false
        animatedSticker?.frame = CGRect(x: 0, y: 0, width: width, height: width)
        addSubview(animatedSticker!)
        animatedSticker?.didLoad()

        // setup the animated sticker
        animatedSticker?.setup(source: AnimatedStickerNodeLocalFileSource(path: path),
                               width: width * 2, height: height * 2,
                               playbackMode: playbackMode,
                               mode: .direct)
        animatedSticker?.play(firstFrame: playbackMode == .toggle(false))
    }
    
    public func setup(localUrl: URL, width: Int, height: Int, playbackMode: AnimatedStickerPlaybackMode) {
        // load the animation
        let path = localUrl.path(percentEncoded: false)

        // add animated sticker to the view
        animatedSticker = AnimatedStickerNode()
        animatedSticker?.translatesAutoresizingMaskIntoConstraints = false
        animatedSticker?.frame = CGRect(x: 0, y: 0, width: width, height: width)
        addSubview(animatedSticker!)
        animatedSticker?.didLoad()

        // setup the animated sticker
        animatedSticker?.setup(source: AnimatedStickerNodeLocalFileSource(path: path),
                               width: width * 2, height: height * 2,
                               playbackMode: playbackMode,
                               mode: .direct)
    }

    public func toggle(_ on: Bool) {
        switch animatedSticker!.playbackMode {
            case .toggle(let toggleMode):
                if toggleMode == on {
                    return
                }
                break
            default:
                break
        }
        animatedSticker?.playbackMode = .toggle(on)
        animatedSticker?.play()
    }
    
    public func playOnce() {
        _ = animatedSticker?.playIfNeeded()
    }
}


public struct WUIAnimatedSticker: UIViewRepresentable {
    
    var name: String
    var size: CGFloat
    var loop: Bool
    var playTrigger: Int
    
    public init(_ name: String, size: CGFloat, loop: Bool, playTrigger: Int = 0) {
        self.name = name
        self.size = size
        self.loop = loop
        self.playTrigger = playTrigger
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(playTrigger: playTrigger)
    }
    
    public func makeUIView(context: Context) -> WAnimatedSticker {
        let sticker = WAnimatedSticker()
        sticker.animationName = name
        sticker.setup(width: Int(size), height: Int(size), playbackMode: loop ? .loop : .once)
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
