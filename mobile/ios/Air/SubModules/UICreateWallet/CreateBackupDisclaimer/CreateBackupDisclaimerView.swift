//
//  AboutView.swift
//  UICreateWallet
//
//  Created by nikstar on 05.09.2025.
//

import UIKit
import SwiftUI
import UIComponents
import WalletContext

enum Step: Comparable {
    case zero, one, two, three
}

struct CreateBackupDisclaimerView: View {

    let introModel: IntroModel

    @State private var currentStep: Step = .zero
    
    var body: some View {
        InsetList(topPadding: 0, spacing: 40) {
            header
            threeSteps
        }
        .backportScrollBounceBehaviorBasedOnSize()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            goToWords
        }
    }
    
    @ViewBuilder
    var header: some View {
        VStack(spacing: 24) {
            WUIAnimatedSticker("animation_snitch", size: 96, loop: false)
                .frame(width: 96, height: 96)
            Text(lang("Create Backup"))
                .font(.system(size: 28, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .multilineTextAlignment(.center)
    }
    
    @ViewBuilder
    var threeSteps: some View {
        VStack(spacing: 16) {
            StepView(
                isEnabled: currentStep >= .zero,
                isCompleted: currentStep >= .one,
                text: langMd("$safety_rules_one"),
                onTap: setStep(.one)
            )
            StepView(
                isEnabled: currentStep >= .one,
                isCompleted: currentStep >= .two,
                text: langMd("$safety_rules_two"),
                onTap: setStep(.two)
            )
            StepView(
                isEnabled: currentStep >= .two,
                isCompleted: currentStep >= .three,
                text: langMd("$safety_rules_three"),
                onTap: setStep(.three)
            )
        }
    }
    
    var goToWords: some View {
        Button(action: onGoToWords) {
            Text(lang("Go to Words"))
        }
        .buttonStyle(.airPrimary)
        .disabled(currentStep != .three)
        .animation(.smooth(duration: 0.4), value: currentStep)
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }
    
    func setStep(_ step: Step) -> () -> () {
        return {
            withAnimation(.spring(duration: 0.3)) {
                currentStep = step
            }
        }
    }
    
    func onGoToWords() {
        introModel.onGoToWords()
    }
}


private struct StepView: View {
    
    var isEnabled: Bool
    var isCompleted: Bool
    var text: LocalizedStringKey
    var onTap: () -> ()
    
    @State private var isOn = false
    
    var body: some View {
        InsetSection {
            InsetButtonCell(verticalPadding: 12, action: onTap) {
                HStack(spacing: 20) {
                    Checkmark(isOn: isCompleted)
                        .padding(.leading, 4)
                        .allowsHitTesting(false) // handled by button
                    Text(text)
                        .font(.system(size: 16, weight: .regular))
                        .contentShape(.rect(cornerRadius: 12))
                        .foregroundStyle(Color.air.primaryLabel)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .backportGeometryGroup()
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.smooth(duration: 0.4), value: isEnabled)
        .allowsHitTesting(!isCompleted && isEnabled)
    }
}

