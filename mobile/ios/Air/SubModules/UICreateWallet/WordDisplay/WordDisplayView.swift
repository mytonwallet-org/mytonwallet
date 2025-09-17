//
//  WordDisplayView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.09.2025.
//

import SwiftUI
import WalletContext
import WalletCore
import UIComponents

struct WordDisplayView: View {
    
    let introModel: IntroModel
    let words: [String]
    var navigationBarInset: CGFloat
    var onScroll: (CGFloat) -> ()

    @State private var shownCopyWarning = false
    @State private var shownScreenshotWarning = false
    
    @State private var showCopyWarning = false
    @State private var showScreenshotWarning = false
    @State private var showContinueWithoutCheckingWarning = false

    @Namespace private var ns

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    WUIAnimatedSticker("animation_bill", size: 96, loop: false)
                        .frame(width: 96, height: 96)
                        .padding(.top, 16)
                        .scrollPosition(ns: ns, offset: navigationBarInset, callback: onScroll)

                    title
                    warning
                    copyToClipboard
                }
                .frame(maxHeight: .infinity, alignment: .center)
                
                WordListView(words: words)
                    .padding(.bottom, 30)
                
                VStack(spacing: 12) {
                    letsCheck
                    if introModel.allowOpenWithoutChecking {
                        openWithoutChecking
                    }
                }
            }
        }
        .navigationBarInset(navigationBarInset)
        .scrollIndicators(.hidden)
        .backportScrollBounceBehaviorBasedOnSize()
        .backportScrollClipDisabled()
        .padding(.horizontal, 32)
        .padding(.bottom, 8)
        .coordinateSpace(name: ns)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            if !shownScreenshotWarning {
                showScreenshotWarning = true
                shownScreenshotWarning = true
            }
        }
    }
    
    var title: some View {
        Text(langMd("$mnemonic_list_description"))
            .multilineTextAlignment(.center)
    }
    
    var warning: some View {
        Text(langMd("$mnemonic_warning"))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.red)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                Color.red.opacity(0.08)
            }
            .clipShape(.rect(cornerRadius: 16))
            .alert(
                Text(lang("Security Warning")),
                isPresented: $showScreenshotWarning,
                actions: {
                    Button("See Words", role: .cancel) { }
                },
                message: {
                    let normal = Text(langMd("$secret_words_warning", arg1: lang("screenshot")))
                    let red = Text(lang("Other apps will be able to read your recovery phrase!")).foregroundColor(.red)
                    Text("\(normal)\n\n\(red)")
                }
            )
    }
    
    var copyToClipboard: some View {
        Button(action: onCopyToClipboard) {
            HStack(spacing: 4) {
                Image.airBundle("Copy20")
                Text(lang("Copy to Clipboard"))
            }
        }
        .buttonStyle(.airClearBackground)
        .alert(
            Text(lang("Security Warning")),
            isPresented: $showCopyWarning,
            actions: {
                Button(lang("See Words"), role: .cancel) { }
                Button(lang("Copy Anyway"), role: .destructive) { onCopyToClipboard() }
            },
            message: {
                let normal = Text(langMd("$secret_words_warning", arg1: lang("clipboard")))
                let red = Text(lang("Other apps will be able to read your recovery phrase!")).foregroundColor(.red)
                Text("\(normal)\n\n\(red)")
                
            }
        )
    }
    
    var letsCheck: some View {
        Button(action: onLetsCheck) {
            Text(lang("Let's Check"))
        }
        .buttonStyle(.airPrimary)
    }
    
    var openWithoutChecking: some View {
        Button(action: onOpenWithoutChecking) {
            Text(lang("Open wallet without checking"))
        }
        .buttonStyle(.airClearBackground)
        .alert(
            Text(lang("Security Warning")),
            isPresented: $showContinueWithoutCheckingWarning,
            actions: {
                Button(lang("See Words"), role: .cancel) { }
                Button(lang("Continue"), role: .destructive) { onOpenWithoutCheckingConfirm() }
            },
            message: {
                let normal = Text(langMd("Make sure you have your recovery phrase securely saved."))
                let red = Text(lang("Without it, you won't be able to access your wallet.")).foregroundColor(.red)
                Text("\(normal)\n\n\(red)")
                
            }
        )

    }
    
    // MARK: Actions
    
    func onCopyToClipboard() {
        if !shownCopyWarning {
            showCopyWarning = true
            shownCopyWarning = true
        } else {
            AppActions.copyString(words.joined(separator: " "), toastMessage: lang("Secret phrase was copied to clipboard"))
        }
    }
    
    func onLetsCheck() {
        introModel.onLetsCheck()
    }

    func onOpenWithoutChecking() {
        showContinueWithoutCheckingWarning = true
    }
    
    func onOpenWithoutCheckingConfirm() {
        introModel.onOpenWithoutChecking()
    }
}


struct WordListView: View {
    
    var words: [String]
    
    var count: Int { words.count }
    var halfCount: Int { count / 2 }
    
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
            ForEach(0..<halfCount, id: \.self) { i in
                GridRow {
                    Text("\(i + 1).")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(Color.air.secondaryLabel)
                    Text(verbatim: words[i])
                        .font(.system(size: 17, weight: .medium))
                        .fixedSize()
                        .frame(width: 100, alignment: .leading)
                    Text("\(i + 1 + halfCount).")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(Color.air.secondaryLabel)
                    Text(verbatim: words[i + halfCount])
                        .font(.system(size: 17, weight: .medium))
                        .fixedSize()
                        .frame(width: 60, alignment: .leading)
                    
                }
            }
        }
    }
}
