//
//  IntroView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.09.2025.
//

import SwiftUI
import WalletContext
import UIComponents

struct IntroView: View {
    
    let introModel: IntroModel
    @State private var didAgreeToTerms = false
    
    @State private var isTouching = false
    @State private var burstTrigger = 0
    
    var body: some View {
        VStack {
            VStack(spacing: 32) {
                iconAndEffect
                VStack(spacing: 20) {
                    title
                    shortDescription
                        .gesture(TapGesture(count: 5).onEnded {
                            introModel.onDone(successKind: .imported)
                        })
                }
                moreAbout
            }
            .frame(maxHeight: .infinity, alignment: .center)
            VStack(spacing: 12) {
                useResposibly
                createNewWallet
                importWallet
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }
    
    var iconAndEffect: some View {
        Image.airBundle("IntroLogo")
            .highlightScale(isTouching, scale: 0.9, isEnabled: true)
            .touchGesture($isTouching)
            .frame(width: 124, height: 124)
            .background {
                ParticleBackground(burstTrigger: $burstTrigger)
            }
            .onChange(of: isTouching) { isTouching in
                if isTouching {
                    burstTrigger += 1
                }
            }
            .backportSensoryFeedback(value: isTouching)
    }
    
    var title: some View {
        Text(APP_NAME)
            .font(.nunito(size: 32))
    }
    
    var shortDescription: some View {
        Text(langMd("$auth_intro"))
            .multilineTextAlignment(.center)
    }
    
    var moreAbout: some View {
        Button(action: onMoreAbout) {
            let text = lang("More about %app_name%", arg1: APP_NAME)
            Text("\(text) ›")
                .foregroundStyle(Color.air.secondaryLabel)
                .fontWeight(.regular)
        }
        .padding(16)
        .contentShape(.capsule)
        .buttonStyle(.borderless)
        .padding(-16)
    }
    
    @ViewBuilder
    var useResposibly: some View {
        let link = "[\(lang("use the wallet responsibly"))](responsibly://s)"
        let text = langMd("I agree to %term%", arg1: link)
        
        HStack(spacing: 10) {
            Checkmark(isOn: didAgreeToTerms)
            Text(text)
                .foregroundStyle(Color.air.secondaryLabel)
                .font(.system(size: 14, weight: .medium))
                .padding(.vertical, 16)
                .contentShape(.rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onTapGesture(perform: onAgreeToTerms)
        .environment(\.openURL, OpenURLAction { _ in
            onUseResponsibly()
            return .handled
        })
    }
    
    var createNewWallet: some View {
        Button(action: onCreateNewWallet) {
            Text(lang("Create New Wallet"))
        }
        .buttonStyle(.airPrimary)
        .disabled(!didAgreeToTerms)
        .animation(.smooth(duration: 0.4), value: didAgreeToTerms)
    }
    
    var importWallet: some View {
        Button(action: onImportWallet) {
            Text(lang("Import Existing Wallet"))
        }
        .buttonStyle(.airClearBackground)
        .disabled(!didAgreeToTerms)
        .animation(.smooth(duration: 0.4), value: didAgreeToTerms)
    }
    
    // MARK: Actions
    
    func onMoreAbout() {
        introModel.onAbout()
    }
    
    func onAgreeToTerms() {
        withAnimation(.spring(duration: 0.3)) {
            didAgreeToTerms.toggle()
        }
    }
    
    func onUseResponsibly() {
        introModel.onUseResponsibly()
    }

    func onCreateNewWallet() {
        introModel.onCreateWallet()
    }

    func onImportWallet() {
        introModel.onImportExisting()
    }
}
