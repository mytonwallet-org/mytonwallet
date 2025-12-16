//
//  Haptics.swift
//  UIComponents
//
//  Centralized haptic feedback utility for consistent tactile feedback across the app.
//

import UIKit

/// Standardized haptic feedback types used throughout the app.
public enum HapticType {
    /// Light "tick" for selection changes (pickers, carousels, menus)
    case selection
    
    /// Light tap for copy actions and soft confirmations
    case lightTap
    
    /// UI state transitions (expand/collapse, modal present)
    case transition
    
    /// Drag and drop, reordering operations
    case drag
    
    /// Successful completion of an action
    case success
    
    /// Error or failure notification
    case error
}

/// Centralized haptic feedback manager for consistent tactile feedback.
@MainActor
public enum Haptics {
    
    // MARK: - Prepared Generators
    
    private static var selectionGenerator: UISelectionFeedbackGenerator?
    private static var lightTapGenerator: UIImpactFeedbackGenerator?
    private static var transitionGenerator: UIImpactFeedbackGenerator?
    private static var dragGenerator: UIImpactFeedbackGenerator?
    private static var notificationGenerator: UINotificationFeedbackGenerator?
    
    /// Prepare generators ahead of time for lower latency feedback
    public static func prepare(_ type: HapticType) {
        switch type {
        case .selection:
            if selectionGenerator == nil {
                selectionGenerator = UISelectionFeedbackGenerator()
            }
            selectionGenerator?.prepare()
            
        case .lightTap:
            if lightTapGenerator == nil {
                lightTapGenerator = UIImpactFeedbackGenerator(style: .soft)
            }
            lightTapGenerator?.prepare()
            
        case .transition:
            if transitionGenerator == nil {
                transitionGenerator = UIImpactFeedbackGenerator(style: .soft)
            }
            transitionGenerator?.prepare()
            
        case .drag:
            if dragGenerator == nil {
                dragGenerator = UIImpactFeedbackGenerator(style: .rigid)
            }
            dragGenerator?.prepare()
            
        case .success, .error:
            if notificationGenerator == nil {
                notificationGenerator = UINotificationFeedbackGenerator()
            }
            notificationGenerator?.prepare()
        }
    }
    
    // MARK: - Play Haptic
    
    /// Play the specified haptic feedback type
    @MainActor
    public static func play(_ type: HapticType) {
        switch type {
        case .selection:
            if let generator = selectionGenerator {
                generator.selectionChanged()
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            
        case .lightTap:
            if let generator = lightTapGenerator {
                generator.impactOccurred()
            } else {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            
        case .transition:
            if let generator = transitionGenerator {
                generator.impactOccurred(intensity: 0.75)
            } else {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.75)
            }
            
        case .drag:
            if let generator = dragGenerator {
                generator.impactOccurred()
            } else {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            
        case .success:
            if let generator = notificationGenerator {
                generator.notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            
        case .error:
            if let generator = notificationGenerator {
                generator.notificationOccurred(.error)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
