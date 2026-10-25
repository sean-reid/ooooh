import SwiftUI

/// Night sky. One accent, nothing else saturated.
public enum Palette {
  public static let sky = Color(red: 0.047, green: 0.051, blue: 0.067)
  public static let skyRaised = Color(red: 0.086, green: 0.090, blue: 0.110)
  public static let amber = Color(red: 0.980, green: 0.741, blue: 0.345)
  public static let amberDim = Color(red: 0.980, green: 0.741, blue: 0.345).opacity(0.35)
  public static let ink = Color(red: 0.925, green: 0.914, blue: 0.886)
  public static let inkDim = Color(red: 0.925, green: 0.914, blue: 0.886).opacity(0.55)
}
