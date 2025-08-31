//
//  LocaleManager.swift
//  LocaleManager
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2018 Mousavian. Distributed under MIT license.
//

import UIKit
import ObjectiveC
import WalletContext

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
     Iterates all localization done by developer in app. It can be used to show available option for user.
     
     Key in returned dictionay can be used as identifer for passing to `apply(identifier:)`.
     
     Value is localized name of language according to current locale and should be shown in user interface.
     
     - Note: First item will be `Base` localization.
     
     - Return: A dictionary that keys are language identifiers and values are localized language name
    */
    @objc public class var availableLocalizations: [String: String] {
        let keys = Bundle.main.localizations
        let vals = keys.map({ Locale.userPreferred.localizedString(forIdentifier: $0) ?? $0 })
        return [String: String].init(zip(keys, vals), uniquingKeysWith: { v, _ in v })
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
    
    /**
     Overrides system-wide locale in application and reloads interface.
     
     - Parameter identifier: Locale identifier to be applied, e.g. `en` or `fa_IR`. `nil` value will change locale to system-wide.
     */
    @available(iOS 9.0, *)
    @objc public class func apply(locale: Locale?, animated: Bool = true) {
        let semantic: UISemanticContentAttribute
        if let locale = locale {
            //setLocale(identifiers: [locale.identifier])
            semantic = locale.isRTL ? .forceRightToLeft : .forceLeftToRight
        } else {
            removeLocale()
            semantic = Locale.baseLocale.isRTL ? .forceRightToLeft : .forceLeftToRight
        }
        Locale.cachePreffered = nil
        UIView.appearance().semanticContentAttribute = semantic
        UITableView.appearance().semanticContentAttribute = semantic
        UISwitch.appearance().semanticContentAttribute = semantic
        UITableViewCell.appearance().semanticContentAttribute = semantic
        UINavigationBar.appearance().semanticContentAttribute = semantic
        
        //reloadWindows(animated: animated)
        //updateHandler()
    }
    
    /**
     Overrides system-wide locale in application and reloads interface.
     
     - Parameter identifier: Locale identifier to be applied, e.g. `en` or `fa_IR`. `nil` value will change locale to system-wide.
     */
    @available(iOS 9.0, *)
    @objc public class func apply(identifier: String?, animated: Bool = true) {
        let locale = identifier.map(Locale.init(identifier:))
        apply(locale: locale, animated: animated)
    }
    
    /**
     This method MUST be called in `application(_:didFinishLaunchingWithOptions:)` method.
     */
    @objc public class func setup() {
        // Allowing to update localized string on the fly.
        Bundle.swizzleMethod(#selector(Bundle.localizedString(forKey:value:table:)),
                             with: #selector(Bundle.mn_custom_localizedString(forKey:value:table:)))
        // Enforcing userInterfaceLayoutDirection based on selected locale. Fixes pop gesture in navigation controller.
        UIApplication.swizzleMethod(#selector(getter: UIApplication.userInterfaceLayoutDirection),
                                    with: #selector(getter: UIApplication.mn_custom_userInterfaceLayoutDirection))
        // Enforcing currect alignment for labels and texts which has `.natural` direction.
        UILabel.swizzleMethod(#selector(UILabel.layoutSubviews), with: #selector(UILabel.mn_custom_layoutSubviews))
        UITextField.swizzleMethod(#selector(UITextField.layoutSubviews), with: #selector(UITextField.mn_custom_layoutSubviews))
    }
}

public extension UITextField {
    private struct AssociatedKeys {
        static var originalAlignment = "lm_originalAlignment"
        static var forcedAlignment = "lm_forcedAlignment"
    }
    
    var originalAlignment: NSTextAlignment? {
        get {
            return (objc_getAssociatedObject(self, &AssociatedKeys.originalAlignment) as? Int).flatMap(NSTextAlignment.init(rawValue:))
        }
        
        set {
            if let newValue = newValue {
                objc_setAssociatedObject(
                    self,
                    &AssociatedKeys.originalAlignment,
                    newValue.rawValue as NSNumber,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }
    
    var forcedAlignment: NSTextAlignment? {
        get {
            return (objc_getAssociatedObject(self, &AssociatedKeys.forcedAlignment) as? Int).flatMap(NSTextAlignment.init(rawValue:))
        }
        
        set {
            if let newValue = newValue {
                objc_setAssociatedObject(
                    self,
                    &AssociatedKeys.forcedAlignment,
                    newValue.rawValue as NSNumber,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }
    
    @objc internal func mn_custom_layoutSubviews() {
        if originalAlignment == nil {
            originalAlignment = self.textAlignment
        }
        
        if let forcedAlignment = forcedAlignment {
            self.textAlignment = forcedAlignment
        } else if originalAlignment == .natural {
            self.textAlignment = Locale._userPreferred.isRTL ? .right : .left
        }
        
        self.mn_custom_layoutSubviews()
    }
}

public extension UILabel {
    private struct AssociatedKeys {
        static var originalAlignment = "lm_originalAlignment"
        static var forcedAlignment = "lm_forcedAlignment"
    }
    
    var originalAlignment: NSTextAlignment? {
        get {
            return (objc_getAssociatedObject(self, &AssociatedKeys.originalAlignment) as? Int).flatMap(NSTextAlignment.init(rawValue:))
        }
        
        set {
            if let newValue = newValue {
                objc_setAssociatedObject(
                    self,
                    &AssociatedKeys.originalAlignment,
                    newValue.rawValue as NSNumber,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }
    
    var forcedAlignment: NSTextAlignment? {
        get {
            return (objc_getAssociatedObject(self, &AssociatedKeys.forcedAlignment) as? Int).flatMap(NSTextAlignment.init(rawValue:))
        }
        
        set {
            if let newValue = newValue {
                objc_setAssociatedObject(
                    self,
                    &AssociatedKeys.forcedAlignment,
                    newValue.rawValue as NSNumber,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }
    
    @objc internal func mn_custom_layoutSubviews() {
        if originalAlignment == nil {
            originalAlignment = self.textAlignment
        }
        
        if let forcedAlignment = forcedAlignment {
            self.textAlignment = forcedAlignment
        } else if originalAlignment == .natural {
            self.textAlignment = Locale._userPreferred.isRTL ? .right : .left
        }
        
        self.mn_custom_layoutSubviews()
    }
}

extension UIApplication {
    @objc var mn_custom_userInterfaceLayoutDirection: UIUserInterfaceLayoutDirection {
        get {
            let _ = self.mn_custom_userInterfaceLayoutDirection // DO NOT OPTIMZE!
            return Locale._userPreferred.isRTL ? .rightToLeft : .leftToRight
        }
    }
}

extension Bundle {
    private static var savedLanguageNames: [String: String] = [:]
    
    private func languageName(for lang: String) -> String? {
        if let langName = Bundle.savedLanguageNames[lang] {
            return langName
        }
        let langName = Locale(identifier: "en").localizedString(forLanguageCode: lang)
        Bundle.savedLanguageNames[lang] = langName
        return langName
    }
    
    fileprivate func resourcePath(for locale: Locale) -> String? {
        /*
         After swizzling localizedString() method, this procedure will be used even for system provided frameworks.
         Thus we shall try to find appropriate localization resource in current bundle, not main.
         
         Apple's framework
         
         Trying to find appropriate lproj resource in the bundle ordered by:
         1. Locale identifier (e.g: en_GB, fa_IR)
         2. Locale language code (e.g en, fa)
         3. Locale language name (e.g English, Japanese), used as resource name in Apple system bundles' localization (Foundation, UIKit, ...)
         */
        if let path = self.path(forResource: locale.identifier, ofType: "lproj") {
            return path
        } else if let path = locale.languageCode.flatMap(languageName(for:)).flatMap({ self.path(forResource: $0, ofType: "lproj") }) {
            return path
        } else if let path = languageName(for: locale.identifier).flatMap({ self.path(forResource: $0, ofType: "lproj") }) {
            return path
        } else {
            return nil
        }
    }
    
    @objc func mn_custom_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let customString = LocaleManager.customTranslation?(key) {
            return customString
        }
        
        /*
         Trying to find lproj resource first in user preferred locale, then system-wide current locale, and finally "Base"
         */
        let bundle: Bundle
        if let path = resourcePath(for: Locale._userPreferred) {
            bundle = Bundle(path: path)!
        } else if let path = resourcePath(for: Locale.current) {
            bundle = Bundle(path: path)!
        } else if let path = self.path(forResource: LocaleManager.base, ofType: "lproj") {
            bundle = Bundle(path: path)!
        } else {
            if let value = value, !value.isEmpty {
                return value
            } else {
                bundle = self
            }
        }
        return bundle.mn_custom_localizedString(forKey: key, value: value, table: tableName)
    }
}

public extension Locale {
    /**
     Caching prefered local to speed up as this method is called frequently in swizzled method.
     Must be set to nil when `AppleLanguages` has changed.
    */
    fileprivate static var cachePreffered: Locale?
    
    fileprivate static var _userPreferred: Locale {
        if let cachePreffered = cachePreffered {
            return cachePreffered
        }
        
        cachePreffered = userPreferred
        return cachePreffered!
    }
    
    fileprivate static var baseLocale: Locale {
        let base = Locale.preferredLanguages.first(where: { $0 != LocaleManager.base }) ?? "en_US"
        return Locale.init(identifier: base)
    }
    
    /**
     Locale selected by user.
     */
    static var userPreferred: Locale {
        let preffered = Locale.preferredLanguages.first.map(Locale.init(identifier:)) ?? Locale.current
        let localizations = AirBundle.localizations.map( { $0.replacingOccurrences(of: "-", with: "_") } )
        let preferredId = preffered.identifier.replacingOccurrences(of: "-", with: "_")
        return localizations.contains(preferredId) ? preffered : baseLocale
    }
    
    /**
     Checking the locale writing direction is right to left.
     */
    var isRTL: Bool {
        return Locale.characterDirection(forLanguage: self.languageCode!) == .rightToLeft
    }
}

public extension NSLocale {
    /**
     Locale selected by user.
     */
    @objc class var userPreferred: Locale {
        return Locale.userPreferred
    }
    
    /**
     Checking the locale writing direction is right to left.
     */
    @objc var isRTL: Bool {
        return (self as Locale).isRTL
    }
}

public extension NSNumber {
    /**
     Returns localized formatted number with maximum fraction digit according to `precision`.
     
     - Parameter precision: The maximum number of digits after the decimal separator allowed.
     - Parameter style: The number style.
     */
    @objc func localized(precision: Int = 0, style: NumberFormatter.Style = .decimal) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = precision
        formatter.numberStyle = style
        formatter.locale = Locale.userPreferred
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = "."
        return formatter.string(from: self)!
    }
}

public extension String {
    /**
     Returns a String object initialized by using a given format string as a template into which
     the remaining argument values are substituted according to user preferred locale information.
     */
    func localizedFormat(_ args: CVarArg...) -> String {
        if args.isEmpty {
            return self
        }
        return String(format: self, locale: Locale.userPreferred, arguments: args)
    }
}

internal extension NSObject {
    @discardableResult
    class func swizzleMethod(_ selector: Selector, with withSelector: Selector) -> Bool {
        
        var originalMethod: Method?
        var swizzledMethod: Method?
        
        originalMethod = class_getInstanceMethod(self, selector)
        swizzledMethod = class_getInstanceMethod(self, withSelector)
        
        if (originalMethod != nil && swizzledMethod != nil) {
            if class_addMethod(self, selector, method_getImplementation(swizzledMethod!), method_getTypeEncoding(swizzledMethod!)) {
                class_replaceMethod(self, withSelector, method_getImplementation(originalMethod!), method_getTypeEncoding(originalMethod!))
            } else {
                method_exchangeImplementations(originalMethod!, swizzledMethod!)
            }
            return true
        }
        return false
    }
    
    @discardableResult
    class func swizzleStaticMethod(_ selector: Selector, with withSelector: Selector) -> Bool {
        
        var originalMethod: Method?
        var swizzledMethod: Method?
        
        originalMethod = class_getClassMethod(self, selector)
        swizzledMethod = class_getClassMethod(self, withSelector)
        
        if (originalMethod != nil && swizzledMethod != nil) {
            if class_addMethod(self, selector, method_getImplementation(swizzledMethod!), method_getTypeEncoding(swizzledMethod!)) {
                class_replaceMethod(self, withSelector, method_getImplementation(originalMethod!), method_getTypeEncoding(originalMethod!))
            } else {
                method_exchangeImplementations(originalMethod!, swizzledMethod!)
            }
            return true
        }
        return false
    }
}
