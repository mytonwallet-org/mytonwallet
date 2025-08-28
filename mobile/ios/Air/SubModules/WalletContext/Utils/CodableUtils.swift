
import Foundation

extension KeyedDecodingContainer {
    
    public func decodeWithDefault<T>(_ type: T.Type, forKey key: KeyedDecodingContainer<K>.Key, default: T, assert assertEnabled: Bool = true) -> T where T : Decodable {
        do {
            return try self.decodeIfPresent(type, forKey: key) ?? `default`
        } catch {
            assert(!assertEnabled, "[debug] decodeWithDefault error: \(error)")
            return `default`
        }
    }
    
    public func decodeOptional<T>(_ type: T.Type, forKey key: KeyedDecodingContainer<K>.Key, assert assertEnabled: Bool = true) -> T? where T : Decodable {
        do {
            return try self.decodeIfPresent(type, forKey: key)
        } catch {
            assert(!assertEnabled, "[debug] decodeOptional error: \(error)")
            return nil
        }
    }
}
