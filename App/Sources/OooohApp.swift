import Design
import SwiftUI

@main
struct OooohApp: App {
  var body: some Scene {
    WindowGroup {
      RootView()
        .preferredColorScheme(colorScheme)
    }
  }

  /// Debug builds take `-ui-color-scheme light|dark` so UI tests can screenshot one appearance.
  private var colorScheme: ColorScheme? {
    #if DEBUG
      switch UserDefaults.standard.string(forKey: "ui-color-scheme") {
      case "light": return .light
      case "dark": return .dark
      default: break
      }
    #endif
    return nil
  }
}
