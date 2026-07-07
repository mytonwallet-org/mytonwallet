//
//  WordCheckView.swift
//
//  Created by nikstar on 04.09.2025.
//

import SwiftUI
import WalletContext
import WalletCore
import UIComponents
import Flow
import Perception

struct WordCheckView: View {

    private let bottomAnchorID = "bottom"

    var introModel: IntroModel
    var model: WordCheckModel
    
    @State private var isLoading = false
    @State private var isChecking = false
    @State private var interactionDisabled = false
    @State private var checkTask: Task<Void, Never>?
    @State private var scrollToBottom = 0

    var body: some View {
        WithPerceptionTracking {
            let tests = model.tests
            let revealCorrect = model.revealCorrect
            let hideAll = model.hideAll
            let showTryAgain = model.showTryAgain
            let allSelected = model.allSelected

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 40) {
                        VStack(spacing: 20) {
                            WUIAnimatedSticker("animation_bill", size: 124, loop: false)
                                .frame(width: 124, height: 124)
                                .padding(.top, -8)
                            VStack(spacing: 20) {
                                title
                                description(tests: tests)
                            }
                        }
                        grid(tests: tests, revealCorrect: revealCorrect, isChecking: isChecking, isEnabled: !interactionDisabled)
                            .opacity(hideAll ? 0 : 1)

                        ZStack {
                            Button("Just-a-placeholder", action: {})
                                .buttonStyle(.airClearBackground)
                                .hidden()

                            if isLoading {
                                Button(lang("Continue"), action: {})
                                    .environment(\.isLoading, true)
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)).animation(.default))
                                    .buttonStyle(.airClearBackground)
                            } else if showTryAgain {
                                error()
                                    .opacity(hideAll ? 0 : 1)
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)).animation(.default))
                            }
                        }
                        .id(bottomAnchorID)
                    }
                }
                .scrollIndicators(.hidden)
                .backportScrollBounceBehaviorBasedOnSize()
                .backportScrollClipDisabled()
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
                .allowsHitTesting(!interactionDisabled)
                .onChange(of: scrollToBottom) { _ in
                    withAnimation(.smooth(duration: 0.3)) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: allSelected) { allSelected in
                guard allSelected, !revealCorrect else { return }
                onAllWordsSelected()
            }
            .onDisappear {
                checkTask?.cancel()
            }
        }
    }
    
    private func onAllWordsSelected() {
        
        checkTask = Task { @MainActor in
            interactionDisabled = true
            withAnimation(.default) { isChecking = true }

            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }

            withAnimation(.default) { isChecking = false }
            model.revealCorrect = true

            if model.allCorrect {
                await completeWalletCreation()
            } else {
                await resetKeepingIncorrect()
            }
        }
    }

    private func resetKeepingIncorrect() async {
        withAnimation(.smooth(duration: 0.2)) {
            model.hideAll = true
        }

        try? await Task.sleep(for: .seconds(0.25))
        guard !Task.isCancelled else { return }

        model.resetKeepingIncorrect()
        scrollToBottom += 1
        withAnimation(.smooth(duration: 1.50)) {
            model.hideAll = false
        }
        interactionDisabled = false
    }

    private func completeWalletCreation() async {
        let completesHere = introModel.hasExistingPassword

        isLoading = completesHere
        interactionDisabled = completesHere
        scrollToBottom += 1

        do {
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
  
            let execution = try await introModel.onCheckPassed()
            switch execution {
            case .completed:
                break
                
            case .deferredToPasscode:
                isLoading = false
                interactionDisabled = false
            }
        } catch {
            isLoading = false
            interactionDisabled = false

            AppActions.showError(error: error)
        }
    }
    
    private var title: some View {
        Text(langMd("Let's Check"))
            .multilineTextAlignment(.center)
            .font(.system(size: 32, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }
    
    @ViewBuilder
    private func description(tests: [Test]) -> some View {
        let ids = tests.map { String($0.id + 1) }
        let line1 = lang("$check_words_description").replacingOccurrences(of: "\n", with: " ")
        let line2 = lang("$mnemonic_check_words_list", arg1: ids.joined(separator: ", "))
        Text(LocalizedStringKey(line1 + "\n\n" + line2))
            .multilineTextAlignment(.center)
            .font(.system(size: 17, weight: .regular))
            .contentTransition(.numericText())
            .animation(.default, value: tests.map(\.id))
    }

    private func grid(tests: [Test], revealCorrect: Bool, isChecking: Bool, isEnabled: Bool) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 24) {
            ForEach(tests) { test in
                GridRow {
                    Text("\(test.id + 1).")
                        .font(.system(size: 17))
                        .foregroundColor(.air.secondaryLabel)
                        .accessibilityHidden(true)
                    HFlow(spacing: 8) {
                        ForEach(test.words, id: \.self) { word in
                            let state: Item.State = {
                                if test.selection != word { return .none }
                                if !revealCorrect { return .selected }
                                return word == test.correctWord.word ? .correct : .wrong
                            }()
                            Item(
                                questionNumber: test.id + 1,
                                word: word,
                                state: state,
                                isEnabled: isEnabled,
                                onTap: {
                                    if let i = model.tests.firstIndex(where: { $0.id == test.id }) {
                                        model.tests[i].selection = word
                                    }
                                }
                            )
                            .opacity(isChecking ? 0.5 : 1)
                            .animation(.smooth(duration: 0.2), value: isChecking)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 16, weight: .medium))
                }
            }
        }
        .animation(.spring, value: revealCorrect)
        .id(tests.map(\.words))
    }

    @ViewBuilder
    private func error() -> some View {
        Text(lang("$mnemonic_check_error"))
            .multilineTextAlignment(.center)
            .foregroundStyle(.red)
            .font(.system(size: 16, weight: .medium))
    }
}


private struct Item: View {
    
    enum State {
        case none, selected, correct, wrong
    }
    
    var questionNumber: Int
    var word: String
    var state: State
    var isEnabled: Bool
    var onTap: () -> ()
    
    @SwiftUI.State private var isTouching = false
    
    var textColor: Color {
        switch state {
        case .none: .air.primaryLabel
        case .selected: .blue
        case .correct: .green
        case .wrong: .red
        }
    }
    
    var borderColor: Color {
        switch state {
        case .none: .clear
        case .selected: .blue
        case .correct: .green
        case .wrong: .red
        }
    }
    
    var lineWidth: CGFloat {
        switch state {
        case .none:
            0
        default:
            1.667
        }
    }
    
    var body: some View {
        Text(verbatim: word)
            .foregroundStyle(textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                Color.air.groupedItem
            }
            .overlay {
                ContainerRelativeShape().strokeBorder(borderColor, lineWidth: lineWidth)
            }
            .clipShape(.rect(cornerRadius: 12))
            .containerShape(.rect(cornerRadius: 12))
            .onTapGesture {
                guard isEnabled else { return }
                withAnimation(.spring(duration: 0.2, bounce: 0)) {
                    onTap()
                }
            }
            .highlightScale(isTouching, scale: 0.95, isEnabled: isEnabled)
            .touchGesture($isTouching)
            .accessibilityElement()
            .accessibilityRemoveTraits(.isStaticText)
            .accessibilityAddTraits(isEnabled ? .isButton : [])
            .accessibilityAddTraits(state != .none ? .isSelected : [])
            .accessibilityLabel(Text(verbatim: "\(questionNumber). \(word)"))
            .accessibilityAction {
                guard isEnabled else { return }
                withAnimation(.spring(duration: 0.2, bounce: 0)) {
                    onTap()
                }
            }
    }
}
