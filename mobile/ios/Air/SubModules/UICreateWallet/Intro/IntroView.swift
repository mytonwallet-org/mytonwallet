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
    @State private var isTouching = false
    @State private var isHovered = false
    
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 657
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: isCompact ? 20 : 32) {
                        iconAndEffect
                            .zIndex(1)
                        VStack(spacing: isCompact ? 12 : 20) {
                            title
                            shortDescription
                                .gesture(TapGesture(count: 5).onEnded {
                                    introModel.onDone(successKind: .imported, hadExistingAccounts: false, accountIds: [])
                                })
                        }
                        moreAbout
                    }
                    .padding(.top, isCompact ? 40 : 80)
                    .frame(maxWidth: .infinity)
                    .zIndex(1)
                    Spacer(minLength: 24)
                    VStack(spacing: 16) {
                        createNewWallet
                            .padding(.horizontal, 18)
                        importWallet
                            .padding(.horizontal, 18)
                        legalNotice
                            .padding(.top, 8)
                    }
                }
                .frame(minHeight: max(0, geometry.size.height - 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .backportScrollBounceBehaviorBasedOnSize()
        }
        .onDisappear {
            isTouching = false
            isHovered = false
        }
    }
    
    @ViewBuilder
    var iconAndEffect: some View {
        if IS_GRAM_WALLET {
            WUISpeedingDiamondWithParticles(diamondSize: 124, isWelcome: true)
        } else {
            Image.mainBundle("IntroLogo")
                .resizable()
                .frame(width: 124, height: 124)
                .highlightScale(isTouching, scale: 0.96, isEnabled: true)
                .touchGesture($isTouching)
                .frame(width: 124, height: 124)
                .background {
                    SparkleParticleBackground(isWelcome: true, welcomeColor: .tintColor,
                                              isHovered: isHovered, isPressed: isTouching)
                        .frame(width: 386, height: 268)
                        .offset(y: -10)
                }
                .onHover { isHovered = $0 }
                .backportSensoryFeedback(value: isTouching)
                .accessibilityHidden(true)
        }
    }

    var title: some View {
        Text(APP_NAME)
            .font(IS_GRAM_WALLET ? .system(size: 32, weight: .semibold) : .calSans(size: 32))
            .tracking(IS_GRAM_WALLET ? 0.4 : 0.096)
            .frame(minHeight: 40)
            .accessibilityAddTraits(.isHeader)
    }
    
    var shortDescription: some View {
        Text(langMd("$auth_intro"))
            .textStyle(.body)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 338)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    var moreAbout: some View {
        Button(action: onMoreAbout) {
            let text = L10n.moreAboutAppName(appName: APP_NAME)
            Text("\(text) ›")
                .foregroundStyle(Color.air.secondaryLabel)
                .textStyle(.body)
        }
        .frame(height: 50)
        .padding(.horizontal, 16)
        .contentShape(.capsule)
        .buttonStyle(.borderless)
    }
    
    var legalNotice: some View {
        let text = L10n.byContinuingYouAgreeToOurTermsAndPrivacy(
            terms: "[\(lang("$auth_terms_of_use"))](\(APP_TERMS_OF_USE_URL))",
            privacy: "[\(lang("$auth_privacy_policy"))](\(APP_PRIVACY_POLICY_URL))"
        )
        return Text(LocalizedStringKey(text))
            .font(.system(size: 13))
            .foregroundStyle(Color.air.secondaryLabel)
            .tint(Color.air.tint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 370)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("intro_terms")
    }
    
    var createNewWallet: some View {
        Button(action: onCreateNewWallet) {
            Text(lang("Create New Wallet"))
        }
        .buttonStyle(.airPrimary)
        .accessibilityIdentifier("intro_create_wallet")
    }
    
    var importWallet: some View {
        Button(action: onImportWallet) {
            Text(lang("Import Existing Wallet"))
        }
        .buttonStyle(.airClearBackground)
        .accessibilityIdentifier("intro_import_wallet")
    }
    
    // MARK: Actions
    
    func onMoreAbout() {
        introModel.onAbout()
    }
    
    func onCreateNewWallet() {
        introModel.onCreateWallet()
    }

    func onImportWallet() {
        introModel.onImportExisting()
    }
}
