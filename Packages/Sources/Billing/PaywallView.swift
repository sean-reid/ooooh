import Design
import SwiftUI

/// The subscribe screen: one sentence, two plans, restore, the legal links, close.
public struct PaywallView<Header: View>: View {
  public var store: BillingStore
  public var onClose: () -> Void
  private let header: Header
  /// ImageRenderer draws a ScrollView empty, so snapshots render the content unscrolled.
  var scrolls = true
  @State private var failure: String?
  @State private var confirmed = false

  /// How long "You're subscribed." stays up before the sheet closes itself.
  static var confirmationDuration: Duration { .seconds(1.2) }
  static var confirmedLine: String { "You're subscribed." }

  /// Shown while the Worker refuses the transaction StoreKit holds; Restore posts it again.
  public static var unconfirmedLine: String {
    "Your subscription could not be confirmed with the server. Restore purchases to try again."
  }

  public static var privacyURL: URL { URL(string: "https://ooooh.app/privacy.html")! }
  public static var termsURL: URL { URL(string: "https://ooooh.app/terms.html")! }

  public init(
    store: BillingStore, onClose: @escaping () -> Void, @ViewBuilder header: () -> Header
  ) {
    self.store = store
    self.onClose = onClose
    self.header = header()
  }

  /// The sheet as it looks the moment after a purchase, for snapshots.
  init(store: BillingStore, confirmed: Bool, onClose: @escaping () -> Void)
  where Header == EmptyView {
    self.init(store: store, onClose: onClose)
    _confirmed = State(initialValue: confirmed)
    scrolls = false
  }

  public var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 0) {
        bar
        if confirmed {
          confirmation
        } else if scrolls {
          ScrollView { content }
        } else {
          GeometryReader { _ in content.fixedSize(horizontal: false, vertical: true) }.clipped()
        }
      }
    }
  }

  private var confirmation: some View {
    VStack(alignment: .leading, spacing: 24) {
      header
      Text(Self.confirmedLine)
        .font(Typography.display)
        .foregroundStyle(Palette.ink)
        .accessibilityAddTraits(.isHeader)
      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.bottom, 48)
    .transition(.opacity)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 24) {
      header
      Text("Keep talking.")
        .font(Typography.display)
        .foregroundStyle(Palette.ink)
        .accessibilityAddTraits(.isHeader)
      Text("A subscription is unlimited sessions and every prompt.")
        .font(Typography.body)
        .foregroundStyle(Palette.ink)
      VStack(alignment: .leading, spacing: 12) {
        if !store.plans.isEmpty {
          ForEach(store.plans) { plan in
            PlanButton(plan: plan, disabled: store.isPurchasing) { buy(plan.id) }
          }
        } else if store.hasLoadedPlans {
          noPlans
        } else {
          loadingPlans
        }
      }
      .padding(.top, 8)
      if let line = failure ?? (store.isUnconfirmed ? Self.unconfirmedLine : nil) {
        Text(line)
          .font(Typography.caption)
          .foregroundStyle(Palette.accent)
      }
      Button {
        restore()
      } label: {
        Text("Restore purchases").tapTarget(alignment: .leading)
      }
      .font(Typography.body)
      .foregroundStyle(Palette.accent)
      .disabled(store.isPurchasing)
      HStack(spacing: 24) {
        Link(destination: Self.privacyURL) { Text("Privacy").tapTarget(alignment: .leading) }
          .accessibilityLabel("Privacy policy")
        Link(destination: Self.termsURL) { Text("Terms").tapTarget(alignment: .leading) }
          .accessibilityLabel("Terms of use")
      }
      .font(Typography.caption)
      .foregroundStyle(Palette.inkDim)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.bottom, 48)
  }

  private var noPlans: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("The plans couldn't be loaded.")
        .font(Typography.body)
        .foregroundStyle(Palette.ink)
      Button {
        reload()
      } label: {
        Text("Try again").tapTarget(alignment: .leading)
      }
      .font(Typography.body)
      .foregroundStyle(Palette.accent)
    }
  }

  /// Two cards the size of the plan buttons, so the sheet keeps its height when the plans arrive.
  private var loadingPlans: some View {
    VStack(spacing: 12) {
      PlanButton(plan: Plan(id: .monthly, price: "$0.00"), disabled: true) {}
      PlanButton(plan: Plan(id: .yearly, price: "$00.00", perMonth: "$0.00"), disabled: true) {}
    }
    .redacted(reason: .placeholder)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading the plans")
  }

  private var bar: some View {
    HStack {
      Spacer()
      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.body.weight(.medium))
          .tapTarget()
      }
      .accessibilityLabel("Close")
    }
    .foregroundStyle(Palette.accent)
    .padding(.horizontal, 12)
    .padding(.top, 4)
  }

  private func buy(_ id: ProductID) {
    Task { await finish { try await store.purchase(id) } }
  }

  private func restore() {
    Task { await finish { try await store.restore() } }
  }

  private func reload() {
    Task { try? await store.load() }
  }

  /// A paid answer shows the confirmation, then closes the sheet on its own.
  private func finish(_ action: () async throws -> Entitlement) async {
    do {
      failure = nil
      let entitlement = try await action()
      guard entitlement.isPaid, !store.isUnconfirmed else { return }
      withAnimation { confirmed = true }
      AccessibilityNotification.Announcement(Self.confirmedLine).post()
      try? await Task.sleep(for: Self.confirmationDuration)
      onClose()
    } catch {
      failure = error.localizedDescription
    }
  }
}

extension PaywallView where Header == EmptyView {
  public init(store: BillingStore, onClose: @escaping () -> Void) {
    self.init(store: store, onClose: onClose) { EmptyView() }
  }
}

struct PlanButton: View {
  var plan: Plan
  var disabled: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 4) {
        Text(plan.name)
          .font(Typography.title)
        Text("\(plan.price) \(plan.period)")
          .font(Typography.body)
        if let perMonth = plan.perMonth {
          Text("\(perMonth) a month")
            .font(Typography.caption)
            .foregroundStyle(Palette.inkDim)
        }
      }
      .foregroundStyle(Palette.ink)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .background(Palette.skyRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityLabel("\(plan.name), \(plan.priceLine)")
    .accessibilityHint("Subscribes")
  }
}
