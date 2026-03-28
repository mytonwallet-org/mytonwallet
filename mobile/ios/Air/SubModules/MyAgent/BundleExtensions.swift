#if !SWIFT_PACKAGE
  import Foundation

  private final class BundleToken {
      static let bundle: Bundle = {
          let bundleName = "MyAgentResources"

          let candidates = [
              // Pod bundle in app
              Bundle.main.resourceURL,
              // Pod bundle in framework
              Bundle(for: BundleToken.self).resourceURL,
          ]

          for candidate in candidates {
              let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
              if let bundlePath, let bundle = Bundle(path: bundlePath.path) {
                  return bundle
              }
          }

          return Bundle(for: BundleToken.self)
      }()
  }

  extension Bundle {
      /// CocoaPods equivalent of SPM's auto-generated `Bundle.module`.
      static var module: Bundle { BundleToken.bundle }
  }
  #endif