//
//  ChartDetailsView.swift
//  GraphTest
//
//  Created by Andrew Solovey on 14/03/2019.
//  Copyright © 2019 Andrei Salavei. All rights reserved.
//

import UIKit

private let cornerRadius: CGFloat = 5
private let verticalMargins: CGFloat = 8
private var labelHeight: CGFloat = 18
private var labelSpacing: CGFloat = 2
private var margin: CGFloat = 10
private var prefixLabelWidth: CGFloat = 29
private let titleLabelWidth: CGFloat = 110
private let minimumValueLabelWidth: CGFloat = 70

private final class ChartDetailsRowView: UIView {
    let prefixLabel = UILabel()
    let titleLabel = UILabel()
    let valueLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false

        prefixLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        prefixLabel.textAlignment = .right
        prefixLabel.numberOfLines = 2
        prefixLabel.lineBreakMode = .byWordWrapping

        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping

        valueLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 1

        addSubview(prefixLabel)
        addSubview(titleLabel)
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class ChartDetailsView: UIControl {
    private struct LayoutMetrics {
        let contentWidth: CGFloat
        let valueLabelWidth: CGFloat

        func totalWidth(showPrefixes: Bool) -> CGFloat {
            margin * 2 +
                (showPrefixes ? (prefixLabelWidth + margin) : 0) +
                contentWidth +
                valueLabelWidth
        }
    }

    let titleLabel = UILabel()
    let arrowView = UIImageView()
    let activityIndicator = UIActivityIndicatorView()
    let arrowButton = UIButton()

    private var rowViews: [String: ChartDetailsRowView] = [:]
    private var viewModel: ChartDetailsViewModel?
    private var textHeight: CGFloat?
    private var theme: ChartTheme = ChartTheme.defaultDayTheme
    private var layoutMetrics = LayoutMetrics(contentWidth: titleLabelWidth, valueLabelWidth: minimumValueLabelWidth)

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.cornerRadius = cornerRadius
        clipsToBounds = true

        addTarget(self, action: #selector(didTapWhole), for: .touchUpInside)
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        arrowView.image = ChartImageFactory.chevronRight(color: theme.chartDetailsArrowColor)
        arrowView.contentMode = .scaleAspectFit

        arrowButton.addTarget(self, action: #selector(didTap), for: .touchUpInside)

        addSubview(titleLabel)
        addSubview(arrowView)
        addSubview(arrowButton)
        addSubview(activityIndicator)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(viewModel: ChartDetailsViewModel, animated: Bool) {
        self.viewModel = viewModel
        layoutMetrics = makeLayoutMetrics(for: viewModel)

        titleLabel.setText(viewModel.title, animated: false)
        titleLabel.setVisible(!viewModel.title.isEmpty, animated: false)
        arrowView.setVisible(viewModel.showArrow && !viewModel.isLoading, animated: false)
        arrowButton.isUserInteractionEnabled = viewModel.showArrow && !viewModel.isLoading
        isEnabled = !viewModel.isLoading

        if viewModel.isLoading {
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
        } else {
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()
        }

        let width = layoutMetrics.totalWidth(showPrefixes: viewModel.showPrefixes)
        var y: CGFloat = verticalMargins

        if !viewModel.title.isEmpty || viewModel.showArrow {
            let reservedTrailingWidth: CGFloat = (viewModel.showArrow || viewModel.isLoading) ? 18 : 0
            titleLabel.frame = CGRect(
                x: margin,
                y: y,
                width: max(0, width - margin * 2 - reservedTrailingWidth),
                height: labelHeight
            )
            arrowView.frame = CGRect(x: width - 6 - margin, y: margin + 2, width: 6, height: 10)

            activityIndicator.transform = CGAffineTransform(scaleX: 0.65, y: 0.65)
            activityIndicator.center = CGPoint(x: width - 3 - margin, y: 16.0)

            y += labelHeight
        }

        let rowModels = viewModel.values + (viewModel.totalValue.map { [$0] } ?? [])
        let totalRowId = viewModel.totalValue?.id
        let activeRowIDs = Set(rowModels.map(\.id))
        let removedRows = rowViews.filter { !activeRowIDs.contains($0.key) }

        var nextTextHeight: CGFloat = 0.0
        var rowLayouts: [(rowView: ChartDetailsRowView, frame: CGRect, alpha: CGFloat)] = []

        for value in rowModels {
            let rowView = rowView(for: value.id)
            let rowHeight = configure(
                rowView: rowView,
                with: value,
                showPrefixes: viewModel.showPrefixes,
                isTotal: value.id == totalRowId,
                layoutMetrics: layoutMetrics
            )
            let targetFrame = CGRect(x: 0.0, y: y, width: width, height: rowHeight)

            if rowView.frame == .zero {
                rowView.frame = targetFrame
            }

            rowLayouts.append((
                rowView: rowView,
                frame: targetFrame,
                alpha: value.visible ? 1.0 : 0.0
            ))

            if value.visible {
                y += rowHeight
                nextTextHeight += rowHeight
            }
        }

        textHeight = nextTextHeight
        invalidateIntrinsicContentSize()

        UIView.perform(animated: animated, animations: {
            for rowLayout in rowLayouts {
                rowLayout.rowView.frame = rowLayout.frame
                rowLayout.rowView.alpha = rowLayout.alpha
            }
            for (_, rowView) in removedRows {
                rowView.alpha = 0.0
            }
            self.arrowButton.frame = CGRect(x: 0.0, y: 0.0, width: width, height: y)
        }, completion: { _ in
            for (id, rowView) in removedRows where self.rowViews[id] === rowView {
                rowView.removeFromSuperview()
                self.rowViews.removeValue(forKey: id)
            }
        })
    }

    override var intrinsicContentSize: CGSize {
        if let viewModel = viewModel {
            var height = ((!viewModel.title.isEmpty || viewModel.showArrow) ? labelHeight : 0) + verticalMargins * 2

            if let textHeight = textHeight {
                height += textHeight
            }

            let width: CGFloat = margin * 2 +
                (viewModel.showPrefixes ? (prefixLabelWidth + margin) : 0) +
                layoutMetrics.contentWidth +
                layoutMetrics.valueLabelWidth

            return CGSize(width: width, height: height)
        } else {
            return CGSize(width: 140, height: labelHeight + verticalMargins)
        }
    }

    @objc private func didTap() {
        viewModel?.tapAction?()
    }

    @objc private func didTapWhole() {
        viewModel?.hideAction?()
    }

    private func rowView(for id: String) -> ChartDetailsRowView {
        if let rowView = rowViews[id] {
            return rowView
        }

        let rowView = ChartDetailsRowView()
        rowView.alpha = 0.0
        addSubview(rowView)
        rowViews[id] = rowView
        return rowView
    }

    private func configure(
        rowView: ChartDetailsRowView,
        with value: ChartDetailsViewModel.Value,
        showPrefixes: Bool,
        isTotal: Bool,
        layoutMetrics: LayoutMetrics
    ) -> CGFloat {
        rowView.prefixLabel.isHidden = !showPrefixes
        rowView.prefixLabel.setTextColor(theme.chartDetailsTextColor, animated: false)
        rowView.prefixLabel.setText(value.prefix, animated: false)

        rowView.titleLabel.setTextColor(theme.chartDetailsTextColor, animated: false)
        rowView.titleLabel.setText(value.title, animated: false)

        rowView.valueLabel.setTextColor(isTotal ? theme.chartDetailsTextColor : value.color, animated: false)
        rowView.valueLabel.setText(value.value, animated: false)

        var x: CGFloat = margin
        if showPrefixes {
            rowView.prefixLabel.frame = CGRect(x: x, y: 0.0, width: prefixLabelWidth, height: labelHeight)
            x += prefixLabelWidth + margin
        } else {
            rowView.prefixLabel.frame = .zero
        }

        let titleHeight = max(
            labelHeight,
            ceil(rowView.titleLabel.sizeThatFits(CGSize(width: layoutMetrics.contentWidth, height: CGFloat.greatestFiniteMagnitude)).height)
        )
        let rowHeight = max(labelHeight, titleHeight + labelSpacing * 2.0)
        rowView.titleLabel.frame = CGRect(x: x, y: labelSpacing, width: layoutMetrics.contentWidth, height: titleHeight)
        x += layoutMetrics.contentWidth

        rowView.valueLabel.frame = CGRect(x: x, y: 0.0, width: layoutMetrics.valueLabelWidth, height: labelHeight)

        return rowHeight
    }

    private func makeLayoutMetrics(for viewModel: ChartDetailsViewModel) -> LayoutMetrics {
        let rowModels = viewModel.values + (viewModel.totalValue.map { [$0] } ?? [])
        let widestValueWidth = rowModels.reduce(CGFloat.zero) { partialResult, value in
            max(partialResult, ceil((value.value as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold)]).width))
        }

        return LayoutMetrics(
            contentWidth: titleLabelWidth,
            valueLabelWidth: max(minimumValueLabelWidth, widestValueWidth)
        )
    }
}

extension ChartDetailsView: ChartThemeContainer {
    func apply(theme: ChartTheme, strings: ChartStrings, animated: Bool) {
        self.theme = theme
        titleLabel.setTextColor(theme.chartDetailsTextColor, animated: animated)
        if let viewModel = viewModel {
            setup(viewModel: viewModel, animated: animated)
        }
        UIView.perform(animated: animated) {
            self.arrowView.image = ChartImageFactory.chevronRight(color: theme.chartDetailsArrowColor)
            self.arrowView.tintColor = theme.chartDetailsArrowColor
            self.activityIndicator.color = theme.chartDetailsArrowColor
            self.backgroundColor = theme.chartDetailsViewColor
        }
    }
}
