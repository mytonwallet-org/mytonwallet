import Foundation
import XCTest
@testable import WalletContext

final class CachedUserDefaultTests: XCTestCase {
    func testBooleanCacheMatchesDefaultsCoercionAndRemoval() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let cached = CachedUserDefault<Bool>(key: "value", defaults: defaults)
        XCTAssertFalse(cached.value)
        for value: Any in [true, false, 1, 0, "YES", "NO", "1", "0", "invalid"] {
            defaults.set(value, forKey: "value")
            XCTAssertEqual(cached.value, defaults.bool(forKey: "value"))
        }
        defaults.removeObject(forKey: "value")
        XCTAssertFalse(cached.value)
    }

    func testReadsInitialValueWithoutReadingDefaultsAgain() throws {
        let defaults = try XCTUnwrap(ReadCountingDefaults(suiteName: UUID().uuidString))
        defaults.set("initial", forKey: "value")
        defer { defaults.removeObject(forKey: "value") }
        let cached = CachedUserDefault(key: "value", defaultValue: "fallback", defaults: defaults) {
            $0 as? String ?? "fallback"
        }
        let reads = defaults.readCount

        for _ in 0..<1_000 {
            XCTAssertEqual(cached.value, "initial")
        }
        XCTAssertEqual(defaults.readCount, reads)
    }

    func testDirectWritesAndRemovalUpdateBeforeTheNextRead() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let cached = CachedUserDefault(key: "value", defaultValue: true, defaults: defaults) {
            ($0 as? NSNumber)?.boolValue ?? true
        }
        XCTAssertTrue(cached.value)

        defaults.set(false, forKey: "value")
        XCTAssertFalse(cached.value)
        defaults.set(true, forKey: "value")
        XCTAssertTrue(cached.value)
        defaults.removeObject(forKey: "value")
        XCTAssertTrue(cached.value)
    }

    func testBackgroundWritesAreVisibleToConcurrentReaders() async throws {
        let defaults = try XCTUnwrap(ReadCountingDefaults(suiteName: UUID().uuidString))
        let cached = CachedUserDefault(key: "value", defaultValue: "fallback", defaults: defaults) {
            $0 as? String ?? "fallback"
        }
        defer { defaults.removeObject(forKey: "value") }

        await Task.detached { @Sendable [defaults] in
            defaults.set("updated", forKey: "value")
        }.value
        let values = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for _ in 0..<100 {
                group.addTask { cached.value }
            }
            var values: [String] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(values, Array(repeating: "updated", count: 100))
    }

    func testUnrelatedDefaultsChangesDoNotDecodeAgain() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let decodes = UnfairLock(initialState: 0)
        let cached = CachedUserDefault(key: "value", defaultValue: false, defaults: defaults) {
            decodes.withLock { $0 += 1 }
            return ($0 as? NSNumber)?.boolValue ?? false
        }
        let initialDecodes = decodes.withLock { $0 }
        defaults.set(true, forKey: "unrelated")
        defaults.removeObject(forKey: "unrelated")

        XCTAssertFalse(cached.value)
        XCTAssertEqual(decodes.withLock { $0 }, initialDecodes)
    }

    func testCacheCanBeReleasedBeforeFurtherWrites() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        var cached: CachedUserDefault<Bool>? = CachedUserDefault(key: "value", defaultValue: false, defaults: defaults) {
            ($0 as? NSNumber)?.boolValue ?? false
        }
        weak let weakCache = cached
        cached = nil
        XCTAssertNil(weakCache)

        defaults.set(true, forKey: "value")
        defaults.removeObject(forKey: "value")
    }
}

private final class ReadCountingDefaults: UserDefaults, @unchecked Sendable {
    private let reads = UnfairLock(initialState: 0)
    var readCount: Int { reads.withLock { $0 } }

    override func object(forKey defaultName: String) -> Any? {
        reads.withLock { $0 += 1 }
        return super.object(forKey: defaultName)
    }
}
