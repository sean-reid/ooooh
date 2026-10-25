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

  /// Debug builds take `-ui-color-scheme light` so UI tests can screenshot both appearances.
  private var colorScheme: ColorScheme {
    #if DEBUG
      if UserDefaults.standard.string(forKey: "ui-color-scheme") == "light" { return .light }
    #endif
    return .dark
  }
}
