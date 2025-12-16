//
//  LocaleManager.swift
//  LocaleManager
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2018 Mousavian. Distributed under MIT license.
//

import UIKit
import ObjectiveC

// MARK: -Languages

/**
 This class handles changing locale/language on the fly, while change interface direction for right-to-left languages.
 
 To use, first call `LocaleManager.setup()` method in AppDelegate's `application(_:didFinishLaunchingWithOptions:)` method, then use
 `LocaleManager.apply(identifier:)` method to change locale.
 
 - Note: If you encounter a problem in updating localized strings (e.g. tabbar items' title) set `LocaleManager.updateHandler` variable to fix issue.
 
 - Important: Due to an underlying bug in iOS, if you have an image which should be flipped for RTL languages,
     don't use asset's direction property to mirror image,
     use `image.imageFlippedForRightToLeftLayoutDirection()` to initialize flippable image instead.
 
 - Important: If you used other libraries like maximbilan/ios_language_manager before, call `applyLocale(identifier: nil)`
     for the first time to remove remnants in order to avoid conflicting.
*/

public class LocaleManager: NSObject {
    /// This handler will be called after every change in language. You can change it to handle minor localization issues in user interface.
    @objc public static var updateHandler: () -> Void = {
        return
    }
    
    /**
     This handler will be called to get root viewController to initialize.
     
     - Important: Either this property or storyboard identifier's of root view controller must be set.
     */
    @objc public static var rootViewController: ((_ window: UIWindow) -> UIViewController?)? = nil
    
    /**
     This handler will be called to get localized string before checking bundle. Allows custom translation for system strings.
     
     - Important: **DON'T USE** `NSLocalizedString()` inside the closure body. Use a `Dictionary` instead.
    */
    @objc public static var customTranslation: ((_ key: String) -> String?)? = nil
    
    /// Returns Base localization identifier
    @objc public class var base: String {
        return "Base"
    }
    
    /**
     Reloads all windows to apply orientation changes in user interface.
     
     - Important: Either rootViewController must be set or storyboardIdentifier of root viewcontroller
         in Main.storyboard must set to a string.
    */
    @MainActor internal class func reloadWindows(animated: Bool = true) {
        let windows = UIApplication.shared.sceneWindows
        for window in windows {
            if let rootViewController = self.rootViewController?(window) {
                window.rootViewController = rootViewController
            } else if let storyboard = window.rootViewController?.storyboard, let id = window.rootViewController?.value(forKey: "storyboardIdentifier") as? String {
                window.rootViewController = storyboard.instantiateViewController(withIdentifier: id)
            }
            for view in (window.subviews) {
                view.removeFromSuperview()
                window.addSubview(view)
            }
        }
        if animated {
            windows.first.map {
                UIView.transition(with: $0, duration: 0.55, options: .transitionFlipFromLeft, animations: nil, completion: nil)
            }
        }
    }
    
    /**
     Overrides system-wide locale in application setting.
     
     - Parameter identifier: Locale identifier to be applied, e.g. `en`, `fa`, `de_DE`, etc.
     */
    private class func setLocale(identifiers: [String]) {
        UserDefaults.standard.set(identifiers, forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }
    
    /// Removes user preferred locale and resets locale to system-wide.
    private class func removeLocale() {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        
        // These keys are used in maximbilan/ios_language_manager and may conflict with this implementation.
        // We remove them here.
        UserDefaults.standard.removeObject(forKey: "AppleTextDirection")
        UserDefaults.standard.removeObject(forKey: "NSForceRightToLeftWritingDirection")
        
        UserDefaults.standard.synchronize()
    }
}
