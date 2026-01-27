//
//  IntroView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.09.2025.
//

import SwiftUI
import WalletContext
import UIComponents
import Perception

struct ActivateBiometricView: View {
    
    var viewModel: ActivateBiometricViewModel

    var onEnable: () -> Void
    var onSkip: () -> Void
    
    private let titleText: String
    private let enableButtonText: String
    private let imageResourceName: String
    
    init(viewModel: ActivateBiometricViewModel, onEnable: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.onEnable = onEnable
        self.onSkip = onSkip
        self.viewModel = viewModel
        
        switch viewModel.biometryType {
        case .face:
            titleText = lang("Use Face ID")
            enableButtonText = lang("Connect Face ID")
            imageResourceName = "FaceIdHeaderImage"
            
        case .touch:
            titleText = lang("Use Touch ID")
            enableButtonText = lang("Connect Touch ID")
            imageResourceName = "TouchIdHeaderImage"
        }
    }
    
    @State private var isTouching = false
    @State private var burstTrigger = 0
        
    var body: some View {
        WithPerceptionTracking {
            VStack {
                VStack(spacing: 32) {
                    iconAndEffect                    
                    VStack(spacing: 20) {
                        title
                        shortDescription
                    }
                    
                    Color.clear.frame(minHeight: 0, maxHeight: 148)
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
    }
    
    var iconAndEffect: some View {
        Image.airBundle(imageResourceName)
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
        Text(titleText)
            .style(.header28)
    }
        
    var shortDescription: some View {
        Text(langMd("$auth_biometric_info"))
            .style(.body17)
            .multilineTextAlignment(.center)
    }
    
    var enableButton: some View {
        Button(action: _onEnable) {
            Text(enableButtonText)
        }
        .buttonStyle(.airPrimary)
        .environment(\.isLoading, viewModel.isAuthenticationInProgress)
        .environment(\.isEnabled, viewModel.areButtonsEnabled)
    }
    
    var skipButton: some View {
        Button(action: _onSkip) {
            Text(lang("Not Now"))
        }
        .buttonStyle(.airClearBackground)
        .environment(\.isLoading, viewModel.isSkippingInProgress)
        .environment(\.isEnabled, viewModel.areButtonsEnabled)
    }
    
    func _onEnable() {
        onEnable()
    }
    
    func _onSkip() {
        onSkip()
    }
}
