import CryptoKit
import Foundation

actor AnimationFrameCacheStore {
    private final class WeakAssetBox {
        weak var asset: AnimationFrameCacheAsset?

        init(asset: AnimationFrameCacheAsset? = nil) {
            self.asset = asset
        }
    }

    private struct BuildState {
        let generation: UInt64
        let task: Task<AnimationFrameCacheAsset?, Never>
    }

    struct Request: Sendable {
        let sourceIdentifier: String
        let rendererCacheKey: String
        let data: Data
        let width: Int
        let height: Int
    }

    struct ArtifactKey: Hashable, Sendable {
        let sourceIdentifier: String
        let width: Int
        let height: Int
    }

    static let shared = AnimationFrameCacheStore()

    private var options = LottieAnimationCacheOptions()
    private var generation: UInt64 = 0
    private var didPrepareFilesystem = false
    private var assets: [ArtifactKey: WeakAssetBox] = [:]
    private var buildTasks: [ArtifactKey: BuildState] = [:]

    static func makeRequest(
        cacheKey: String,
        data: Data,
        width: Int,
        height: Int
    ) -> Request {
        let stableKey: String
        if cacheKey.isEmpty {
            let digest = SHA256.hash(data: data)
            stableKey = digest.map { String(format: "%02x", $0) }.joined()
        } else {
            stableKey = cacheKey
        }

        return Request(
            sourceIdentifier: stableKey,
            rendererCacheKey: stableKey,
            data: data,
            width: width,
            height: height
        )
    }

    func setOptions(_ options: LottieAnimationCacheOptions) {
        guard self.options != options else {
            return
        }

        let formatVersionChanged = self.options.formatVersion != options.formatVersion
        self.options = options

        if formatVersionChanged {
            self.invalidateArtifacts()
        }

        self.didPrepareFilesystem = false
        self.prepareFilesystemIfNeeded()
        self.pruneDiskIfNeeded()
    }

    func currentOptions() -> LottieAnimationCacheOptions {
        self.options
    }

    func cachedAsset(for request: Request) -> AnimationFrameCacheAsset? {
        self.prepareFilesystemIfNeeded()

        let key = ArtifactKey(request: request)
        let url = self.cacheURL(for: key)

        if let asset = self.assets[key]?.asset {
            Self.touchFile(at: url)
            return asset
        }

        guard let asset = AnimationFrameCacheAsset.load(url: url) else {
            self.assets[key] = nil
            return nil
        }
        self.assets[key] = WeakAssetBox(asset: asset)
        Self.touchFile(at: url)
        return asset
    }

    func buildAssetIfNeeded(
        request: Request,
        info: LottieAnimationInfo
    ) async -> AnimationFrameCacheAsset? {
        self.prepareFilesystemIfNeeded()

        let key = ArtifactKey(request: request)
        if let asset = self.assets[key]?.asset {
            return asset
        }

        let outputURL = self.cacheURL(for: key)

        if let asset = AnimationFrameCacheAsset.load(url: outputURL) {
            self.assets[key] = WeakAssetBox(asset: asset)
            Self.touchFile(at: outputURL)
            return asset
        }

        if let buildState = self.buildTasks[key] {
            return await buildState.task.value
        }

        let buildGeneration = self.generation
        let buildTask = Task.detached(priority: .userInitiated) {
            await AnimationFrameCacheBuilder.buildAsset(
                outputURL: outputURL,
                info: info,
                width: request.width,
                height: request.height,
                data: request.data,
                cacheKey: request.rendererCacheKey
            )
        }
        self.buildTasks[key] = BuildState(generation: buildGeneration, task: buildTask)

        let asset = await buildTask.value
        if self.buildTasks[key]?.generation == buildGeneration {
            self.buildTasks[key] = nil
        }
        guard buildGeneration == self.generation else {
            let hasReplacementForCurrentGeneration =
                self.buildTasks[key]?.generation == self.generation ||
                self.assets[key]?.asset != nil
            if !hasReplacementForCurrentGeneration {
                try? FileManager.default.removeItem(at: outputURL)
            }
            return nil
        }
        if let asset {
            self.assets[key] = WeakAssetBox(asset: asset)
            Self.touchFile(at: outputURL)
            self.pruneDiskIfNeeded()
        }
        return asset
    }

    func storageSizeBytes(for request: Request) -> Int64 {
        self.prepareFilesystemIfNeeded()
        return Self.fileSize(at: self.cacheURL(for: ArtifactKey(request: request)))
    }

    func clearAll() {
        self.invalidateArtifacts()

        let rootDirectory = Self.cacheRootDirectory()
        try? FileManager.default.removeItem(at: rootDirectory)
        self.didPrepareFilesystem = false
        self.prepareFilesystemIfNeeded()
    }

    private func prepareFilesystemIfNeeded() {
        guard !self.didPrepareFilesystem else {
            return
        }

        let fileManager = FileManager.default
        let rootDirectory = Self.cacheRootDirectory()
        let currentDirectoryName = self.currentCacheDirectory().lastPathComponent

        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        if let existingEntries = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for entry in existingEntries where entry.lastPathComponent != currentDirectoryName {
                try? fileManager.removeItem(at: entry)
            }
        }

        try? fileManager.createDirectory(at: self.currentCacheDirectory(), withIntermediateDirectories: true)
        self.didPrepareFilesystem = true
    }

    private func currentCacheDirectory() -> URL {
        Self.cacheRootDirectory().appendingPathComponent("v\(self.options.formatVersion)", isDirectory: true)
    }

    private func cacheURL(for key: ArtifactKey) -> URL {
        self.currentCacheDirectory()
            .appendingPathComponent(Self.fileName(for: key))
            .appendingPathExtension("lottieframes")
    }

    private func pruneDiskIfNeeded() {
        guard self.options.diskLimitBytes > 0 else {
            return
        }

        let directory = self.currentCacheDirectory()
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        struct Entry {
            let url: URL
            let size: Int64
            let date: Date
        }

        let protectedURLs = Set(
            self.buildTasks.keys.map { self.cacheURL(for: $0) } +
            self.assets.compactMap { key, box in
                guard box.asset != nil else {
                    return nil
                }
                return self.cacheURL(for: key)
            }
        )

        var entries: [Entry] = []
        entries.reserveCapacity(fileURLs.count)

        for fileURL in fileURLs {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys), values.isRegularFile == true else {
                continue
            }
            entries.append(
                Entry(
                    url: fileURL,
                    size: Int64(values.fileSize ?? 0),
                    date: values.contentModificationDate ?? .distantPast
                )
            )
        }

        var totalSize = entries.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > self.options.diskLimitBytes else {
            return
        }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard totalSize > self.options.diskLimitBytes else {
                break
            }
            guard !protectedURLs.contains(entry.url) else {
                continue
            }
            try? fileManager.removeItem(at: entry.url)
            totalSize -= entry.size
        }
    }

    private func invalidateArtifacts() {
        self.generation &+= 1
        for buildState in self.buildTasks.values {
            buildState.task.cancel()
        }
        self.assets.removeAll()
        self.buildTasks.removeAll()
    }

    private static func cacheRootDirectory() -> URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory.appendingPathComponent("LottieKit/LottieFrameCache", isDirectory: true)
    }

    private static func fileName(for key: ArtifactKey) -> String {
        let descriptor = "\(key.sourceIdentifier)|\(key.width)x\(key.height)|argb-v1"
        let digest = SHA256.hash(data: Data(descriptor.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static func touchFile(at url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
}

private extension AnimationFrameCacheStore.ArtifactKey {
    init(request: AnimationFrameCacheStore.Request) {
        self.init(
            sourceIdentifier: request.sourceIdentifier,
            width: request.width,
            height: request.height
        )
    }
}
