
import SwiftUI
import UIKit
import WalletCore
import WalletContext
import Dependencies
import Perception

private let revealDuration: TimeInterval = 5

public final class WSensitiveData<Content: UIView>: WTouchPassView {
    
    public enum Alignment {
        case leading
        case trailing
        case center
    }
    
    public var shyMask: ShyMask?
    private let contentContainer: WTouchPassView
    private var content: Content?
    
    private var _cols: Int
    private let _rows: Int
    private let _cellSize: CGFloat
    private let _cornerRadius: CGFloat
    private var _theme: ShyMask.Theme
    private let _alignment: Alignment
    
    private var _isDisabled: Bool = false
    private var isRevealed = false
    private var lastReportedMaskVisible: Bool?
    private var revealResetWorkItem: DispatchWorkItem?
    private nonisolated(unsafe) var observationToken: NSObjectProtocol?
    
    /// Called when local mask visibility changes. `true` = mask visible (balance hidden), `false` = revealed or globally visible.
    public var onMaskStateChanged: ((Bool) -> Void)? {
        didSet {
            if let onMaskStateChanged, let lastReportedMaskVisible {
                onMaskStateChanged(lastReportedMaskVisible)
            }
        }
    }

    public init(cols: Int, rows: Int, cellSize: CGFloat, cornerRadius: CGFloat, theme: ShyMask.Theme, alignment: Alignment) {
        self._cols = cols
        self._rows = rows
        self._cellSize = cellSize
        self._cornerRadius = cornerRadius
        self._theme = theme
        self._alignment = alignment
        self.contentContainer = WTouchPassView()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupMaskIfNeeded(isSensitiveDataHidden: false)
        setupContainer()
        updateSensitiveData()
        
        observationToken = NotificationCenter.default.addObserver(
            forName: .updateSensitiveData,
            object: nil,
            queue: .main,
            using: { [weak self]  _ in
                MainActor.assumeIsolated {
                    self?.resetRevealAndUpdateSensitiveData()
                }
            }
        )
    }
    
    deinit {
        observationToken.map { NotificationCenter.default.removeObserver($0) }
    }
    
    private func setupMaskIfNeeded(isSensitiveDataHidden: Bool) {
        if !isSensitiveDataHidden || self.shyMask != nil { return }
        let shyMask = ShyMask(cols: _cols, rows: _rows, cellSize: _cellSize, theme: _theme)
        self.shyMask = shyMask
        addSubview(shyMask)
        shyMask.layer.cornerRadius = _cornerRadius
        shyMask.clipsToBounds = true
        shyMask.translatesAutoresizingMaskIntoConstraints = false
        shyMask.alpha = 0
        switch _alignment {
        case .leading:
            NSLayoutConstraint.activate([
                shyMask.leadingAnchor.constraint(equalTo: leadingAnchor),
                shyMask.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        case .trailing:
            NSLayoutConstraint.activate([
                shyMask.trailingAnchor.constraint(equalTo: trailingAnchor),
                shyMask.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        case .center:
            NSLayoutConstraint.activate([
                shyMask.centerYAnchor.constraint(equalTo: centerYAnchor),
                shyMask.centerXAnchor.constraint(equalTo: centerXAnchor),
            ])
        }
        setupTapGesture()
    }
    
    private func setupContainer() {
        addSubview(contentContainer)
        contentContainer.backgroundColor = .clear
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        UIView.performWithoutAnimation {
            updateSensitiveData()
        }
        if let shyMask {
            bringSubviewToFront(shyMask)
        }
    }

    public func addContent(_ content: Content) {
        assert(!content.translatesAutoresizingMaskIntoConstraints)
        self.content = content
        cancelRevealReset()
        isRevealed = false
        contentContainer.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        updateSensitiveData()
    }

    private func resetRevealAndUpdateSensitiveData() {
        cancelRevealReset()
        isRevealed = false
        updateSensitiveData()
    }

    public func resetReveal() {
        resetRevealAndUpdateSensitiveData()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateSensitiveData() {
        let isGloballyHidden = isDisabled == false && AppStorageHelper.isSensitiveDataHidden
        if !isGloballyHidden {
            isRevealed = false
            cancelRevealReset()
        }
        let isSensitiveDataHidden = isGloballyHidden && !isRevealed
        notifyMaskStateChangedIfNeeded(isSensitiveDataHidden)
        setupMaskIfNeeded(isSensitiveDataHidden: isSensitiveDataHidden)
        if isSensitiveDataHidden {
            self.shyMask?.startUpdates()
        }
        UIView.animate(withDuration: 0.3) {
            self.contentContainer.alpha = isSensitiveDataHidden ? 0 : 1
            self.shyMask?.alpha = isSensitiveDataHidden ? 1 : 0
        } completion: { [weak self] _ in
            if let self, let shyMask, shyMask.alpha == 0 {
                shyMask.pauseUpdates()
                shyMask.removeFromSuperview()
                self.shyMask = nil
            }
        }
    }
    
    private func notifyMaskStateChangedIfNeeded(_ isMaskVisible: Bool) {
        guard lastReportedMaskVisible != isMaskVisible else { return }
        lastReportedMaskVisible = isMaskVisible
        onMaskStateChanged?(isMaskVisible)
    }
    
    public var maskSize: CGSize {
        CGSize(width: CGFloat(_cols) * _cellSize, height: CGFloat(_rows) * _cellSize)
    }
    
    /// This must have been the `sizeThatFits` implementation but to avoid any involved layout breakdown for existing consumers, let's create a new method.
    /// - Note: in hidden mode the width returned is the mask one!
    public func contentSizeThatFits(_ size: CGSize) -> CGSize {
        var result = content?.sizeThatFits(size)
        
        let isSensitiveDataHidden = isDisabled == false && AppStorageHelper.isSensitiveDataHidden && !isRevealed
        if isSensitiveDataHidden {
            let maskSize = self.maskSize
            if result == nil {
                result = maskSize
            } else {
                result?.width = maskSize.width
            }
        }
        
        return result ?? .zero
    }
    
    public func setCols(_ newCols: Int) {
        self._cols = newCols
        shyMask?.setCols(newCols)
        resetReveal()
    }

    public func setTheme(_ newTheme: ShyMask.Theme) {
        self._theme = newTheme
        shyMask?.setTheme(newTheme)
        resetReveal()
    }
    
    private func setupTapGesture() {
        let g = UITapGestureRecognizer(target: self, action: #selector(onMaskTap))
        shyMask?.addGestureRecognizer(g)
    }
    
    public func performTap() {
        if !isDisabled && isTapToRevealEnabled && shyMask != nil {
            onMaskTap()
        }
    }
    
    @objc private func onMaskTap() {
        isRevealed = true
        updateSensitiveData()
        scheduleRevealReset()
    }

    private func scheduleRevealReset() {
        cancelRevealReset()
        guard !isDisabled, AppStorageHelper.isSensitiveDataHidden else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.resetRevealAndUpdateSensitiveData()
        }
        revealResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + revealDuration, execute: workItem)
    }

    private func cancelRevealReset() {
        revealResetWorkItem?.cancel()
        revealResetWorkItem = nil
    }
    
    public var isDisabled: Bool {
        get { _isDisabled }
        set {
            if _isDisabled != newValue {
                _isDisabled = newValue
            }
            resetReveal()
        }
    }
    
    /// defaults to true
    public var isTapToRevealEnabled: Bool {
        get { shyMask?.isUserInteractionEnabled ?? false }
        set { shyMask?.isUserInteractionEnabled = newValue }
    }
}


// MARK: - SwiftUI support

public struct SensitiveDataViewModifier: ViewModifier {
    
    private var alignment: Alignment
    private var cols: Int
    private var rows: Int
    private var cellSize: CGFloat?
    private var theme: ShyMask.Theme
    private var cornerRadius: CGFloat
    private var onMaskStateChanged: ((Bool) -> Void)?
    private var onReveal: (() -> Void)?
    
    @Dependency(\.sensitiveData.isHidden) private var isSensitiveDataHidden
    @State private var isRevealed = false

    private var shouldHideSensitiveData: Bool {
        isSensitiveDataHidden && !isRevealed
    }
    
    public init(
        alignment: Alignment,
        cols: Int,
        rows: Int,
        cellSize: CGFloat?,
        theme: ShyMask.Theme = .adaptive,
        cornerRadius: CGFloat,
        onMaskStateChanged: ((Bool) -> Void)? = nil,
        onReveal: (() -> Void)? = nil
    ) {
        self.alignment = alignment
        self.cols = cols
        self.rows = rows
        self.cellSize = cellSize
        self.theme = theme
        self.cornerRadius = cornerRadius
        self.onMaskStateChanged = onMaskStateChanged
        self.onReveal = onReveal
    }
    
    @ViewBuilder
    public func body(content: Content) -> some View {
        WithPerceptionTracking {
            HStack {
                if shouldHideSensitiveData {
                    content
                        .opacity(0)
                        .overlay {
                            GeometryReader { geom in
                                Color.clear.overlay(alignment: alignment) {
                                    WUIShyMask(cols: cols, rows: rows, cellSize: cellSize ?? (geom.size.height / Double(rows)), theme: theme)
                                        .fixedSize()
                                        .clipShape(.rect(cornerRadius: cornerRadius))
                                        .onTapGesture {
                                            isRevealed = true
                                            onReveal?()
                                        }
                                }
                            }
                        }
                } else {
                    content
                }
            }
            .animation(.default, value: shouldHideSensitiveData)
            .onAppear {
                onMaskStateChanged?(shouldHideSensitiveData)
            }
            .onChange(of: shouldHideSensitiveData) { isMaskVisible in
                onMaskStateChanged?(isMaskVisible)
            }
            .onChange(of: isSensitiveDataHidden) { newValue in
                if !newValue {
                    isRevealed = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateSensitiveData)) { _ in
                isRevealed = false
            }
            .task(id: isRevealed) {
                guard isRevealed, isSensitiveDataHidden else { return }
                try? await Task.sleep(for: .seconds(revealDuration))
                guard !Task.isCancelled, isSensitiveDataHidden else { return }
                isRevealed = false
            }
        }
    }
    
}

public struct SensitiveDataInPlaceViewModifier: ViewModifier {
    
    private var cols: Int
    private var rows: Int
    private var cellSize: CGFloat
    private var theme: ShyMask.Theme
    private var cornerRadius: CGFloat
    
    @Dependency(\.sensitiveData.isHidden) private var isSensitiveDataHidden
    @State private var isRevealed = false

    private var shouldHideSensitiveData: Bool {
        isSensitiveDataHidden && !isRevealed
    }
    
    public init(cols: Int, rows: Int, cellSize: CGFloat, theme: ShyMask.Theme = .adaptive, cornerRadius: CGFloat) {
        self.cols = cols
        self.rows = rows
        self.cellSize = cellSize
        self.theme = theme
        self.cornerRadius = cornerRadius
    }
    
    @ViewBuilder
    public func body(content: Content) -> some View {
        WithPerceptionTracking {
            HStack {
                if shouldHideSensitiveData {
                    WUIShyMask(cols: cols, rows: rows, cellSize: cellSize, theme: theme)
                        .fixedSize()
                        .clipShape(.rect(cornerRadius: cornerRadius))
                        .onTapGesture {
                            isRevealed = true
                        }
                } else {
                    content
                }
            }
            .animation(.default, value: shouldHideSensitiveData)
            .onChange(of: isSensitiveDataHidden) { newValue in
                if !newValue {
                    isRevealed = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateSensitiveData)) { _ in
                isRevealed = false
            }
            .task(id: isRevealed) {
                guard isRevealed, isSensitiveDataHidden else { return }
                try? await Task.sleep(for: .seconds(revealDuration))
                guard !Task.isCancelled, isSensitiveDataHidden else { return }
                isRevealed = false
            }
        }
    }
    
}

public extension View {
    @ViewBuilder
    func sensitiveData(
        alignment: Alignment,
        cols: Int,
        rows: Int,
        cellSize: CGFloat?,
        theme: ShyMask.Theme,
        cornerRadius: CGFloat,
        onMaskStateChanged: ((Bool) -> Void)? = nil,
        onReveal: (() -> Void)? = nil
    ) -> some View {
        self
            .modifier(
                SensitiveDataViewModifier(
                    alignment: alignment,
                    cols: cols,
                    rows: rows,
                    cellSize: cellSize,
                    theme: theme,
                    cornerRadius: cornerRadius,
                    onMaskStateChanged: onMaskStateChanged,
                    onReveal: onReveal
                )
            )
    }
    
    @ViewBuilder
    func sensitiveDataInPlace(cols: Int, rows: Int, cellSize: CGFloat, theme: ShyMask.Theme, cornerRadius: CGFloat) -> some View {
        self
            .modifier(SensitiveDataInPlaceViewModifier(cols: cols, rows: rows, cellSize: cellSize, theme: theme, cornerRadius: cornerRadius))
    }
}
