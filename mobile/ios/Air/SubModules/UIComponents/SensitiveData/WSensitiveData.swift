
import SwiftUI
import UIKit
import WalletCore
import WalletContext
import Dependencies
import Perception

public final class WSensitiveData<Content: UIView>: WTouchPassView, WSensitiveDataProtocol {
    
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
        self.content = content
        contentContainer.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        updateSensitiveData()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateSensitiveData() {
        let isSensitiveDataHidden = isDisabled == false && AppStorageHelper.isSensitiveDataHidden
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
    
    public func setCols(_ newCols: Int) {
        self._cols = newCols
        shyMask?.setCols(newCols)
    }

    public func setTheme(_ newTheme: ShyMask.Theme) {
        self._theme = newTheme
        shyMask?.setTheme(newTheme)
    }
    
    private func setupTapGesture() {
        let g = UITapGestureRecognizer(target: self, action: #selector(onMaskTap))
        shyMask?.addGestureRecognizer(g)
    }
    
    @objc private func onMaskTap() {
        AppActions.setSensitiveDataIsHidden(false)
    }
    
    public var isDisabled: Bool {
        get { _isDisabled }
        set {
            _isDisabled = newValue
            updateSensitiveData()
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
    
    @Dependency(\.sensitiveData.isHidden) private var isSensitiveDataHidden
    
    public init(alignment: Alignment, cols: Int, rows: Int, cellSize: CGFloat?, theme: ShyMask.Theme = .adaptive, cornerRadius: CGFloat) {
        self.alignment = alignment
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
                if isSensitiveDataHidden {
                    content
                        .opacity(0)
                        .overlay {
                            GeometryReader { geom in
                                Color.clear.overlay(alignment: alignment) {
                                    WUIShyMask(cols: cols, rows: rows, cellSize: cellSize ?? (geom.size.height / Double(rows)), theme: theme)
                                        .fixedSize()
                                        .clipShape(.rect(cornerRadius: cornerRadius))
                                        .onTapGesture {
                                            AppActions.setSensitiveDataIsHidden(false)
                                        }
                                }
                            }
                        }
                } else {
                    content
                }
            }
            .animation(.default, value: isSensitiveDataHidden)
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
                if isSensitiveDataHidden {
                    WUIShyMask(cols: cols, rows: rows, cellSize: cellSize, theme: theme)
                        .fixedSize()
                        .clipShape(.rect(cornerRadius: cornerRadius))
                        .onTapGesture {
                            AppActions.setSensitiveDataIsHidden(false)
                        }
                } else {
                    content
                }
            }
            .animation(.default, value: isSensitiveDataHidden)
        }
    }
    
}

public extension View {
    @ViewBuilder
    func sensitiveData(alignment: Alignment, cols: Int, rows: Int, cellSize: CGFloat?, theme: ShyMask.Theme, cornerRadius: CGFloat) -> some View {
        self
            .modifier(SensitiveDataViewModifier(alignment: alignment, cols: cols, rows: rows, cellSize: cellSize, theme: theme, cornerRadius: cornerRadius))
    }
    
    @ViewBuilder
    func sensitiveDataInPlace(cols: Int, rows: Int, cellSize: CGFloat, theme: ShyMask.Theme, cornerRadius: CGFloat) -> some View {
        self
            .modifier(SensitiveDataInPlaceViewModifier(cols: cols, rows: rows, cellSize: cellSize, theme: theme, cornerRadius: cornerRadius))
    }
}
