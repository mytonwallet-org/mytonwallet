//
//  WButton.swift
//  UIComponents
//
//  Created by Sina on 3/30/23.
//

import SwiftUI
import WalletContext
import WalletCore


public struct TokenPickerButton: View {
    
    public var token: ApiToken?
    public var inBaseCurrency: Bool
    public var onTap: (() -> ())?
    
    public init(token: ApiToken?, inBaseCurrency: Bool, onTap: (() -> Void)?) {
        self.token = token
        self.inBaseCurrency = inBaseCurrency
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 6) {
                if inBaseCurrency {
                    Text(lang("in"))
                        .textStyle(.footnote, scaling: .dynamic)
                        .foregroundStyle(.secondary)
                        .transition(.scale.combined(with: .opacity).combined(with: .offset(x: 20)))
                }
                WUIIconViewToken(
                    token: token,
                    isWalletView: false,
                    showldShowChain: true,
                    size: 20,
                    chainSize: 8,
                    chainBorderWidth: 0.667,
                    chainHorizontalOffset: 3,
                    chainVerticalOffset: 1
                )
                    .frame(width: 20, height: 20)
                    
                HStack(spacing: 2) {
                    Text(token?.symbol ?? ApiToken.TONCOIN.symbol)
                        .textStyle(
                            .bodyStrong,
                            content: .technical,
                            scaling: .dynamic
                        )
                    
                    if onTap != nil {
                        Image("SendPickToken", bundle: AirBundle)
                            .textStyle(
                                .footnote,
                                content: .technical,
                                scaling: .dynamic
                            )
                            .foregroundStyle(.secondary)
                    }
                }
                
            }
            .padding(.trailing, onTap == nil ? 2 : 0)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.air.secondaryFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(.trailing, onTap == nil ? 2 : 0)
        .animation(.snappy, value: inBaseCurrency)
        .animation(.snappy, value: token)
    }
}
