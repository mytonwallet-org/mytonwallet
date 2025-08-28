//
//  AudioHelpers.swift
//  WalletContext
//
//  Created by Sina on 7/9/24.
//

import Foundation
import AVFoundation

public class AudioHelpers {
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
    public static func play(sound: Sound) {
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
