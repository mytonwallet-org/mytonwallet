
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception

struct DappHeaderView: View {
    
    var dapp: ApiDapp
    var accountContext: AccountContext
    
    var showWarning: Bool { dapp.isUrlEnsured != true }
    
    var body: some View {
        WithPerceptionTracking {
            HStack {
                leadingSide
                trailingSide
            }
            .truncationMode(.middle)
            .allowsTightening(true)
            .foregroundStyle(.white)
            .background {
                Background()
            }
            .clipShape(.containerRelative)
            .containerShape(.rect(cornerRadius: 26))
            .padding(.horizontal, 16)
        }
    }
    
    var leadingSide: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(accountContext.account.displayName)
                .font(.system(size: 16, weight: .medium))
                .frame(minHeight: 22)
            if let balance = accountContext.balance {
                Text(balance.formatted(.baseCurrencyEquivalent))
                    .font(.system(size: 14, weight: .regular))
                    .opacity(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(.leading, 16)
    }
    
    var trailingSide: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                title
                    .lineLimit(3)
                transfer
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(3)
            }
            icon
        }
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .multilineTextAlignment(.trailing)
        .background {
            ZStack {
                BackgroundBlur(radius: 16)
                Rectangle()
                    .fill(.black)
                    .opacity(0.1)
                    .blendMode(.plusDarker)
            }
            .frame(maxWidth: .infinity)
            .clipShape(HeaderLine())
            .padding(.leading, -24)
        }
    }
    
    var title: some View {
        Text(dapp.name)
            .font(.system(size: 16, weight: .medium))
            .frame(minHeight: 22)
    }
    
    var icon: some View {
        DappIcon(iconUrl: dapp.iconUrl)
            .frame(width: 40, height: 40)
            .background(Color(WTheme.secondaryFill))
            .clipShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    var transfer: some View {
        let dapp = Text(dapp.displayUrl)
            .foregroundColor(.white.opacity(0.75))
        if showWarning {
            let warning = Text(Image(systemName: "exclamationmark.circle.fill"))
                .foregroundColor(Color.orange)
                .fontWeight(.bold)
            Text("\(dapp) \(warning)")
                .imageScale(.small)
                .contentShape(.rect)
                .onTapGesture {
                    topWViewController()?.showTip(title: lang("Unverified Source"), kind: .warning) {
                        EmptyView()
                    }
                }
        } else {
            Text("\(dapp)")
        }
    }
}

struct AngledArea: Shape {
    
    var x: CGFloat
    var radiusMultiplier: CGFloat
    
    nonisolated func path(in rect: CGRect) -> Path {
        Path {
            let h = rect.height
            let w = rect.width
            let x = w * x
            let r = (w + h) * radiusMultiplier
            $0.move(to: CGPoint(x: x, y: 2 * h))
            $0.addRelativeArc(center: CGPoint(x: x + r, y: 2 * h), radius: r, startAngle: .degrees(-180), delta: .degrees(90))
            $0.addLine(to: CGPoint(x: 0, y: 0))
            $0.addLine(to: CGPoint(x: 0, y: 2 * h))
            $0.addLine(to: CGPoint(x: x, y: 2 * h))
            $0.closeSubpath()
        }
    }
}

struct HeaderLine: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path {
            let h = rect.height
            let w = rect.width
            let dx = 0.3 * h
            let dw = 7.0
            let ds = 5.0
            let x1 = dw + ds
            let r = 10.0
            $0.move(to: CGPoint(x: 0, y: 0))
            $0.addArc(
                tangent1End: CGPoint(x: dx, y: h/2),
                tangent2End: CGPoint(x: 0, y: h),
                radius: r
            )
            $0.addLine(to: CGPoint(x: 0, y: h))
            $0.addLine(to: CGPoint(x: dw, y: h))
            $0.addArc(
                tangent1End: CGPoint(x: dw + dx, y: h/2),
                tangent2End: CGPoint(x: dw, y: 0),
                radius: r + dw * 0.5
            )
            $0.addLine(to: CGPoint(x: dw, y: 0))
            $0.closeSubpath()
            
            $0.move(to: CGPoint(x: x1, y: 0))
            $0.addArc(
                tangent1End: CGPoint(x: x1 + dx, y: h/2),
                tangent2End: CGPoint(x: x1, y: h),
                radius: r + x1 * 0.5
            )
            $0.addLine(to: CGPoint(x: x1, y: h))
            $0.addLine(to: CGPoint(x: w, y: h))
            $0.addLine(to: CGPoint(x: w, y: 0))
            
        }
    }
}

private struct Background: View {
    var body: some View {
        ZStack {
            Rectangle()
            AngledArea(x: 0.05, radiusMultiplier: 0.9)
                .fill(.white)
                .opacity(0.1)
            AngledArea(x: 0.17, radiusMultiplier: 0.7)
                .fill(.white)
                .opacity(0.1)
            AngledArea(x: 0.3, radiusMultiplier: 0.55)
                .fill(.white)
                .opacity(0.1)
        }
        .foregroundStyle(.tint)
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview {
    @Previewable @AccountContext(source: .current) var account: MAccount
    DappHeaderView(dapp: .sample, accountContext: _account)
        .padding(16)
}
#endif
