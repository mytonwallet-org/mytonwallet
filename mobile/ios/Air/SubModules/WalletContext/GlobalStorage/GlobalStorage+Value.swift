import Foundation

extension GlobalStorage {
    public struct Value {
        var rawValue: Any?

        init(_ rawValue: Any?) {
            self.rawValue = rawValue
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
                var value = rawValue
                while let key = keyPath.first {
                    if let dict = value as? [String: Any], let child = dict[String(key)] {
                        value = child
                        keyPath = Array(keyPath.dropFirst())
                    } else {
                        return nil
                    }
                }
                return value
            }
            set {
                if let key = keyPath.first {
                    var dict = rawValue as? [String: Any] ?? [:]
                    let child = dict[String(key)]
                    var childValue = Value(child)
                    childValue[Array(keyPath.dropFirst())] = newValue
                    dict[String(key)] = childValue.rawValue
                    rawValue = dict
                } else {
                    rawValue = newValue
                }
            }
        }
    }
}
