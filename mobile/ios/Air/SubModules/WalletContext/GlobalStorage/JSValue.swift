
import Foundation
import WebKit


public final class JSValue {
    
    private var _value: UnfairLock<Value>
    
    public init(_ object: Any?) {
        self._value = .init(uncheckedState: Value(object))
    }
    
    public var value: Any? {
        _value.withLock { $0._value }
    }
    
    public subscript(_ keyPath: String) -> Any? {
        _value.withLock { $0[keyPath] }
    }
    
    public func update(_ f: (inout Value) -> ()) {
        _value.withLock { f(&$0) }
    }
}

extension JSValue: CustomStringConvertible {
    public var description: String {
        if let value {
            "JSValue<\(String(describing: value))>"
        } else {
            "JSValue<nil>"
        }
    }
}


extension JSValue {
    public struct Value {
        
        var _value: Any?
        
        init(_ _value: Any?) {
            self._value = _value
        }
        
        public subscript(_ keyPath: String) -> Any? {
            get {
                let keyPath = keyPath.split(separator: ".")
                return self[keyPath]
            }
            set {
                let keyPath = keyPath.split(separator: ".")
                self[keyPath] = newValue
            }
        }
        
        public subscript<S: StringProtocol>(_ keyPath: [S]) -> Any? {
            get {
                var keyPath = keyPath
                var v = _value
                while let key = keyPath.first {
                    if let dict = v as? [String: Any], let child = dict[String(key)] {
                        v = child
                        keyPath = Array(keyPath.dropFirst())
                    } else {
                        return nil
                    }
                }
                return v
            }
            set {
                if let key = keyPath.first {
                    var dict = _value as? [String: Any] ?? [:]
                    let child = dict[String(key)]
                    var childValue = Value(child)
                    childValue[Array(keyPath.dropFirst())] = newValue
                    dict[String(key)] = childValue._value
                    _value = dict
                } else {
                    _value = newValue
                }
            }
        }
    }
}
