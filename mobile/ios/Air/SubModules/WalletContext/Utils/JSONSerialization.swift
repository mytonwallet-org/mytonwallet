
import Foundation


public extension JSONSerialization {
    
    static func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
        let value = try JSONDecoder().decode(T.self, from: data)
        return value
    }
    
    static func encode<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return object
    }
    
    static func jsonObject(withString: String) throws -> Any {
        let data = withString.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

public extension JSONDecoder {
    
    func decode<T: Decodable>(_ type: T.Type, fromString: String) throws -> T {
        let data = fromString.data(using: .utf8)!
        return try decode(T.self, from: data)
    }
}

public extension Encodable {
    func json() throws -> Any {
        try JSONSerialization.encode(self)
    }
}

public extension Encodable {
    func jsonString() -> String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)!
    }
    func jsonStringPretty() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8)!
    }
#if DEBUG
    func printJsonString() {
        print(jsonString())
    }
    func printJsonStringPretty() {
        print(jsonStringPretty())
    }
#endif
}

//public extension Decodable {
//    init(json: Any) throws {
//        self = try JSONSerialization.decode(Self.self, from: json)
//    }
//}


@dynamicMemberLookup
public class Json {

    private var value: Value
    
    public var object: Any? {
        switch value {
        case .dict(let dictionary):
            return dictionary
        case .arr(let array):
            return array
        case .leaf(let any):
            return any
        case .error:
            return nil
        }
    }
    
    public enum Value {
        case dict([String: Any])
        case arr([Any])
        case leaf(Any)
        case error
    }
    
    private init(value: Value) {
        self.value = value
    }
    
    public init(_ object: Any?) {
        if let dict = object as? [String: Any] {
            value = .dict(dict)
        } else if let arr = object as? [Any] {
            value = .arr(arr)
        } else {
            value = .leaf(object as Any)
        }
    }
    
    public subscript(dynamicMember member: String) -> Json {
        if case .dict(let dict) = value {
            return Json(dict[member])
        }
        return Json(value: .error)
    }
    
    public func string() -> String? {
        if case .leaf(let any) = value {
            return any as? String
        }
        return nil
    }
    
    public func dict() -> [String: Json]? {
        if case .dict(let dict) = value {
            return dict.mapValues { Json($0) }
        }
        return nil
    }
    
    public func `as`<T>(_ type: T.Type) -> T? {
        object as? T
    }
}
