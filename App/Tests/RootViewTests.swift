import Design
import Foundation
import Notes
import Persistence
import Session
import SnapshotTesting
import SwiftUI
import TestSupport
import Testing
import Transcription
import UIKit

@testable import ooooh

/// The real root view over the shared host, in a window, read as pixels: which screen the body
/// picks for each stage of the host's controller, and what the Debug demo starts. An orb at rest
/// settles on its first frame, so a screen drawn twice is the same picture; the session screen,
/// whose orb moves, is known by its End button. The host is lent a microphone that needs no
/// permissions and handed back after.
@MainActor
@Suite(.serialized) struct RootViewTests {
  static let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
  let shortFixture = try! Bundle.tests.fixtureURL("short.json")
  let defaultsKeys = ["onboardingComplete", "onboarding", "demo", "demo-speed"]

  /// The mounted root view, drawn on demand.
  @MainActor struct Screen {
    let window: UIWindow
    let hosting: UIHostingController<AnyView>

    var presentsASheet: Bool { hosting.presentedViewController != nil }

    func picture() -> UIImage { RootViewTests.draw(hosting.view) }

    /// True when `part` is drawn somewhere on the screen, in full.
    func shows(_ part: UIImage) -> Bool { RootViewTests.contains(picture(), part) }

    /// True when the whole screen is `expected`, within the snapshot tolerance.
    func matches(_ expected: UIImage) -> Bool {
      Snapshotting<UIImage, UIImage>.pixels.diffing.diff(expected, picture()) == nil
    }
  }

  /// Lends the host `environment`, sets the launch defaults, mounts the root view, and puts
  /// everything back when `body` returns.
  func mounted<T>(
    _ environment: @escaping @MainActor () -> SessionController.Environment,
    onboarded: Bool = true, demo: Bool = false,
    before: (SessionHost) async -> Void = { _ in },
    body: (SessionHost, Screen) async throws -> T
  ) async rethrows -> T {
    let defaults = UserDefaults.standard
    let saved = defaultsKeys.map { ($0, defaults.object(forKey: $0)) }
    defaults.set(onboarded, forKey: "onboardingComplete")
    defaults.removeObject(forKey: "onboarding")
    defaults.set(demo, forKey: "demo")
    defaults.set("16", forKey: "demo-speed")
    let host = SessionHost.shared
    let hostEnvironment = host.environment
    let onboardedBefore = host.onboarded
    host.environment = environment
    host.onboarded = { onboarded }
    host.reset()
    await before(host)
    let (window, hosting) = Self.mount(RootView(launch: LaunchWork()))
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      host.environment = hostEnvironment
      host.onboarded = onboardedBefore
      host.reset()
      for (key, value) in saved {
        if let value {
          defaults.set(value, forKey: key)
        } else {
          defaults.removeObject(forKey: key)
        }
      }
    }
    return try await body(host, Screen(window: window, hosting: hosting))
  }

  func microphoneEnvironment() -> SessionController.Environment {
    downloadEnvironment(HandFedMicrophone())
  }

  /// Polls four times a second, since each look draws the screen.
  func eventually(
    _ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition(), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(250))
    }
    if !condition() {
      Issue.record("the screen did not show it within 10 s", sourceLocation: sourceLocation)
    }
  }

  @Test func onboardingShowsUntilItIsComplete() async {
    await mounted(microphoneEnvironment, onboarded: false) { _, screen in
      let onboarding = await picture(ofScreen: OnboardingFlow(start: { nil }, done: {}))
      await eventually { screen.matches(onboarding) }
      #expect(screen.matches(onboarding))
      #expect(!screen.shows(startButton))
    }
  }

  @Test func idleShowsHomeWithTheStartButton() async {
    await mounted(microphoneEnvironment) { host, screen in
      let start = startButton
      await eventually { screen.shows(start) }
      #expect(host.controller.stage == .idle)
      #expect(screen.shows(start))
      #expect(!screen.shows(failureLine(.unavailable)))
    }
  }

  /// The card lists the store's open threads, three at most, and is gone when there are none.
  @Test func idleShowsTheCarryoverCardOnlyForOpenThreadsInTheStore() async throws {
    let store = try #require(AppStore.shared.current)
    let threads = try await store.openThreads(limit: 3)
    await mounted(microphoneEnvironment) { _, screen in
      let start = startButton
      await eventually { screen.shows(start) }
      if threads.isEmpty {
        try? await Task.sleep(for: .milliseconds(500))
        #expect(!screen.shows(carryoverHeader))
      } else {
        let card = carryoverCard(threads)
        await eventually { screen.shows(card) }
        #expect(screen.shows(card))
      }
    }
  }

  @Test func idleWithOpenThreadsInTheStoreShowsThemOnTheCard() async throws {
    let store = try #require(AppStore.shared.current)
    let suffix = UUID().uuidString.prefix(8)
    let notes = SessionNotes(
      title: "Root view \(suffix)", summary: "Two threads left open.",
      decisions: [],
      openThreads: [
        NoteItem(id: "first-\(suffix)", text: "First thread \(suffix)"),
        NoteItem(id: "second-\(suffix)", text: "Second thread \(suffix)"),
      ])
    let result = await FixtureDriver.run(
      fixture: try DebugHistory.demoFixture(), config: .initial,
      dependencies: .init(
        decisions: SilentDecisionProvider(), compactor: PassthroughCompactor(),
        phraser: TemplatePhraser()))
    let saved = try await store.save(result: result, notes: notes, title: notes.title)
    let threads = try await store.openThreads(limit: 3)
    #expect(threads.map(\.sessionID).contains(saved))

    await mounted(microphoneEnvironment) { _, screen in
      let card = carryoverCard(threads)
      await eventually { screen.shows(card) }
      #expect(screen.shows(startButton))
      #expect(screen.shows(card))
    }
    try await store.delete(session: saved)
  }

  @Test func aRunningSessionShowsTheSessionScreen() async {
    await SessionHost.shared.controller.end()
    await mounted(
      microphoneEnvironment, before: { host in await host.controller.start(.microphone) },
      body: { host, screen in
        #expect(host.controller.stage == .running)
        let end = endButton
        await eventually { screen.shows(end) }
        #expect(screen.shows(end))
        #expect(!screen.shows(startButton))
        await host.controller.end()
      })
  }

  @Test func aSessionEndedWithNotesShowsThemAndOffersNoPaywall() async throws {
    let store = try SessionStore(configuration: .inMemory)
    let withNotes: @MainActor () -> SessionController.Environment = {
      var environment = downloadEnvironment(HandFedMicrophone())
      environment.notesGenerator = SessionControllerTests.CannedNotes()
      environment.store = store
      return environment
    }
    try await mounted(withNotes) { host, screen in
      await eventually { screen.shows(startButton) }
      await host.controller.start(.fixture(shortFixture, speed: .infinity))
      await wait { host.controller.notes == .written(SessionControllerTests.CannedNotes.notes) }
      let editor = try #require(host.controller.editor)
      let notes = await picture(
        ofScreen: EditableNotesView(
          editor: editor, lines: host.controller.lines, onMarkBad: { _, _ in }, onDone: {}))
      await eventually { screen.matches(notes) }
      #expect(screen.matches(notes))
      #expect(!screen.shows(startButton))
      try? await Task.sleep(for: .milliseconds(300))
      #expect(!screen.presentsASheet)
    }
  }

  @Test func aSessionEndedWithoutNotesShowsThePendingScreen() async throws {
    try await mounted(microphoneEnvironment) { host, screen in
      await eventually { screen.shows(startButton) }
      await host.controller.start(.fixture(shortFixture, speed: .infinity))
      await wait { host.controller.stage == .ended }
      #expect(host.controller.notes == .unavailable)
      let result = try #require(host.controller.result)
      let pending = await picture(
        ofScreen: PendingNotesView(
          state: result.state, transcript: result.transcript,
          line: PendingNotesView.line(for: host.controller), lines: host.controller.lines,
          onMarkBad: { _, _ in }, done: {}))
      await eventually { screen.matches(pending) }
      #expect(screen.matches(pending))
    }
  }

  @Test func aSessionThatHeardNothingShowsTheEmptyScreen() async throws {
    let empty = FileManager.default.temporaryDirectory.appending(path: "root-empty-\(UUID()).json")
    try Data(#"{"segments":[]}"#.utf8).write(to: empty)
    await mounted(microphoneEnvironment) { host, screen in
      await eventually { screen.shows(startButton) }
      await host.controller.start(.fixture(empty, speed: .infinity))
      await wait { host.controller.stage == .ended }
      #expect(host.controller.notes == .empty)
      let emptyScreen = await picture(ofScreen: EmptySessionView {})
      await eventually { screen.matches(emptyScreen) }
      #expect(screen.matches(emptyScreen))
    }
  }

  /// The free count the Worker reports goes through `AppBilling`, as the app wires it, and a
  /// spent count opens the paywall sheet over the notes.
  @Test func theLastFreeSessionOffersThePaywallWhenItEnds() async {
    let freeSessions = AppBilling.freeSessions
    let remainingBefore = freeSessions.remaining
    defer {
      freeSessions.record(.free(remaining: remainingBefore ?? 3, promptMinutes: 20))
      Task { await AppBilling.store.refresh() }
    }
    await mounted(microphoneEnvironment) { host, screen in
      await eventually { screen.shows(startButton) }
      freeSessions.record(.refused(reason: "free-exhausted"))
      await host.controller.start(.fixture(shortFixture, speed: .infinity))
      await wait { host.controller.stage == .ended }
      await wait { screen.presentsASheet }
      #expect(screen.presentsASheet)
      #expect(RootView.offersPaywall(AppBilling.store))
      screen.hosting.dismiss(animated: false)
    }
  }

  @Test func aFailedStartShowsHomeWithTheReason() async {
    let missing = shortFixture.deletingLastPathComponent().appending(path: "missing.json")
    await mounted(
      microphoneEnvironment,
      before: { host in await host.controller.start(.fixture(missing, speed: .infinity)) },
      body: { host, screen in
        #expect(host.controller.stage == .failed(.unavailable))
        let line = failureLine(.unavailable)
        await eventually { screen.shows(line) }
        #expect(screen.shows(line))
        #expect(screen.shows(startButton))
      })
  }

  /// `-demo 1` skips onboarding and replays the bundled decision fixture on the host's controller;
  /// End then lands on the pending screen, since the demo has no Worker here.
  @Test func theDemoLaunchArgumentStartsTheFixtureSession() async throws {
    try await mounted(microphoneEnvironment, onboarded: false, demo: true) { host, screen in
      await wait { host.controller.stage == .running }
      await wait { host.controller.level > 0 }
      await wait { host.controller.level == 0 }
      await host.controller.end()
      let result = try #require(host.controller.result)
      #expect(result.transcript.first?.text.hasPrefix("Right, apartments.") == true)
      let pending = await picture(
        ofScreen: PendingNotesView(
          state: result.state, transcript: result.transcript,
          line: PendingNotesView.line(for: host.controller), lines: host.controller.lines,
          onMarkBad: { _, _ in }, done: {}))
      await eventually { screen.matches(pending) }
      #expect(screen.matches(pending))
      #expect(!screen.shows(startButton))
    }
  }

  // MARK: Pictures

  var startButton: UIImage {
    picture(ofPart: Button("Start") {}.buttonStyle(.amber).padding(.horizontal, 32))
  }

  var endButton: UIImage {
    picture(
      ofPart: Button {
      } label: {
        Text("End")
          .font(Typography.body)
          .frame(minWidth: 120, minHeight: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Palette.ink)
      .background(Palette.skyRaised, in: Capsule())
      .padding(.top, 20)
      .padding(.bottom, 12))
  }

  /// The top of the card, the same whatever threads it lists.
  var carryoverHeader: UIImage {
    let card = picture(ofPart: CarryoverCard(threads: [], pick: { _ in }, dismiss: {}))
    let top = CGRect(x: 0, y: 0, width: card.size.width * 2, height: 40 * 2)
    return UIImage(cgImage: card.cgImage!.cropping(to: top)!)
  }

  func carryoverCard(_ threads: [OpenThread]) -> UIImage {
    picture(ofPart: CarryoverCard(threads: threads, pick: { _ in }, dismiss: {}))
  }

  func failureLine(_ failure: StartFailure) -> UIImage {
    picture(
      ofPart: Text(failure.message)
        .font(Typography.caption)
        .foregroundStyle(Palette.accent)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32))
  }

  /// `screen` over the sky in a window the root view's size, as the root view shows one.
  func picture(ofScreen screen: some View) async -> UIImage {
    let (window, hosting) = Self.mount(
      ZStack {
        Palette.sky.ignoresSafeArea()
        screen
      })
    try? await Task.sleep(for: .milliseconds(200))
    let image = Self.draw(hosting.view)
    window.isHidden = true
    return image
  }

  /// `part` at the top of the sky at the root view's width, cut below its last drawn row, to
  /// find on a screen.
  func picture(ofPart part: some View) -> UIImage {
    let content = part.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Palette.sky)
    let hosting = UIHostingController(rootView: AnyView(content))
    hosting.safeAreaRegions = []
    let window = Self.window(CGRect(x: 0, y: 200, width: Self.frame.width, height: 400))
    window.rootViewController = hosting
    window.isHidden = false
    hosting.view.layoutIfNeeded()
    let image = Self.trimmed(Self.draw(hosting.view))
    window.isHidden = true
    return image
  }

  /// The image without the rows at its bottom that are only its top-left colour.
  static func trimmed(_ image: UIImage) -> UIImage {
    guard let drawn = pixels(image), let cgImage = image.cgImage else { return image }
    let rowBytes = drawn.width * 4
    let background = Array(drawn.bytes[0..<4])
    var last = drawn.height - 1
    while last > 0 {
      let row = drawn.bytes[(last * rowBytes)..<((last + 1) * rowBytes)]
      let blank = stride(from: row.startIndex, to: row.endIndex, by: 4).allSatisfy { start in
        (0..<4).allSatisfy { abs(Int(row[start + $0]) - Int(background[$0])) <= 2 }
      }
      if !blank { break }
      last -= 1
    }
    let kept = CGRect(x: 0, y: 0, width: drawn.width, height: min(last + 3, drawn.height))
    return cgImage.cropping(to: kept).map { UIImage(cgImage: $0, scale: 2, orientation: .up) }
      ?? image
  }

  /// A window on the host app's scene, so it draws and keeps drawing like the app's own.
  static func window(_ frame: CGRect) -> UIWindow {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: frame)
    window.frame = frame
    return window
  }

  static func mount(_ view: some View) -> (UIWindow, UIHostingController<AnyView>) {
    let hosting = UIHostingController(rootView: AnyView(view))
    let window = window(frame)
    window.rootViewController = hosting
    window.isHidden = false
    hosting.view.layoutIfNeeded()
    return (window, hosting)
  }

  /// Rasterizes the layer tree at 2x, the way the snapshot suites draw a view.
  static func draw(_ view: UIView) -> UIImage {
    view.setNeedsLayout()
    view.layoutIfNeeded()
    CATransaction.flush()
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
      view.layer.render(in: context.cgContext)
    }
  }

  /// The image as 8-bit sRGB rows, whatever format it was drawn in.
  static func pixels(_ image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
    guard let cgImage = image.cgImage else { return nil }
    let width = cgImage.width
    let height = cgImage.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue)
      else { return false }
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return drawn ? (bytes, width, height) : nil
  }

  /// True when every row of `part` appears in order in `whole`, at most two bytes in a thousand
  /// off by more than 24 levels. Text drawn in another window differs by a few levels at its
  /// edges; a different view, or another label on the same button, differs by far more.
  static func contains(_ whole: UIImage, _ part: UIImage) -> Bool {
    guard let whole = pixels(whole), let part = pixels(part), whole.width == part.width,
      part.height <= whole.height
    else { return false }
    let rowBytes = whole.width * 4
    let allowed = part.bytes.count / 500
    let anchor = busiestRow(part)
    func off(
      _ wholeRow: Int, _ partRow: Int, _ wholeBytes: UnsafeBufferPointer<UInt8>,
      _ partBytes: UnsafeBufferPointer<UInt8>
    ) -> Int {
      var off = 0
      for x in 0..<rowBytes
      where abs(Int(wholeBytes[wholeRow + x]) - Int(partBytes[partRow + x])) > 64 {
        off += 1
      }
      return off
    }
    return whole.bytes.withUnsafeBufferPointer { wholeBytes in
      part.bytes.withUnsafeBufferPointer { partBytes in
        for top in 0...(whole.height - part.height) {
          guard
            off((top + anchor) * rowBytes, anchor * rowBytes, wholeBytes, partBytes) <= rowBytes
              / 100
          else { continue }
          var total = 0
          var row = 0
          while row < part.height, total <= allowed {
            total += off((top + row) * rowBytes, row * rowBytes, wholeBytes, partBytes)
            row += 1
          }
          if total <= allowed { return true }
        }
        return false
      }
    }
  }

  /// The row that differs most from the image's top-left colour, which rules out a position
  /// on its own almost everywhere.
  static func busiestRow(_ image: (bytes: [UInt8], width: Int, height: Int)) -> Int {
    let rowBytes = image.width * 4
    let background = Array(image.bytes[0..<4])
    var busiest = (row: 0, weight: -1)
    for row in 0..<image.height {
      var weight = 0
      for x in 0..<rowBytes {
        weight += abs(Int(image.bytes[row * rowBytes + x]) - Int(background[x % 4]))
      }
      if weight > busiest.weight { busiest = (row, weight) }
    }
    return busiest.row
  }

}
