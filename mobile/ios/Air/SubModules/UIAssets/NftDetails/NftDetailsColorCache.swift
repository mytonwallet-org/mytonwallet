import UIKit

/// Thread-safe `String` → `UIColor` store with compact binary persistence under Caches.
/// - Format: magic `NDCC`, `UInt8` version, `UInt32` LE entry count, then per key: `UInt32` LE UTF-8 length, UTF-8 bytes, 4×`UInt8` RGBA (sRGB).
final class NftDetailsColorCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: UIColor] = [:]
    private var diskLoadState: DiskLoadState = .pending

    private enum DiskLoadState { case pending, loading, done }
    private var dirty = false

    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "NftDetails.colorCache.io")
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.5

    private static let magic: [UInt8] = [0x4E, 0x44, 0x43, 0x43] // "(N)ft(D)etails(C)olor(C)ache"
    private static let fileVersion: UInt8 = 1

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base.appendingPathComponent("nft_details_color_cache.bin", isDirectory: false)
        }
    }

    deinit {
        pendingSaveWorkItem?.cancel()
        let url = fileURL
        ioQueue.sync {
            lock.lock()
            let wasDirty = dirty
            let snapshot = storage
            lock.unlock()
            guard wasDirty else { return }
            let data = Self.encode(snapshot)
            _ = Self.atomicWrite(data, to: url)
        }
    }

    func color(forKey key: String) -> UIColor? {
        ensureLoadedFromDisk()
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func setColor(_ color: UIColor, forKey key: String) {
        ensureLoadedFromDisk()
        lock.lock()
        storage[key] = color
        dirty = true
        lock.unlock()

        ioQueue.async { [weak self] in
            self?.scheduleDebouncedSave()
        }
    }

    func saveIfNeeded() {
        ensureLoadedFromDisk()
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.pendingSaveWorkItem?.cancel()
            self.pendingSaveWorkItem = nil
            self.performSaveSnapshot()
        }
    }

    func flush() {
        ensureLoadedFromDisk()
        ioQueue.sync { [weak self] in
            guard let self else { return }
            self.pendingSaveWorkItem?.cancel()
            self.pendingSaveWorkItem = nil
            self.performSaveSnapshot()
        }
    }

    /// Removes all entries from memory and deletes the on-disk file.
    func clearCache() {
        lock.lock()
        storage.removeAll()
        dirty = false
        diskLoadState = .done   // prevent a stale file from being reloaded
        lock.unlock()

        ioQueue.async { [weak self] in
            guard let self else { return }
            self.pendingSaveWorkItem?.cancel()
            self.pendingSaveWorkItem = nil
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }

    #if DEBUG
    func debugStats() -> (keyCount: Int, fileURL: URL) {
        ensureLoadedFromDisk()
        lock.lock()
        let count = storage.count
        lock.unlock()
        return (count, fileURL)
    }
    #endif

    private func ensureLoadedFromDisk() {
        lock.lock()
        switch diskLoadState {
        case .done:
            lock.unlock()
            return
        case .loading:
            // Another thread is already loading; wait for it to finish.
            lock.unlock()
            lock.lock()
            lock.unlock()
            return
        case .pending:
            diskLoadState = .loading
            lock.unlock()
        }

        // Only one thread reaches here.
        let path = fileURL.path
        var loaded: [String: UIColor] = [:]
        if FileManager.default.fileExists(atPath: path),
           let data = try? Data(contentsOf: fileURL),
           let decoded = Self.decode(data) {
            loaded = decoded
        }

        lock.lock()
        for (k, v) in loaded where storage[k] == nil {
            storage[k] = v
        }
        diskLoadState = .done
        lock.unlock()
    }

    private func scheduleDebouncedSave() {
        pendingSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performSaveSnapshot()
        }
        pendingSaveWorkItem = work
        ioQueue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func performSaveSnapshot() {
        lock.lock()
        guard dirty else {
            lock.unlock()
            return
        }
        let snapshot = storage
        dirty = false
        lock.unlock()

        let data = Self.encode(snapshot)
        if !Self.atomicWrite(data, to: fileURL) {
            lock.lock()
            dirty = true
            lock.unlock()
        }
    }

    private static func rgbaBytes(for color: UIColor) -> [UInt8]? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let cg = color.cgColor.converted(to: srgb, intent: .relativeColorimetric, options: nil),
              let components = cg.components else {
            return nil
        }
        let n = cg.numberOfComponents
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        switch n {
        case 2:
            r = components[0]
            g = components[0]
            b = components[0]
            a = components[1]
        case 4:
            r = components[0]
            g = components[1]
            b = components[2]
            a = components[3]
        case 1:
            r = components[0]
            g = components[0]
            b = components[0]
            a = 1
        default:
            return nil
        }
        return [
            UInt8(clamping: Int((r * 255).rounded())),
            UInt8(clamping: Int((g * 255).rounded())),
            UInt8(clamping: Int((b * 255).rounded())),
            UInt8(clamping: Int((a * 255).rounded())),
        ]
    }

    private static func encode(_ map: [String: UIColor]) -> Data {
        let entries: [(String, [UInt8])] = map.compactMap { key, color in
            guard let rgba = rgbaBytes(for: color) else { return nil }
            return (key, rgba)
        }
        .sorted { $0.0 < $1.0 }

        var data = Data()
        data.append(contentsOf: magic)
        data.append(fileVersion)
        let countLE = UInt32(entries.count).littleEndian
        withUnsafeBytes(of: countLE) { data.append(contentsOf: $0) }
        for (key, rgba) in entries {
            let keyUTF8 = Array(key.utf8)
            let lenLE = UInt32(keyUTF8.count).littleEndian
            withUnsafeBytes(of: lenLE) { data.append(contentsOf: $0) }
            data.append(contentsOf: keyUTF8)
            data.append(contentsOf: rgba)
        }
        return data
    }

    private static func decode(_ data: Data) -> [String: UIColor]? {
        guard data.count >= magic.count + MemoryLayout<UInt8>.size + MemoryLayout<UInt32>.size else { return nil }
        guard Array(data.prefix(magic.count)) == magic else { return nil }
        var offset = magic.count
        guard data[offset] == fileVersion else { return nil }
        offset += 1
        guard offset + MemoryLayout<UInt32>.size <= data.count else { return nil }
        let count: UInt32 = data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
        offset += MemoryLayout<UInt32>.size
        guard count < 10_000_000 else { return nil }

        var result: [String: UIColor] = [:]
        result.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard offset + MemoryLayout<UInt32>.size <= data.count else { return nil }
            let keyLen32: UInt32 = data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
            }
            offset += MemoryLayout<UInt32>.size
            let keyLen = Int(keyLen32)
            guard keyLen >= 0, offset + keyLen + 4 <= data.count else { return nil }
            guard let key = String(data: data.subdata(in: offset..<(offset + keyLen)), encoding: .utf8) else { return nil }
            offset += keyLen
            let r = data[offset]
            let g = data[offset + 1]
            let b = data[offset + 2]
            let a = data[offset + 3]
            offset += 4
            result[key] = UIColor(
                red: CGFloat(r) / 255,
                green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255,
                alpha: CGFloat(a) / 255
            )
        }
        guard offset == data.count else { return nil }
        return result
    }

    private static func atomicWrite(_ data: Data, to dst: URL) -> Bool {
        let dir = dst.deletingLastPathComponent()
        let temp = dir.appendingPathComponent("nft_details_color_cache.\(UUID().uuidString).tmp", isDirectory: false)
        let fm = FileManager.default
        do {
            try data.write(to: temp)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.moveItem(at: temp, to: dst)
            return true
        } catch {
            try? fm.removeItem(at: temp)
            return false
        }
    }
}
