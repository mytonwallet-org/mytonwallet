//
//  IntroView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.09.2025.
//

import SwiftUI
import WalletContext
import UIComponents

struct ActivateBiometricView: View {
    
    var onEnable: () -> ()
    var onSkip: (() -> ())?
    
    @State private var isTouching = false
    @State private var burstTrigger = 0
    
    @State private var isLoadingEnable = false
    @State private var isLoadingSkip = false
    
    var body: some View {
        VStack {
            VStack(spacing: 32) {
                iconAndEffect
                VStack(spacing: 20) {
                    title
                    shortDescription
                }
                .padding(.bottom, 180)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            VStack(spacing: 12) {
                enableButton
                skipButton
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }
    
    var iconAndEffect: some View {
        Image.airBundle("FaceIdHeaderImage")
            .highlightScale(isTouching, scale: 0.9, isEnabled: true)
            .touchGesture($isTouching)
            .frame(width: 124, height: 124)
            .background {
                ParticleBackground(color: .systemGreen, burstTrigger: $burstTrigger)
                    .opacity(0.8)
            }
            .onChange(of: isTouching) { isTouching in
                if isTouching {
                    burstTrigger += 1
                }
            }
            .backportSensoryFeedback(value: isTouching)
    }
    
    var title: some View {
        Text(lang("Use Face ID"))
            .font(.system(size: 28, weight: .semibold))
    }
    
    var shortDescription: some View {
        Text(langMd("$auth_biometric_info"))
            .multilineTextAlignment(.center)
    }
    
    var enableButton: some View {
        Button(action: _onEnable) {
            Text(lang("Connect Face ID"))
        }
        .buttonStyle(.airPrimary)
        .environment(\.isLoading, isLoadingEnable)
    }
    
    var skipButton: some View {
        Button(action: _onSkip) {
            Text(lang("Not Now"))
        }
        .buttonStyle(.airClearBackground)
        .environment(\.isLoading, isLoadingSkip)
    }
    
    func _onEnable() {
        isLoadingEnable = true
        onEnable()
    }
    
    func _onSkip() {
        isLoadingSkip = true
        onSkip?()
    }
}
