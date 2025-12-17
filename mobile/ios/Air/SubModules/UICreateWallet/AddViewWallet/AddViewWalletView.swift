
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

struct AddViewWalletView: View {
    
    var introModel: IntroModel
    
    @State var value: String = ""
    @State var isFocused: Bool = false
    
    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea(.keyboard, edges: .bottom)
                
            VStack(spacing: 32) {
                VStack(spacing: 20) {
                    WUIAnimatedSticker("animation_bill", size: 160, loop: true)
                        .frame(width: 160, height: 160)
                    
                    VStack(spacing: 20) {
                        title
                        description
                    }
                }
                addressView
                    .frame(minHeight: 100, alignment: .top)
            }
            .padding(.bottom, 100)
            .onAppear {
                if value.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        isFocused = true
                    }
                }
            }
            
            Color.clear
                .safeAreaInset(edge: .bottom) {
                    Button(action: onContinue) {
                        Text(lang("Continue"))
                    }
                    .buttonStyle(.airPrimary)
                    .padding(.bottom, 16)
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty )
                }
        }
        .padding(.horizontal, 32)
    }
    
    var title: some View {
        Text(langMd("View Any Address"))
            .multilineTextAlignment(.center)
            .font(.system(size: 28, weight: .semibold))
    }
    
    @ViewBuilder
    var description: some View {
        let symbols = ApiChain.allCases.map(\.symbol)
        Text(langMd("$import_view_account_note", arg1: langJoin(symbols, .or)))
            .font(.system(size: 17))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    var addressView: some View {
        InsetSection(backgroundColor: WTheme.sheetBackground, horizontalPadding: -16) {
            InsetCell(verticalPadding: 14) {
                HStack {
                    AddressTextField(
                        value: $value,
                        isFocused: $isFocused,
                        onNext: { onSubmit() }
                    )
                    .offset(y: 1)
                    .background(alignment: .leading) {
                        if value.isEmpty {
                            Text(lang("Wallet address or domain"))
                                .foregroundStyle(Color(UIColor.placeholderText))
                        }
                    }
                    
                    if value.isEmpty {
                        HStack(spacing: 12) {
                            Button(action: onPaste) {
                                Text(lang("Paste"))
                            }
                        }
                        .offset(x: 4)
                        .padding(.vertical, -1)
                    } else {
                        Button(action: { value = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .tint(Color(WTheme.secondaryFill))
                                .scaleEffect(0.9)
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
            .contentShape(.rect)
            .onTapGesture {
                isFocused = true
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions
    
    func onSubmit() {
        onContinue()
    }
    
    func onContinue() {
        introModel.onAddViewWalletContinue(address: self.value)
    }
    
    func onPaste() {
        if let string = UIPasteboard.general.string?.nilIfEmpty {
            value = string
        }
    }
}
