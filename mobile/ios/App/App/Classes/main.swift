import UIKit
import Darwin
import WalletContext

prepareMacMetalCacheForSuspension()

UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    NSStringFromClass(MyTonWalletApp.self),
    NSStringFromClass(AppDelegate.self)
)

private func prepareMacMetalCacheForSuspension() {
    guard ProcessInfo.processInfo.isiOSAppOnMac,
          ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27,
          let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

    let length = confstr(_CS_DARWIN_USER_CACHE_DIR, nil, 0)
    guard length > 0 else { return }
    var buffer = [CChar](repeating: 0, count: length)
    guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, length) == length else { return }
    let lockURL = URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
        .appendingPathComponent(bundleIdentifier, isDirectory: true)
        .appendingPathComponent("com.apple.metal/archiveUsage.db/lock.mdb")

    do {
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Prepare the file before Metal first uses it, including rendering after background entry.
        // Never open/close an existing file: doing so could release Metal's process-owned POSIX lock.
        let descriptor = open(lockURL.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, S_IRUSR | S_IWUSR)
        if descriptor >= 0 {
            close(descriptor)
        } else if errno != EEXIST {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        // macOS 27 omits this undocumented RunningBoard marker on Metal's LMDB cache lock, causing 0xdead10cc at suspension.
        // Match Metal's other cache files; never exempt wallet databases or interrupt their writes.
        // Preserve any marker already supplied by the system.
        var canSuspend: UInt8 = 1
        let result = setxattr(lockURL.path, "com.apple.runningboard.can-suspend-locked", &canSuspend, 1, 0, XATTR_CREATE)
        guard result == 0 || errno == EEXIST else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    } catch {
        Log("MacMetalCache").error("Failed to prepare Mac Metal cache for suspension: \(error, .public)")
    }
}
