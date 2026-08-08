
import SwiftUI
import UIComponents
import WalletContext
import Perception


struct LedgerSignView<HeaderView: View>: View {

    var headerView: HeaderView
    var compactHeaderView: AnyView
    var viewModel: LedgerViewModel

    var body: some View {
        WithPerceptionTracking {
            AdaptiveLedgerSignLayout {
                headerView
                    .padding(44)

                compactHeaderView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)

                ledgerPanel
            }
            .clipped()
        }
    }

    private var ledgerPanel: some View {
        ZStack {
            Color.air.background
                .clipShape(.rect(cornerRadius: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Image.mainBundle("LedgerConnect")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 60)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                LedgerStepsView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                buttons
            }
        }
    }
    
    @ViewBuilder
    var buttons: some View {
        HStack {
            Button(action: { viewModel.stop() }) {
                Text(viewModel.exitButtonTitle)
            }
            .buttonStyle(WUIButtonStyle(style: .clearBackground))
            .environment(\.isEnabled, viewModel.backEnabled)
            
            if viewModel.showRetry {
                Button(action: { viewModel.restart() }) {
                    Text(lang("Try Again"))
                }
                .buttonStyle(WUIButtonStyle(style: .secondary))
                .environment(\.isEnabled, viewModel.retryEnabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .animation(.smooth, value: viewModel.showRetry)
    }
}

private struct AdaptiveLedgerSignLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 3 else {
            return proposal.replacingUnspecifiedDimensions()
        }
        let width = proposal.width
        let measurements = measurements(width: width, subviews: subviews)
        let usesCompactHeader = proposal.height.map {
            measurements.fullHeader.height + measurements.panel.height > $0
        } ?? false
        let header = usesCompactHeader ? measurements.compactHeader : measurements.fullHeader
        return CGSize(
            width: width ?? max(header.width, measurements.panel.width),
            height: proposal.height ?? header.height + measurements.panel.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 3 else { return }
        let measurements = measurements(width: bounds.width, subviews: subviews)
        let usesCompactHeader = measurements.fullHeader.height + measurements.panel.height > bounds.height
        let headerIndex = usesCompactHeader ? 1 : 0
        let unusedHeaderIndex = usesCompactHeader ? 0 : 1
        let headerSize = usesCompactHeader ? measurements.compactHeader : measurements.fullHeader

        subviews[headerIndex].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: headerSize.height)
        )
        subviews[unusedHeaderIndex].place(
            at: CGPoint(x: bounds.maxX + bounds.width, y: bounds.minY),
            anchor: .topLeading,
            proposal: .zero
        )
        subviews[2].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + headerSize.height),
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: bounds.width,
                height: max(bounds.height - headerSize.height, 0)
            )
        )
    }

    private func measurements(width: CGFloat?, subviews: Subviews) -> Measurements {
        let proposal = ProposedViewSize(width: width, height: nil)
        return Measurements(
            fullHeader: subviews[0].sizeThatFits(proposal),
            compactHeader: subviews[1].sizeThatFits(proposal),
            panel: subviews[2].sizeThatFits(proposal)
        )
    }

    private struct Measurements {
        let fullHeader: CGSize
        let compactHeader: CGSize
        let panel: CGSize
    }
}
