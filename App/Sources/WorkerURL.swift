import Foundation

/// The Worker base URL, from the OOOOH_WORKER_URL build setting through Info.plist.
enum WorkerURL {
  static var fromBundle: URL? {
    guard let text = Bundle.main.object(forInfoDictionaryKey: "OoooohWorkerURL") as? String,
      !text.isEmpty
    else { return nil }
    return URL(string: text)
  }
}
