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
    
    case chartSelection

    /// Successful completion of an action
    case success
    
    /// Error or failure notification
    case error
}

/// Centralized haptic feedback manager for consistent tactile feedback.
@MainActor
public enum Haptics {
    
    // MARK: - Prepared Generators
    
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let softImpactGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    
    /// Prepare generators ahead of time for lower latency feedback
    public static func prepare(_ type: HapticType) {
        switch type {
        case .selection:
            selectionGenerator.prepare()
            
        case .lightTap:
            softImpactGenerator.prepare()
            
        case .transition:
            softImpactGenerator.prepare()
            
        case .drag:
            rigidImpactGenerator.prepare()
            
        case .chartSelection:
            lightImpactGenerator.prepare()

        case .success:
            notificationGenerator.prepare()

        case .error:
            notificationGenerator.prepare()
        }
    }
    
    // MARK: - Play Haptic
    
    /// Play the specified haptic feedback type
    @MainActor
    public static func play(_ type: HapticType) {
        switch type {
        case .selection:
            selectionGenerator.selectionChanged()
            
        case .lightTap:
            softImpactGenerator.impactOccurred()
            
        case .transition:
            softImpactGenerator.impactOccurred(intensity: 0.75)
            
        case .drag:
            rigidImpactGenerator.impactOccurred()

        case .chartSelection:
            lightImpactGenerator.impactOccurred(intensity: 0.75)

        case .success:
            notificationGenerator.notificationOccurred(.success)
            
        case .error:
            notificationGenerator.notificationOccurred(.error)
        }
    }
}
