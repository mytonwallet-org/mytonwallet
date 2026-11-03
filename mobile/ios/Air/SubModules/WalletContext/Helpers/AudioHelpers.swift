//
//  AudioHelpers.swift
//  WalletContext
//
//  Created by Sina on 7/9/24.
//

import Foundation
import AVFoundation

@MainActor public class AudioHelpers {
    public enum Sound {
        case incomingTransaction
        
        var url: URL? {
            switch self {
            case .incomingTransaction:
                guard let path = AirBundle.path(forResource: "incoming-transaction", ofType:"mp3") else {
                    return nil
                }
                return URL(fileURLWithPath: path)
            }
        }
    }
    
    private static var player: AVAudioPlayer? = nil
    private static var soundSuspensions: Set<UUID> = []

    public static func suspendSounds() -> @MainActor @Sendable () -> Void {
        let id = UUID()
        soundSuspensions.insert(id)
        player?.stop()
        player = nil
        return { soundSuspensions.remove(id) }
    }

    public static func play(sound: Sound) {
        play(sound: sound) { sound in
            guard let url = sound.url else {return}
            do {
                try AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
                try AVAudioSession.sharedInstance().setActive(true)
                player = try AVAudioPlayer(contentsOf: url)
                player?.play()
            } catch {
            }
        }
    }

    static func play(sound: Sound, using playback: (Sound) -> Void) {
        guard soundSuspensions.isEmpty else { return }
        playback(sound)
    }
}
