import Foundation

/// The Worker base URL, from the OOOOH_WORKER_URL build setting through Info.plist.
/// Debug builds take `-worker-url <url>` on the command line instead.
enum WorkerURL {
  static var fromBundle: URL? {
    #if DEBUG
      if let override = UserDefaults.standard.string(forKey: "worker-url"), !override.isEmpty {
        return URL(string: override)
      }
    #endif
    guard let text = Bundle.main.object(forInfoDictionaryKey: "OoooohWorkerURL") as? String,
      !text.isEmpty
    else { return nil }
    return URL(string: text)
  }
}
